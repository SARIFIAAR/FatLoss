import SwiftUI
import AuthenticationServices

/// Auth-first guided onboarding in the HUMANS dark theme (build 52):
/// MARKETING (everyone) → Sign in with Apple → branch on whether a CLOUD PROFILE EXISTS for that Apple ID
/// (not device state — the load-bearing fix for the "new version = brand-new user" bug):
///   • returning (cloud plan exists) → a real "Restoring your plan…" beat tied to the Firestore fetch,
///     then straight into the app (questionnaire SKIPPED);
///   • new account / guest → questionnaire → Connect-your-device → "Building your plan" → app.
/// No profile data is collected or persisted before an identity exists to own it.
/// Re-opened from Profile → "Edit my answers" it shows the questions only (skippable, no marketing/auth).
struct OnboardingView: View {

    /// One screen in the flow. Question steps host the existing questionnaire bodies; the rest are narrative.
    private enum Step: Hashable {
        case welcome, privacy
        case energyExplainer
        case bodyExplainer
        case socialProof               // NEW (v4 item 3) — honest credibility beat before sign-in
        case signIn                    // Sign in with Apple, before any question
        case welcomeBack               // returning user's restore beat (branch target)
        case aboutYou, goal
        case goalPreview               // NEW (v4 item 2) — honest weeks-to-goal estimate from partial intake
        case activity
        case activityPreview           // NEW (v4 item 2) — honest daily-calorie estimate from partial intake
        case training
        case recoveryExplainer         // NEW (v4 item 1) — micro-explainer: recovery / training-load, before Training
        case food
        case sleepExplainer            // NEW (v4 item 1) — micro-explainer: sleep, before Lifestyle
        case lifestyle
        case chronotype                // NEW (v4 item 5) — single-question chronotype, near Lifestyle
        case health
        case medExplainer              // NEW (v4 item 4) — shown ONLY if medications entered; HR-calibration
        case habits, supplements
        case connectDevice             // Apple Watch / Oura / WHOOP / HUMANS soon / phone-only
        case building, summary, valueProp
    }

    @State private var p: IntakeProfile
    @State private var idx: Int = 0
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    @Environment(HealthKitManager.self) private var hk
    @Environment(WearableLink.self) private var link
    @Environment(\.dismiss) private var dismiss
    let onDone: (IntakeProfile) -> Void
    let canSkip: Bool

    /// The user chose "Continue without an account" on the sign-in screen (local/guest path).
    @State private var isGuest = false
    /// True once we've routed past the sign-in gate (returning → welcomeBack, else → questionnaire).
    @State private var didBranch = false

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

    /// Marketing beats shown to everyone, then the sign-in gate, then the questionnaire → connect → plan.
    /// `.welcomeBack` is the returning-user branch target (jumped to from the sign-in gate, not in the
    /// linear order). Editing from Profile is questions-only (no marketing, no auth, no device step).
    private var steps: [Step] {
        isEditing
            ? [.aboutYou, .goal, .activity, .training, .food, .lifestyle, .chronotype, .health, .habits, .supplements, .summary]
            : [.welcome, .privacy, .bodyExplainer, .energyExplainer, .socialProof, .signIn,
               .aboutYou, .goal, .goalPreview, .activity, .activityPreview,
               .recoveryExplainer, .training, .food,
               .sleepExplainer, .lifestyle, .chronotype, .health, .medExplainer,
               .habits, .supplements,
               .connectDevice, .building, .summary, .valueProp]
    }

    /// The medication → HR-calibration explainer (item 4) is only meaningful if the user actually entered
    /// medications on the Health step. When the field is empty we skip it so nobody sees an irrelevant beat.
    /// Kept honest and non-diagnostic — it explains that Recovery/HR zones read from the user's own baseline.
    private func shouldSkip(_ step: Step) -> Bool {
        step == .medExplainer && p.medications.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var current: Step {
        if showWelcomeBack { return .welcomeBack }
        return steps[min(idx, steps.count - 1)]
    }
    private var isLast: Bool { idx >= steps.count - 1 }
    /// Progress hides during marketing/auth/branch beats (there's no meaningful "% of setup" yet).
    private var progress: Double {
        // Base the bar on the questionnaire span only, so it reads honestly once questions begin.
        guard let signInIdx = steps.firstIndex(of: .signIn) else { return Double(idx + 1) / Double(steps.count) }
        let qStart = signInIdx + 1
        let qCount = max(1, steps.count - qStart)
        return Double(max(0, idx - qStart) + 1) / Double(qCount)
    }

    var body: some View {
        Group {
            switch current {
            case .welcome:         welcomeScreen
            case .privacy:         privacyScreen
            case .energyExplainer: energyScreen
            case .bodyExplainer:   bodyScreen
            case .socialProof:     socialProofScreen
            case .signIn:          signInScreen
            case .welcomeBack:     welcomeBackScreen
            case .goalPreview:     goalPreviewScreen
            case .activityPreview: activityPreviewScreen
            case .recoveryExplainer: recoveryExplainerScreen
            case .sleepExplainer:  sleepExplainerScreen
            case .medExplainer:    medExplainerScreen
            case .chronotype:      chronotypeScaffold
            case .connectDevice:   connectDeviceScreen
            case .building:        OnboardingLoader(name: p.name) { advance() }
            case .valueProp:       valuePropScreen
            case .summary:         summaryScaffold
            default:               questionScaffold(current)
            }
        }
        .background(Theme.bg)
        .interactiveDismissDisabled(!canSkip)
        // Guest → existing-account collision (Bug 2): a one-line confirm, cloud wins by default.
        .overlay { collisionOverlay }
        // If the sign-in gate is up and the fetch resolves to a returning user, route to the restore beat.
        .onChange(of: cloud.accountHasCloudProfile) { _, _ in routeAfterSignInIfNeeded() }
        .onChange(of: cloud.isResolvingSignIn) { _, _ in routeAfterSignInIfNeeded() }
        .onAppear {
            // Debug: `-obStep habits` (etc.) jumps straight to a step for screenshots/QA. New steps
            // signIn / connectDevice / welcomeBack are addressable by name too.
            guard !didJump else { return }
            didJump = true
            if let name = UserDefaults.standard.string(forKey: "obStep"),
               let i = steps.firstIndex(where: { "\($0)" == name }) { idx = i }
            else if UserDefaults.standard.string(forKey: "obStep") == "welcomeBack" {
                idx = steps.firstIndex(of: .signIn) ?? 0   // welcomeBack isn't in the linear list
                showWelcomeBack = true
            }
        }
    }

    @State private var didJump = false
    /// Returning-user branch: replaces the sign-in gate with the restore beat.
    @State private var showWelcomeBack = false

    // MARK: sign-in gate routing

    /// After Sign in with Apple, branch on the REAL cloud-profile-exists signal (not device state).
    private func routeAfterSignInIfNeeded() {
        guard current == .signIn, cloud.isSignedIn, !cloud.isResolvingSignIn, !didBranch else { return }
        if cloud.pendingCollision != nil { return }   // collision confirm handles this case
        didBranch = true
        if cloud.accountHasCloudProfile {
            withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = true }
        } else {
            // New account — proceed into the questionnaire.
            withAnimation(.easeInOut(duration: 0.25)) { idx += 1 }
        }
    }

    // MARK: flow control

    private func advance() {
        commitNumbers()
        if isLast { finish(); return }
        withAnimation(.easeInOut(duration: 0.25)) {
            idx += 1
            // Skip conditionally-hidden steps (e.g. the med explainer when no meds were entered).
            while idx < steps.count - 1 && shouldSkip(steps[idx]) { idx += 1 }
            if isLast && shouldSkip(steps[idx]) { finish() }
        }
    }
    private func back() {
        withAnimation(.easeInOut(duration: 0.25)) {
            idx = max(0, idx - 1)
            while idx > 0 && shouldSkip(steps[idx]) { idx -= 1 }
        }
    }
    /// Skip a QUESTION step without requiring valid input — the profile keeps its current/default values, so
    /// the plan still builds from defaults. Same forward motion as `advance()` (which never gates on `valid`),
    /// but named separately so the intent is explicit and it can never accidentally block on validation.
    private func skip() { advance() }
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
        case .chronotype: return "Your body clock"
        case .health:    return "Health"
        case .habits:    return "Habits to build"
        case .supplements: return "Supplements"
        case .summary:   return "Your plan"
        default:         return ""
        }
    }

    // MARK: question screens (host the existing questionnaire bodies)

    @ViewBuilder private func questionScaffold(_ step: Step) -> some View {
        OnboardingScaffold(progress: progress, title: title(step),
                           showBack: idx > 0, canClose: canSkip, continueEnabled: valid(step),
                           onSkip: skip,
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
            headline: "Pro-grade health, from the wearable you already own.",
            body_: "Recovery, sleep, strain and energy — finally in one place. No extra hardware.",
            primaryTitle: "Get started",
            progress: progress,
            onPrimary: advance,
            hero: {
                VStack(spacing: 18) {
                    Image("SplashMark").resizable().scaledToFit().frame(height: 76)
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
            body_: "We never sell your data, and your health readings stay on your phone unless you choose to back them up to your own account.",
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
            body_: "From your wearable's heart-rate, HRV and sleep, HUMANS scores how recovered you are and how hard to train today.",
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
                    OBMiniGauge(value: 0.69, display: "14.5/21", label: "Strain", tint: Theme.primary)
                }
            }
        )
    }

    private var valuePropScreen: some View {
        OnboardingIntro(
            icon: "checkmark.seal.fill",
            headline: p.name.isEmpty ? "You're all set." : "You're all set, \(p.name).",
            body_: "Your plan is ready. Log a meal, wear your device, and check the Body tab each morning — the numbers get sharper the more you use it.",
            primaryTitle: "Start HUMANS",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    // MARK: v4 item 3 — honest social-proof / credibility beat (near sign-in)

    /// PRE-APP-STORE: no ratings, testimonials or "App of the Day" — we have none, so we invent none.
    /// Instead a factual credibility beat: the real signals HUMANS reads from the watch the user already
    /// owns, and that they stay private. When we have a genuine, permissioned testimonial post-launch,
    /// drop it into `Self.realTestimonial` and the quote card below renders automatically. Until then it
    /// stays nil and NOTHING fake is shown.
    /// Format when ready, e.g.: OBTestimonial(quote: "…", attribution: "— A., TestFlight tester")
    private static let realTestimonial: OBTestimonial? = nil   // ← post-launch: real, permissioned quote only

    private var socialProofScreen: some View {
        OnboardingIntro(
            eyebrow: "Why it works",
            icon: "waveform.path.ecg", tint: Theme.primary,
            headline: "Built on the signals your wearable already records.",
            body_: "HUMANS reads heart-rate variability, resting heart rate and sleep — the same measurements sports scientists use to gauge recovery. Nothing is guessed, and it stays private to you.",
            features: [
                OBFeature(icon: "heart.fill", title: "HRV & resting HR", detail: "Read straight from Apple Health — your own baseline, not an average.", tint: Theme.primary),
                OBFeature(icon: "bed.double.fill", title: "Sleep stages", detail: "Deep, REM and time in bed, night by night.", tint: Color(hex: 0x9B8CFF)),
                OBFeature(icon: "lock.fill", title: "Private by design", detail: "Your readings stay on your phone unless you back them up to your own account.", tint: Theme.blue)
            ],
            showcase: Self.realTestimonial.map { AnyView(OBTestimonialCard($0)) },
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    // MARK: v4 item 2 — personalised, honest preview beats (real estimates from the PARTIAL profile)

    /// After "Your goal": a real weeks-to-goal estimate from PlanBuilder on the partial profile. Updates
    /// with their weight/goal/pace answers. Clearly labelled an estimate; at maintenance it says so.
    private var goalPreviewScreen: some View {
        let t = PlanBuilder.targets(for: p)
        let hasLoss = t.kgToLose > 0 && t.weeksToGoal > 0
        return OnboardingIntro(
            eyebrow: "Your estimate so far",
            icon: "flag.checkered", tint: Theme.primary,
            headline: hasLoss
                ? "At a \(p.pace.label.lowercased()) pace, about \(t.weeksToGoal) weeks to \(Fmt.num(p.goalWeightKg)) kg."
                : "Your goal is at maintenance.",
            body_: hasLoss
                ? "That's \(Fmt.num(t.kgToLose)) kg at ~\(Fmt.num(p.pace.kgPerWeek)) kg/week. It's an estimate from your answers so far and will sharpen as we learn your activity — real weeks depend on how consistent the deficit is."
                : "You've set a goal at or above your current weight, so targets will hold you steady rather than drop weight. You can change this any time.",
            showcase: AnyView(
                OBShowcaseCard(eyebrow: "Estimate", icon: "flag.checkered", trailing: "updates as you answer") {
                    HStack(spacing: 22) {
                        OBMiniGauge(value: min(1, Double(t.weeksToGoal) / 52.0),
                                    display: hasLoss ? "\(t.weeksToGoal)" : "—",
                                    label: "weeks", tint: Theme.primary)
                        VStack(alignment: .leading, spacing: 10) {
                            OBStatChip(color: Theme.text.opacity(0.9), label: "To lose", value: hasLoss ? "\(Fmt.num(t.kgToLose)) kg" : "0 kg")
                            OBStatChip(color: Theme.primary, label: "Pace", value: "~\(Fmt.num(p.pace.kgPerWeek)) kg/wk")
                            OBStatChip(color: Theme.orange, label: "Target", value: "\(Fmt.num(p.goalWeightKg)) kg")
                        }
                        Spacer(minLength: 0)
                    }
                }
            ),
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    /// After "Daily activity": a real estimated daily calorie target from PlanBuilder on the partial
    /// profile. Now that job + steps + training days are known, the maintenance and deficit estimates mean
    /// something. Labelled an estimate; final macros are shown on the summary.
    private var activityPreviewScreen: some View {
        let t = PlanBuilder.targets(for: p)
        return OnboardingIntro(
            eyebrow: "Your estimate so far",
            icon: "flame.fill", tint: Theme.orange,
            headline: "Around \(t.kcal.formatted()) kcal a day to start.",
            body_: t.deficit > 0
                ? "We estimate you burn ~\(t.tdee.formatted()) kcal on a day like yours, so eating ~\(t.kcal.formatted()) kcal sets a ~\(t.deficit.formatted()) kcal deficit. It's an estimate from your answers — it re-tunes weekly as the scale moves."
                : "We estimate you burn ~\(t.tdee.formatted()) kcal on a day like yours. This is an estimate from your answers and re-tunes weekly as the scale moves.",
            showcase: AnyView(
                OBShowcaseCard(eyebrow: "Estimated daily target", icon: "fork.knife", trailing: "estimate") {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(t.kcal.formatted()).font(Theme.score(40)).foregroundStyle(Theme.text)
                            Text("kcal").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
                            Spacer()
                        }
                        HStack(spacing: 16) {
                            OBStatChip(color: Theme.muted, label: "Maintenance", value: "~\(t.tdee.formatted())")
                            if t.deficit > 0 { OBStatChip(color: Theme.orange, label: "Deficit", value: "−\(t.deficit.formatted())") }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            ),
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    // MARK: v4 item 1 — micro-explainers woven between questions

    /// Before Training: a short recovery / training-load beat, so the next questions have context.
    private var recoveryExplainerScreen: some View {
        OnboardingIntro(
            eyebrow: "Before we talk training",
            headline: "Harder isn't always better.",
            body_: "HUMANS tracks how much load you take on and how recovered you are, so it can tell you which days to push and which to keep easy. A few questions next shape your programme around that.",
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance,
            hero: {
                OBMiniGauge(value: 0.69, display: "14.5/21", label: "Strain today", tint: Theme.primary)
            }
        )
    }

    /// Before Lifestyle: a short sleep beat — the honest "sleep drives hunger" value line.
    private var sleepExplainerScreen: some View {
        OnboardingIntro(
            eyebrow: "Before we talk sleep",
            headline: "Sleep is a fat-loss tool.",
            body_: "Short nights raise the hormones that drive hunger and cravings. HUMANS times your reminders and a wind-down breathing session around when you actually sleep — the next few questions set that up.",
            primaryTitle: "Continue",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance,
            hero: {
                OBMiniGauge(value: 0.78, display: "7h 12m", label: "Sleep", tint: Color(hex: 0x9B8CFF))
            }
        )
    }

    // MARK: v4 item 4 — medication → HR-calibration explainer (only when meds entered; non-diagnostic)

    /// Shown ONLY when the user entered medications on the Health step (gated by `shouldSkip`). Surfaces,
    /// factually and non-diagnostically, the PlanBuilder logic: Recovery and HR zones read from the user's
    /// OWN baseline, so beta-blockers / stimulants that shift heart rate don't skew the score. No medical
    /// claims, no advice — just how the number is computed.
    private var medExplainerScreen: some View {
        OnboardingIntro(
            eyebrow: "About your medications",
            icon: "waveform.path.ecg.rectangle", tint: Theme.blue,
            headline: "Your scores read from your baseline, not a formula.",
            body_: "Some medications — beta-blockers, stimulants and others — raise or lower heart rate. HUMANS judges Recovery and your heart-rate zones against your own 28-day baseline, so the score reflects your real readiness rather than the medication. Weight is read on the 7-day trend, not single days.",
            features: [
                OBFeature(icon: "heart.fill", title: "Recovery from your own history", detail: "Compared to your personal baseline, not an age-based average.", tint: Theme.primary),
                OBFeature(icon: "chart.line.uptrend.xyaxis", title: "Trends over single days", detail: "Water and appetite can shift day to day — the 7-day trend is what counts.", tint: Theme.orange)
            ],
            primaryTitle: "Got it",
            showBack: true, progress: progress,
            onBack: back, onPrimary: advance
        )
    }

    // MARK: v4 item 5 — chronotype single-question screen (near Lifestyle)

    private var chronotypeScaffold: some View {
        OnboardingScaffold(progress: progress, title: title(.chronotype),
                           subtitle: "When do you naturally feel sharpest? We'll keep this to time reminders and training suggestions around your rhythm.",
                           showBack: idx > 0, canClose: canSkip, continueEnabled: true,
                           onSkip: skip,
                           centerContent: true,
                           onBack: back, onClose: { dismiss() }, onContinue: advance) {
            options(IntakeProfile.Chronotype.allCases, selected: $p.chronotype, detail: { $0.detail })
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
            field("Your first name") { OBTextField(text: $p.name, placeholder: "e.g. Ahmed", caps: .words) }
            field("Sex (for the metabolism formula)") { sexSegmented }
            HStack(spacing: 12) {
                field("Birth year") { obNum($birthYearText, "1985", decimal: false) }
                field("Height (cm)") { obNum($heightText, "175") }
            }
            HStack(spacing: 12) {
                field("Current weight (kg)") { obNum($weightText, "90") }
                // v5 item 3: keep the label a single line so the 2-column row stays aligned; the field's
                // own placeholder ("optional") communicates it isn't required.
                field("Waist at navel (cm)") { obNum($waistText, "optional") }
            }
        }
    }

    /// P1-1: on-brand numeric field for onboarding (raised surface + hairline + emerald focus ring),
    /// replacing the near-black shared `NumField` on the About-you / Supplements screens.
    private func obNum(_ text: Binding<String>, _ placeholder: String, decimal: Bool = true) -> some View {
        OBTextField(text: text, placeholder: placeholder, caps: .never,
                    keyboard: decimal ? .decimalPad : .numberPad)
    }

    /// P1-2: Male/Female segmented control with an emerald-filled selected segment and a recessed track,
    /// clearly higher contrast than the default system segmented picker on a dark surface.
    private var sexSegmented: some View {
        HStack(spacing: 6) {
            ForEach(Array(IntakeProfile.Sex.allCases)) { c in
                let on = p.sex == c
                Button { withAnimation(.easeInOut(duration: 0.15)) { p.sex = c } } label: {
                    Text(c.label)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(on ? Color.black : Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(on ? Theme.primary : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: 0x20292F), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0x2C3940), lineWidth: 1))
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
    // Metric-backed habits auto-tick from Health/meals/workouts once tracked.
    private static let habitChoices: [HabitMetric] =
        [.steps, .water, .protein, .sleepDuration, .meditation, .sunExposure, .floors, .workoutCount, .mood]

    // v5 item 5: extend the picker with common daily habits people actually track. These are
    // check-in-style library templates (a single yes/no tick a day). Each carries its own name + SF Symbol
    // glyph, so every chip has a leading glyph consistent with build 52. Ids reference HabitLibrary.all so
    // selecting one writes a fully-configured HabitDef on apply (see Store.applyIntake).
    private static let habitTemplateChoices: [HabitTemplate] = {
        // Note: no "meditate" here — the metric-backed .meditation chip above already covers it.
        let ids = ["nosugar", "read", "journal", "stretch", "noalcohol", "veggies", "coldshower", "vitamins", "breathe", "noscreens", "gratitude"]
        return ids.compactMap { id in HabitLibrary.all.first { $0.id == id } }
    }()

    private var habitsStep: some View {
        Group {
            intro("Pick a few daily habits to build. We'll add them to your tracker — you can change them any time.")
            habitChips
            if p.wantedHabits.isEmpty && p.wantedHabitTemplates.isEmpty {
                Text("No pressure — leave this empty and we'll start you with Steps, Water and Protein.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
            }
        }
    }

    /// P1-4 + P2 + v5-5: one wrapping grid of habit chips — metric-backed first, then common check-in
    /// habits — each with a leading monoline glyph; selected = emerald-tinted fill + a check, matching the
    /// device-chip / explainer-card icon quality.
    private var habitChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.habitChoices) { m in
                let on = p.wantedHabits.contains(m)
                habitChip(icon: m.icon, title: m.title, on: on) {
                    if on { p.wantedHabits.remove(m) } else { p.wantedHabits.insert(m) }
                }
            }
            ForEach(Self.habitTemplateChoices) { t in
                let on = p.wantedHabitTemplates.contains(t.id)
                habitChip(icon: t.icon, title: t.name, on: on) {
                    if on { p.wantedHabitTemplates.remove(t.id) } else { p.wantedHabitTemplates.insert(t.id) }
                }
            }
        }
    }

    @ViewBuilder private func habitChip(icon: String, title: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark" : icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(on ? Color.black : Theme.primary)
                Text(title).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(on ? Color.black : Theme.text)
            }
            .padding(.vertical, 9).padding(.horizontal, 13)
            .background(on ? Theme.primary : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.primary : Theme.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// The combined tracked list the picker renders — catalog picks (in catalog order) + any custom entries.
    /// PER-USER: driven entirely by this profile's `supplementsWanted` + `customSupplements`.
    private var onboardingTrackedSupplements: [TrackedSupplement] {
        let catalog = Plan.supplementCatalog
            .filter { p.supplementsWanted.contains($0.key) }
            .map(TrackedSupplement.init)
        return catalog + p.customSupplements
    }

    private var supplementsStep: some View {
        // v5 item 6: these are PER-USER — supplementsWanted / customSupplements live in this user's own
        // IntakeProfile (defaults: [] and []), so a brand-new profile shows nothing tracked. No auto-select.
        // The searchable picker replaces both the fixed 4-row list and the old free-text box (custom-add
        // covers "anything else you take"). No cap — add as many as you want.
        Group {
            intro("Search the library and tap to add the ones you want to track each day — we'll show just those on your Today screen. Can't find it? Type the name and add your own.")
            SupplementPicker(
                tracked: onboardingTrackedSupplements,
                setCatalog: { key, on in
                    if on { p.supplementsWanted.insert(key) } else { p.supplementsWanted.remove(key) }
                },
                addCustom: { name in
                    let entry = TrackedSupplement.custom(named: name)
                    guard !entry.name.isEmpty, !p.customSupplements.contains(where: { $0.id == entry.id }) else { return }
                    p.customSupplements.append(entry)
                },
                remove: { id in
                    p.supplementsWanted.remove(id)
                    p.customSupplements.removeAll { $0.id == id }
                }
            )
        }
    }

    // MARK: sign-in gate

    private var signInScreen: some View {
        OnboardingSignIn(
            progress: 0,
            isWorking: cloud.isSignedIn && cloud.isResolvingSignIn,
            onRequest: cloud.prepareAppleRequest,
            onCompletion: { result in
                didBranch = false            // a fresh sign-in should re-evaluate the branch
                cloud.handleApple(result)
            },
            onGuest: {
                isGuest = true
                withAnimation(.easeInOut(duration: 0.25)) { idx += 1 }   // into the questionnaire, local
            },
            onBack: idx > 0 ? { back() } : nil,
            errorText: cloud.lastError
        )
    }

    private var restoreFailure: String? {
        if case .failed(let m) = cloud.restoreState { return m } else { return nil }
    }

    private var welcomeBackScreen: some View {
        OnboardingWelcomeBack(
            name: cloud.email?.split(separator: "@").first.map(String.init) ?? p.name,
            failed: restoreFailure,
            onRetry: { cloud.retryRestore() }
        )
        .onChange(of: cloud.restoreState) { _, s in
            // Real fetch landed → data is in the store; leave onboarding and drop into the app.
            if s == .restored { finishRestore() }
        }
        .onAppear {
            if cloud.restoreState == .restored { finishRestore() }
        }
    }

    /// Returning user: the plan is already merged into the store by CloudSync — just dismiss (no applyIntake,
    /// no questionnaire). Guard so it fires once.
    private func finishRestore() {
        guard showWelcomeBack else { return }
        showWelcomeBack = false
        dismiss()
    }

    // MARK: connect-your-device step

    private var connectDeviceScreen: some View {
        // Debug: `-connectScroll bottom` starts the step scrolled down so the phone-only card + honest
        // note are screenshot-able.
        let anchor: UnitPoint? = UserDefaults.standard.string(forKey: "connectScroll") == "bottom" ? .bottom : nil
        return OnboardingScaffold(progress: progress, title: "Connect your device",
                           subtitle: "Recovery, Strain and Sleep come from a wearable. Connect one now, or start phone-only and add one later.",
                           showBack: true, canClose: false,
                           continueTitle: "Continue", continueEnabled: true,
                           onSkip: skip,
                           scrollAnchor: anchor,
                           onBack: back, onContinue: advance) {
            connectDeviceCards
        }
        // v5 item 7: mis-tap guard for "No wearable", and a brief success beat when a device links.
        .overlay { connectConfirmOverlay }
        // Debug: `-obConfirmPhoneOnly` auto-presents the no-wearable confirm for QA/screenshots.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "obConfirmPhoneOnly") { confirmPhoneOnly = true }
        }
    }

    @ViewBuilder private var connectConfirmOverlay: some View {
        if confirmPhoneOnly {
            OBConfirmDialog(
                icon: "iphone",
                tint: Theme.blue,
                title: "Continue without a wearable?",
                message: "Recovery, Strain & Sleep need one — you can add it any time in Settings.",
                primaryTitle: "Use a wearable",
                secondaryTitle: "Continue phone-only",
                onPrimary: { withAnimation(.easeInOut(duration: 0.2)) { confirmPhoneOnly = false } },
                onSecondary: {
                    confirmPhoneOnly = false
                    p.hasAppleWatch = false
                    advance()
                }
            )
        } else if let device = wearableConnected {
            OBConfirmDialog(
                icon: "checkmark.seal.fill",
                tint: Theme.primary,
                title: "\(device) connected",
                message: "Your Recovery, Strain and Sleep scores will fill in as HUMANS reads your data.",
                primaryTitle: "Continue",
                secondaryTitle: "Connect another",
                onPrimary: {
                    wearableConnected = nil
                    advance()
                },
                onSecondary: { withAnimation(.easeInOut(duration: 0.2)) { wearableConnected = nil } }
            )
        }
    }

    @State private var humansInterest = UserDefaults.standard.bool(forKey: "humansWearableInterest")
    /// v5 item 7: mis-tap guards on the connect step. `confirmPhoneOnly` gates the "No wearable" choice;
    /// `wearableConnected` shows a brief success beat after a device links (nil = no dialog).
    @State private var confirmPhoneOnly = false
    @State private var wearableConnected: String? = nil

    private var connectDeviceCards: some View {
        VStack(spacing: 12) {
            // Apple Watch → HealthKit permission prompt (steps, HR, HRV, sleep).
            OBDeviceCard(icon: "applewatch", title: "Apple Watch",
                         note: "Steps, heart rate, HRV and sleep — the full Recovery, Strain and Sleep scores.") {
                if hk.hasConnected { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.primary) }
            }
            connectButtonRow(
                title: hk.hasConnected ? "Apple Health connected" : (hk.isSyncing ? "Requesting access…" : "Connect Apple Watch"),
                enabled: hk.isAvailable && !hk.isSyncing && !hk.hasConnected
            ) {
                p.hasAppleWatch = true
                Task {
                    await hk.connectAndSync(store: store, days: 30)
                    // v5 item 7: brief success beat once access is granted (a positive confirm, like the
                    // phone-only guard). If access was denied hasConnected stays false and we show nothing.
                    if hk.hasConnected {
                        await MainActor.run { withAnimation(.easeInOut(duration: 0.2)) { wearableConnected = "Apple Watch" } }
                    }
                }
            }

            // Oura / WHOOP → vendor connect (reuse the existing WearableLink plumbing).
            ForEach(WearableLink.vendors, id: \.self) { vendor in vendorCard(vendor) }

            // HUMANS — own-brand wearable, not connectable. Optional local "Notify me" (no backend).
            OBDeviceCard(icon: "sparkles", title: "HUMANS", note: "Our own band, built for these scores. In development.",
                         tint: Theme.orange, comingSoon: true) {
                Button {
                    humansInterest.toggle()
                    UserDefaults.standard.set(humansInterest, forKey: "humansWearableInterest")
                } label: {
                    Text(humansInterest ? "Notified" : "Notify me")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(humansInterest ? Theme.muted : Theme.orange)
                }
                .buttonStyle(.plain)
            }

            // Phone-only — honest note that wearable scores need a device (no faked scores).
            OBDeviceCard(icon: "iphone", title: "No wearable — use my phone",
                         note: "Track steps and motion from your iPhone and log meals by hand.",
                         tint: Theme.blue) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.muted)
            }
            // v5 item 7: confirm before skipping wearable setup — a mis-tap here shouldn't advance silently.
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { confirmPhoneOnly = true } }

            Text("Recovery, Strain and Sleep need a wearable — add one any time from Profile to unlock them.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .id("connect-bottom")

            if let e = link.lastError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { if cloud.isSignedIn { await link.refreshStatus() } }
    }

    @ViewBuilder private func connectButtonRow(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .heavy))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(enabled ? Theme.primary : Theme.muted)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(enabled ? Theme.primary.opacity(0.5) : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    @ViewBuilder private func vendorCard(_ vendor: String) -> some View {
        let meta: (String, String, String) = vendor == "whoop"
            ? ("waveform.path.ecg", "WHOOP", "HRV, recovery, sleep and workouts from WHOOP.")
            : ("circle.circle", "Oura", "HRV, readiness, sleep stages and SpO₂ from Oura.")
        let st = link.status[vendor]
        let busy = link.busy == vendor
        VStack(spacing: 8) {
            OBDeviceCard(icon: meta.0, title: meta.1, note: meta.2, tint: Color(hex: 0x9B8CFF)) {
                if st?.linked == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.primary) }
            }
            if !cloud.isSignedIn {
                Text("Sign in to link \(meta.1).").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if st?.configured == false {
                Text("\(meta.1) connect isn't available yet.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if st?.linked == true {
                connectButtonRow(title: busy ? "Syncing…" : "Sync now", enabled: !busy) {
                    Task { await link.sync(vendor, store: store) }
                }
            } else {
                connectButtonRow(title: busy ? "Connecting…" : "Connect \(meta.1)", enabled: !busy) {
                    Task {
                        await link.connect(vendor, store: store)
                        if link.status[vendor]?.linked == true {
                            await MainActor.run { withAnimation(.easeInOut(duration: 0.2)) { wearableConnected = meta.1 } }
                        }
                    }
                }
            }
        }
    }

    // MARK: collision confirm (guest → existing account)

    @ViewBuilder private var collisionOverlay: some View {
        if cloud.pendingCollision != nil {
            CollisionConfirmView(
                onUseSaved: {
                    cloud.resolveCollision(useCloud: true)
                    didBranch = true
                    withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = true }
                },
                onKeepEntered: {
                    cloud.resolveCollision(useCloud: false)
                    didBranch = true
                    // Keep going through the questionnaire flow with the just-entered answers.
                    if idx <= (steps.firstIndex(of: .signIn) ?? 0) {
                        withAnimation(.easeInOut(duration: 0.25)) { idx += 1 }
                    }
                }
            )
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
                    // v5 item 4: label centred in the pill (multiline-centre + fixed min height so a
                    // wrapping word like "Burnt out" doesn't shove the row out of alignment).
                    Text(["Calm", "Fine", "Busy", "Stressed", "Burnt out"][n - 1])
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(on ? Color.black : Theme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .padding(.vertical, 8)
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
extension IntakeProfile.Chronotype: LabeledOption {}
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
