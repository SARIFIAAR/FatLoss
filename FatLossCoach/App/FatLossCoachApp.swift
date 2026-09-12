import SwiftUI

@main
struct FatLossCoachApp: App {
    @State private var store = Store()
    @State private var health = HealthKitManager()
    @State private var cloud = CloudSync()
    @State private var scanner = MealScanner()
    @State private var reminders = ReminderManager()
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
                if health.hasConnected {
                    Task { await health.sync(store: store, days: 7); reminders.schedulePlan() }
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
    /// New profile (no answers, no data) → questionnaire first. `-onboarding 1` forces it for screenshots.
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
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(text: t)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .task {
            if UserDefaults.standard.bool(forKey: "onboarding") { showOnboarding = true; return }
            guard store.data.intake == nil && store.data.isEmpty else { return }
            // A reinstall keeps the Sign in with Apple session in the keychain, so an empty
            // store does NOT mean a new user — give auth a moment to resolve, and if it does,
            // wait for the Firestore snapshot to restore the data before deciding.
            if cloud.isConfigured {
                for _ in 0..<6 where !cloud.isSignedIn {                            // ~1.5 s for auth
                    try? await Task.sleep(for: .milliseconds(250))
                }
                for _ in 0..<40 where cloud.isSignedIn && store.data.isEmpty {      // ~10 s for restore
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            if store.data.intake == nil && store.data.isEmpty { showOnboarding = true }
        }
        .onChange(of: store.data.isEmpty) { _, empty in
            // Cloud restore landed while the questionnaire was up (slow network) — drop it.
            if !empty && showOnboarding && store.data.intake != nil { showOnboarding = false }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(existing: store.data.intake,
                           canSkip: !store.data.isEmpty || cloud.isSignedIn) { store.applyIntake($0) }
        }
    }
}
