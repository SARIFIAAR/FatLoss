import Foundation

/// WHOOP-style scores computed on-device from the HealthKit data the app already syncs.
/// All three scores are personal-baseline models, not absolute thresholds: the first week of
/// data "calibrates" (returns nil) and every metric is judged against a rolling 28-day window.
enum BodyMetrics {

    static let baselineDays = 28
    /// Minimum nights of HRV history before scores are trusted (matches the calibration idea).
    static let minCalibrationDays = 7

    // MARK: Baselines

    struct Baseline {
        var mean: Double
        var sd: Double
        func z(_ v: Double) -> Double { sd > 0 ? (v - mean) / sd : 0 }
    }

    static func baseline(_ values: [Double]) -> Baseline? {
        let vs = values.filter { $0 > 0 }
        guard vs.count >= minCalibrationDays else { return nil }
        let mean = vs.reduce(0, +) / Double(vs.count)
        let sd = sqrt(vs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(vs.count))
        return Baseline(mean: mean, sd: max(sd, mean * 0.02))   // floor sd so one flat week can't explode z
    }

    /// Logistic squash of a z-score into 0...1 (z = 0 → 0.5, ±2 → ~0.88/0.12).
    private static func squash(_ z: Double) -> Double { 1 / (1 + exp(-1.1 * z)) }

    // MARK: Recovery (0–100 %)

    struct Recovery {
        var score: Int                 // 0–100
        var hrvScore: Double?          // component contributions 0...1, for the detail rows
        var rhrScore: Double?
        var sleepScore: Double?
        var respScore: Double?
        var tempScore: Double?
        var spo2Score: Double?

        enum Zone { case red, yellow, green }
        var zone: Zone { score <= 33 ? .red : score <= 66 ? .yellow : .green }
    }

    /// HRV is log-normal, so its z-score uses ln(HRV). Weights: HRV 40 · RHR 22 · sleep 18 ·
    /// resp 8 · wrist temp 8 · SpO2 4, reweighted over whichever inputs exist. Elevated resp
    /// and elevated temp count against recovery; low values are neutral.
    static func recovery(day: RecoveryDay,
                         hrvHistory: [Double], rhrHistory: [Double], respHistory: [Double],
                         tempHistory: [Double] = [], spo2History: [Double] = [],
                         sleepPerformance: Double?) -> Recovery? {
        guard let hrv = day.hrv, hrv > 0,
              let hrvBase = baseline(hrvHistory.map(log)) else { return nil }

        var weights = 0.0, total = 0.0
        var out = Recovery(score: 0)

        let hrvS = squash(hrvBase.z(log(hrv)))
        out.hrvScore = hrvS; total += 0.40 * hrvS; weights += 0.40

        if let rhr = day.rhr, rhr > 0, let base = baseline(rhrHistory) {
            let s = squash(-base.z(rhr))
            out.rhrScore = s; total += 0.22 * s; weights += 0.22
        }
        if let perf = sleepPerformance {
            let s = min(1, perf / 100)
            out.sleepScore = s; total += 0.18 * s; weights += 0.18
        }
        if let resp = day.resp, resp > 0, let base = baseline(respHistory) {
            let s = squash(-max(0, base.z(resp)) * 1.5 + 0.9)   // only elevated resp penalises
            out.respScore = s; total += 0.08 * s; weights += 0.08
        }
        if let t = day.tempC, t > 30, let base = baseline(tempHistory) {
            let s = squash(-max(0, base.z(t)) * 1.5 + 0.9)      // only elevated temp penalises
            out.tempScore = s; total += 0.08 * s; weights += 0.08
        }
        if let o = day.spo2, o > 0, let base = baseline(spo2History) {
            let s = squash(-max(0, -base.z(o)) * 1.2 + 0.9)     // only depressed SpO2 penalises
            out.spo2Score = s; total += 0.04 * s; weights += 0.04
        }

        out.score = max(1, min(99, Int((total / weights * 100).rounded())))
        return out
    }

    // MARK: Strain (0–21)

    struct Strain {
        var score: Double              // 0–21
        var label: String {
            score < 10 ? "Light" : score < 14 ? "Moderate" : score < 18 ? "High" : "All Out"
        }
    }

    /// Daily load = the stronger of two signals, each normalised against a personal
    /// 90th-percentile cap: active energy (steps fill in phone-only days at ~35 kcal/1000)
    /// and Edwards TRIMP from workout HR zones (zone 1–5 minutes × 1–5). The 0–21 scale is
    /// logarithmic: doubling the load does not double the score.
    static func strain(activeKcal: Double?, steps: Int, workouts: [WorkoutEntry],
                       capKcal: Double, capTrimp: Double) -> Strain {
        let kcalLoad = max(activeKcal ?? 0, Double(steps) * 0.035)
        let xKcal = kcalLoad / max(capKcal, 300)
        let xTrimp = trimp(workouts) / max(capTrimp, 60)
        let x = max(xKcal, xTrimp)
        guard x > 0 else { return Strain(score: 0) }
        return Strain(score: min(21, 21 * (1 - exp(-1.2 * x))))
    }

    /// Edwards TRIMP: minutes in HR zone n weighted by n.
    static func trimp(_ workouts: [WorkoutEntry]) -> Double {
        var total = 0.0
        for w in workouts {
            for (i, mins) in w.zoneMin.enumerated() where i < 5 {
                total += mins * Double(i + 1)
            }
        }
        return total
    }

    /// Per-workout strain on the same 0–21 curve (TRIMP when HR exists, else kcal).
    static func workoutStrain(_ w: WorkoutEntry, capKcal: Double, capTrimp: Double) -> Double {
        let t = trimp([w])
        let x = t > 0 ? t / max(capTrimp, 60) : (w.kcal ?? 0) / max(capKcal, 300)
        return min(21, 21 * (1 - exp(-1.2 * x)))
    }

    static func cap(_ history: [Double], floor: Double) -> Double {
        let vs = history.filter { $0 > 0 }.sorted()
        guard !vs.isEmpty else { return floor * 2 }
        return max(floor, vs[min(vs.count - 1, Int(Double(vs.count) * 0.9))])
    }

    /// Recovery-dependent strain target band (green → push, red → rest), mirroring the
    /// "optimal strain from recovery" mapping idea.
    static func targetStrain(recovery: Int) -> ClosedRange<Double> {
        let t = 6 + Double(recovery) / 100 * 12         // 6...18
        return (t - 2)...min(21, t + 1.5)
    }

    // MARK: Sleep need & performance

    struct SleepNeed {
        var baseline: Double
        var debt: Double
        var strainCredit: Double
        var total: Double { baseline + debt + strainCredit }
    }

    /// need = baseline + 50 % of the shortfall of the last two nights (capped 2 h)
    ///        + a credit after high-strain days. Performance = slept / need.
    static func sleepNeed(baselineH: Double, lastNights: [Double?], yesterdayStrain: Double?) -> SleepNeed {
        let shortfall = lastNights.prefix(2).compactMap { $0 }.map { max(0, baselineH - $0) }.reduce(0, +)
        let credit: Double = (yesterdayStrain ?? 0) >= 14 ? 0.5 : (yesterdayStrain ?? 0) >= 10 ? 0.25 : 0
        return SleepNeed(baseline: baselineH, debt: min(2, shortfall * 0.5), strainCredit: credit)
    }

    static func sleepPerformance(slept: Double?, need: SleepNeed) -> Double? {
        guard let slept, slept > 0 else { return nil }
        return min(100, slept / need.total * 100)
    }

    // MARK: Sleep consistency

    /// Spread of bedtime over the last nights: ± minutes from the median. Nil until 3 nights.
    /// Times are measured as minutes since 6 PM so a midnight crossing doesn't wrap.
    static func consistencyMinutes(bedTimes: [Date]) -> Int? {
        guard bedTimes.count >= 3 else { return nil }
        let cal = Calendar.current
        let mins = bedTimes.map { t -> Double in
            let c = cal.dateComponents([.hour, .minute], from: t)
            let m = Double(c.hour! * 60 + c.minute!) - 18 * 60
            return m < 0 ? m + 24 * 60 : m
        }
        let med = mins.sorted()[mins.count / 2]
        let dev = mins.map { abs($0 - med) }.reduce(0, +) / Double(mins.count)
        return Int(dev.rounded())
    }

    // MARK: Vitals typical ranges (health-monitor style)

    struct VitalRange {
        var low: Double
        var high: Double
        func contains(_ v: Double) -> Bool { v >= low && v <= high }
    }

    static func typicalRange(_ history: [Double]) -> VitalRange? {
        guard let b = baseline(history) else { return nil }
        return VitalRange(low: b.mean - 1.5 * b.sd, high: b.mean + 1.5 * b.sd)
    }
}

// MARK: - Store convenience

extension Store {
    /// History for one recovery field over the baseline window, excluding today
    /// (today's value is the one being judged).
    func bodyHistory(_ keyPath: KeyPath<RecoveryDay, Double?>, days: Int = BodyMetrics.baselineDays) -> [Double] {
        (1...days).compactMap { n in
            let v = data.recovery[DateKey.key(DateKey.daysAgo(n))]?[keyPath: keyPath]
            return (v ?? 0) > 0 ? v : nil
        }
    }

    func activeKcalHistory(days: Int = BodyMetrics.baselineDays) -> [Double] {
        (1...days).compactMap { n in data.health[DateKey.key(DateKey.daysAgo(n))]?.activeKcal }
    }

    func trimpHistory(days: Int = BodyMetrics.baselineDays) -> [Double] {
        (1...days).map { n in BodyMetrics.trimp(data.workouts[DateKey.key(DateKey.daysAgo(n))] ?? []) }
    }

    func setWorkouts(_ list: [WorkoutEntry], on day: String) {
        if list.isEmpty { data.workouts.removeValue(forKey: day) } else { data.workouts[day] = list }
    }

    /// The full day-score bundle for any date.
    func bodyDay(_ key: String? = nil) -> BodyDayScores {
        let k = key ?? today
        let rec = data.recovery[k] ?? RecoveryDay()
        let health = data.health[k]
        let workouts = data.workouts[k] ?? []
        let yesterdayKey = DateKey.key(DateKey.daysAgo(1))

        let capKcal = BodyMetrics.cap(activeKcalHistory(), floor: 300)
        let capTrimp = BodyMetrics.cap(trimpHistory(), floor: 60)
        let strain = BodyMetrics.strain(activeKcal: health?.activeKcal, steps: health?.steps ?? 0,
                                        workouts: workouts, capKcal: capKcal, capTrimp: capTrimp)
        let yStrain = data.health[yesterdayKey].map {
            BodyMetrics.strain(activeKcal: $0.activeKcal, steps: $0.steps,
                               workouts: data.workouts[yesterdayKey] ?? [],
                               capKcal: capKcal, capTrimp: capTrimp).score
        }

        let lastNights: [Double?] = (1...2).map { data.recovery[DateKey.key(DateKey.daysAgo($0))]?.sleepH }
        let need = BodyMetrics.sleepNeed(baselineH: 8, lastNights: lastNights, yesterdayStrain: yStrain)
        let perf = BodyMetrics.sleepPerformance(slept: rec.sleepH, need: need)

        let recovery = BodyMetrics.recovery(day: rec,
                                            hrvHistory: bodyHistory(\.hrv),
                                            rhrHistory: bodyHistory(\.rhr),
                                            respHistory: bodyHistory(\.resp),
                                            tempHistory: bodyHistory(\.tempC),
                                            spo2History: bodyHistory(\.spo2),
                                            sleepPerformance: perf)
        return BodyDayScores(day: rec, health: health, workouts: workouts, recovery: recovery,
                             strain: strain, sleepNeed: need, sleepPerformance: perf,
                             capKcal: capKcal, capTrimp: capTrimp)
    }

    /// Bedtimes of the last `nights` (for the consistency metric).
    func recentBedTimes(nights: Int = 4) -> [Date] {
        (0..<nights).compactMap { data.recovery[DateKey.key(DateKey.daysAgo($0))]?.bedTime }
    }

    // MARK: Behavior impacts (journal-style)

    /// For each habit/supplement: average next-day recovery on days it was logged vs days it
    /// wasn't, over the last 60 days. Needs >=4 samples on each side to report.
    func behaviorImpacts(days: Int = 60) -> [BehaviorImpact] {
        var recoveryByDay: [String: Int] = [:]
        for n in 0..<days {
            let k = DateKey.key(DateKey.daysAgo(n))
            if let r = bodyDay(k).recovery { recoveryByDay[k] = r.score }
        }
        var out: [BehaviorImpact] = []
        let allNames = Set(data.habits.values.flatMap { $0 }).union(data.supplements.values.flatMap { $0 })
        for name in allNames {
            var with: [Int] = [], without: [Int] = []
            for n in 1..<days {
                let day = DateKey.key(DateKey.daysAgo(n))
                let next = DateKey.key(DateKey.daysAgo(n - 1))
                guard let r = recoveryByDay[next] else { continue }
                let logged = (data.habits[day]?.contains(name) ?? false)
                    || (data.supplements[day]?.contains(name) ?? false)
                logged ? with.append(r) : without.append(r)
            }
            guard with.count >= 4, without.count >= 4 else { continue }
            let delta = Double(with.reduce(0, +)) / Double(with.count)
                      - Double(without.reduce(0, +)) / Double(without.count)
            out.append(BehaviorImpact(name: name, delta: delta, sampleCount: with.count))
        }
        return out.sorted { abs($0.delta) > abs($1.delta) }
    }

    // MARK: Week in review

    func weekReport() -> WeekReport {
        var recoveries: [Int] = [], strains: [Double] = [], sleeps: [Double] = []
        var debt = 0.0, deficits: [Double] = []
        for n in 0..<7 {
            let k = DateKey.key(DateKey.daysAgo(n))
            let s = bodyDay(k)
            if let r = s.recovery { recoveries.append(r.score) }
            if s.strain.score > 0 { strains.append(s.strain.score) }
            if let h = s.day.sleepH, h > 0 {
                sleeps.append(h)
                debt += max(0, s.sleepNeed.total - h)
            }
            if let burned = s.health?.burnedKcal {
                let eaten = (data.meals[k] ?? []).reduce(0) { $0 + $1.kcal }
                if eaten > 0 { deficits.append(burned - eaten) }
            }
        }
        let weights = data.weightLogs.suffix(14)
        let delta: Double? = weights.count >= 2 ? weights.last!.value - weights.first!.value : nil
        func avg(_ v: [Int]) -> Int? { v.isEmpty ? nil : v.reduce(0, +) / v.count }
        func avgD(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return WeekReport(avgRecovery: avg(recoveries), avgStrain: avgD(strains),
                          avgSleep: avgD(sleeps), sleepDebt: debt,
                          avgDeficit: avgD(deficits), weightDelta: delta)
    }
}

struct BodyDayScores {
    var day: RecoveryDay
    var health: HealthDay?
    var workouts: [WorkoutEntry] = []
    var recovery: BodyMetrics.Recovery?
    var strain: BodyMetrics.Strain
    var sleepNeed: BodyMetrics.SleepNeed
    var sleepPerformance: Double?
    var capKcal: Double = 600
    var capTrimp: Double = 120
}

struct BehaviorImpact: Identifiable {
    var name: String
    var delta: Double          // percentage points of next-day recovery
    var sampleCount: Int
    var id: String { name }
}

struct WeekReport {
    var avgRecovery: Int?
    var avgStrain: Double?
    var avgSleep: Double?
    var sleepDebt: Double
    var avgDeficit: Double?
    var weightDelta: Double?
}
