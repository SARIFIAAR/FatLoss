import Foundation

/// Local-calendar "yyyy-MM-dd" keys (the web app used UTC via toISOString; native uses local days).
enum DateKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date = Date()) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
    static func daysAgo(_ n: Int) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: Date())) ?? Date()
    }
}

struct MeasurementEntry: Codable, Identifiable, Hashable {
    var date: String
    var value: Double
    var id: String { date }
}

/// One supplement the user tracks on Today. Either a catalog entry (`id` == a `Plan.supplementCatalog` key,
/// `custom` false) or a user-typed custom one (`id` == a generated "custom-…" id, `custom` true, `name` free).
/// The daily taken-toggle keys off `id`, so both catalog keys and custom ids flow through
/// `AppData.supplements[date]: Set<String>` unchanged.
struct TrackedSupplement: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var dose: String?
    var when: String?
    var custom: Bool = false

    init(id: String, name: String, dose: String? = nil, when: String? = nil, custom: Bool = false) {
        self.id = id; self.name = name; self.dose = dose; self.when = when; self.custom = custom
    }

    /// From a catalog supplement (dose/timing carried through so the card shows them).
    init(_ s: Supplement) {
        self.init(id: s.key, name: s.name, dose: s.dose, when: s.when, custom: false)
    }

    /// A user-typed custom supplement (stable id derived from the trimmed name so re-adding the same
    /// name doesn't create a duplicate).
    static func custom(named raw: String) -> TrackedSupplement {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let id = "custom-" + String(String(slug).prefix(40))
        return TrackedSupplement(id: id, name: name, dose: nil, when: nil, custom: true)
    }

    /// SF Symbol for the icon tile — the catalog's symbol for a known key, a neutral glyph for custom ones.
    var symbol: String { custom ? "pills.fill" : (Plan.supplement(id)?.symbol ?? "pills.fill") }

    /// "dose · when" when either is known, else nil.
    var detail: String? {
        switch (dose, when) {
        case let (d?, w?): return "\(d) · \(w)"
        case let (d?, nil): return d
        case let (nil, w?): return w
        case (nil, nil):   return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = c.value(.id,     default: "")
        name   = c.value(.name,   default: "")
        dose   = c.value(.dose,   default: nil)
        when   = c.value(.when,   default: nil)
        custom = c.value(.custom, default: false)
    }
}

struct RecoveryDay: Codable, Hashable {
    var hrv: Double?
    var rhr: Double?
    var sleepH: Double?
    var deepH: Double?
    var remH: Double?
    var resp: Double?
    var mood: Int?
    var spo2: Double?        // overnight blood oxygen %, Series 6+
    var tempC: Double?       // sleeping wrist temperature °C, Series 8+
    var inBedH: Double?      // time in bed (efficiency = sleepH / inBedH)
    var bedTime: Date?       // first in-bed/asleep sample (consistency)
    var wakeTime: Date?      // last asleep sample end
    var awakeCount: Int?     // awake segments during the night (disturbances)
    var napH: Double?        // daytime nap hours (separate from the main sleep)

    var hasMetrics: Bool { (hrv ?? 0) > 0 || (sleepH ?? 0) > 0 || (rhr ?? 0) > 0 }
    var isEmpty: Bool {
        !hasMetrics && deepH == nil && remH == nil && resp == nil && mood == nil
            && spo2 == nil && tempC == nil && inBedH == nil
    }
    var efficiency: Double? {
        guard let s = sleepH, let b = inBedH, b > 0.5, s > 0 else { return nil }
        return min(100, s / b * 100)
    }
}

/// A body-composition reading (e.g. from an InBody report photo or manual entry).
struct BodyCompEntry: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var date: String                 // DateKey
    var weightKg: Double
    var bodyFatPct: Double?
    var fatMassKg: Double?           // fat mass
    var muscleKg: Double?            // skeletal muscle mass (SMM)
    var visceralFat: Double?         // InBody visceral fat level (unitless)
    var bmr: Double?                 // basal metabolic rate from the report
    var source: String = "manual"   // "inbody" | "manual"
    // Fuller InBody sheet fields (all optional)
    var totalBodyWaterL: Double?     // total body water (L)
    var visceralFatArea: Double?     // visceral fat area (cm²)
    var inbodyScore: Double?         // InBody score (points)
    var proteinKg: Double?
    var mineralKg: Double?
    var segmentalLean: [Double]?     // lean % of ideal: [right arm, left arm, trunk, right leg, left leg]

    /// Fat mass falls back to weight × body-fat % when the report only gives the percentage.
    var fatKg: Double? { fatMassKg ?? (bodyFatPct.map { weightKg * $0 / 100 }) }

    init(id: String = UUID().uuidString, date: String, weightKg: Double, bodyFatPct: Double? = nil,
         fatMassKg: Double? = nil, muscleKg: Double? = nil, visceralFat: Double? = nil,
         bmr: Double? = nil, source: String = "manual", totalBodyWaterL: Double? = nil,
         visceralFatArea: Double? = nil, inbodyScore: Double? = nil, proteinKg: Double? = nil,
         mineralKg: Double? = nil, segmentalLean: [Double]? = nil) {
        self.id = id; self.date = date; self.weightKg = weightKg; self.bodyFatPct = bodyFatPct
        self.fatMassKg = fatMassKg; self.muscleKg = muscleKg; self.visceralFat = visceralFat
        self.bmr = bmr; self.source = source; self.totalBodyWaterL = totalBodyWaterL
        self.visceralFatArea = visceralFatArea; self.inbodyScore = inbodyScore
        self.proteinKg = proteinKg; self.mineralKg = mineralKg; self.segmentalLean = segmentalLean
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = c.value(.id,          default: UUID().uuidString)
        date        = c.value(.date,        default: "")
        weightKg    = c.value(.weightKg,    default: 0)
        bodyFatPct  = c.value(.bodyFatPct,  default: nil)
        fatMassKg   = c.value(.fatMassKg,   default: nil)
        muscleKg    = c.value(.muscleKg,    default: nil)
        visceralFat = c.value(.visceralFat, default: nil)
        bmr         = c.value(.bmr,         default: nil)
        source      = c.value(.source,      default: "manual")
        totalBodyWaterL = c.value(.totalBodyWaterL, default: nil)
        visceralFatArea = c.value(.visceralFatArea, default: nil)
        inbodyScore     = c.value(.inbodyScore,     default: nil)
        proteinKg       = c.value(.proteinKg,       default: nil)
        mineralKg       = c.value(.mineralKg,       default: nil)
        segmentalLean   = c.value(.segmentalLean,   default: nil)
    }
}

/// One Apple Health workout (name, duration, HR summary, minutes per HR zone 1–5).
struct WorkoutEntry: Codable, Hashable, Identifiable {
    var id: String                    // HKWorkout UUID
    var date: String                  // DateKey
    var name: String
    var start: Date
    var minutes: Double
    var kcal: Double?
    var avgHR: Double?
    var maxHR: Double?
    var zoneMin: [Double] = []        // minutes in zones 1...5 (may be empty without HR data)

    init(id: String, date: String, name: String, start: Date, minutes: Double,
         kcal: Double? = nil, avgHR: Double? = nil, maxHR: Double? = nil, zoneMin: [Double] = []) {
        self.id = id; self.date = date; self.name = name; self.start = start
        self.minutes = minutes; self.kcal = kcal; self.avgHR = avgHR; self.maxHR = maxHR; self.zoneMin = zoneMin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = c.value(.id,      default: UUID().uuidString)
        date    = c.value(.date,    default: "")
        name    = c.value(.name,    default: "Workout")
        start   = c.value(.start,   default: Date())
        minutes = c.value(.minutes, default: 0)
        kcal    = c.value(.kcal,    default: nil)
        avgHR   = c.value(.avgHR,   default: nil)
        maxHR   = c.value(.maxHR,   default: nil)
        zoneMin = c.value(.zoneMin, default: [])
    }
}

struct ExerciseLog: Codable, Identifiable, Hashable {
    var date: String
    var kg: Double
    var reps: Int
    var id: String { date }
}

struct HealthDay: Codable, Hashable {
    var steps: Int = 0
    var restingHR: Double?
    var activeKcal: Double?      // Apple Watch "Move" energy (active calories)
    var basalKcal: Double?       // resting / basal energy for the same day
    var bodyFatPct: Double?      // from a BIA band/scale via Apple Health
    var leanMassKg: Double?      // lean body mass from the same source
    var vo2Max: Double?          // ml/kg/min, Apple Health (Watch cardio fitness)
    var glucoseMgDl: Double?     // avg blood glucose mg/dL (CGM / glucometer via Health)
    var bpSystolic: Double?      // avg systolic mmHg
    var bpDiastolic: Double?     // avg diastolic mmHg
    var hrrBpm: Double?          // 1-min heart-rate recovery (bpm drop after a workout)

    /// Total energy burned so far that day (nil until the Watch has reported anything).
    var burnedKcal: Double? {
        let total = (activeKcal ?? 0) + (basalKcal ?? 0)
        return total > 0 ? total : nil
    }

    init(steps: Int = 0, restingHR: Double? = nil, activeKcal: Double? = nil, basalKcal: Double? = nil,
         bodyFatPct: Double? = nil, leanMassKg: Double? = nil, vo2Max: Double? = nil,
         glucoseMgDl: Double? = nil, bpSystolic: Double? = nil, bpDiastolic: Double? = nil,
         hrrBpm: Double? = nil) {
        self.steps = steps; self.restingHR = restingHR; self.activeKcal = activeKcal; self.basalKcal = basalKcal
        self.bodyFatPct = bodyFatPct; self.leanMassKg = leanMassKg; self.vo2Max = vo2Max
        self.glucoseMgDl = glucoseMgDl; self.bpSystolic = bpSystolic; self.bpDiastolic = bpDiastolic
        self.hrrBpm = hrrBpm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps       = c.value(.steps,       default: 0)
        restingHR   = c.value(.restingHR,   default: nil)
        activeKcal  = c.value(.activeKcal,  default: nil)
        basalKcal   = c.value(.basalKcal,   default: nil)
        bodyFatPct  = c.value(.bodyFatPct,  default: nil)
        leanMassKg  = c.value(.leanMassKg,  default: nil)
        vo2Max      = c.value(.vo2Max,      default: nil)
        glucoseMgDl = c.value(.glucoseMgDl, default: nil)
        bpSystolic  = c.value(.bpSystolic,  default: nil)
        bpDiastolic = c.value(.bpDiastolic, default: nil)
        hrrBpm      = c.value(.hrrBpm,      default: nil)
    }
}

struct Goals: Codable, Hashable {
    var startWeight: Double = 106
    var goalWeight: Double = 93
    var waistTarget: Double = 95
    var stepsGoal: Int = 8000
    var waterGoal: Int = 3000
    var kcal: Int = 1850
    var protein: Int = 165
    var carbs: Int = 150
    var fat: Int = 65
    var deficit: Int = 550
    /// When true (net, Lifesum's default), Apple-Watch/active burn is added to the day's calorie
    /// allowance (budget = target + burned). When false (gross), the budget is just eaten-vs-target
    /// and burn is shown but not added. Default true preserves the app's current energy-balance model.
    var countBurnedCalories: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startWeight = c.value(.startWeight, default: 106)
        goalWeight  = c.value(.goalWeight,  default: 93)
        waistTarget = c.value(.waistTarget, default: 95)
        stepsGoal   = c.value(.stepsGoal,   default: 8000)
        waterGoal   = c.value(.waterGoal,   default: 3000)
        kcal        = c.value(.kcal,        default: 1850)
        protein     = c.value(.protein,     default: 165)
        carbs       = c.value(.carbs,       default: 150)
        fat         = c.value(.fat,         default: 65)
        deficit     = c.value(.deficit,     default: 550)
        countBurnedCalories = c.value(.countBurnedCalories, default: true)
    }
}

struct FoodItem: Codable, Hashable, Identifiable {
    var name: String
    var portion: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var id: String { name + portion }
}

/// A logged meal (from the photo scanner or entered manually).
struct MealEntry: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var date: String                 // DateKey
    var time: Date = Date()
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double? = nil         // grams; enables a richer food rating when present
    var sugar: Double? = nil         // grams
    var sodium: Double? = nil        // mg
    var satFat: Double? = nil        // grams
    var items: [FoodItem] = []
    var confidence: String? = nil    // low / medium / high
    var notes: String? = nil
    var slot: String? = nil          // Plan.meals key: breakfast / lunch / snack / dinner / evening
}

/// A progress (body) photo — a LOCAL METADATA INDEX entry. The image BYTES live in Firebase Storage at
/// `users/{uid}/photos/{id}.jpg` (cross-device source of truth) with a small Firestore metadata doc; a
/// local file-protected cache holds downloaded bytes for offline display (see `PhotoStore`/`PhotoSync`).
/// This struct carries NO image bytes, so it stays cheap in the AppData sync blob; it's the on-device
/// index PhotoSync reconciles against the cloud (guests keep it local-only until they sign in).
struct ProgressPhoto: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var date: String                 // DateKey (yyyy-MM-dd, local)
    var filename: String             // cache filename in the progress-photos dir (id + ".jpg")
    var at: Date = Date()            // capture/import timestamp (ordering within a day)
    var weightKg: Double? = nil      // optional weight snapshot at the time
    var note: String? = nil          // optional short note

    init(id: String = UUID().uuidString, date: String, filename: String, at: Date = Date(),
         weightKg: Double? = nil, note: String? = nil) {
        self.id = id; self.date = date; self.filename = filename; self.at = at
        self.weightKg = weightKg; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.value(.id,       default: UUID().uuidString)
        date     = c.value(.date,     default: "")
        filename = c.value(.filename, default: "")
        at       = c.value(.at,       default: Date())
        weightKg = c.value(.weightKg, default: nil)
        note     = c.value(.note,     default: nil)
    }
}

struct ProgramState: Codable, Hashable {
    var phase: Int = 1
    var startDate: String?      // DateKey of the day this phase was started; nil = not started

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = c.value(.phase, default: 1)
        startDate = c.value(.startDate, default: nil)
    }
}

/// Local-notification preferences (water + walk nudges). Synced like everything else.
struct ReminderSettings: Codable, Hashable {
    var waterOn = false
    var waterEveryMinutes = 120        // 60 / 90 / 120 / 180
    var startHour = 9                  // first reminder of the day
    var endHour = 21                   // no reminders after this hour
    var walkOn = false
    var walkHours: [Int] = [16, 19]    // steps check-ins (skipped once the step goal is reached)
    var mealsOn = false                // meal-logging reminders (breakfast/lunch/dinner)
    var mealHours: [Int] = [8, 13, 19] // when to nudge for each meal
    var healthAlertsPush = false       // notify when a vital is out of your typical range
    var maxHrOverride: Int?            // user-set max HR for zones (nil = 220 − age)
    // Per-habit reminders: habitId → minutes-of-day (e.g. 8*60+30). Presence of a key = enabled.
    // Pruned to existing habitDefs whenever the plan runs, so a deleted habit leaves no stale nudge.
    var habitReminders: [String: Int] = [:]
    // Per-supplement reminders: TrackedSupplement.id → minutes-of-day. Pruned to tracked supplements.
    var supplementReminders: [String: Int] = [:]
    // Workout reminder: fires on the current programme phase's training weekdays only.
    var workoutOn = false
    var workoutMinute = 18 * 60        // minutes-of-day (default 6 PM; onboarding preferredTime overrides)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterOn           = c.value(.waterOn,           default: false)
        waterEveryMinutes = c.value(.waterEveryMinutes, default: 120)
        startHour         = c.value(.startHour,         default: 9)
        endHour           = c.value(.endHour,           default: 21)
        walkOn            = c.value(.walkOn,            default: false)
        walkHours         = c.value(.walkHours,         default: [16, 19])
        mealsOn           = c.value(.mealsOn,           default: false)
        mealHours         = c.value(.mealHours,         default: [8, 13, 19])
        healthAlertsPush  = c.value(.healthAlertsPush,  default: false)
        maxHrOverride     = c.value(.maxHrOverride,     default: nil)
        habitReminders       = c.value(.habitReminders,       default: [:])
        supplementReminders  = c.value(.supplementReminders,  default: [:])
        workoutOn            = c.value(.workoutOn,            default: false)
        workoutMinute        = c.value(.workoutMinute,        default: 18 * 60)
    }
}

/// Everything the app persists. One JSON file on disk, mirrored to Firestore when signed in.
struct AppData: Codable, Hashable {
    var weightLogs: [MeasurementEntry] = []                 // was "weight-logs" (+ "cur-weight")
    var waistLogs: [MeasurementEntry] = []                  // was "waist-logs"  (+ "cur-waist")
    var recovery: [String: RecoveryDay] = [:]               // was "rec-YYYY-MM-DD"
    var overload: [String: [ExerciseLog]] = [:]             // was "po-{Exercise}"
    var habits: [String: Set<String>] = [:]                 // was "habits-YYYY-MM-DD"
    var supplements: [String: Set<String>] = [:]            // was "supps-YYYY-MM-DD"
    var water: [String: Int] = [:]                          // was "water-YYYY-MM-DD"
    var health: [String: HealthDay] = [:]                   // was "health-sync"
    var exerciseDone: [String: Set<Int>] = [:]              // was "ex-YYYY-MM-DD-Mon"
    var meals: [String: [MealEntry]] = [:]                  // date -> meals eaten
    var workouts: [String: [WorkoutEntry]] = [:]            // date -> Apple Health workouts
    var bodyComp: [BodyCompEntry] = []                      // InBody / manual body-composition readings
    var breathing: [String: Set<String>] = [:]              // date -> breathing slots done
    var habitDefs: [HabitDef] = []                          // customizable habit definitions
    var habitLog: [String: [String: Double]] = [:]          // date -> habitId -> logged value (manual)
    var didSeedHabits = false                               // starter habits seeded once
    // Legacy: the four-item onboarding selection (Plan.supplements keys). Kept only so old JSON still opens
    // and migrates into `supplementsTracked` on first decode. New writes go to `supplementsTracked`.
    var supplementsSelected: [String] = []
    // The supplements the user tracks on Today — catalog entries AND custom ones, any number. Source of truth
    // for the card, the manage sheet, and adherence. Empty on a completed profile = "track none".
    var supplementsTracked: [TrackedSupplement] = []
    var nutritionPlanId: String? = nil                      // chosen diet program (Nutrition > Program)
    var favoriteMeals: [MealEntry] = []                     // hearted meals for quick re-logging
    var plannedMeals: [String: [String: String]] = [:]      // date -> slot -> recipeId (persisted meal plan)
    var caffeine: [String: [CaffeineEntry]] = [:]           // date -> logged coffees (shots + mg + time)
    // Progress-photo METADATA only (id/date/filename/optional weight+note). The image BYTES stay on-device
    // in the progress-photos dir (PhotoStore) and are NEVER encoded here — so this can sync safely while the
    // sensitive body photos never leave the phone. Union-merged by id like the other id-keyed collections.
    var progressPhotos: [ProgressPhoto] = []
    var goals = Goals()
    var program = ProgramState()
    var reminders = ReminderSettings()
    var intake: IntakeProfile? = nil                        // onboarding questionnaire (nil = not done)
    var updatedAt: Date = Date()
    /// When goals / programme / reminders last changed. Merges take those three from the copy with the
    /// newer settings stamp, so a copy that is "newer" only because of health or meal writes can't revert them.
    var settingsUpdatedAt: Date = Date(timeIntervalSince1970: 0)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weightLogs   = c.value(.weightLogs,   default: [])
        waistLogs    = c.value(.waistLogs,    default: [])
        recovery     = c.value(.recovery,     default: [:])
        overload     = c.value(.overload,     default: [:])
        habits       = c.value(.habits,       default: [:])
        supplements  = c.value(.supplements,  default: [:])
        water        = c.value(.water,        default: [:])
        health       = c.value(.health,       default: [:])
        exerciseDone = c.value(.exerciseDone, default: [:])
        meals        = c.value(.meals,        default: [:])
        workouts     = c.value(.workouts,     default: [:])
        bodyComp     = c.value(.bodyComp,     default: [])
        breathing    = c.value(.breathing,    default: [:])
        habitDefs    = c.value(.habitDefs,    default: [])
        habitLog     = c.value(.habitLog,     default: [:])
        didSeedHabits = c.value(.didSeedHabits, default: false)
        supplementsSelected = c.value(.supplementsSelected, default: [])
        // Migrate: if a build wrote the new list, use it; otherwise rebuild it from the legacy 4-item keys so
        // existing users keep exactly the supplements they picked (no drop, no reset to all).
        let tracked = c.value(.supplementsTracked, default: [TrackedSupplement]())
        if !tracked.isEmpty {
            supplementsTracked = tracked
        } else {
            supplementsTracked = supplementsSelected.compactMap { key in Plan.supplement(key).map(TrackedSupplement.init) }
        }
        nutritionPlanId = c.value(.nutritionPlanId, default: nil)
        favoriteMeals = c.value(.favoriteMeals, default: [])
        plannedMeals = c.value(.plannedMeals, default: [:])
        caffeine     = c.value(.caffeine,     default: [:])
        progressPhotos = c.value(.progressPhotos, default: [])
        goals        = c.value(.goals,        default: Goals())
        program      = c.value(.program,      default: ProgramState())
        reminders    = c.value(.reminders,    default: ReminderSettings())
        intake       = c.value(.intake,       default: nil)
        // An unreadable stamp must never make a copy look newest — default to the epoch, not now.
        updatedAt    = c.value(.updatedAt,    default: Date(timeIntervalSince1970: 0))
        settingsUpdatedAt = c.value(.settingsUpdatedAt, default: Date(timeIntervalSince1970: 0))
    }

    var isEmpty: Bool {
        weightLogs.isEmpty && waistLogs.isEmpty && recovery.isEmpty && overload.isEmpty
            && habits.isEmpty && supplements.isEmpty && water.isEmpty && health.isEmpty && meals.isEmpty
            && progressPhotos.isEmpty
    }

    /// Union merge used by cloud sync. For scalar conflicts the newer snapshot wins.
    func merged(with other: AppData) -> AppData {
        let otherIsNewer = other.updatedAt > updatedAt
        var out = otherIsNewer ? other : self
        let older = otherIsNewer ? self : other

        func mergeLogs(_ a: [MeasurementEntry], _ b: [MeasurementEntry]) -> [MeasurementEntry] {
            var byDate: [String: Double] = [:]
            for e in b { byDate[e.date] = e.value }
            for e in a { byDate[e.date] = e.value }   // newer wins
            return byDate.map { MeasurementEntry(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        }
        out.weightLogs = mergeLogs(out.weightLogs, older.weightLogs)
        out.waistLogs = mergeLogs(out.waistLogs, older.waistLogs)
        out.recovery.merge(older.recovery) { newer, _ in newer }
        out.health.merge(older.health) { newer, old in
            var h = newer
            h.steps = max(newer.steps, old.steps)
            h.activeKcal = [newer.activeKcal, old.activeKcal].compactMap { $0 }.max()
            h.basalKcal = [newer.basalKcal, old.basalKcal].compactMap { $0 }.max()
            h.restingHR = newer.restingHR ?? old.restingHR
            return h
        }
        out.water.merge(older.water) { newer, old in max(newer, old) }
        out.habits.merge(older.habits) { $0.union($1) }
        out.supplements.merge(older.supplements) { $0.union($1) }
        out.exerciseDone.merge(older.exerciseDone) { $0.union($1) }
        out.breathing.merge(older.breathing) { $0.union($1) }
        // Habit definitions: union by id, order-preserving (keep the newer snapshot's order, then
        // append any habits only the older copy has). Never re-sort dictionary values — that reshuffles.
        var mergedDefs = out.habitDefs
        let mergedIDs = Set(mergedDefs.map(\.id))
        for d in older.habitDefs where !mergedIDs.contains(d.id) { mergedDefs.append(d) }
        out.habitDefs = mergedDefs
        out.didSeedHabits = out.didSeedHabits || older.didSeedHabits
        // Tracked supplements: union by id, order-preserving (newer snapshot's order first, then any the older
        // copy has that the newer one dropped) — same rule as habit defs so adds from two devices don't fight.
        var mergedSupps = out.supplementsTracked
        let mergedSuppIDs = Set(mergedSupps.map(\.id))
        for s in older.supplementsTracked where !mergedSuppIDs.contains(s.id) { mergedSupps.append(s) }
        out.supplementsTracked = mergedSupps
        // Favorite meals: union by lowercased name (newer wins).
        var favByName: [String: MealEntry] = [:]
        for m in older.favoriteMeals { favByName[m.name.lowercased()] = m }
        for m in out.favoriteMeals { favByName[m.name.lowercased()] = m }
        out.favoriteMeals = favByName.values.sorted { $0.name < $1.name }
        for (day, slots) in older.plannedMeals {
            out.plannedMeals[day] = out.plannedMeals[day]?.merging(slots) { newer, _ in newer } ?? slots
        }
        // Caffeine: union by entry id per day.
        for (day, entries) in older.caffeine {
            var byID: [String: CaffeineEntry] = [:]
            for e in entries { byID[e.id] = e }
            for e in out.caffeine[day] ?? [] { byID[e.id] = e }
            out.caffeine[day] = byID.values.sorted { $0.time < $1.time }
        }
        for (day, vals) in older.habitLog {
            out.habitLog[day] = out.habitLog[day]?.merging(vals) { newer, _ in newer } ?? vals
        }
        out.overload.merge(older.overload) { newer, old in
            var byDate: [String: ExerciseLog] = [:]
            for l in old { byDate[l.date] = l }
            for l in newer { byDate[l.date] = l }
            return byDate.values.sorted { $0.date < $1.date }
        }
        out.meals.merge(older.meals) { newer, old in
            var byID: [String: MealEntry] = [:]
            for m in old { byID[m.id] = m }
            for m in newer { byID[m.id] = m }
            return byID.values.sorted { $0.time < $1.time }
        }
        out.workouts.merge(older.workouts) { newer, old in
            var byID: [String: WorkoutEntry] = [:]
            for w in old { byID[w.id] = w }
            for w in newer { byID[w.id] = w }
            return byID.values.sorted { $0.start < $1.start }
        }
        var byID: [String: BodyCompEntry] = [:]
        for e in older.bodyComp { byID[e.id] = e }
        for e in out.bodyComp { byID[e.id] = e }
        out.bodyComp = byID.values.sorted { $0.date < $1.date }
        // Progress-photo metadata: union by id (newer wins), oldest→newest. Note a merged-in entry from
        // ANOTHER device points to a file that only exists on that device — the UI renders such an entry as
        // a missing thumbnail, never as another user's photo (and account isolation wipes on account switch).
        var photosByID: [String: ProgressPhoto] = [:]
        for p in older.progressPhotos { photosByID[p.id] = p }
        for p in out.progressPhotos { photosByID[p.id] = p }
        out.progressPhotos = photosByID.values.sorted { $0.at < $1.at }
        // Settings (goals, programme, reminders) follow their own stamp, not the data stamp.
        let settingsSource = other.settingsUpdatedAt > settingsUpdatedAt ? other : self
        out.goals = settingsSource.goals
        out.reminders = settingsSource.reminders
        out.program = settingsSource.program
        out.intake = settingsSource.intake ?? older.intake ?? out.intake
        // Programme safety net: the further-along phase wins, and at the same phase a started
        // programme beats a not-started one (never silently move someone backwards or un-start them).
        for cand in [program, other.program] {
            if cand.phase > out.program.phase { out.program = cand }
            else if cand.phase == out.program.phase, out.program.startDate == nil, cand.startDate != nil { out.program = cand }
        }
        out.updatedAt = max(updatedAt, other.updatedAt)
        out.settingsUpdatedAt = max(settingsUpdatedAt, other.settingsUpdatedAt)
        return out
    }
}

struct DatedValue: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default d: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? d
    }
}
