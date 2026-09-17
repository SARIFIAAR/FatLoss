import SwiftUI

/// Full body-composition analysis for one reading — range-bar metric cards + history trends +
/// segmental lean, in the HUMANS dark design language.
struct BodyAnalysisView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var draft: BodyCompEntry?
    @State private var editingExisting = false

    private var entries: [BodyCompEntry] { store.bodyCompSorted }
    private var entry: BodyCompEntry { entries[min(index, entries.count - 1)] }

    init(startIndex: Int? = nil) {
        _index = State(initialValue: startIndex ?? 0)   // set to last on appear
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topBar
                if entries.isEmpty {
                    Text("No body-composition readings yet.").font(.system(size: 13))
                        .foregroundStyle(W.muted).padding(.top, 40)
                } else {
                    dateSelector
                    scoreCard
                    obesityCard
                    waterCard
                    if let seg = entry.segmentalLean, seg.count == 5 { segmentalCard(seg) }
                    historyCard
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(W.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { if index == 0 { index = max(0, entries.count - 1) } }
        .sheet(item: $draft) { d in
            BodyCompEntrySheet(entry: d, isFromPhoto: false) { saved in
                store.addBodyComp(saved)
                // jump to the newly-saved reading
                if let i = store.bodyCompSorted.firstIndex(where: { $0.id == saved.id }) { index = i }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(W.text)
                    .frame(width: 36, height: 36).background(W.card).clipShape(Circle())
            }
            Spacer()
            Text("BODY ANALYSIS").font(W.label(13)).kerning(1.5).foregroundStyle(W.text)
            Spacer()
            Button {
                draft = BodyCompEntry(date: store.today, weightKg: store.currentWeight ?? 0)
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(W.vibrant)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.top, 8)
    }

    private var dateSelector: some View {
        HStack {
            Button { index = max(0, index - 1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(index > 0 ? W.blue : W.card2)
            }.disabled(index == 0)
            Spacer()
            Menu {
                Button { draft = entry } label: { Label("Edit this reading", systemImage: "pencil") }
                Button(role: .destructive) {
                    let id = entry.id; store.deleteBodyComp(id)
                    index = max(0, min(index, store.bodyCompSorted.count - 1))
                } label: { Label("Delete", systemImage: "trash") }
            } label: {
                HStack(spacing: 5) {
                    Text(prettyDate(entry.date)).font(W.label(13)).foregroundStyle(W.text)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(W.muted)
                }
            }
            Spacer()
            Button { index = min(entries.count - 1, index + 1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(index < entries.count - 1 ? W.blue : W.card2)
            }.disabled(index == entries.count - 1)
        }
        .padding(.vertical, 4)
    }

    // MARK: Cards

    private var scoreCard: some View {
        DarkCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BODY SCORE").font(W.label(10)).kerning(1).foregroundStyle(W.muted)
                    Text(entry.inbodyScore.map { "\(Int($0))" } ?? "–")
                        .font(W.score(40)).foregroundStyle(W.vibrant)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    miniStat("Weight", String(format: "%.1f kg", entry.weightKg))
                    miniStat("Muscle", entry.muscleKg.map { String(format: "%.1f kg", $0) } ?? "–")
                    miniStat("Body fat", entry.bodyFatPct.map { String(format: "%.1f%%", $0) } ?? "–")
                }
            }
        }
    }

    private func miniStat(_ l: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(l).font(.system(size: 11)).foregroundStyle(W.muted)
            Text(v).font(W.score(15)).foregroundStyle(W.text)
        }
    }

    private var obesityCard: some View {
        DarkCard {
            CardTitle("Obesity Analysis", "healthy band shaded", chevron: false) {}
            VStack(spacing: 14) {
                if let bmi = store.bmi { rangeBar("BMI", bmi, "", low: 18.5, high: 25, scaleLo: 15, scaleHi: 35, lowerBetter: nil) }
                if let bf = entry.bodyFatPct {
                    let hi = (store.data.intake?.sex == .female) ? 30.0 : 20.0
                    rangeBar("Percent body fat", bf, "%", low: 10, high: hi, scaleLo: 5, scaleHi: 40, lowerBetter: true)
                }
                if let vl = entry.visceralFat { rangeBar("Visceral fat level", vl, "", low: 1, high: 10, scaleLo: 1, scaleHi: 20, lowerBetter: true) }
                if let va = entry.visceralFatArea { rangeBar("Visceral fat area", va, "cm²", low: 0, high: 100, scaleLo: 0, scaleHi: 200, lowerBetter: true) }
            }
        }
    }

    private var waterCard: some View {
        guard entry.totalBodyWaterL != nil || entry.proteinKg != nil || entry.mineralKg != nil else {
            return AnyView(EmptyView())
        }
        return AnyView(DarkCard {
            CardTitle("Composition", "the building blocks", chevron: false) {}
            DividedRows(rows: [
                entry.totalBodyWaterL.map { AnyView(compRow("Total body water", String(format: "%.1f L", $0))) },
                entry.proteinKg.map { AnyView(compRow("Protein", String(format: "%.1f kg", $0))) },
                entry.mineralKg.map { AnyView(compRow("Minerals", String(format: "%.2f kg", $0))) },
                entry.fatKg.map { AnyView(compRow("Body fat mass", String(format: "%.1f kg", $0))) },
            ].compactMap { $0 })
        })
    }

    private func compRow(_ l: String, _ v: String) -> some View {
        HStack { Text(l).font(.system(size: 13)).foregroundStyle(W.muted); Spacer()
            Text(v).font(W.score(17)).foregroundStyle(W.text) }.padding(.vertical, 9)
    }

    private func segmentalCard(_ seg: [Double]) -> some View {
        let names = ["Right arm", "Left arm", "Trunk", "Right leg", "Left leg"]
        return DarkCard {
            CardTitle("Segmental Lean", "% of ideal per region", chevron: false) {}
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(names[i]).font(.system(size: 12)).foregroundStyle(W.text).frame(width: 78, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(W.card2)
                            Capsule().fill(seg[i] >= 100 ? W.green : seg[i] >= 90 ? W.yellow : W.red)
                                .frame(width: max(4, geo.size.width * min(seg[i], 130) / 130))
                        }
                    }.frame(height: 8)
                    Text("\(Int(seg[i]))%").font(W.score(14)).foregroundStyle(W.text).frame(width: 42, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private var historyCard: some View {
        DarkCard {
            CardTitle("History", "your last \(min(entries.count, 8)) tests", chevron: false) {}
            VStack(spacing: 18) {
                historyTrend("Weight", "kg", W.sleep) { $0.weightKg }
                historyTrend("Skeletal muscle", "kg", W.vibrant) { $0.muscleKg }
                historyTrend("Percent body fat", "%", W.yellow) { $0.bodyFatPct }
            }
        }
    }

    private func historyTrend(_ title: String, _ unit: String, _ color: Color,
                              _ value: (BodyCompEntry) -> Double?) -> some View {
        let pts = entries.suffix(8).compactMap { e -> (Date, Double)? in
            guard let v = value(e), let d = DateKey.date(e.date) else { return nil }
            return (d, v)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(W.label(10)).kerning(0.8).foregroundStyle(W.muted)
                Spacer()
                if let last = pts.last { Text("\(fmt(last.1)) \(unit)").font(W.score(15)).foregroundStyle(color) }
            }
            if pts.count > 1 {
                TrendGraph(points: pts.map { (date: $0.0, value: $0.1) }, unit: unit, color: color).frame(height: 74)
            } else {
                Text("Add more readings to see the trend").font(.system(size: 11)).foregroundStyle(W.muted)
            }
        }
    }

    private func fmt(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v) }

    /// A value on a horizontal scale with the healthy band shaded and a marker dot.
    private func rangeBar(_ name: String, _ value: Double, _ unit: String,
                          low: Double, high: Double, scaleLo: Double, scaleHi: Double, lowerBetter: Bool?) -> some View {
        let span = max(scaleHi - scaleLo, 0.1)
        func x(_ v: Double) -> Double { min(1, max(0, (v - scaleLo) / span)) }
        let inBand = value >= low && value <= high
        let color: Color = inBand ? W.green : (lowerBetter == true && value > high) ? W.red : W.yellow
        return VStack(spacing: 5) {
            HStack {
                Text(name).font(.system(size: 13)).foregroundStyle(W.text)
                Spacer()
                Text("\(fmt(value))\(unit.isEmpty ? "" : " " + unit)").font(W.score(17)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.card2)
                    Capsule().fill(W.green.opacity(0.25))
                        .frame(width: geo.size.width * (x(high) - x(low))).offset(x: geo.size.width * x(low))
                    Circle().fill(color).frame(width: 12, height: 12)
                        .offset(x: min(geo.size.width - 12, max(0, geo.size.width * x(value) - 6)))
                }
            }
            .frame(height: 12)
        }
    }

    private func prettyDate(_ key: String) -> String {
        guard let d = DateKey.date(key) else { return key }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f.string(from: d)
    }
}
