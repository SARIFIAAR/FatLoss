import Foundation
import Observation
import UIKit
import FirebaseAuth
import FirebaseFunctions

/// Sends a meal photo to the `analyzeMeal` Cloud Function (Claude vision) and returns items + macros.
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
            case .notFood: return "That doesn't look like food. Try another photo."
            case .server(let m): return m
            }
        }
    }

    var isAnalyzing = false

    private var functions: Functions { Functions.functions(region: "europe-west1") }

    var isAvailable: Bool { Auth.auth().currentUser != nil }

    func analyze(_ image: UIImage, hint: String? = nil) async throws -> Analysis {
        guard Auth.auth().currentUser != nil else { throw ScanError.notSignedIn }
        guard let jpeg = Self.downscaledJPEG(image) else { throw ScanError.badImage }
        isAnalyzing = true
        defer { isAnalyzing = false }

        var payload: [String: Any] = ["image": jpeg.base64EncodedString(), "mediaType": "image/jpeg"]
        if let hint, !hint.isEmpty { payload["hint"] = hint }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("analyzeMeal").call(payload)
        } catch {
            let ns = error as NSError
            let msg = (ns.userInfo[FunctionsErrorDetailsKey] as? String) ?? ns.localizedDescription
            throw ScanError.server(msg)
        }
        let data = try JSONSerialization.data(withJSONObject: result.data)
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
