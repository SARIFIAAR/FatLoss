import SwiftUI

struct WorkoutView: View {
    @Environment(Store.self) private var store
    @State private var selected: WorkoutDay?

    var body: some View {
        let today = Plan.todayAbbrev
        let phase = store.currentPhase
        Screen(subtitle: "Phase \(phase.number) — \(phase.name)", title: "Workout 🏋️") {
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
        .onAppear {
            // Debug: launch with `-openDay Mon` to open a session directly.
            if selected == nil, let d = UserDefaults.standard.string(forKey: "openDay") {
                selected = store.currentPhase.workouts.first { $0.day == d }
            }
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
                SectionTitle("🏁 Programme · Phase \(phase.number) of \(Plan.phases.count)")
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
                         ? (prog.isComplete ? "Phase complete 🎉" : "\(prog.daysLeft) days left in this phase")
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
                Button("▶︎ Start Phase \(phase.number) today") { store.startCurrentPhase() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            } else if prog.isComplete, phase.number < Plan.phases.count {
                Button("Advance to Phase \(phase.number + 1): \(Plan.phase(phase.number + 1).name) →") { store.advancePhase() }
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
                    Text("Start →")
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

struct SessionSheet: View {
    let day: WorkoutDay
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                        ExerciseRow(day: day.day, index: i, exercise: ex)
                        if i < day.exercises.count - 1 { Divider().overlay(Theme.border) }
                    }
                    Button("✅ Complete Workout") {
                        store.completeWorkout()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 16)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.card)
            .navigationTitle("\(day.day): \(day.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct ExerciseRow: View {
    let day: String
    let index: Int
    let exercise: Exercise
    @Environment(Store.self) private var store
    @State private var kg = ""
    @State private var reps = ""

    var body: some View {
        let done = store.isExerciseDone(day: day, index: index)
        let last = store.lastLog(for: exercise.name)
        let saved = store.todayLog(for: exercise.name) != nil
        VStack(alignment: .leading, spacing: 0) {
            if !exercise.images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(exercise.images, id: \.self) { ExerciseImage(url: $0) }
                }
                .padding(.bottom, 4)
                HStack(spacing: 6) {
                    Text("START").frame(maxWidth: .infinity)
                    Text("FINISH").frame(maxWidth: .infinity)
                }
                .font(.system(size: 9, weight: .bold)).kerning(0.4).foregroundStyle(Theme.muted)
                .padding(.bottom, 8)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text(exercise.muscles).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                    if let last {
                        Text("📊 Last: \(Fmt.num(last.kg)) kg × \(last.reps) reps")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.blue).padding(.top, 2)
                    } else {
                        Text("Set your baseline today")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent).padding(.top, 2)
                    }
                }
                Spacer()
                Text(exercise.sets).font(.system(size: 13)).foregroundStyle(Theme.muted)
                CheckCircle(done: done, size: 28) { store.toggleExercise(day: day, index: index) }
            }
            Divider().overlay(Theme.border).padding(.vertical, 10)
            HStack(spacing: 6) {
                NumField(placeholder: "kg", text: $kg, decimal: true)
                Text("×").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.muted)
                NumField(placeholder: "reps", text: $reps, decimal: false)
                Button(saved ? "✓ Saved" : "Log Weight") {
                    guard let k = Fmt.parse(kg), k > 0, let r = Int(reps.trimmingCharacters(in: .whitespaces)), r > 0 else {
                        store.showToast("Enter weight & reps first")
                        return
                    }
                    store.saveExerciseLog(exercise.name, kg: k, reps: r)
                }
                .buttonStyle(PrimaryButtonStyle(color: saved ? Theme.primaryLight : Theme.primary, compact: true))
            }
        }
        .padding(.vertical, 12)
        .onAppear {
            if let t = store.todayLog(for: exercise.name) {
                kg = Fmt.num(t.kg)
                reps = String(t.reps)
            }
        }
    }
}

struct ExerciseImage: View {
    let url: URL
    var height: CGFloat = 86
    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(Theme.border)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 26)).foregroundStyle(Theme.muted)
                    default:
                        ProgressView().tint(Theme.muted)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
