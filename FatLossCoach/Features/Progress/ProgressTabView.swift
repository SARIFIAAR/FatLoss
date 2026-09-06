import SwiftUI
import Charts

struct ProgressTabView: View {
    @Environment(Store.self) private var store
    @State private var showWaist = false

    var body: some View {
        let g = store.data.goals
        Screen(subtitle: "Toward your goal", title: "Progress 📊") {
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
            streakCard
            adherenceCard
        }
        .sheet(isPresented: $showWaist) {
            LogValueSheet(title: "📏 Log Waist Circumference", placeholder: "e.g. 102 cm") { store.logWaist($0) }
        }
    }

    private var goalCard: some View {
        let g = store.data.goals
        let w = store.currentWeight ?? g.startWeight
        return Card {
            SectionTitle("Weight Goal")
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
            SectionTitle("📏 Waist Circumference")
            HStack {
                Text(store.currentWaist.map { "\(Fmt.num($0)) cm" } ?? "– cm")
                    .font(.system(size: 28, weight: .black)).foregroundStyle(Theme.orange)
                Text("Target: <\(Fmt.num(g.waistTarget)) cm").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.leading, 6)
                Spacer()
                Button("+ Log") { showWaist = true }.buttonStyle(PillButtonStyle())
            }
            .padding(.bottom, 8)
            LineChartView(points: store.waistSeries(days: 30), color: Theme.orange, days: 30, unit: "cm")
        }
    }

    private var streakCard: some View {
        Card {
            SectionTitle("Habit Streak — Last 28 Days")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach((0..<28).reversed(), id: \.self) { back in
                    let count = store.habitCount(on: DateKey.key(DateKey.daysAgo(back)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(streakColor(count))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            HStack(spacing: 8) {
                legend(Theme.border, "0"); legend(Color(hex: 0xB7E4C7), "1-2"); legend(Theme.accent, "3-4"); legend(Theme.primary, "5-6")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.muted)
            .padding(.top, 10)
        }
    }

    private func streakColor(_ n: Int) -> Color {
        n == 0 ? Theme.border : n <= 2 ? Color(hex: 0xB7E4C7) : n <= 4 ? Theme.accent : Theme.primary
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12)
            Text(t)
        }
    }

    private var adherenceCard: some View {
        Card {
            SectionTitle("Supplement Adherence (7 days)")
            VStack(spacing: 0) {
                ForEach(Array(Plan.supplements.filter { Plan.trackedSupplements.contains($0.key) }.enumerated()), id: \.element.id) { i, s in
                    HStack {
                        Text(s.name).font(.system(size: 15)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(store.adherence(s.key))%").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.primary)
                    }
                    .padding(.vertical, 9)
                    if i < Plan.trackedSupplements.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }
}

// MARK: - Charts

struct EmptyChart: View {
    var text = "No data yet"
    var body: some View {
        Text(text)
            .font(.system(size: 13)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 170)
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
