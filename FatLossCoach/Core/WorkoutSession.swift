import Foundation
import CoreLocation
import UIKit
import Observation

/// In-app workout tracker (Apple-Watch-style session logging): phone GPS for distance/pace, the
/// HUMANS ring for live heart rate. Saves the same `WorkoutEntry` the HealthKit import produces —
/// so zones feed Strain and the Physical Age activity levers — and, for outdoor walks/runs with
/// enough signal, derives a sub-maximal VO₂-max estimate (ACSM pace equation extrapolated over
/// heart-rate reserve). That estimate fills the Physical Age VO₂ input for ring-only users; a
/// Watch-measured value for the same day always wins (we never overwrite an existing one).
@Observable @MainActor
final class WorkoutSession: NSObject {

    enum Kind: String, CaseIterable, Identifiable {
        case walk = "Walk", run = "Run", cycle = "Cycle", strength = "Strength", other = "Other"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .walk: "figure.walk"; case .run: "figure.run"; case .cycle: "figure.outdoor.cycle"
            case .strength: "dumbbell.fill"; case .other: "flame.fill"
            }
        }
        var usesGPS: Bool { self == .walk || self == .run || self == .cycle }
        /// Fallback intensity when no HR is streaming (Compendium of Physical Activities).
        var met: Double {
            switch self {
            case .walk: 3.5; case .run: 8.5; case .cycle: 6.5; case .strength: 4.0; case .other: 4.5
            }
        }
    }

    private(set) var kind: Kind = .walk
    private(set) var active = false
    private(set) var startedAt = Date()
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceM: Double = 0
    private(set) var currentHR: Int?
    private(set) var kcal: Double = 0
    private(set) var gpsAuthDenied = false

    /// min/km, nil until there's enough distance to be meaningful.
    var paceMinPerKm: Double? {
        guard distanceM > 50, elapsed > 30 else { return nil }
        return (elapsed / 60) / (distanceM / 1000)
    }
    var avgHR: Double? { hrSamples.isEmpty ? nil : hrSamples.reduce(0, +) / Double(hrSamples.count) }

    private var hrSamples: [Double] = []          // one every 5 s
    private var peakHR: Double?
    private var zoneSec = [0.0, 0, 0, 0, 0]
    private var timer: Timer?
    private var tick = 0
    private var locator: SessionLocator?
    private weak var store: Store?
    private weak var ring: QRingManager?

    // MARK: Session control

    func start(_ kind: Kind, store: Store, ring: QRingManager) {
        guard !active else { return }
        self.kind = kind; self.store = store; self.ring = ring
        startedAt = Date(); elapsed = 0; distanceM = 0; kcal = 0
        hrSamples = []; peakHR = nil; zoneSec = [0, 0, 0, 0, 0]; tick = 0
        currentHR = nil; gpsAuthDenied = false
        active = true

        var wantsGPS = kind.usesGPS
#if DEBUG
        // Screenshot harness runs must not trigger the location permission dialog.
        if UserDefaults.standard.bool(forKey: "workoutDemo") ||
           UserDefaults.standard.bool(forKey: "workoutSummary") { wantsGPS = false }
#endif
        if wantsGPS {
            let l = SessionLocator()
            l.onDistance = { [weak self] m in self?.distanceM += m }
            l.onDenied = { [weak self] in self?.gpsAuthDenied = true }
            l.start()
            locator = l
        }
        if ring.connected != nil { ring.startLiveHeartRate() }
        UIApplication.shared.isIdleTimerDisabled = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.secondTick() }
        }
    }

    /// What the summary screen shows after a session ends.
    struct Summary: Identifiable {
        let id = UUID()
        var entry: WorkoutEntry
        var distanceM: Double
        var paceMinPerKm: Double?
        var vo2Est: Double?
        var saved: Bool
    }

    /// End the session. `save: false` discards everything and returns nil.
    @discardableResult
    func end(save: Bool) -> Summary? {
        guard active else { return nil }
        active = false
        timer?.invalidate(); timer = nil
        locator?.stop(); locator = nil
        ring?.stopLiveHeartRate()
        UIApplication.shared.isIdleTimerDisabled = false
        guard save, let store else { return nil }

        let key = DateKey.key(startedAt)
        let zones = hrSamples.isEmpty ? [] : zoneSec.map { $0 / 60 }
        let entry = WorkoutEntry(id: "ring-\(UUID().uuidString)", date: key,
                                 name: kind == .other ? "Workout" : kind.rawValue,
                                 start: startedAt, minutes: elapsed / 60,
                                 kcal: kcal > 0 ? kcal : nil,
                                 avgHR: avgHR, maxHR: peakHR, zoneMin: zones)
        guard elapsed >= 60 else {
            store.showToast("Too short to save")
            return Summary(entry: entry, distanceM: distanceM, paceMinPerKm: paceMinPerKm,
                           vo2Est: nil, saved: false)
        }
        store.logWorkout(entry)

        var vo2: Double?
        if let est = estimatedVO2Max(), store.data.health[key]?.vo2Max == nil {
            store.setHealth(vo2Max: est, on: key)             // a Watch value always wins
            vo2 = est
        }
        store.showToast("Workout saved ✓")
        return Summary(entry: entry, distanceM: distanceM, paceMinPerKm: paceMinPerKm,
                       vo2Est: vo2, saved: true)
    }

#if DEBUG
    /// Screenshot/QA harness: fill the live screen with representative values (no ring/GPS in the sim).
    func demoFill() {
        startedAt = Date().addingTimeInterval(-1475)
        elapsed = 1475; distanceM = 3240; currentHR = 142; kcal = 287
        hrSamples = [128, 135, 142, 149, 144]; peakHR = 166
        zoneSec = [120, 300, 540, 420, 95]
    }

    static var demoSummary: Summary {
        Summary(entry: WorkoutEntry(id: "demo", date: DateKey.key(Date()), name: "Run",
                                    start: Date().addingTimeInterval(-1475), minutes: 24.6,
                                    kcal: 287, avgHR: 143, maxHR: 166,
                                    zoneMin: [2, 5, 9, 7, 1.6]),
                distanceM: 3240, paceMinPerKm: 7.6, vo2Est: 41, saved: true)
    }
#endif

    // MARK: Per-second work

    private func secondTick() {
        guard active else { return }
        elapsed += 1
        tick += 1
        // The ring's real-time HR stream needs a periodic keep-alive (SDK drops it after ~20 s).
        if tick % 15 == 0, ring?.connected != nil { ring?.startLiveHeartRate() }
        guard tick % 5 == 0 else { return }

        if let hr = ring?.liveHR, hr > 30 {
            currentHR = hr
            let v = Double(hr)
            hrSamples.append(v)
            peakHR = max(peakHR ?? 0, v)
            let pct = v / Double(maxHR)
            let z = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4
            zoneSec[z] += 5
            kcal += keytelKcalPerMin(hr: v) * (5.0 / 60)
        } else {
            currentHR = nil
            kcal += kind.met * 3.5 * weightKg / 200 * (5.0 / 60)   // MET fallback, kcal/min
        }
    }

    // MARK: Physiology helpers

    private var weightKg: Double { store?.currentWeight ?? store?.data.intake?.weightKg ?? 80 }
    private var age: Double { Double(store?.data.intake?.age ?? 30) }
    private var isMale: Bool { store?.data.intake?.sex != .female }
    private var maxHR: Int {
        if let m = store?.data.reminders.maxHrOverride, m > 100 { return m }
        return 220 - Int(age)
    }

    /// Keytel et al. 2005 — kcal/min from HR, weight, age, sex (gross energy expenditure).
    private func keytelKcalPerMin(hr: Double) -> Double {
        let raw = isMale
            ? -55.0969 + 0.6309 * hr + 0.1988 * weightKg + 0.2017 * age
            :  -20.4022 + 0.4472 * hr - 0.1263 * weightKg + 0.0740 * age
        return max(0, raw / 4.184)
    }

    /// Sub-maximal VO₂-max estimate from an outdoor walk/run: ACSM equation gives the oxygen cost
    /// of the recorded pace; extrapolating over heart-rate reserve projects it to max effort.
    /// Needs ≥ 8 min, ≥ 400 m of GPS distance and a meaningful average HR. ±10–15 % class accuracy —
    /// fine for the Physical Age trend, never surfaced as a clinical number.
    private func estimatedVO2Max() -> Double? {
        guard kind == .walk || kind == .run,
              elapsed >= 8 * 60, distanceM >= 400,
              let avg = avgHR, avg >= 95 else { return nil }
        let rhr = restingHR
        guard avg > rhr + 15, Double(maxHR) > avg + 5 else { return nil }

        let v = distanceM / (elapsed / 60)                       // m/min
        let walking = kind == .walk || v < 134                   // < ~8 km/h → walking economy
        let vo2Sub = walking ? 3.5 + 0.1 * v : 3.5 + 0.2 * v     // ACSM, level ground
        let reserve = (Double(maxHR) - rhr) / (avg - rhr)
        let est = 3.5 + (vo2Sub - 3.5) * reserve
        return min(max(est, 20), 65)
    }

    private var restingHR: Double {
        guard let data = store?.data else { return 60 }
        let recent = data.recovery.keys.sorted(by: >).prefix(7)
        let vals = recent.compactMap { data.recovery[$0]?.rhr }
        return vals.isEmpty ? 60 : vals.reduce(0, +) / Double(vals.count)
    }
}

/// Tiny CoreLocation wrapper. NSObject delegate conformance kept out of the @Observable session
/// class (the Swift observation macro and the ObjC delegate protocol don't mix well).
private final class SessionLocator: NSObject, CLLocationManagerDelegate {
    var onDistance: ((Double) -> Void)?
    var onDenied: (() -> Void)?
    private let manager = CLLocationManager()
    private var last: CLLocation?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation(); manager.delegate = nil }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .denied, .restricted: DispatchQueue.main.async { self.onDenied?() }
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 50 {
            if let prev = last {
                let d = loc.distance(from: prev)
                if d >= 1, d < 200 {        // ignore jitter and GPS teleports
                    DispatchQueue.main.async { self.onDistance?(d) }
                }
            }
            last = loc
        }
    }
}
