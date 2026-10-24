# QCBandSDK (QRing iOS SDK V1.0.0, 2026-03-26) — full teardown

Source: `~/Downloads/QRing_iOS_SDK_V1.0.0_20260326.zip` → demo project `QCBandSDKDemo` + `QCBandSDK.framework` + EN/CN dev-guide PDFs + R02A ring firmware bins.
**The framework binary is byte-identical (MD5 `1aac5045…`) to the one already vendored at `Vendor/QCBandSDK/`** — everything here applies 1:1 to our integration; the new value is the demo code (esp. the Feb-2026 `PPGViewController`), the PDFs, and the firmware bins.

Companion doc: `docs/qring-integration.md` (our integration state). This doc = what the SDK itself can do.

## ★ 0. The VY28C is a Colmi R02 platform — open-source protocol available (2026-10-24)

The firmware bins in the SDK demo are `R02A_2.06.06_240302.bin` / `R02A_2.06.11_240327.bin` → this ring is the
**Colmi R02 platform** (Oudmon/Vivistar ODM). CONFIRMED: the Colmi R02 BLE service UUID
`6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E` + RX/TX `6E400002/3` **exactly match** the UUIDs in our QRing binary, and
the Colmi 16-byte packet protocol (byte[0]=opcode, bytes[1..14]=payload, byte[15]=checksum=sum%255, multi-packet
reassembly for big reads) matches our APK decode. **The Colmi R02 is one of the most reverse-engineered rings in
open source** — so we can implement the protocol OURSELVES (with our own retry/reassembly/timeout and the
timestamp-based opcode-21 today-HR read the iOS SDK never exposed), bypassing the flaky `QCBandSDK`.

Reference implementations (study, don't blindly copy — check licenses; protocol facts aren't copyrightable and
we already decoded the opcodes from the APK):
- **anikbharadwaj129/Colmi** — SwiftUI iOS app, sleep staging + HRV + temperature + readiness. Closest reference.
- **tahnok/colmi_r02_client** — canonical Python client + the best protocol documentation (HR/SpO2/sleep/stress/steps).
- **robinojw/openring** — vendor-neutral TypeScript parser core (+ React Native BLE adapter) — clean architecture.
- **wrcrooks/Colmi-Smart-Ring-Tools**, **ngeorge15/smart-ring** — more coverage + a full local-first stack.

This is the recommended fix for the retrieval-reliability problem (see §11). VY28C is a Vivistar variant (adds body
temp) so verify command-by-command, but core protocol + service UUID match.

## 1. Package contents

| Item | Notes |
|---|---|
| `QCBandSDK.framework` | arm64 device-only, ObjC, min iOS 9.0, same binary we vendor |
| `QCBandSDKDemo` Xcode project | CocoaPods (CocoaDebug only). Needs `-ObjC` linker flag + `EXCLUDED_ARCHS …simulator… = arm64 …` (matches our setup) |
| `PPGViewController.m` (new, 2026-02-12) | Raw-PPG capture harness — the recipe for true HRV (§6) |
| `Ring/R02A_2.06.06_240302.bin`, `R02A_2.06.11_240327.bin` | Ring firmware, flashable via `syncOtaBinData` (§9) |
| `iOS SDK SDK Development Guide.pdf` (+ Chinese) | Restates the headers; one extra note: battery may be reported 0–8 on some devices |

## 2. Architecture (4 public classes + 1 private)

| Class | Role |
|---|---|
| `QCSDKManager` (singleton) | Owns the connected peripheral (`addPeripheral:finished:` after YOU connect via CoreBluetooth), hosts **push-callback blocks** (§8), and the **measurement session engine** `startToMeasuringWithOperateType:timeout:measuringHandle:completedHandle:` / `stopToMeasuring…` / wear-calibration (120 s default). `debug` flag → `QCLogger` file log. |
| `QCSDKCmdCreator` (all class methods) | ~95 commands. **Strictly serial** — README: commands must be called in order; a command issued while another is in flight FAILS (this is why our `QRingBridge` serial queue exists). |
| `QCBleCentralManager` (PrivateHeaders) | Optional scan/connect helper (scan by service UUIDs, reconnect-without-timeout, `connectDeviceName:serviceUUIDs:…`). The demo instead uses its own `QCCentralManager` wrapper over raw CoreBluetooth — so do we. |
| `OdmBandNotifyCenter` | NSNotification firehose (§8). |
| `QCDFU_Utils` | Feature-flag constants (§3), DFU/protocol opcodes, shared enums. |

Connection flow (demo-canonical): scan `[QCBANDSDKSERVERUUID1, QCBANDSDKSERVERUUID2]` → `connectPeripheral` → on `didConnect` → `QCSDKManager.addPeripheral(_:finished:)` → **`setTime` first** (it returns the capability dictionary) → everything else. Reconnect: persist `peripheral.identifier`, use `retrieveConnectedPeripheralsWithServices` (demo does exactly what our bridge does). Candidate vendor service UUIDs in the binary: `6e40fff0-b5a3-f393-e0a9-e50e24dcca9e` (+ `6e400002/3` UART-style chars), `de5bf728/9-d711-4e47-af26-65e3012a5dc7`, `FEE7`, `FDD3`.

## 3. Capability discovery — `setTime` featureList

`+setTime:success:` returns `NSDictionary *featureList`; keys are `QCBandFeature*` constants (~50 in `QCDFU_Utils.h`), value `@"1"` = supported. Ring-relevant flags: `…BloodOxygen, …BloodPressure, …BloodGlucose, …Stress, …HRV, …HRVInterval` (HRV interval editable), `…Temperature, …TemperatureInterval`, `…ManualHeartRate, …OneKeyMeasure, …AppManual, …WearCalibration, …SedentaryReminder, …FlipWrist` (L/R hand), `…TouchControl / …GestureControl*` (music/video/ebook/photo/call/game/HR-measure), `…TouchControlOfScreenDevice`, `…LowPower, …MSLPraise, …Menstr, …NewSleepProtocol, …Drowsiness`. **We should log this dict once on connect and gate features off it instead of trial-and-error.**

## 4. Historical data retrieval (the sync surface)

Day indexing everywhere: `0=today, 1=yesterday…` (sport history max 29).

| Data | Method(s) | Returns / granularity |
|---|---|---|
| Steps/today summary | `getCurrentSportSucess:` ✅(works on VY28C) | `QCSportModel` {totalStepCount, runStepCount, **calories (unit: small-cal 卡)**, distance m, activeTime min} |
| Steps/day summary | `getOneDaySportBy:` (deprecated, device saves every 15 min) ❌on VY28C | one `QCSportModel` |
| Steps/intraday detail | `getSportDetailDataByDay:` (+ minuteInterval/begin/endIndex variant) ❌on VY28C | ≤96 × 15-min `QCSportModel` slices |
| Sleep v1 | `getSleepDetailDataByDay:` / `getFulldaySleepDetailDataByDay:` (**sleeps + naps**) / `get(Fullday)SleepDetailDataFromDay:` (multi-day dict) | `QCSleepModel` segments {type: none/sober/light/deep/**REM**/unworn, happenDate, endTime, total min} + helpers `sleepDuration:`/`fallAsleepDuration:` |
| Sleep v2 | `getSleepDetailDataV2ByDay:` (gated by `QCBandFeatureNewSleepProtocol`; `QCSleepProcotolVersion`) | dict date→segments |
| Scheduled HR | `getSchedualHeartRateDataWithDayIndexs:` ✅(our HR range 54–109) or `…WithDates:` | `QCSchedualHeartRateModel` {date, heartRates[], **secondInterval**} |
| Manual HR | `getManualHeartRateDataByDayIndex:` | `QCManualHeartRateModel` {heartRates[], hrTimes[] (minute-of-day)} |
| 1-min HR | `getOneMinuHeartRateDataWithIntervalByDayIndex:` | finer HR array (worth trying for better envelope) |
| HRV history | `getSchedualHRVDataWithDates:` ✅(our HRV 65) — **ring-only** | `QCHRVModel` {date, hrv[], secondInterval} |
| Stress history | `getSchedualStressDataWithDates:` ✅(our stress 25) — **ring-only** | `QCStressModel` {date, stresses[], secondInterval} |
| SpO₂ | `getBloodOxygenDataByDayIndex:` ✅ · manual: `getManualBloodOxygenDataByDayIndex:` · interval variant: `getBloodOxygenDataWithIntervalByDayIndex:` (returns count too) | `QCBloodOxygenModel` {soa2, min/max, sourceType 0=sched/1=manual} |
| Temperature | `getSchedualTemperatureDataByDayIndex:` / `getManualTemperatureDataByDayIndex:` / `getTemperatureDataWithIntervalByDayIndex:` (returns interval) — **all 3 empty on VY28C (ring stores no temp history — confirmed limitation)** | `QCTemperatureModel` {time, temperature, type} |
| Blood pressure | sched: `getSchedualBPHistoryData(WithUserAge:)` · manual: `getManualBloodPressureDataWithLastUnixSeconds:` | `QCBloodPressureModel` {sbp, dbp, type, date} + calibration helpers |
| Blood glucose | `getBloodGlucoseDataByDayIndex:` (0–6) | `QCBloodGlucoseModel` {glu, min/max, continuous/random, before/after-meal} |
| Workouts legacy | `getExerciseDataWithLastUnixSeconds:` | `QCExerciseModel` {run/bike/weights/walk, steps, m, cal, HR every 2 min} |
| Workouts Sport+ V2 | `getSportPlusSummaryFromTimestamp:` → `getSportPlusDetailsWithSummary:` · or `getSportRecordsFromLastTimeStamp:` | `OdmGeneralExerciseSummaryModel` {**238 sport types**, duration, distance, calorie, avg/min/max HR, hrs[], sampleRateSeconds, steps…} + `OdmGeneralExerciseDetailModel` {hrs[], speeds[], gpsLocations[]} |
| Sedentary / wear timeline | `getSedentaryReminderFromDay:` — **ring-only** | `QCSedentaryModel` {date→segments, type 0=static/1=sedentary-trigger/2=moving, duration min}. Demo log shows it's effectively an **all-day wear/activity timeline** — usable as off-wrist detection |
| Prayer counts | `getPraiseDataByDayIndexs:` / `clearPraiseData` | `QCMslPrayerModel` |

## 5. Live/on-demand measurement engine (`QCSDKManager`)

`startToMeasuringWithOperateType:timeout:measuringHandle:completedHandle:` with `QCMeasuringType`:
`heartRate, bloodPressue, bloodOxygen, oneKeyMeasure, stress, bloodGlucose, HRV, bodyTemperature, threeValueBodyTemperature, oneKeyMeasureHeartRate, heartRateRaw, bloodOxygenRaw`.
Errors: −1 start-cmd failed, −2 end-cmd failed, **−3 not worn properly, −4 uncalibrated** (→ run wear calibration §7).

- **One-key HR measure** (`oneKeyMeasureHeartRate`) streams `QCRealOneKeyMeasureHeartRateModel` — the richest single object: {heartRateValue, heartRateHRV ms, stress 0-100, **rri ms (updates every second)**, **temp (0.1 °C units)**, sbp, dbp}. Note: temp also rides along here — alternative to our separate temp measure chain.
- Legacy start/end pairs also exist (`beginRealTimeHeartRate…`, `startBloodPressureMeasuring…`, `startBloodOxygenMeasuring…` etc.) plus `realTimeHeartRateWithCmd:` (start/end/**hold** keep-alive — demo re-sends hold every ≤20 s).
- One-key-examination switch: `openOneKeyExaminationSwitchWithSuccess:` / `close…`.

## 6. RAW PPG (the true-HRV unlock) — from the new `PPGViewController`

`QCMeasuringTypeHeartRateRaw` (and `bloodOxygenRaw`): `startToMeasuring… timeout:100` → `completedHandle` returns an **NSArray of `QCBloodGlucoseHeartRateRawModel`**:
{ppgCount (≤255 rolling), value, greenLightPpgL/H, xAxisL/H, yAxisL/H, zAxisL/H} — **25 Hz** (demo stamps each sample `(i+1)*0.04 s`; a 100 s window ≈ 2500 samples). 16-bit values = `H<<8 | L`.
Demo pattern: one 100 s raw capture every **550 s**, serial dispatch-timer with monotonic-clock drift correction, screen kept awake, JSON-appended to `Documents/PPG/yyyyMM/PPG_data_*.json` with crash-recovery truncation. Stop with `stopToMeasuringWithOperateType:`.
Matching live notifications: `OdmBandRealTimeHeartRateRaw` / `OdmBandRealTimeBloodGlucoseRaw` with keys `OdmPpgCountKey, OdmValueKey, OdmRedLightPpg(L/H)Key, OdmInfraredPpg(L/H)Key, OdmX/Y/ZAxis(L/H)Key`.
→ This is exactly the input for our deferred raw-PPG→rMSSD pipeline: green PPG + accel for motion-artifact rejection, 25 Hz is enough for beat detection (interpolate for RR precision).

## 7. Config / control commands (ring-relevant)

- **Scheduled-monitoring switches**: HR `setSchedualHeartRateStatus:` (+ `interval:` + `maxHrTip/minHrTip` alarm variant; read with `getSchedualHeartRateInfoWithSuccess:` → enable, interval, minInterval, min/max tips) · SpO₂ `setSchedualBOInfoOn:(timeInterval:)` · HRV `setSchedualHRVStatus:` · Stress `setSchedualStressStatus:` · BP `setSchedualBPInfoOn:begin:end:minuteInterval:` · generic `setSchedualInfoType:` for **bloodGlucose / bloodLipids / uricAcid / bodyTemperator** (+calibrate, +interval).
- **Wear calibration**: `wearCalibration:` type 1=start(reset ring data!)/2=end/3=single/4=power-consumption-mode/5=stop-power/6=app-start; or managed `startToWearCalibrationWithTimeout:` (120 s) + `QCBandWearCalibrationUpdateNotification(01)`.
- **User/profile**: `setTimeFormatTwentyfourHourFormat:metricSystem:gender:age:height:weight:sbpBase:dbpBase:hrAlarmValue:` + getter; goals `set/getStepTarget…` {steps, cal, distance, sportMin, sleepMin}.
- **Ring wearing hand**: `set/getFlipWristInfo` (`QCFlipWristInfoModel` {enable, 1=L/2=R, brightness…}) — ring-only variant; watches use `setFlipWristOn:flipType:`.
- **Touch/gesture control**: `set/getTouchControl…` and `set/getGestureControl…` (`QCTouchGestureControlType`: off/music/video/MSL-praise/ebook/photo/call/game/**HR-measure**/touchEvent; strength 1-10; sleep duration). Screen-device variant for RT11-class rings.
- **Device ops**: `readBatterySuccess:(int,charging)`, `lookupDeviceSuccess:` (buzz the ring), `shutDownSuccess:`, `resetBandHardlySuccess:` (reboot), `resetBandToFacotrySuccess:` (wipe), `setLowPowerWith:`, `getDeviceMacAddress`, `getDeviceSoftAndHardVersion`, `set/getUUID` (≤10 chars custom tag), `endBroadcast:`, `setANCSFlag`, DND, brightness 1-10, screen-on seconds 4-10 (`QCDimingTimeInfo` incl. always-on fields), sedentary-reminder set (`setBeginTime:endTime:repeatModel:timeInterval:`), drink-water reminders (indexed alarms), alarms (`QCAlarmModel`), menstrual cycle, weather push, notification filters (15 app types), contacts, camera remote (switch/hold/stop photo UI).
- Watch-only (ignore for ring): dial market/sync/delete/params, wallpaper `syncImage:`, music/ebook file ops, contacts cards, homepage styling.

## 8. Push channels (device → app, unsolicited)

**`QCSDKManager` blocks**: `findPhone(1/2)`, `realTimeHeartRate(hr)`, `hrMeasuring/bpMeasuring/boMeasuring/measuringFail` (watch-initiated), **`currentStepInfo(step,cal,distance)`** (live step push — some rings), **`currentSportInfo(QCSportInfoModel{type,state,duration,hr,step,cal,distance})`** (after app starts a sport), **`currentBatteryInfo(battery,charging)`**, `watchDataUpdateReport(QCDeviceDataUpdateReport,value)` (typed change feed: HR, BP, BO, temp, sleep, sportRecord, power, **HRV 0x2b, stress 0x2c**, touchSleep 0x2a…), `flipWristInfo`, `gestureAndTouchInfo`, `touchSleepInfo`, `dailIndex`, `lowerPower`, camera blocks.
**`OdmBandNotifyCenter` NSNotifications**: real-time HR/SBP-DBP/stress/HRV/glucose/**body-temp** (`OdmBandRealTimeBodyTemperature` — our temp fallback if the operate-types fail)/three-value temp/SpO₂, one-key-measure HR, raw PPG (§6), ECG set (§10), find-phone, battery, sport/activity state, wear calibration, AGPS request, location request. Payload keys incl. `OdmHeartRateValueKey, OdmHeartRateHRVKey, OdmStressKey, OdmRriKey, OdmTempKey, OdmBloodPressureSbp/DbpKey`.

## 9. OTA / DFU

`syncOtaBinData:start:percentage:success:failed:` flashes a `.bin` (nRF-style DFU; service/char UUID constants exported; `ODM_DFU_Operation` opcode map in `QCDFU_Utils.h` doubles as the wire-protocol reference — sleep 0x27, manual HR 0x28, sport+ 0x41-0x46, ECG 0x70-0x73, 1-min HR 0x75, temp-interval 0x74…). Two **R02A** firmware bins ship in the demo. ⚠️ Only flash firmware matching the device model — VY28C ≠ R02A; don't flash these.

## 10. Hidden API (binary-only, NOT in public headers)

`OdmBandCmdCreator` (the internal command layer behind `QCSDKCmdCreator`) exports a **complete ECG stack**: `getECGListFinished:`, `getECGDataWithTimestamp:finished:` (with decompression + HR-data decompress), `startRealTimeECGExamine(With:)…`, `stopRealTimeECGExamineWithType:…`, `open/closeECGRecord…`, plus notifications `OdmBandRealTimeECG/PPG`, `OdmBandECGPPGLeadStateNotication`, ECG timer-tick/terminated. Callable via ObjC runtime if a future HUMANS device has ECG electrodes; almost certainly unsupported by VY28C (optical only). Also internal: `OdmBandHeartRateCalibration`, `OdmBandOpen/CloseHealthDetectionSwitch`, AGPS.

## 10b. Official QRing Android APK teardown (v1.0.0.35) — protocol ground-truth

Decompiled the official app (`QRing_1.0.0.35_APKPure.apk`, pkg `com.qcwireless.qcwatch`, verCode 36) with jadx. Same ODM platform as iOS: BLE layer `com.oudmon.ble.base.*`, entities/responses under `communication/{rsp,entity,sport,dfu_temperature}`. This is the authoritative answer to every unit question.

| Field | Wire format (parser) | Display conversion | Our handling | Verdict |
|---|---|---|---|---|
| **Steps** | `TodaySportDataRsp`: 3-byte int, bytes[0..2] | shown raw | raw | ✅ correct |
| **Calories** | 3-byte int, bytes[6..8] — **milli-kcal** | **`/ 1000`** at EVERY UI site (`getCalorie()/1000.0f`, sport detail, week/month, Google-Fit upload) | `÷1000` | ✅ **confirmed** — 69416 → 69 kcal is the TRUE active number |
| **Distance** | 3-byte int, bytes[9..11] — meters | `/ 1000` → km | — | ✅ (we keep meters) |
| **HRV** | int ms | shown raw (`String.valueOf(getValue())`, no divisor) | raw ms | ✅ correct |
| **Temperature** | `TemperatureHandle`: **`(byte / 10.0f) + 32.0f`** (offset from 32 °C, 0.1 °C units) via a **file-transfer series protocol** (`ACTION_SERIES=37`, `ACTION_ONCE=38`, compressed) | shown as computed °C | our bridge auto-scales `>45 ⇒ /10`, **no +32 offset** | ⚠️ **our temp math is wrong** (see below) |
| **Today total source** | `syncTodayStepTotal()` → `TodaySportDataRsp` | — | our `getCurrentSportSucess` reads the same total | ✅ correct source |

**Two things the APK revealed that change our integration:**

1. **Temperature parsing is wrong AND read via the wrong channel.** The device sends temperature as a single byte = `(°C − 32) × 10`, so true °C = `byte/10 + 32`. Our bridge does `while t>45 { t/=10 }` with no +32 offset, which mis-scales any raw reading. Worse, the official app reads the temperature *series* through the **`dfu_temperature` file-transfer protocol** (opcodes 37/38, gzip-compressed payload) — NOT the simple `getSchedualTemperatureData` command we call. That's why our history reads come back empty even though the app's `syncTemperatureAuto()` works. If we want temp history we must drive the file-series path; our on-demand `startToMeasuring(.bodyTemperature)` value also needs the `+32` offset applied (verify against a live reading before trusting it).

2. **The official app's health sync is a fixed ordered pipeline** (`HealthyViewModel`): `syncTodayStepTotal → syncTodaySportPlusDetail → syncTodayHeart… → syncTodayHrv → syncTemperatureAuto → syncHistory*`. Each is a discrete serial command — exactly the serial-queue discipline our bridge already uses. It also distinguishes **today** (`syncToday*`) from **history** (`syncHistory*`) calls, and has explicit `*Single` on-demand variants. Our 0/1-day sync matches the "today + yesterday" shape; for a fuller backfill we'd mirror its `syncHistory*` calls.

**Settled, no change needed:** calories ÷1000 (our fix is right — 69 kcal active is real), steps raw, HRV raw ms, SpO₂/stress/HR all match. The `libDspConfig.so` native lib is the PPG→HR/HRV DSP (closed-source; same algorithm family our raw-PPG pipeline would reimplement).

## 11. Implications for our open VY28C issues

1. **kcal ×1000**: `QCSportModel.calories` and the goal API are documented in **small calories (卡/cal)**, not kcal → 39400 cal = 39.4 kcal. Our `/1000` divisor is right; the lingering 39400 display must be the `setHealth` overwrite / sync-guard path, not the unit math.
2. **Temperature**: history confirmed absent by design on this ring. Three more paths to try beyond our two operate-types: (a) the **one-key HR measure** result (`temp` field, 0.1 °C), (b) `OdmBandRealTimeBodyTemperature` / three-value notifications during measurement, (c) `setSchedualInfoType(.bodyTemperator, interval:)` then `getTemperatureDataWithIntervalByDayIndex` (long shot — flag may be off).
3. **True HRV**: full raw-PPG recipe now documented (§6) — 25 Hz green PPG + accel, 100 s windows.
4. **Capability gating**: log the `setTime` featureList dict once; stop probing unsupported commands.
5. **Wear detection**: `getSedentaryReminderFromDay` gives an all-day worn/active timeline — useful to invalidate garbage samples.
6. **Live steps**: subscribe `currentStepInfo` instead of re-polling `getCurrentSport`.
7. **Workout sessions**: `operateSportModeWithType:state:` + `currentSportInfo` push + `getSportRecordsFromLastTimeStamp:` gives us ring-initiated workout tracking (238 types) feeding Strain.
