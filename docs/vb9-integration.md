# VB9 wristband integration (HUMANS)

Status: **scaffolding landed, hardware pending.** Compiles + runs on the simulator today; the real BLE
path activates when the band + vendor framework are in hand. Branch `vb9-integration`.

## What the VB9 is

IWOWN / Zeroner **"Mid-Autumn" protobuf BLE** platform. iOS SDK = `BLEMidAutumn.framework` v6.6.6
(Obj-C, module-mapped → importable from Swift). Data is BLE-only; ECG/AF AI analysis runs **on-device**
(no vendor cloud). Full capability decode: `docs/vb9-coverage-expansion.md` (companion) / supplier SDK in
`~/Downloads/VB9SDK`.

## Architecture (how it plugs into HUMANS)

The band is a **direct-BLE data source** that feeds the **same `AppData` + BodyMetrics engine** as Apple
Health and the Whoop/Oura cloud path (`applyWearable`). No parallel metrics stack.

```
VB9Manager (BLE transport)  ──►  Store.applyVB9History / applyVB9OneKey / recordECG  ──►  AppData
  (Core/Wearable/VB9Manager.swift)     (Core/Wearable/VB9Store.swift)                      │
  real path  #if canImport(BLEMidAutumn)  ← device only                                    ▼
  sim stub   #else  (-vb9Sim 1 demo data)                                         BodyMetrics / Body tab
```

Value types + SDK-JSON decoders: `Core/Wearable/VB9Kit.swift`.

### The device-only constraint (load-bearing)

The framework is **arm64 device-only — no simulator slice** and is a **commercial binary in a public
repo**. Therefore:

- It is **git-ignored** and dropped locally at `Vendor/BLEMidAutumn/` (see that README), linked to the
  **device build only**.
- All framework-touching code sits behind `#if canImport(BLEMidAutumn)`. Simulator builds exclude it, so
  the app keeps compiling and the whole sim-harness (screenshots) still works.
- `VB9Manager.isAvailable` reports which path is live. `-vb9Sim 1` injects a demo band for UI work.

## Data → model mapping

| VB9 signal | Source call | AppData field |
|---|---|---|
| Resting HR | history `SD_TYPE_HEART_RATE` / one-key | `RecoveryDay.rhr`, `HealthDay.restingHR` |
| All-day HR floor/ceiling | auto-HR history | `HealthDay.hrMinDay` / `hrMaxDay` *(new)* |
| Live HR | `startReadRealTimeData[HR]` | `VB9Manager.liveHR` (transient) |
| HRV (SDNN) | history / ECG-AI | `RecoveryDay.hrv` |
| Sleep (stages) | `SD_TYPE_SLEEP` | `RecoveryDay.sleepH/deepH/remH` |
| SpO₂ | `SD_TYPE_Spo2` / one-key | `RecoveryDay.spo2` |
| Respiration | one-key | `RecoveryDay.resp` |
| Skin temp | `SD_TYPE_Temperature` / one-key | `RecoveryDay.tempC` |
| Blood pressure | one-key / `SD_TYPE_BLOOD_PRESSURE` | `HealthDay.bpSystolic/bpDiastolic` |
| Stress index | one-key / ECG-AI | `RecoveryDay.stressMeasured` *(new)* |
| Fatigue index | one-key / ECG-AI | `RecoveryDay.fatigue` *(new)* |
| Steps / active kcal | `SD_TYPE_SPORT/STEP` | `HealthDay.steps/activeKcal` |
| Workouts | `SD_TYPE_SPORT` | `AppData.workouts` (id `vb9-…`) |
| ECG + rhythm/AF/heart-age/QTc/ANS | `testECGModel` → `calculateEcgAiJson` (+ AF-AI) | `AppData.ecg[date]: [ECGResult]` *(new)* |
| Body composition (BIA, segmental) | `measureBia` | existing `HealthDay.bodyFatPct/leanMassKg` + `BodyCompEntry` |
| Device/battery | `readDeviceInfo` / `readDeviceBattery` | `AppData.band: BandInfo` *(new)* |

## Body screen additions (shipped in this scaffolding)

- **HUMANS Band card** — status dot, name, battery, live-HR readout, and Health-check / ECG / Sync
  actions (Connect/scan when unpaired). Shown once paired or on an SDK-equipped device (`showBandCard`).
- **Heart Rhythm (ECG) card** — rhythm label + AF badge, 0–99 score, heart age, QTc, PR, HRV (SDNN/rMSSD),
  autonomic balance. Wellness-framed disclaimer. Appears once an ECG exists.
- **Health Monitor rows** — Blood pressure, **HR range (all day)**, **Stress (band)** added alongside the
  existing wrist-temp / SpO₂ / HRR / glucose rows.

Verify in sim: `-vb9Sim 1 -startTab 5` (band card), `-bodyScroll stress` (ECG card), `-bodyScroll week`
(monitor rows).

## Hardware-arrival checklist

1. Drop `BLEMidAutumn.framework` into `Vendor/BLEMidAutumn/` and add Protobuf / iOSDFULibrary /
   ZIPFoundation / Masonry / IVBaseKit (device-only link). See `Vendor/BLEMidAutumn/README.md`.
2. Finish the `bridge*` methods in `VB9Manager.swift` against the physical band (scan→bind→onBluetoothInit,
   real-time HR, `calculateEcgAiJson` on ECG finish, `getDataStoreDate` + `startSpecialData` per `SD_TYPE`).
3. Confirm the auto-HR logging interval (the key open question — determines all-day HR density).
4. BLE background-mode review for App Review (`bluetooth-central` justification).
5. **Regulatory**: sign off how ECG rhythm / AF / BP / heart-age / QTc surface (wellness line — same as
   Physical Age). Keep the disclaimer.

## Open / deferred

- Raw PPG/ACC/GYRO/MAG streams, GNSS track, and the TCM/"Five-Qi" data are **not** mapped (not needed).
- Continuous-HR as a per-minute series is summarized to a daily min/max envelope for now; a full series
  store can come later if a feature needs it.
