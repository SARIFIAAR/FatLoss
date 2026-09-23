import Foundation
import Observation
import FirebaseAuth

/// Nutrition-database lookups through the analyzer service: USDA FoodData Central by name, and
/// Open Food Facts / USDA Branded by barcode. Results are per 100 g plus household portions.
@Observable
final class FoodSearch {
    struct Macros: Codable, Hashable {
        var kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0
        var fibre: Double = 0, sugar: Double = 0, sodium: Double = 0, satFat: Double = 0   // per unit; sodium in mg
        func scaled(_ factor: Double) -> Macros {
            Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
                   fibre: fibre * factor, sugar: sugar * factor, sodium: sodium * factor, satFat: satFat * factor)
        }
        static func + (a: Macros, b: Macros) -> Macros {
            Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat,
                   fibre: a.fibre + b.fibre, sugar: a.sugar + b.sugar, sodium: a.sodium + b.sodium, satFat: a.satFat + b.satFat)
        }
        init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
             fibre: Double = 0, sugar: Double = 0, sodium: Double = 0, satFat: Double = 0) {
            self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
            self.fibre = fibre; self.sugar = sugar; self.sodium = sodium; self.satFat = satFat
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kcal = (try? c.decode(Double.self, forKey: .kcal)) ?? 0
            protein = (try? c.decode(Double.self, forKey: .protein)) ?? 0
            carbs = (try? c.decode(Double.self, forKey: .carbs)) ?? 0
            fat = (try? c.decode(Double.self, forKey: .fat)) ?? 0
            fibre = (try? c.decode(Double.self, forKey: .fibre)) ?? 0
            sugar = (try? c.decode(Double.self, forKey: .sugar)) ?? 0
            sodium = (try? c.decode(Double.self, forKey: .sodium)) ?? 0
            satFat = (try? c.decode(Double.self, forKey: .satFat)) ?? 0
        }
    }
    struct Serving: Codable, Hashable, Identifiable {
        var label: String
        var grams: Double
        var id: String { label }
    }
    struct Food: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var brand: String?
        var kind: String            // generic / branded
        var category: String?
        var per100: Macros
        var servings: [Serving]
        var barcode: String?

        var subtitle: String {
            if let brand, !brand.isEmpty { return brand }
            return category ?? "Generic"
        }

        enum CodingKeys: String, CodingKey { case id, name, brand, kind, category, per100, servings, barcode }
        init(id: String, name: String, brand: String?, kind: String, category: String?,
             per100: Macros, servings: [Serving], barcode: String?) {
            self.id = id; self.name = name; self.brand = brand; self.kind = kind
            self.category = category; self.per100 = per100; self.servings = servings; self.barcode = barcode
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) } else { id = try c.decode(String.self, forKey: .id) }
            name = try c.decode(String.self, forKey: .name)
            brand = try c.decodeIfPresent(String.self, forKey: .brand)
            kind = try c.decode(String.self, forKey: .kind)
            category = try c.decodeIfPresent(String.self, forKey: .category)
            per100 = try c.decode(Macros.self, forKey: .per100)
            servings = try c.decodeIfPresent([Serving].self, forKey: .servings) ?? []
            barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        }
    }

    var isSearching = false

    static let base = URL(string: "https://fatloss-analyzer.fly.dev")!

    func search(_ query: String) async throws -> [Food] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        isSearching = true
        defer { isSearching = false }
        struct Reply: Decodable { let foods: [Food] }
        let data = try await get("/foods", query: [URLQueryItem(name: "q", value: q)])
        return try JSONDecoder().decode(Reply.self, from: data).foods
    }

    func barcode(_ code: String) async throws -> Food {
        isSearching = true
        defer { isSearching = false }
        struct Reply: Decodable { let food: Food }
        let data = try await get("/barcode", query: [URLQueryItem(name: "code", value: code)])
        return try JSONDecoder().decode(Reply.self, from: data).food
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        guard let user = Auth.auth().currentUser else { throw MealScanner.ScanError.notSignedIn }
        let token = try await user.getIDToken()
        var comps = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MealScanner.ScanError.server("No connection — check your internet and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw MealScanner.ScanError.server(msg ?? "Food database error (\(status)).")
        }
        return data
    }
}
