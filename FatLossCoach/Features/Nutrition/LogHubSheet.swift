import SwiftUI
import PhotosUI

/// The tabs of the "+ More ways to log" hub.
enum LogHubTab: String, CaseIterable, Identifiable {
    case methods = "Methods", recents = "Recents", favorites = "Favorites", yesterday = "Yesterday"
    var id: String { rawValue }
}

/// The single "+" logging hub. Holds every logging method that used to be a top-level button
/// (Camera / Library / Type / Barcode / Say it / Compare / Quick add) plus item-level re-logging
/// (Recents / Favorites / Same as yesterday). Everything is scoped to the currently selected day
/// (`flow.day`) and, when set, the chosen meal slot — so past-day editing is preserved.
struct LogHubSheet: View {
    @Bindable var flow: ScanFlow
    let day: String
    @Environment(Store.self) private var store
    @Environment(MealScanner.self) private var scanner
    @Environment(\.dismiss) private var dismiss

    @State private var tab: LogHubTab = .methods
    /// Which slot the re-added items should land in. nil = "Other" (no slot).
    @State private var slot: String?

    private func closeAndRun(_ action: @escaping () -> Void) { dismiss(); DispatchQueue.main.async(execute: action) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                SegmentedTabs(selection: $tab, options: LogHubTab.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 16).padding(.top, 8)

                // Slot picker applies to Recents / Favorites / Yesterday (which slot to log into).
                if tab != .methods {
                    SlotPicker(slot: $slot).padding(.horizontal, 16)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        switch tab {
                        case .methods:   methods
                        case .recents:   recentsList
                        case .favorites: favoritesList
                        case .yesterday: yesterdayList
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .background(Theme.bg)
            .navigationTitle(day == DateKey.key() ? "Log a meal" : "Log · \(WeekCalendarCard.longDay(day))")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { tab = flow.hubTab; slot = flow.slot }
    }

    // MARK: Methods tab — the old button stack, now one tidy grid.

    private var methods: some View {
        VStack(spacing: 12) {
            Text("Snap, search, scan or just type it — every method logs to \(day == DateKey.key() ? "today" : WeekCalendarCard.longDay(day)).")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                methodTile("Take photo", "camera.fill", Theme.primary) {
                    closeAndRun { flow.camera(slot: flow.slot) }
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                methodTile("Photo library", "photo.on.rectangle", Theme.accent) {
                    closeAndRun { flow.error = nil; flow.showLibrary = true }
                }
                methodTile("Type it in", "keyboard", Theme.blue) {
                    closeAndRun { flow.typed(slot: flow.slot) }
                }
                methodTile("Scan barcode", "barcode.viewfinder", Theme.blue) {
                    closeAndRun { flow.typed(slot: flow.slot, barcode: true) }
                }
                methodTile("Say it", "mic.fill", Theme.primary) {
                    closeAndRun { flow.error = nil; flow.showVoice = true }
                }
                methodTile("Compare", "arrow.left.arrow.right", Theme.orange) {
                    closeAndRun { flow.showCompare = true }
                }
                methodTile("Quick add", "bolt.fill", Theme.orange) {
                    closeAndRun { flow.showQuickAdd = true }
                }
                methodTile("Log with AI", "sparkles", Theme.primary) {
                    closeAndRun { flow.error = nil; flow.showAIChat = true }
                }
            }
        }
    }

    private func methodTile(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 17)).foregroundStyle(color)
                }
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Item-level re-logging (Recents / Favorites / Yesterday)

    private var recentsList: some View {
        let recent = store.recentMeals()
        return Group {
            if recent.isEmpty {
                emptyState("No recent foods yet", "Log a meal and it shows up here for one-tap re-adding.")
            } else {
                ForEach(recent) { m in itemRow(m, icon: "arrow.counterclockwise", tint: Theme.primary) }
            }
        }
    }

    private var favoritesList: some View {
        let favs = store.favoriteMeals
        return Group {
            if favs.isEmpty {
                emptyState("No favorites yet", "Tap the heart on any logged meal to keep it here.")
            } else {
                ForEach(favs) { m in itemRow(m, icon: "heart.fill", tint: Theme.red) }
            }
        }
    }

    private var yesterdayList: some View {
        // Item-level "same as yesterday": the items logged to THIS slot yesterday, each with its own "+".
        let items = slot.map { store.yesterdayItems(slot: $0, before: day) } ?? []
        let prev = store.previousDay(of: day)
        return Group {
            if slot == nil {
                emptyState("Pick a meal above", "“Same as yesterday” lists the items you logged to that meal yesterday, so you can re-add them one by one.")
            } else if items.isEmpty {
                emptyState("Nothing logged to \(Plan.meal(slot)?.name ?? "this meal") on \(WeekCalendarCard.longDay(prev))",
                           "Pick a different meal, or log something new.")
            } else {
                HStack {
                    Text("\(Plan.meal(slot)?.name ?? "This meal") · \(WeekCalendarCard.longDay(prev))")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button {
                        for m in items { store.repeatMeal(m, on: day, slot: slot) }
                    } label: {
                        Text("Add all \(items.count)").font(.system(size: 12, weight: .bold))
                    }.buttonStyle(PillButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(items) { m in itemRow(m, icon: "clock.arrow.circlepath", tint: Theme.blue) }
            }
        }
    }

    /// One re-addable food/meal row. The "+" re-logs just this item to the chosen slot/day.
    private func itemRow(_ m: MealEntry, icon: String, tint: Color) -> some View {
        Card {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.16)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("P \(Int(m.protein.rounded())) · C \(Int(m.carbs.rounded())) · F \(Int(m.fat.rounded()))")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(Int(m.kcal.rounded())) kcal").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                Button { store.repeatMeal(m, on: day, slot: slot) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.primary)
                }.buttonStyle(.plain).padding(.leading, 4)
            }
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
    }
}

/// Fast path to log calories (and optional protein) without choosing a specific food.
/// Writes a minimal "Quick add" MealEntry to the selected day/slot.
struct QuickAddSheet: View {
    @Bindable var flow: ScanFlow
    let day: String
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kcal = ""
    @State private var protein = ""
    @State private var slot: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Log calories fast — no food search. Protein is optional. Everything else stays 0.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            field("Calories (kcal)", $kcal)
                            field("Protein (g) — optional", $protein)
                        }
                    }

                    SlotPicker(slot: $slot)

                    Button(Plan.logLabel(slot)) {
                        let k = Fmt.parse(kcal) ?? 0
                        store.quickAdd(kcal: k, protein: Fmt.parse(protein) ?? 0, on: day, slot: slot)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled((Fmt.parse(kcal) ?? 0) <= 0)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(day == DateKey.key() ? "Quick add" : "Quick add · \(WeekCalendarCard.longDay(day))")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { slot = flow.slot }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.blue)
            Spacer()
            NumField(placeholder: "0", text: text, width: 90)
        }
    }
}
