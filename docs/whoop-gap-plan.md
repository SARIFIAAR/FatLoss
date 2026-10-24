# HUMANS Strap vs WHOOP — gap-closure plan (2026-10-24)

The HUMANS wearable is the **VY28C strap** ("QRing" is only the vendor's commercial name — same
screenless-strap form factor as WHOOP). With the native protocol client now verified on-device
(op21 today-HR, teardown §12), every remaining gap vs WHOOP is an engineering item on OUR side of
the link, not a vendor dependency. This is the ordered plan to close them.

**WHOOP's four structural advantages** (from the architecture read): ① continuous sampling,
② persistent background connection, ③ chunked/resumable transfer + cloud stitching,
④ a decade of validated algorithms (rMSSD HRV, sleep staging, Recovery/Strain baselines).
①–③ are buildable now; ④ we approximate with transparent models + a validation pass.

---

## Phase 1 — Finish owning retrieval (kills the reliability gap)

The flaky vendor-SDK reads get replaced one at a time by the native client; SDK stays as fallback.

1. **op21 history backfill** — extend the native HR-log read to days 1–6 (same command, yesterday+
   timestamps; parser already handles non-today days). Replaces the SDK's `getSchedualHeartRateData`
   as primary. *Small: parser + transport exist.*
2. **Sleep via Big Data 0x27** — RingDirect variant targeting the `de5bf728` service (write `de5bf72a`,
   notify `de5bf729`), request `bigDataRequest(.sleep)`, reuse `RingBigDataReassembler` (unit-tested);
   port openring's `parseSleepPayload` (daysAgo + signed min-after-midnight + stage pairs
   2=light 3=deep 4=REM 5=awake). Replaces the single flakiest SDK read. *Medium.*
3. **HRV 57 / stress 55 / steps 67 native** — same multi-packet shape as op21 (HRV sub_type 1 carries
   daysAgo instead of timestamp, range 30 min). *Small each, after #1 proves the pattern.*
4. **Exit criterion:** 20 consecutive syncs with zero native-read failures; vendor SDK used only for
   one-key measure, realtime streams, and config commands.

## Phase 2 — Background continuity (WHOOP's always-on)

`UIBackgroundModes: bluetooth-central` is ALREADY in Info.plist (from the VB9 work).

1. **CoreBluetooth state restoration** — `CBCentralManagerOptionRestoreIdentifierKey` +
   `willRestoreState`; reconnect to the persisted peripheral ID and run a sync whenever iOS wakes us
   on a connection event. The strap then syncs with the app closed — the single biggest UX jump.
2. **Connection-event syncs** — on every didConnect (background included) run syncHistory; keep the
   15-min auto one-key throttle.
3. **Firebase write-through** — after each flush, push the ring-day rows through CloudMirror
   immediately (it already diffs by SHA, so this is cheap) → partial syncs get stitched in the cloud
   like WHOOP. *Small: the pieces exist, wire them.*

## Phase 3 — Sampling density (continuous-ish HR)

1. **Lower the scheduled-HR interval** — `setSchedualHeartRateStatus(interval:)`: firmware default is
   5 min; test how low it accepts (official app UI suggests configurable). Measure battery per setting
   over 24 h (strap battery push already wired). Target: 1–2 min passive sampling if battery allows
   ≥2 days.
2. **Live-accumulate while connected** — `Store.observeHeartRate` already catches realtime HR; with
   Phase 2's background link this becomes near-continuous coverage whenever phone and strap are
   together.
3. Wear-detection via `getSedentaryReminderFromDay` (all-day worn/active timeline) to invalidate
   off-wrist samples before they pollute baselines.

## Phase 4 — True HRV + respiratory rate (the science gap)

The strap exposes what WHOOP computes from: **25 Hz raw green PPG + 3-axis accel**
(`QCMeasuringTypeHeartRateRaw`, 100 s windows — full recipe in teardown §6).

1. Capture pipeline: 100 s raw windows on a schedule (sleep hours first, when motion is lowest).
2. Signal processing: band-pass → beat detection → RR series (interpolate for precision) → **rMSSD**
   (true HRV, replacing firmware HRV) + **respiratory rate** via RSA/EDR. Accel gates motion artifacts.
3. Feed BodyMetrics Recovery with rMSSD; keep firmware HRV as the fallback series.
4. This also unlocks a WHOOP-style "measured during sleep" HRV baseline instead of spot readings.

## Phase 5 — Score maturity + validation (WHOOP's moat)

1. **Validation week:** strap + Apple Watch worn together 7 days; per-day deltas on HR envelope,
   resting HR, sleep duration/stages, HRV trend. Tune clamps/baselines where we diverge. (The models
   are ours in BodyMetrics — the vendor app computes nothing — so tuning is free.)
2. **Readiness/Rest index** (deferred item) once Phase 4 gives trustworthy nightly rMSSD.
3. Recalibrate Strain's TRIMP path with denser HR from Phase 3.
4. Wellness-not-medical framing stays (claims register; same line WHOOP walks).

## Phase 6 — Productization (hardware-side asks)

1. **Vivistar OEM firmware request** (production order): broadcast name "HUMANS" (confirmed
   impossible from the phone — setUUID unimplemented), branded packaging; ask what else is
   configurable (HR interval floor, charging LED). App already auto-connects to `HUMANS*` names.
2. Battery UX: low-battery nudge off the existing battery push; charge-reminder before sleep if <20%.
3. Onboarding flow for strap-only users (no Apple Watch): wear calibration (§7), first-sync
   walkthrough, Physical Age calibration expectations.

---

**Sequence logic:** 1→2 are the platform (reliable + always-on); 3 rides on 2; 4 is the one
hard-science project and can start in parallel after 1; 5 needs 3+4's data; 6 is independent and
belongs with the production order. After Phases 1–3, the honest comparison vs WHOOP is "same
architecture, coarser passive sampling, younger baselines"; after 4–5 it's feature parity with a
transparent model and no subscription.
