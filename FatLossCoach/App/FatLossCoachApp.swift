import SwiftUI
import UIKit

@main
struct FatLossCoachApp: App {
    @State private var store = Store()
    @State private var health = HealthKitManager()
    @State private var cloud = CloudSync()
    @State private var scanner = MealScanner()
    @State private var reminders = ReminderManager()
    @State private var wearables = WearableLink()
    @State private var photoSync = PhotoSync()
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
                    // Photo sync: attach BEFORE cloud so the auth listener can start it once a uid resolves.
                    photoSync.attach(store: store)
                    store.photoSync = photoSync
                    cloud.attach(store: store, photoSync: photoSync)
                    reminders.attach(store: store)
                    reminders.schedulePlan()
                    // Debug: `-debugLogWeight 101.5` performs a write on launch (crash repro / automation).
                    let w = UserDefaults.standard.double(forKey: "debugLogWeight")
                    if w > 0 { store.logWeight(w) }
                    // Debug/QA (screenshots): `-seedProgressPhotos 1` seeds two SYNTHETIC placeholder photos
                    // (never real body photos) so the timeline + compare can be captured. No-op if photos exist.
                    if UserDefaults.standard.bool(forKey: "seedProgressPhotos") { seedDemoProgressPhotos() }
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

    /// Seed two SYNTHETIC gradient placeholder images as progress photos for screenshots/QA. Never real
    /// body photos. Dated ~6 weeks apart so the timeline + compare read as before/after.
    private func seedDemoProgressPhotos() {
        guard store.progressPhotosOnDevice.isEmpty else { return }
        func placeholder(_ top: UIColor, _ bottom: UIColor, _ label: String) -> UIImage {
            let size = CGSize(width: 600, height: 800)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let cg = ctx.cgContext
                let colors = [top.cgColor, bottom.cgColor] as CFArray
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .heavy),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]
                let s = NSString(string: label)
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: size.height / 2 - sz.height / 2), withAttributes: attrs)
            }
        }
        let firstDate = DateKey.key(DateKey.daysAgo(42))
        let latestDate = DateKey.key(DateKey.daysAgo(2))
        store.addProgressPhoto(placeholder(UIColor(hex: 0x2B3A42), UIColor(hex: 0x101518), "Week 1"),
                               on: firstDate, weightKg: 104.5, note: "Starting out — sample photo.")
        store.addProgressPhoto(placeholder(UIColor(hex: 0x1E4D3A), UIColor(hex: 0x101518), "Week 6"),
                               on: latestDate, weightKg: 99.2, note: "Six weeks in — sample photo.")
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
        .onReceive(NotificationCenter.default.publisher(for: .openTrain)) { _ in tab = 2 }
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
