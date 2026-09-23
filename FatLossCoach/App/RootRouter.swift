import SwiftUI

/// Root of the app (build 53). Fixes the "Home flashes, then onboarding slides up over it" bug:
/// previously the TabView (ContentView) was the WindowGroup root and onboarding was a fullScreenCover
/// flipped on ~1.5 s later, so Home always drew first. Now a SPLASH decides the route BEFORE any real
/// screen is drawn — Home is only ever constructed once the route resolves to `.app`.
///
/// Decision order (all on the splash, over the dark ambient background):
///   1. Debug launch args (`-showCollision`, `-onboarding`, `-obStep`) short-circuit for QA/screenshots.
///   2. Local plan present (`intake != nil` or non-empty data) → returning user → `.app` immediately.
///   3. Cloud configured: wait briefly for the auth session to resume, then for a cloud restore to land.
///      • signed-in + data restored  → `.app` (the returning-user "Restoring…" beat lives in onboarding's
///        welcomeBack when it's the sign-in that triggers it; here the silent-resume path just waits).
///      • nothing restores           → `.onboarding` (new / signed-out user; the flow owns sign-in).
///   4. Not configured / no session  → `.onboarding`.
struct RootRouter: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud

    enum Route: Equatable { case splash, onboarding, app }
    @State private var route: Route = .splash
    /// When resolving involves a cloud round-trip, show the honest "Welcome back / Restoring" beat on the
    /// splash rather than a bare logo, so a returning user on a slow network sees progress (not a stall).
    @State private var restoring = false
    @State private var decided = false

    var body: some View {
        ZStack {
            switch route {
            case .splash:
                SplashView(restoring: restoring, name: splashName)
            case .app:
                // Home is constructed ONLY here — after the route is decided. It can never precede the splash.
                ContentView()
            case .onboarding:
                // The guided flow owns marketing → Sign in with Apple → branch. Presented as the root (not a
                // cover over Home) so nothing is behind it.
                OnboardingView(existing: store.data.intake, canSkip: false) { intake in
                    store.applyIntake(intake)
                    withAnimation(.easeInOut(duration: 0.25)) { route = .app }
                }
                // A returning user who signs in during onboarding lands back here once their data is merged;
                // onboarding dismisses itself and we drop into the app.
                .onChange(of: store.data.isEmpty) { _, empty in
                    if !empty && store.data.intake != nil {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .app }
                    }
                }
            }
        }
        .transition(.opacity)
        .task { await resolve() }
    }

    private var splashName: String {
        cloud.email?.split(separator: "@").first.map(String.init) ?? store.data.intake?.name ?? ""
    }

    /// Resolve the route ONCE, on the splash, before any real screen is drawn.
    private func resolve() async {
        guard !decided else { return }
        decided = true

        // 1. Debug overrides (QA / screenshots).
        let d = UserDefaults.standard
        // `-splashHold <seconds>` keeps the splash on screen so QA can film the data-flow animation. It only
        // delays the resolve; it does not change which route is chosen. No effect unless the arg is passed.
        if d.object(forKey: "splashHold") != nil {
            let hold = max(0, d.double(forKey: "splashHold"))
            if hold > 0 { try? await Task.sleep(for: .seconds(hold)) }
        }
        // `-showCollision` exercises the in-app collision overlay (ContentView owns it) → route to the app.
        if d.bool(forKey: "showCollision") {
            withAnimation(.easeInOut(duration: 0.25)) { route = .app }
            return
        }
        // `-onboarding` / `-obStep <name>` force the guided flow (implies onboarding) for screenshots.
        if d.bool(forKey: "onboarding") || d.string(forKey: "obStep") != nil {
            withAnimation(.easeInOut(duration: 0.25)) { route = .onboarding }
            return
        }

        // 2. Local plan already on device → returning user, go straight to the app (no flash of onboarding).
        if store.data.intake != nil || !store.data.isEmpty {
            withAnimation(.easeInOut(duration: 0.25)) { route = .app }
            return
        }

        // 3. Cloud path: let auth resume and a restore land before deciding new-vs-returning.
        if cloud.isConfigured {
            for _ in 0..<6 where !cloud.isSignedIn {                       // ~1.5 s for the session to resume
                try? await Task.sleep(for: .milliseconds(250))
            }
            if cloud.isSignedIn {
                restoring = true                                          // show the "Restoring…" beat
                for _ in 0..<40 where store.data.isEmpty {                // ~10 s for the Firestore snapshot
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }

        // 4. Decide. Data present → app; still empty → genuinely new/signed-out → onboarding.
        let hasPlan = store.data.intake != nil || !store.data.isEmpty
        withAnimation(.easeInOut(duration: 0.3)) { route = hasPlan ? .app : .onboarding }
    }
}

/// The splash: HUMANS mark centred on the OBAmbient dark background while the route resolves. When a cloud
/// restore is in flight it shows the honest "Welcome back / Restoring your plan…" beat instead of a bare
/// logo, so a returning user on a slow network sees progress rather than a stall.
///
/// The mark is now the TRANSPARENT `SplashMark` asset (the H alone — no baked navy square), sitting on the
/// ambient background. Over it rides a quiet, looping "data-flow" animation that embodies the mark's meaning:
/// the H's RIGHT leg is orange/organic ("the body"), the LEFT leg is blue with a circuit line + nodes
/// ("the app"). `SplashDataFlow` emits a handful of small glowing pulses that leave the body (right), cross
/// the centre pinch, shift emerald→blue as they travel, and land into the app (left) with a soft bloom. It
/// reads at a glance as "body → app". Motion is garnish: under `reduceMotion` (or while `restoring`) the
/// pulses are suppressed and only the static mark (plus the restore spinner) shows.
struct SplashView: View {
    var restoring: Bool
    var name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var spin = false

    /// Height of the mark; the flow overlay is sized off the same box so the path tracks the H's legs.
    private let markSize: CGFloat = 92

    var body: some View {
        ZStack {
            OBAmbient()
            VStack(spacing: 22) {
                ZStack {
                    Image("SplashMark")
                        .resizable().scaledToFit().frame(width: markSize, height: markSize)
                    // Data-flow pulses ride just over the mark's mid-band; the crisp H stays legible beneath.
                    // Suppressed while restoring (the spinner owns motion then) and under reduceMotion.
                    if !reduceMotion && !restoring {
                        SplashDataFlow()
                            .frame(width: markSize, height: markSize)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: appeared)

                if restoring {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.08), lineWidth: 6).frame(width: 42, height: 42)
                            Circle().trim(from: 0, to: 0.25)
                                .stroke(AngularGradient(gradient: Gradient(colors: [Theme.primary.opacity(0.4), Theme.primaryLight]), center: .center),
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 42, height: 42)
                                .rotationEffect(.degrees(spin ? 360 : 0))
                        }
                        Text(name.isEmpty ? "Welcome back — restoring your plan…" : "Welcome back, \(name) — restoring your plan…")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(restoring ? "Restoring your plan" : "HUMANS")
    }
}

/// The splash's "data-flow" garnish: a small, seamless loop of glowing pulses that leave the H's RIGHT leg
/// (the body), travel LEFT across the centre pinch, and settle into the LEFT leg (the app) with a soft bloom.
///
/// Structure (all driven by one `TimelineView(.animation)` clock, drawn in a single `Canvas`):
///  • Coordinate model — the mark is square; the H's legs sit near x≈0.30 (app) and x≈0.70 (body), joined by a
///    crossbar around y≈0.50. Pulses ride the mid-band: they start at the body leg, dip slightly toward the
///    pinch (a gentle sine bow), and rise back into the app leg. All positions are fractions of the frame, so
///    the path tracks the H at any `markSize`.
///  • Timing — CYCLE = 2.4 s, looped by `fmod` so it repeats seamlessly. `PULSES` (5) are evenly staggered by
///    phase offset i/PULSES, so at any instant a few dots are strung along the current, not bunched.
///  • Per-pulse motion — normalized progress p∈[0,1) with an ease-in-out so a dot accelerates off the body and
///    eases into the app. x interpolates bodyX→appX (right→left); hue shifts emerald→blue as it crosses (tying
///    the dot to the leg it's heading into); alpha fades in at birth and out on arrival so nothing pops.
///  • Current + bloom — a faint horizontal streak sits under the dots the whole time (the "wire"); when a
///    pulse's progress is near 1 it feeds a soft bloom centred on the app leg that brightens briefly, reading
///    as the signal "landing". Bloom intensity is the summed arrival-weight of all pulses, so landings overlap
///    smoothly instead of blinking.
///
/// Deliberately quiet: 5 small blurred dots + one thin streak + a gentle left bloom. Not a particle storm.
/// The caller only mounts this when motion is allowed and no restore is in flight.
private struct SplashDataFlow: View {
    private let cycle: Double = 2.4
    private let pulseCount = 5

    // Path anchors as fractions of the (square) mark box.
    private let bodyX: CGFloat = 0.70   // right leg — the body, where pulses are emitted
    private let appX:  CGFloat = 0.30   // left leg — the app, where pulses arrive
    private let midY:  CGFloat = 0.50   // crossbar height
    private let bow:   CGFloat = 0.05   // how far the path dips toward the pinch mid-travel

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height

                func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: px * w, y: py * h) }

                // Progress of pulse i, staggered and looped seamlessly.
                func progress(_ i: Int) -> Double {
                    let offset = Double(i) / Double(pulseCount)
                    return (t / cycle + offset).truncatingRemainder(dividingBy: 1)
                }
                // Ease-in-out so a dot leaves the body and settles into the app rather than moving linearly.
                func eased(_ p: Double) -> Double { p * p * (3 - 2 * p) }

                // 1. The faint "current" streak under the dots (the wire the signal rides).
                var wire = Path()
                let steps = 24
                for s in 0...steps {
                    let p = Double(s) / Double(steps)
                    let e = eased(p)
                    let x = bodyX + (appX - bodyX) * e
                    let y = midY + bow * CGFloat(sin(p * .pi))   // gentle bow toward the pinch
                    let pt = point(x, y)
                    if s == 0 { wire.move(to: pt) } else { wire.addLine(to: pt) }
                }
                ctx.stroke(wire, with: .color(.white.opacity(0.05)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // 2. Accumulate arrival-weight for the landing bloom while drawing each pulse.
                var bloom = 0.0
                for i in 0..<pulseCount {
                    let p = progress(i)
                    let e = eased(p)
                    let x = bodyX + (appX - bodyX) * e
                    let y = midY + bow * CGFloat(sin(p * .pi))

                    // Fade in over the first 15%, hold, fade out over the last 20%.
                    let fadeIn  = min(1, p / 0.15)
                    let fadeOut = min(1, (1 - p) / 0.20)
                    let alpha   = max(0, min(fadeIn, fadeOut))

                    // Emerald (body) → blue (app) as it crosses. Emerald ~150°, blue ~215° hue.
                    let hue = (150.0 + (215.0 - 150.0) * e) / 360.0
                    let dot = Color(hue: hue, saturation: 0.55, brightness: 1.0)

                    // Landing weight: ramps up over the last ~25% of travel.
                    bloom += max(0, (p - 0.75) / 0.25) * alpha

                    let c = point(x, y)
                    let r: CGFloat = 3.0
                    // Soft glow halo, then a crisp white-hot core.
                    let halo = Path(ellipseIn: CGRect(x: c.x - r*2.2, y: c.y - r*2.2, width: r*4.4, height: r*4.4))
                    ctx.fill(halo, with: .color(dot.opacity(0.22 * alpha)))
                    let core = Path(ellipseIn: CGRect(x: c.x - r*0.6, y: c.y - r*0.6, width: r*1.2, height: r*1.2))
                    ctx.fill(core, with: .color(.white.opacity(0.9 * alpha)))
                    let mid = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
                    ctx.fill(mid, with: .color(dot.opacity(0.7 * alpha)))
                }

                // 3. The soft bloom on the app (left) leg when pulses land.
                let b = min(1.0, bloom)
                if b > 0.01 {
                    let c = point(appX, midY)
                    let br: CGFloat = 14
                    let g = Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: br*2, height: br*2))
                    // App-blue bloom, kept gentle so it brightens rather than flares.
                    ctx.fill(g, with: .color(Color(hue: 215.0/360.0, saturation: 0.5, brightness: 1.0).opacity(0.18 * b)))
                }
            }
            .blur(radius: 0.6)   // just enough to read as "glow", not sharp dots
        }
    }
}
