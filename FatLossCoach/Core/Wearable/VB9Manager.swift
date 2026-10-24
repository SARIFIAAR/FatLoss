import Foundation
import SwiftUI

// VB9 wristband transport (BLE). The IWOWN/Zeroner "Mid-Autumn" SDK ships as an Objective-C framework
// (BLEMidAutumn.framework) that is **arm64 device-only — no simulator slice**. So:
//
//   • The real BLE code lives in VB9Bridge.swift, entirely behind `#if canImport(BLEMidAutumn)`. The
//     framework is NOT in this (public) repo and is linked into the DEVICE build only (SDK-conditional
//     [sdk=iphoneos*] settings) — so simulator builds exclude it and keep compiling. `canImport` is the gate.
//   • The `#else` branch below is a fully-working stub so the app builds/runs on the simulator. With
//     `-vb9Sim 1` it injects realistic band data into the Store so the Body cards develop/screenshot.
//
// Public API is transport-agnostic. On device the VB9Bridge drives the SDK and calls BACK into the
// `@MainActor ingest*` / `apply*` methods here; both paths end at the same Store `applyVB9…` ingestion.
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
    var btPower: String?            // on-screen scan diagnostic (Bluetooth power state)
    var logLines: [String] = []     // on-screen [VB9] log tail (for untethered/TestFlight debugging)

    /// Append a diagnostic line shown in the band card's on-screen log (keeps the last ~60).
    func pushLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 60 { logLines.removeFirst(logLines.count - 60) }
    }

    private weak var store: Store?
    func attach(store: Store) { self.store = store }

    /// On-device SDK bridge (VB9Bridge). Held as `AnyObject?` because the concrete type only exists when
    /// the vendor framework is linked (device build); nil on the simulator. See `deviceBridge`.
    private var bridgeBox: AnyObject?

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

    #if canImport(BLEMidAutumn)
    /// Lazily-created SDK bridge for the device build.
    private var deviceBridge: VB9Bridge {
        if let b = bridgeBox as? VB9Bridge { return b }
        let b = VB9Bridge(manager: self)
        bridgeBox = b
        return b
    }
    #endif

    // MARK: Lifecycle used by the app

    /// Called on launch. On device, reconnects a previously-bound band. On the sim with `-vb9Sim 1`,
    /// seeds demo data so the Body cards aren't empty.
    func start() {
        #if canImport(BLEMidAutumn)
        deviceBridge.start()
        #else
        if simulated { injectSimulatedData(); state = .connected }
        #endif
    }

    func startScan() {
        lastError = nil
        state = .scanning
        #if canImport(BLEMidAutumn)
        discovered = []
        deviceBridge.startScan()
        #else
        guard simulated else { state = .idle; lastError = "Connect the HUMANS band on a real device."; return }
        discovered = [Device(id: "SIM-VB9", name: "HUMANS Band (VB9)", rssi: -52)]
        #endif
    }

    func stopScan() {
        #if canImport(BLEMidAutumn)
        deviceBridge.stopScan()
        #endif
        if state == .scanning { state = discovered.isEmpty ? .idle : .scanning }
    }

    func connect(_ device: Device) {
        state = .connecting
        #if canImport(BLEMidAutumn)
        deviceBridge.connect(id: device.id)
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
        deviceBridge.disconnect()
        #endif
        connected = nil; liveHR = nil; state = .disconnected
    }

    // MARK: Measurements

    func startLiveHeartRate() {
        #if canImport(BLEMidAutumn)
        isMeasuring = true
        deviceBridge.startLiveHR()
        #else
        isMeasuring = true
        if simulated { liveHR = 72 }
        #endif
    }

    func stopLiveHeartRate() {
        #if canImport(BLEMidAutumn)
        deviceBridge.stopLiveHR()
        #endif
        isMeasuring = false
    }

    /// One-key health measurement (~60 s): fatigue/stress/SpO₂/HR/BP/breath/temperature.
    func oneKeyMeasure() {
        #if canImport(BLEMidAutumn)
        isMeasuring = true
        deviceBridge.oneKeyMeasure()
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
        isMeasuring = true
        deviceBridge.measureECG()
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

    /// Body composition (BIA): requires touching the electrodes; result is a full ZRBiaDataModel.
    func measureBodyComp() {
        #if canImport(BLEMidAutumn)
        isMeasuring = true
        deviceBridge.measureBIA()
        #else
        guard simulated else { lastError = "Requires the HUMANS band."; return }
        store?.showToast("Body composition (sim)")
        #endif
    }

    /// Full history sync (device-only; on the sim the demo data stands in).
    func syncHistory() async {
        #if canImport(BLEMidAutumn)
        deviceBridge.syncHistory()
        #else
        if simulated { injectSimulatedData() }
        store?.data.band?.lastSyncAt = Date()
        #endif
    }

    // MARK: - Device ingestion (called by VB9Bridge, already hopped to the main actor)

    #if canImport(BLEMidAutumn)
    func ingestDiscovered(id: String, name: String, rssi: Int?) {
        let dev = Device(id: id, name: name, rssi: rssi)
        if let i = discovered.firstIndex(where: { $0.id == id }) { discovered[i] = dev }
        else { discovered.append(dev) }
    }

    func ingestScanStopped() { if state == .scanning { state = discovered.isEmpty ? .idle : .scanning } }

    func ingestConnecting(name: String) { state = .connecting; lastError = nil }

    /// Fired once the SDK handshake completes (`readRequiredInfoAfterConnect`) — device is command-ready.
    func ingestReady(id: String, name: String) {
        connected = Device(id: id, name: name, rssi: connected?.rssi)
        state = .connected
        store?.setBand(BandInfo(name: name, model: "VB9", lastSyncAt: Date()))
    }

    func ingestDeviceInfo(model: String?, firmware: String?, mac: String?, battery: Int?) {
        if let battery { self.battery = battery }
        guard store != nil else { return }
        var info = store?.data.band ?? BandInfo(name: connected?.name ?? "HUMANS Band (VB9)")
        if let model { info.model = model }
        if let firmware { info.firmware = firmware }
        if let mac { info.mac = mac }
        if let battery { info.battery = battery }
        store?.setBand(info)
    }

    func ingestDisconnected(error: String?) {
        connected = nil; liveHR = nil; isMeasuring = false
        state = .disconnected
        if let error { lastError = error }
    }

    func ingestLiveHR(_ hr: Int) { if hr > 0 { liveHR = hr } }

    func ingestError(_ message: String) { lastError = message; isMeasuring = false }

    func applyOneKey(_ r: VB9OneKey) {
        store?.applyVB9OneKey(r)
        isMeasuring = false
        store?.showToast("Health check complete ✓")
    }

    func applyECG(_ result: ECGResult) {
        store?.recordECG(result)
        isMeasuring = false
        store?.showToast("ECG recorded ✓")
    }

    func applyHistory(days: [VB9Day], workouts: [VB9Work]) {
        store?.applyVB9History(days: days, workouts: workouts)
        store?.data.band?.lastSyncAt = Date()
    }

    /// Body-composition (BIA) reading → BodyCompEntry + health fat%/lean. Weight falls back to the user's
    /// last logged weight (the band measures composition, not mass).
    func applyBIA(fatPct: Double?, fatKg: Double?, muscleKg: Double?, waterKg: Double?,
                  visceral: Double?, bmr: Double?, protein: Double?, bone: Double?) {
        isMeasuring = false
        let w = store?.currentWeight ?? 0
        let entry = BodyCompEntry(date: store?.today ?? DateKey.key(), weightKg: w,
                                  bodyFatPct: fatPct, fatMassKg: fatKg, muscleKg: muscleKg,
                                  visceralFat: visceral, bmr: bmr, source: "vb9",
                                  totalBodyWaterL: waterKg, proteinKg: protein, mineralKg: bone)
        store?.addBodyComp(entry)
        if let fatPct { store?.setHealth(bodyFatPct: fatPct) }
        if let muscleKg { store?.setHealth(leanMassKg: muscleKg) }
        store?.showToast("Body composition saved ✓")
    }
    #endif

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
