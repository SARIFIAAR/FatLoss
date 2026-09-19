import Foundation
import Observation

/// Single source of truth. Replaces the web app's localStorage; persists to one JSON file
/// in Application Support (debounced) and notifies `CloudSync` on every change.
@Observable
final class Store {
    /// NOTE: never mutate `data` inside this observer — that re-enters the setter and recurses.
    var data: AppData {
        didSet {
            guard data != oldValue else { return }
            if !isApplyingRemote {
                lastModified = Date()
                if data.goals != oldValue.goals || data.program != oldValue.program || data.reminders != oldValue.reminders || data.intake != oldValue.intake {
                    settingsModified = Date()
                }
            }
            scheduleSave()
            if !isApplyingRemote { onChange?() }
        }
    }
    /// Kept outside `data` so writes don't observe themselves. Stamped into `updatedAt` on save/export/push.
    var lastModified: Date
    /// Same idea for goals / programme / reminders — see `AppData.settingsUpdatedAt`.
    var settingsModified: Date
    var toast: String?

    /// Set by CloudSync while merging a remote snapshot so we don't echo it back.
    var isApplyingRemote = false
    var onChange: (() -> Void)?

    private var toastTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? dir.appendingPathComponent("fatloss-data.json")
        let loaded = (try? Data(contentsOf: self.fileURL))
            .flatMap { try? Self.decoder.decode(AppData.self, from: $0) } ?? AppData()
        data = loaded
        lastModified = loaded.updatedAt
        settingsModified = loaded.settingsUpdatedAt
    }

    /// `data` with the current modification time stamped in — what gets persisted and synced.
    func snapshot() -> AppData {
        var d = data
        d.updatedAt = lastModified
        d.settingsUpdatedAt = settingsModified
        return d
    }

    // MARK: Persistence

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Accept both "2026-09-07T19:21:25Z" and "…25.467Z" so a timestamp never fails to decode.
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: str) ?? fractional.date(from: str) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(str)"))
        }
        return d
    }()

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        do {
            let raw = try Self.encoder.encode(snapshot())
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            print("Store.save failed: \(error)")
        }
        WidgetSync.publish(from: self)
    }

    func exportJSON() -> String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(snapshot())).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Dates

    var today: String { DateKey.key() }

    // MARK: Habits

    func isHabitDone(_ key: String, on day: String? = nil) -> Bool {
        data.habits[day ?? today]?.contains(key) ?? false
    }
    func toggleHabit(_ key: String) {
        var set = data.habits[today] ?? []
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
            showToast("Habit logged! 🎉")
        }
        data.habits[today] = set
    }
    func habitCount(on day: String) -> Int { data.habits[day]?.count ?? 0 }

    /// Auto-complete a habit from another tracker (supplements, breathing, water). Never un-ticks.
    private func autoHabit(_ key: String, done: Bool) {
        guard done, !(data.habits[today]?.contains(key) ?? false) else { return }
        var set = data.habits[today] ?? []
        set.insert(key)
        data.habits[today] = set
    }

    // MARK: Nutrition — diet program & recipes

    var nutritionPlan: DietProgram? { ProgramCatalog.by(id: data.nutritionPlanId) }

    /// Start a diet program: sets it active and rewrites the macro targets from its split.
    func chooseProgram(_ p: DietProgram) {
        data.nutritionPlanId = p.id
        let m = p.macros(forKcal: data.goals.kcal)
        data.goals.protein = m.protein
        data.goals.carbs = m.carbs
        data.goals.fat = m.fat
        settingsModified = Date()
        showToast("\(p.name) plan started")
    }
    func clearNutritionPlan() { data.nutritionPlanId = nil; settingsModified = Date() }

    /// Log a recipe straight to the diary as a meal.
    func logRecipe(_ r: Recipe, slot: String? = nil, on day: String? = nil) {
        let entry = MealEntry(date: day ?? today, name: r.name,
                              kcal: Double(r.kcal), protein: Double(r.protein),
                              carbs: Double(r.carbs), fat: Double(r.fat), slot: slot)
        addMeal(entry)
        showToast("\(r.name) logged")
    }

    // MARK: Custom habits (user-defined trackers)

    var habitDefs: [HabitDef] { data.habitDefs }

    /// Give a fresh install three sensible starter habits; never re-seeds once the user has curated.
    func seedDefaultHabitsIfNeeded() {
        guard !data.didSeedHabits, data.habitDefs.isEmpty else { return }
        data.habitDefs = [
            HabitDef(metric: .steps,   colorHex: 0x43CB00),
            HabitDef(metric: .water,   colorHex: 0x4CA9E8),
            HabitDef(metric: .protein, colorHex: 0xA96CF0),
        ]
        data.didSeedHabits = true
    }

    func addHabit(_ def: HabitDef) {
        data.habitDefs.append(def); data.didSeedHabits = true
        showToast("Habit added")
    }
    func updateHabit(_ def: HabitDef) {
        if let i = data.habitDefs.firstIndex(where: { $0.id == def.id }) { data.habitDefs[i] = def }
    }
    func deleteHabit(_ id: String) { data.habitDefs.removeAll { $0.id == id } }

    /// Today's value for a habit — auto metrics read existing data, manual ones read the log.
    func habitValue(_ def: HabitDef, on day: String? = nil) -> Double {
        let k = day ?? today
        switch def.metric {
        case .steps:            return Double(data.health[k]?.steps ?? 0)
        case .caloriesBurned:   return data.health[k]?.burnedKcal ?? 0
        case .caloriesConsumed: return (data.meals[k] ?? []).reduce(0) { $0 + $1.kcal }
        case .protein:          return (data.meals[k] ?? []).reduce(0) { $0 + $1.protein }
        case .water:            return Double(data.water[k] ?? 0)
        case .sleepDuration:    return data.recovery[k]?.sleepH ?? 0
        case .workoutCount:     return Double((data.workouts[k] ?? []).count)
        default:                return data.habitLog[k]?[def.id] ?? 0     // manual
        }
    }

    func logHabit(_ def: HabitDef, value: Double, on day: String? = nil) {
        let k = day ?? today
        var m = data.habitLog[k] ?? [:]
        m[def.id] = value
        data.habitLog[k] = m
    }

    func habitProgress(_ def: HabitDef, on day: String? = nil) -> Double {
        guard def.goal > 0 else { return habitValue(def, on: day) > 0 ? 1 : 0 }
        return min(1, habitValue(def, on: day) / def.goal)
    }
    func habitMet(_ def: HabitDef, on day: String? = nil) -> Bool {
        def.goal > 0 ? habitValue(def, on: day) >= def.goal : habitValue(def, on: day) > 0
    }
    /// Consecutive days (ending today) the habit's goal was met.
    func habitStreak(_ def: HabitDef) -> Int {
        var n = 0
        while habitMet(def, on: DateKey.key(DateKey.daysAgo(n))) { n += 1; if n > 400 { break } }
        return n
    }

    // MARK: Onboarding

    /// Save the questionnaire and derive goals, first weight/waist entries and reminder hours from it.
    func applyIntake(_ intake: IntakeProfile) {
        var p = intake
        p.completedAt = Date()
        var d = data
        d.intake = p
        d.goals = PlanBuilder.goals(for: p, existing: d.goals)
        d.reminders.startHour = min(max(p.wakeHour + 1, 6), 12)
        d.reminders.endHour = min(max(p.bedHour - 1, 18), 23)
        data = d
        if data.weightLogs.isEmpty || (currentWeight ?? 0) != p.weightKg { _ = logWeight(p.weightKg) }
        if let w = p.waistCm, data.waistLogs.last?.value != w { _ = logWaist(w) }
        showToast("Plan ready for \(p.name.isEmpty ? "you" : p.name) 🎯")
    }

    // MARK: Breathing

    func isBreathingDone(_ name: String) -> Bool { data.breathing[today]?.contains(name) ?? false }
    /// Called when a guided session finishes — ticks the slot, never un-ticks.
    func markBreathingDone(_ name: String) {
        guard !isBreathingDone(name) else { return }
        var set = data.breathing[today] ?? []
        set.insert(name)
        data.breathing[today] = set
        autoHabit("breath", done: true)
        showToast("\(name) done 🌬️")
    }
    func toggleBreathing(_ name: String) {
        var set = data.breathing[today] ?? []
        if set.contains(name) { set.remove(name) } else { set.insert(name); showToast("Breathing done 🌬️") }
        data.breathing[today] = set
        autoHabit("breath", done: !set.isEmpty)
    }

    // MARK: Supplements

    func isSupplementTaken(_ key: String) -> Bool { data.supplements[today]?.contains(key) ?? false }
    func toggleSupplement(_ key: String) {
        var set = data.supplements[today] ?? []
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
            showToast("Supplement taken! 💊")
        }
        data.supplements[today] = set
        autoHabit("supps", done: Plan.trackedSupplements.allSatisfy { set.contains($0) })
    }
    /// Percent of the last `days` days on which the supplement was taken.
    func adherence(_ key: String, days: Int = 7) -> Int {
        let taken = (0..<days).filter { data.supplements[DateKey.key(DateKey.daysAgo($0))]?.contains(key) ?? false }.count
        return Int((Double(taken) / Double(days) * 100).rounded())
    }

    // MARK: Water

    var waterToday: Int { data.water[today] ?? 0 }
    /// Called after water changes so reminders can be re-planned with the new progress.
    var onWaterChange: (() -> Void)?

    func addWater(_ ml: Int) {
        data.water[today] = min(waterToday + ml, Plan.maxWaterPerDay)
        showToast("+\(ml) ml 💧")
        autoHabit("water", done: waterToday >= data.goals.waterGoal)
        onWaterChange?()
    }
    func resetWater() { data.water[today] = 0; onWaterChange?() }

    func setHealthAlertsPush(_ on: Bool) { data.reminders.healthAlertsPush = on }
    func setMaxHR(_ bpm: Int?) { data.reminders.maxHrOverride = bpm }

    // MARK: Weight & waist

    var currentWeight: Double? { data.weightLogs.max { $0.date < $1.date }?.value }
    var currentWaist: Double? { data.waistLogs.max { $0.date < $1.date }?.value }

    var kgLost: Double { max(0, data.goals.startWeight - (currentWeight ?? data.goals.startWeight)) }
    var goalProgress: Double {
        let span = data.goals.startWeight - data.goals.goalWeight
        guard span > 0 else { return 0 }
        return min(kgLost / span, 1)
    }

    @discardableResult
    func logWeight(_ v: Double, on day: String? = nil) -> Bool {
        guard v >= 30, v <= 300 else { showToast("Enter a valid weight"); return false }
        upsert(&data.weightLogs, date: day ?? today, value: v)
        showToast("Weight saved: \(Fmt.num(v)) kg ✓")
        return true
    }

    @discardableResult
    func logWaist(_ v: Double, on day: String? = nil) -> Bool {
        guard v >= 40, v <= 200 else { showToast("Enter a valid measurement"); return false }
        upsert(&data.waistLogs, date: day ?? today, value: v)
        showToast("Waist saved: \(Fmt.num(v)) cm ✓")
        return true
    }

    func upsert(_ logs: inout [MeasurementEntry], date: String, value: Double) {
        logs.removeAll { $0.date == date }
        logs.append(MeasurementEntry(date: date, value: value))
        logs.sort { $0.date < $1.date }
    }

    // MARK: Chart series

    func series(_ logs: [MeasurementEntry], days: Int) -> [DatedValue] {
        let start = DateKey.daysAgo(days - 1)
        return logs.compactMap { e in
            guard let d = DateKey.date(e.date), d >= start else { return nil }
            return DatedValue(date: d, value: e.value)
        }.sorted { $0.date < $1.date }
    }
    func weightSeries(days: Int = 30) -> [DatedValue] { series(data.weightLogs, days: days) }
    func waistSeries(days: Int = 30) -> [DatedValue] { series(data.waistLogs, days: days) }

    func recoverySeries(days: Int, _ keyPath: KeyPath<RecoveryDay, Double?>) -> [DatedValue] {
        (0..<days).reversed().compactMap { n in
            let d = DateKey.daysAgo(n)
            guard let v = data.recovery[DateKey.key(d)]?[keyPath: keyPath], v > 0 else { return nil }
            return DatedValue(date: d, value: v)
        }
    }

    func stepsSeries(days: Int = 7) -> [DatedValue] {
        (0..<days).reversed().map { n in
            let d = DateKey.daysAgo(n)
            return DatedValue(date: d, value: Double(data.health[DateKey.key(d)]?.steps ?? 0))
        }
    }

    // MARK: Recovery / readiness

    var recoveryToday: RecoveryDay { data.recovery[today] ?? RecoveryDay() }

    func updateRecovery(on day: String? = nil, _ mutate: (inout RecoveryDay) -> Void) {
        let k = day ?? today
        var r = data.recovery[k] ?? RecoveryDay()
        mutate(&r)
        if r.isEmpty { data.recovery.removeValue(forKey: k) } else { data.recovery[k] = r }
    }

    func setMood(_ m: Int) {
        updateRecovery { $0.mood = m }
        let msgs = ["", "😔 Noted", "😞 Noted", "😐 Noted", "😊 Great!", "😄 Amazing!"]
        showToast(msgs[min(max(m, 0), 5)])
    }

    /// Same formula as the web app: HRV 40 pts · sleep 30 (+5 deep, +5 REM) · resting HR 20.
    static func readiness(_ d: RecoveryDay) -> Int? {
        guard d.hasMetrics else { return nil }
        let hrv = d.hrv ?? 0, sleep = d.sleepH ?? 0, rhr = d.rhr ?? 0
        var s = 0
        if hrv > 0 { s += min(40, Int((hrv / 80 * 40).rounded())) }
        if sleep > 0 {
            s += min(30, Int((sleep / 8 * 30).rounded()))
            if let deep = d.deepH, deep > 0 { s += min(5, Int((deep / 1.5 * 5).rounded())) }
            if let rem = d.remH, rem > 0 { s += min(5, Int((rem / 2 * 5).rounded())) }
        }
        if rhr > 0 { s += rhr <= 55 ? 20 : rhr <= 65 ? 15 : rhr <= 75 ? 8 : 3 }
        return min(100, s)
    }

    // MARK: Progressive overload

    func logs(for exercise: String) -> [ExerciseLog] { data.overload[exercise] ?? [] }
    func lastLog(for exercise: String) -> ExerciseLog? {
        logs(for: exercise).filter { $0.date != today }.max { $0.date < $1.date }
    }
    func todayLog(for exercise: String) -> ExerciseLog? {
        logs(for: exercise).first { $0.date == today }
    }
    func saveExerciseLog(_ exercise: String, kg: Double, reps: Int, on day: String? = nil) {
        let k = day ?? today
        var l = logs(for: exercise)
        l.removeAll { $0.date == k }
        l.append(ExerciseLog(date: k, kg: kg, reps: reps))
        l.sort { $0.date < $1.date }
        data.overload[exercise] = l
        if day == nil { showToast("\(exercise): \(Fmt.num(kg)) kg × \(reps) ✓") }
    }

    // MARK: Meals

    struct MacroTotals { var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0 }

    var mealsToday: [MealEntry] { (data.meals[today] ?? []).sorted { $0.time < $1.time } }

    func totals(on day: String? = nil) -> MacroTotals {
        (data.meals[day ?? today] ?? []).reduce(into: MacroTotals()) {
            $0.kcal += $1.kcal; $0.protein += $1.protein; $0.carbs += $1.carbs; $0.fat += $1.fat
        }
    }

    func meals(slot: String, on day: String? = nil) -> [MealEntry] {
        let key: String = day ?? today
        let list: [MealEntry] = data.meals[key] ?? []
        return list.filter { $0.slot == slot }
    }
    func kcal(slot: String, on day: String? = nil) -> Double { meals(slot: slot, on: day).reduce(0) { $0 + $1.kcal } }
    func meals(on day: String) -> [MealEntry] { (data.meals[day] ?? []).sorted { $0.time < $1.time } }

    struct MacroKcal: Identifiable {
        let date: Date; let macro: String; let kcal: Double
        var id: String { "\(date.timeIntervalSince1970)-\(macro)" }
    }
    /// Calories per day split into protein / carbs / fat energy (4 / 4 / 9 kcal per g).
    func macroKcalSeries(days: Int = 7) -> [MacroKcal] {
        (0..<days).reversed().flatMap { n -> [MacroKcal] in
            let d = DateKey.daysAgo(n)
            let t = totals(on: DateKey.key(d))
            return [MacroKcal(date: d, macro: "Protein", kcal: t.protein * 4),
                    MacroKcal(date: d, macro: "Carbs", kcal: t.carbs * 4),
                    MacroKcal(date: d, macro: "Fat", kcal: t.fat * 9)]
        }
    }

    func addMeal(_ meal: MealEntry) {
        var list = data.meals[meal.date] ?? []
        list.removeAll { $0.id == meal.id }
        list.append(meal)
        data.meals[meal.date] = list
        showToast("\(meal.name) logged · \(Int(meal.kcal.rounded())) kcal 🍽️")
    }

    func deleteMeal(_ meal: MealEntry) {
        var list = data.meals[meal.date] ?? []
        list.removeAll { $0.id == meal.id }
        if list.isEmpty { data.meals.removeValue(forKey: meal.date) } else { data.meals[meal.date] = list }
    }

    // MARK: Programme phases

    struct PhaseProgress {
        var started: Bool
        var week: Int          // 1-based, clamped to totalWeeks
        var totalWeeks: Int
        var fraction: Double   // 0...1 within the phase
        var daysLeft: Int
        var isComplete: Bool { started && fraction >= 1 }
    }

    var currentPhase: Phase { Plan.phase(data.program.phase) }

    var phaseProgress: PhaseProgress {
        let ph = currentPhase
        guard let sd = data.program.startDate, let start = DateKey.date(sd) else {
            return PhaseProgress(started: false, week: 0, totalWeeks: ph.weeks, fraction: 0, daysLeft: ph.weeks * 7)
        }
        let elapsed = max(0, Calendar.current.dateComponents([.day], from: start, to: DateKey.daysAgo(0)).day ?? 0)
        let total = ph.weeks * 7
        return PhaseProgress(started: true,
                             week: min(elapsed / 7 + 1, ph.weeks),
                             totalWeeks: ph.weeks,
                             fraction: min(Double(elapsed) / Double(total), 1),
                             daysLeft: max(0, total - elapsed))
    }

    /// Completion of each phase for the 3-segment programme bar.
    func phaseFill(_ n: Int) -> Double {
        if n < data.program.phase { return 1 }
        if n == data.program.phase { return phaseProgress.fraction }
        return 0
    }

    func startCurrentPhase() {
        data.program.startDate = today
        showToast("Phase \(currentPhase.number) started — let's go 💪")
    }

    func setPhase(_ n: Int, startToday: Bool) {
        guard Plan.phases.contains(where: { $0.number == n }) else { return }
        data.program.phase = n
        data.program.startDate = startToday ? today : nil
        showToast("Now on Phase \(n): \(Plan.phase(n).name)")
    }

    func advancePhase() {
        let next = min(data.program.phase + 1, Plan.phases.count)
        guard next != data.program.phase else { return }
        setPhase(next, startToday: true)
    }

    /// Habit subtitle for the workout habit follows the current phase's training days.
    func habitTime(_ h: Habit) -> String {
        h.key == "workout" ? currentPhase.trainingDays.joined(separator: "/") : h.time
    }

    // MARK: Workout session

    private func sessionKey(_ day: String) -> String { "\(today)-\(day)" }
    func isExerciseDone(day: String, index: Int) -> Bool {
        data.exerciseDone[sessionKey(day)]?.contains(index) ?? false
    }
    func toggleExercise(day: String, index: Int) {
        var set = data.exerciseDone[sessionKey(day)] ?? []
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        data.exerciseDone[sessionKey(day)] = set
    }
    func completeWorkout() {
        var set = data.habits[today] ?? []
        set.insert("workout")
        data.habits[today] = set
        showToast("Workout completed! 💪 Great job!")
    }

    // MARK: Health (steps / resting HR)

    var healthToday: HealthDay? { data.health[today] }

    func setHealth(steps: Int? = nil, restingHR: Double? = nil,
                   activeKcal: Double? = nil, basalKcal: Double? = nil,
                   bodyFatPct: Double? = nil, leanMassKg: Double? = nil, vo2Max: Double? = nil,
                   glucoseMgDl: Double? = nil, bpSystolic: Double? = nil, bpDiastolic: Double? = nil,
                   hrrBpm: Double? = nil, on day: String? = nil) {
        let k = day ?? today
        var h = data.health[k] ?? HealthDay()
        if let steps { h.steps = steps }
        if let restingHR { h.restingHR = restingHR }
        if let activeKcal { h.activeKcal = activeKcal }
        if let basalKcal { h.basalKcal = basalKcal }
        if let bodyFatPct { h.bodyFatPct = bodyFatPct }
        if let leanMassKg { h.leanMassKg = leanMassKg }
        if let vo2Max { h.vo2Max = vo2Max }
        if let glucoseMgDl { h.glucoseMgDl = glucoseMgDl }
        if let bpSystolic { h.bpSystolic = bpSystolic }
        if let bpDiastolic { h.bpDiastolic = bpDiastolic }
        if let hrrBpm { h.hrrBpm = hrrBpm }
        data.health[k] = h
    }

    /// Apple Health hydration fills a day only if the user hasn't logged more water manually.
    func setHydrationFromHealth(_ ml: Int, on day: String) {
        if (data.water[day] ?? 0) < ml { data.water[day] = ml }
    }

    // MARK: Body composition (InBody / manual entries + Apple Health BIA fallback)

    var bodyCompSorted: [BodyCompEntry] { data.bodyComp.sorted { $0.date < $1.date } }
    var latestBodyComp: BodyCompEntry? { bodyCompSorted.last }

    func addBodyComp(_ e: BodyCompEntry) {
        // Upsert: replace an entry with the same id (editing), else append (adding/backfilling).
        if let i = data.bodyComp.firstIndex(where: { $0.id == e.id }) { data.bodyComp[i] = e }
        else { data.bodyComp.append(e) }
        // Keep the weight chart in sync so a report also logs weight.
        if e.weightKg > 0 { _ = logWeight(e.weightKg, on: e.date) }
        showToast("Body composition saved")
    }

    func deleteBodyComp(_ id: String) { data.bodyComp.removeAll { $0.id == id } }

    /// Most recent body-fat % and derived fat/lean masses — prefers an InBody/manual entry,
    /// falls back to Apple Health BIA within the last `days`.
    func bodyComposition(days: Int = 90) -> (bodyFatPct: Double, fatMassKg: Double, leanMassKg: Double, date: String)? {
        if let e = latestBodyComp, let bf = e.bodyFatPct ?? (e.fatKg.map { $0 / e.weightKg * 100 }) {
            let fat = e.fatKg ?? (e.weightKg * bf / 100)
            let lean = e.muscleKg ?? (e.weightKg - fat)
            return (bf, fat, lean, e.date)
        }
        for n in 0..<days {
            let k = DateKey.key(DateKey.daysAgo(n))
            guard let h = data.health[k], let bf = h.bodyFatPct else { continue }
            let weight = weightOn(k) ?? currentWeight
            guard let w = weight else { continue }
            let fat = w * bf / 100
            return (bf, fat, h.leanMassKg ?? (w - fat), k)
        }
        return nil
    }

    /// Weight logged on or most recently before a given day key.
    func weightOn(_ key: String) -> Double? {
        data.weightLogs.filter { $0.date <= key }.max { $0.date < $1.date }?.value
    }

    /// BMI from current weight + onboarding height.
    var bmi: Double? {
        guard let w = currentWeight else { return nil }
        let h = (data.intake?.heightCm ?? 0) / 100
        guard h > 1 else { return nil }
        return w / (h * h)
    }

    /// Latest VO2 max within the last `days` (Apple Health, infrequent).
    func latestVO2(days: Int = 90) -> Double? {
        for n in 0..<days {
            if let v = data.health[DateKey.key(DateKey.daysAgo(n))]?.vo2Max, v > 0 { return v }
        }
        return nil
    }

    /// Fitness-age estimate from recent metrics (28-day averages of HRV/RHR/steps/sleep + latest VO2).
    func fitnessAge() -> BodyMetrics.FitnessAge? {
        guard let intake = data.intake else { return nil }
        func avg(_ vals: [Double]) -> Double? { vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count) }
        let hrv = avg(bodyHistory(\.hrv, days: 28))
        let rhr = avg(bodyHistory(\.rhr, days: 28))
        let sleep = avg(bodyHistory(\.sleepH, days: 28))
        let steps = avg((1...28).compactMap { n -> Double? in
            let s = data.health[DateKey.key(DateKey.daysAgo(n))]?.steps ?? 0
            return s > 0 ? Double(s) : nil
        })
        return BodyMetrics.fitnessAge(chronological: intake.age, isMale: intake.sex == .male,
                                      vo2Max: latestVO2(), hrv: hrv, restingHR: rhr,
                                      avgSteps: steps, avgSleepH: sleep)
    }

    /// Mifflin-St Jeor BMR from intake (matches PlanBuilder).
    var bmr: Int? {
        guard let p = data.intake else { return nil }
        let w = currentWeight ?? p.weightKg
        let s = p.sex == .female ? -161.0 : 5.0
        return Int((10 * w + 6.25 * p.heightCm - 5 * Double(p.age) + s).rounded())
    }

    // MARK: Energy balance (Apple Watch burn vs. logged intake)

    struct EnergyDay: Identifiable, Hashable {
        let date: Date
        let eaten: Double
        let active: Double?
        let basal: Double?
        var burned: Double? { let t = (active ?? 0) + (basal ?? 0); return t > 0 ? t : nil }
        /// Positive = deficit, negative = surplus. nil until both sides have data.
        var deficit: Double? { guard let burned, eaten > 0 else { return nil }; return burned - eaten }
        var id: Date { date }
    }

    func energy(on day: String? = nil) -> EnergyDay {
        let k = day ?? today
        let h = data.health[k]
        return EnergyDay(date: DateKey.date(k) ?? Date(), eaten: totals(on: k).kcal,
                         active: h?.activeKcal, basal: h?.basalKcal)
    }

    func energySeries(days: Int = 7) -> [EnergyDay] {
        (0..<days).reversed().map { energy(on: DateKey.key(DateKey.daysAgo($0))) }
    }

    /// Average daily deficit over the last `days` full days that have both intake and burn logged.
    func averageDeficit(days: Int = 7) -> Double? {
        let ds = (1...days).compactMap { energy(on: DateKey.key(DateKey.daysAgo($0))).deficit }
        return ds.isEmpty ? nil : ds.reduce(0, +) / Double(ds.count)
    }

    /// Manual fallback for the Profile tab (mirrors the web app's manualSync()).
    func manualSync(steps: Int?, rhr: Double?, hrv: Double?, sleep: Double?, deep: Double?, rem: Double?) {
        if steps != nil || rhr != nil { setHealth(steps: steps, restingHR: rhr) }
        updateRecovery { r in
            if let hrv, hrv > 0 { r.hrv = hrv }
            if let rhr, rhr > 0 { r.rhr = rhr }
            if let sleep, sleep > 0 { r.sleepH = sleep }
            if let deep, deep > 0 { r.deepH = deep }
            if let rem, rem > 0 { r.remH = rem }
        }
        showToast("Synced! \((steps ?? healthToday?.steps ?? 0).formatted()) steps ✓")
    }

    /// fatlosscoach://sync?hrv=45&rhr=52&sleep=7.2&deep=1.4&rem=1.8&resp=14&mood=4&steps=7500
    func handle(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return }
        var q: [String: Double] = [:]
        for it in items { if let v = it.value.flatMap(Fmt.parse) { q[it.name] = v } }
        guard !q.isEmpty else { return }
        updateRecovery { r in
            if let v = q["hrv"] { r.hrv = v }
            if let v = q["rhr"] { r.rhr = v }
            if let v = q["sleep"] { r.sleepH = v }
            if let v = q["deep"] { r.deepH = v }
            if let v = q["rem"] { r.remH = v }
            if let v = q["resp"] { r.resp = v }
            if let v = q["mood"] { r.mood = Int(v) }
        }
        if q["steps"] != nil || q["rhr"] != nil {
            setHealth(steps: q["steps"].map { Int($0) }, restingHR: q["rhr"])
        }
        showToast("Apple Health synced ✓ 🍎")
    }

    // MARK: Toast

    func showToast(_ msg: String) {
        toastTask?.cancel()
        toast = msg
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
