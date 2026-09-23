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

/// The splash: HUMANS logo centred on the OBAmbient dark background while the route resolves. When a cloud
/// restore is in flight it shows the honest "Welcome back / Restoring your plan…" beat instead of a bare
/// logo, so a returning user on a slow network sees progress rather than a stall.
struct SplashView: View {
    var restoring: Bool
    var name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var spin = false

    var body: some View {
        ZStack {
            OBAmbient()
            VStack(spacing: 22) {
                Image("SplashLogo")
                    .resizable().scaledToFit().frame(height: 92)
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
