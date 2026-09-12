# Fat Loss Coach (iOS)

Native SwiftUI port of the single-file "My Fitness Coach" web app, built for a personal fat-loss
programme (106 kg → 93 kg). iOS 17+, iPhone. Currently on TestFlight as build 1.0.0 (11).

## Status (12 September 2026)

- **Build 11 uploaded 12 September 2026** — one type scale across the app (the Body screen's
  condensed-heavy sizes) and a calmer emerald accent replacing the neon mint.
- **Build 10 uploaded 12 September 2026** — a new **Body** tab (WHOOP-style dashboard, always dark):
  recovery / strain / sleep ring gauges, a week strip with recovery-zone dots, sleep-need breakdown
  (baseline + debt + strain credit) with stage bars, a health monitor comparing HRV, resting HR,
  respiratory rate, wrist temperature, blood oxygen and sleep against personal 28-day typical ranges,
  behaviour impacts (next-day recovery effect of each habit and supplement), a week-in-review card and
  full-screen deep-dives per pillar with 30-day trend bars. Scores are computed on-device: recovery
  0–100 from baseline z-scores, strain 0–21 from active energy and workout HR zones (Edwards TRIMP).
  HealthKit now also reads workouts with heart-rate samples, SpO2, sleeping wrist temperature and
  in-bed time. The whole app moved to one dark theme matching the Body tab, and the tab bar is now
  five tabs (Today · Body · Nutrition · Train · Progress) with Profile behind the gear icon on Today.
- **In progress (8 September 2026):** a nine-step **onboarding questionnaire** (body, goal and pace, daily
  activity, training availability and equipment, food style and allergies, sleep and stress, health
  conditions with gentle mood and anxiety questions, medications and supplements, devices) that builds
  personal calorie, macro, water and step targets plus a timeline. Shown on first launch for a new profile;
  editable later from Profile.
- **Build 9 uploaded 7 September 2026 (evening):** fixes a cloud-sync merge that could reset the programme start date
  and reminder switches after an update, and adds an Apple-Fitness-style **week calendar** on Nutrition — a
  calorie ring per day, swipe between weeks, tap any day to see what you ate and log meals to that day.
- **Build 8 uploaded 7 September 2026** with everything below.
- Every meal can now be logged three ways — **photo**,
  **typed search** against the USDA FoodData Central database (household portions or grams × quantity,
  several foods per meal) and **barcode** (Open Food Facts, USDA Branded fallback) — plus an
  "Ask AI to estimate" fallback for a typed description. Server gained `/foods`, `/barcode` and text
  input on `/analyze`; needs a redeploy and, ideally, a free `USDA_API_KEY` secret.
- **Guided breathing**: every session in the Today breathing schedule opens a guided screen — technique
  guide, a square / triangle / circle with a dot that travels one side per breath step, ocean background,
  calming music, spoken cues, haptics, pause/end — and ticks the schedule and the breathing habit when finished.
- The Anthropic key on the server was replaced on 7 September after the old one was revoked
  ("Model error 401" in the app).
- All five tabs, HealthKit sync, cloud backup, web-app import and the three-phase programme are built
  and on TestFlight. **Build 7 uploaded 6 September 2026 and is VALID** (builds 1–4, 6 and 7 are there).
- The meal-photo analyzer backend (`server/`) is **live on Fly.io** (`fatloss-analyzer.fly.dev`) and the
  scanner works from build 6 onward.
- Build 7 adds: Apple Watch calories burned (active + resting) with a daily **deficit** on Today, Nutrition
  and a new Energy Balance chart; water and walk **reminders** (local notifications with "Log 250/500 ml"
  actions); a per-user **backend mirror** (`users/{uid}/days`, `users/{uid}/meals`, profile/goals/stats);
  a coach **dashboard** at `/admin` on the Fly app (per-user trends, meals/scans/days tables, CSV export);
  and the scanner now sends the user's targets as context, so the dietitian prompt is no longer
  hard-coded to one person.
- **Waiting on the owner:** the Fly secrets `ADMIN_KEY` and `FIREBASE_SERVICE_ACCOUNT` are not set yet
  (`/health` reports `firestore:false, admin:false`), so `/admin` is locked and scans are not logged
  server-side. Also rotate the Anthropic key and delete the stray `com.metatec.myfitnesscoach` app
  from the Firebase project.

## What it does

| Tab | Features |
|---|---|
| **Today** | Guided breathing sessions (shape + travelling dot, music, voice, haptics) from the breathing schedule · Programme phase strip · daily targets (eaten vs target once meals are logged) · Apple Watch steps, resting HR and kcal burned with a burned / eaten / deficit line · readiness score from HRV, sleep and resting HR · 7 habits (supplements, breathing and water tick themselves) · water · supplements · tickable breathing schedule · log weight / waist |
| **Progress** | Weight goal bar · waist and weight charts with goal line · daily calories stacked by protein / carbs / fat · 7-day energy balance (eaten vs burned, per-day deficit, average) · weekly steps vs goal · HRV (30 nights) · sleep total / deep / REM (14 nights) · 28-day habit heat-map · supplement adherence |
| **Workout** | Three-phase programme with a progress bar and week counter: **Phase 1 Foundation** (4 weeks, 2× full body + walks), **Phase 2 Build** (4 weeks, machine-first 3×), **Phase 3 Full Gym** (8 weeks, Push / Pull / Legs). Exercise photos, per-exercise progressive-overload log, start / advance / change phase |
| **Nutrition** | Week calendar with a calorie ring per day (swipe weeks, tap a day to review or back-fill it) · Log each meal by photo (Claude vision), typed search (USDA FoodData Central, portions × quantity, multi-food meals), barcode (Open Food Facts / USDA Branded) or a one-line AI estimate · "+" menu on each meal-plan slot · eaten-today list · kcal burned and deficit so far plus 7-day average deficit · water tracker · 9 PM kitchen-closed banner |
| **Profile** | Goals · cloud backup with Sign in with Apple · Apple Health connect and sync · manual entry fallback · water / walk reminders · Shortcuts URL scheme · import from the web app · JSON export |

## Architecture

- **Data**: one `AppData` struct (Codable) saved as JSON in Application Support, mirrored to Firestore
  at `users/{uid}` when signed in. Field names map 1:1 to the old localStorage keys, and the importer
  reads a `JSON.stringify(localStorage)` dump (the web app got a "Copy my data" button for this).
- **Backend mirror**: when signed in, `CloudMirror` also writes one flat row per day to
  `users/{uid}/days/{date}` (weight, recovery, steps, kcal burned / eaten, deficit, habits, lifts …) and
  one per scanned meal to `users/{uid}/meals/{id}`, plus profile / goals / stats on the user doc. Rows are
  hash-diffed so only changed days are written. Every person who signs in with Apple gets their own tree.
- **Health**: HealthKit reads steps, resting HR, HRV, respiratory rate, sleep stages and active + resting
  energy, with a 30-day backfill and a re-sync on every foreground.
- **Meal scanner**: the phone downsizes the photo to 1024 px and POSTs it with its Firebase ID token and
  the user's targets to a small Node service on Fly.io (`server/`), which verifies the token and asks
  Claude for a structured estimate. The Anthropic key lives only on the server.
- **Coach dashboard**: `server/admin.html` at `/admin`, unlocked by the `ADMIN_KEY` header, reads the
  `users/*` rows and the server-side `scans/` log through a tiny REST Firestore client (service account,
  no firebase-admin).
- **Reminders**: `ReminderManager` schedules local notifications for water (interval within set hours)
  and walks; the water notification has log actions that write straight into the store.
- **Cloud**: Firebase Auth (Apple) + Firestore on the free plan, owner-only rules in `firestore.rules`
  (`users/{uid}` and its `days` / `meals`; `scans` is server-only).

See `CLAUDE.md` for identifiers, conventions, gotchas and the exact build / ship commands.

## Setup

1. Clone, then restore the Firebase config (git-ignored because the repo is public):
   `firebase apps:sdkconfig IOS 1:836772213794:ios:91156d2fa72e12d2a6867b --project fat-loss-6516d --out FatLossCoach/GoogleService-Info.plist`
2. Open `FatLossCoach.xcodeproj` in Xcode 26 and run on an iPhone (team 9F2G8CQ45J). Swift packages
   (Firebase) resolve on first build.
3. Analyzer, once: `cd server && flyctl auth login && flyctl apps create fatloss-analyzer && flyctl secrets set ANTHROPIC_API_KEY=... && flyctl deploy --ha=false`
   (optional `MODEL=claude-sonnet-5` secret for a cheaper model).
4. Dashboard + scan logging (optional):
   `flyctl -a fatloss-analyzer secrets set ADMIN_KEY="$(openssl rand -hex 24)" FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"`
   then open `https://fatloss-analyzer.fly.dev/admin` and paste the key. `GET /health` shows which of
   the two are configured.

## Migrating from the web app

In the old HTML app: Profile → **Copy my data**. In the iOS app: Profile → Import → **Paste** →
**Import**. Entries are merged, nothing is deleted.

| web localStorage key | native field |
|---|---|
| `weight-logs`, `cur-weight` | `weightLogs` |
| `waist-logs`, `cur-waist` | `waistLogs` |
| `rec-YYYY-MM-DD` | `recovery[date]` |
| `po-{Exercise}` | `overload[name]` |
| `habits-YYYY-MM-DD` | `habits[date]` |
| `supps-YYYY-MM-DD` | `supplements[date]` |
| `water-YYYY-MM-DD` | `water[date]` |
| `health-sync` | `health[date]` |
| `ex-YYYY-MM-DD-Mon` | `exerciseDone["date-Mon"]` |

Shortcuts can still push metrics:
`fatlosscoach://sync?hrv=45&rhr=52&sleep=7.2&deep=1.4&rem=1.8&resp=14&mood=4&steps=7500`

## Build history

| Build | Change |
|---|---|
| 1 | Initial port of all five tabs, HealthKit, charts, cloud sync, importer. Crashed on every write (fixed in 2) |
| 2 | Fixed the write crash (observer re-entrancy in the store) |
| 3 | Three-phase programme with progress tracking |
| 4 | Meal photo scanner, real eaten-vs-target macros, version footer |
| 5 | Camera per meal slot, stacked calories chart, breathing / supplement habit links (archived, not uploaded) |
| 6 | Analyzer moved from Cloud Functions to Fly.io (no Google billing) |
| 7 | Apple Watch energy + daily deficit, Energy Balance chart, water / walk reminders, per-user backend mirror (schema 2), `/admin` coach dashboard, scanner context |

Builds 1–4, 6 and 7 are on TestFlight. `node scripts/asc_builds.mjs` lists them with their processing state.
