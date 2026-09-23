import Foundation
import Observation
import UIKit
import FirebaseAuth

/// Sends a meal photo (or a written description) to the analyzer service on Fly.io (Claude) and returns items + macros.
/// The request carries the user's Firebase ID token; the server verifies it before calling the model.
@Observable
final class MealScanner {
    struct Analysis: Decodable {
        struct Item: Decodable {
            let name: String
            let portion: String
            let grams: Double
            let kcal: Double
            let protein_g: Double
            let carbs_g: Double
            let fat_g: Double

            init(name: String, portion: String, grams: Double, kcal: Double,
                 protein_g: Double, carbs_g: Double, fat_g: Double) {
                self.name = name; self.portion = portion; self.grams = grams; self.kcal = kcal
                self.protein_g = protein_g; self.carbs_g = carbs_g; self.fat_g = fat_g
            }
        }
        let is_food: Bool
        let meal_name: String
        let items: [Item]
        let total_kcal: Double
        let total_protein_g: Double
        let total_carbs_g: Double
        let total_fat_g: Double
        let confidence: String
        let notes: String

        func mealEntry(date: String) -> MealEntry {
            MealEntry(date: date, name: meal_name,
                      kcal: total_kcal, protein: total_protein_g, carbs: total_carbs_g, fat: total_fat_g,
                      fibre: fibre_g, sugar: sugar_g, sodium: sodium_mg, satFat: sat_fat_g,
                      items: items.map { FoodItem(name: $0.name, portion: $0.portion, grams: $0.grams, kcal: $0.kcal,
                                                  protein: $0.protein_g, carbs: $0.carbs_g, fat: $0.fat_g) },
                      confidence: confidence, notes: notes.isEmpty ? nil : notes)
        }

        // Optional micros — decoded when the model/back-end supplies them, carried into the MealEntry
        // so the meal-level rating can use fibre/sugar/sodium/sat-fat. Nil when unknown (unknown ≠ zero).
        var fibre_g: Double? = nil
        var sugar_g: Double? = nil
        var sodium_mg: Double? = nil
        var sat_fat_g: Double? = nil

        enum CodingKeys: String, CodingKey {
            case is_food, meal_name, items, total_kcal, total_protein_g, total_carbs_g, total_fat_g,
                 confidence, notes, fibre_g, sugar_g, sodium_mg, sat_fat_g
        }

        // Memberwise init so a barcode product (or a test) can build an Analysis directly.
        init(is_food: Bool, meal_name: String, items: [Item], total_kcal: Double, total_protein_g: Double,
             total_carbs_g: Double, total_fat_g: Double, confidence: String, notes: String,
             fibre_g: Double? = nil, sugar_g: Double? = nil, sodium_mg: Double? = nil, sat_fat_g: Double? = nil) {
            self.is_food = is_food; self.meal_name = meal_name; self.items = items
            self.total_kcal = total_kcal; self.total_protein_g = total_protein_g
            self.total_carbs_g = total_carbs_g; self.total_fat_g = total_fat_g
            self.confidence = confidence; self.notes = notes
            self.fibre_g = fibre_g; self.sugar_g = sugar_g; self.sodium_mg = sodium_mg; self.sat_fat_g = sat_fat_g
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            is_food = (try? c.decode(Bool.self, forKey: .is_food)) ?? true
            meal_name = (try? c.decode(String.self, forKey: .meal_name)) ?? "Meal"
            items = (try? c.decode([Item].self, forKey: .items)) ?? []
            total_kcal = (try? c.decode(Double.self, forKey: .total_kcal)) ?? 0
            total_protein_g = (try? c.decode(Double.self, forKey: .total_protein_g)) ?? 0
            total_carbs_g = (try? c.decode(Double.self, forKey: .total_carbs_g)) ?? 0
            total_fat_g = (try? c.decode(Double.self, forKey: .total_fat_g)) ?? 0
            confidence = (try? c.decode(String.self, forKey: .confidence)) ?? "medium"
            notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
            fibre_g = try? c.decodeIfPresent(Double.self, forKey: .fibre_g)
            sugar_g = try? c.decodeIfPresent(Double.self, forKey: .sugar_g)
            sodium_mg = try? c.decodeIfPresent(Double.self, forKey: .sodium_mg)
            sat_fat_g = try? c.decodeIfPresent(Double.self, forKey: .sat_fat_g)
        }

        /// Build an editable estimate from a scanned barcode product. One serving = 100 g by default
        /// (the user confirms/adjusts the portion on the same result screen). Micros carry through so
        /// the meal rating is as accurate as the packaging data allows.
        static func fromBarcode(_ food: FoodSearch.Food) -> Analysis {
            let m = food.per100   // per 100 g
            let name = food.brand.map { "\($0) \(food.name)" } ?? food.name
            let item = Item(name: food.name, portion: "100 g", grams: 100,
                            kcal: m.kcal, protein_g: m.protein, carbs_g: m.carbs, fat_g: m.fat)
            return Analysis(is_food: true, meal_name: name, items: [item],
                            total_kcal: m.kcal, total_protein_g: m.protein, total_carbs_g: m.carbs,
                            total_fat_g: m.fat, confidence: "high",
                            notes: "From the product barcode (per 100 g). Adjust the portion to match what you ate.",
                            fibre_g: m.fibre > 0 ? m.fibre : nil, sugar_g: m.sugar > 0 ? m.sugar : nil,
                            sodium_mg: m.sodium > 0 ? m.sodium : nil, sat_fat_g: m.satFat > 0 ? m.satFat : nil)
        }
    }

    enum ScanError: LocalizedError {
        case notSignedIn, badImage, notFood, server(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in with Apple (Profile tab) to use meal scanning."
            case .badImage: return "Couldn't read that photo."
            case .notFood: return "That doesn't look like food. Try again."
            case .server(let m): return m
            }
        }
    }

    var isAnalyzing = false

    static let endpoint = URL(string: "https://fatloss-analyzer.fly.dev/analyze")!

    var isAvailable: Bool { Auth.auth().currentUser != nil }

    /// Sent with each scan so the dietitian prompt uses this user's numbers (not a hard-coded profile).
    struct Context: Encodable {
        var kcalTarget: Int
        var proteinTarget: Int
        var currentWeightKg: Double?
        var goalWeightKg: Double
        var slot: String?
    }

    // MARK: InBody / body-composition report scanning

    struct BodyReport: Decodable {
        let is_report: Bool
        let weight_kg: Double
        let body_fat_pct: Double
        let fat_mass_kg: Double
        let skeletal_muscle_kg: Double
        let visceral_fat: Double
        let bmr_kcal: Double
        let confidence: String
        let notes: String

        func entry(date: String) -> BodyCompEntry {
            func z(_ v: Double) -> Double? { v > 0 ? v : nil }
            return BodyCompEntry(date: date, weightKg: weight_kg, bodyFatPct: z(body_fat_pct),
                                 fatMassKg: z(fat_mass_kg), muscleKg: z(skeletal_muscle_kg),
                                 visceralFat: z(visceral_fat), bmr: z(bmr_kcal), source: "inbody")
        }
    }

    static let inbodyEndpoint = URL(string: "https://fatloss-analyzer.fly.dev/inbody")!

    /// Photograph an InBody/Tanita/scale report → parsed body-composition numbers.
    func analyzeInBody(_ image: UIImage) async throws -> BodyReport {
        guard let user = Auth.auth().currentUser else { throw ScanError.notSignedIn }
        guard let jpeg = Self.downscaledJPEG(image, maxSide: 1400) else { throw ScanError.badImage }
        isAnalyzing = true
        defer { isAnalyzing = false }
        let token = try await user.getIDToken()
        var request = URLRequest(url: Self.inbodyEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject:
            ["image": jpeg.base64EncodedString(), "mediaType": "image/jpeg"])
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ScanError.server("No connection — check your internet and try again.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw ScanError.server(msg ?? "Analyzer error (\(status)).")
        }
        let report = try JSONDecoder().decode(BodyReport.self, from: data)
        guard report.is_report, report.weight_kg > 0 else {
            throw ScanError.server("That doesn't look like a body-composition report.")
        }
        return report
    }

    func analyze(_ image: UIImage, hint: String? = nil, context: Context? = nil) async throws -> Analysis {
        guard let jpeg = Self.downscaledJPEG(image) else { throw ScanError.badImage }
        return try await post(["image": jpeg.base64EncodedString(), "mediaType": "image/jpeg"], hint: hint, context: context)
    }

    /// Estimate from a typed description ("2 eggs, toast with butter, black coffee") — no photo.
    func analyze(text: String, hint: String? = nil, context: Context? = nil) async throws -> Analysis {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw ScanError.notFood }
        return try await post(["text": t], hint: hint, context: context)
    }

    private func post(_ fields: [String: Any], hint: String?, context: Context?) async throws -> Analysis {
        guard let user = Auth.auth().currentUser else { throw ScanError.notSignedIn }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let token = try await user.getIDToken()
        var payload = fields
        if let hint, !hint.isEmpty { payload["hint"] = hint }
        if let context, let ctx = try? JSONEncoder().encode(context),
           let obj = try? JSONSerialization.jsonObject(with: ctx) { payload["context"] = obj }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ScanError.server("No connection — check your internet and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw ScanError.server(msg ?? "Analyzer error (\(status)).")
        }
        let analysis = try JSONDecoder().decode(Analysis.self, from: data)
        guard analysis.is_food, !analysis.items.isEmpty else { throw ScanError.notFood }
        return analysis
    }

    /// Longest side 1024 px, JPEG 0.8 — plenty for food recognition, small enough to upload fast.
    static func downscaledJPEG(_ image: UIImage, maxSide: CGFloat = 1024) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f
        }())
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
