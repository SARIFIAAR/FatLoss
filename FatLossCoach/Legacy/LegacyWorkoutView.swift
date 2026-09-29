import SwiftUI

// MARK: - PARKED: legacy phase-based Workout UI (Foundation → Build → Full Gym)
//
// This is the ORIGINAL Workout-tab body and its phase widgets, preserved intact. The live
// Workout tab (WorkoutView) now renders `PhysicalAgePlanView` (the aging-algo-driven weekly
// programme). Nothing here is on the live path — it stays only so restoring the phase programme
// is a one-line swap in WorkoutView (`PhysicalAgePlanView()` → `LegacyWorkoutView()`).
//
// The lift-logging surface (SessionSheet / ExerciseRow / ExerciseImage) is NOT here — it stays
// shared in WorkoutView.swift and is used by both engines, so progressive-overload logging is
// identical either way.

/// The original phase-based Workout tab body. Restore by swapping it back into WorkoutView.
struct LegacyWorkoutView: View {
    @Environment(Store.self) private var store
    @State private var selected: WorkoutDay?

    var body: some View {
        let today = Plan.todayAbbrev
        let phase = store.currentPhase
        Screen(subtitle: "Phase \(phase.number) — \(phase.name)", title: "Workout") {
            PhaseCard()

            VStack(spacing: 10) {
                ForEach(phase.workouts) { d in
                    DayCard(day: d, isToday: d.day == today) {
                        if d.isTraining { selected = d }
                    }
                }
            }

            Card {
                SectionTitle("Progression rule — Phase \(phase.number)")
                Text(phase.tip)
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
            }
        }
        .sheet(item: $selected) { day in
            SessionSheet(day: day)
        }
    }
}

/// "Where am I" — 3-segment programme bar, current-phase week counter, start / advance controls.
struct PhaseCard: View {
    @Environment(Store.self) private var store
    @State private var confirmPhase: Int?

    var body: some View {
        let phase = store.currentPhase
        let prog = store.phaseProgress
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Programme · Phase \(phase.number) of \(Plan.phases.count)")
                Spacer()
                Menu {
                    ForEach(Plan.phases) { ph in
                        Button {
                            confirmPhase = ph.number
                        } label: {
                            Label("Phase \(ph.number): \(ph.name)", systemImage: ph.number == phase.number ? "checkmark" : "circle")
                        }
                    }
                    Divider()
                    Button("Restart current phase today") { store.setPhase(phase.number, startToday: true) }
                } label: {
                    Label("Change", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                }
                .padding(.bottom, 10)
            }

            PhaseTrack()

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(phase.name).font(Theme.scoreM).foregroundStyle(Theme.text)
                    Text(phase.tagline).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(prog.started ? "Week \(prog.week) of \(prog.totalWeeks)" : "Not started")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(prog.started ? Theme.primary : Theme.orange)
                        .padding(.vertical, 3).padding(.horizontal, 9)
                        .background((prog.started ? Theme.primary : Theme.orange).opacity(0.12))
                        .clipShape(Capsule())
                }
                ProgressBar(value: prog.fraction, height: 10, fill: AnyShapeStyle(Theme.primary))
                    .padding(.top, 2)
                HStack {
                    Text(prog.started
                         ? (prog.isComplete ? "Phase complete" : "\(prog.daysLeft) days left in this phase")
                         : "\(phase.weeks) weeks · \(phase.trainingDays.count)× training per week")
                    Spacer()
                    if let sd = store.data.program.startDate, let d = DateKey.date(sd) {
                        Text("Started \(d.formatted(.dateTime.day().month(.abbreviated)))")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 12)

            Text(phase.goal)
                .font(.system(size: 13)).foregroundStyle(Theme.text).lineSpacing(3)
                .padding(.top, 10)

            if !prog.started {
                Button("︎ Start Phase \(phase.number) today") { store.startCurrentPhase() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            } else if prog.isComplete, phase.number < Plan.phases.count {
                Button("Advance to Phase \(phase.number + 1): \(Plan.phase(phase.number + 1).name)") { store.advancePhase() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.orange))
                    .padding(.top, 12)
            }
        }
        .confirmationDialog(
            confirmPhase.map { "Switch to Phase \($0): \(Plan.phase($0).name)?" } ?? "",
            isPresented: Binding(get: { confirmPhase != nil }, set: { if !$0 { confirmPhase = nil } }),
            titleVisibility: .visible
        ) {
            if let n = confirmPhase {
                Button("Switch and start today") { store.setPhase(n, startToday: true) }
                Button("Switch, start later") { store.setPhase(n, startToday: false) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Three segments, one per phase; filled to each phase's completion.
struct PhaseTrack: View {
    @Environment(Store.self) private var store
    var compact = false

    var body: some View {
        let current = store.currentPhase.number
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Plan.phases) { ph in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.border)
                            Capsule().fill(ph.number < current ? Theme.primaryLight : Theme.primary)
                                .frame(width: geo.size.width * store.phaseFill(ph.number))
                        }
                        .overlay(Capsule().stroke(ph.number == current ? Theme.primary : Color.clear, lineWidth: 1.5))
                    }
                    .frame(height: compact ? 8 : 12)
                }
            }
            if !compact {
                HStack(spacing: 4) {
                    ForEach(Plan.phases) { ph in
                        Text("\(ph.number) · \(ph.name)")
                            .font(.system(size: 10, weight: ph.number == current ? .heavy : .semibold))
                            .foregroundStyle(ph.number == current ? Theme.primary : Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

struct DayCard: View {
    let day: WorkoutDay
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(day.day)
                    .font(Theme.scoreS).foregroundStyle(Theme.muted)
                    .frame(minWidth: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(day.label).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                        if isToday {
                            Text("Today")
                                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.primary)
                                .padding(.vertical, 2).padding(.horizontal, 8)
                                .background(Color(hex: 0xD8F3DC)).clipShape(Capsule())
                        }
                    }
                    Text(day.tag).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if day.isTraining {
                    Text("Start")
                        .font(.system(size: 11, weight: isToday ? .heavy : .regular))
                        .foregroundStyle(isToday ? Theme.primary : Theme.muted)
                        .padding(.vertical, 3).padding(.horizontal, 9)
                        .background(isToday ? Theme.accent : Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(day.isTraining ? Theme.card : Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? Theme.primary : (day.isTraining ? Theme.accent : Theme.border), lineWidth: 2))
            .shadow(color: day.isTraining ? Theme.primary.opacity(0.1) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!day.isTraining)
    }
}
