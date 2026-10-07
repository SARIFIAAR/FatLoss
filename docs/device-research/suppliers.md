# HUMANS — Wearable Device Research: Supplier Registry

Tracking OEM/ODM suppliers evaluated to pair a wearable with the HUMANS app. Goal: a band that
exposes **raw HRV (RRI)** and the core vitals over an **iOS-accessible SDK or BLE protocol**, so the
app's on-device recovery/strain/stress/sleep engine can run on it (no vendor cloud lock-in).

Last updated: 2026-09-29

---

## Status summary

| Supplier | Device(s) | Stage | Next action |
|---|---|---|---|
| **Shenzhen Vivistar** | VB9, VC2, **SH09 ← lead candidate** | ⏳ SH09 IS the device documented by the Tech Guide + BLE protocol (2026-07-24): screenless, metal faceplate (brandable/private mold), 5 ATM, ~10–15 d; exposes **raw RRI + raw PPG (25–500 Hz) + ECG 500 Hz + SpO2 + skin/body temp + respiration** over **iOS SDK + DEMO + documented BLE protocol (Service 0xFFF0), no cloud**. Clears every HUMANS requirement in the preferred screenless form. **⚠️ But the supplier's VSH09-HTO2 spec sheet (received 2026-09-29, dated 2023-04-11) describes a DIFFERENT config — see the SH09 table below — with a 0.87" PMOLED screen, plastic/IP68, BT 4.2, IXFIT app, HRV(RRI)+SpO2+temp+BP but NO ECG/raw-PPG/respiration listed. Reconcile which SH09 the sample will actually be.** | Confirm with Cassidy which SH09 config ships (screenless-metal-ECG per the Tech Guide, or the screened VSH09-HTO2 per this spec); confirm raw RRI is a readable stream + data-access path (SDK vs BLE); get price/MOQ; order a sample. Resolved by the spec sheet: **chipset = Nordic nRF52832**, battery 60 mAh / 7 days, IP68. |
| ICTOPSUPPLY | H59 | ⬜ Not contacted | Backup — open SDK, MOQ 10 |
| Shenzhen Tianpengyu | ECG+HRV band | ⬜ Not contacted | Backup — open SDK, MOQ 1 |
| Erontech (erontech.en.alibaba.com) | HR-only screenless SKU seen | ⬜ Lower priority (2026-09-24) — the screenless HRV band first noted here is actually Vivistar's SH09 (re-attributed) | Only pursue if it beats Vivistar on price + PROVEN data access |

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

### DECISION (2026-09-29) — sample VC2 + VB9; SH09 parked
Ordering **VC2** (the pick — only device with *confirmed* raw RRI over open BLE, best sensor set; screen no longer a concern) **and VB9** (to test whether we can crack its data — HRV is bundled in "stress," so this validates whether raw RRI is reachable without custom firmware). **SH09 is parked** pending Cassidy's confirmation of (a) raw-RRI/open-BLE data access and (b) which config actually ships (screened VSH09-HTO2 vs the Tech-Guide screenless-ECG unit). This matches the pending PI (VB9 + VC2). Device track paused here while product work continues.

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

#### SH09 / VSH09-HTO2 — spec sheet received 2026-09-29 (supplier spec dated 2023-04-11)
"High-Precision HR + SpO2 + Blood Pressure + Body Temperature + HRV(RRI) + Stress Level Smart Bracelet."
| Attribute | Value |
|---|---|
| Form | **0.87" PMOLED screen** (128×32, single-point touch) — ⚠️ **NOT screenless**; contradicts the earlier "screenless metal faceplate" SH09 note |
| Size / weight | 40.2 × 18.1 × 13.0 mm · 8.4 g device + 7.0 g strap |
| MCU / BLE | **Nordic nRF52832** · **Bluetooth 4.2** · 512 KB flash |
| Sensors | HR (dynamic, ultra-low-power), SpO2 (PPG reflective, red + IR), body/skin temp **±0.2 °C** (range 32–42 °C), G-sensor; **HRV (RRI)** + Stress level (0–255); BP (**"not accurate, to be updated"**); steps + sleep; NFC 13.56 MHz M1; SOS + social-distancing (gateway-optional) |
| HRV | **RRI: YES** — described "for evaluating emotional stress / psychological status." ⚠️ Confirm it's a **readable raw beat-to-beat stream**, not only the derived 0–255 stress index. |
| Battery / water | 60 mAh polymer · **7 days** (steps + BT + HR always-on) · **IP68** · USB direct charge, 2 h |
| Vendor app | **IXFIT** (the *same* app as VC2) |
| **Data access** | **[TO CONFIRM]** — the spec sheet doesn't state SDK vs BLE. IXFIT is the VC2 app, and VC2 = documented BLE protocol / no SDK, so **assume VC2-style open BLE with raw RRI until Vivistar confirms**; request the SH09 BLE protocol (or SDK) doc. |
| Material | Case: **plastic** · wristband: TPU (⚠️ contradicts the "metal faceplate / 5 ATM" note — this SKU is plastic / IP68) |
| Packaging | Box 98×98×40 mm, 92 g (device + strap + charger) · carton 100 pcs |

**⚠️ Discrepancies vs the earlier SH09 "lead candidate" prose (must reconcile with supplier):**
- Earlier (from the Tech Guide + BLE doc, 2026-07-24): **screenless, metal faceplate, 5 ATM, raw PPG 25–500 Hz + ECG 500 Hz + respiration, iOS SDK + BLE 0xFFF0.**
- This 2023 spec sheet instead: **screened 0.87" PMOLED, plastic, IP68, BT 4.2, IXFIT**, with **HRV(RRI) + SpO2 + temp + BP + stress** — but **no ECG, no raw-PPG sampling rates, no respiration** listed.
- Most likely either (a) **VSH09-HTO2 is a base/older SKU** and the Tech-Guide SH09 is a different/upgraded config, or (b) the earlier richer spec conflated two devices. **Ask Cassidy which SH09 the sample will be**, and whether ECG / raw PPG / the screenless-metal shell are available options.
- ✅ Resolves one open item: **chipset = Nordic nRF52832** (matches the docs, not the "JL7013A6S" spec line).

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

### VB9 custom-firmware path (preferred device — 2026-09-16)
**Hardware is capable; firmware is the bottleneck.** VB9 internals:
- **ADI/MAX30001** — medical-grade **ECG + BioZ AFE**. Can output **raw ECG → R-R intervals directly**
  (ECG-based HRV = gold standard, cleaner than VC2's PPG-derived RRI).
- **HX3695H** — optical PPG (HR / can give raw PPG).
- **Actions 3085S4** — BLE MCU (proprietary, locked firmware).

**Can we reflash it ourselves?** No — locked firmware, no source/toolchain/signing; the SDK only reads
what firmware exposes + sends supported commands. **Only Vivistar can reprogram it** (they already do custom
firmware — e.g. VB9's night RRI @10 min).

**Custom-firmware ask to Vivistar (VB9):**
1. Expose **raw R-R intervals** via SDK (from MAX30001 ECG and/or PPG) — not just the bundled "stress" value.
2. **Continuous / configurable RRI cadence** (not 30-min default).
3. Optional: expose **raw ECG waveform** (MAX30001 supports it) → a real ECG feature VC2 lacks.
4. Confirm SDK returns **per-sample RRI** the app can pull.

⚠️ Custom firmware is normally gated behind a **production MOQ**, not a single sample — a commit decision.
If they'll do it, **VB9 becomes the best option**: preferred screenless size + ECG-grade HRV.

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
