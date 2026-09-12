import SwiftUI

/// Full-screen deep-dive for one pillar: hero gauge, day stats, 30-day trend bars.
struct PillarDetailView: View {
    let pillar: Pillar
    let dayOffset: Int
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var dateKey: String { DateKey.key(DateKey.daysAgo(dayOffset)) }
    private var scores: BodyDayScores { store.bodyDay(dateKey) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topBar
                hero
                statsCard
                trendCard
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(W.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(W.text)
                    .frame(width: 36, height: 36).background(W.card).clipShape(Circle())
            }
            Spacer()
            Text(title.uppercased()).font(W.label(13)).kerning(1.5).foregroundStyle(W.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }

    private var title: String {
        switch pillar {
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .strain: "Strain"
        }
    }

    // MARK: Hero gauge

    private var hero: some View {
        VStack(spacing: 4) {
            switch pillar {
            case .sleep:
                RingGauge(title: "Performance",
                          value: scores.sleepPerformance.map { "\(Int($0))%" } ?? "–",
                          fraction: (scores.sleepPerformance ?? 0) / 100,
                          color: W.sleep, size: 190, valueSize: 54)
            case .recovery:
                RingGauge(title: recoveryVerdict,
                          value: scores.recovery.map { "\($0.score)%" } ?? "–",
                          fraction: Double(scores.recovery?.score ?? 0) / 100,
                          color: scores.recovery.map { W.recoveryColor($0.zone) } ?? W.muted,
                          size: 190, valueSize: 54)
            case .strain:
                RingGauge(title: scores.strain.score > 0 ? scores.strain.label : "No activity",
                          value: String(format: "%.1f", scores.strain.score),
                          fraction: scores.strain.score / 21,
                          color: W.blue, size: 190, valueSize: 54)
            }
        }
        .padding(.vertical, 10)
    }

    private var recoveryVerdict: String {
        guard let r = scores.recovery else { return "Calibrating" }
        return r.zone == .green ? "Primed to push" : r.zone == .yellow ? "Maintain today" : "Prioritise rest"
    }

    // MARK: Day stats

    private var statsCard: some View {
        DarkCard {
            CardTitle(statsTitle, "", chevron: false) {}
            DividedRows(rows: statsRows)
        }
    }

    private var statsRows: [AnyView] {
        switch pillar {
        case .sleep:
            var rows: [AnyView] = [
                AnyView(row("Time asleep", scores.day.sleepH.map(BodyView.hm) ?? "–")),
                AnyView(row("Sleep need", BodyView.hm(scores.sleepNeed.total))),
                AnyView(row("Baseline need", BodyView.hm(scores.sleepNeed.baseline))),
            ]
            if scores.sleepNeed.debt > 0.01 { rows.append(AnyView(row("Sleep debt carried", BodyView.hm(scores.sleepNeed.debt)))) }
            if scores.sleepNeed.strainCredit > 0 { rows.append(AnyView(row("Strain credit", BodyView.hm(scores.sleepNeed.strainCredit)))) }
            rows.append(AnyView(row("Deep", scores.day.deepH.map(BodyView.hm) ?? "–")))
            rows.append(AnyView(row("REM", scores.day.remH.map(BodyView.hm) ?? "–")))
            if let b = scores.day.inBedH { rows.append(AnyView(row("Time in bed", BodyView.hm(b)))) }
            if let e = scores.day.efficiency { rows.append(AnyView(row("Efficiency", "\(Int(e))%"))) }
            if let c = BodyMetrics.consistencyMinutes(bedTimes: store.recentBedTimes()) {
                rows.append(AnyView(row("Bedtime consistency", "±\(c) min")))
            }
            if let a = scores.day.awakeCount, a > 0 { rows.append(AnyView(row("Disturbances", "\(a)"))) }
            return rows
        case .recovery:
            return [
                AnyView(componentRow("HRV", scores.day.hrv.map { "\(Int($0.rounded())) ms" }, scores.recovery?.hrvScore)),
                AnyView(componentRow("Resting HR", scores.day.rhr.map { "\(Int($0.rounded())) bpm" }, scores.recovery?.rhrScore)),
                AnyView(componentRow("Sleep", scores.sleepPerformance.map { "\(Int($0))%" }, scores.recovery?.sleepScore)),
                AnyView(componentRow("Respiratory rate", scores.day.resp.map { "\(Int($0.rounded())) rpm" }, scores.recovery?.respScore)),
            ]
        case .strain:
            var rows: [AnyView] = []
            if let r = scores.recovery {
                let t = BodyMetrics.targetStrain(recovery: r.score)
                rows.append(AnyView(row("Target strain", "\(String(format: "%.1f", t.lowerBound))–\(String(format: "%.1f", t.upperBound))")))
            }
            rows.append(AnyView(row("Active energy", scores.health?.activeKcal.map { "\(Int($0)) kcal" } ?? "–")))
            rows.append(AnyView(row("Total burn", scores.health?.burnedKcal.map { "\(Int($0)) kcal" } ?? "–")))
            rows.append(AnyView(row("Steps", (scores.health?.steps).map { $0.formatted() } ?? "–")))
            for w in scores.workouts {
                let s = BodyMetrics.workoutStrain(w, capKcal: scores.capKcal, capTrimp: scores.capTrimp)
                rows.append(AnyView(row("\(w.name) · \(Int(w.minutes)) min"
                                        + (w.avgHR.map { " · \(Int($0)) bpm" } ?? ""),
                                        String(format: "%.1f", s))))
            }
            return rows
        }
    }

    private var statsTitle: String {
        switch pillar {
        case .sleep: "Last night"
        case .recovery: "Contributors"
        case .strain: "Day activity"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(W.muted)
            Spacer()
            Text(value).font(W.score(17)).foregroundStyle(W.text)
        }
        .padding(.vertical, 9)
    }

    /// Contributor row with a small bar showing how much this input helped (0...1).
    private func componentRow(_ label: String, _ value: String?, _ score: Double?) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13)).foregroundStyle(W.muted)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.card2)
                    if let score {
                        Capsule()
                            .fill(score >= 0.6 ? W.green : score >= 0.4 ? W.yellow : W.red)
                            .frame(width: max(4, geo.size.width * score))
                    }
                }
            }
            .frame(height: 6)
            Text(value ?? "–").font(W.score(14)).foregroundStyle(W.text)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    // MARK: 30-day trend

    private var trendCard: some View {
        let bars = trendBars()
        return DarkCard {
            CardTitle("Last 30 days", trendSub, chevron: false) {}
            if bars.allSatisfy({ $0.value <= 0 }) {
                Text("No data yet").font(.system(size: 12)).foregroundStyle(W.muted).padding(.vertical, 20)
            } else {
                TrendBarChart(bars: bars, maxValue: trendMax)
                    .frame(height: 110)
                    .padding(.top, 4)
            }
        }
    }

    private var trendSub: String {
        switch pillar {
        case .sleep: "hours slept"
        case .recovery: "recovery %"
        case .strain: "day strain"
        }
    }

    private var trendMax: Double {
        switch pillar {
        case .sleep: 10
        case .recovery: 100
        case .strain: 21
        }
    }

    private func trendBars() -> [TrendBar] {
        (0..<30).reversed().map { n in
            let s = store.bodyDay(DateKey.key(DateKey.daysAgo(n)))
            switch pillar {
            case .sleep:
                let h = s.day.sleepH ?? 0
                let hitNeed = h >= s.sleepNeed.total * 0.9
                return TrendBar(daysAgo: n, value: h, color: hitNeed ? W.vibrant : W.sleep)
            case .recovery:
                let v = s.recovery.map { Double($0.score) } ?? 0
                let c = s.recovery.map { W.recoveryColor($0.zone) } ?? W.card2
                return TrendBar(daysAgo: n, value: v, color: c)
            case .strain:
                return TrendBar(daysAgo: n, value: s.strain.score, color: W.blue)
            }
        }
    }
}

struct TrendBar: Identifiable {
    let daysAgo: Int
    let value: Double
    let color: Color
    var id: Int { daysAgo }
}

struct TrendBarChart: View {
    let bars: [TrendBar]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let w = max(2, (geo.size.width - CGFloat(bars.count - 1) * 2) / CGFloat(bars.count))
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bars) { bar in
                    Capsule()
                        .fill(bar.value > 0 ? bar.color : W.card2)
                        .frame(width: w, height: max(3, geo.size.height * bar.value / maxValue))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
