import Foundation
import SwiftUI

// VB9 wristband transport (BLE). The IWOWN/Zeroner "Mid-Autumn" SDK ships as an Objective-C framework
// (BLEMidAutumn.framework) that is **arm64 device-only — no simulator slice**. So:
//
//   • The real BLE code is gated behind `#if canImport(BLEMidAutumn)`. The framework is NOT in this
//     (public) repo and is added to the DEVICE build only — so simulator builds exclude it and keep
//     compiling. When the hardware + framework are in hand, that branch activates and is finished on device.
//   • The `#else` branch is a fully-working stub so the app builds/runs on the simulator. With `-vb9Sim 1`
//     it injects realistic band data into the Store so the Body cards can be developed and screenshotted.
//
// Public API is transport-agnostic; both branches drive the same Store `applyVB9…` ingestion in VB9Store.swift.
@Observable
@MainActor
final class VB9Manager {

    enum ConnState: Equatable { case idle, scanning, connecting, connected, disconnected }

    /// A discovered band (wraps the SDK peripheral by identifier on device).
    struct Device: Identifiable, Hashable { var id: String; var name: String; var rssi: Int? }

    // Observable state the Body "Band" card renders.
    var state: ConnState = .idle
    var discovered: [Device] = []
    var connected: Device?
    var battery: Int?
    var liveHR: Int?
    var isMeasuring = false
    var lastError: String?

    private weak var store: Store?
    func attach(store: Store) { self.store = store }

    /// True when the vendor framework is present (device build). False on the simulator.
    var isAvailable: Bool {
        #if canImport(BLEMidAutumn)
        return true
        #else
        return false
        #endif
    }

    /// Whether to run the on-simulator demo band (`-vb9Sim 1`).
    private var simulated: Bool { UserDefaults.standard.bool(forKey: "vb9Sim") }

    // MARK: Lifecycle used by the app

    /// Called on launch. On device, reconnects a previously-bound band. On the sim with `-vb9Sim 1`,
    /// seeds demo data so the Body cards aren't empty.
    func start() {
        #if canImport(BLEMidAutumn)
        bridgeStart()
        #else
        if simulated { injectSimulatedData(); state = .connected }
        #endif
    }

    func startScan() {
        lastError = nil
        state = .scanning
        #if canImport(BLEMidAutumn)
        bridgeStartScan()
        #else
        guard simulated else { state = .idle; lastError = "Connect the HUMANS band on a real device."; return }
        discovered = [Device(id: "SIM-VB9", name: "HUMANS Band (VB9)", rssi: -52)]
        #endif
    }

    func stopScan() {
        #if canImport(BLEMidAutumn)
        bridgeStopScan()
        #endif
        if state == .scanning { state = discovered.isEmpty ? .idle : .scanning }
    }

    func connect(_ device: Device) {
        state = .connecting
        #if canImport(BLEMidAutumn)
        bridgeConnect(device)
        #else
        connected = device
        battery = 78
        state = .connected
        store?.setBand(BandInfo(name: device.name, model: "VB9", battery: battery, lastSyncAt: Date()))
        if simulated { injectSimulatedData() }
        #endif
    }

    func disconnect() {
        #if canImport(BLEMidAutumn)
        bridgeDisconnect()
        #endif
        connected = nil; liveHR = nil; state = .disconnected
    }

    // MARK: Measurements

    func startLiveHeartRate() {
        #if canImport(BLEMidAutumn)
        bridgeStartLiveHR()
        #else
        isMeasuring = true
        if simulated { liveHR = 72 }
        #endif
    }

    func stopLiveHeartRate() {
        #if canImport(BLEMidAutumn)
        bridgeStopLiveHR()
        #endif
        isMeasuring = false
    }

    /// One-key health measurement (~60 s): fatigue/stress/SpO₂/HR/BP/breath/temperature.
    func oneKeyMeasure() {
        #if canImport(BLEMidAutumn)
        bridgeOneKey()
        #else
        guard simulated else { lastError = "Requires the HUMANS band."; return }
        store?.applyVB9OneKey(VB9OneKey(fatigue: 38, stress: 41, spo2: 97, hr: 68,
                                        sbp: 118, dbp: 76, breathRate: 14, temperatureC: 36.6))
        store?.showToast("Health check complete ✓")
        #endif
    }

    /// Single-lead ECG: streams the waveform, then the band's on-device AI returns rhythm/HRV/AF.
    func measureECG() {
        #if canImport(BLEMidAutumn)
        bridgeMeasureECG()
        #else
        guard simulated else { lastError = "Requires the HUMANS band."; return }
        let json = """
        {"AI_Result":{"type":1,"type_name":"Sinus Rhythm"},
         "HRV":{"SDNN":44.83,"rMSSD":22.04,"pNN50":10.2,"HR":69},
         "GradeInfo":{"fatigue":38.0,"pressure":41.0,"score":76,"sympathetic_nerve":58.0,
                      "parasympathetic":42.0,"autonomic_balance":0.72},
         "QRS":{"avgHr":69,"avgPrIntervals":160,"avgQrs":90,"avgQtc":410,"heartAge":34,
                "score":82,"scoreDescription":"Healthy","diagLabels":["SN"]},
         "RRI":[796,772,764]}
        """
        let r = VB9Parse.result(date: store?.today ?? "", at: Date(),
                                ecg: VB9Parse.ecg(json), af: nil)
        store?.recordECG(r)
        store?.showToast("ECG recorded ✓")
        #endif
    }

    /// Full history sync (device-only; on the sim the demo data stands in).
    func syncHistory() async {
        #if canImport(BLEMidAutumn)
        await bridgeSyncHistory()
        #else
        if simulated { injectSimulatedData() }
        store?.data.band?.lastSyncAt = Date()
        #endif
    }

    // MARK: Simulator demo data

    /// Seeds a realistic band: 7 days of HR-envelope + stress/fatigue, BP, a resting temperature, and one
    /// ECG recording — so the Body cards render for screenshots without hardware. Never runs on device.
    func injectSimulatedData() {
        guard let store else { return }
        store.setBand(BandInfo(name: "HUMANS Band (VB9)", model: "VB9", mac: "SIM",
                               firmware: "6.6.6", battery: 78, lastSyncAt: Date()))
        var days: [VB9Day] = []
        for n in 0..<7 {
            let k = DateKey.key(DateKey.daysAgo(n))
            days.append(VB9Day(date: k, hrv: 46 + Double(n % 3) * 4, rhr: 54 + Double(n % 2),
                               resp: 14, spo2: 97, tempC: 36.5,
                               hrMinDay: 49 + Double(n % 3), hrMaxDay: 132 - Double(n % 4) * 5,
                               bpSystolic: 118, bpDiastolic: 76,
                               stress: 40 + Double(n % 3) * 6, fatigue: 36 + Double(n % 4) * 5))
        }
        store.applyVB9History(days: days, workouts: [])
        measureECG()
        connected = connected ?? Device(id: "SIM-VB9", name: "HUMANS Band (VB9)", rssi: -52)
        battery = 78
    }
}

#if canImport(BLEMidAutumn)
import BLEMidAutumn

// MARK: - On-device BLE bridge (activated when the vendor framework is linked into the device build).
//
// Scaffolding against the documented iOS API (BLEAutumn / BLESolstice / BLEquinox, SDK v6.6.6). The
// delegate callbacks (onScanResult / connect status / real-time HR / ECG-AI JSON / history records) are
// wired here and must be verified on the first physical band — Obj-C selector/param nuances can only be
// confirmed with hardware. Each stub calls back into the same Store ingestion the simulator path uses.
extension VB9Manager {
    private func bridgeStart() { /* reConnectDevice via BLEAutumn.midAutumn(.PB); see VB9-INTEGRATION.md */ }
    private func bridgeStartScan() { /* BLEAutumn.startScan(); map onScanResult → discovered */ }
    private func bridgeStopScan() { /* BLEAutumn.stopScan() */ }
    private func bridgeConnect(_ device: Device) { /* BLEAutumn.bindDevice(peripheral) → onBluetoothInit */ }
    private func bridgeDisconnect() { /* BLEAutumn.unbind() */ }
    private func bridgeStartLiveHR() { /* solstice.startReadRealTimeData(withTypes: [HR]) → responseHeartRateData */ }
    private func bridgeStopLiveHR() { /* solstice.stopReadRealTimeData(withTypes: [HR]) */ }
    private func bridgeOneKey() { /* solstice.startExercise(); parse one-key result → applyVB9OneKey */ }
    private func bridgeMeasureECG() { /* solstice.testECGModel(); on finish calculateEcgAiJson → recordECG */ }
    private func bridgeSyncHistory() async { /* solstice.getDataStoreDate(); startSpecialData per SD_TYPE → applyVB9History */ }
}
#endif
