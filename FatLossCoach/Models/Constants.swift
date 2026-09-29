import Foundation

struct Habit: Identifiable, Hashable {
    let key: String
    let label: String
    let time: String
    var id: String { key }
}

struct Supplement: Identifiable, Hashable {
    let key: String
    let name: String
    /// Well-known supplements carry a suggested dose + timing; the long tail omits them (nil).
    let dose: String?
    let when: String?
    /// SF Symbol for the row's icon tile. Defaults to "pills.fill" when the catalog entry omits one.
    let symbol: String

    var id: String { key }

    init(key: String, name: String, dose: String? = nil, when: String? = nil, symbol: String = "pills.fill") {
        self.key = key
        self.name = name
        self.dose = dose
        self.when = when
        self.symbol = symbol
    }

    /// Backwards-compatible icon accessor (older call sites used `.icon`). Equals `symbol`.
    var icon: String { symbol }

    /// "dose · when" when either is known, else nil. Used by rows that show a subtitle only when we have one.
    var detail: String? {
        switch (dose, when) {
        case let (d?, w?): return "\(d) · \(w)"
        case let (d?, nil): return d
        case let (nil, w?): return w
        case (nil, nil):   return nil
        }
    }
}

struct Exercise: Identifiable, Hashable {
    let name: String
    let sets: String
    let muscles: String
    let images: [URL]
    var id: String { name }

    init(_ name: String, _ sets: String, _ muscles: String, _ slug: String) {
        self.name = name
        self.sets = sets
        self.muscles = muscles
        let base = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
        self.images = ["0", "1"].compactMap { URL(string: base + slug + "/" + $0 + ".jpg") }
    }
}

struct WorkoutDay: Identifiable, Hashable {
    let day: String       // "Mon"
    let label: String
    let tag: String
    let exercises: [Exercise]
    var id: String { day }
    var isTraining: Bool { !exercises.isEmpty }
}

struct Phase: Identifiable, Hashable {
    let number: Int          // 1...3
    let name: String         // "Foundation"
    let tagline: String      // shown in the Workout header
    let weeks: Int           // planned length
    let goal: String         // what this phase is for
    let tip: String          // progression rule for this phase
    let workouts: [WorkoutDay]
    var id: Int { number }
    var trainingDays: [String] { workouts.filter(\.isTraining).map(\.day) }
}

struct BreathingSlot: Identifiable {
    let icon: String
    let time: String
    let name: String
    let detail: String
    /// Seconds for inhale · hold · exhale · hold (0 = skip that phase).
    var pattern: [Int] = [4, 4, 4, 4]
    /// Session length in minutes (used when `cycles` is nil).
    var minutes: Int = 3
    /// Fixed number of breath cycles instead of a timed session.
    var cycles: Int? = nil
    /// Why and how — shown on the session intro screen.
    var guide: String = ""
    var id: String { name }

    var inhale: Int { pattern[0] }
    var hold1: Int { pattern.count > 1 ? pattern[1] : 0 }
    var exhale: Int { pattern.count > 2 ? pattern[2] : 0 }
    var hold2: Int { pattern.count > 3 ? pattern[3] : 0 }
    var cycleSeconds: Int { inhale + hold1 + exhale + hold2 }
    var totalSeconds: Int { cycles.map { $0 * cycleSeconds } ?? minutes * 60 }
    var patternLabel: String {
        var parts = ["In \(inhale)s"]
        if hold1 > 0 { parts.append("Hold \(hold1)s") }
        parts.append("Out \(exhale)s")
        if hold2 > 0 { parts.append("Hold \(hold2)s") }
        return parts.joined(separator: " · ")
    }
}

struct Meal: Identifiable {
    let key: String          // "breakfast"
    let name: String
    let time: String
    let targetKcal: Int
    var id: String { key }
    var kcal: String { "~\(targetKcal) kcal" }
}

/// Static programme content, ported 1:1 from the web app.
enum Plan {
    static let habits: [Habit] = [
        Habit(key: "walk",    label: "Morning Walk",        time: "30–45 min"),
        Habit(key: "workout", label: "Workout Done",       time: "Mon/Wed/Fri"),
        Habit(key: "water",   label: "Water 3L",            time: "all day"),
        Habit(key: "kitchen", label: "Kitchen Closed 9pm",  time: "9:00 PM"),
        Habit(key: "breath",  label: "Breathing Exercise", time: "any time"),
        Habit(key: "supps",   label: "Supplements Taken",   time: "D3 · Omega-3 · Mg"),
        Habit(key: "sleep",   label: "In Bed by 11pm",      time: "11:00 PM"),
    ]

    /// The original four (kept as-is, same keys/dose/timing). These are the well-known picks surfaced first
    /// and are the only ones an old build ever wrote to `supplementsSelected`, so their keys must not change.
    static let supplements: [Supplement] = [
        Supplement(key: "vd3", name: "Vitamin D3",              dose: "2000–4000 IU", when: "With breakfast", symbol: "sun.max.fill"),
        Supplement(key: "o3",  name: "Omega-3",                 dose: "2–3g EPA+DHA", when: "With meal",       symbol: "fish.fill"),
        Supplement(key: "mg",  name: "Magnesium Glycinate",     dose: "300–400mg",    when: "At night",        symbol: "moon.zzz.fill"),
        Supplement(key: "wh",  name: "Whey Protein (optional)", dose: "25–30g",       when: "Post-workout",    symbol: "dumbbell.fill"),
    ]

    /// A broad, searchable library of common supplements the user can add any number of. The first four keep
    /// the legacy keys (vd3/o3/mg/wh) so existing `supplementsSelected` data maps straight in. Dose/timing are
    /// filled only for the well-known ones — the long tail is name + icon and the user sets their own routine.
    static let supplementCatalog: [Supplement] = supplements + [
        // Vitamins
        Supplement(key: "vitA",       name: "Vitamin A",                                              symbol: "eye.fill"),
        Supplement(key: "bcomplex",   name: "B-Complex",              dose: "1 tablet",  when: "With breakfast", symbol: "b.circle.fill"),
        Supplement(key: "b12",        name: "Vitamin B12",            dose: "500–1000 mcg", when: "Morning",    symbol: "bolt.heart.fill"),
        Supplement(key: "vitC",       name: "Vitamin C",              dose: "500–1000 mg", when: "With meal",   symbol: "leaf.fill"),
        Supplement(key: "vitE",       name: "Vitamin E",                                              symbol: "drop.fill"),
        Supplement(key: "k2",         name: "Vitamin K2",             dose: "100–200 mcg", when: "With fat",    symbol: "drop.fill"),
        Supplement(key: "folate",     name: "Folate",                                                 symbol: "leaf.fill"),
        Supplement(key: "biotin",     name: "Biotin",                                                 symbol: "sparkles"),
        Supplement(key: "multi",      name: "Multivitamin",           dose: "1 serving", when: "With breakfast", symbol: "pills.circle.fill"),
        Supplement(key: "dk",         name: "Vitamin D + K",          dose: "With fat",  when: "Morning",     symbol: "sun.max.fill"),
        // Minerals
        Supplement(key: "mgcit",      name: "Magnesium Citrate",      dose: "200–400 mg", when: "Evening",     symbol: "moon.stars.fill"),
        Supplement(key: "mgsleep",    name: "Magnesium (sleep)",      dose: "300–400 mg", when: "Before bed",  symbol: "bed.double.fill"),
        Supplement(key: "zinc",       name: "Zinc",                   dose: "15–30 mg",  when: "With food",   symbol: "aqi.medium"),
        Supplement(key: "iron",       name: "Iron",                   dose: "With vitamin C", when: "Away from coffee", symbol: "drop.triangle.fill"),
        Supplement(key: "calcium",    name: "Calcium",                dose: "500 mg",    when: "With meal",   symbol: "circle.hexagongrid.fill"),
        Supplement(key: "potassium",  name: "Potassium",                                              symbol: "bolt.fill"),
        Supplement(key: "iodine",     name: "Iodine",                                                 symbol: "atom"),
        Supplement(key: "selenium",   name: "Selenium",                                               symbol: "atom"),
        Supplement(key: "electro",    name: "Electrolytes",           dose: "1 sachet",  when: "During training", symbol: "drop.halffull"),
        // Omega / oils
        Supplement(key: "fishoil",    name: "Fish Oil",               dose: "1–2 g EPA+DHA", when: "With meal", symbol: "fish.fill"),
        Supplement(key: "krill",      name: "Krill Oil",                                              symbol: "fish.fill"),
        Supplement(key: "codliver",   name: "Cod Liver Oil",          dose: "1 tsp",     when: "With meal",   symbol: "fish.fill"),
        // Performance
        Supplement(key: "creatine",   name: "Creatine Monohydrate",   dose: "5 g",       when: "Any time daily", symbol: "bolt.fill"),
        Supplement(key: "casein",     name: "Casein Protein",         dose: "25–30 g",   when: "Before bed",  symbol: "moon.fill"),
        Supplement(key: "collagen",   name: "Collagen",               dose: "10–15 g",   when: "Any time",    symbol: "figure.strengthtraining.functional"),
        Supplement(key: "eaa",        name: "BCAA / EAA",             dose: "5–10 g",    when: "Around training", symbol: "figure.run"),
        Supplement(key: "glutamine",  name: "Glutamine",              dose: "5 g",       when: "Post-workout", symbol: "figure.run"),
        Supplement(key: "betaala",    name: "Beta-Alanine",           dose: "3–5 g",     when: "Daily",       symbol: "flame.fill"),
        Supplement(key: "preworkout", name: "Pre-Workout",            dose: "1 scoop",   when: "Before training", symbol: "flame.fill"),
        Supplement(key: "caffeine",   name: "Caffeine",               dose: "100–200 mg", when: "Before training", symbol: "cup.and.saucer.fill"),
        Supplement(key: "caffltheanine", name: "Caffeine + L-Theanine", dose: "100 mg / 200 mg", when: "Morning", symbol: "cup.and.saucer.fill"),
        Supplement(key: "taurine",    name: "Taurine",                                                symbol: "bolt.fill"),
        // Gut / general
        Supplement(key: "probiotics", name: "Probiotics",             dose: "1 capsule", when: "With food",   symbol: "allergens.fill"),
        Supplement(key: "prebiotic",  name: "Prebiotic Fibre",                                        symbol: "leaf.fill"),
        Supplement(key: "psyllium",   name: "Psyllium Husk",          dose: "1 tbsp",    when: "With water",  symbol: "leaf.fill"),
        Supplement(key: "greens",     name: "Greens Powder",          dose: "1 scoop",   when: "Morning",     symbol: "leaf.fill"),
        Supplement(key: "acv",        name: "Apple Cider Vinegar",    dose: "1 tbsp",    when: "Before meals", symbol: "drop.fill"),
        // Adaptogens / sleep / mind
        Supplement(key: "ashwa",      name: "Ashwagandha",            dose: "300–600 mg", when: "Evening",    symbol: "leaf.circle.fill"),
        Supplement(key: "rhodiola",   name: "Rhodiola",                                               symbol: "leaf.circle.fill"),
        Supplement(key: "ltheanine",  name: "L-Theanine",             dose: "100–200 mg", when: "As needed",  symbol: "brain.head.profile"),
        Supplement(key: "melatonin",  name: "Melatonin",              dose: "0.5–3 mg",  when: "Before bed",  symbol: "moon.zzz.fill"),
        Supplement(key: "ginkgo",     name: "Ginkgo Biloba",                                          symbol: "brain.head.profile"),
        Supplement(key: "inositol",   name: "Inositol",                                               symbol: "circle.grid.cross.fill"),
        // Joints / heart / liver / metabolic
        Supplement(key: "turmeric",   name: "Turmeric / Curcumin",    dose: "500 mg",    when: "With meal",   symbol: "circle.fill"),
        Supplement(key: "coq10",      name: "CoQ10",                  dose: "100–200 mg", when: "With fat",   symbol: "heart.fill"),
        Supplement(key: "glucosamine", name: "Glucosamine",           dose: "1500 mg",   when: "Daily",       symbol: "figure.walk"),
        Supplement(key: "nac",        name: "NAC",                    dose: "600 mg",    when: "Daily",       symbol: "lungs.fill"),
        Supplement(key: "berberine",  name: "Berberine",              dose: "500 mg",    when: "With meals",  symbol: "circle.hexagonpath.fill"),
        Supplement(key: "milkthistle", name: "Milk Thistle",                                          symbol: "leaf.fill"),
    ]

    /// Catalog lookup by key.
    static func supplement(_ key: String) -> Supplement? { supplementCatalog.first { $0.key == key } }

    /// Default supplements shown in the adherence card when we have no user selection to reason about.
    static let trackedSupplements = ["vd3", "o3", "mg"]

    // MARK: Programme phases — PARKED (no longer the Workout-tab driver)
    //
    // The static 3-phase programme content moved to `Legacy/LegacyProgramme.swift` (`LegacyPlan`)
    // when the Physical-Age engine became the training driver. These two members stay as thin
    // shims so `Store.currentPhase`/`phaseProgress`, the Today PhaseStrip, ProfileView, and the
    // ReminderManager training-weekday derivation keep compiling and working — and so restoring
    // the phase-based programme is a one-line swap in WorkoutView. See LegacyProgramme.swift.
    static var phases: [Phase] { LegacyPlan.phases }
    static func phase(_ n: Int) -> Phase { LegacyPlan.phase(n) }


    /// "Mon" ... "Sun" for today, independent of the device locale.
    static var todayAbbrev: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: Date())
    }

    static let breathing: [BreathingSlot] = [
        BreathingSlot(icon: "", time: "7:00 AM",           name: "Box Breathing",   detail: "Inhale 4s · Hold 4s · Exhale 4s · Hold 4s — 5 min",
                      pattern: [4, 4, 4, 4], minutes: 5,
                      guide: "Sit tall, shoulders down, one hand on your belly. Breathe in through the nose for 4, hold 4, out through the nose for 4, hold 4 — the four equal sides of a box.\n\nThis steadies the nervous system and sharpens focus for the day. If 4 seconds feels long at first, the app will still guide you — just follow the circle and let the breath be quiet, never forced."),
        BreathingSlot(icon: "", time: "Pre-Workout",       name: "Belly Breathing", detail: "Deep diaphragm breaths — 3 min to activate focus",
                      pattern: [5, 0, 5, 0], minutes: 3,
                      guide: "Belly (diaphragmatic) breathing: one hand on the chest, one on the belly. As you breathe in for 5 seconds the belly hand should rise more than the chest hand; breathe out for 5 and feel it fall.\n\nIt lowers tension in the neck and shoulders and switches you on before training. Keep the jaw soft and breathe through the nose."),
        BreathingSlot(icon: "", time: "Evening (craving)", name: "4-7-8 Technique", detail: "Inhale 4s · Hold 7s · Exhale 8s — 3 cycles. Stops cravings.",
                      pattern: [4, 7, 8, 0], cycles: 4,
                      guide: "Tongue resting behind the top front teeth. Breathe in quietly through the nose for 4, hold for 7, then breathe out fully through the mouth for 8 with a soft whoosh.\n\nThe long hold and exhale calm the stress response that drives evening cravings — do it before opening the fridge. If the 7-second hold is too much at first, hold for as long as is comfortable; the count will still guide you."),
        BreathingSlot(icon: "", time: "Bedtime",           name: "Extended Exhale", detail: "Inhale 4s · Exhale 8s — repeat until drowsy",
                      pattern: [4, 0, 8, 0], minutes: 5,
                      guide: "Lying down, lights low. Breathe in through the nose for 4 and let the breath out slowly for 8 — the exhale is twice the inhale.\n\nA long exhale tells the body it is safe to sleep; better sleep means lower cortisol and easier fat loss. Stop whenever you feel drowsy — there is no need to finish the timer."),
    ]

    static let meals: [Meal] = [
        Meal(key: "breakfast", name: "Breakfast",          time: "7:00 – 8:30 AM",  targetKcal: 480),
        Meal(key: "lunch",     name: "Lunch",              time: "12:30 – 2:00 PM", targetKcal: 560),
        Meal(key: "snack",     name: "Snack",              time: "3:30 – 4:30 PM",  targetKcal: 200),
        Meal(key: "dinner",    name: "Dinner",             time: "7:00 – 8:00 PM",  targetKcal: 480),
        Meal(key: "evening",   name: "Evening (optional)", time: "before 9:00 PM",  targetKcal: 130),
        Meal(key: "alcohol",   name: "Alcohol",            time: "log any drinks",  targetKcal: 0),
    ]
    static func meal(_ key: String?) -> Meal? { meals.first { $0.key == key } }

    static let kitchenClosesHour = 21
    static let maxWaterPerDay = 5000
}
