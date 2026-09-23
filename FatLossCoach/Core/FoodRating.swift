import SwiftUI

// MARK: - Plan-aware, three-level food rating
//
// One transparent engine scores three levels — an individual food/item, a whole meal, and the day —
// using the SAME nutrient signals (protein / fat density / calorie density / fibre / sugar / sodium /
// sat-fat). The score is re-weighted by the user's ACTIVE diet plan, so the same food grades
// differently under, say, High Protein vs Keto vs Balanced. Every grade carries the drivers that
// produced it (see `Rating.drivers`) so nothing on screen is a black box.
//
// This is a heuristic nutrition-quality hint, not medical advice. Grades are relative to the chosen
// plan's emphasis, not a claim about health outcomes.

/// The nutrient inputs any level reduces to before scoring. Macros in grams, sodium in mg.
/// Optional micros refine the grade when known (packaged / scanned foods); absent = not counted.
struct NutrientProfile {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double? = nil
    var sugar: Double? = nil
    var sodium: Double? = nil
    var satFat: Double? = nil

    static let zero = NutrientProfile(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (a: NutrientProfile, b: NutrientProfile) -> NutrientProfile {
        func opt(_ x: Double?, _ y: Double?) -> Double? {
            if x == nil && y == nil { return nil }
            return (x ?? 0) + (y ?? 0)
        }
        return NutrientProfile(kcal: a.kcal + b.kcal, protein: a.protein + b.protein,
                               carbs: a.carbs + b.carbs, fat: a.fat + b.fat,
                               fibre: opt(a.fibre, b.fibre), sugar: opt(a.sugar, b.sugar),
                               sodium: opt(a.sodium, b.sodium), satFat: opt(a.satFat, b.satFat))
    }
}

/// How a plan re-weights the score drivers. 1.0 = the neutral (Balanced) weight; >1 amplifies that
/// driver's reward/penalty, <1 damps it. Kept as plain multipliers so the effect is auditable.
struct PlanWeighting {
    var protein = 1.0        // reward for protein density
    var fatDensity = 1.0     // penalty for very fat-dense calories (keto flips this to a reward)
    var carbDensity = 0.0    // penalty for very carb-dense calories (0 = ignored on most plans)
    var fibre = 1.0          // reward for fibre
    var sugar = 1.0          // penalty for sugar
    var sodium = 1.0         // penalty for sodium
    var satFat = 1.0         // penalty for saturated fat
    /// On very-low-carb plans, high fat is desirable rather than penalised.
    var fatIsFuel = false

    /// Derive a weighting from a diet program. Falls back to Balanced when no plan is active.
    static func from(programId: String?) -> PlanWeighting {
        switch programId {
        case "keto":
            // Fat is fuel; carbs and sugar are the thing to avoid; protein still valued, less than HP.
            return PlanWeighting(protein: 0.9, fatDensity: 1.0, carbDensity: 2.2, fibre: 1.0,
                                 sugar: 2.0, sodium: 1.0, satFat: 0.4, fatIsFuel: true)
        case "low_carb":
            return PlanWeighting(protein: 1.2, fatDensity: 0.7, carbDensity: 1.4, fibre: 1.1,
                                 sugar: 1.6, sodium: 1.0, satFat: 0.8, fatIsFuel: false)
        case "high_protein":
            return PlanWeighting(protein: 1.8, fatDensity: 1.0, carbDensity: 0.0, fibre: 1.0,
                                 sugar: 1.2, sodium: 1.0, satFat: 1.0)
        case "mediterranean":
            return PlanWeighting(protein: 1.0, fatDensity: 0.6, carbDensity: 0.0, fibre: 1.3,
                                 sugar: 1.3, sodium: 1.2, satFat: 1.4)
        case "clean_eating", "paleo":
            return PlanWeighting(protein: 1.1, fatDensity: 0.9, carbDensity: 0.0, fibre: 1.3,
                                 sugar: 1.6, sodium: 1.3, satFat: 1.1)
        case "plant_based":
            return PlanWeighting(protein: 1.3, fatDensity: 1.0, carbDensity: 0.0, fibre: 1.5,
                                 sugar: 1.2, sodium: 1.1, satFat: 1.2)
        case "fasting_168", "fasting_52", "balanced", nil:
            return PlanWeighting()   // neutral
        default:
            return PlanWeighting()
        }
    }
}

enum FoodRating {
    enum Grade: String, CaseIterable { case a = "A", b = "B", c = "C", d = "D", e = "E"
        var color: Color {
            switch self {
            case .a: Color(hex: 0x43CB00)   // green
            case .b: Color(hex: 0x9ACD32)   // light green
            case .c: Color(hex: 0xF0C930)   // yellow
            case .d: Color(hex: 0xF0A030)   // orange
            case .e: Color(hex: 0xFF3B30)   // red
            }
        }
        /// A–E from a clamped 1–5 score (5 = A … 1 = E).
        static func from(score: Double) -> Grade {
            switch Int(max(1, min(5, score.rounded()))) {
            case 5: return .a
            case 4: return .b
            case 3: return .c
            case 2: return .d
            default: return .e
            }
        }
    }

    /// One transparent reason the grade moved. `points` is the signed contribution to the 1–5 score.
    struct Driver: Identifiable {
        let label: String
        let points: Double
        var id: String { label }
        var positive: Bool { points >= 0 }
    }

    /// The full result of scoring a profile under a plan: the A–E grade, a 0–100 numeric for bars,
    /// and the drivers that produced it.
    struct Rating {
        let grade: Grade
        let score100: Int          // 0–100, for progress bars and the day/Life-Score blend
        let drivers: [Driver]      // strongest first
        let planId: String?        // the plan the score was weighted by (for the "under <plan>" caption)
    }

    /// Score any nutrient profile under a plan weighting. Returns nil for negligible items (<20 kcal).
    /// Starts at C (3.0) and moves by weighted signals; the same profile grades differently per plan.
    static func rate(_ p: NutrientProfile, plan: PlanWeighting, planId: String?) -> Rating? {
        guard p.kcal >= 20 else { return nil }
        let proteinKcal = p.protein * 4
        let fatKcal = p.fat * 9
        let carbKcal = p.carbs * 4
        let proteinPct = proteinKcal / p.kcal
        let fatPct = fatKcal / p.kcal
        let carbPct = carbKcal / p.kcal

        var score = 3.0
        var drivers: [Driver] = []
        func add(_ label: String, _ raw: Double, weight: Double) {
            let pts = raw * weight
            guard abs(pts) >= 0.15 else { return }   // hide negligible drivers from the explanation
            score += pts
            drivers.append(Driver(label: label, points: pts))
        }

        // Protein density — rewarded on every plan, amplified on high-protein.
        if proteinPct >= 0.35 { add("High protein density", 2.0, weight: plan.protein) }
        else if proteinPct >= 0.25 { add("Good protein density", 1.0, weight: plan.protein) }
        else if proteinPct < 0.10 { add("Low protein", -1.0, weight: plan.protein) }
        if p.protein >= 25 { add("Protein ≥ 25 g", 0.5, weight: plan.protein) }

        // Fat density — a penalty on most plans, but FUEL on keto (sign flips).
        if plan.fatIsFuel {
            if fatPct >= 0.60 { add("Fat-fuelled (fits keto)", 1.2, weight: plan.fatDensity) }
            else if fatPct >= 0.40 { add("Moderate fat", 0.4, weight: plan.fatDensity) }
            else if fatPct < 0.20 { add("Low fat for keto", -0.8, weight: plan.fatDensity) }
        } else {
            if fatPct >= 0.55 { add("Very fat-dense", -1.5, weight: plan.fatDensity) }
            else if fatPct >= 0.40 { add("Fat-dense", -0.5, weight: plan.fatDensity) }
        }

        // Carb density — only counts on carb-controlled plans (weight 0 elsewhere).
        if plan.carbDensity > 0 {
            if carbPct >= 0.55 { add("Very carb-dense", -1.4, weight: plan.carbDensity) }
            else if carbPct >= 0.40 { add("Carb-dense", -0.6, weight: plan.carbDensity) }
            else if carbPct < 0.15 { add("Low carb", 0.5, weight: plan.carbDensity) }
        }

        // Calorie-density penalty for very high-cal single items (plan-independent).
        if p.kcal >= 700 { add("Calorie-dense", -0.5, weight: 1.0) }

        // Micro-nutrient signals, scored per 100 kcal (only when the data is present).
        let per100 = p.kcal / 100
        if let fibre = p.fibre, per100 > 0 {
            let f = fibre / per100
            if f >= 3 { add("Good fibre", 1.0, weight: plan.fibre) }
            else if f >= 1.5 { add("Some fibre", 0.5, weight: plan.fibre) }
        }
        if let sugar = p.sugar, per100 > 0 {
            let s = sugar / per100
            if s >= 12 { add("High sugar", -1.0, weight: plan.sugar) }
            else if s >= 6 { add("Sugary", -0.5, weight: plan.sugar) }
        }
        if let sodium = p.sodium, per100 > 0 {
            let na = sodium / per100
            if na >= 400 { add("High sodium", -1.0, weight: plan.sodium) }
            else if na >= 250 { add("Salty", -0.5, weight: plan.sodium) }
        }
        if let satFat = p.satFat, per100 > 0 {
            let sf = satFat / per100
            if sf >= 5 { add("High saturated fat", -1.0, weight: plan.satFat) }
            else if sf >= 3 { add("Some saturated fat", -0.5, weight: plan.satFat) }
        }

        let clamped = max(1, min(5, score))
        let grade = Grade.from(score: clamped)
        // 0–100 numeric: map the 1–5 continuous score linearly (1→20 … 5→100).
        let score100 = Int((clamped * 20).rounded())
        drivers.sort { abs($0.points) > abs($1.points) }
        return Rating(grade: grade, score100: score100, drivers: drivers, planId: planId)
    }

    // MARK: Level 1 — a single food / item

    static func rate(item: FoodItem, planId: String?) -> Rating? {
        rate(NutrientProfile(kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat),
             plan: .from(programId: planId), planId: planId)
    }

    // MARK: Level 2 — a whole meal (aggregate of its items + any known micros)

    /// A meal's grade uses the meal totals AND, when the meal has multiple items, a small penalty for a
    /// lopsided calorie distribution (one item dominating), so "balanced meal" beats "one calorie bomb".
    static func rate(meal: MealEntry, planId: String?) -> Rating? {
        let profile = NutrientProfile(kcal: meal.kcal, protein: meal.protein, carbs: meal.carbs,
                                      fat: meal.fat, fibre: meal.fibre, sugar: meal.sugar,
                                      sodium: meal.sodium, satFat: meal.satFat)
        guard var r = rate(profile, plan: .from(programId: planId), planId: planId) else { return nil }
        // Distribution factor: only meaningful with ≥2 items and non-trivial calories.
        if meal.items.count >= 2, meal.kcal > 0 {
            let share = meal.items.map { $0.kcal / meal.kcal }
            let hhi = share.reduce(0) { $0 + $1 * $1 }     // Herfindahl concentration, 0…1
            if hhi >= 0.7 {
                let drivers = r.drivers + [Driver(label: "One item dominates the meal", points: -0.3)]
                let grade = Grade.from(score: Double(r.score100) / 20 - 0.3)
                r = Rating(grade: grade, score100: max(0, r.score100 - 6),
                           drivers: drivers.sorted { abs($0.points) > abs($1.points) }, planId: planId)
            }
        }
        return r
    }

    // MARK: Level 3 — the whole day (plan-aware, reconciled with the Life Score)

    /// The day's diet-quality grade. It reuses the SAME plan-weighted engine over the day's totals so
    /// item, meal and day all speak the same language. The 0–100 numeric here is the "quality" pillar
    /// that `LifeScore` blends with calorie + protein adherence — the day badge and the Life Score are
    /// two faces of one calculation, never two independent scores.
    static func rateDay(meals: [MealEntry], planId: String?) -> Rating? {
        guard !meals.isEmpty else { return nil }
        var profile = NutrientProfile.zero
        for m in meals { profile = profile + NutrientProfile(kcal: m.kcal, protein: m.protein,
                                                             carbs: m.carbs, fat: m.fat,
                                                             fibre: m.fibre, sugar: m.sugar,
                                                             sodium: m.sodium, satFat: m.satFat) }
        return rate(profile, plan: .from(programId: planId), planId: planId)
    }
}

/// The 0–100 daily diet-quality score shown on the diary ("Life Score"). It now blends the PLAN-AWARE
/// day quality grade with how well the day's calories + protein hit target — so switching plan moves
/// the Life Score too. Same public API as before (score / color / label); callers pass the active plan.
enum LifeScore {
    static func score(meals: [MealEntry], goals: Goals, planId: String? = nil) -> Int? {
        guard !meals.isEmpty else { return nil }
        // 1) Plan-aware diet quality — the day-level rating's 0–100 numeric (same engine as item/meal).
        let quality = Double(FoodRating.rateDay(meals: meals, planId: planId)?.score100 ?? 60)

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

// MARK: - Visual language

/// Small circular A–E badge (unchanged visual).
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

/// A tappable badge that reveals the transparent drivers behind the grade (why this letter, under
/// which plan). Reuses `FoodRatingBadge` as the visual; the popover is the "explainable" surface.
struct RatingBadgeButton: View {
    let rating: FoodRating.Rating
    var size: CGFloat = 22
    var title: String = "Food rating"
    @State private var show = false

    var body: some View {
        Button { show = true } label: { FoodRatingBadge(grade: rating.grade, size: size) }
            .buttonStyle(.plain)
            .popover(isPresented: $show) { RatingExplainCard(rating: rating, title: title) }
    }
}

/// The explanation surface: grade, plan caption, and the signed driver list. Factual, non-diagnostic.
struct RatingExplainCard: View {
    let rating: FoodRating.Rating
    var title: String = "Food rating"

    private var planName: String { ProgramCatalog.by(id: rating.planId)?.name ?? "Balanced" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FoodRatingBadge(grade: rating.grade, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("Rated for your \(planName) plan").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            Divider().overlay(Theme.border)
            if rating.drivers.isEmpty {
                Text("A middling C — nothing stands out either way for this plan.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Text("WHAT MOVED IT").font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                ForEach(rating.drivers.prefix(6)) { d in
                    HStack(spacing: 8) {
                        Image(systemName: d.positive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 13)).foregroundStyle(d.positive ? Theme.primary : Theme.orange)
                        Text(d.label).font(.system(size: 13)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(d.positive ? "＋" : "－").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(d.positive ? Theme.primary : Theme.orange)
                    }
                }
            }
            Text("A quality hint weighted for your plan — not medical advice.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 2)
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.card)
        .presentationCompactAdaptation(.popover)
    }
}
