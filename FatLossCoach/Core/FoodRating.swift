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

    /// Score a meal from its macros. When fibre / sugar / sodium / sat-fat are known, they refine
    /// the grade (6-signal), otherwise it falls back to the 3-signal macro heuristic.
    static func grade(kcal: Double, protein: Double, carbs: Double, fat: Double,
                      fibre: Double? = nil, sugar: Double? = nil, sodium: Double? = nil, satFat: Double? = nil) -> Grade? {
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

        // Extra nutrients, scored per 100 kcal (only when the data is present).
        let per100 = kcal / 100
        if let fibre, per100 > 0 {                    // fibre is good
            let f = fibre / per100
            if f >= 3 { score += 1 } else if f >= 1.5 { score += 0.5 }
        }
        if let sugar, per100 > 0 {                    // added/total sugar is bad
            let s = sugar / per100
            if s >= 12 { score -= 1 } else if s >= 6 { score -= 0.5 }
        }
        if let sodium, per100 > 0 {                   // sodium mg per 100 kcal
            let na = sodium / per100
            if na >= 400 { score -= 1 } else if na >= 250 { score -= 0.5 }
        }
        if let satFat, per100 > 0 {                   // saturated fat is bad
            let sf = satFat / per100
            if sf >= 5 { score -= 1 } else if sf >= 3 { score -= 0.5 }
        }

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

/// Aggregate daily diet-quality score (0–100), Lifesum "Life Score" analogue. Combines the average
/// food grade of the day's meals with how well the day's macros + calories hit target.
enum LifeScore {
    static func score(meals: [MealEntry], goals: Goals) -> Int? {
        guard !meals.isEmpty else { return nil }
        // 1) Average food grade (A=100 … E=20), weighted by calories.
        let gradeVal: [FoodRating.Grade: Double] = [.a: 100, .b: 82, .c: 64, .d: 45, .e: 25]
        var wSum = 0.0, w = 0.0
        for m in meals {
            guard let g = FoodRating.grade(kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat) else { continue }
            let weight = max(1, m.kcal)
            wSum += (gradeVal[g] ?? 60) * weight; w += weight
        }
        let quality = w > 0 ? wSum / w : 60

        let totals = meals.reduce(into: (kcal: 0.0, p: 0.0)) { $0.kcal += $1.kcal; $0.p += $1.protein }
        // 2) Calorie adherence — best near target, penalise big over/under.
        let kcalRatio = goals.kcal > 0 ? totals.kcal / Double(goals.kcal) : 1
        let calAdh = max(0, 100 - abs(kcalRatio - 1) * 140)
        // 3) Protein adherence — reward hitting protein.
        let protRatio = goals.protein > 0 ? min(1.2, totals.p / Double(goals.protein)) : 1
        let protAdh = min(100, protRatio * 100)

        let final = quality * 0.55 + calAdh * 0.25 + protAdh * 0.20
        return max(0, min(100, Int(final.rounded())))
    }

    static func color(_ s: Int) -> Color {
        s >= 80 ? Color(hex: 0x43CB00) : s >= 60 ? Color(hex: 0xF0C930) : s >= 40 ? Color(hex: 0xF0A030) : Color(hex: 0xFF3B30)
    }
    static func label(_ s: Int) -> String {
        s >= 80 ? "Excellent" : s >= 60 ? "Good" : s >= 40 ? "Fair" : "Needs work"
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
