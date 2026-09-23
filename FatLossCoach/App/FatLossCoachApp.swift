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
            // Root is the SPLASH ROUTER (build 53), not the TabView. It decides onboarding-vs-app on the
            // splash BEFORE Home is ever constructed, fixing the "Home flashes then onboarding" bug.
            RootRouter()
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
            // after finishing setup). The onboarding route presents its own copy while it's up; here in the
            // app route onboarding is never on screen, so this is safe to always show.
            if cloud.pendingCollision != nil {
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
            // Debug: present the collision confirm for screenshots (`-showCollision 1`). The route decision
            // (onboarding vs app) now lives in RootRouter; ContentView only ever renders in the app route.
            if UserDefaults.standard.bool(forKey: "showCollision") {
                try? await Task.sleep(for: .milliseconds(600))   // let the initial auth(nil) settle first
                cloud.debugPresentCollision()
            }
        }
    }
}
