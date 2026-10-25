#if canImport(QCBandSDK)
import Foundation
import CoreBluetooth
import UIKit
import QCBandSDK

// On-device bridge for the QRing smart ring (QCBandSDK). Compiles only on the device build (framework linked
// [sdk=iphoneos*]). Unlike the VB9, the APP owns CoreBluetooth: we scan the ring's service UUIDs, connect,
// hand the peripheral to QCSDKManager, then use QCSDKCmdCreator (commands) + OdmBandNotifyCenter (realtime
// notifications) + QCSDKManager block callbacks. Everything marshals onto the main actor into QRingManager,
// feeding the SAME Store.applyVB9History pipeline. See docs/qring-integration.md.
//
// Obj-C→Swift API spellings are best-effort (confirmed by the device compile-check, like the VB9 port).
final class QRingBridge: NSObject {

    private weak var manager: QRingManager?
    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]
    private var connecting: CBPeripheral?
    private var pendingName: String?
    private var autoConnecting = false
    private var histObservers: [NSObjectProtocol] = []
    // Native protocol executor (Colmi R02 wire protocol, teardown §12) — borrows the peripheral delegate
    // from the SDK for one command at a time, inside the same serial queue. SDK calls stay as fallback.
    private var ringDirect: RingDirect?

    // Serial command queue — the QCBandSDK requires commands to run ONE AT A TIME (simultaneous calls drop).
    private var cmdQueue: [(@escaping () -> Void) -> Void] = []
    private var cmdRunning = false
    private var syncing = false   // guards against overlapping syncHistory passes (which return empty)
    private var syncToken: UUID?  // invalidates a stale watchdog when a new sync starts
    // Days (DateKey) already covered by the NATIVE protocol this sync — the SDK fallback reads skip them.
    private var nativeHRDays: Set<String> = []
    private var nativeSleepDays: Set<String> = []
    private func enqueue(_ cmd: @escaping (@escaping () -> Void) -> Void) { cmdQueue.append(cmd); runNext() }

    /// Enqueue a read that fails intermittently (the SDK's multi-stage history commands do, on a weak
    /// link). `attempt` runs the read and calls back `true` if it got data / succeeded. On failure it is
    /// re-enqueued (after a short delay, at the BACK of the queue so other reads proceed) up to `tries`.
    private func enqueueRetrying(_ label: String, tries: Int = 3, _ attempt: @escaping (@escaping (Bool) -> Void) -> Void) {
        func run(_ left: Int) {
            enqueue { [weak self] done in
                attempt { ok in
                    if ok || left <= 1 { if !ok { self?.log("\(label) gave up after \(tries) tries") }; done(); return }
                    self?.log("\(label) failed → retry (\(left - 1) left)")
                    done()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { run(left - 1) }
                }
            }
        }
        run(tries)
    }
    private func runNext() {
        guard !cmdRunning, !cmdQueue.isEmpty else { return }
        cmdRunning = true
        let cmd = cmdQueue.removeFirst()
        var done = false
        let finish: () -> Void = { [weak self] in
            guard !done else { return }; done = true
            self?.cmdRunning = false; self?.runNext()
        }
        cmd(finish)
        // Safety: don't let a silent command stall the queue forever. 20s (was 8s) — heavy multi-packet
        // reads like sleep detail (96 slots) regularly take >8s, and firing finish() early launched the
        // NEXT command concurrently → the SDK drops BOTH (seen as "sleep fail" + "currentSport fail"
        // together). Real commands call finish() the instant they return, so this only affects stuck ones.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finish() }
    }

    init(manager: QRingManager) {
        self.manager = manager
        super.init()
        // State restoration (WHOOP-style always-on, phase 2): iOS relaunches the app in the background
        // on strap connection events and hands the session back via willRestoreState. Requires the
        // bluetooth-central UIBackgroundMode (already in Info.plist).
        self.central = CBCentralManager(delegate: self, queue: nil,
                                        options: [CBCentralManagerOptionRestoreIdentifierKey: "humans-strap-central"])
        OdmBandNotifyCenter.registerNotify()
        observeRealtime()
        log("QRing bridge init")
    }

    // Background execution window: a sync kicked off while backgrounded (state restoration / bg connect
    // event) gets ~30 s of runtime from iOS instead of being frozen mid-read.
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private func beginBackgroundWindow() {
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "qring-sync") { [weak self] in
            self?.endBackgroundWindow()
        }
    }
    private func endBackgroundWindow() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid
    }

    private func log(_ s: String) {
        NSLog("[QRing] %@", s)
        onMain { $0.pushLog(s) }
    }
    private func onMain(_ body: @escaping @MainActor (QRingManager) -> Void) {
        Task { @MainActor [weak manager] in if let m = manager { body(m) } }
    }

    // MARK: Commands (called from QRingManager)

    func start() { startScan() }   // bridge auto-connects to the ring on discovery

    func startScan() {
        peripherals.removeAll(); autoConnecting = false
        guard central.state == .poweredOn else {
            log("scan — bluetooth not powered on (state \(central.state.rawValue))")
            onMain { $0.btPower = "state \(self.central.state.rawValue)" }
            return
        }
        onMain { $0.btPower = "powered on" }
        // Reuse a known/already-connected ring FIRST — this survives app reinstall: the system keeps the
        // link even when the ring isn't advertising, so we don't need a BT toggle after every install.
        if let p = knownRing() {
            log("reusing known ring \(p.name ?? p.identifier.uuidString)")
            peripherals[p.identifier.uuidString] = p
            autoConnecting = true
            connect(id: p.identifier.uuidString)
            return
        }
        // Else broad scan (rings often don't advertise their service UUIDs). Named devices only — see didDiscover.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("scan started (broad — all BLE)")
    }

    private func knownRing() -> CBPeripheral? {
        let svc = [CBUUID(string: QCBANDSDKSERVERUUID1), CBUUID(string: QCBANDSDKSERVERUUID2)]
        if let p = central.retrieveConnectedPeripherals(withServices: svc).first { return p }
        if let idStr = UserDefaults.standard.string(forKey: "qringPeripheralId"), let uuid = UUID(uuidString: idStr) {
            return central.retrievePeripherals(withIdentifiers: [uuid]).first
        }
        return nil
    }

    func stopScan() { central.stopScan() }

    func connect(id: String) {
        guard let p = peripherals[id] else { onMain { $0.ingestError("Ring no longer in range — scan again.") }; return }
        connecting = p; pendingName = p.name
        userRequestedDisconnect = false
        central.stopScan()
        central.connect(p, options: nil)
        log("connecting to \(p.name ?? "ring")…")
    }

    func disconnect() {
        autoConnecting = false
        userRequestedDisconnect = true
        if let p = connecting { central.cancelPeripheralConnection(p) }
    }
    private var userRequestedDisconnect = false
    var restoredPending: [CBPeripheral] = []   // stashed by willRestoreState until poweredOn

    func startLiveHR() {
        log("startLiveHR")
        QCSDKCmdCreator.realTimeHeartRate(with: QCBandRealTimeHeartRateCmdTypeStart, finished: nil)
        QCSDKManager.shareInstance().realTimeHeartRate = { [weak self] hr in
            self?.onMain { $0.ingestLiveHR(hr) }
        }
    }
    func stopLiveHR() {
        QCSDKCmdCreator.realTimeHeartRate(with: QCBandRealTimeHeartRateCmdTypeEnd, finished: nil)
    }

    private var lastOneKey: QCRealOneKeyMeasureHeartRateModel?
    private var lastLiveHR = 0

    /// One-key heart-rate reading. On this ring the live handler streams HR as an NSNumber (not a full
    /// model), so we capture it and save it on completion. HRV / stress / SpO₂ come from the scheduled
    /// history sync (the ring auto-records them all day).
    func oneKeyMeasure(auto: Bool = false) {
        log("oneKeyMeasure (OneKeyMeasureHeartRate)\(auto ? " [auto]" : "")")
        lastOneKey = nil; lastLiveHR = 0
        oneKeyRRIs.removeAll()
        QCSDKManager.shareInstance().startToMeasuring(withOperateType: .oneKeyMeasureHeartRate,
            measuringHandle: { [weak self] live in
                if let m = live as? QCRealOneKeyMeasureHeartRateModel {
                    self?.lastOneKey = m
                    // True-HRV path for this strap (raw PPG unsupported): the live RRI updates ~1×/s
                    // during the measure — accumulate the series, rMSSD computed at completion.
                    if m.rri > 0 { self?.oneKeyRRIs.append(Double(m.rri)) }
                    if m.heartRateValue > 0 { self?.lastLiveHR = m.heartRateValue; self?.onMain { $0.ingestLiveHR(m.heartRateValue) } }
                } else if let n = live as? NSNumber, n.intValue > 0 {
                    self?.lastLiveHR = n.intValue
                    self?.onMain { $0.ingestLiveHR(n.intValue) }
                }
            },
            completedHandle: { [weak self] ok, result, err in
                guard let self else { return }
                let m = (result as? QCRealOneKeyMeasureHeartRateModel) ?? self.lastOneKey
                self.log("oneKey done ok=\(ok) model=\(m != nil) hr=\(self.lastLiveHR) err=\((err as NSError?)?.code ?? 0)")
                if let r = RingPPG.rmssd(fromRRIms: self.oneKeyRRIs) {
                    self.log(String(format: "★ RRI rMSSD=%.0f ms (from %d intervals, %d samples)",
                                    r.rmssd, r.usedIntervals, self.oneKeyRRIs.count))
                }
                // Everything (HR, HRV, stress, temp, BP) comes from the SINGLE one-key model — no second
                // concurrent measurement (that collided → err=-1). If the model carries no temp, fire the
                // temp measure SEQUENTIALLY (after one-key fully finished) so it never overlaps.
                if let m, m.heartRateValue > 0 || m.rri > 0 {
                    self.applyOneKey(m, silent: auto)
                    if m.temp <= 0 { self.measureTemperature() }
                } else if self.lastLiveHR > 0 {
                    self.onMain { $0.applyOneKey(hr: self.lastLiveHR, hrvMs: nil, rriMs: nil, stress: nil, tempC: nil, sbp: nil, dbp: nil, silent: auto) }
                    self.measureTemperature()
                } else if !ok {
                    let code = (err as NSError?)?.code ?? 0
                    if !auto {
                        let msg = code == -4 ? "Ring needs calibration — tap Measure again to calibrate + measure."
                                             : "Measurement failed — wear the ring snug, stay still."
                        self.onMain { $0.ingestError(msg) }
                    }
                }
            })
    }

    /// On-demand body-temperature measurement — this ring stores NO temperature history (all history
    /// Normalize a raw body-temperature value to °C. The official QRing APK parses the wire byte as
    /// `(byte / 10) + 32` (0.1 °C units offset from 32 °C), e.g. raw 42 → 36.2 °C. The iOS SDK may hand
    /// us the already-converted °C, the pre-offset tenths (≈4.x), or raw tenths (≈362). Try each
    /// interpretation and accept the first that lands in a plausible body range — so we stop dropping
    /// the ~4.x values our old `clamp 30–45` silently discarded.
    static func normalizedBodyTemp(_ v: Double) -> Double? {
        let plausible = { (t: Double) in t >= 30 && t <= 45 }
        let candidates = [v, v + 32, v / 10 + 32, v / 10, v / 100]   // already-°C, offset, byte/10+32, tenths, hundredths
        return candidates.first(where: plausible)
    }

    /// On-demand body-temperature measurement. NB: the ODM platform stores a temperature *series* only
    /// via the dfu_temperature file-transfer protocol (opcodes 37/38) the simple history commands don't
    /// touch — confirmed in the official APK — which is why our history reads come back empty; on-demand
    /// measurement via the Measure button is the reliable path on this ring.
    private func measureTemperature() {
        log("measuring body temperature")
        let handle: (Any?) -> Void = { [weak self] obj in
            guard let self, let obj else { return }
            var cands: [Double] = []
            if let m = obj as? QCTemperatureModel { cands = [Double(m.temperature)] }
            else if let m = obj as? QCThreeValueTemperatureModel { cands = [Double(m.temperature1), Double(m.temperature2), Double(m.temperature3)] }
            else if let n = obj as? NSNumber { cands = [n.doubleValue] }
            for v in cands {
                if let t = Self.normalizedBodyTemp(v) {
                    self.log("body temp=\(t) (raw \(v))")
                    self.onMain { $0.ingestTemperature(t) }
                    break
                }
            }
        }
        QCSDKManager.shareInstance().startToMeasuring(withOperateType: .bodyTemperature,
            measuringHandle: { live in handle(live) },
            completedHandle: { [weak self] ok, result, err in
                self?.log("temp measure done ok=\(ok) err=\((err as NSError?)?.code ?? 0)")
                handle(result)
                if !ok {
                    // Some VY28C units only expose the three-value temperature operate type.
                    QCSDKManager.shareInstance().startToMeasuring(withOperateType: .threeValueBodyTemperature,
                        measuringHandle: { live in handle(live) },
                        completedHandle: { [weak self] ok2, result2, err2 in
                            self?.log("temp3 measure done ok=\(ok2) err=\((err2 as NSError?)?.code ?? 0)")
                            handle(result2)
                            self?.onMain { $0.isMeasuring = false }
                        })
                } else {
                    self?.onMain { $0.isMeasuring = false }
                }
            })
    }

    /// Turn on the ring's all-day scheduled recording (off by default). Without this the ring stores no
    /// HRV / stress / SpO₂ / HR history, so sync comes back empty.
    private func enableMonitoring() {
        enqueue { [weak self] done in
            QCSDKCmdCreator.setSchedualHeartRateStatus(true, success: { _ in self?.log("HR monitoring ON"); done() }, fail: { done() })
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.setSchedualHRVStatus(true, finshed: { err in self?.log("HRV monitoring ON err=\((err as NSError?)?.code ?? 0)"); done() })
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.setSchedualStressStatus(true, finshed: { err in self?.log("stress monitoring ON err=\((err as NSError?)?.code ?? 0)"); done() })
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.setSchedualBOInfoOn(true, success: { _ in self?.log("SpO2 monitoring ON"); done() }, fail: { done() })
        }
        enqueue { [weak self] done in
            // Body temperature is a "scheduled info" feature (type 3 = BodyTemperator).
            QCSDKCmdCreator.setSchedualInfoType(SchedualInfoType(rawValue: 3) ?? .bloodGlucose, featureOn: true,
                calibrate: 0, success: { self?.log("temp monitoring ON"); done() }, fail: { done() })
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.setSchedualBPInfoOn(true, beginTime: "00:00", endTime: "23:59", minuteInterval: 60,
                success: { _, _, _, _ in self?.log("BP monitoring ON"); done() }, fail: { done() })
        }
    }

    /// Serial history sync — each command waits for the previous to finish (SDK requirement). Logs each
    /// result count so we can verify what the ring actually has. Today + yesterday (0,1) to keep it short.
    func syncHistory() {
        if syncing { log("syncHistory skipped — a sync is already running"); return }
        syncing = true
        if UIApplication.shared.applicationState != .active { beginBackgroundWindow() }
        log("syncHistory (serial)")
        // Hard watchdog: if the final "sync complete" marker never fires (a dropped command), the guard
        // would wedge true forever and freeze all future syncs. Force-clear it after 30 s no matter what.
        let token = UUID(); syncToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.syncing, self.syncToken == token else { return }
            self.log("sync watchdog fired — clearing stuck guard"); self.syncing = false
        }
        histAgg.removeAll(); histWorkouts.removeAll()
        nativeHRDays.removeAll(); nativeSleepDays.removeAll()
        // ★ NATIVE sleep read — Big Data channel, dataId 0x27, ONE request returns ALL retained nights
        // (the SDK's per-day sleep read is the flakiest command on this strap). SDK path below is fallback.
        enqueueRetrying("sleep (bigData 0x27)", tries: 2) { [weak self] finish in
            guard let self, let direct = self.ringDirect else { finish(true); return }
            direct.runBigData(RingProtocol.bigDataRequest(.sleep), timeout: 15) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let e):
                    self.log("sleep 0x27 ✗ \(e.localizedDescription)"); finish(false)
                case .success(let msg):
                    guard msg.id == RingProtocol.BigDataID.sleep.rawValue else {
                        self.log("sleep 0x27: unexpected dataId \(msg.id)"); finish(false); return
                    }
                    let nights = RingProtocol.parseSleepPayload(msg.payload)
                    self.log("sleep 0x27 ✓ bytes=\(msg.payload.count) nights=\(nights.count)")
                    for n in nights {
                        let k = self.dayKey(daysAgo: n.daysAgo)
                        self.nativeSleepDays.insert(k)
                        self.agg(k) {
                            $0.sleepH = Double(n.asleepMin) / 60.0
                            if n.deepMin > 0 { $0.deepH = Double(n.deepMin) / 60.0 }
                            if n.remMin > 0 { $0.remH = Double(n.remMin) / 60.0 }
                        }
                    }
                    self.scheduleFlush(); finish(true)
                }
            }
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.getSchedualHRVData(withDates: self?.weekDates ?? []) { models, _ in
                let arr = (models as? [QCHRVModel]) ?? []
                self?.log("HRV models=\(arr.count)")
                for m in arr {
                    let vals = (m.hrv ?? []).map(\.doubleValue).filter { $0 >= 5 && $0 <= 200 }
                    if let k = self?.keyFromDateString(m.date), !vals.isEmpty { self?.agg(k) { $0.hrvSum += vals.reduce(0,+); $0.hrvN += vals.count } }
                }
                self?.scheduleFlush(); done()
            }
        }
        enqueue { [weak self] done in
            QCSDKCmdCreator.getSchedualStressData(withDates: self?.weekDates ?? []) { models, _ in
                let arr = (models as? [QCStressModel]) ?? []
                self?.log("stress models=\(arr.count)")
                for m in arr {
                    let vals = (m.stresses ?? []).map(\.doubleValue).filter { $0 > 0 }
                    if let k = self?.keyFromDateString(m.date), !vals.isEmpty { self?.agg(k) { $0.stressSum += vals.reduce(0,+); $0.stressN += vals.count } }
                }
                self?.scheduleFlush(); done()
            }
        }
        for day in 0...1 {
            enqueue { [weak self] done in
                QCSDKCmdCreator.getBloodOxygenData(byDayIndex: day) { datas, _ in
                    let models = (datas as? [QCBloodOxygenModel]) ?? []
                    let nums = (datas as? [NSNumber])?.map { $0.doubleValue } ?? []
                    let vals = (models.isEmpty ? nums : models.map { Double($0.soa2) }).filter { $0 >= 70 && $0 <= 100 }
                    self?.log("spo2 day\(day)=\(vals.count)")
                    let k = self?.dayKey(daysAgo: day) ?? ""
                    for v in vals { self?.agg(k) { $0.spo2Sum += v; $0.spo2N += 1 } }
                    self?.scheduleFlush(); done()
                }
            }
            enqueue { [weak self] done in
                QCSDKCmdCreator.getBloodGlucoseData(byDayIndex: day) { datas, _ in
                    let arr = (datas as? [QCBloodGlucoseModel]) ?? []
                    self?.log("glucose day\(day)=\(arr.count)")
                    let k = self?.dayKey(daysAgo: day) ?? ""
                    let vals = arr.map { Double($0.glu) }.filter { $0 > 0 }
                    if let avg = vals.isEmpty ? nil : vals.reduce(0,+) / Double(vals.count) {
                        let mgdl = avg < 30 ? avg * 18.0 : avg    // mmol/L → mg/dL if needed
                        self?.agg(k) { $0.glu = mgdl }
                    }
                    self?.scheduleFlush(); done()
                }
            }
            enqueue { [weak self] done in
                let k = self?.dayKey(daysAgo: day) ?? ""
                // The official app's temperature can live under scheduled, manual, OR interval storage.
                // Try each in turn; the first that returns data wins. Parse QCTemperatureModel /
                // QCThreeValueTemperatureModel / NSNumber robustly (°C, auto-scaled from 0.1°C units).
                let parse: (Any?, String) -> Int = { list, src in
                    let raw = (list as? [Any]) ?? []
                    self?.log("temp day\(day) \(src)=\(raw.count)\(raw.first.map { " type=\(type(of: $0))" } ?? "")")
                    for item in raw {
                        var cands: [Double] = []
                        if let m = item as? QCTemperatureModel { cands = [Double(m.temperature)] }
                        else if let m = item as? QCThreeValueTemperatureModel { cands = [Double(m.temperature1), Double(m.temperature2), Double(m.temperature3)] }
                        else if let n = item as? NSNumber { cands = [n.doubleValue] }
                        for v in cands { if let t = Self.normalizedBodyTemp(v) { self?.agg(k) { $0.tempSum += t; $0.tempN += 1 }; break } }
                    }
                    return raw.count
                }
                QCSDKCmdCreator.getSchedualTemperatureData(byDayIndex: day) { list, _ in
                    if parse(list, "sched") > 0 { self?.scheduleFlush(); done(); return }
                    QCSDKCmdCreator.getManualTemperatureData(byDayIndex: day) { list2, _ in
                        if parse(list2, "manual") > 0 { self?.scheduleFlush(); done(); return }
                        QCSDKCmdCreator.getTemperatureDataWithInterval(byDayIndex: day) { _, list3, _ in
                            _ = parse(list3, "interval")
                            self?.scheduleFlush(); done()
                        }
                    }
                }
            }
            enqueue { [weak self] done in
                // SDK sleep fallback — skipped when the native Big Data read already covered this day.
                if let self, self.nativeSleepDays.contains(self.dayKey(daysAgo: day)) {
                    self.log("sleep day\(day) skipped (native 0x27 covered)"); done(); return
                }
                // Parse a sleep-model array into total/deep/REM hours (type 2=light, 3=deep, 4=REM).
                let store: ([QCSleepModel], String) -> Bool = { arr, k in
                    var total = 0.0, deep = 0.0, rem = 0.0
                    for s in arr {
                        let h = Double(s.total) / 60.0
                        guard s.type.rawValue >= 1, s.type.rawValue <= 4 else { continue }   // skip none/unworn
                        total += h
                        if s.type.rawValue == 3 { deep += h }
                        if s.type.rawValue == 4 { rem += h }
                    }
                    if total > 0 { self?.agg(k) { $0.sleepH = total; if deep > 0 { $0.deepH = deep }; if rem > 0 { $0.remH = rem } } }
                    return total > 0
                }
                let k = self?.dayKey(daysAgo: day) ?? ""
                QCSDKCmdCreator.getFulldaySleepDetailData(byDay: day, sleepDatas: { sleeps, naps in
                    let arr = ((sleeps as? [QCSleepModel]) ?? []) + ((naps as? [QCSleepModel]) ?? [])
                    self?.log("sleep day\(day)=\(arr.count)")
                    if store(arr, k) { self?.scheduleFlush(); done(); return }
                    // Empty → this ring likely uses the NEW sleep protocol; read it via V2.
                    QCSDKCmdCreator.getSleepDetailDataV2(byDay: day, sleepDatas: { dict in
                        let v2 = dict.values.flatMap { $0 }
                        self?.log("sleep v2 day\(day)=\(v2.count)")
                        _ = store(v2, k); self?.scheduleFlush(); done()
                    }, fail: { self?.log("sleep v2 day\(day) fail"); self?.scheduleFlush(); done() })
                }, fail: {
                    self?.log("sleep day\(day) fail → trying v2")
                    QCSDKCmdCreator.getSleepDetailDataV2(byDay: day, sleepDatas: { dict in
                        let v2 = dict.values.flatMap { $0 }
                        self?.log("sleep v2 day\(day)=\(v2.count)")
                        _ = store(v2, k); self?.scheduleFlush(); done()
                    }, fail: { self?.log("sleep v2 day\(day) fail"); self?.scheduleFlush(); done() })
                })
            }
        }
        // Today's step/calorie total. getCurrentSport is the reliable path on this ring (the per-day
        // getSportDetailData/getOneDaySport fail). calories is in small-calories → ÷1000 for kcal.
        enqueueRetrying("currentSport") { [weak self] finish in
            QCSDKCmdCreator.getCurrentSportSucess({ model in
                let kcal = model.calories > 2000 ? model.calories / 1000.0 : model.calories
                self?.log("currentSport steps=\(model.totalStepCount) kcal=\(Int(kcal))")
                let k = self?.dayKey(daysAgo: 0) ?? ""
                if model.totalStepCount > 0 { self?.agg(k) { $0.steps = model.totalStepCount; $0.activeKcal = kcal } }
                self?.scheduleFlush(); finish(true)
            }, failed: { self?.log("currentSport fail"); finish(false) })
        }
        // ★ Full HR series for days 0–6 via the NATIVE opcode-21 read (the timestamped command the
        // official app uses and the iOS SDK never exposed — teardown §12). Our transport, SDK idle;
        // fills resting HR + envelope + the 5-min series (HR-zone minutes) per day. Days that succeed
        // are marked in nativeHRDays so the SDK fallbacks below skip them.
        for day in 0...6 {
            enqueueRetrying("HR op21 day\(day)", tries: day == 0 ? 3 : 2) { [weak self] finish in
                guard let self, let direct = self.ringDirect else { finish(true); return }   // no link → skip quietly
                let target = DateKey.daysAgo(day)
                let parser = RingHeartRateLogParser(requestedToday: day == 0)
                var result: RingHeartRateLog?
                direct.run(RingProtocol.heartRateLogRequest(day: target), timeout: 15, onFrame: { frame in
                    switch parser.feed(frame) {
                    case .waiting: return false
                    case .noData: return true
                    case .done(let log): result = log; return true
                    }
                }, completion: { [weak self] err in
                    guard let self else { return }
                    if let err { self.log("op21 day\(day) ✗ \(err.localizedDescription)"); finish(false); return }
                    guard let r = result else {
                        // An empty HISTORY day is a real answer (strap not worn) — don't burn retries on it.
                        self.log("op21 day\(day): no data"); finish(day != 0); return
                    }
                    let hrs = r.samples.filter { $0 >= 30 && $0 <= 220 }
                    self.log("op21 day\(day) ✓ valid=\(hrs.count) interval=\(r.intervalMinutes)m")
                    guard let lo = hrs.min(), let hi = hrs.max() else { finish(day != 0); return }
                    let k = self.dayKey(daysAgo: day)
                    self.nativeHRDays.insert(k)
                    self.agg(k) {
                        $0.restingHR = min($0.restingHR ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMin = min($0.hrMin ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMax = max($0.hrMax ?? 0, Double(hi))
                        $0.hrSeries = hrs            // assignment (not append) — native wins over any SDK data
                        $0.hrInterval = r.intervalMinutes * 60
                    }
                    self.scheduleFlush(); finish(true)
                })
            }
        }
        // SDK scheduled-HR history — FALLBACK: only aggregates days the native op21 reads missed.
        enqueueRetrying("HR series (SDK fallback)") { [weak self] finish in
            guard let self else { finish(true); return }
            if self.nativeHRDays.count >= 7 { self.log("HR series skipped (op21 covered all 7 days)"); finish(true); return }
            QCSDKCmdCreator.getSchedualHeartRateData(withDayIndexs: self.weekDates, success: { [weak self] models in
                let arr = (models as? [QCSchedualHeartRateModel]) ?? []
                self?.log("HR models=\(arr.count)")
                for m in arr {
                    let hrs = (m.heartRates ?? []).map(\.intValue).filter { $0 >= 30 && $0 <= 220 }
                    guard !hrs.isEmpty, let k = self?.keyFromDateString(m.date), let lo = hrs.min(), let hi = hrs.max() else { continue }
                    if self?.nativeHRDays.contains(k) == true { continue }   // native already owns this day
                    self?.agg(k) {
                        $0.restingHR = min($0.restingHR ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMin = min($0.hrMin ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMax = max($0.hrMax ?? 0, Double(hi))
                        $0.hrSeries.append(contentsOf: hrs)       // all-day series → HR-zone minutes
                        if m.secondInterval > 0 { $0.hrInterval = m.secondInterval }
                    }
                }
                self?.scheduleFlush(); finish(!arr.isEmpty)
            }, fail: { [weak self] in self?.log("HR series fail"); finish(false) })
        }
        // TODAY's HR range — second SDK fallback, only when op21 missed today. Parse defensively
        // (NSNumber bpm values OR models carrying a heartRates array).
        enqueue { [weak self] done in
            if let self, self.nativeHRDays.contains(self.dayKey(daysAgo: 0)) { done(); return }
            QCSDKCmdCreator.getOneMinuHeartRateDataWithInterval(byDayIndex: 0) { data, _ in
                let raw = (data as? [Any]) ?? []
                var hrs: [Int] = []
                for item in raw {
                    if let n = item as? NSNumber { hrs.append(n.intValue) }
                    else if let m = item as? QCSchedualHeartRateModel { hrs.append(contentsOf: (m.heartRates ?? []).map(\.intValue)) }
                    else if let m = item as? QCManualHeartRateModel { hrs.append(contentsOf: (m.heartRates ?? []).map(\.intValue)) }
                }
                hrs = hrs.filter { $0 >= 30 && $0 <= 220 }
                self?.log("today 1-min HR count=\(raw.count) valid=\(hrs.count)")
                if let lo = hrs.min(), let hi = hrs.max() {
                    let k = self?.dayKey(daysAgo: 0) ?? ""
                    self?.agg(k) {
                        $0.restingHR = min($0.restingHR ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMin = min($0.hrMin ?? .greatestFiniteMagnitude, Double(lo))
                        $0.hrMax = max($0.hrMax ?? 0, Double(hi))
                    }
                }
                self?.scheduleFlush(); done()
            }
        }
        // Blood pressure history → per-day SBP/DBP.
        enqueue { [weak self] done in
            QCSDKCmdCreator.getSchedualBPHistoryData(success: { data in
                let arr = (data as? [QCBloodPressureModel]) ?? []
                self?.log("BP models=\(arr.count)")
                for m in arr where m.systolicPressure > 0 && m.diastolicPressure > 0 {
                    guard let k = self?.dateKey(m.date) else { continue }
                    self?.agg(k) { $0.sbp = Double(m.systolicPressure); $0.dbp = Double(m.diastolicPressure) }
                }
                self?.scheduleFlush(); done()
            }, fail: { done() })
        }
        // Workouts / exercise sessions → VB9Work.
        enqueue { [weak self] done in
            QCSDKCmdCreator.getExerciseData(withLastUnixSeconds: 0, getData: { models in
                let arr = (models as? [QCExerciseModel]) ?? []
                self?.log("workouts=\(arr.count)")
                for m in arr where m.usable {
                    let date = Date(timeIntervalSince1970: Double(m.startTime) / 1000.0)
                    let hrs = (m.heartRates ?? []).map(\.doubleValue).filter { $0 > 0 }
                    let avgHR = hrs.isEmpty ? nil : hrs.reduce(0,+) / Double(hrs.count)
                    self?.histWorkouts.append(VB9Work(date: DateKey.key(date),
                                                      name: self?.exerciseName(m.type),
                                                      minutes: Double(m.lastSeconds) / 60.0,
                                                      kcal: Double(m.calories), avgHR: avgHR))
                }
                self?.scheduleFlush(); done()
            }, fail: { done() })
        }
        // Final marker — clears the overlap guard once every history command has drained, then captures
        // a wrist-temperature sample on-demand (this ring exposes no readable temp history via the SDK).
        enqueue { [weak self] done in
            self?.log("sync complete"); self?.syncing = false; self?.scheduleFlush(); done()
            self?.autoOneKeyIfDue()
            // Give the flush + CloudSync push (debounced ~4 s total) time to land before the background
            // window closes; harmless when running in the foreground.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self?.endBackgroundWindow() }
        }
    }

    private var oneKeyRRIs: [Double] = []   // live RRI stream of the current one-key measure (→ rMSSD)

    /// After each sync, take ONE silent one-key measurement (throttled ~15 min). This single reading gives
    /// HR (→ today's HR range + resting HR via observeHeartRate), HRV, stress, temp, and BP in one shot —
    /// avoiding the concurrent temp+HR measurements that collided (err=-1). Runs a couple seconds after the
    /// queue drains so it never overlaps a history command.
    private var lastAutoMeasure: Date?
    private func autoOneKeyIfDue() {
        if let last = lastAutoMeasure, Date().timeIntervalSince(last) < 15 * 60 { return }
        lastAutoMeasure = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.log("auto one-key (post-sync)")
            self?.oneKeyMeasure(auto: true)
        }
    }

    private func dateKey(_ d: Date?) -> String? { d.map { DateKey.key($0) } }
    private func exerciseName(_ t: ExerciseType) -> String {
        switch t { case .run: return "Run"; case .bike: return "Cycle"; case .weightLifting: return "Strength"; case .walk: return "Walk"; @unknown default: return "Workout" }
    }

    // MARK: One-key result

    private func applyOneKey(_ m: QCRealOneKeyMeasureHeartRateModel, silent: Bool = false) {
        log("oneKey hr=\(m.heartRateValue) hrv=\(m.heartRateHRV) rri=\(m.rri) stress=\(m.stress) temp=\(m.temp) bp=\(m.bloodPressureSbp)/\(m.bloodPressureDbp)")
        let tempC = m.temp > 0 ? Self.normalizedBodyTemp(Double(m.temp)) : nil   // scaling varies; normalize
        onMain { $0.applyOneKey(hr: m.heartRateValue > 0 ? m.heartRateValue : nil,
                                hrvMs: m.heartRateHRV > 0 ? m.heartRateHRV : nil,
                                rriMs: m.rri > 0 ? m.rri : nil,
                                stress: m.stress > 0 ? m.stress : nil,
                                tempC: tempC,
                                sbp: m.bloodPressureSbp > 0 ? m.bloodPressureSbp : nil,
                                dbp: m.bloodPressureDbp > 0 ? m.bloodPressureDbp : nil,
                                silent: silent) }
    }

    // MARK: History sync → per-day VB9Day

    private struct DayAgg {
        var hrvSum = 0.0; var hrvN = 0
        var stressSum = 0.0; var stressN = 0
        var spo2Sum = 0.0; var spo2N = 0
        var tempSum = 0.0; var tempN = 0
        var restingHR: Double?
        var hrMin: Double?; var hrMax: Double?
        var sleepH: Double?; var deepH: Double?; var remH: Double?
        var hrSeries: [Int] = []; var hrInterval = 0
        var steps: Int?; var activeKcal: Double?
        var sbp: Double?; var dbp: Double?; var glu: Double?
    }
    private var histAgg: [String: DayAgg] = [:]
    private var histWorkouts: [VB9Work] = []
    private var flushTask: Task<Void, Never>?

    private func agg(_ key: String, _ m: (inout DayAgg) -> Void) {
        var a = histAgg[key] ?? DayAgg(); m(&a); histAgg[key] = a
    }
    private func dayKey(daysAgo i: Int) -> String { DateKey.key(DateKey.daysAgo(i)) }

    /// QRing reports battery either as a level (0–8) or a percent. Normalize to a %.
    private func batteryPct(_ v: Int) -> Int { v > 8 ? min(v, 100) : Int((Double(v) / 8.0 * 100).rounded()) }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
    private func flush() {
        let days: [VB9Day] = histAgg.map { (k, a) in
            var d = VB9Day(date: k)
            if a.hrvN > 0 { d.hrv = a.hrvSum / Double(a.hrvN) }
            if a.stressN > 0 { d.stress = a.stressSum / Double(a.stressN) }
            if a.spo2N > 0 { d.spo2 = a.spo2Sum / Double(a.spo2N) }
            if a.tempN > 0 { var t = a.tempSum / Double(a.tempN); while t > 45 { t /= 10 }; if t >= 30 { d.tempC = t } }
            d.rhr = a.restingHR; d.hrMinDay = a.hrMin; d.hrMaxDay = a.hrMax
            d.sleepH = a.sleepH; d.deepH = a.deepH; d.remH = a.remH
            if !a.hrSeries.isEmpty { d.hrSeries = a.hrSeries; d.hrIntervalSec = a.hrInterval > 0 ? a.hrInterval : 300 }
            d.steps = a.steps; d.activeKcal = a.activeKcal
            d.bpSystolic = a.sbp; d.bpDiastolic = a.dbp; d.glucose = a.glu
            return d
        }
        guard !days.isEmpty else { return }
        onMain { $0.applyHistory(days: days, workouts: self.histWorkouts) }
    }

    private var weekDates: [NSNumber] { (0...6).map { NSNumber(value: $0) } }

    // MARK: Helpers

    /// QRing models return a "yyyy-MM-dd" date string; map it to our DateKey.
    private func keyFromDateString(_ s: String?) -> String? {
        guard let s, s.count >= 10 else { return nil }
        return String(s.prefix(10))   // DateKey is yyyy-MM-dd
    }
    private func hrFrom(_ m: QCSchedualHeartRateModel) -> (String, Double)? {
        // ⚠︎ VERIFY-ON-DEVICE: QCSchedualHeartRateModel field shape (date + hr series vs single).
        nil
    }

    // MARK: Realtime notification observers

    private func observeRealtime() {
        let nc = NotificationCenter.default
        histObservers.append(nc.addObserver(forName: NSNotification.Name(OdmBandRealTimeHeartRate),
                                            object: nil, queue: .main) { [weak self] n in
            if let hr = (n.userInfo?[OdmHeartRateValueKey] as? NSNumber)?.intValue { self?.onMain { $0.ingestLiveHR(hr) } }
        })
        histObservers.append(nc.addObserver(forName: NSNotification.Name(OdmBandRealOneKeyMeasureHeartRate),
                                            object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            if let m = n.object as? QCRealOneKeyMeasureHeartRateModel { self.applyOneKey(m); return }
            let u = n.userInfo
            let hr = (u?[OdmHeartRateValueKey] as? NSNumber)?.intValue
            let hrv = (u?[OdmHeartRateHRVKey] as? NSNumber)?.intValue
            let rri = (u?[OdmRriKey] as? NSNumber)?.intValue
            let stress = (u?[OdmStressKey] as? NSNumber)?.intValue
            let temp = (u?[OdmTempKey] as? NSNumber)?.intValue
            let sbp = (u?[OdmBloodPressureSbpKey] as? NSNumber)?.intValue
            let dbp = (u?[OdmBloodPressureDbpKey] as? NSNumber)?.intValue
            self.log("oneKey NOTIF hr=\(hr ?? -1) hrv=\(hrv ?? -1) rri=\(rri ?? -1) stress=\(stress ?? -1) temp=\(temp ?? -1) bp=\(sbp ?? -1)/\(dbp ?? -1)")
            if (hr ?? 0) > 0 || (rri ?? 0) > 0 {
                self.onMain { $0.applyOneKey(hr: hr, hrvMs: hrv, rriMs: rri, stress: stress,
                                             tempC: temp.map { Double($0) / 10.0 }, sbp: sbp, dbp: dbp) }
            }
        })
        // Raw PPG (red/IR light + accel) — captured for future RRI/HRV signal processing. Log only for now.
        histObservers.append(nc.addObserver(forName: NSNotification.Name(OdmBandRealTimeHeartRateRaw),
                                            object: nil, queue: .main) { [weak self] n in
            let count = (n.userInfo?[OdmPpgCountKey] as? NSNumber)?.intValue ?? 0
            self?.log("raw PPG packet count=\(count)")
        })
        // Real-time ECG (if this ring has electrodes) — log to confirm support.
        histObservers.append(nc.addObserver(forName: .OdmBandRealTimeECG,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.log("ECG packet received")
        })
    }

    /// ★ Raw-PPG capture → true HRV (WHOOP plan phase 4, scaffold). Captures a 100 s window of 25 Hz
    /// green-light PPG, runs RingPPG beat detection → RR intervals → rMSSD, logs the result and saves
    /// the raw window to Documents/PPG/ for offline tuning. Not yet feeding Recovery (phase 4/5 gate:
    /// nightly scheduling + validation against a reference first). Wear the strap snug and stay still.
    func measureRawPPG() {
        // First tap on-device failed INSTANTLY with err=-1 (start-cmd rejected). Known causes: a stale
        // measuring session on the strap, or the raw mode needing a clean stop first. So: stop any
        // lingering raw session, start, and retry once on -1. If it still -1s with the HeartRateRaw
        // feature flag absent from the setTime featureList, raw PPG is unsupported on this firmware →
        // the fallback path is RRI accumulation from one-key measures (model.rri updates every second).
        log("raw PPG: stopping any stale session…")
        QCSDKManager.shareInstance().stopToMeasuring(withOperateType: .heartRateRaw) { [weak self] _, _ in
            self?.startRawPPG(retriesLeft: 1)
        }
    }

    private func startRawPPG(retriesLeft: Int) {
        log("raw PPG capture — 100 s, hold still…")
        var green: [Double] = []
        let collect: (Any?) -> Void = { item in
            if let m = item as? QCBloodGlucoseHeartRateRawModel {
                green.append(Double((m.greenLightPpgH << 8) | m.greenLightPpgL))
            } else if let arr = item as? [QCBloodGlucoseHeartRateRawModel] {
                for m in arr { green.append(Double((m.greenLightPpgH << 8) | m.greenLightPpgL)) }
            }
        }
        QCSDKManager.shareInstance().startToMeasuring(withOperateType: .heartRateRaw, timeout: 100,
            measuringHandle: { live in collect(live) },
            completedHandle: { [weak self] ok, result, err in
                guard let self else { return }
                collect(result)
                let code = (err as NSError?)?.code ?? 0
                self.log("raw PPG done ok=\(ok) samples=\(green.count) (~\(Int(Double(green.count) / 25))s) err=\(code)")
                if !ok, code == -1, green.isEmpty, retriesLeft > 0 {
                    self.log("raw PPG start rejected → retrying in 3 s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.startRawPPG(retriesLeft: retriesLeft - 1)
                    }
                    return
                }
                self.onMain { $0.isMeasuring = false }
                guard green.count >= 500 else {
                    self.onMain { $0.ingestError("PPG capture failed (err \(code)) — check the features log line; if HeartRateRaw is absent this firmware can't stream raw PPG.") }
                    return
                }
                if let a = RingPPG.analyze(ppg: green, hz: 25) {
                    self.log(String(format: "★ PPG rMSSD=%.0f ms · HR %.0f bpm · beats=%d · rr=%d",
                                    a.rmssd, a.meanHR, a.beats, a.rrIntervals.count))
                } else {
                    self.log("PPG analysis: too noisy (motion?) — no clean RR series")
                }
                self.savePPGWindow(green)
            })
    }

    /// Persist a capture window as JSON under Documents/PPG/ (same layout idea as the vendor demo) so
    /// the beat-detection can be tuned offline against real data.
    private func savePPGWindow(_ samples: [Double]) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("PPG", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("ppg_\(stamp).json")
        if let data = try? JSONSerialization.data(withJSONObject: ["hz": 25, "samples": samples]) {
            try? data.write(to: url)
            log("PPG window saved (\(samples.count) samples)")
        }
    }
}

// MARK: - CBCentralManagerDelegate (app owns CoreBluetooth)

extension QRingBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("bluetooth state \(central.state.rawValue)")
        onMain { $0.btPower = central.state == .poweredOn ? "powered on" : "state \(central.state.rawValue)" }
        // Adopt peripherals stashed by willRestoreState now that the stack is actually up.
        if central.state == .poweredOn, !restoredPending.isEmpty {
            let pending = restoredPending; restoredPending.removeAll()
            for p in pending {
                connecting = p
                if p.state == .connected {
                    log("adopting restored connection (\(p.name ?? "strap"))")
                    centralManager(central, didConnect: p)
                } else {
                    log("reconnecting restored strap (\(p.name ?? "strap"))")
                    central.connect(p, options: nil)
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Named devices only — hide the dozens of no-name BLE beacons. The ring advertises as "Y28C_…".
        let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = (peripheral.name ?? local), !name.isEmpty else { return }
        let id = peripheral.identifier.uuidString
        peripherals[id] = peripheral
        log("DISCOVERED '\(name)' rssi=\(RSSI.intValue)")
        onMain { $0.ingestDiscovered(id: id, name: name, rssi: RSSI.intValue) }
        // Auto-connect to the HUMANS ring (VY28C advertises as "Y28C_…"). Single-shot, strongest-signal.
        let upper = name.uppercased()
        // "HUMANS" included: the setUUID rename experiment may change the advertised name — never
        // lock ourselves out of auto-connect if it works.
        let isRing = upper.hasPrefix("Y28") || upper.hasPrefix("VY2") || upper.contains("28C") || upper.hasPrefix("HUMANS")
        if !autoConnecting, isRing, RSSI.intValue >= -95 {
            autoConnecting = true
            log("auto-connecting to ring \(name)")
            connect(id: id)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("didConnect — handing to QCSDKManager")
        QCSDKManager.shareInstance().remove(peripheral)
        QCSDKManager.shareInstance().add(peripheral) { [weak self] success in
            guard let self else { return }
            if success {
                let id = peripheral.identifier.uuidString
                let name = peripheral.name ?? "HUMANS Ring"
                UserDefaults.standard.set(id, forKey: "qringPeripheralId")   // remember for reinstall-proof reconnect
                self.ringDirect = RingDirect(peripheral: peripheral) { [weak self] in self?.log($0) }
                self.log("addPeripheral ready")
                self.onMain { $0.ingestReady(id: id, name: name) }
                self.cmdQueue.removeAll(); self.cmdRunning = false; self.syncing = false   // fresh serial queue + unstick the sync guard on connect
                QCSDKManager.shareInstance().currentBatteryInfo = { [weak self] battery, _ in
                    self?.onMain { $0.ingestDeviceInfo(battery: self?.batteryPct(battery) ?? battery, firmware: nil) }
                }
                // Live pedometer feed — fires as the ring counts steps. Tells us if it's counting at all.
                // ⚠︎ calories arrive in small-calories here too (the 39400-vs-39.4 bug lived in this push:
                // it overwrote the converted sync value on every step tick). Same ÷1000 rule as currentSport.
                QCSDKManager.shareInstance().currentStepInfo = { [weak self] step, calorie, distance in
                    let kcal = calorie > 2000 ? Double(calorie) / 1000.0 : Double(calorie)
                    self?.log("live steps=\(step) kcal=\(Int(kcal)) (raw \(calorie)) dist=\(distance)")
                    guard step > 0 else { return }
                    let k = self?.dayKey(daysAgo: 0) ?? ""
                    self?.agg(k) { $0.steps = step; $0.activeKcal = kcal }
                    self?.scheduleFlush()
                }
                // FIRST: set the ring clock. A new/uninitialized ring has no valid data timeline until this
                // is done, so every history read fails. (The official app does this on first setup.)
                self.enqueue { [weak self] done in
                    QCSDKCmdCreator.setTime(Date(), success: { features in
                        // Capability discovery (teardown §3): log the supported-feature flags ONCE so we
                        // stop probing commands this firmware doesn't implement (value "1" = supported).
                        let on = (features as? [String: Any] ?? [:])
                            .filter { "\($0.value)" == "1" }.keys.sorted().joined(separator: ",")
                        self?.log("ring time set ✓ features: \(on.isEmpty ? "(none reported)" : on)")
                        done()
                    }, failed: { self?.log("setTime failed"); done() })
                }
                // User profile — the step/calorie algorithm needs it; part of proper first-time init.
                self.enqueue { [weak self] done in
                    QCSDKCmdCreator.setTimeFormatTwentyfourHourFormat(true, metricSystem: true, gender: 0,
                        age: 30, height: 175, weight: 75, sbpBase: 0, dbpBase: 0, hrAlarmValue: 0,
                        success: { _, _, _, _, _, _, _, _, _ in self?.log("user profile set ✓"); done() },
                        fail: { self?.log("user profile failed"); done() })
                }
                self.enqueue { [weak self] done in
                    QCSDKCmdCreator.readBatterySuccess({ (battery: Int32, charging: Bool) in
                        let pct = self?.batteryPct(Int(battery)) ?? Int(battery)
                        self?.log("battery level=\(battery) → \(pct)% charging=\(charging)")
                        self?.onMain { $0.ingestDeviceInfo(battery: pct, firmware: nil) }
                        done()
                    }, failed: { self?.log("battery read failed"); done() })
                }
                // NOTE (rename experiment, 2026-10-24): setUUID("HUMANS")/getUUID both FAIL on the VY28C —
                // the firmware doesn't implement the custom-tag command, so the advertised BLE name
                // ("Y28C_7EB0") cannot be changed from the phone. Renaming = OEM firmware ask to Vivistar.
                // ★ Sampling-density experiment (WHOOP plan phase 3): read the scheduled-HR config, then
                // push the interval to the firmware's floor (denser passive HR → better zones/resting HR).
                // Battery impact is observed over the following days via the battery log lines.
                self.enqueue { [weak self] done in
                    QCSDKCmdCreator.getSchedualHeartRateInfo(success: { enable, interval, minInterval, minTip, maxTip in
                        self?.log("schedHR: on=\(enable) interval=\(interval)m floor=\(minInterval)m")
                        done()
                        let target = max(1, minInterval)
                        if !enable || interval != target {
                            self?.enqueue { d2 in
                                QCSDKCmdCreator.setSchedualHeartRateStatus(true, interval: target, success: { en, iv in
                                    self?.log("schedHR set → \(iv)m (on=\(en))"); d2()
                                }, fail: { self?.log("schedHR set ✗ (kept \(interval)m)"); d2() })
                            }
                        }
                    }, fail: { self?.log("schedHR info ✗"); done() })
                }
                self.enableMonitoring()   // the ring records nothing until these are on (official app does this at setup)
                self.syncHistory()
            } else {
                self.autoConnecting = false
                self.onMain { $0.ingestError("Failed to initialize the ring.") }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        autoConnecting = false
        onMain { $0.ingestError(error?.localizedDescription ?? "Failed to connect to the ring.") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        QCSDKManager.shareInstance().remove(peripheral)
        ringDirect = nil
        autoConnecting = false; connecting = nil
        onMain { $0.ingestDisconnected(error: error?.localizedDescription) }
        // Always-on (phase 2): unless the user asked to disconnect, immediately re-issue a pending
        // connect — it has no timeout and fires the moment the strap is back in range, including in
        // the background (state restoration relaunches us for the event).
        if !userRequestedDisconnect {
            log("auto-reconnect armed (\(peripheral.name ?? "strap"))")
            peripherals[peripheral.identifier.uuidString] = peripheral
            connecting = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Relaunched in the background for a strap event: re-adopt the restored peripherals so the
        // normal didConnect → syncHistory path (and its Firebase push) runs with the app closed.
        // ⚠️ Do NOT touch the peripherals here: willRestoreState arrives BEFORE poweredOn, and
        // QCSDKManager.add hangs silently in that window (the app sat frozen all night on this).
        // Stash them; centralManagerDidUpdateState adopts them once the stack is up.
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        log("willRestoreState — \(restored.count) peripheral(s), deferring to poweredOn")
        beginBackgroundWindow()
        restoredPending = restored
        for p in restored { peripherals[p.identifier.uuidString] = p }
    }
}
#endif
