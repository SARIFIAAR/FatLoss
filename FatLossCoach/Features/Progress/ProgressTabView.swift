import SwiftUI
import Charts

struct ProgressTabView: View {
    @Environment(Store.self) private var store
    @State private var showWaist = false
    @State private var showWeight = false

    var body: some View {
        let g = store.data.goals
        // Debug/QA (screenshots): `-progressScroll photos` scrolls to the progress-photos card on appear,
        // matching the app's `-bodyScroll` convention (no effect in production).
        let scrollTo = UserDefaults.standard.string(forKey: "progressScroll")
        Screen(subtitle: "Toward your goal", title: "Progress", scrollTo: scrollTo) {
            WeeklyRecapCard()
            ProgressPhotosCard().id("photos")
            goalCard
            waistCard
            Card {
                SectionTitle("Weight — Last 30 Days")
                LineChartView(points: store.weightSeries(days: 30), color: Theme.primary, days: 30,
                              goal: g.goalWeight, unit: "kg")
            }
            Card {
                SectionTitle("Daily Calories — Last 7 Days")
                CaloriesChartView(points: store.macroKcalSeries(days: 7), target: Double(g.kcal))
            }
            Card {
                SectionTitle("Energy Balance — Last 7 Days")
                EnergyChartView(points: store.energySeries(days: 7), goalDeficit: Double(g.deficit))
            }
            Card {
                SectionTitle("Weekly Steps")
                StepsChartView(points: store.stepsSeries(days: 7), goal: Double(g.stepsGoal))
            }
            Card {
                SectionTitle("HRV — Last 30 Nights")
                LineChartView(points: store.recoverySeries(days: 30, \.hrv), color: Theme.blue, days: 30,
                              yDomain: 0...100, unit: "ms")
            }
            Card {
                SectionTitle("Sleep — Last 14 Nights")
                SleepChartView(series: [
                    SleepSeries(name: "Total", points: store.recoverySeries(days: 14, \.sleepH)),
                    SleepSeries(name: "Deep", points: store.recoverySeries(days: 14, \.deepH)),
                    SleepSeries(name: "REM", points: store.recoverySeries(days: 14, \.remH)),
                ])
            }
            HabitProgressCard().id("habits")
            adherenceCard
        }
        .sheet(isPresented: $showWaist) {
            LogValueSheet(title: "Log Waist Circumference", placeholder: "e.g. 102 cm") { store.logWaist($0) }
        }
        .sheet(isPresented: $showWeight) {
            LogValueSheet(title: "Log Today's Weight", placeholder: "e.g. 105.4") { store.logWeight($0) }
        }
    }

    /// Uppercased section title with a standard "+" add button on the right.
    private func addTitle(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(color)
            }
        }
        .padding(.bottom, 10)
    }

    private var goalCard: some View {
        let g = store.data.goals
        let w = store.currentWeight ?? g.startWeight
        return Card {
            addTitle("Weight Goal", color: Theme.primary) { showWeight = true }
            HStack(alignment: .firstTextBaseline) {
                Text("\(Fmt.num(w)) kg").font(.system(size: 28, weight: .black)).foregroundStyle(Theme.primary)
                Spacer()
                (Text("Goal: ").foregroundStyle(Theme.muted) + Text("\(Fmt.num(g.goalWeight)) kg").bold().foregroundStyle(Theme.text))
                    .font(.system(size: 13))
            }
            ProgressBar(value: store.goalProgress, height: 14,
                        fill: AnyShapeStyle(LinearGradient(colors: [Theme.orange, Theme.primary], startPoint: .leading, endPoint: .trailing)))
                .padding(.top, 6)
            HStack {
                Text("Start: \(Fmt.num(g.startWeight)) kg")
                Spacer()
                Text("\(String(format: "%.1f", store.kgLost)) kg lost")
                Spacer()
                Text("Goal: \(Fmt.num(g.goalWeight)) kg")
            }
            .font(.system(size: 12)).foregroundStyle(Theme.muted)
            .padding(.top, 4)
        }
    }

    private var waistCard: some View {
        let g = store.data.goals
        return Card {
            addTitle("Waist Circumference", color: Theme.orange) { showWaist = true }
            HStack {
                Text(store.currentWaist.map { "\(Fmt.num($0)) cm" } ?? "– cm")
                    .font(.system(size: 28, weight: .black)).foregroundStyle(Theme.orange)
                Text("Target: <\(Fmt.num(g.waistTarget)) cm").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.leading, 6)
                Spacer()
            }
            .padding(.bottom, 8)
            LineChartView(points: store.waistSeries(days: 30), color: Theme.orange, days: 30, unit: "cm")
        }
    }

    private var adherenceCard: some View {
        // Adherence for exactly what the user tracks (catalog + custom), in tracked order.
        let supps = store.trackedSupplements
        return Group {
            if !supps.isEmpty {
                Card {
                    SectionTitle("Supplement Adherence (7 days)")
                    VStack(spacing: 0) {
                        ForEach(Array(supps.enumerated()), id: \.element.id) { i, s in
                            HStack {
                                Text(s.name).font(.system(size: 15)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(store.adherence(s.id))%").font(Theme.scoreS).foregroundStyle(Theme.primary)
                            }
                            .padding(.vertical, 9)
                            if i < supps.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Charts

struct EmptyChart: View {
    var text = "No data yet"
    var icon = "chart.line.uptrend.xyaxis"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light)).foregroundStyle(Theme.muted.opacity(0.5))
            Text(text)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct LineChartView: View {
    let points: [DatedValue]
    let color: Color
    var days: Int = 30
    var goal: Double? = nil
    var yDomain: ClosedRange<Double>? = nil
    var unit: String = ""

    private var xDomain: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: DateKey.daysAgo(0)) ?? Date()
        return DateKey.daysAgo(days - 1)...end
    }

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        var vals = points.map(\.value)
        if let goal { vals.append(goal) }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        if points.isEmpty {
            EmptyChart()
        } else {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Date", p.date, unit: .day), yStart: .value("Base", domain.lowerBound), yEnd: .value(unit, p.value))
                        .foregroundStyle(color.opacity(0.1))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", p.date, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(color)
                        .symbolSize(22)
                }
                if let goal {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(Theme.red)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, days / 6))) {
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 170)
        }
    }
}

struct StepsChartView: View {
    let points: [DatedValue]
    let goal: Double

    var body: some View {
        let top = max(12000, (points.map(\.value).max() ?? 0) * 1.1)
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Steps", p.value))
                    .foregroundStyle(p.value >= goal ? Theme.primary : Theme.accent.opacity(0.8))
                    .cornerRadius(5)
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(Theme.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Goal").font(.system(size: 9)).foregroundStyle(Theme.red)
                }
        }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 170)
    }
}

/// Eaten (logged meals) vs burned (Apple Watch active + basal) per day, with the resulting deficit.
struct EnergyChartView: View {
    let points: [Store.EnergyDay]
    let goalDeficit: Double

    struct Bar: Identifiable {
        let date: Date; let kind: String; let kcal: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind)" }
    }

    var body: some View {
        let hasBurn = points.contains { $0.burned != nil }
        let hasFood = points.contains { $0.eaten > 0 }
        if !hasBurn || !hasFood {
            EmptyChart(text: hasBurn ? "Scan meals to compare with what you burn"
                                     : "Connect Apple Health (Profile) to see calories burned")
        } else {
            let bars = points.flatMap { p -> [Bar] in
                [Bar(date: p.date, kind: "Eaten", kcal: p.eaten), Bar(date: p.date, kind: "Burned", kcal: p.burned ?? 0)]
            }
            let top = (bars.map(\.kcal).max() ?? 0) * 1.15
            let deficits = points.compactMap(\.deficit)
            let avg = deficits.isEmpty ? nil : deficits.reduce(0, +) / Double(deficits.count)
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(bars) { b in
                        BarMark(x: .value("Day", b.date, unit: .day), y: .value("kcal", b.kcal))
                            .foregroundStyle(by: .value("Kind", b.kind))
                            .position(by: .value("Kind", b.kind))
                            .cornerRadius(3)
                    }
                    ForEach(points.filter { $0.deficit != nil }) { p in
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.burned ?? 0))
                            .symbolSize(0)
                            .annotation(position: .top, spacing: 2) {
                                let d = p.deficit ?? 0
                                Text(d >= 0 ? "−\(Int(d))" : "+\(Int(-d))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(d >= goalDeficit ? Theme.primary : d >= 0 ? Theme.blue : Theme.red)
                            }
                    }
                }
                .chartForegroundStyleScale(["Eaten": Theme.primary, "Burned": Theme.orange])
                .chartYScale(domain: 0...max(top, 1000))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .frame(height: 200)
                if let avg {
                    Text("Average \(avg >= 0 ? "deficit" : "surplus") \(Int(abs(avg))) kcal/day over \(deficits.count) day\(deficits.count == 1 ? "" : "s") · goal \(Int(goalDeficit)) · burned = Watch active + resting energy")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

struct CaloriesChartView: View {
    let points: [Store.MacroKcal]
    let target: Double

    var body: some View {
        if points.allSatisfy({ $0.kcal == 0 }) {
            EmptyChart(text: "Scan or log meals to see calories here")
        } else {
            let dayTotals = Dictionary(grouping: points, by: \.date).mapValues { $0.reduce(0) { $0 + $1.kcal } }
            let top = max(target * 1.15, (dayTotals.values.max() ?? 0) * 1.1)
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.kcal))
                        .foregroundStyle(by: .value("Macro", p.macro))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(Int(target))").font(.system(size: 9)).foregroundStyle(Theme.red)
                    }
            }
            .chartForegroundStyleScale(["Protein": Theme.primary, "Carbs": Theme.orange, "Fat": Theme.blue])
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 190)
        }
    }
}

struct SleepSeries: Identifiable {
    let name: String
    let points: [DatedValue]
    var id: String { name }
}

struct SleepChartView: View {
    let series: [SleepSeries]

    private var xDomain: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: DateKey.daysAgo(0)) ?? Date()
        return DateKey.daysAgo(13)...end
    }

    var body: some View {
        if series.allSatisfy({ $0.points.isEmpty }) {
            EmptyChart()
        } else {
            Chart {
                ForEach(series) { s in
                    ForEach(s.points) { p in
                        LineMark(x: .value("Night", p.date, unit: .day), y: .value("Hours", p.value), series: .value("Type", s.name))
                            .foregroundStyle(by: .value("Type", s.name))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Night", p.date, unit: .day), y: .value("Hours", p.value))
                            .foregroundStyle(by: .value("Type", s.name))
                            .symbolSize(18)
                    }
                }
            }
            .chartForegroundStyleScale(["Total": Theme.blue, "Deep": Theme.primary, "REM": Theme.orange])
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) {
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: false)
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 190)
        }
    }
}
