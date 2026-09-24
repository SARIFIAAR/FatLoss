import SwiftUI

/// GitHub-style contribution grid: 7 weekday rows × N week columns, filled oldest→newest.
/// Green (habit colour) for met days, faint for missed. Livity-style.
struct ContributionGrid: View {
    let history: [Bool]        // oldest → newest, one per day
    let color: Color
    var weeks: Int = 12

    var body: some View {
        let cells = Array(history.suffix(weeks * 7))
        // Pad the front so the newest day lands bottom-right and weekdays align.
        let pad = (7 - (cells.count % 7)) % 7
        let padded: [Bool?] = Array(repeating: nil, count: pad) + cells.map { Optional($0) }
        let cols = (padded.count + 6) / 7
        return HStack(spacing: 3) {
            ForEach(0..<cols, id: \.self) { c in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { r in
                        let i = c * 7 + r
                        let v = i < padded.count ? padded[i] : nil
                        RoundedRectangle(cornerRadius: 2)
                            .fill(v == true ? color : (v == nil ? Color.clear : Color.white.opacity(0.06)))
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }
}

/// High-level habits card on Progress → taps into the per-habit detail.
struct HabitProgressCard: View {
    @Environment(Store.self) private var store
    @State private var showDetail = false
    @State private var showManage = false

    var body: some View {
        let habits = store.habitDefs
        let doneToday = habits.filter { store.habitMet($0) }.count
        Card {
            HStack(spacing: 12) {
                Button { if !habits.isEmpty { showDetail = true } } label: {
                    HStack(spacing: 4) {
                        Text("HABITS").font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                        if !habits.isEmpty {
                            Text("· Details").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.primary)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer()
                // Manage (add / edit / delete) — reuses the same HabitsScreen the Today card presents.
                Button { showManage = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold))
                        Text("Manage").font(.system(size: 12, weight: .bold))
                    }.foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
                Button { showManage = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain)
            }.padding(.bottom, 8)

            if habits.isEmpty {
                Button { showManage = true } label: {
                    Text("Add your first habit — steps, water, meditate, read and more.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.buttonStyle(.plain)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 7)
                        Circle().trim(from: 0, to: max(0.001, Double(doneToday) / Double(max(habits.count, 1))))
                            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -1) {
                            Text("\(doneToday)").font(W.score(24)).foregroundStyle(Theme.text)
                            Text("of \(habits.count)").font(.system(size: 9)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(doneToday) of \(habits.count) done today").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.text)
                        // top 3 habits as mini rows — long-press to delete quickly.
                        ForEach(habits.prefix(3)) { def in
                            HStack(spacing: 6) {
                                Image(systemName: def.metric.icon).font(.system(size: 10)).foregroundStyle(def.color).frame(width: 14)
                                Text(def.name).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                                Spacer()
                                let s = store.habitStreak(def)
                                if s > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "flame.fill").font(.system(size: 8)).foregroundStyle(Theme.orange)
                                        Text("\(s)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.orange)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button { showManage = true } label: { Label("Manage habits", systemImage: "slider.horizontal.3") }
                                Button(role: .destructive) { store.deleteHabit(def.id) } label: { Label("Delete \(def.name)", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showDetail) { HabitProgressDetailView() }
        .sheet(isPresented: $showManage) { HabitsScreen() }
    }
}

/// Per-habit detail — one card each with streak, best, completion % and a contribution grid.
struct HabitProgressDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showManage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.habitDefs) { def in
                        card(def)
                            .contextMenu {
                                Button { showManage = true } label: { Label("Manage habits", systemImage: "slider.horizontal.3") }
                                Button(role: .destructive) { store.deleteHabit(def.id) } label: { Label("Delete \(def.name)", systemImage: "trash") }
                            }
                    }
                    Button { showManage = true } label: {
                        Label("Manage habits", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Habit progress").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showManage = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 16)).foregroundStyle(Theme.primary) }
                }
            }
            .sheet(isPresented: $showManage) { HabitsScreen() }
        }
    }

    private func card(_ def: HabitDef) -> some View {
        let streak = store.habitStreak(def)
        let best = store.habitBestStreak(def)
        let completion = store.habitCompletion(def, days: 30)
        return Card(accent: streak >= 3 ? def.color : nil) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(def.color.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: def.metric.icon).font(.system(size: 17)).foregroundStyle(def.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("\(completion)% in the last 30 days").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(streak > 0 ? Theme.orange : Theme.muted)
                        Text("\(streak)").font(W.score(20)).foregroundStyle(streak > 0 ? Theme.orange : Theme.muted)
                    }
                    Text("Best \(best)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            Divider().overlay(Theme.border).padding(.vertical, 12)
            ContributionGrid(history: store.habitHistory(def, days: 84), color: def.color)
            HStack(spacing: 8) {
                Text("12 weeks").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Text("Missed").font(.system(size: 10)).foregroundStyle(Theme.muted)
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(width: 10, height: 10)
                RoundedRectangle(cornerRadius: 2).fill(def.color).frame(width: 10, height: 10)
                Text("Met").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)
        }
    }
}
