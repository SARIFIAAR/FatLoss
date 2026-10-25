# FatLoss Coach — Backlog

*Per-project backlog (project brain). CEO-parked / known-next work, newest first. Part of the MetaTec agile operating model (`~/MyCompany/agents/AGILE-OPERATING-MODEL.md`). Template: `~/MyCompany/agents/BACKLOG-TEMPLATE.md`.*

*Rules: anyone may append; keep to the item format. Don't invent work — only real, known items. When an item ships or is decided, remove it here; decisions go to `~/MyCompany/decisions/DECISIONS-LOG.md`.*

## Backlog

## IN-REVIEW — HUMANS strap native protocol client (WHOOP plan phases 1–4) — reg 🟢 — BUILT + DEVICE-VERIFIED 2026-10-25
**Story:** As a HUMANS user, I want my strap's data (HR, sleep, HRV, stress) to arrive reliably and automatically so the Body scores are always current — WHOOP-grade, without the flaky vendor SDK.
**Done:** validated the VY28C == Colmi R02 protocol byte-for-byte (`docs/qring-sdk-teardown.md` §12) and built a native BLE client (`Core/Wearable/RingProtocol|RingDirect|RingPPG.swift`): native reads for HR days 0–6 (op21), sleep (Big Data 0x27, all nights in one request), HRV (57), stress (55) — vendor SDK demoted to fallback that skips native-covered days. Always-on: CoreBluetooth state restoration (incl. the before-poweredOn race fix that froze the app overnight), auto-reconnect, background sync window; Firestore push on every flush. Verified on-device: full sync all-native, zero failures, ~27 s. Firmware verdicts recorded: 5-min HR floor effective (1-min set doesn't persist), raw PPG unsupported → HRV = the ring's firmware series. 25 offline protocol tests. Plan: `docs/whoop-gap-plan.md`. Pushed to origin (`vb9-integration`, 9 commits).
**Next step:** CEO review → Phase-1 exit watch (~20 clean syncs via normal use) + background field test (leave phone, return, check Firestore rows) → bump version → TestFlight decision (CEO-gated).

## READY — WHOOP plan Phase 5: Apple Watch validation week — reg 🟢
**Story:** As HUMANS, we want the strap's numbers validated against a reference device so the Body scores are trustworthy before wider release.
**Context:** `docs/whoop-gap-plan.md` Phase 5. Wear strap + Apple Watch together ~7 days; compare per-day HR envelope, resting HR, sleep duration/stages, HRV trend; tune `BodyMetrics` clamps/baselines where they diverge; then build the Readiness index on the validated HRV series.
**Next step:** CEO starts wearing both; per-day comparison pulled from the container + HealthKit, divergences tuned.

## NEXT — WHOOP plan Phase 6: Vivistar OEM asks (with the production order) — reg 🟢
**Context:** `docs/whoop-gap-plan.md` Phase 6 — questions for Vivistar when ordering production units: custom broadcast name "HUMANS" (proven impossible from the phone — setUUID unimplemented on VY28C), 1-min HR-interval persistence (firmware reverts to 5 m), raw-PPG-capable firmware (featureList lacks the flag), packaging/branding. App already auto-connects to `HUMANS*` names.
**Next step:** fold these into the supplier conversation when the production order is placed.

## IN-REVIEW — Biometric app-lock (Face ID) — reg 🟢 — BUILT 2026-10-15
**Story:** As a HUMANS user, I want to lock the app behind Face ID so my health data is private on a shared/lost phone.
**Done:** `Core/AppLock.swift` (LocalAuthentication, Face ID/Touch ID + passcode fallback, fail-open if no biometrics/passcode so the user can't be trapped out) + full-screen branded `LockView` overlay in `FatLossCoachApp` (covers splash/onboarding) + lock-on-background / unlock-on-active via scenePhase + "Privacy & Security" toggle in `ProfileView` (`PrivacySecurityCard`) + `NSFaceIDUsageDescription` in Info.plist. `-lockPreview 1` debug arg for QA. **Compile ✓ `** BUILD SUCCEEDED **`; sim-verified** (branded gate renders; real iOS auth sheet fires with passcode fallback — shots in `build/shots/e1-04-*`).
**Next step:** CEO review → bump `CURRENT_PROJECT_VERSION` (all 4 configs) → ship via TestFlight (CEO-gated).

## IN-REVIEW — Biometric-gated personal document vault — reg 🟢 — BUILT 2026-10-15
**Story:** As a HUMANS user, I want to store and view my own health PDFs (blood tests, InBody reports) behind Face ID so that my records live with my data.
**Done:** `HealthDoc` model + `AppData.documents` (metadata only, merge-aware) · `DocStore` (encrypted-at-rest, backup-excluded, wiped on account switch — mirrors PhotoStore) · `DocSync` (Storage `users/{uid}/documents/{id}.{ext}` + Firestore `users/{uid}/documents/{id}`, owner-only, mirrors PhotoSync) · `Store.addDocument/deleteDocument/documentsOnDevice` · `DocumentVaultView` (Face ID gate via `AppLock.authenticate`, PDF `fileImporter` + photo `PhotosPicker`, QuickLook viewer, add-details sheet, delete) · entry in Profile "Privacy & Security" card · threaded through `CloudSync` auth lifecycle. **Container only — no OCR/parsing/interpretation.** `-vaultPreview 1` QA arg. **Compile ✓; sim-verified** (vault renders with seeded docs + disclaimer — `build/shots/e1-02-vault.png`).
**⚠️ Deploy gate:** cross-device cloud sync needs the new `firestore.rules` + `storage.rules` deployed (CEO-gated: `firebase deploy --only firestore:rules,storage --project fat-loss-6516d`). Local vault works without it.
**Next step:** CEO review → deploy rules → bump version → ship (batched with the app-lock).

## NEXT — Seasonal alternate app icons — reg 🟢
**Story:** As a HUMANS user, I want to pick alternate app icons so the app feels premium/seasonal.
**Context:** Needs real icon art (design-quality bar, not a recolor hack). `UIApplication.setAlternateIconName` + `CFBundleIcons`/`CFBundleAlternateIcons` in Info.plist + a picker in the Privacy/Appearance section.
**Next step:** brief the app-icon-designer for ≥2 alternate icon families; then wire Info.plist + picker.

## PARKED (market research) — Burjeel medical-adjacent borrows — parked 2026-10-17
CEO parked the Burjeel borrow initiative as **market research** (2026-10-17) — not active build. Source/artifact = the competitive teardown of Burjeel Health v1.0.310, `docs/teardown/burjeel-health-teardown.md`. The biometric app-lock + document vault that came out of this exploration were **kept as standalone HUMANS features** (above), decoupled from the Burjeel framing. The remaining borrow ideas are parked here for later evaluation, **NOT scheduled**:
- **Multi-wearable ingestion (Terra-style, ex-CGM)** — Oura/Whoop/Garmin/Fitbit into the existing `applyWearable` path; exclude CGM/glucose (clinical).
- **Coaching-session scheduling + reminders + calendar write** — appointment/reminder UX on `ReminderManager` + EventKit; scheduling only, no clinician telehealth.
- **AI "app concierge" (intent-router, no health advice)** — RA pre-cleared GO-WITH-CONDITIONS (spec `docs/legal/concierge-guardrails.md`); tool-calling-only router, never interprets.
**Red line (unchanged):** anything clinical — telehealth, lab interpretation, prescriptions, insurance, diagnosis, CGM — stays OUT (keeps HUMANS non-regulated / US App-Store-clean).
**Next step:** none scheduled — revisit as a market-research input when prioritising the medical-adjacent direction.

## PARKED — US restaurant / fast-food menu nutrition data — added 2026-10-15
**User story:** As a US user logging meals, I want to search real restaurant & fast-food menu items (e.g. McDonald's, Chipotle, Five Guys, Starbucks in-café drinks) so that I can log what I actually eat out without guessing.
**Context / why parked:** Investigated 2026-10-15. Our `server/data/foods.db` (443k foods) is USDA — but all 429k "branded" rows are **packaged grocery products with barcodes, not restaurant menus**. Major US chains return ~0 (Five Guys, In-N-Out, Shake Shack, Panda Express, Jersey Mike's, Jack in the Box = 0; Panera 8, Arby's 3). This is a real gap for a US-focused app; competitors (MyFitnessPal, Lose It, MacroFactor) all have strong chain-menu data. CEO focus confirmed = **US market**. Parked — not building now.
**Options evaluated:**
- **Nutritionix API** — US restaurant-menu leader, most complete, kept current. But **recurring** subscription (2026: ~$499/mo @200 MAU → $999 @1k MAU → $1,850+/mo commercial, billed annually, MAU-based). No one-time option.
- **Curate top ~30 US chains ourselves** — mostly one-time build + occasional menu-refresh; we own it offline, near-zero recurring cost.
- **Lean on the Claude photo scanner** — already shipped; catches any off-menu plate.
**Leaning (CEO):** hybrid — curate top US chains once (owned) + keep USDA for grocery/barcode + photo scanner for the rest; add Nutritionix later only if users demand deeper coverage. Avoids a permanent bill.
**Next step:** when resumed — (1) pull how often real logged searches currently return no match (size the problem), then (2) decide curate-vs-Nutritionix, then (3) scope the chosen path (chain list + legal sourcing, or Nutritionix integration into `FoodSearch`).

## NEXT — Wire onboarding questionnaire answers into the plan — added 2026-09-23
`Models/Intake.swift` (`IntakeProfile`, ~45 questions) exists (2026-09-08) but is not yet shipped; the workout phases + meal plan still come from `Plan` constants and don't use the answers. Tailoring the plan to the intake answers is the natural next step.
**Next step:** consume `IntakeProfile` to tailor workout phases / meal plan; then bump `CURRENT_PROJECT_VERSION` (both configs) and ship via `scripts/ship.sh` (CEO build approval required).

## NEXT — Backend: set Fly secrets, verify dashboard, invite testers — added 2026-09-23
`/health` returned `{"firestore":false,"admin":false}` (checked 2026-09-06), so `/admin` reports firestore/admin down until the two Fly secrets are set. Build 6 is valid on TestFlight.
**Next step:** set the two Fly secrets, confirm the coach dashboard works, invite testers.

## NEXT — Remove stray Firebase iOS app `com.metatec.myfitnesscoach` — added 2026-09-23
A stray Firebase iOS app (bundle `com.metatec.myfitnesscoach`) still exists in the project — housekeeping.
**Next step:** confirm it's unused, then delete it from the Firebase project.
