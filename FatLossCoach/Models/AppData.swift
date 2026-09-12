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

    /// Total energy burned so far that day (nil until the Watch has reported anything).
    var burnedKcal: Double? {
        let total = (activeKcal ?? 0) + (basalKcal ?? 0)
        return total > 0 ? total : nil
    }

    init(steps: Int = 0, restingHR: Double? = nil, activeKcal: Double? = nil, basalKcal: Double? = nil) {
        self.steps = steps; self.restingHR = restingHR; self.activeKcal = activeKcal; self.basalKcal = basalKcal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps      = c.value(.steps,      default: 0)
        restingHR  = c.value(.restingHR,  default: nil)
        activeKcal = c.value(.activeKcal, default: nil)
        basalKcal  = c.value(.basalKcal,  default: nil)
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
    var items: [FoodItem] = []
    var confidence: String? = nil    // low / medium / high
    var notes: String? = nil
    var slot: String? = nil          // Plan.meals key: breakfast / lunch / snack / dinner / evening
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

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterOn           = c.value(.waterOn,           default: false)
        waterEveryMinutes = c.value(.waterEveryMinutes, default: 120)
        startHour         = c.value(.startHour,         default: 9)
        endHour           = c.value(.endHour,           default: 21)
        walkOn            = c.value(.walkOn,            default: false)
        walkHours         = c.value(.walkHours,         default: [16, 19])
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
    var breathing: [String: Set<String>] = [:]              // date -> breathing slots done
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
        breathing    = c.value(.breathing,    default: [:])
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
