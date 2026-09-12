import SwiftUI

/// Plan questionnaire: nine short steps → `PlanBuilder` targets → `Store.applyIntake`.
/// Shown on first launch for a new profile, and from Profile → "Edit my answers".
struct OnboardingView: View {
    @State private var p: IntakeProfile
    @State private var step: Int
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onDone: (IntakeProfile) -> Void
    let canSkip: Bool

    // Text mirrors for numeric fields (NumField works on strings).
    @State private var heightText: String
    @State private var weightText: String
    @State private var waistText: String
    @State private var goalText: String
    @State private var birthYearText: String

    static let titles = ["About you", "Your goal", "Daily activity", "Training", "Food", "Lifestyle", "Health", "Devices", "Your plan"]

    init(existing: IntakeProfile? = nil, canSkip: Bool = false, onDone: @escaping (IntakeProfile) -> Void) {
        let start = existing ?? IntakeProfile()
        _p = State(initialValue: start)
        _step = State(initialValue: UserDefaults.standard.integer(forKey: "onboardingStep"))
        _heightText = State(initialValue: Fmt.num(start.heightCm))
        _weightText = State(initialValue: Fmt.num(start.weightKg))
        _waistText = State(initialValue: start.waistCm.map(Fmt.num) ?? "")
        _goalText = State(initialValue: Fmt.num(start.goalWeightKg))
        _birthYearText = State(initialValue: String(start.birthYear))
        self.onDone = onDone
        self.canSkip = canSkip
    }

    private var last: Int { Self.titles.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: aboutYou
                    case 1: goal
                    case 2: activity
                    case 3: training
                    case 4: food
                    case 5: lifestyle
                    case 6: health
                    case 7: devices
                    default: summary
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Theme.bg)
        .interactiveDismissDisabled(!canSkip)
    }

    // MARK: chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(step + 1) of \(Self.titles.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                Spacer()
                if canSkip { Button("Close") { dismiss() }.font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent) }
            }
            Text(Self.titles[step]).font(Theme.titleL).foregroundStyle(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * Double(step + 1) / Double(Self.titles.count))
                }
            }
            .frame(height: 6)
            .animation(.easeInOut, value: step)
        }
        .padding(20)
        .background(Theme.primary)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }.buttonStyle(SecondaryButtonStyle())
            }
            if step < last {
                Button("Continue") { commitNumbers(); withAnimation { step += 1 } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!stepValid)
                    .opacity(stepValid ? 1 : 0.5)
            } else {
                Button(p.completedAt == nil ? "Start my plan" : "Save my plan") { commitNumbers(); onDone(p); dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.card)
    }

    private var stepValid: Bool {
        switch step {
        case 0: return !p.name.trimmingCharacters(in: .whitespaces).isEmpty && (Fmt.parse(weightText) ?? 0) >= 35 && (Fmt.parse(heightText) ?? 0) >= 120 && (Int(birthYearText) ?? 0) > 1920
        case 1: return (Fmt.parse(goalText) ?? 0) >= 35
        default: return true
        }
    }

    private func commitNumbers() {
        if let v = Fmt.parse(heightText) { p.heightCm = v }
        if let v = Fmt.parse(weightText) { p.weightKg = v }
        p.waistCm = Fmt.parse(waistText)
        if let v = Fmt.parse(goalText) { p.goalWeightKg = v }
        if let v = Int(birthYearText) { p.birthYear = v }
    }

    // MARK: steps

    private var aboutYou: some View {
        Group {
            intro("A few basics so the numbers are yours, not a template.")
            field("Your first name") { TextField("e.g. Ahmed", text: $p.name).textFieldStyle(.roundedBorder).textInputAutocapitalization(.words) }
            field("Sex (for the metabolism formula)") { segmented($p.sex) }
            HStack(spacing: 12) {
                field("Birth year") { NumField(placeholder: "1985", text: $birthYearText, decimal: false, width: nil) }
                field("Height (cm)") { NumField(placeholder: "175", text: $heightText, width: nil) }
            }
            HStack(spacing: 12) {
                field("Current weight (kg)") { NumField(placeholder: "90", text: $weightText, width: nil) }
                field("Waist at navel (cm) — optional") { NumField(placeholder: "100", text: $waistText, width: nil) }
            }
        }
    }

    private var goal: some View {
        Group {
            intro("Where do you want to get to, and how fast? Slower paces are the ones people actually keep.")
            field("Goal weight (kg)") { NumField(placeholder: "80", text: $goalText, width: nil) }
            field("Pace") { options(IntakeProfile.Pace.allCases, selected: $p.pace, detail: { $0.detail }) }
            field("Is there a date you're aiming for? (optional)") { TextField("e.g. wedding in December", text: $p.event).textFieldStyle(.roundedBorder) }
            field("Why does this matter to you?") {
                TextField("One honest sentence — you'll see it on hard days", text: $p.motivation, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var activity: some View {
        Group {
            intro("How much you move outside training decides your calorie budget more than the gym does.")
            field("Your work day is mostly…") { options(IntakeProfile.JobActivity.allCases, selected: $p.jobActivity) }
            field("Typical daily steps (check Health if unsure)") { options(IntakeProfile.StepsBand.allCases, selected: $p.dailySteps) }
            field("Workouts per week right now") { stepper($p.currentTrainingDays, range: 0...7, unit: "days") }
        }
    }

    private var training: some View {
        Group {
            intro("This shapes the programme phases and which exercises you get.")
            field("Experience") { options(IntakeProfile.Experience.allCases, selected: $p.experience, detail: { $0.detail }) }
            field("Days you can realistically train") { stepper($p.trainingDays, range: 2...6, unit: "days / week") }
            field("Where") { segmented($p.location) }
            field("Equipment available") { chips(IntakeProfile.Equipment.allCases, selected: $p.equipment) }
            field("Preferred time") { segmented($p.preferredTime) }
            field("Injuries or limitations (optional)") {
                TextField("e.g. left knee — no deep squats", text: $p.limitations, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var food: some View {
        Group {
            intro("The meal plan only works if it's food you'll actually eat.")
            field("Eating style") { options(IntakeProfile.EatingStyle.allCases, selected: $p.eatingStyle) }
            field("Allergies or intolerances") { chips(IntakeProfile.Allergy.allCases, selected: $p.allergies) }
            field("Foods you dislike (optional)") { TextField("e.g. fish, mushrooms", text: $p.dislikes).textFieldStyle(.roundedBorder) }
            field("Cuisines you enjoy") { chips(IntakeProfile.Cuisine.allCases, selected: $p.cuisines) }
            field("Meals per day you prefer") { stepper($p.mealsPerDay, range: 2...6, unit: "meals") }
            field("Cooking at home") { options(IntakeProfile.Cooking.allCases, selected: $p.cooking) }
            field("Meals out or delivered per week") { stepper($p.eatingOutPerWeek, range: 0...21, unit: "meals") }
            field("When do cravings hit?") { options(IntakeProfile.CravingTime.allCases, selected: $p.cravingTime) }
            field("Coffee / tea / energy drinks per day") { stepper($p.caffeinePerDay, range: 0...10, unit: "cups") }
            field("Alcohol") { segmented($p.alcohol) }
            field("Do you fast?") { options(IntakeProfile.Fasting.allCases, selected: $p.fasting) }
        }
    }

    private var lifestyle: some View {
        Group {
            intro("Sleep and stress drive hunger. The plan times reminders and the kitchen-closed rule around your day.")
            HStack(spacing: 12) {
                field("Usually wake at") { hourPicker($p.wakeHour) }
                field("Usually in bed by") { hourPicker($p.bedHour) }
            }
            field("Hours of sleep on a normal night") { stepper($p.sleepHours, range: 4...10, step: 0.5, unit: "h") }
            field("Stress level lately") { stressPicker }
            Toggle(isOn: $p.shiftWork) { Text("I work shifts or irregular hours").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text) }.tint(Theme.primary)
        }
    }

    private var health: some View {
        Group {
            intro("Not medical advice — but the plan avoids things that clash with these.")
            field("Any of these?") { chips(IntakeProfile.Condition.allCases, selected: $p.conditions) }
            VStack(alignment: .leading, spacing: 6) {
                Text("How you've been feeling").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                Text("Mood, stress and anxiety change appetite, sleep and energy, so the plan can go easier where it needs to. Answer however you like — this stays in your own profile.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
            }
            .padding(.top, 6)
            field("Over the last few weeks, my mood has been…") { options(IntakeProfile.Mood.allCases, selected: $p.mood) }
            field("Do you feel anxious or on edge?") { options(IntakeProfile.Anxiety.allCases, selected: $p.anxiety) }
            field("Medications you take (optional)") { TextField("e.g. metformin, sertraline", text: $p.medications, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder) }
            field("Supplements you already take (optional)") { TextField("e.g. vitamin D, omega-3", text: $p.currentSupplements).textFieldStyle(.roundedBorder) }
            Toggle(isOn: $p.smoker) { Text("I smoke or vape").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text) }.tint(Theme.primary)
            Toggle(isOn: $p.doctorCleared) { Text("A doctor has cleared me for diet and exercise").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text) }.tint(Theme.primary)
        }
    }

    private var devices: some View {
        Group {
            intro("An Apple Watch lets the app measure calories burned, steps, sleep and heart-rate variability instead of estimating them.")
            Toggle(isOn: $p.hasAppleWatch) { Text("I wear an Apple Watch").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text) }.tint(Theme.primary)
            Text(p.hasAppleWatch ? "After this, connect Apple Health from the Profile tab — the plan then uses your real daily burn to show your deficit."
                                 : "No problem — your calorie budget uses your job and step answers instead. You can log steps by hand.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
            Text("Sign in with Apple in the Profile tab afterwards to back everything up — each person who signs in gets their own private profile.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3)
        }
    }

    private var summary: some View {
        let t = PlanBuilder.targets(for: p)
        return Group {
            intro(p.name.isEmpty ? "Here's your starting plan." : "\(p.name), here's your starting plan. Everything can be tuned later in Profile.")
            Card {
                SectionTitle("🎯 Daily targets")
                HStack(spacing: 8) {
                    MacroStat(value: "\(t.kcal)", label: "kcal", color: Theme.primary)
                    MacroStat(value: "\(t.protein)g", label: "protein", color: Theme.primary)
                    MacroStat(value: "\(t.carbs)g", label: "carbs", color: Theme.orange)
                    MacroStat(value: "\(t.fat)g", label: "fat", color: Theme.blue)
                }
                .padding(.vertical, 10)
                row("Maintenance (estimated burn)", "\(t.tdee) kcal")
                row("Daily deficit", "−\(t.deficit) kcal")
                row("Water", "\(t.waterMl) ml")
                row("Steps", "\(t.stepsGoal.formatted())")
                if let w = t.waistTarget { row("Waist target", "\(Fmt.num(w)) cm") }
            }
            Card {
                SectionTitle("📅 Timeline")
                if t.kgToLose > 0 {
                    Text("\(Fmt.num(t.kgToLose)) kg to lose at ~\(Fmt.num(p.pace.kgPerWeek)) kg/week ≈ \(t.weeksToGoal) weeks")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Weeks 1–4 build habits and technique, weeks 5–8 add training volume, then the full gym programme. Weight is re-checked weekly and the calories adjust as you lose.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 4)
                } else {
                    Text("Targets are set to maintenance.").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
            if !t.notes.isEmpty {
                Card {
                    SectionTitle("ℹ️ Tailored for you")
                    ForEach(t.notes, id: \.self) { n in
                        Text("• \(n)").font(.system(size: 13)).foregroundStyle(Theme.text).lineSpacing(3).padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: controls

    private func intro(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(4)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
        }
        .padding(.vertical, 4)
    }

    private func segmented<T: Hashable & Identifiable & CaseIterable>(_ sel: Binding<T>) -> some View where T.AllCases: RandomAccessCollection, T: LabeledOption {
        Picker("", selection: sel) {
            ForEach(Array(T.allCases)) { c in Text(c.label).tag(c) }
        }
        .pickerStyle(.segmented)
    }

    private func options<T: Hashable & Identifiable & LabeledOption>(_ all: [T], selected: Binding<T>, detail: ((T) -> String)? = nil) -> some View {
        VStack(spacing: 6) {
            ForEach(all) { c in
                let on = selected.wrappedValue == c
                Button { selected.wrappedValue = c } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Theme.primary : Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            if let d = detail?(c) { Text(d).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(on ? Theme.primary.opacity(0.10) : Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Theme.primary : Theme.border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chips<T: Hashable & Identifiable & LabeledOption>(_ all: [T], selected: Binding<Set<T>>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(all) { c in
                let on = selected.wrappedValue.contains(c)
                Button {
                    if on { selected.wrappedValue.remove(c) } else { selected.wrappedValue.insert(c) }
                } label: {
                    Text(c.label).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? .white : Theme.text)
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(on ? Theme.primary : Theme.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(on ? Theme.primary : Theme.border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepper(_ value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        Stepper(value: value, in: range) {
            Text("\(value.wrappedValue) \(unit)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepper(_ value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text("\(Fmt.num(value.wrappedValue)) \(unit)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hourPicker(_ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<24, id: \.self) { h in Text(Self.hourLabel(h)).tag(h) }
        }
        .pickerStyle(.menu)
        .tint(Theme.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func hourLabel(_ h: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date())
    }

    private var stressPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                let on = p.stress == n
                Button { p.stress = n } label: {
                    VStack(spacing: 2) {
                        Text(["😌", "🙂", "😐", "😣", "🤯"][n - 1]).font(.system(size: 22))
                        Text(["Calm", "Fine", "Busy", "Stressed", "Burnt out"][n - 1]).font(.system(size: 10, weight: .bold)).foregroundStyle(on ? .white : Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(on ? Theme.primary : Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Theme.primary : Theme.border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Options with a display label (the intake enums).
protocol LabeledOption { var label: String { get } }
extension IntakeProfile.Sex: LabeledOption {}
extension IntakeProfile.Pace: LabeledOption {}
extension IntakeProfile.JobActivity: LabeledOption {}
extension IntakeProfile.StepsBand: LabeledOption {}
extension IntakeProfile.Experience: LabeledOption {}
extension IntakeProfile.TrainingLocation: LabeledOption {}
extension IntakeProfile.Equipment: LabeledOption {}
extension IntakeProfile.TrainingTime: LabeledOption {}
extension IntakeProfile.EatingStyle: LabeledOption {}
extension IntakeProfile.Allergy: LabeledOption {}
extension IntakeProfile.Cooking: LabeledOption {}
extension IntakeProfile.Cuisine: LabeledOption {}
extension IntakeProfile.CravingTime: LabeledOption {}
extension IntakeProfile.Alcohol: LabeledOption {}
extension IntakeProfile.Fasting: LabeledOption {}
extension IntakeProfile.Condition: LabeledOption {}
extension IntakeProfile.Mood: LabeledOption {}
extension IntakeProfile.Anxiety: LabeledOption {}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
