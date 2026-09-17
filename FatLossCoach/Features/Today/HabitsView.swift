import SwiftUI

/// Customizable habit tracker. Users add habits (metric + frequency + goal + colour) via the "+".
/// Auto metrics (steps/water/protein/…) fill from existing data; manual ones are logged by tapping.
struct HabitsCard: View {
    @Environment(Store.self) private var store
    @State private var showAdd = false
    @State private var logging: HabitDef?

    var body: some View {
        Card {
            HStack {
                Text("HABITS").font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.primary)
                }
            }
            .padding(.bottom, 6)

            if store.habitDefs.isEmpty {
                Text("Tap ＋ to add a habit — steps, water, protein, meditation and more.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.habitDefs.enumerated()), id: \.element.id) { i, def in
                        HabitRow(def: def) { logging = def }
                        if i < store.habitDefs.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddHabitSheet { store.addHabit($0) } }
        .sheet(item: $logging) { HabitLogSheet(def: $0) }
        .onAppear {
            store.seedDefaultHabitsIfNeeded()
            if UserDefaults.standard.bool(forKey: "addHabit") { showAdd = true }   // debug/screenshots
        }
    }
}

private struct HabitRow: View {
    @Environment(Store.self) private var store
    let def: HabitDef
    let onLog: () -> Void

    var body: some View {
        let value = store.habitValue(def)
        let prog = store.habitProgress(def)
        let met = store.habitMet(def)
        Button { if !def.metric.isAuto { onLog() } } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(def.color.opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: def.metric.icon).font(.system(size: 15)).foregroundStyle(def.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(valueLine(value)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Theme.card2, lineWidth: 5)
                    Circle().trim(from: 0, to: max(0.001, prog))
                        .stroke(def.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if met {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(def.color)
                    } else {
                        Text("\(Int(prog * 100))").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !def.metric.isAuto { Button { onLog() } label: { Label("Log value", systemImage: "square.and.pencil") } }
            Button(role: .destructive) { store.deleteHabit(def.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func valueLine(_ v: Double) -> String {
        if def.metric == .mood || def.goal == 0 {
            return store.habitMet(def) ? "Logged today" : "Tap to log"
        }
        return "\(fmtNum(v)) / \(fmtNum(def.goal)) \(def.metric.unit)"
    }
}

// MARK: - Add habit

struct AddHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (HabitDef) -> Void

    @State private var metric: HabitMetric = .steps
    @State private var freq: HabitFrequency = .daily
    @State private var goal: Double = HabitMetric.steps.defaultGoal
    @State private var colorHex: UInt32 = HabitColors.all[0]

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("WHAT TO TRACK") {
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(HabitMetric.allCases, id: \.self) { metricPill($0) }
                        }
                    }
                    section("HOW OFTEN") {
                        HStack(spacing: 10) { ForEach(HabitFrequency.allCases, id: \.self) { freqPill($0) } }
                        Text(freq.blurb).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    section("GOAL") {
                        VStack(spacing: 14) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(fmtNum(goal)).font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.text)
                                Text(metric.unit).font(.system(size: 15)).foregroundStyle(Theme.muted)
                            }
                            Stepper("", value: $goal, in: 0...100000, step: goalStep).labelsHidden()
                            if !metric.presets.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(metric.presets, id: \.self) { p in
                                        Button(fmtNum(p)) { goal = p }
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(goal == p ? Color(hex: 0x101518) : Theme.text)
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(goal == p ? Color(hex: colorHex) : Theme.card, in: Capsule())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(18)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16))
                    }
                    section("COLOR") {
                        HStack(spacing: 12) { ForEach(HabitColors.all, id: \.self) { colorSwatch($0) } }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Add Habit").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .onChange(of: metric) { _, m in goal = m.defaultGoal }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(HabitDef(metric: metric, frequency: freq, goal: goal, colorHex: colorHex))
                        dismiss()
                    } label: { Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.primary) }
                }
            }
        }
    }

    private var goalStep: Double {
        switch metric {
        case .steps: 500; case .water: 250
        case .caloriesBurned, .caloriesConsumed: 50
        case .protein, .floors: 5; case .sleepDuration: 0.5
        default: 1
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func metricPill(_ m: HabitMetric) -> some View {
        let sel = metric == m
        return Button { metric = m } label: {
            HStack(spacing: 8) {
                Image(systemName: m.icon).font(.system(size: 14))
                    .foregroundStyle(sel ? Color(hex: colorHex) : Theme.muted).frame(width: 20)
                Text(m.title).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sel ? Theme.text : Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if sel { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(hex: colorHex)) }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(sel ? Color(hex: colorHex).opacity(0.15) : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(sel ? Color(hex: colorHex) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func freqPill(_ f: HabitFrequency) -> some View {
        let sel = freq == f
        return Button { freq = f } label: {
            Text(f.title).font(.system(size: 14, weight: .bold))
                .foregroundStyle(sel ? Color(hex: 0x101518) : Theme.text)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(sel ? Color(hex: colorHex) : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ hex: UInt32) -> some View {
        Button { colorHex = hex } label: {
            Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                .overlay { if colorHex == hex { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white) } }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Manual value log

struct HabitLogSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let def: HabitDef
    @State private var value: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(def.name) {
                    HStack {
                        Text("Value"); Spacer()
                        TextField("0", value: $value, format: .number).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text(def.metric.unit).foregroundStyle(Theme.muted)
                    }
                    if !def.metric.presets.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(def.metric.presets, id: \.self) { p in
                                Button(fmtNum(p)) { value = p }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if def.goal > 0 {
                        Button("Mark done (\(fmtNum(def.goal)) \(def.metric.unit))") { value = def.goal }
                    } else {
                        Button("Mark done") { value = 1 }
                    }
                }
            }
            .navigationTitle("Log \(def.name)").navigationBarTitleDisplayMode(.inline)
            .onAppear { value = store.habitValue(def) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.logHabit(def, value: value); dismiss() }
                }
            }
        }
    }
}

private func fmtNum(_ x: Double) -> String {
    x.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(x)) : String(format: "%.1f", x)
}
