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
  ⚠️ **We requested 1× each** — PI came back as 3× each. Correct on the PI unless 3 of each is wanted.
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

### Confirmations RESOLVED (supplier reply, 2026-09-16)
- [x] **VC2 integration = documented BLE protocol, NO SDK** (spec sheet's "SDK/API" line was wrong). Provides **raw RRI**. Acceptable.
- [x] **VB9 iOS SDK is independent of Carefit** — reads device data directly, no vendor app install needed.
- [x] **Docs on order confirmation** — VB9 SDK docs + VC2 BLE protocol doc will be sent once sample order confirmed.

### Still open / to confirm
- [ ] **VB9 HRV:** confirmed *bundled inside the "stress" value*, not a standalone raw stream. Still unconfirmed whether it's **RMSSD-based** and readable as an overnight number. Raw RRI is 30-min default (10-min at night in scientific sleep mode).
- [ ] **VC2 SpO2 interval** on the sample firmware (15 vs 60 min) — supplier verifying before shipment. Requested spec: night 22:00–08:00, one reading every 15–30 min, ideally command-configurable.
- [ ] **VC2 night-only SpO2** needs **custom firmware** (standard = 24 h). Test standard first.
- [ ] Both: reconfirm the iOS SDK/BLE protocol is **fully local** (no vendor cloud dependency).
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

## Key finding — how WHOOP / Hume actually source hardware (2026-09-16)

There is **no special "Hume chip"** to buy. From the Hume teardown: the Hume app is white-labeled from
**Lefu Healthcare / FitTrack** (`com.elink.fittrackhealth.pro`, "elink" = Lefu's app arm). The Body Pod
scale firmware in the package is Lefu's **CF818 family on a Beken BK3432 BLE chip**, OTA'd via **Nordic
DFU**. The Hume Band rides the same ODM ecosystem (Beken/Nordic-class BLE + optical PPG) — the **same
tier as Vivistar VB9/VC2**. What makes WHOOP/Hume feel premium is **custom firmware + server-side
algorithms** — the part HUMANS already owns. And **Hume's band data is locked** (no dev SDK), so cloning
its hardware gives *worse* access than the Vivistar quotes.

**Reframe of the VB9/VC2 problem:** they don't "not work" on hardware — it's *firmware config*. VC2 already
provides continuous 25 Hz HR + **raw RRI over open BLE** (the strongest data we've found); its only real
objections are the screen and night-only SpO2, both firmware/enclosure issues, not sensor issues.

### Options (WHOOP/Hume playbook, adapted)
1. **Custom firmware on VC2** — ask Vivistar to enable night-windowed/continuous SpO2 + preferred RRI
   cadence (VB9's "scientific sleep mode" proves configurability). Lowest effort, same supplier.
2. **Custom screenless build** — "VC2 internals (Nordic + raw RRI) in a VB9 screenless shell." Private-mold
   request; ODMs do this routinely. Needs MOQ + tooling.
3. **Go to Lefu directly** — Lefu Healthcare (lefu.com) is the ODM behind Hume. Request their band **with
   SDK/raw-data access** = Hume-grade hardware minus Hume's lock. Adds a supplier + leverage.

**Recommendation:** keep VC2 (best raw data), treat screen + SpO2-window as a custom-firmware/enclosure
request (Option 1→2); contact **Lefu** in parallel (Option 3) as the Hume-grade alternative.

---

## 4. Shenzhen Unique Scales Co., Ltd. (brand "LEFU") — SCALE OEM behind Hume's Body Pod
- **Corrected identity (2026-09-16):** "lefu.com" was wrong. **LEFU is a brand of Shenzhen Unique Scales
  Co., Ltd.** — the manufacturer behind Hume's Body Pod scale. App = "Unique Health" (`com.lefu.futula.healthu`).
- **Address:** 301 & 601, No. 22 Huanping Road, Gaoqiao Community, Pingdi Street, Longgang District,
  Shenzhen 518117 (same district as Vivistar).
- **On Alibaba:** ✅ Shenzhen Unique Scales Co., Ltd. — 16 yrs · 4.9★ · 3,731 sold · 8-electrode scale · MOQ 500.
- **Caveat:** this is the **scale** OEM (8-electrode body composition), **NOT confirmed as the wrist-band ODM**.
  Hume's band is likely a different ODM; the shared elink/FitTrack app covers both. So this does **not** solve
  the band/HRV need.
- **Where it helps:** if HUMANS wants **accurate 8-electrode body composition** (which wrist-BIA like VB9
  can't do), this + similar SDK scale OEMs are the right suppliers. The app already reads body fat / lean from
  Apple Health, so any scale that writes to HealthKit or exposes an SDK feeds the Body Composition tracker.

## 5. Scale OEMs with open SDK/API (body composition, Alibaba) — for the scale path
- **Shenzhen Yolanda Technology** — "SDK Support… 25 body metrics" 8-electrode scale · 10 yrs · 4.8★ · MOQ 1.
- **Shenzhen Acct Electronics** — "Free API / SDK / APP" body-fat scale · 8 yrs · 4.6★.
- **Guangdong Welland Technology** — 8-electrode OEM/ODM · big volume (11,320 sold).
- **Guangdong Transtek Medical** — major scale OEM · 22 yrs.
- Note: the **band** (raw HRV/RRI) and the **scale** (accurate body comp) are two separate sourcing tracks.

---

## What we need from any supplier (checklist)
1. **Raw RRI (beat-to-beat intervals)** exposed via SDK or documented BLE — this is what lets HUMANS compute real RMSSD recovery.
2. **iOS-native access** (Swift/BLE) with **no dependency on the vendor's app or cloud**.
3. Core vitals: continuous HR, SpO2 (ideally overnight), skin temp, sleep stages.
4. SDK / BLE protocol **documentation** provided before/at sampling.
5. Reasonable battery (≥5–7 days) and screenless form factor preferred.
6. Sample availability (low MOQ) before any production commitment.
