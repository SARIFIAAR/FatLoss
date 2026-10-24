#if canImport(BLEMidAutumn)
import Foundation
import CoreBluetooth
import BLEMidAutumn

// On-device SDK bridge for the VB9 (IWOWN/Zeroner "Mid-Autumn") wristband.
//
// This file compiles ONLY on the device build, where BLEMidAutumn.framework is linked (SDK-conditional
// [sdk=iphoneos*]). It owns the Obj-C SDK objects (BLEAutumn + the BLESolstice command interface) and
// conforms to the three SDK delegate protocols. Every SDK callback (arbitrary thread) is marshalled onto
// the main actor into the `@MainActor ingest*/apply*` methods on VB9Manager — the SAME Store ingestion
// the simulator stub uses.
//
// Ported from the vendor demo (AutumnTest/Classes/BLE/BLEShareInstance{,+ResponseFromSDK}.m). The call
// sequence is verified against the SDK headers; a handful of field mappings (marked ⚠︎ VERIFY-ON-DEVICE)
// can only be confirmed with a physical band — the logging here is deliberately verbose so we can read
// exactly what the hardware sends on the first pairing and tighten the mapping.
//
// NS_ENUM cases are referenced by rawValue (SD_TYPE / HDType / connection-protocol) to avoid depending on
// Swift's prefix-stripped case spellings, which differ across SDK versions and can't be verified until the
// framework is on the search path.
final class VB9Bridge: NSObject {

    private weak var manager: VB9Manager?

    private let autumn: BLEAutumn
    private var solstice: BLESolstice?

    /// Discovered peripherals kept so we can `bindDevice:` by our Device.id (the CB identifier string).
    private var peripherals: [String: ZRBlePeripheral] = [:]
    private var pendingConnectId: String?
    private var pendingConnectName: String?
    private var autoConnecting = false   // guards one-shot auto-connect to the BIO-… band

    // History-sync accumulators (filled across updateNormalHealthData callbacks, flushed on finish).
    private var histWorkouts: [VB9Work] = []
    private var syncing = false
    private var flushTask: Task<Void, Never>?   // debounced flush of accumulated history → Store
    private var biaTimeout: Task<Void, Never>?  // auto-stops the BIA realtime stream so it can't block sync

    /// Per-day accumulator — the band streams per-minute records, so we aggregate properly (resting HR =
    /// lowest valid HR, HRV = mean of physiological SDNN, HR envelope = min/max) instead of last-wins.
    private struct DayAgg {
        var restingHR: Double?            // min valid avg_bpm
        var hrMin: Double?; var hrMax: Double?
        var hrvSum = 0.0; var hrvN = 0
        var spo2Sum = 0.0; var spo2N = 0
        var tempSum = 0.0; var tempN = 0
        var fatigue: Double?; var stress: Double?
        var sbp: Double?; var dbp: Double?
        var steps: Int?; var activeKcal: Double?
        var sleepH: Double?; var deepH: Double?
    }
    private var dayAgg: [String: DayAgg] = [:]

    // SD_TYPE raw values (AutumnHeader.h) we sync.
    private enum SD {
        static let summary = 0xF1   // SD_TYPE_DATA_SUMMARY  — daily totals
        static let normal  = 0x80   // SD_TYPE_DATA_NORMAL   — per-minute sport/sleep/HR
        static let sleep   = 0x02
        static let heart   = 0x03
        static let spo2    = 0x0B
        static let temp    = 0x0C
        static let ecg      = 0x04
    }
    // HDType raw values (ZRHealthData.h) seen in updateNormalHealthData.
    private enum HD {
        static let summary = 0x29, sport = 0x28, sleep = 0x27, hrHours = 0x53
        static let minute = 0x61, ecg = 0x64, rri = 0x66, spo2 = 0x69, temp = 0x70, health6B = 0x6b
    }
    private static let kSyncFinished = 12  // KSyscDataStateIsFinished (enum order in AutumnHeader.h)

    init(manager: VB9Manager) {
        self.manager = manager
        // BLEProtocol_Any = 8 — let the SDK pick the right protocol for the band.
        self.autumn = BLEAutumn.midAutumn(BLEProtocol(rawValue: 8) ?? .null)
        super.init()
        self.autumn.discoverDelegate = self
        self.autumn.connectDelegate = self
        log("bridge init (protocol=Any)")
    }

    /// Tagged logging — Xcode console ("[VB9]") AND the on-screen log tail (for untethered/TestFlight).
    private func log(_ s: String) {
        NSLog("[VB9] %@", s)
        onMain { $0.pushLog(s) }
    }

    /// Human-readable CBManagerState (readManagerPowerState).
    private func powerStateName(_ n: Int) -> String {
        switch n {
        case 0: return "unknown"; case 1: return "resetting"; case 2: return "unsupported"
        case 3: return "UNAUTHORIZED"; case 4: return "POWERED OFF"; case 5: return "powered on"
        default: return "state \(n)"
        }
    }

    // MARK: Commands (called from VB9Manager, main actor)

    func start() {
        // Fast path: reconnect a previously-bound band. Then ALWAYS scan too — the bridge auto-connects to
        // the BIO band on discovery, so a failed/slow reconnect can't leave us stuck in "connecting".
        if autumn.isBound() { _ = autumn.reConnectDevice() }
        startScan()
    }

    func startScan() {
        peripherals.removeAll()
        autoConnecting = false   // allow a fresh auto-connect attempt on every scan
        let power = autumn.readManagerPowerState()
        log("startScan — bluetooth \(powerStateName(power))")
        onMain { $0.btPower = self.powerStateName(power) }
        if power != 5 {
            onMain { $0.ingestError("Bluetooth is \(self.powerStateName(power)). Enable Bluetooth + allow it for HUMANS.") }
        }
        // Broad scan: nil service-UUIDs so we see EVERY advertising peripheral the SDK reports, allow
        // duplicates so we get repeated adverts. Diagnostic-wide; we filter by name once we see the band.
        let opts: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        autumn.startScan(forTimeInternal: 30, andServiceUuids: nil, andOptions: opts)
    }

    func stopScan() { autumn.stopScan() }

    func connect(id: String) {
        guard let p = peripherals[id] else {
            onMain { $0.ingestError("Band no longer in range — scan again.") }
            return
        }
        pendingConnectId = id
        pendingConnectName = p.deviceName
        autumn.bindDevice(p)
    }

    func disconnect() {
        autoConnecting = false
        autumn.unbind()
        onMain { $0.ingestDisconnected(error: nil) }
    }

    func startLiveHR() { log("startLiveHR — solstice=\(solstice != nil)"); solstice?.switchStandardHeartRate(true) }
    func stopLiveHR() { log("stopLiveHR"); solstice?.switchStandardHeartRate(false) }

    /// One-key combined measurement. The band runs ~60 s then reports via updateNormalHealthData
    /// (ZR6BHealthDataModel) and/or responseOfBloodPressureData.
    func oneKeyMeasure() { log("oneKeyMeasure (startExercise) — solstice=\(solstice != nil)"); solstice?.startExercise() }

    /// Single-lead ECG. The AI result (rhythm/HRV/AF/heart-age) arrives pre-computed in
    /// ZRECGModel.jsonData via updateNormalHealthData (no separate AI call).
    func measureECG() { log("measureECG (testECGModel) — solstice=\(solstice != nil)"); solstice?.testECGModel() }

    /// Body composition (BIA) — real-time sensor stream; touch the electrodes. Result = ZRBiaDataModel.
    func measureBIA() {
        log("measureBIA (RealTime_BIA) — solstice=\(solstice != nil)")
        solstice?.startReadRealTimeData(withTypes: [NSNumber(value: 0x200)])   // RealTime_BIA
        // Safety: stop the realtime stream after 35s even if no data arrives, so it can't block history sync.
        biaTimeout?.cancel()
        biaTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled else { return }
            self?.solstice?.stopReadRealTimeData(withTypes: [NSNumber(value: 0x200)])
            self?.log("BIA stream stopped (timeout — no body-comp data received)")
            self?.onMain { $0.isMeasuring = false }
        }
    }

    private func biaReceived() { biaTimeout?.cancel(); solstice?.stopReadRealTimeData(withTypes: [NSNumber(value: 0x200)]) }

    func syncHistory() {
        log("syncHistory — solstice=\(solstice != nil)")
        guard let s = solstice else {
            onMain { $0.ingestError("Band not ready — connect first.") }
            return
        }
        dayAgg.removeAll(); histWorkouts.removeAll(); syncing = true
        // getDataStoreDate → updateNormalHealthDataInfo (index table) → we pull each type below.
        s.getDataStoreDate()
        // Daily summary + per-minute health don't depend on the index table; request them directly.
        s.startSpecialData(sdType(SD.summary))
        s.startSpecialData(sdType(SD.normal))
    }

    // MARK: Helpers

    private func sdType(_ raw: Int) -> SD_TYPE { SD_TYPE(rawValue: raw) ?? SD_TYPE(rawValue: 0)! }

    /// Hop a block onto the main actor with a strong, non-nil manager.
    private func onMain(_ body: @escaping @MainActor (VB9Manager) -> Void) {
        Task { @MainActor [weak manager] in if let m = manager { body(m) } }
    }

    private func key(_ date: Date?) -> String { DateKey.key(date ?? Date()) }

    private func agg(_ date: Date?, _ mutate: (inout DayAgg) -> Void) {
        let k = key(date)
        var a = dayAgg[k] ?? DayAgg()
        mutate(&a)
        dayAgg[k] = a
        scheduleFlush()
    }

    /// Debounced flush: the band streams history in bursts that can arrive AFTER the "sync finished"
    /// signal, so we flush ~1.2 s after the last record lands (and again on finish). Store merges are
    /// idempotent per day, so re-flushing the cumulative set is safe.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.flushHistory()
        }
    }

    private func flushHistory() {
        let days: [VB9Day] = dayAgg.map { (k, a) in
            var d = VB9Day(date: k)
            d.rhr = a.restingHR
            d.hrMinDay = a.hrMin; d.hrMaxDay = a.hrMax
            if a.hrvN > 0 { d.hrv = a.hrvSum / Double(a.hrvN) }
            if a.spo2N > 0 { d.spo2 = a.spo2Sum / Double(a.spo2N) }
            if a.tempN > 0 {
                var t = a.tempSum / Double(a.tempN)
                while t > 45 { t /= 10 }         // normalize ×10/×100 encodings to °C
                if t >= 30 { d.tempC = t }
            }
            d.fatigue = a.fatigue; d.stress = a.stress
            d.bpSystolic = a.sbp; d.bpDiastolic = a.dbp
            d.steps = a.steps; d.activeKcal = a.activeKcal
            d.sleepH = a.sleepH; d.deepH = a.deepH
            return d
        }
        let works = histWorkouts
        guard !days.isEmpty || !works.isEmpty else { return }
        onMain { $0.applyHistory(days: days, workouts: works) }
    }
}

// MARK: - BleDiscoverDelegate

extension VB9Bridge: BleDiscoverDelegate {
    func solsticeDidDiscoverDevice(withMAC iwDevice: ZRBlePeripheral) {
        let id = iwDevice.cbDevice?.identifier.uuidString ?? iwDevice.uuidString ?? iwDevice.mediaAC ?? UUID().uuidString
        let name = iwDevice.deviceName ?? iwDevice.cbDevice?.name ?? "HUMANS Band (VB9)"
        let rssi = iwDevice.rssi?.intValue
        log("DISCOVERED name='\(name)' mac=\(iwDevice.mediaAC ?? "?") rssi=\(rssi.map(String.init) ?? "?") id=\(id)")
        peripherals[id] = iwDevice
        onMain { $0.ingestDiscovered(id: id, name: name, rssi: rssi) }

        // Automated connect: prefer THE band we've paired with before (remembered by name) so a stranger's
        // BIO band nearby can never hijack the connection. First-ever pairing: take the strongest BIO.
        let boundName = UserDefaults.standard.string(forKey: "vb9BoundName")
        let isTarget: Bool
        if let boundName { isTarget = (name == boundName) }
        else { isTarget = name.uppercased().hasPrefix("BIO") && ((rssi == nil) || rssi! >= -95) }
        if !autoConnecting, solstice == nil, isTarget {
            autoConnecting = true
            pendingConnectId = id
            pendingConnectName = name
            log("auto-connecting to \(name) (rssi=\(rssi.map(String.init) ?? "?"))…")
            autumn.stopScan()
            autumn.bindDevice(iwDevice)
            onMain { $0.ingestConnecting(name: name) }
        }
    }

    func solsticeStopScan() { log("scan stopped — \(peripherals.count) device(s) found"); onMain { $0.ingestScanStopped() } }

    func centralManagerStatePoweredOn() { log("bluetooth powered ON") }
    func centralManagerStatePoweredOff() { log("bluetooth powered OFF") }
}

// MARK: - BleConnectDelegate

extension VB9Bridge: BleConnectDelegate {
    func solsticeDidConnectDevice(_ device: ZRBlePeripheral) {
        // Per the demo: grab the command interface, resume the cmd queue, register for data callbacks.
        solstice = autumn.solstice()
        autumn.resumeCmdQueueAfterResponse()
        _ = autumn.registerSolsticeEquinox(self)
        let name = device.deviceName ?? "HUMANS Band (VB9)"
        log("solsticeDidConnectDevice '\(name)' — solstice set=\(solstice != nil), equinox registered")
        onMain { $0.ingestConnecting(name: name) }
    }

    func solsticeDidDisConnect(withDevice device: ZRBlePeripheral, andError error: Error?) {
        solstice = nil; autoConnecting = false; pendingConnectId = nil
        onMain { $0.ingestDisconnected(error: error?.localizedDescription) }
    }

    func solsticeDidFail(toConnectDevice device: ZRBlePeripheral, andError error: Error?) {
        autoConnecting = false; pendingConnectId = nil
        onMain { $0.ingestError(error?.localizedDescription ?? "Failed to connect to the band.") }
    }

    func solsticeConnectTimeOut() { onMain { $0.ingestError("Connection timed out.") } }
}

// MARK: - BLEquinox (data callbacks)

extension VB9Bridge: BLEquinox {

    /// SDK handshake complete — device is command-ready. Read identity + battery and mark connected.
    func readRequiredInfoAfterConnect() {
        let id = pendingConnectId ?? (solstice?.getConnectedPeriphral()?.identifier.uuidString) ?? "vb9"
        let name = solstice?.getConnectedPeriphral()?.name ?? "HUMANS Band (VB9)"
        log("readRequiredInfoAfterConnect — READY; reading info, enabling auto-HR, auto-syncing")
        // Remember this exact band so future auto-connects prefer it over any stranger's BIO nearby.
        if let n = pendingConnectName, n.uppercased().hasPrefix("BIO") {
            UserDefaults.standard.set(n, forKey: "vb9BoundName")
        }
        onMain { $0.ingestReady(id: id, name: name) }
        solstice?.readDeviceInfo()
        solstice?.readDeviceBattery()
        solstice?.syscTimeAtOnce()
        // Automated collection: enable continuous standard HR, then pull whatever the band has stored.
        solstice?.switchStandardHeartRate(true)
        syncHistory()
    }
    // NOTE: deliberately NOT implementing response(ofConnectStatus:) — doing so disables the SDK's RCC
    // (rotation-check-communication) readiness handshake, which breaks all command responses.

    /// Device info + battery come back here, tagged by cmdResponse.
    func readResponse(fromDevice response: ZRReadResponse) {
        let type = response.cmdResponse.rawValue
        log("readResponse cmd=0x\(String(type, radix: 16)) data=\(String(describing: Swift.type(of: response.data)))")
        if type == 0x00, let info = response.data as? ZRDeviceInfo {   // CMD_RESPONSE_DEVICE_GET_INFORMATION
            let model = info.model, fw = info.version, mac = info.bleAddr
            let bat = Int(info.batLevel)
            onMain { $0.ingestDeviceInfo(model: model, firmware: fw, mac: mac, battery: bat > 0 ? bat : nil) }
        } else if type == 0x01 {                                       // CMD_RESPONSE_DEVICE_GET_BATTERY
            if let info = response.data as? ZRDeviceInfo {
                let bat = Int(info.batLevel)
                onMain { $0.ingestDeviceInfo(model: nil, firmware: nil, mac: nil, battery: bat) }
            } else if let n = response.data as? NSNumber {
                onMain { $0.ingestDeviceInfo(model: nil, firmware: nil, mac: nil, battery: n.intValue) }
            }
        }
    }

    /// Live standard heart rate (bpm).
    func responseHeartRateData(_ hr: Int) { log("responseHeartRateData hr=\(hr)"); onMain { $0.ingestLiveHR(hr) } }

    func response(ofExerciseStatus status: Int) {
        // 0 = SUCCESS. Non-zero is an error/busy state during one-key measurement.
        log("response(ofExerciseStatus: \(status))")
        if status != 0 { onMain { $0.ingestError("Measurement status \(status). Keep the band snug and still.") } }
    }

    func response(ofExerciseSport sportType: sd_sportType) { log("response(ofExerciseSport: \(sportType.rawValue))") }

    func response(ofExercise string: String) { log("response(ofExercise: \(string))") }

    func response(ofRealTimeSensorData sData: ZRSensorDataModel) {
        log("response(ofRealTimeSensorData) sType=0x\(String(sData.sType.rawValue, radix: 16)) count=\(sData.detailData?.count ?? 0) sample=\(sData.detailData?.prefix(4) ?? [])")
        // BIA may also surface as a parsed model on the sensor payload.
        if let bia = sData.detailData?.compactMap({ $0 as? ZRBiaDataModel }).first {
            log("BIA(sensor) fat%=\(bia.bodyFatPercentage) muscle=\(bia.muscleMassKg) imp=\(bia.impedanceOhm)")
            biaReceived()
            func d(_ f: Float) -> Double? { f > 0 ? Double(f) : nil }
            onMain { $0.applyBIA(fatPct: d(bia.bodyFatPercentage), fatKg: d(bia.bodyFatKg),
                                 muscleKg: d(bia.muscleMassKg), waterKg: d(bia.bodyWaterKg),
                                 visceral: d(bia.visceralFatLevel), bmr: d(bia.bmrKcal),
                                 protein: d(bia.proteinKg), bone: d(bia.boneMassKg)) }
        }
    }

    func updateDataProgress(_ progress: Int) { log("updateDataProgress \(progress)%") }

    // Catch-all logging — find which channel a BIA/body-comp result actually arrives on.
    func response(ofBPAdjustData bpSensor: ZRBPSensorData) {
        log("response(ofBPAdjustData) led1=\(bpSensor.led1) hr=\(bpSensor.hr) spo2=\(bpSensor.spo2) progress=\(bpSensor.progress) status=\(bpSensor.bp_status)")
    }
    func update(_ alarmData: ZRAlarmInfoData) { log("updateAlarmInfoData") }
    func responseKeyNotify(_ bkn: BKeyNotify) { log("responseKeyNotify \(bkn.rawValue)") }

    /// Blood pressure during/after one-key (array form, per SDK).
    func response(ofBloodPressureData data: [Any]) {
        log("response(ofBloodPressureData: \(data))")
        let ints = data.compactMap { ($0 as? NSNumber)?.intValue }
        guard ints.count >= 2 else { return }
        let r = VB9OneKey(sbp: ints[0], dbp: ints[1])     // ⚠︎ VERIFY-ON-DEVICE: array order [sbp, dbp]
        onMain { $0.applyOneKey(r) }
    }

    /// The main history + measurement data stream, dispatched by HDType.
    func updateNormalHealthData(_ zrhData: ZRHealthData) {
        let hd = Int(zrhData.hdInfo.hdType.rawValue)
        let date = zrhData.recordDate
        log("updateNormalHealthData hd=0x\(String(hd, radix: 16)) class=\(String(describing: Swift.type(of: zrhData)))")

        // Body composition (BIA) can arrive here as a ZRBiaDataModel regardless of hd type.
        if let bia = zrhData as? ZRBiaDataModel {
            log("BIA fat%=\(bia.bodyFatPercentage) fatKg=\(bia.bodyFatKg) muscle=\(bia.muscleMassKg) waterKg=\(bia.bodyWaterKg) visc=\(bia.visceralFatLevel) bmr=\(bia.bmrKcal) imp=\(bia.impedanceOhm)")
            biaReceived()
            func d(_ f: Float) -> Double? { f > 0 ? Double(f) : nil }
            onMain { $0.applyBIA(fatPct: d(bia.bodyFatPercentage), fatKg: d(bia.bodyFatKg),
                                 muscleKg: d(bia.muscleMassKg), waterKg: d(bia.bodyWaterKg),
                                 visceral: d(bia.visceralFatLevel), bmr: d(bia.bmrKcal),
                                 protein: d(bia.proteinKg), bone: d(bia.boneMassKg)) }
            return
        }

        switch hd {
        case HD.ecg:
            if let m = zrhData as? ZRECGModel, let json = m.jsonData, !json.isEmpty {
                let r = VB9Parse.result(date: DateKey.key(date ?? Date()), at: date ?? Date(),
                                        ecg: VB9Parse.ecg(json), af: nil)
                onMain { $0.applyECG(r) }
            }

        case HD.health6B:
            // One-key combined result. ⚠︎ VERIFY-ON-DEVICE: field names/scaling below.
            if let m = zrhData as? ZR6BHealthDataModel {
                var r = VB9OneKey()
                r.hr = m.hr_avg_bpm > 0 ? m.hr_avg_bpm : nil
                r.spo2 = m.spio > 0 ? m.spio : nil
                r.breathRate = m.breath > 0 ? m.breath : nil
                r.fatigue = m.hrv_fatigue > 0 ? m.hrv_fatigue : nil
                r.stress = m.mood > 0 ? m.mood : nil                 // ⚠︎ mood≈stress until confirmed
                r.sbp = m.bp_sbp > 0 ? m.bp_sbp : nil
                r.dbp = m.bp_dbp > 0 ? m.bp_dbp : nil
                if let t = m.temp, t.estiArm1 > 0 { r.temperatureC = Double(t.estiArm1) / 100.0 } // ⚠︎ scaling
                onMain { $0.applyOneKey(r) }
            }

        case HD.summary:
            if let m = zrhData as? ZRSummaryData {
                agg(date) { a in
                    if m.steps > 0 { a.steps = max(a.steps ?? 0, Int(m.steps)) }  // daily total
                    if m.calorie > 0 { a.activeKcal = Double(m.calorie) }
                    if let sm = m.sleepMinutes?.doubleValue, sm > 0 { a.sleepH = sm / 60.0 }
                    // NOTE: summary.heartRate is "last detected HR", not resting — don't use it for RHR.
                }
            }

        case HD.minute:
            if let m = zrhData as? ZRData61Model {
                agg(date) { a in
                    let hr = Double(m.avg_bpm)
                    if hr >= 30, hr <= 220 { a.restingHR = min(a.restingHR ?? .greatestFiniteMagnitude, hr) }
                    if m.min_bpm > 0 { a.hrMin = min(a.hrMin ?? .greatestFiniteMagnitude, Double(m.min_bpm)) }
                    if m.max_bpm > 0 { a.hrMax = max(a.hrMax ?? 0, Double(m.max_bpm)) }
                    let sdnn = Double(m.sdnn); if sdnn >= 5, sdnn <= 200 { a.hrvSum += sdnn; a.hrvN += 1 }
                    let ox = Double(m.avgOxy); if ox >= 70, ox <= 100 { a.spo2Sum += ox; a.spo2N += 1 }
                    if m.fatigue > 0 { a.fatigue = Double(m.fatigue) }
                    if m.sbp > 0 { a.sbp = Double(m.sbp) }
                    if m.dbp > 0 { a.dbp = Double(m.dbp) }
                    if m.est_t > 0 { a.tempSum += Double(m.est_t); a.tempN += 1 }
                    if m.step > 0 { a.steps = (a.steps ?? 0) + Int(m.step) }
                }
            }

        case HD.sleep:
            if let m = zrhData as? ZRSleepData {
                // sleep_type 3 = deep; activity is minutes in that state.
                agg(m.start_time ?? date) { a in
                    let h = Double(m.activity) / 60.0
                    a.sleepH = (a.sleepH ?? 0) + h
                    if m.sleep_type.rawValue == 3 { a.deepH = (a.deepH ?? 0) + h }
                }
            }

        case HD.spo2:
            if let m = zrhData as? ZRRRIModel {
                for v in (m.dataArray ?? []).compactMap({ ($0 as? NSNumber)?.doubleValue }) where v >= 70 && v <= 100 {
                    agg(date) { $0.spo2Sum += v; $0.spo2N += 1 }
                }
            }

        case HD.temp:
            if let m = zrhData as? ZRTemperatureModel, m.estiArm1 > 0 {
                agg(date) { $0.tempSum += Double(m.estiArm1); $0.tempN += 1 }
            }

        default:
            break
        }
    }

    func updateNormalHealthDataInfo(_ zrDInfo: ZRDataInfo) {
        // Index table: for each date-range entry, request that type's detail.
        guard let s = solstice else { return }
        let type = Int(zrDInfo.dataType)
        log("updateNormalHealthDataInfo dataType=0x\(String(type, radix: 16)) entries=\(zrDInfo.ddInfos?.count ?? 0)")
        for dd in (zrDInfo.ddInfos ?? []) {
            let date = dd.date
            // Watch-class data needs the seq range from the index entry, or the band returns nothing.
            switch type {
            case 0x61: s.startSpecialData(sdType(SD.normal), with: date, startSeq: dd.seqStart, endSeq: dd.seqEnd) // NormalHealth
            case 0x64: s.startSpecialData(sdType(SD.ecg), with: date, startSeq: dd.seqStart, endSeq: dd.seqEnd)    // ECG
            case 0x66: s.startSpecialData(SD_TYPE(rawValue: 0x0A) ?? sdType(SD.normal), with: date, startSeq: dd.seqStart, endSeq: dd.seqEnd) // RRI/AF
            case 0x69: s.startSpecialData(sdType(SD.spo2), with: date, startSeq: dd.seqStart, endSeq: dd.seqEnd)   // SpO2
            case 0x70: s.startSpecialData(sdType(SD.temp), with: date, startSeq: dd.seqStart, endSeq: dd.seqEnd)   // Temperature
            default: break
            }
        }
    }

    func syscDataFinishedStateChange(_ ksdState: KSyscDataState) {
        log("syscDataFinishedStateChange state=\(ksdState.rawValue)")
        guard ksdState.rawValue == VB9Bridge.kSyncFinished else { return }
        syncing = false
        flushHistory()   // backup flush; the debounced flush catches late-arriving bursts
    }
}
#endif
