import Foundation

/// Everything the onboarding questionnaire captures to design someone's plan. Stored in `AppData.intake`
/// and synced like the rest; `PlanBuilder` turns it into `Goals`.
struct IntakeProfile: Codable, Hashable {
    enum Sex: String, Codable, CaseIterable, Identifiable { case male, female; var id: String { rawValue }
        var label: String { self == .male ? "Male" : "Female" } }
    enum Pace: String, Codable, CaseIterable, Identifiable { case gentle, steady, fast; var id: String { rawValue }
        var label: String { switch self { case .gentle: return "Gentle"; case .steady: return "Steady"; case .fast: return "Fast" } }
        var kgPerWeek: Double { switch self { case .gentle: return 0.35; case .steady: return 0.6; case .fast: return 0.9 } }
        var detail: String { switch self {
            case .gentle: return "≈ 0.25–0.5 kg/week · easiest to stick to"
            case .steady: return "≈ 0.5–0.75 kg/week · recommended"
            case .fast:   return "≈ 0.75–1 kg/week · demanding, needs high protein" } } }
    enum JobActivity: String, Codable, CaseIterable, Identifiable { case desk, mixed, onFeet, physical; var id: String { rawValue }
        var label: String { switch self { case .desk: return "Desk / driving"; case .mixed: return "Mixed"; case .onFeet: return "On my feet"; case .physical: return "Physical work" } }
        var factor: Double { switch self { case .desk: return 1.2; case .mixed: return 1.3; case .onFeet: return 1.45; case .physical: return 1.6 } } }
    enum StepsBand: String, Codable, CaseIterable, Identifiable { case under4k, k4to7, k7to10, over10k; var id: String { rawValue }
        var label: String { switch self { case .under4k: return "Under 4,000"; case .k4to7: return "4,000 – 7,000"; case .k7to10: return "7,000 – 10,000"; case .over10k: return "Over 10,000" } }
        var goal: Int { switch self { case .under4k: return 6000; case .k4to7: return 8000; case .k7to10: return 10000; case .over10k: return 12000 } }
        var factorBonus: Double { switch self { case .under4k: return 0; case .k4to7: return 0.03; case .k7to10: return 0.07; case .over10k: return 0.12 } } }
    enum Experience: String, Codable, CaseIterable, Identifiable { case beginner, intermediate, advanced; var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var detail: String { switch self { case .beginner: return "New or returning after a long break"; case .intermediate: return "Trained on and off for a year or more"; case .advanced: return "Consistent training for years" } } }
    enum TrainingLocation: String, Codable, CaseIterable, Identifiable { case gym, home, both; var id: String { rawValue }
        var label: String { switch self { case .gym: return "Gym"; case .home: return "Home"; case .both: return "Both" } } }
    enum Equipment: String, Codable, CaseIterable, Identifiable { case dumbbells, barbell, machines, cables, bands, bench, kettlebell, none; var id: String { rawValue }
        var label: String { self == .none ? "Bodyweight only" : rawValue.capitalized } }
    enum TrainingTime: String, Codable, CaseIterable, Identifiable { case morning, midday, evening; var id: String { rawValue }
        var label: String { rawValue.capitalized } }
    enum EatingStyle: String, Codable, CaseIterable, Identifiable { case everything, halal, vegetarian, pescatarian, vegan; var id: String { rawValue }
        var label: String { switch self { case .everything: return "I eat everything"; case .halal: return "Halal only"; case .vegetarian: return "Vegetarian"; case .pescatarian: return "Pescatarian"; case .vegan: return "Vegan" } } }
    enum Allergy: String, Codable, CaseIterable, Identifiable { case gluten, lactose, nuts, eggs, shellfish, soy; var id: String { rawValue }
        var label: String { rawValue.capitalized } }
    enum Cooking: String, Codable, CaseIterable, Identifiable { case rarely, sometimes, mostly; var id: String { rawValue }
        var label: String { switch self { case .rarely: return "Rarely — mostly ordered or eaten out"; case .sometimes: return "Sometimes"; case .mostly: return "Most meals at home" } } }
    enum Cuisine: String, Codable, CaseIterable, Identifiable { case arabic, indian, mediterranean, asian, western; var id: String { rawValue }
        var label: String { rawValue.capitalized } }
    enum CravingTime: String, Codable, CaseIterable, Identifiable { case none, afternoon, evening, lateNight; var id: String { rawValue }
        var label: String { switch self { case .none: return "Not really"; case .afternoon: return "Afternoon"; case .evening: return "After dinner"; case .lateNight: return "Late night" } } }
    enum Alcohol: String, Codable, CaseIterable, Identifiable { case never, occasionally, weekly; var id: String { rawValue }
        var label: String { rawValue.capitalized } }
    enum Fasting: String, Codable, CaseIterable, Identifiable { case none, sixteenEight, ramadan; var id: String { rawValue }
        var label: String { switch self { case .none: return "No"; case .sixteenEight: return "16:8 window"; case .ramadan: return "Ramadan-style (sunrise–sunset)" } } }
    enum Mood: String, Codable, CaseIterable, Identifiable { case good, upAndDown, low, private_; var id: String { rawValue }
        var label: String { switch self { case .good: return "Mostly good"; case .upAndDown: return "Up and down"; case .low: return "Low more days than not"; case .private_: return "I'd rather not say" } } }
    enum Anxiety: String, Codable, CaseIterable, Identifiable { case rarely, sometimes, often, private_; var id: String { rawValue }
        var label: String { switch self { case .rarely: return "Rarely"; case .sometimes: return "Sometimes"; case .often: return "Often — it gets in the way"; case .private_: return "I'd rather not say" } } }
    enum Condition: String, Codable, CaseIterable, Identifiable { case prediabetes, diabetes, hypertension, cholesterol, thyroid, pcos, joints, heart, kidney; var id: String { rawValue }
        var label: String { switch self {
            case .prediabetes: return "Pre-diabetes"; case .diabetes: return "Diabetes"; case .hypertension: return "High blood pressure"
            case .cholesterol: return "High cholesterol"; case .thyroid: return "Thyroid"; case .pcos: return "PCOS"
            case .joints: return "Joint / back pain"; case .heart: return "Heart condition"; case .kidney: return "Kidney condition" } } }

    // About you
    var name = ""
    var sex: Sex = .male
    var birthYear = 1985
    var heightCm: Double = 175
    var weightKg: Double = 90
    var waistCm: Double? = nil
    // Goal
    var goalWeightKg: Double = 80
    var pace: Pace = .steady
    var motivation = ""
    var event = ""
    // Activity
    var jobActivity: JobActivity = .desk
    var dailySteps: StepsBand = .k4to7
    var currentTrainingDays = 0
    // Training
    var experience: Experience = .beginner
    var trainingDays = 3
    var location: TrainingLocation = .gym
    var equipment: Set<Equipment> = []
    var limitations = ""
    var preferredTime: TrainingTime = .evening
    // Nutrition
    var eatingStyle: EatingStyle = .everything
    var allergies: Set<Allergy> = []
    var dislikes = ""
    var mealsPerDay = 4
    var cooking: Cooking = .sometimes
    var eatingOutPerWeek = 3
    var cuisines: Set<Cuisine> = []
    var cravingTime: CravingTime = .evening
    var caffeinePerDay = 2
    var alcohol: Alcohol = .never
    var fasting: Fasting = .none
    // Lifestyle
    var wakeHour = 7
    var bedHour = 23
    var sleepHours: Double = 7
    var stress = 3
    var shiftWork = false
    // Health
    var conditions: Set<Condition> = []
    var mood: Mood = .good
    var anxiety: Anxiety = .rarely
    var medications = ""
    var currentSupplements = ""
    var doctorCleared = false
    var smoker = false
    // Devices
    var hasAppleWatch = false
    var completedAt: Date? = nil

    var age: Int { max(14, Calendar.current.component(.year, from: Date()) - birthYear) }
    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, default: ""); sex = c.value(.sex, default: .male); birthYear = c.value(.birthYear, default: 1985)
        heightCm = c.value(.heightCm, default: 175); weightKg = c.value(.weightKg, default: 90); waistCm = c.value(.waistCm, default: nil)
        goalWeightKg = c.value(.goalWeightKg, default: 80); pace = c.value(.pace, default: .steady)
        motivation = c.value(.motivation, default: ""); event = c.value(.event, default: "")
        jobActivity = c.value(.jobActivity, default: .desk); dailySteps = c.value(.dailySteps, default: .k4to7)
        currentTrainingDays = c.value(.currentTrainingDays, default: 0)
        experience = c.value(.experience, default: .beginner); trainingDays = c.value(.trainingDays, default: 3)
        location = c.value(.location, default: .gym); equipment = c.value(.equipment, default: [])
        limitations = c.value(.limitations, default: ""); preferredTime = c.value(.preferredTime, default: .evening)
        eatingStyle = c.value(.eatingStyle, default: .everything); allergies = c.value(.allergies, default: [])
        dislikes = c.value(.dislikes, default: ""); mealsPerDay = c.value(.mealsPerDay, default: 4)
        cooking = c.value(.cooking, default: .sometimes); eatingOutPerWeek = c.value(.eatingOutPerWeek, default: 3)
        cuisines = c.value(.cuisines, default: []); cravingTime = c.value(.cravingTime, default: .evening)
        caffeinePerDay = c.value(.caffeinePerDay, default: 2); alcohol = c.value(.alcohol, default: .never)
        fasting = c.value(.fasting, default: .none)
        wakeHour = c.value(.wakeHour, default: 7); bedHour = c.value(.bedHour, default: 23)
        sleepHours = c.value(.sleepHours, default: 7); stress = c.value(.stress, default: 3); shiftWork = c.value(.shiftWork, default: false)
        conditions = c.value(.conditions, default: []); medications = c.value(.medications, default: "")
        mood = c.value(.mood, default: .good); anxiety = c.value(.anxiety, default: .rarely)
        currentSupplements = c.value(.currentSupplements, default: ""); doctorCleared = c.value(.doctorCleared, default: false)
        smoker = c.value(.smoker, default: false); hasAppleWatch = c.value(.hasAppleWatch, default: false)
        completedAt = c.value(.completedAt, default: nil)
    }
}

/// Turns the questionnaire into daily targets. Mifflin-St Jeor BMR × activity, a deficit sized by the chosen
/// pace but capped at 25 % of maintenance, protein by goal weight, fat ≈ 27 % of calories, carbs the rest.
enum PlanBuilder {
    struct Targets {
        var bmr: Int, tdee: Int, kcal: Int, deficit: Int, protein: Int, carbs: Int, fat: Int
        var waterMl: Int, stepsGoal: Int, waistTarget: Double?
        var weeksToGoal: Int, kgToLose: Double
        var notes: [String]
    }

    static func targets(for p: IntakeProfile) -> Targets {
        let w = max(40, p.weightKg), h = max(140, p.heightCm), a = Double(p.age)
        let bmr = 10 * w + 6.25 * h - 5 * a + (p.sex == .male ? 5 : -161)
        var factor = p.jobActivity.factor + p.dailySteps.factorBonus + Double(p.trainingDays) * 0.03
        if p.hasAppleWatch == false && p.jobActivity == .desk { factor = min(factor, 1.45) }
        let tdee = bmr * factor
        let kgToLose = max(0, w - p.goalWeightKg)
        var deficit = p.pace.kgPerWeek * 7700 / 7
        deficit = min(deficit, tdee * 0.25)
        let floor: Double = p.sex == .male ? 1500 : 1200
        var kcal = max(floor, tdee - deficit)
        deficit = tdee - kcal
        var notes: [String] = []
        if kgToLose == 0 { kcal = tdee; deficit = 0; notes.append("Goal weight is at or above current weight — targets are set to maintenance.") }
        let goalW = kgToLose > 0 ? p.goalWeightKg : w
        var protein = 1.8 * goalW
        if p.age >= 50 { protein = 2.0 * goalW; notes.append("Protein is set higher (2 g/kg) to protect muscle after 50.") }
        protein = min(max(protein, 100), 230)
        let fat = max(45, (kcal * 0.27) / 9)
        let carbs = max(70, (kcal - protein * 4 - fat * 9) / 4)
        let water = min(4000, max(2000, Int((w * 35 / 250).rounded()) * 250))
        let waist = p.waistCm.map { max(70, ($0 - kgToLose * 0.9).rounded()) }
        let weeks = deficit > 0 ? Int((kgToLose * 7700 / (deficit * 7)).rounded(.up)) : 0
        if p.conditions.contains(.diabetes) || p.conditions.contains(.prediabetes) { notes.append("Carbs are kept moderate and spread across meals for blood-sugar control.") }
        if p.conditions.contains(.hypertension) || p.conditions.contains(.heart) || p.conditions.contains(.kidney) { notes.append("Please confirm this plan with your doctor before starting.") }
        if p.sleepHours < 6.5 { notes.append("Under 6.5 h sleep raises hunger hormones — the bedtime breathing session matters for you.") }
        if p.mood == .low || p.anxiety == .often {
            notes.append("Because you've had a rough stretch, the plan leans on daily walks, sleep and the breathing sessions — they lift mood as reliably as they help fat loss. Small, consistent wins over big pushes.")
            notes.append("If low mood or anxiety has lasted more than two weeks, talking to a doctor or counsellor is worth it — it's the strongest lever you have.")
        }
        if !p.medications.trimmingCharacters(in: .whitespaces).isEmpty {
            notes.append("Some medications change appetite, water retention or energy. Weight is judged on the 7-day trend, not single days, and your doctor should know about any calorie change.")
        }
        if p.fasting == .ramadan { notes.append("Meals are grouped into the eating window; keep protein in both main meals.") }
        return Targets(bmr: Int(bmr.rounded()), tdee: Int(tdee.rounded()), kcal: Int((kcal / 10).rounded() * 10), deficit: Int(deficit.rounded()),
                       protein: Int(protein.rounded()), carbs: Int(carbs.rounded()), fat: Int(fat.rounded()),
                       waterMl: water, stepsGoal: p.dailySteps.goal, waistTarget: waist,
                       weeksToGoal: weeks, kgToLose: kgToLose, notes: notes)
    }

    static func goals(for p: IntakeProfile, existing: Goals) -> Goals {
        let t = targets(for: p)
        var g = existing
        g.startWeight = p.weightKg
        g.goalWeight = p.goalWeightKg
        g.kcal = t.kcal; g.protein = t.protein; g.carbs = t.carbs; g.fat = t.fat; g.deficit = t.deficit
        g.waterGoal = t.waterMl
        g.stepsGoal = t.stepsGoal
        if let w = t.waistTarget { g.waistTarget = w }
        return g
    }
}
