import SwiftUI

/// Lifesum-style A–E food/meal quality grade, derived transparently from macros per 100 kcal.
/// Rewards protein and fibre-ish carb balance, penalises very fat- or sugar-dense calories.
/// This is a heuristic nutrition-quality hint, not medical advice.
enum FoodRating {
    enum Grade: String { case a = "A", b = "B", c = "C", d = "D", e = "E"
        var color: Color {
            switch self {
            case .a: Color(hex: 0x43CB00)   // green
            case .b: Color(hex: 0x9ACD32)   // light green
            case .c: Color(hex: 0xF0C930)   // yellow
            case .d: Color(hex: 0xF0A030)   // orange
            case .e: Color(hex: 0xFF3B30)   // red
            }
        }
    }

    /// Score a meal from its macros. Returns nil for trivial/zero-calorie entries.
    static func grade(kcal: Double, protein: Double, carbs: Double, fat: Double) -> Grade? {
        guard kcal >= 20 else { return nil }
        let proteinKcal = protein * 4
        let fatKcal = fat * 9
        let proteinPct = proteinKcal / kcal          // want higher
        let fatPct = fatKcal / kcal                  // very high = worse

        var score = 3.0                              // start at C
        // Protein density
        if proteinPct >= 0.35 { score += 2 }
        else if proteinPct >= 0.25 { score += 1 }
        else if proteinPct < 0.10 { score -= 1 }
        // Fat density
        if fatPct >= 0.55 { score -= 1.5 }
        else if fatPct >= 0.40 { score -= 0.5 }
        // Calorie density penalty (very high-cal single items)
        if kcal >= 700 { score -= 0.5 }
        // Reasonable protein floor bonus
        if protein >= 25 { score += 0.5 }

        let clamped = max(1, min(5, score.rounded()))
        switch clamped {
        case 5: return .a
        case 4: return .b
        case 3: return .c
        case 2: return .d
        default: return .e
        }
    }
}

/// Small circular A–E badge.
struct FoodRatingBadge: View {
    let grade: FoodRating.Grade
    var size: CGFloat = 22
    var body: some View {
        Text(grade.rawValue)
            .font(.system(size: size * 0.55, weight: .heavy))
            .foregroundStyle(Color(hex: 0x101518))
            .frame(width: size, height: size)
            .background(grade.color, in: Circle())
    }
}
