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
    @State private var vb9 = VB9Manager()        // parked — replaced by the QRing/VY28C ring
    @State private var qring = QRingManager()
    @State private var photoSync = PhotoSync()
    @State private var docSync = DocSync()
    @State private var content = ContentService()
    @State private var appLock = AppLock()
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
                .environment(vb9)
                .environment(qring)
                .environment(content)
                .environment(appLock)
                .environment(docSync)
                .onOpenURL { store.handle(url: $0) }
                .task {
                    // Photo sync: attach BEFORE cloud so the auth listener can start it once a uid resolves.
                    photoSync.attach(store: store)
                    store.photoSync = photoSync
                    docSync.attach(store: store)
                    store.docSync = docSync
                    cloud.attach(store: store, photoSync: photoSync, docSync: docSync)
                    reminders.attach(store: store)
                    reminders.schedulePlan()
                    // HUMANS Ring (QRing / VY28C) is the active band. VB9 is parked (code kept, not started).
                    qring.attach(store: store)
                    qring.start()
                    // Remote meal programs: fetch on launch so the Nutrition tab is fresh when opened.
                    // `-contentSeedOnly 1` (QA / offline-fallback repro) skips the fetch and keeps the
                    // cache/bundled-Ariana seed.
                    if !content.seedOnly { content.refresh() }
                    // Debug: `-debugLogWeight 101.5` performs a write on launch (crash repro / automation).
                    let w = UserDefaults.standard.double(forKey: "debugLogWeight")
                    if w > 0 { store.logWeight(w) }
                    // Debug/QA (screenshots): `-seedProgressPhotos 1` seeds two SYNTHETIC placeholder photos
                    // (never real body photos) so the timeline + compare can be captured. No-op if photos exist.
                    if UserDefaults.standard.bool(forKey: "seedProgressPhotos") { seedDemoProgressPhotos() }
                    // Debug/QA: `-arianaLog ariana-b01` logs that Ariana recipe into today's matching
                    // slot on launch, to verify the "Log to today's …" write without tapping.
                    if let rid = UserDefaults.standard.string(forKey: "arianaLog"),
                       let r = MealProgram.ariana.recipes.first(where: { $0.id == rid }) {
                        store.addMeal(r.mealEntry(on: store.today))
                    }
                    // Debug/QA: `-vaultPreview 1` seeds a sample document so the vault screenshot isn't empty.
                    if UserDefaults.standard.bool(forKey: "vaultPreview") { seedDemoDocument() }
                }
                // Biometric app lock (E1-04): covers the whole app (splash/onboarding included) while locked.
                .overlay {
                    if appLock.enabled && appLock.isLocked {
                        LockView().environment(appLock).transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: appLock.isLocked)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.save()
                appLock.lockOnBackground()
            case .active:
                if !appLock.previewMode { appLock.unlock() }
                reminders.refreshPermission()
                WidgetSync.publish(from: store)
                // Ring data only refreshed on connect before — a ring that stays connected went stale
                // (HR range / HRV / SpO₂ frozen at connect-time values). Re-sync on every foreground;
                // the bridge's overlap guard makes this safe to call repeatedly.
                if qring.connected != nil { Task { await qring.syncHistory() } }
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

    /// Seed one synthetic PDF into the vault for the `-vaultPreview 1` screenshot. No-op if docs exist.
    private func seedDemoDocument() {
        guard store.documents.isEmpty else { return }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let pdf = renderer.pdfData { ctx in
            ctx.beginPage()
            NSString(string: "Sample Lab Report (demo)").draw(at: CGPoint(x: 40, y: 60),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        }
        store.addDocument(data: pdf, contentType: "application/pdf", title: "Blood test – Oct 2026", category: .bloods)
        store.addDocument(data: pdf, contentType: "application/pdf", title: "InBody report – Sep 2026", category: .inbody)
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
    /// Debug/QA: `-vaultPreview 1` opens the document vault (gate bypassed) for a screenshot.
    @State private var qaVault = UserDefaults.standard.bool(forKey: "vaultPreview")

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
        .fullScreenCover(isPresented: $qaVault) { DocumentVaultView() }
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
