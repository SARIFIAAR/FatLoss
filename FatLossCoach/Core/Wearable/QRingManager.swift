import Foundation
import SwiftUI

// QRing smart-ring transport (QCBandSDK). The Vivistar QRing platform (VY26/VY28C) ships a self-contained,
// local (no-cloud) Objective-C framework — richer than the VB9 for HUMANS: raw RRI (per-second), raw PPG,
// SpO₂, BP, stress, temp, HRV, blood glucose. Swim-safe (5 ATM). See docs/qring-integration.md.
//
//   • Real SDK code lives in QRingBridge.swift behind `#if canImport(QCBandSDK)` — framework linked DEVICE-only
//     (SDK-conditional [sdk=iphoneos*]), so simulator builds exclude it and keep compiling. `canImport` gates.
//   • Unlike the VB9 (where the SDK owned scanning), the APP owns CoreBluetooth; QRingBridge drives it and
//     hands the peripheral to QCSDKManager, then feeds the SAME Store `applyVB9History` + BodyMetrics pipeline.
@Observable
@MainActor
final class QRingManager {

    enum ConnState: Equatable { case idle, scanning, connecting, connected, disconnected }

    struct Device: Identifiable, Hashable { var id: String; var name: String; var rssi: Int? }

    var state: ConnState = .idle
    var discovered: [Device] = []
    var connected: Device?
    var battery: Int?
    var liveHR: Int?
    var isMeasuring = false
    var lastError: String?
    var btPower: String?
    var logLines: [String] = []

    func pushLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 60 { logLines.removeFirst(logLines.count - 60) }
    }

    private weak var store: Store?
    func attach(store: Store) {
        self.store = store
        // Clear leftover band info from the parked VB9 so the ring card shows cleanly (not "BIO-4044").
        if store.data.band?.model == "VB9" { store.data.band = nil }
        // Sanitize persisted small-calorie values from the pre-fix builds (the 39400-kcal bug): any
        // day whose activeKcal is physiologically impossible was written raw by the ring → ÷1000.
        for (k, var h) in store.data.health where (h.activeKcal ?? 0) > 10000 {
            h.activeKcal = (h.activeKcal ?? 0) / 1000.0
            store.data.health[k] = h
        }
    }

    private var bridgeBox: AnyObject?

    var isAvailable: Bool {
        #if canImport(QCBandSDK)
        return true
        #else
        return false
        #endif
    }

    private var simulated: Bool { UserDefaults.standard.bool(forKey: "qringSim") }

    #if canImport(QCBandSDK)
    private var deviceBridge: QRingBridge {
        if let b = bridgeBox as? QRingBridge { return b }
        let b = QRingBridge(manager: self)
        bridgeBox = b
        return b
    }
    #endif

    // MARK: Lifecycle

    func start() {
        #if canImport(QCBandSDK)
        deviceBridge.start()
        #else
        if simulated { injectSimulatedData(); state = .connected }
        #endif
    }

    func startScan() {
        lastError = nil
        state = .scanning
        #if canImport(QCBandSDK)
        discovered = []
        deviceBridge.startScan()
        #else
        guard simulated else { state = .idle; lastError = "Connect the HUMANS ring on a real device."; return }
        discovered = [Device(id: "SIM-QRING", name: "HUMANS Ring", rssi: -48)]
        #endif
    }

    func stopScan() {
        #if canImport(QCBandSDK)
        deviceBridge.stopScan()
        #endif
        if state == .scanning { state = discovered.isEmpty ? .idle : .scanning }
    }

    func connect(_ device: Device) {
        state = .connecting
        #if canImport(QCBandSDK)
        deviceBridge.connect(id: device.id)
        #else
        connected = device; battery = 90; state = .connected
        store?.setBand(BandInfo(name: device.name, model: "QRing", battery: battery, lastSyncAt: Date()))
        if simulated { injectSimulatedData() }
        #endif
    }

    func disconnect() {
        #if canImport(QCBandSDK)
        deviceBridge.disconnect()
        #endif
        connected = nil; liveHR = nil; state = .disconnected
    }

    // MARK: Measurements

    func startLiveHeartRate() {
        isMeasuring = true
        #if canImport(QCBandSDK)
        deviceBridge.startLiveHR()
        #else
        if simulated { liveHR = 70 }
        #endif
    }

    func stopLiveHeartRate() {
        #if canImport(QCBandSDK)
        deviceBridge.stopLiveHR()
        #endif
        isMeasuring = false
    }

    /// One-key measurement — the ring returns HR + HRV + RRI + stress + temp + BP in a single reading.
    func oneKeyMeasure() {
        isMeasuring = true
        #if canImport(QCBandSDK)
        deviceBridge.oneKeyMeasure()
        #else
        guard simulated else { lastError = "Requires the HUMANS ring."; return }
        applyOneKey(hr: 68, hrvMs: 52, rriMs: 880, stress: 34, tempC: 36.6, sbp: 118, dbp: 76)
        #endif
    }

    func syncHistory() async {
        #if canImport(QCBandSDK)
        deviceBridge.syncHistory()
        #else
        if simulated { injectSimulatedData() }
        store?.data.band?.lastSyncAt = Date()
        #endif
    }

    /// 100 s raw-PPG capture → rMSSD (true HRV) — phase-4 scaffold; result lands in the log panel.
    func measureRawPPG() {
        #if canImport(QCBandSDK)
        isMeasuring = true
        deviceBridge.measureRawPPG()
        #else
        lastError = "Requires the HUMANS strap."
        #endif
    }

    /// One-key reading → today's recovery/health (available on both sim and device paths).
    /// HRV prefers the RRI-derived value when available.
    func applyOneKey(hr: Int?, hrvMs: Int?, rriMs: Int?, stress: Int?, tempC: Double?, sbp: Int?, dbp: Int?, silent: Bool = false) {
        isMeasuring = false
        store?.updateRecovery { rec in
            if let v = hrvMs, v > 0 { rec.hrv = Double(v) }
            if let v = stress, v > 0 { rec.stressMeasured = Double(v) }
            if let v = tempC, v > 0 { rec.tempC = v }
        }
        // `hr` is a one-shot SPOT reading, not resting HR — but fold it into today's HR envelope (min→max)
        // so the current day's resting HR + HR range populate over repeated measurements. The ring's
        // history command never returns the current day, so this is the only live source.
        if let hr { store?.observeHeartRate(hr) }
        store?.setHealth(bpSystolic: sbp.map(Double.init), bpDiastolic: dbp.map(Double.init))
        if !silent { store?.showToast("Ring measurement saved ✓") }
    }

    /// Silent wrist-temperature write (no toast) — used by the auto-temperature measurement that runs at
    /// the end of each sync. This ring records no readable temperature history (the official app reads it
    /// via a file-transfer protocol the iOS SDK doesn't expose), so we sample it on-demand each sync.
    func ingestTemperature(_ c: Double) {
        guard c > 0 else { return }
        store?.updateRecovery { $0.tempC = c }
    }

    // MARK: - Ingestion (called by QRingBridge, already on the main actor)

    #if canImport(QCBandSDK)
    func ingestDiscovered(id: String, name: String, rssi: Int?) {
        let d = Device(id: id, name: name, rssi: rssi)
        if let i = discovered.firstIndex(where: { $0.id == id }) { discovered[i] = d } else { discovered.append(d) }
    }
    func ingestScanStopped() { if state == .scanning { state = discovered.isEmpty ? .idle : .scanning } }
    func ingestConnecting(name: String) { state = .connecting; lastError = nil }
    func ingestReady(id: String, name: String) {
        connected = Device(id: id, name: name, rssi: connected?.rssi)
        state = .connected
        store?.setBand(BandInfo(name: name, model: "QRing", lastSyncAt: Date()))
    }
    func ingestDeviceInfo(battery: Int?, firmware: String?) {
        if let battery { self.battery = battery }
        guard store != nil else { return }
        var info = store?.data.band ?? BandInfo(name: connected?.name ?? "HUMANS Ring")
        info.model = "QRing"
        if let firmware { info.firmware = firmware }
        if let battery { info.battery = battery }
        store?.setBand(info)
    }
    func ingestDisconnected(error: String?) {
        connected = nil; liveHR = nil; isMeasuring = false; state = .disconnected
        if let error { lastError = error }
    }
    func ingestLiveHR(_ hr: Int) {
        guard hr > 0 else { return }
        liveHR = hr
        // Build today's HR envelope live from every reading we observe (real-time stream, one-key, workout).
        // The ring's history command never returns the CURRENT day, so this is how today's resting HR +
        // HR range populate. Lowest observed ≈ resting HR; highest = peak.
        store?.observeHeartRate(hr)
    }
    func ingestError(_ message: String) { lastError = message; isMeasuring = false }

    func applyHistory(days: [VB9Day], workouts: [VB9Work]) {
        store?.applyVB9History(days: days, workouts: workouts)
        store?.data.band?.lastSyncAt = Date()
    }
    #endif

    // MARK: Simulator demo data

    func injectSimulatedData() {
        guard let store else { return }
        store.setBand(BandInfo(name: "HUMANS Ring", model: "QRing", firmware: "1.0.0", battery: 90, lastSyncAt: Date()))
        var days: [VB9Day] = []
        for n in 0..<7 {
            let k = DateKey.key(DateKey.daysAgo(n))
            days.append(VB9Day(date: k, hrv: 48 + Double(n % 3) * 5, rhr: 56 + Double(n % 2),
                               resp: 14, spo2: 98, tempC: 36.5,
                               hrMinDay: 50 + Double(n % 3), hrMaxDay: 128 - Double(n % 4) * 4,
                               stress: 32 + Double(n % 3) * 5))
        }
        store.applyVB9History(days: days, workouts: [])
        connected = connected ?? Device(id: "SIM-QRING", name: "HUMANS Ring", rssi: -48)
        battery = 90
    }
}
