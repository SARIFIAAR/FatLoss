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
            if !isApplyingRemote { lastModified = Date() }
            scheduleSave()
            if !isApplyingRemote { onChange?() }
        }
    }
    /// Kept outside `data` so writes don't observe themselves. Stamped into `updatedAt` on save/export/push.
    var lastModified: Date
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
    }

    /// `data` with the current modification time stamped in — what gets persisted and synced.
    func snapshot() -> AppData {
        var d = data
        d.updatedAt = lastModified
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
        d.dateDecodingStrategy = .iso8601
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
    }
    /// Percent of the last `days` days on which the supplement was taken.
    func adherence(_ key: String, days: Int = 7) -> Int {
        let taken = (0..<days).filter { data.supplements[DateKey.key(DateKey.daysAgo($0))]?.contains(key) ?? false }.count
        return Int((Double(taken) / Double(days) * 100).rounded())
    }

    // MARK: Water

    var waterToday: Int { data.water[today] ?? 0 }
    func addWater(_ ml: Int) {
        data.water[today] = min(waterToday + ml, Plan.maxWaterPerDay)
        showToast("+\(ml) ml 💧")
    }
    func resetWater() { data.water[today] = 0 }

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

    func setHealth(steps: Int? = nil, restingHR: Double? = nil, on day: String? = nil) {
        let k = day ?? today
        var h = data.health[k] ?? HealthDay()
        if let steps { h.steps = steps }
        if let restingHR { h.restingHR = restingHR }
        data.health[k] = h
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
