# HUMANS — Wearable Device Research: Supplier Registry

Tracking OEM/ODM suppliers evaluated to pair a wearable with the HUMANS app. Goal: a band that
exposes **raw HRV (RRI)** and the core vitals over an **iOS-accessible SDK or BLE protocol**, so the
app's on-device recovery/strain/stress/sleep engine can run on it (no vendor cloud lock-in).

Last updated: 2026-09-16

---

## Status summary

| Supplier | Device(s) | Stage | Next action |
|---|---|---|---|
| **Shenzhen Vivistar** | VB9, VC2 | ⏳ Sample PI issued (3× each) | Confirm PI + send Dubai delivery address |
| ICTOPSUPPLY | H59 | ⬜ Not contacted | Backup — open SDK, MOQ 10 |
| Shenzhen Tianpengyu | ECG+HRV band | ⬜ Not contacted | Backup — open SDK, MOQ 1 |

Legend: ✅ done · ⏳ in progress · ⬜ not started

---

## 1. Shenzhen Vivistar Technology Co., Ltd  — PRIMARY

**Company:** 8 yrs on Alibaba · custom manufacturer · 4.5★ (5,749 reviews) · ≤2h response · 98.4% on-time · CE/ISO/FCC/RoHS · self-describes "12-years OEM/ODM Top-10 smartwatch manufacturer".
**Address:** 216 Baokang Road, Henggang, Longgang District, Shenzhen 518173, Guangdong, China
**Web:** www.vivistar.com.cn

**Contacts:**
| Name | Role | Email | Phone / WhatsApp |
|---|---|---|---|
| Cassidy Wong | Sales Manager (current) | cassidy@vivistar.com.cn | WhatsApp +86 133 1697 6287 · office +86-755-2513-1180 |
| Mila | Sales (first contact) | MILA@VIVISTAR.COM.CN | +86 177 0402 7394 |

### Current order (sample)
- **Proforma Invoice issued:** 3× VB9 + 3× VC2 (sample cost + shipping to Dubai, UAE).
- **Receiver:** Mike Muller, Dubai UAE — *delivery address to be provided.*
- **Blocking on us:** confirm the PI + send full delivery address.
- **Then supplier sends:** VB9 SDK documentation + VC2 BLE protocol document → integration can start.

### Devices under evaluation

#### VB9 — screenless band (preferred form factor)
| Attribute | Value |
|---|---|
| Form | Screenless, ultra-thin, ~21 g |
| MCU / BLE | Actions 3085S4 · BLE 5.3 · 16 MB storage |
| Sensors | BioZ/BIA + ECG (ADI/MAX **30001**), HR (HX3695H), temp (NST117) |
| Battery / water | 90 mAh · **3–5 days** · IP67 |
| Vendor app | iCarefit / Carefit |
| **Data access** | **iOS SDK, independent of the Carefit app** — SDK sends commands + syncs device data; integrate directly into the HUMANS iOS app (no Carefit install needed) |
| **Sampling intervals** | HR every **10 min**; BP / SpO2 / stress / body temp every **30 min**; **RRI default every 30 min → every 10 min at night with "scientific sleep mode" enabled** |
| HRV | **Included in the stress value** (not a standalone raw stream in the default SDK output) |
| Body composition | Wrist **BIA** — rough trend only (single-wrist path; far less accurate than an 8-electrode scale) |

#### VC2 — band with 0.96" TFT screen (best sensor set)
| Attribute | Value |
|---|---|
| Form | 0.96" TFT touch band (not screenless) |
| MCU / BLE | Nordic **nRF52840** · BT 5.2 |
| Sensors | ECG+PPG, HR (**25 Hz** continuous), **raw RRI**, SpO2 (red+IR), temp ±0.1 °C, respiratory rate, stress, fatigue, BP (labelled "not accurate"), REM sleep |
| Battery / water | 80 mAh · **7 days** · IP68 |
| Vendor app | IXFIT |
| **Data access** | **Fully documented BLE protocol — NO SDK.** Provides **original RRI**. Integrate directly over the Bluetooth protocol. |
| **SpO2 interval** | 15-min or 60-min depending on firmware — *supplier to verify the sample firmware's interval before shipment.* |
| Night-only config | Standard firmware = 24-hour period; **command-based night-only needs custom firmware.** Test standard first. |

### Open questions / to confirm
- [ ] VC2 sample firmware SpO2 interval (15 vs 60 min) — supplier verifying.
- [ ] VB9: can the SDK expose **raw RRI directly** (not only the derived stress value)? Night RRI @10 min is promising — confirm it's readable per-interval.
- [ ] Both: confirm the iOS SDK/BLE protocol needs **no vendor cloud** (fully local BLE).
- [ ] MOQ + unit price for a production run (samples ≈ VB9 $36, VC2 $30 from Alibaba listings).

### Fit assessment (for HUMANS)
- **VC2** = best data (Nordic chip, 25 Hz continuous HR, **raw RRI over open BLE**, temp ±0.1 °C, respiratory rate). Trade-off: has a screen; SpO2 not night-only without custom firmware.
- **VB9** = preferred *look* (screenless) and adds wrist BIA body-fat, but HRV is bundled into "stress" and RRI is 30-min by default (10-min only at night in sleep mode), 3–5 day battery.
- **Plan:** sample both; wear VB9 daily, keep VC2 as the raw-RRI reference; whichever streams clean beat-to-beat data into the app's `BodyMetrics` recovery/stress engine wins.

---

## 2. ICTOPSUPPLY Electronics Co., Ltd — BACKUP (not contacted)
- **Device:** H59 screenless band — HR, HRV, SpO2, sleep, **open SDK**, ODM/OEM.
- **Alibaba:** 9 yrs · 4.9★ · MOQ 10 · ~$10/unit.
- Worth a parallel quote for negotiation leverage and a second open-SDK option.

## 3. Shenzhen Tianpengyu Technology Co., Ltd — BACKUP (not contacted)
- **Device:** Screenless ECG+HRV band — HR, HRV, IP68, **open SDK, ODM**.
- **Alibaba:** 13 yrs · 4.6★ · **MOQ 1** · ~$27/unit.

---

## What we need from any supplier (checklist)
1. **Raw RRI (beat-to-beat intervals)** exposed via SDK or documented BLE — this is what lets HUMANS compute real RMSSD recovery.
2. **iOS-native access** (Swift/BLE) with **no dependency on the vendor's app or cloud**.
3. Core vitals: continuous HR, SpO2 (ideally overnight), skin temp, sleep stages.
4. SDK / BLE protocol **documentation** provided before/at sampling.
5. Reasonable battery (≥5–7 days) and screenless form factor preferred.
6. Sample availability (low MOQ) before any production commitment.
