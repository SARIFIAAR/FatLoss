# Fat Loss Coach (iOS)

Native SwiftUI port of the single-file "My Fitness Coach" web app, built for a personal fat-loss
programme (106 kg → 93 kg). iOS 17+, iPhone. Currently on TestFlight as build 1.0.0 (6).

## What it does

| Tab | Features |
|---|---|
| **Today** | Programme phase strip · daily targets (eaten vs target once meals are logged) · Apple Watch steps and resting HR · readiness score from HRV, sleep and resting HR · 7 habits (supplements, breathing and water tick themselves) · water · supplements · tickable breathing schedule · log weight / waist |
| **Progress** | Weight goal bar · waist and weight charts with goal line · daily calories stacked by protein / carbs / fat · weekly steps vs goal · HRV (30 nights) · sleep total / deep / REM (14 nights) · 28-day habit heat-map · supplement adherence |
| **Workout** | Three-phase programme with a progress bar and week counter: **Phase 1 Foundation** (4 weeks, 2× full body + walks), **Phase 2 Build** (4 weeks, machine-first 3×), **Phase 3 Full Gym** (8 weeks, Push / Pull / Legs). Exercise photos, per-exercise progressive-overload log, start / advance / change phase |
| **Nutrition** | Photograph a meal → calories, protein, carbs, fat per item (Claude vision) · camera button on each meal-plan slot · eaten-today list · water tracker · 9 PM kitchen-closed banner |
| **Profile** | Goals · cloud backup with Sign in with Apple · Apple Health connect and sync · manual entry fallback · Shortcuts URL scheme · import from the web app · JSON export |

## Architecture

- **Data**: one `AppData` struct (Codable) saved as JSON in Application Support, mirrored to Firestore
  at `users/{uid}` when signed in. Field names map 1:1 to the old localStorage keys, and the importer
  reads a `JSON.stringify(localStorage)` dump (the web app got a "Copy my data" button for this).
- **Health**: HealthKit reads steps, resting HR, HRV, respiratory rate and sleep stages, with a
  30-day backfill and a re-sync on every foreground.
- **Meal scanner**: the phone downsizes the photo to 1024 px and POSTs it with its Firebase ID token to
  a small Node service on Fly.io (`server/`), which verifies the token and asks Claude for a structured
  estimate. The Anthropic key lives only on the server.
- **Cloud**: Firebase Auth (Apple) + Firestore on the free plan, owner-only rules in `firestore.rules`.

See `CLAUDE.md` for identifiers, conventions, gotchas and the exact build / ship commands.

## Setup

1. Clone, then restore the Firebase config (git-ignored because the repo is public):
   `firebase apps:sdkconfig IOS 1:836772213794:ios:91156d2fa72e12d2a6867b --project fat-loss-6516d --out FatLossCoach/GoogleService-Info.plist`
2. Open `FatLossCoach.xcodeproj` in Xcode 26 and run on an iPhone (team 9F2G8CQ45J). Swift packages
   (Firebase) resolve on first build.
3. Analyzer, once: `cd server && flyctl auth login && flyctl apps create fatloss-analyzer && flyctl secrets set ANTHROPIC_API_KEY=... && flyctl deploy`
   (optional `MODEL=claude-sonnet-5` secret for a cheaper model).

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
| 5 | Camera per meal slot, stacked calories chart, breathing / supplement habit links |
| 6 | Analyzer moved from Cloud Functions to Fly.io (no Google billing) |
