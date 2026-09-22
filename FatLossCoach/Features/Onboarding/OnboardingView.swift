import SwiftUI

/// Livity-style guided onboarding in the HUMANS dark theme → `PlanBuilder` targets → `Store.applyIntake`.
/// First launch runs the full guided flow (welcome, explainers, questions, "building your plan", plan,
/// value prop). Re-opened from Profile → "Edit my answers" it shows the questions only (skippable).
struct OnboardingView: View {

    /// One screen in the flow. Question steps host the existing questionnaire bodies; the rest are narrative.
    private enum Step: Hashable {
        case welcome, privacy
        case aboutYou, goal
        case energyExplainer
        case activity, training
        case bodyExplainer
        case food, lifestyle, health, habits, supplements, devices
        case building, summary, valueProp
    }

    @State private var p: IntakeProfile
    @State private var idx: Int = 0
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

    init(existing: IntakeProfile? = nil, canSkip: Bool = false, onDone: @escaping (IntakeProfile) -> Void) {
        let start = existing ?? IntakeProfile()
        _p = State(initialValue: start)
        _heightText = State(initialValue: Fmt.num(start.heightCm))
        _weightText = State(initialValue: Fmt.num(start.weightKg))
        _waistText = State(initialValue: start.waistCm.map(Fmt.num) ?? "")
        _goalText = State(initialValue: Fmt.num(start.goalWeightKg))
        _birthYearText = State(initialValue: String(start.birthYear))
        self.onDone = onDone
        self.canSkip = canSkip
    }

    /// Editing an existing profile from Profile → questions only, no narrative or paywall beats.
    private var isEditing: Bool { canSkip }

    private var steps: [Step] {
        isEditing
            ? [.aboutYou, .goal, .activity, .training, .food, .lifestyle, .health, .habits, .supplements, .devices, .summary]
            : [.welcome, .privacy, .aboutYou, .goal, .energyExplainer, .activity, .training,
               .bodyExplainer, .food, .lifestyle, .health, .habits, .supplements, .devices, .building, .summary, .valueProp]
    }

    private var current: Step { steps[min(idx, steps.count - 1)] }
    private var isLast: Bool { idx >= steps.count - 1 }
    private var progress: Double { Double(idx + 1) / Double(steps.count) }

    var body: some View {
        Group {
            switch current {
            case .welcome:         welcomeScreen
            case .privacy:         privacyScreen
            case .energyExplainer: energyScreen
            case .bodyExplainer:   bodyScreen
            case .building:        OnboardingLoader(name: p.name) { advance() }
            case .valueProp:       valuePropScreen
            case .summary:         summaryScaffold
            default:               questionScaffold(current)
            }
        }
        .background(Theme.bg)
        .interactiveDismissDisabled(!canSkip)
        .onAppear {
            // Debug: `-obStep habits` (etc.) jumps straight to a step for screenshots/QA.
            guard !didJump else { return }
            didJump = true
            if let name = UserDefaults.standard.string(forKey: "obStep"),
               let i = steps.firstIndex(where: { "\($0)" == name }) { idx = i }
        }
    }

    @State private var didJump = false

    // MARK: flow control

    private func advance() {
        commitNumbers()
        if isLast { finish() } else { withAnimation(.easeInOut(duration: 0.25)) { idx += 1 } }
    }
    private func back() { withAnimation(.easeInOut(duration: 0.25)) { idx = max(0, idx - 1) } }
    private func finish() { commitNumbers(); onDone(p); dismiss() }

    private func valid(_ step: Step) -> Bool {
        switch step {
        case .aboutYou: return !p.name.trimmingCharacters(in: .whitespaces).isEmpty && (Fmt.parse(weightText) ?? 0) >= 35 && (Fmt.parse(heightText) ?? 0) >= 120 && (Int(birthYearText) ?? 0) > 1920
        case .goal:     return (Fmt.parse(goalText) ?? 0) >= 35
        default:        return true
        }
    }

    private func title(_ step: Step) -> String {
        switch step {
        case .aboutYou:  return "About you"
        case .goal:      return "Your goal"
        case .activity:  return "Daily activity"
        case .training:  return "Training"
        case .food:      return "Food"
        case .lifestyle: return "Lifestyle"
        case .health:    return "Health"
        case .habits:    return "Habits to build"
        case .supplements: return "Supplements"
        case .devices:   return "Devices"
        case .summary:   return "Your plan"
        default:         return ""
        }
    }

    // MARK: question screens (host the existing questionnaire bodies)

    @ViewBuilder private func questionScaffold(_ step: Step) -> some View {
        OnboardingScaffold(progress: progress, title: title(step),
                           showBack: idx > 0, canClose: canSkip, continueEnabled: valid(step),
                           onBack: back, onClose: { dismiss() }, onContinue: advance) {
            switch step {
            case .aboutYou:  aboutYou
            case .goal:      goal
            case .activity:  activity
            case .training:  training
            case .food:      food
            case .lifestyle: lifestyle
            case .health:    health
            case .habits:    habitsStep
            case .supplements: supplementsStep
            case .devices:   devices
            default:         EmptyView()
            }
        }
    }

    private var summaryScaffold: some View {
        OnboardingScaffold(progress: progress, title: title(.summary),
                           showBack: idx > 0, canClose: canSkip,
                           continueTitle: isLast ? (p.completedAt == nil ? "Start my plan" : "Save my plan") : "Looks good",
                           continueEnabled: true,
                           onBack: back, onClose: { dismiss() }, onContinue: advance) {
            summary
        }
    }

    // MARK: narrative screens

    private var welcomeScreen: some View {
        OnboardingIntro(
            headline: "Pro-grade health, from the watch you already wear.",
            body_: "Recovery, sleep, strain and energy — finally in one place. No extra hardware.",
            primaryTitle: "Get started",
            progress: progress,
            onPrimary: advance,
            hero: {
                VStack(spacing: 18) {
                    Image("SplashLogo").resizable().scaledToFit().frame(height: 76)
                    FlowLayout(spacing: 8) {
                        OBDeviceChip(icon: "applewatch", name: "Apple Watch")
                        OBDeviceChip(icon: "waveform.path.ecg", name: "WHOOP")
                        OBDeviceChip(icon: "circle.circle", name: "Oura")
                        OBDeviceChip(icon: "figure.run", name: "Garmin")
                    }
                    .frame(maxWidth: 320)
                }
            }
        )
    }

    private var privacyScreen: some View {
        OnboardingIntro(
            icon: "lock.shield.fill",
            headline: "Private by design.",
            body_: "Your answers build your plan on this device. We never sell your data, and health readings stay on your phone unless you choose to back them up.",
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    private var energyScreen: some View {
        OnboardingIntro(
            eyebrow: "How it works",
            icon: "flame.fill", tint: Theme.orange,
            headline: "Fat loss is an energy balance.",
            body_: "We estimate what you burn, set a deficit you can actually keep, and adjust it every week as your weight moves.",
            features: [
                OBFeature(icon: "camera.viewfinder", title: "Snap your meals", detail: "Photo, barcode or describe it — calories and macros in seconds.", tint: Theme.primary),
                OBFeature(icon: "arrow.left.arrow.right", title: "Energy Balance", detail: "Eaten vs burned, with your deficit shown live.", tint: Theme.blue),
                OBFeature(icon: "chart.line.uptrend.xyaxis", title: "Weekly auto-adjust", detail: "Targets re-tune as the scale changes — no plateaus.", tint: Theme.orange)
            ],
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    private var bodyScreen: some View {
        OnboardingIntro(
            eyebrow: "Your body, scored",
            headline: "Recovery, Strain & Sleep — every day.",
            body_: "From your watch's heart-rate, HRV and sleep, HUMANS scores how recovered you are and how hard to train today.",
            features: [
                OBFeature(icon: "heart.fill", title: "Recovery", detail: "HRV, resting HR and sleep against your own baseline.", tint: Theme.primary),
                OBFeature(icon: "bolt.fill", title: "Strain", detail: "How much load you've taken on — and your target for today.", tint: Theme.blue),
                OBFeature(icon: "bed.double.fill", title: "Sleep coach", detail: "Sleep debt and a bedtime that pays it back.", tint: Color(hex: 0x9B8CFF))
            ],
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance,
            hero: {
                HStack(spacing: 22) {
                    OBMiniGauge(value: 0.47, display: "47%", label: "Sleep", tint: Theme.blue)
                    OBMiniGauge(value: 0.62, display: "62%", label: "Recovery", tint: Theme.orange)
                    OBMiniGauge(value: 0.69, display: "14.5", label: "Strain", tint: Theme.primary)
                }
            }
        )
    }

    private var valuePropScreen: some View {
        OnboardingIntro(
            icon: "checkmark.seal.fill",
            headline: p.name.isEmpty ? "You're all set." : "You're all set, \(p.name).",
            body_: "Your plan is ready. Log a meal, wear your watch, and check the Body tab each morning — the numbers get sharper the more you use it.",
            primaryTitle: "Start HUMANS",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
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

    // Buildable habit choices offered in onboarding (curated from the full HabitMetric catalog).
    private static let habitChoices: [HabitMetric] =
        [.steps, .water, .protein, .sleepDuration, .meditation, .sunExposure, .floors, .workoutCount, .mood]

    private var habitsStep: some View {
        Group {
            intro("Pick a few daily habits to build. We'll add them to your tracker — you can change them any time.")
            chips(Self.habitChoices, selected: $p.wantedHabits)
            if p.wantedHabits.isEmpty {
                Text("No pressure — leave this empty and we'll start you with Steps, Water and Protein.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
            }
        }
    }

    private var supplementsStep: some View {
        Group {
            intro("Taking any of these? Tick the ones you want to track each day — we'll show just those on your Today screen.")
            VStack(spacing: 8) {
                ForEach(Plan.supplements) { s in
                    let on = p.supplementsWanted.contains(s.key)
                    Button {
                        if on { p.supplementsWanted.remove(s.key) } else { p.supplementsWanted.insert(s.key) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20)).foregroundStyle(on ? Theme.primary : Theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                Text("\(s.dose) · \(s.when)").font(.system(size: 11)).foregroundStyle(Theme.muted)
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
            field("Anything else you take? (optional)") {
                TextField("e.g. creatine, vitamin C", text: $p.currentSupplements).textFieldStyle(.roundedBorder)
            }
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
                SectionTitle("Daily targets")
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
                SectionTitle("Timeline")
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
                    SectionTitle("ℹ Tailored for you")
                    ForEach(t.notes, id: \.self) { n in
                        Text("• \(n)").font(.system(size: 13)).foregroundStyle(Theme.text).lineSpacing(3).padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: controls

    private func intro(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(Theme.muted).lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A dark, on-brand text field — replaces the light `.roundedBorder` system control everywhere.
    private func styledField(_ text: Binding<String>, _ placeholder: String,
                             axis: Axis = .horizontal, lines: ClosedRange<Int>? = nil,
                             caps: TextInputAutocapitalization = .sentences) -> some View {
        OBTextField(text: text, placeholder: placeholder, axis: axis, lines: lines, caps: caps)
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
                        Text(["", "", "", "", ""][n - 1]).font(.system(size: 22))
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

/// Let the habit catalog flow through the shared chip control.
extension HabitMetric: Identifiable { public var id: String { rawValue } }
extension HabitMetric: LabeledOption { var label: String { title } }

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
