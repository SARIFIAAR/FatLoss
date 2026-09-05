import SwiftUI

@main
struct FatLossCoachApp: App {
    @State private var store = Store()
    @State private var health = HealthKitManager()
    @State private var cloud = CloudSync()
    @State private var scanner = MealScanner()
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
                .onOpenURL { store.handle(url: $0) }
                .task {
                    cloud.attach(store: store)
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
                if health.hasConnected {
                    Task { await health.sync(store: store, days: 7) }
                }
            default:
                break
            }
        }
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    /// Launch with `-startTab 2` to open a specific tab (debug / screenshots).
    @State private var tab = UserDefaults.standard.integer(forKey: "startTab")

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }.tag(0)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(1)
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }.tag(2)
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "leaf.fill") }.tag(3)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(Theme.primary)
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(text: t)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
    }
}
