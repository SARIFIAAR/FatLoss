import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

/// Remote-driven meal-program catalog for the Nutrition tab.
///
/// Source of truth is Firestore (`mealPrograms/{id}` + a `recipes` subcollection, published and seeded
/// only by the Admin SDK — see `firestore.rules`; clients read as any signed-in user, never write). This
/// means new programs/recipes appear with NO app build.
///
/// Data flow (honest about what's on screen):
///   1. On init, load the on-disk cache so the Program tab renders INSTANTLY and works offline.
///   2. If there's no cache, fall back to the bundled `MealProgram.ariana` (+ bundled images) so a
///      first-run-offline user still sees a program.
///   3. On launch / Nutrition-tab appear, fetch `published == true` programs (ordered by `order`) and
///      each program's `published` recipes, map into the existing `MealProgram` types, refresh the
///      cache, and publish — remote supersedes the seed/cache the moment it lands.
///
/// Fetch uses the Firestore SDK (same auth the app already uses in `CloudSync`/`CloudMirror`: the signed
/// in user's token is carried by the SDK; rules allow any authed read of `mealPrograms`). A
/// permission-denied / offline / signed-out fetch is non-fatal: the cache (or the seed) stays on screen.
///
/// Shared schema (also written in `MealProgram.swift` for the Android port):
///   mealPrograms/{id}: name, blurb, bannerImageUrl, order:Int, published:Bool, updatedAt:Timestamp
///   …/recipes/{id}:    title, category(breakfast|lunch|dinner), imageUrl, serves:Int, timeMin:Int,
///                      type, ingredients:[String], method:[String],
///                      nutrition{kcal,protein,carbs,fat,fibre,sugar}, note, order:Int, published:Bool
@Observable
final class ContentService {
    /// Programs currently shown in the Nutrition tab. Never empty: seeds with the bundled Ariana program
    /// until a cache or remote fetch replaces it.
    private(set) var programs: [MealProgram]

    /// Observable status for debugging / future UI ("Updated …"). Not shown as a hard error — a failed
    /// refresh silently keeps the cached/seed content (unknown ≠ wrong data on screen).
    private(set) var lastError: String?
    private(set) var isLoading = false
    /// True once a remote fetch has successfully replaced the seed/cache this run.
    private(set) var loadedRemote = false

    private let cacheURL: URL
    private var fetchTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("meal-programs.json")

        // 1. cache → 2. bundled seed. Remote (step 3) lands later via refresh().
        if let cached = Self.loadCache(cacheURL), !cached.isEmpty {
            programs = cached
        } else {
            programs = [.ariana]
        }
    }

    // MARK: Remote fetch

    /// Fetch published programs + their published recipes, then publish + cache. Non-fatal on failure.
    /// Safe to call on launch and on every Nutrition-tab appear (coalesces in-flight fetches).
    @MainActor
    func refresh() {
        guard Self.firestoreConfigured else { return }        // no GoogleService-Info → stay on seed/cache
        guard fetchTask == nil else { return }
        isLoading = true
        fetchTask = Task { @MainActor [weak self] in
            await self?.fetch()
            self?.fetchTask = nil
            self?.isLoading = false
        }
    }

    @MainActor
    private func fetch() async {
        let db = Firestore.firestore()
        do {
            let progSnap = try await db.collection("mealPrograms")
                .whereField("published", isEqualTo: true)
                .order(by: "order")
                .getDocuments()

            var result: [MealProgram] = []
            for doc in progSnap.documents {
                let recSnap = try await doc.reference.collection("recipes")
                    .whereField("published", isEqualTo: true)
                    .order(by: "order")
                    .getDocuments()
                let recipes = recSnap.documents.compactMap { Self.recipe(from: $0.documentID, $0.data()) }
                if let program = Self.program(from: doc.documentID, doc.data(), recipes: recipes) {
                    result.append(program)
                }
            }

            guard !result.isEmpty else {
                // A successful fetch that returned nothing published → keep the seed/cache rather than
                // showing an empty tab. (Treated like a soft miss, not an error.)
                lastError = nil
                return
            }
            programs = result
            loadedRemote = true
            lastError = nil
            saveCache(result)
        } catch {
            // Offline, permission-denied, signed-out, etc. — keep whatever is already on screen.
            lastError = error.localizedDescription
        }
    }

    // MARK: Mapping (Firestore map → existing MealProgram types)

    static func program(from id: String, _ data: [String: Any], recipes: [MealProgram.Recipe]) -> MealProgram? {
        guard let name = data["name"] as? String, !name.isEmpty else { return nil }
        let blurb = data["blurb"] as? String ?? ""
        let banner = (data["bannerImageUrl"] as? String)?.nilIfEmpty
        return MealProgram(id: id, name: name, blurb: blurb,
                           bannerImageURL: banner,
                           bannerImageName: "ariana-banner",   // bundled banner fallback if the URL fails
                           recipes: recipes)
    }

    static func recipe(from id: String, _ data: [String: Any]) -> MealProgram.Recipe? {
        guard let title = (data["title"] as? String)?.nilIfEmpty,
              let category = MealCategory(rawValue: (data["category"] as? String ?? "").lowercased())
        else { return nil }
        let n = data["nutrition"] as? [String: Any] ?? [:]
        func d(_ k: String) -> Double {
            if let v = n[k] as? Double { return v }
            if let v = n[k] as? Int { return Double(v) }
            if let v = n[k] as? NSNumber { return v.doubleValue }
            return 0
        }
        let nutrition = MealProgram.Nutrition(
            kcal: d("kcal"), protein: d("protein"), carbs: d("carbs"),
            fat: d("fat"), fibre: d("fibre"), sugar: d("sugar"))
        return MealProgram.Recipe(
            id: id,
            title: title,
            category: category,
            imageName: "ariana-banner",                        // generic bundled fallback for remote recipes
            imageURL: (data["imageUrl"] as? String)?.nilIfEmpty,
            serves: (data["serves"] as? Int) ?? (data["serves"] as? NSNumber)?.intValue ?? 1,
            timeMin: (data["timeMin"] as? Int) ?? (data["timeMin"] as? NSNumber)?.intValue ?? 0,
            type: data["type"] as? String ?? "",
            ingredients: data["ingredients"] as? [String] ?? [],
            method: data["method"] as? [String] ?? [],
            nutrition: nutrition,
            note: data["note"] as? String ?? "")
    }

    // MARK: Cache (JSON in Application Support)

    private static func loadCache(_ url: URL) -> [MealProgram]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([MealProgram].self, from: data)
    }

    private func saveCache(_ programs: [MealProgram]) {
        if let data = try? JSONEncoder().encode(programs) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    /// Whether Firebase is configured (mirrors `CloudSync`'s guard — the app runs fine without it).
    private static var firestoreConfigured: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    // MARK: Debug / QA

    /// `-contentSeedOnly 1` forces the bundled seed (skips remote) so screenshots/tests are deterministic
    /// and the offline-fallback path can be exercised in the simulator without touching the network.
    var seedOnly: Bool { UserDefaults.standard.bool(forKey: "contentSeedOnly") }
}
