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
                      items: items.map { FoodItem(name: $0.name, portion: $0.portion, grams: $0.grams, kcal: $0.kcal,
                                                  protein: $0.protein_g, carbs: $0.carbs_g, fat: $0.fat_g) },
                      confidence: confidence, notes: notes.isEmpty ? nil : notes)
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
