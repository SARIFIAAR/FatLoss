# Fat Loss Coach (iOS)

Native SwiftUI port of the single-file "My Fitness Coach" web app. iOS 17+, iPhone.

- **Today** — targets, Apple Watch steps/RHR, readiness score (HRV · sleep · RHR), habits, water, supplements, breathing schedule, weight/waist logging
- **Progress** — weight/waist/HRV/sleep charts (Swift Charts), weekly steps, 28-day habit heat-map, supplement adherence
- **Workout** — Mon/Wed/Fri programme with exercise photos, per-exercise progressive-overload log
- **Nutrition** — water tracker, meal plan, macro targets, 9 PM kitchen-closed banner
- **Profile** — goals, Apple Health sync, cloud backup (Sign in with Apple + Firestore), import from the web app, JSON export

## Data

`AppData` (Codable) is stored as one JSON file in Application Support and mirrored to Firestore at `users/{uid}` when signed in.
Old web-app data: in the HTML app tap **Profile → Copy my data**, then **Profile → Import → Paste** in the iOS app.

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

## Setup

1. `firebase apps:sdkconfig IOS 1:836772213794:ios:91156d2fa72e12d2a6867b --project fat-loss-6516d --out FatLossCoach/GoogleService-Info.plist` (file is git-ignored)
2. Firebase console → Authentication → Sign-in method → enable **Apple**
3. Open `FatLossCoach.xcodeproj`, build for iPhone (team 9F2G8CQ45J)

Shortcuts can also push metrics: `fatlosscoach://sync?hrv=45&rhr=52&sleep=7.2&deep=1.4&rem=1.8&resp=14&mood=4&steps=7500`
