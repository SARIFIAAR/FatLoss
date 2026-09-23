# FatLoss Coach — Backlog

*Per-project backlog (project brain). CEO-parked / known-next work, newest first. Part of the MetaTec agile operating model (`~/MyCompany/agents/AGILE-OPERATING-MODEL.md`). Template: `~/MyCompany/agents/BACKLOG-TEMPLATE.md`.*

*Rules: anyone may append; keep to the item format. Don't invent work — only real, known items. When an item ships or is decided, remove it here; decisions go to `~/MyCompany/decisions/DECISIONS-LOG.md`.*

## Backlog

## NEXT — Wire onboarding questionnaire answers into the plan — added 2026-09-23
`Models/Intake.swift` (`IntakeProfile`, ~45 questions) exists (2026-09-08) but is not yet shipped; the workout phases + meal plan still come from `Plan` constants and don't use the answers. Tailoring the plan to the intake answers is the natural next step.
**Next step:** consume `IntakeProfile` to tailor workout phases / meal plan; then bump `CURRENT_PROJECT_VERSION` (both configs) and ship via `scripts/ship.sh` (CEO build approval required).

## NEXT — Backend: set Fly secrets, verify dashboard, invite testers — added 2026-09-23
`/health` returned `{"firestore":false,"admin":false}` (checked 2026-09-06), so `/admin` reports firestore/admin down until the two Fly secrets are set. Build 6 is valid on TestFlight.
**Next step:** set the two Fly secrets, confirm the coach dashboard works, invite testers.

## NEXT — Remove stray Firebase iOS app `com.metatec.myfitnesscoach` — added 2026-09-23
A stray Firebase iOS app (bundle `com.metatec.myfitnesscoach`) still exists in the project — housekeeping.
**Next step:** confirm it's unused, then delete it from the Firebase project.
