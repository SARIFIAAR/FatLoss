# HUMANS — Wearable Compatibility Study (2025–2026)

**Question this answers:** how compatible is HUMANS's *design* with the wider wearable market?

HUMANS reads **all** of its data from **Apple HealthKit**. So "can wearable X feed our app?"
reduces to one testable fact: **does wearable X's iOS companion app write that metric into
Apple Health?** A device can measure something perfectly and still be useless to us if its app
keeps the data in its own silo (Fitbit did this for years; Whoop and Garmin still do for their
best metrics).

## How to read the matrix

- **✓** — the wearable's app writes this to HealthKit → **our app gets it automatically today**
- **✗** — the device measures it but does **not** write it to HealthKit → we can't see it
- **–** — the device doesn't measure it
- **~** — partial: manual refresh, summary-only, model/firmware-dependent, or a bridge app needed
- **HUMANS reads?** — whether our `HealthKitManager` already ingests that HealthKit type

Columns: AW=Apple Watch · WH=WHOOP · OU=Oura · UH=Ultrahuman · GA=Garmin · FB=Fitbit ·
SS=Samsung Galaxy Watch · PO=Polar · WI=Withings · CO=COROS · AZ=Amazfit/Zepp · RC=RingConn Gen2

## Master matrix

| # | Data point | HUMANS reads? | AW | WH | OU | UH | GA | FB | SS | PO | WI | CO | AZ | RC |
|---|-----------|:---:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| 1 | Steps | ✓ | ✓ | ✗ | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| 2 | Active energy (calories) | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ~ | ✓ | ✓ |
| 3 | Resting heart rate | ✓ | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ |
| 4 | Continuous heart rate | ✓ | ✓ | ~ | ✓ | ~ | ~ | ~ | ✗ | ✗ | ✓ | ~ | ✓ | ~ |
| 5 | **HRV** | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ~ | ✗ |
| 6 | Respiratory rate | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ~ | ✗ |
| 7 | Sleep stages (deep/REM/light) | ✓ | ✓ | ~ | ✓ | ~ | ✓ | ✓ | ✗ | ~ | ✓ | ✗ | ✓ | ✓ |
| 8 | Blood oxygen (SpO2) | ✓ | ✓ | ✓ | ✗ | ~ | ✓ | ✓ | ✗ | ✗ | ~ | ✗ | ✓ | ✓ |
| 9 | Skin / wrist temperature | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | – | ✗ | ✗ | ✗ | ✗ |
| 10 | VO2 max / cardio fitness | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| 11 | Workouts + HR zones | ✓ | ✓ (zones) | ✓ | ✓ | ~ | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ~ | ~ |
| 12 | ECG / AFib | ✗ | ✓ | – | – | – | ✗ | ✗ | ✗ | – | ✗ | – | ✗ | – |
| 13 | Blood pressure | ✓ | –* | – | – | – | – | – | ✗ | – | ✓ | – | – | – |
| 14 | Blood glucose (CGM) | ✓ | – | – | – | ✓ | – | – | – | – | – | – | – | – |
| 15 | Body composition (fat/lean/wt) | ✓ | ~* | ✗ | ~ | ✗ | ~ | ✗ | ✗ | ~ | ✓ | – | ~ | ~ |
| 16 | Readiness / Recovery score | *we compute* | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| 17 | Stress score | *we compute* | ~ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| 18 | Mindfulness / meditation | ✓ | ✓ | ✗ | ✓ | ~ | ✗ | ✗ | ✗ | – | – | – | ✗ | ✗ |

\* Apple Watch reads blood pressure & body-fat from paired accessories (BPM cuff, BIA scale); the
watch itself doesn't measure them.

## The three findings that matter for our design

1. **Our ingestion surface is already comprehensive.** HUMANS reads 18 HealthKit types — every
   metric any of these wearables can export. We are not leaving data on the table on our side; the
   ceiling is set by the wearables, not by us. No design change is needed to "support" more devices —
   supporting HealthKit *is* supporting the whole compatible market.

2. **Proprietary scores can never arrive via HealthKit — so computing our own was the right call.**
   Whoop Recovery/Strain, Oura Readiness/Stress/Resilience, Garmin Body Battery/Training Readiness,
   Ultrahuman/Amazfit indices — **none** cross HealthKit, because Apple defines no native sample type
   for them. HUMANS deriving its own Recovery / Strain / Stress / Body Battery from raw signals is
   what makes us **wearable-agnostic**: a Garmin user and an Oura user both get a HUMANS score, where
   a vendor-score-dependent app would show nothing. This is a genuine architectural advantage — keep it.

3. **HRV is the market's biggest hole, and a subtle data-quality trap.** Every device measures HRV,
   but only **Apple Watch and Ultrahuman** write it to HealthKit. Worse, the two camps store it
   differently: **Apple & Ultrahuman = SDNN**, while Whoop & Oura use **RMSSD** (and don't export at
   all). Our `heartRateVariabilitySDNN` read is correct, but any future multi-source HRV merge must
   not mix SDNN and RMSSD values on the same axis — they aren't interchangeable.

## Compatibility tiers (HealthKit-only, i.e. plug-and-play today)

| Tier | Wearables | What HUMANS gets automatically |
|---|---|---|
| **Full** | Apple Watch | Everything, incl. ECG, VO2 max, HR zones, temp, HRV (SDNN) |
| **Strong** | Oura, Withings, Garmin | Sleep stages, HR, SpO2/resp, workouts; +VO2max & sleep (Garmin), +BP/body-comp/VO2max (Withings), +temp/mindful (Oura) |
| **Good** | Ultrahuman, Amazfit/Zepp, RingConn, Fitbit† | Core activity + sleep + vitals; Ultrahuman uniquely adds **CGM glucose** & HRV |
| **Weak** | Polar, COROS | Workouts + partial dailies only; COROS syncs **workouts only** |
| **Unusable** | Samsung Galaxy Watch / Ring | Samsung Health on iOS doesn't write to HealthKit — we get ≈nothing |

† Fitbit only became HealthKit-compatible in **Aug 2026** via the Google Health iOS app (v5.05);
older setups still need a bridge app (Sync Solver / Health Sync).

## Special cases worth remembering

- **Ultrahuman Ring Air** is the only device here that can put **CGM glucose** into Apple Health
  (via its M1 sensor) — a differentiator if we lean into metabolic tracking.
- **Circular Ring** (not in the main grid) is the broadest *ring* for HealthKit — it writes HRV,
  respiratory rate, **and** skin temperature (fixed mid-2026), which even Oura/RingConn don't.
- **ECG** is effectively **Apple-Watch-only** for everyone: HealthKit's ECG type is write-restricted,
  so no third-party device populates it regardless of hardware. We don't read ECG today (fine).

## If we ever go beyond HealthKit (direct cloud APIs)

Only needed to capture the proprietary scores / HRV that HealthKit won't carry. Viability varies a lot:

| API | Access model | Gets us the vendor scores? |
|---|---|---|
| **Oura API v2** | Self-serve OAuth2 (PATs deprecated Dec 2025) | ✓ Readiness, Stress, Resilience, HRV, VO2max |
| **WHOOP API v2** | Self-serve OAuth2 | ✓ Recovery, Strain, HRV, sleep |
| **Withings Cloud API** | Self-serve OAuth2 | ✓ full-fidelity incl. BP, body-comp |
| **Polar AccessLink** | Open OAuth2 | ✓ Nightly Recharge, HRV, VO2max |
| **Garmin Health API** | Partner-approval only; new sign-ups reportedly paused | Body Battery, HRV, stress (if approved) |
| **Fitbit Web API** | OAuth2 — **but sunset Sept 2026, do not build on it** | — |
| **Samsung / COROS / Amazfit** | No usable self-serve iOS API (Samsung=Android-only; COROS/Amazfit via aggregators Terra/ROOK) | ✗ |

**Recommendation:** stay HealthKit-only for now — it already covers the whole plug-and-play market
and keeps zero integration/maintenance burden. If users ask for Oura/Whoop *scores* specifically,
Oura v2 and Whoop v2 are the two clean, self-serve APIs worth adding first. Avoid Fitbit's API
(sunsetting) and don't expect anything from Samsung on iOS.

---
*Compiled from web-verified 2025–2026 behavior across three research passes. Cells marked ~ or
footnoted are firmware/version/region-dependent — confirm on a real device before depending on them.*
