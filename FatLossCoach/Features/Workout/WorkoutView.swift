import SwiftUI

struct WorkoutView: View {
    @Environment(Store.self) private var store
    @State private var selected: WorkoutDay?

    var body: some View {
        let today = Plan.todayAbbrev
        Screen(subtitle: "Phase 3 — Full Gym", title: "Workout 🏋️") {
            Text("🏋️ Phase 3: Full Gym Active")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 16)
                .background(Theme.primary).clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(Plan.workouts) { d in
                    DayCard(day: d, isToday: d.day == today) {
                        if d.isTraining { selected = d }
                    }
                }
            }

            Card {
                SectionTitle("Progressive Overload")
                Text("When you complete all reps at the top of your range for 2 sessions in a row, add weight next time. Upper body: +2.5 kg · Lower body: +5 kg")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
            }
        }
        .sheet(item: $selected) { day in
            SessionSheet(day: day)
        }
        .onAppear {
            // Debug: launch with `-openDay Mon` to open a session directly.
            if selected == nil, let d = UserDefaults.standard.string(forKey: "openDay") {
                selected = Plan.workout(for: d)
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
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.muted)
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
