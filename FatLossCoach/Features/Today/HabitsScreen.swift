import SwiftUI

/// Dedicated Habits management screen (pushed from the Today card's "See all"):
/// add from the library, see all habits with streaks, log/check-in, delete.
struct HabitsScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showLibrary = false
    @State private var logging: HabitDef?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.habitDefs.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.habitDefs) { def in
                            HabitFullRow(def: def) { logging = def }
                        }
                    }
                    Button { showLibrary = true } label: {
                        Label("Add a habit", systemImage: "plus").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Habits").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showLibrary = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.primary) }
                }
            }
            .sheet(isPresented: $showLibrary) { HabitLibrarySheet() }
            .sheet(item: $logging) { HabitLogSheet(def: $0) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 34)).foregroundStyle(Theme.primary)
            Text("Build your habits").font(Theme.titleL).foregroundStyle(Theme.text)
            Text("Pick from the library — steps, water, meditate, read, no sugar and more — or create your own.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

/// A full habit row for the management screen: ring/check, name, value, streak, delete.
private struct HabitFullRow: View {
    @Environment(Store.self) private var store
    let def: HabitDef
    let onLog: () -> Void

    var body: some View {
        let met = store.habitMet(def)
        let prog = store.habitProgress(def)
        let streak = store.habitStreak(def)
        Card {
            HStack(spacing: 12) {
                Button { tap() } label: {
                    ZStack {
                        Circle().fill(def.color.opacity(0.18)).frame(width: 40, height: 40)
                        Image(systemName: def.metric.icon).font(.system(size: 17)).foregroundStyle(def.color)
                    }
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        Text(valueLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        if streak > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(Theme.orange)
                                Text("\(streak)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange)
                            }
                        }
                    }
                }
                Spacer()
                Button { tap() } label: { progressRing(met: met, prog: prog) }.buttonStyle(.plain)
            }
        }
        .contextMenu {
            if def.metric == .checkIn { Button { store.toggleHabitCheckIn(def) } label: { Label(met ? "Undo" : "Mark done", systemImage: met ? "arrow.uturn.backward" : "checkmark") } }
            else if !def.metric.isAuto { Button { onLog() } label: { Label("Log value", systemImage: "square.and.pencil") } }
            Button(role: .destructive) { store.deleteHabit(def.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func tap() {
        if def.metric == .checkIn { store.toggleHabitCheckIn(def) }
        else if !def.metric.isAuto { onLog() }
    }

    private var valueLine: String {
        if def.metric == .checkIn { return store.habitMet(def) ? "Done today" : "Tap to check off" }
        if def.metric.isAuto || def.goal > 0 {
            return "\(fmt(store.habitValue(def))) / \(fmt(def.goal)) \(def.metric.unit)"
        }
        return "Tap to log"
    }

    private func progressRing(met: Bool, prog: Double) -> some View {
        ZStack {
            Circle().stroke(Theme.card2, lineWidth: 5)
            Circle().trim(from: 0, to: max(0.001, prog)).stroke(def.color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            if met { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(def.color) }
        }.frame(width: 34, height: 34)
    }
    private func fmt(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x) }
}

/// The habit library — browse ready-made habits by area, tap to add fully configured.
struct HabitLibrarySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { showCustom = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundStyle(Theme.primary)
                            Text("Create a custom habit").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                    }.buttonStyle(.plain)

                    ForEach(HabitLibrary.areas, id: \.self) { area in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(area.uppercased()).font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(HabitLibrary.by(area: area)) { t in templateTile(t) }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Add a habit").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showCustom) { AddHabitSheet { store.addHabit($0) } }
        }
    }

    private func templateTile(_ t: HabitTemplate) -> some View {
        let added = store.habitDefs.contains { $0.name.lowercased() == t.name.lowercased() }
        return Button {
            if !added { store.addHabit(t.makeDef()) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: t.colorHex).opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: t.icon).font(.system(size: 14)).foregroundStyle(Color(hex: t.colorHex))
                }
                Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(added ? Theme.muted : Theme.primary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
