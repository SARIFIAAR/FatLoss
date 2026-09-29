import SwiftUI

/// The Workout/Train tab. Now driven by the Physical-Age engine (aging levers + recovery gate),
/// replacing the static 3-phase programme (parked in Legacy/). Sessions stay checkable and loggable;
/// progressive-overload lift logging is unchanged (see SessionSheet / ExerciseRow below).
struct WorkoutView: View {
    var body: some View { PhysicalAgePlanView() }
}

/// "Your Physical Age plan" — the week generated from the user's aging levers, recovery-adjusted.
struct PhysicalAgePlanView: View {
    @Environment(Store.self) private var store
    @State private var selected: WorkoutDay?

    var body: some View {
        Screen(subtitle: "Generated from your Physical Age", title: "Your plan") {
            if let wk = store.weeklyProgramme() {
                planHeader(wk)
                if wk.gate.restToday { recoveryBanner(wk.gate) }
                VStack(spacing: 10) {
                    ForEach(wk.sessions) { s in SessionCard(session: s) { openLog(s) } }
                }
                Card {
                    Text(wk.note).font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
            } else {
                Card {
                    SectionTitle("Your plan")
                    Text("Connect Apple Health and finish your quick setup — your training plan is generated from your Physical Age and adjusts to your recovery each day.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
            }
        }
        .sheet(item: $selected) { day in SessionSheet(day: day) }
        .onAppear {
            // Debug: `-openDay Mon` opens that strength session's log sheet directly.
            if selected == nil, let d = UserDefaults.standard.string(forKey: "openDay") {
                selected = LegacyPlan.phase(3).workouts.first { $0.day == d }
            }
        }
    }

    private func openLog(_ s: BodyMetrics.PlannedSession) {
        // Only strength sessions have a lift-logging catalogue day; cardio/recover cards aren't loggable.
        if let day = store.catalogDay(for: s) { selected = day }
    }

    private func planHeader(_ wk: BodyMetrics.WeeklyProgramme) -> some View {
        Card {
            SectionTitle(wk.headline)
            if let lever = wk.priorityLever {
                HStack(spacing: 6) {
                    Image(systemName: wk.strengthPromoted ? "dumbbell.fill" : "target")
                        .font(.system(size: 12)).foregroundStyle(Theme.primary)
                    Text(wk.strengthPromoted
                         ? "Leaning into strength — your biggest lever right now"
                         : "Focused on \(lever) — your biggest lever right now")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    private func recoveryBanner(_ gate: BodyMetrics.RecoveryGate) -> some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 16)).foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Take it easy today").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(gate.reason ?? "Your recovery is low today — the plan has eased off. Come back to it when you're recovered.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
            }
        }
    }
}

/// One generated session row. Strength cards are tappable to open lift logging; held-back sessions
/// grey out and show WHY so nothing contradicts the recovery ring.
struct SessionCard: View {
    let session: BodyMetrics.PlannedSession
    let onTap: () -> Void

    private var icon: String {
        switch session.kind {
        case .strength: "dumbbell.fill"
        case .zone2: "figure.run"
        case .intervals: "bolt.heart.fill"
        case .walk: "figure.walk"
        case .recover: "moon.zzz.fill"
        }
    }
    private var loggable: Bool { session.kind == .strength && session.loggableCatalogDay != nil && !session.heldBack }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 18))
                    .foregroundStyle(session.heldBack ? Theme.muted : Theme.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.title).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(session.heldBack ? Theme.muted : Theme.text)
                        if session.heldBack {
                            Text("eased off").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.orange)
                                .padding(.vertical, 2).padding(.horizontal, 7)
                                .background(Theme.orange.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    Text(session.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.why).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 1)
                    if let r = session.heldReason {
                        Text(r).font(.system(size: 11)).foregroundStyle(Theme.orange).padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
                if loggable {
                    Text("Log").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.primary)
                        .padding(.vertical, 3).padding(.horizontal, 9)
                        .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(session.heldBack ? Theme.bg : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(session.heldBack ? Theme.border : Theme.accent, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!loggable)
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
                    Button("Complete Workout") {
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
                        Text("Last: \(Fmt.num(last.kg)) kg × \(last.reps) reps")
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
                Button(saved ? "Saved" : "Log Weight") {
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
