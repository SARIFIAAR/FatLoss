import Foundation

/// A read-only "This week" recap: aggregates the last 7 completed days and compares each metric with the
/// prior 7 days (week-over-week). HONEST BY DESIGN — every metric is optional; a metric is `nil` when there
/// isn't enough data, and the UI renders "—" (or hides the row) rather than inventing a zero. No logging.
///
/// Window: "this week" = day offsets 1...7 (yesterday back a week — today is still in progress, so it's
/// excluded to keep the average honest). "last week" = offsets 8...14. Deltas are this − last.
///
/// Reconciliation with the daily Life Score: this shows the AVERAGE daily Life Score across the week (the
/// same `LifeScore.score` used on the diary, per day, then averaged) — a WEEKLY cadence, deliberately NOT a
/// duplicate of today's single Life Score number. One engine, two cadences.
struct WeeklyRecap {

    /// One metric: this-week value, last-week value, and how to phrase it. Any side may be nil (no data).
    struct Metric: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let thisWeek: Double?
        let lastWeek: Double?
        /// Formats a value for display (e.g. "1,845 kcal", "8,240", "72%").
        let format: (Double) -> String
        /// When true, a HIGHER value is "better" (green ▲). When false, lower is better (e.g. weight, resting
        /// HR). Used only to colour the delta, never to hide it.
        let higherIsBetter: Bool

        var hasThisWeek: Bool { thisWeek != nil }
        /// Signed week-over-week change, or nil when either side is missing.
        var delta: Double? {
            guard let t = thisWeek, let l = lastWeek else { return nil }
            return t - l
        }
        var thisWeekText: String { thisWeek.map(format) ?? "—" }
        var deltaText: String? {
            guard let d = delta else { return nil }
            if abs(d) < 0.0001 { return "no change" }
            return (d > 0 ? "▲ " : "▼ ") + format(abs(d)) + " vs last week"
        }
        /// True when the change is in the "good" direction (for colour only).
        var deltaIsGood: Bool? {
            guard let d = delta, abs(d) >= 0.0001 else { return nil }
            return (d > 0) == higherIsBetter
        }
    }

    var metrics: [Metric]

    /// Whether there's anything at all to show (any metric has this-week data).
    var hasAnyData: Bool { metrics.contains { $0.hasThisWeek } }

    // MARK: Build

    static func build(from store: Store) -> WeeklyRecap {
        let d = store.data
        // Two windows of 7 calendar-day keys each.
        let thisKeys = (1...7).map { DateKey.key(DateKey.daysAgo($0)) }
        let lastKeys = (8...14).map { DateKey.key(DateKey.daysAgo($0)) }

        // Averaging helper that returns nil when no day in the window has the value.
        func avg(_ keys: [String], _ value: (String) -> Double?) -> Double? {
            let vals = keys.compactMap(value)
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        // --- Nutrition: avg daily calories eaten (days with any meal logged) ---
        func eaten(_ k: String) -> Double? {
            let list = d.meals[k] ?? []
            guard !list.isEmpty else { return nil }
            return list.reduce(0) { $0 + $1.kcal }
        }
        // --- Deficit: burned − eaten, only when both sides exist that day ---
        func deficit(_ k: String) -> Double? { store.energy(on: k).deficit }
        // --- Diet quality: the daily Life Score (weekly cadence = its average) ---
        func lifeScore(_ k: String) -> Double? {
            let list = d.meals[k] ?? []
            guard !list.isEmpty else { return nil }
            return LifeScore.score(meals: list, goals: d.goals, planId: d.nutritionPlanId).map(Double.init)
        }
        // --- Activity: steps + active burn (days the Watch reported anything) ---
        func steps(_ k: String) -> Double? {
            let s = d.health[k]?.steps ?? 0
            return s > 0 ? Double(s) : nil
        }
        func activeBurn(_ k: String) -> Double? {
            guard let a = d.health[k]?.activeKcal, a > 0 else { return nil }
            return a
        }
        // --- Water adherence: % of goal, days with any water logged ---
        func waterAdh(_ k: String) -> Double? {
            let ml = d.water[k] ?? 0
            guard ml > 0, d.goals.waterGoal > 0 else { return nil }
            return min(100, Double(ml) / Double(d.goals.waterGoal) * 100)
        }
        // --- Habit completion rate: % of defined habits met per day (only if habits exist) ---
        func habitRate(_ k: String) -> Double? {
            let defs = d.habitDefs
            guard !defs.isEmpty else { return nil }
            let met = defs.filter { store.habitMet($0, on: k) }.count
            return Double(met) / Double(defs.count) * 100
        }
        // --- Recovery / Strain / Sleep from the BodyMetrics engine (when present) ---
        func recovery(_ k: String) -> Double? { store.bodyDay(k).recovery.map { Double($0.score) } }
        func strain(_ k: String) -> Double? { let s = store.bodyDay(k).strain.score; return s > 0 ? s : nil }
        func sleepH(_ k: String) -> Double? { let h = store.bodyDay(k).day.sleepH ?? 0; return h > 0 ? h : nil }

        // --- Weight change: latest logged weight within a window (nil if none) ---
        func latestWeight(_ keys: [String]) -> Double? {
            let earliest = keys.min() ?? ""
            let latest = keys.max() ?? ""
            return d.weightLogs.filter { $0.date >= earliest && $0.date <= latest }
                .max { $0.date < $1.date }?.value
        }

        // Formatters.
        let kcal: (Double) -> String = { "\(Int($0.rounded())) kcal" }
        let count: (Double) -> String = { Int($0.rounded()).formatted() }
        let pct: (Double) -> String = { "\(Int($0.rounded()))%" }
        let score: (Double) -> String = { "\(Int($0.rounded()))" }
        let kg: (Double) -> String = { Fmt.num(($0 * 10).rounded() / 10) + " kg" }
        let hrs: (Double) -> String = { String(format: "%.1f h", $0) }

        var metrics: [Metric] = [
            Metric(id: "kcal", title: "Avg calories eaten", systemImage: "fork.knife",
                   thisWeek: avg(thisKeys, eaten), lastWeek: avg(lastKeys, eaten),
                   format: kcal, higherIsBetter: false),
            Metric(id: "deficit", title: "Avg daily deficit", systemImage: "flame",
                   thisWeek: avg(thisKeys, deficit), lastWeek: avg(lastKeys, deficit),
                   format: { v in v >= 0 ? "\(Int(v.rounded())) kcal" : "+\(Int((-v).rounded())) kcal" },
                   higherIsBetter: true),
            Metric(id: "life", title: "Avg Life Score", systemImage: "leaf",
                   thisWeek: avg(thisKeys, lifeScore), lastWeek: avg(lastKeys, lifeScore),
                   format: score, higherIsBetter: true),
            Metric(id: "steps", title: "Avg steps", systemImage: "figure.walk",
                   thisWeek: avg(thisKeys, steps), lastWeek: avg(lastKeys, steps),
                   format: count, higherIsBetter: true),
            Metric(id: "burn", title: "Avg active burn", systemImage: "bolt.heart",
                   thisWeek: avg(thisKeys, activeBurn), lastWeek: avg(lastKeys, activeBurn),
                   format: kcal, higherIsBetter: true),
            Metric(id: "water", title: "Water adherence", systemImage: "drop",
                   thisWeek: avg(thisKeys, waterAdh), lastWeek: avg(lastKeys, waterAdh),
                   format: pct, higherIsBetter: true),
            Metric(id: "habits", title: "Habit completion", systemImage: "checkmark.circle",
                   thisWeek: avg(thisKeys, habitRate), lastWeek: avg(lastKeys, habitRate),
                   format: pct, higherIsBetter: true),
            Metric(id: "recovery", title: "Avg recovery", systemImage: "heart",
                   thisWeek: avg(thisKeys, recovery), lastWeek: avg(lastKeys, recovery),
                   format: score, higherIsBetter: true),
            Metric(id: "strain", title: "Avg strain", systemImage: "figure.run",
                   thisWeek: avg(thisKeys, strain), lastWeek: avg(lastKeys, strain),
                   format: { String(format: "%.1f", $0) }, higherIsBetter: true),
            Metric(id: "sleep", title: "Avg sleep", systemImage: "bed.double",
                   thisWeek: avg(thisKeys, sleepH), lastWeek: avg(lastKeys, sleepH),
                   format: hrs, higherIsBetter: true),
        ]

        // Weight change (kg): latest this-week weight vs latest last-week weight. Lower is better.
        metrics.insert(
            Metric(id: "weight", title: "Weight", systemImage: "scalemass",
                   thisWeek: latestWeight(thisKeys), lastWeek: latestWeight(lastKeys),
                   format: kg, higherIsBetter: false),
            at: 3)

        return WeeklyRecap(metrics: metrics)
    }
}
