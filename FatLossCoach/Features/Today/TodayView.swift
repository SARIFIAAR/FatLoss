import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var showWeight = false
    @State private var showWaist = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning! 👋" : h < 17 ? "Good afternoon! ☀️" : "Good evening! 🌙"
    }
    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        Screen(subtitle: dateLine, title: greeting) {
            TargetsCard()
            WatchCard()
            RecoveryCard()
            HabitsCard()
            WaterCard()
            SupplementsCard()
            BreathingCard()
            HStack(spacing: 10) {
                Button("+ Log Weight") { showWeight = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("📏 Log Waist") { showWaist = true }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.orange))
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showWeight) {
            LogValueSheet(title: "Log Today's Weight", placeholder: "e.g. 105.4") { store.logWeight($0) }
        }
        .sheet(isPresented: $showWaist) {
            LogValueSheet(title: "📏 Log Waist Circumference", placeholder: "e.g. 102 cm") { store.logWaist($0) }
        }
    }
}

// MARK: - Cards

struct TargetsCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        let g = store.data.goals
        Card {
            SectionTitle("Daily Targets")
            HStack(spacing: 8) {
                MacroStat(value: "\(g.kcal)", label: "kcal", color: Theme.primary)
                MacroStat(value: "\(g.protein)g", label: "protein", color: Theme.primary)
                MacroStat(value: "\(g.carbs)g", label: "carbs", color: Theme.orange)
                MacroStat(value: "\(g.fat)g", label: "fat", color: Theme.blue)
            }
        }
    }
}

struct MacroStat: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WatchCard: View {
    @Environment(Store.self) private var store
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        let h = store.healthToday
        let goal = Double(store.data.goals.stepsGoal)
        Card {
            SectionTitle("⌚ Apple Watch Today")
            HStack(spacing: 12) {
                StatBox {
                    Text((h?.steps ?? 0).formatted())
                        .font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.primary)
                    Text("steps").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    ProgressBar(value: Double(h?.steps ?? 0) / goal, height: 8)
                        .padding(.top, 3)
                    Text("Goal: \(store.data.goals.stepsGoal.formatted())")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                StatBox {
                    Text(h?.restingHR.map { "\(Int($0.rounded()))" } ?? "–")
                        .font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.primary)
                    Text("resting HR").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text(h?.restingHR != nil ? "bpm resting" : (health.hasConnected ? "No reading yet" : "Connect Health in Profile"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 3)
                }
            }
        }
    }
}

struct RecoveryCard: View {
    @Environment(Store.self) private var store
    private let moods = ["😔", "😞", "😐", "😊", "😄"]

    var body: some View {
        let rec = store.recoveryToday
        let score = Store.readiness(rec)
        let color = score.map(Readiness.color) ?? Theme.muted
        Card {
            SectionTitle("⚡ Recovery & Readiness")
            VStack(spacing: 4) {
                Text(score.map { String($0) } ?? "–")
                    .font(.system(size: 52, weight: .black)).foregroundStyle(color)
                Text(Readiness.label(score).uppercased())
                    .font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(Theme.muted)
                ProgressBar(value: Double(score ?? 0) / 100, height: 10, fill: AnyShapeStyle(color))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                RecStat(label: "HRV ms", value: rec.hrv.map { "\(Int($0.rounded()))" })
                RecStat(label: "Sleep", value: rec.sleepH.map { String(format: "%.1fh", $0) })
                RecStat(label: "Rest HR", value: rec.rhr.map { "\(Int($0.rounded()))" })
                RecStat(label: "Deep", value: rec.deepH.map { String(format: "%.1fh", $0) })
                RecStat(label: "REM", value: rec.remH.map { String(format: "%.1fh", $0) })
                RecStat(label: "Resp/min", value: rec.resp.map { "\(Int($0.rounded()))" })
            }
            .padding(.top, 10)

            Divider().overlay(Theme.border).padding(.vertical, 12)

            HStack {
                Text("Today's Mood").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { m in
                        let sel = rec.mood == m
                        Button { store.setMood(m) } label: {
                            Text(moods[m - 1])
                                .font(.system(size: 22))
                                .padding(.vertical, 3).padding(.horizontal, 5)
                                .background(sel ? Theme.primary.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(sel ? Theme.primary : Color.clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct RecStat: View {
    let label: String
    let value: String?
    var body: some View {
        VStack(spacing: 2) {
            Text(value ?? "–").font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.primary)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct HabitsCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        Card {
            SectionTitle("Today's Habits")
            VStack(spacing: 0) {
                ForEach(Array(Plan.habits.enumerated()), id: \.element.id) { i, h in
                    let done = store.isHabitDone(h.key)
                    Button { store.toggleHabit(h.key) } label: {
                        HStack(spacing: 12) {
                            CheckMark(done: done)
                            Text(h.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(done ? Theme.muted : Theme.text)
                                .strikethrough(done, color: Theme.muted)
                            Spacer()
                            Text(h.time).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < Plan.habits.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }
}

struct WaterCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        let ml = store.waterToday
        let goal = store.data.goals.waterGoal
        Card {
            SectionTitle("💧 Water")
            HStack {
                Text("\(ml) ml").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.primary)
                Spacer()
                Text("Goal: \(goal.formatted()) ml").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            ProgressBar(value: Double(ml) / Double(goal), height: 18,
                        fill: AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.blue], startPoint: .leading, endPoint: .trailing)))
                .padding(.vertical, 8)
            Button("+ 250 ml") { store.addWater(250) }.buttonStyle(PillButtonStyle())
        }
    }
}

struct SupplementsCard: View {
    @Environment(Store.self) private var store
    var body: some View {
        Card {
            SectionTitle("💊 Supplements")
            VStack(spacing: 0) {
                ForEach(Array(Plan.supplements.enumerated()), id: \.element.id) { i, s in
                    let taken = store.isSupplementTaken(s.key)
                    Button { store.toggleSupplement(s.key) } label: {
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(taken ? Theme.orange : Color.clear)
                                .overlay(Capsule().stroke(Theme.orange, lineWidth: 2))
                                .frame(width: 32, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                (Text(s.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                 + Text(" \(s.dose)").font(.system(size: 12)).foregroundStyle(Theme.muted))
                                Text(s.when).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if taken {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < Plan.supplements.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }
}

struct BreathingCard: View {
    var body: some View {
        Card {
            SectionTitle("🌬️ Breathing Schedule")
            VStack(spacing: 0) {
                ForEach(Array(Plan.breathing.enumerated()), id: \.element.id) { i, b in
                    HStack(alignment: .top, spacing: 10) {
                        Text(b.icon).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.time).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.primary)
                            Text(b.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Text(b.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    if i < Plan.breathing.count - 1 { Divider().overlay(Theme.border) }
                }
            }
        }
    }
}
