# QRing (QCBandSDK) integration — HUMANS

Knowledge base for integrating the **QRing smart ring** (Vivistar QRing platform — VY26 / VY28C / VY25S / VY26S)
into HUMANS. Built from `QCBandSDK` iOS SDK v1.0.0 (2026-03-26), the English dev guide, and the framework
headers. This is the **stronger long-term wearable for HUMANS than the VB9** (raw RRI + raw PPG + ECG, no
cloud, swim-safe 5 ATM).

SDK source: `~/Downloads/QRingSDK/QCBandSDKDemo/` (framework at `QCBandSDK.framework`, English guide
`iOS SDK SDK Development Guide.pdf`, demo app `QCBandSDKDemo`).

## Why QRing beats the VB9 for HUMANS

| HUMANS need | QRing (QCBandSDK) | VB9 (BLEMidAutumn) |
|---|---|---|
| **Raw RRI** (per-second RR intervals → gold-standard HRV) | ✅ `rri` updated every second | ❌ bundled in "stress"; needed custom firmware |
| Raw PPG (red/IR light + 3-axis ACC) | ✅ `OdmBandRealTimeHeartRateRaw` | ⚠️ not mapped |
| Real-time ECG + PPG + lead state | ✅ notifications | ⚠️ ECG only, pull unconfirmed |
| SpO₂ / BP / stress / temp / HRV | ✅ all, realtime + scheduled history | ✅ |
| Blood glucose (non-invasive est.) | ✅ `QCBloodGlucoseModel` | ❌ |
| BIA / body composition | ❌ (not in SDK) | ❌ (firmware doesn't expose) |
| **Cloud dependency** | ❌ **none — local BLE framework** | ❌ none |
| External link deps | **none — self-contained static framework** | Protobuf (hand-built lib) |
| Water | **5 ATM — swim-safe** | IP67 — not swim-safe |

## Framework facts (integration constraints)

- `QCBandSDK.framework` is a **static** framework (`Archive`), **arm64 device-only** (no simulator slice),
  **module-mapped** (umbrella `QCBandSDK.h`) → Swift-importable via `import QCBandSDK`.
- **Fully self-contained** — `nm` shows zero external OBJC class deps (no Protobuf, no third-party). Only the
  demo uses a `CocoaDebug` pod (debug console, not needed).
- Setup (per dev guide §1): add framework, **`-ObjC`** linker flag (categories), exclude arm64 for simulator,
  Bluetooth usage strings. → Same **device-only `[sdk=iphoneos*]`** gating we used for the VB9; sim builds
  exclude it via `#if canImport(QCBandSDK)`.
- iOS 9.0+.

## Architecture (how it plugs into HUMANS)

Unlike the VB9 (where `BLEAutumn` owned scanning), **the APP drives CoreBluetooth**, then hands the connected
peripheral to the SDK:

```
CBCentralManager (app-owned)                QCSDKManager.shareInstance       QCSDKCmdCreator (commands)
  scanForPeripherals(services: [UUID1,UUID2])   addPeripheral:finished:          OdmBandNotifyCenter (realtime
  didDiscover → filter by name                  removePeripheral:                  NSNotifications)
  connectPeripheral                             block callbacks (hr/bp/bo/…)
  didConnect → addPeripheral:finished:(ready) ──────────────┘
```

- **Service UUIDs:** `QCBANDSDKSERVERUUID1`, `QCBANDSDKSERVERUUID2` (scan filter). Secondary-filter by name.
- **Connect handoff:** `didConnectPeripheral` → `[[QCSDKManager shareInstance] addPeripheral:peripheral finished:^(BOOL ready){…}]`.
  The `finished:` block is the **device-ready signal** — commands only after it fires.
- **Disconnect:** `didDisconnectPeripheral` → `removePeripheral:`.
- **Commands:** `QCSDKCmdCreator` class methods with block callbacks — **call sequentially** (concurrent
  commands fail; the later one is dropped).
- **Real-time data:** `[OdmBandNotifyCenter registerNotify]`, then observe `OdmBand*` notifications and read
  `userInfo` keys.

## Measurements (on-demand)

`QCSDKManager startToMeasuringWithOperateType:(QCMeasuringType)type measuringHandle:^(id live) completedHandle:^(BOOL ok, id result, NSError *err)`.
Stop via `stopToMeasuringWithOperateType:`. Error codes: -1 start-send fail, -2 end-send fail, **-3 not worn**, -4 uncalibrated.

`QCMeasuringType`: HeartRate(0), BloodPressure, BloodOxygen, OneKeyMeasure, Stress, BloodGlucose, HRV,
BodyTemperature, ThreeValueBodyTemperature, **OneKeyMeasureHeartRate**, **HeartRateRaw (raw PPG)**, BloodOxygenRaw.

Result shapes: HR → `NSNumber`; BP → `@{"sbp":…, "dbp":…}`; SpO₂ → `NSNumber`.

### The key one: OneKeyMeasureHeartRate → RRI
`QCRealOneKeyMeasureHeartRateModel` carries **everything in one measurement**: `heartRateValue`, `heartRateHRV`
(ms), `stress` (0–100), **`rri`** (ms, per-second), `temp` (0.1°C), `bloodPressureSbp/Dbp`. Arrives via the
`OdmBandRealOneKeyMeasureHeartRate` notification. **This is the raw-RRI source HUMANS wanted.**

## Real-time notifications (`OdmBandNotifyCenter`)

Register once: `[OdmBandNotifyCenter registerNotify]`. Observe:
- `OdmBandRealTimeHeartRate` / `QCBandRealTimeHeartRateNotification` — live HR
- `OdmBandRealTimeHRV` (key `OdmHeartRateHRVKey`), `OdmBandRealTimeStress` (`OdmStressKey`)
- `OdmBandRealTimeSBP_DBP` (`OdmBloodPressureSbpKey`/`OdmBloodPressureDbpKey`), `OdmBandRealTimeSO2`
- `OdmBandRealTimeBodyTemperature` (`OdmTempKey`), `OdmBandRealTimeBloodGlucose`
- `OdmBandRealOneKeyMeasureHeartRate` → `QCRealOneKeyMeasureHeartRateModel` (**RRI**, key `OdmRriKey`)
- `OdmBandRealTimeHeartRateRaw` → **raw PPG**: `OdmPpgCountKey`, `OdmRedLightPpgL/HKey`, `OdmInfraredPpgL/HKey`,
  `OdmXAxisL/HKey`, `OdmYAxisL/HKey`, `OdmZAxisL/HKey`
- `OdmBandRealTimeECGNotification` / `OdmBandRealTimePPGNotification` / `OdmBandECGPPGLeadStateNotication`
- `QCBandBatteryNotification`, `QCBandDataUpdateReportNotification`

## History sync (scheduled data → dashboard)

`QCSDKCmdCreator` class methods, block callbacks returning arrays of typed models:
- Sleep: `getSleepDetailDataFromDay:sleepDatas:fail:` → `QCSleepModel`
- **HRV** (ring only): `getSchedualHRVDataWithDates:finished:`
- **Stress** (ring only): `getSchedualStressDataWithDates:finished:`
- **SpO₂**: `getBloodOxygenDataWithIntervalByDayIndex:finished:` + scheduled `setSchedualBOInfoOn:timeInterval:`
- Timed HR, timed/manual BP, timed/manual body temp, steps/exercise (Sport+ V2), targets, sedentary.
- Enable scheduled monitoring: `setSchedualHRVStatus:`, `setSchedualStressStatus:`, `setSchedualBOInfoOn:…`,
  `setSchedualInfoType:featureOn:…` — so the ring **auto-collects** and we sync (matches HUMANS' automated goal).

## Wear calibration
`startToWearCalibrationWithCompletedHandle:` (120 s) / `wearCalibration:` (1 start/reset, 2 end, 3 single, …).
Measurements can return **-4 uncalibrated** — calibrate on first setup.

## Integration plan (reuse the VB9 architecture)

The VB9 scaffolding is reusable: a new **QRing transport** feeds the SAME `Store.applyVB9History` /
`BodyMetrics` pipeline (rename to a neutral `applyBandHistory` later). Plan:

1. Vendor `QCBandSDK.framework` → `Vendor/QCBandSDK/` (git-ignored), link **device-only** via
   `FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]` + `OTHER_LDFLAGS[sdk=iphoneos*] = -ObjC -framework QCBandSDK`.
   **No Protobuf step** — self-contained.
2. `Core/Wearable/QRingBridge.swift` (`#if canImport(QCBandSDK)`, NSObject): owns `CBCentralManager`
   (scan UUIDs + name filter → connect → `addPeripheral:finished:`), registers `OdmBandNotifyCenter`, maps
   notifications + measurement callbacks → main-actor ingestion.
3. `QRingManager` (@Observable @MainActor) mirroring `VB9Manager`: auto-connect, state, live values, feeds
   the Store. Prefer RRI-derived HRV over the bundled value.
4. On ready: enable scheduled HRV/stress/SpO₂, pull history (sleep/HRV/stress/SpO₂/HR/BP/temp/steps), then
   auto-sync. One-key-measure for an on-demand full reading (HR+HRV+RRI+stress+temp+BP).
5. Band-picker on the Body card (VB9 vs QRing) — or auto-detect by advertised name.

## Open questions / caveats
- Confirm **VY28C advertised name** + which `QCBANDSDKSERVERUUID` values the ring uses (read the constants at runtime).
- **Raw-RRI → HRV**: compute RMSSD/SDNN ourselves from the per-second RRI stream for best quality (don't rely
  on the bundled HRV only).
- Runtime **0-egress check** (like the VB9) to confirm no cloud calls, for the appsec file.
- Dev guide + headers are in the SDK zip; keep for reference. BIA/body-comp is NOT available (same as VB9).
