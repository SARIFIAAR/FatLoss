import SwiftUI

@main
struct FatLossCoachApp: App {
    @State private var store = Store()
    @State private var health = HealthKitManager()
    @State private var cloud = CloudSync()
    @State private var scanner = MealScanner()
    @State private var reminders = ReminderManager()
    @State private var wearables = WearableLink()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudSync.configureFirebaseIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(health)
                .environment(cloud)
                .environment(scanner)
                .environment(reminders)
                .environment(wearables)
                .onOpenURL { store.handle(url: $0) }
                .task {
                    cloud.attach(store: store)
                    reminders.attach(store: store)
                    reminders.schedulePlan()
                    // Debug: `-debugLogWeight 101.5` performs a write on launch (crash repro / automation).
                    let w = UserDefaults.standard.double(forKey: "debugLogWeight")
                    if w > 0 { store.logWeight(w) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.save()
            case .active:
                reminders.refreshPermission()
                WidgetSync.publish(from: store)
                if health.hasConnected {
                    Task { await health.sync(store: store, days: 7); reminders.schedulePlan(); reminders.notifyHealthAlertsIfNeeded() }
                } else {
                    reminders.schedulePlan()
                }
            default:
                break
            }
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    /// Launch with `-startTab 2` to open a specific tab (debug / screenshots).
    /// Profile has no tab anymore — `-startTab 4` opens Today with the profile sheet up.
    @State private var tab: Int = {
        let t = UserDefaults.standard.integer(forKey: "startTab")
        return t == 4 ? 0 : t
    }()
    /// Auth-first onboarding gate. A fresh install with no local plan shows the guided flow
    /// (marketing → Sign in with Apple → branch). `-onboarding 1` forces it for screenshots.
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }.tag(0)
            BodyView()
                .tabItem { Label("Body", systemImage: "heart.fill") }.tag(5)
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "leaf.fill") }.tag(3)
            WorkoutView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }.tag(2)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(1)
        }
        .tint(Theme.primary)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openBody)) { _ in tab = 5 }
        .onReceive(NotificationCenter.default.publisher(for: .openNutrition)) { _ in tab = 3 }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(text: t)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let c = store.celebration { CelebrationView(text: c) }
        }
        .overlay {
            // Guest → existing-account collision that happened OUTSIDE onboarding (e.g. Profile sign-in
            // after finishing setup). Onboarding presents its own copy while it's up.
            if cloud.pendingCollision != nil && !showOnboarding {
                CollisionConfirmView(
                    onUseSaved: { cloud.resolveCollision(useCloud: true) },
                    onKeepEntered: { cloud.resolveCollision(useCloud: false) }
                )
                .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .animation(.spring(duration: 0.4), value: store.celebration)
        .animation(.easeInOut(duration: 0.2), value: cloud.pendingCollision)
        .task {
            if UserDefaults.standard.bool(forKey: "showCollision") {
                try? await Task.sleep(for: .milliseconds(600))   // let the initial auth(nil) settle first
                cloud.debugPresentCollision(); return
            }
            if UserDefaults.standard.bool(forKey: "onboarding") { showOnboarding = true; return }
            // Debug: jump straight to a specific onboarding step for screenshots/QA (implies onboarding).
            if UserDefaults.standard.string(forKey: "obStep") != nil { showOnboarding = true; return }
            guard store.data.intake == nil && store.data.isEmpty else { return }
            // A returning user who is ALREADY signed in (normal launch, not a reinstall that cleared auth)
            // restores silently — give the auth session + Firestore snapshot a moment so we don't flash the
            // guided flow at them. If nothing restores, this is a genuinely new/local user → show onboarding,
            // which itself runs the marketing → Sign in with Apple → branch (the auth-first model).
            if cloud.isConfigured {
                for _ in 0..<6 where !cloud.isSignedIn {                            // ~1.5 s for auth to resume
                    try? await Task.sleep(for: .milliseconds(250))
                }
                for _ in 0..<40 where cloud.isSignedIn && store.data.isEmpty {      // ~10 s for restore
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            if store.data.intake == nil && store.data.isEmpty { showOnboarding = true }
        }
        .onChange(of: store.data.isEmpty) { _, empty in
            // Cloud restore landed while onboarding was up (slow network) — drop it.
            if !empty && showOnboarding && store.data.intake != nil { showOnboarding = false }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            // Auth-first: never `canSkip` on first-run (the flow owns sign-in + the returning-user branch).
            // Editing from Profile passes canSkip:true (questions-only) via its own presentation.
            OnboardingView(existing: store.data.intake, canSkip: false) { store.applyIntake($0) }
        }
    }
}
