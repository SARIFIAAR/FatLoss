# Lifesum — Complete Teardown Dossier

_Competitor to HUMANS / FatLoss Coach. Compiled 2026-09-23 by Reverse Engineering & Competitive Intelligence._

**Subject:** Lifesum — "AI Calorie Counter" · pkg `com.sillens.shapeupclub` (Android) · iOS App ID `286906691` · APK teardown version `20.10.0` (versionCode 531) · vendor Lifesum AB (Stockholm) · ~65M user claim.

**HUMANS baseline for parity notes:** build 54 — auth-first onboarding, AI Claude logging, USDA food proxy, Body Recovery/Strain/Sleep, energy-balance vs Apple-Watch burn, week-calendar diary, whole-day copy-yesterday, 10 plans / 48 recipes, **no paywall yet**.

**Source tags used throughout:** **[APK]** = from the 20.10.0 decompilation · **[WEB]** = public web/help-center/store (URL cited) · **[INFER]** = reasoned inference · **[UNVERIFIED]** = claimed but not confirmed.

> **Two premise corrections vs. our previous docs (read these first):**
> 1. **"8-lives-cat.io" is NOT Lifesum's AI backend.** `api-production.8-lives-cat.io` is **RevenueCat's failover subscription-infrastructure domain** (the "8 backup lives" pun on a cat). It appears in the APK only because Lifesum uses RevenueCat for subscriptions. No Lifesum source references a cat mascot or "8-lives" for its meal AI. The prior teardown (`Lifesum_20.10.0_Analysis.md` §3) misattributed this. **[WEB/INFER]**
> 2. **The food rating is NOT a Nutri-Score "A–E" letter grade.** Lifesum uses a proprietary per-100-kcal rating with checkmark/x feedback and a top tier called **"High Nutritional Value"** — green→red gradient, not A/B/C/D/E letters. Our previous docs (and the 67-row table) conflated it with the separate EU Nutri-Score. **[WEB — help.lifesum.com/food-rating]**

---

## How to read the "HUMANS today" notes

Each area ends with a verdict: **Parity** · **Ahead** (HUMANS deeper) · **Behind** (Lifesum somewhat deeper) · **Gap** (Lifesum has it, we don't / big delta). Items flagged **⭐ MISSED** were absent or wrong in the three prior docs.

---

## 1. Onboarding & Activation

**What Lifesum does (concrete):**
- Runs **two funnels**: a native iOS/Android app flow and a longer **web quiz funnel** (~52 screens) used for paid acquisition. Screen counts vary (19/27/52) due to A/B testing. **[WEB — pageflows.com, reteno.com]**
- **Verified iOS app step order:** Splash → Get started → Select goal (Lose/Maintain/Gain) → **Enable notifications** (early opt-in, styled to mimic a system prompt) → Select gender → Quick-start guide → Confirm date of birth → Enter height → Enter weight → **Continue with email → Create account (name/email/password)** → Goals summary → **Upgrade (paywall)** → **App Tracking Transparency prompt** → email verification → Dashboard. **[WEB — pageflows.com]**
- **Account creation happens MID-flow** (before goals summary and paywall), not deferred to the end. ⭐ MISSED — prior docs implied end-of-flow. **[WEB]**
- **Paywall placement:** immediately after the Goals summary, **before the app is usable**, but **skippable** — free tier is permanent. ⭐ MISSED (exact placement). **[WEB]**
- **Data collected:** goal, gender, DOB/age, height, weight, goal weight, activity level (Low/Moderate/High/Very High), weekly pace (0.1–0.7 kg/wk, capped at 1 kg/wk, steered to ~0.5 kg/wk). **[WEB — helpshift faq 235, lifesum.com pace article]**
- **Plan recommendation logic:** BMR via **Mifflin-St Jeor** (`men 10·kg+6.25·cm−5·age+5`; `women −161`) × activity, adjusted for goal + pace; **daily goal cannot be set below BMR** (safety floor). Adaptive: recalculates as weight changes unless the user hard-sets a target. ⭐ MISSED (exact formula + BMR floor). **[WEB — helpshift 235/634]**
- **Health Test (optional, post-activation):** a **41-question** assessment that seeds the Life Score (16 metrics, 0–150). Not on the mandatory sign-up path. ⭐ MISSED. **[WEB — help.lifesum.com/life-score-ios]**
- **Diet branching:** the goal chosen (Lose/Maintain/Gain) exposes a different subset of Programs/Meal Plans (see §8). **[WEB]**
- **Social proof:** store listing shows "65 MILLION USERS" + Apple **Editors' Choice**; onboarding uses aspirational food photography. Whether testimonials/counts render *inside* in-app onboarding screens is **[UNVERIFIED]** (confirmed on store/marketing surfaces only).
- **Login options:** Sign in with Apple, Email+password, Facebook Login, Google (privacy-policy referenced, likely Android/web). **[WEB — helpshift 410, policy]**
- **Not confirmed:** projected weight-loss curve / explicit goal date on the summary screen (do NOT assume Noom-style projection); dedicated allergy or meal-frequency screens. Both **[UNVERIFIED]**.

**HUMANS today:** **Behind.** HUMANS' 9-dense-screen linear flow collects far more (~45 answers incl. mood/meds) but paces worse and lacks the one-question cadence, social-proof screens, a paywall moment, and the felt "building your plan" payoff. HUMANS is **Ahead** on input breadth and on *using* med/mood signal. Note HUMANS is auth-first; Lifesum is account-mid-flow — comparable friction.

---

## 2. Home / Diary

**What Lifesum does:**
- Jetpack **Compose main shell**, bottom tabs (Diary, Recipes, + others). **[APK]**
- **Diary day-view cards:** Food (meal-type sections), Water, Habit, **MealPlanCard**, **AiTrackingBanner**. **[APK]**
- **Meal types visible by default even before logging** (Breakfast/Lunch/Dinner/Snacks). **[WEB — multimodal-tracking-explained]**
- **Color-coded calendar** representing daily progress vs calorie goal; diary notes attachable per day. **[WEB — Progress & Statistics]**
- **Above the fold:** calorie budget ring/remaining + per-meal food rating; AI-tracking banner is a persistent conversion surface. **[APK/WEB]**
- ⭐ **MISSED — the AI redesign REMOVED per-meal calorie visibility**, drawing heavy 1-star backlash ("You can't see calories by meal anymore", "foods no longer organized by meal type"). A live UX regression. **[WEB — App Store reviews]**

**HUMANS today:** **Parity-to-Ahead.** HUMANS' week-calendar diary + energy-balance (eaten vs Apple-Watch burn) is a cleaner glance than Lifesum's post-redesign diary; Lifesum's meal-card + water/habit cards are comparable. HUMANS should NOT repeat Lifesum's mistake of hiding per-meal calories.

---

## 3. Food Logging (all methods)

**What Lifesum does:** two modes since early-2025 — **AI Tracking (default ON)** and **Classic/Traditional Tracking** (toggle off).

- **Entry point:** "+" in bottom tab bar or next to a Meal Card → with AI on, opens the **AI chat**. **[WEB — ai-tracking-how-does-it-work]**

| Method | User action | Free/Premium |
|---|---|---|
| **AI text/chat** | Type a meal ("chicken salad with rice") | Premium |
| **Voice** | Mic in chat, hands-free | Premium |
| **Photo / image recognition** | Camera → photograph dish | Premium |
| **Barcode** | AI on: "+" → barcode; AI off: meal → barcode icon; manual number entry + flash | Free* (see §14 conflict) |
| **Text search (DB)** | "Search Food" → DB + your Favorites | Free |
| **Quick Track (quick-add cals)** | Meal → ⋯ → Quick Track → calories (+optional macros/title) | Free |
| **Recents** | One-tap re-track recent items | Free |
| **Favorites** | Saved/self-created items | **Premium** ⭐ MISSED |
| **Same as Yesterday** | Re-track prior day's meal, per meal-type | Free |
| **Smart Suggestions** | AI row of "foods you frequently log at that time of day" | Premium |

- **The multimodal "+" flow** unifies text/voice/photo/barcode + Recents/Favorites/Quick Track/Search into one chat surface. **[WEB]**
- **AI correction flow (natural language):** open the logged entry → **"Add more food"** → chat reopens → "add milk", "replace rice with quinoa". Portions "estimated based on input", manually adjustable per ingredient after logging. **[WEB — multimodal-tracking-explained]**
- **Copy meal between days:** the ONLY documented copy is **"Same as Yesterday"** (prev-day → today, per meal). ⭐ MISSED — there is **no documented arbitrary date-X→date-Y copy** and the older multi-select-from-recents was **removed** in the AI redesign. **[WEB]**
- **Edit/delete item:** expand meal → iOS swipe-left / Android long-press or ⋯ → Delete → confirm; open item to change quantity. **Past-day editing** works because the diary is date-navigable (no documented restriction). **[WEB/INFER]**
- The `track/copy/{from}/{to}/{meal_type}` and `track/quick`, `track/recipe`, `track/food/{date}` endpoints in the APK confirm server-side plumbing for these. **[APK]**

**HUMANS today:** **Parity, Ahead in places.** HUMANS' single AI composer + 8 entry points ≈ Lifesum's chat; HUMANS is **Ahead** on portion picker (½/1/1.5/2×), confidence display, whole-day copy-yesterday, and lower signup friction (Sign in with Apple, AI not paywalled). Lifesum is **Behind** in one respect that matters: it **paywalls its own AI + Favorites**. HUMANS' barcode is a separate entry (Lifesum folds it into chat) — **minor Behind**.

---

## 4. Food Database ("Foodipedia")

**What Lifesum does:**
- **Six sources:** USDA (US), **MyNetDiary** (licensed), UK Food Standards Agency, Bundeslebensmittelschlüssel (Germany), Livsmedelverket (Sweden), user-created foods. **[WEB — help.lifesum.com/lifesums-food-database]**
- **Size:** ~**2M entries** (smaller than MyFitnessPal / FatSecret / Lose It!); marketing says "millions". **[WEB — review aggregation]**
- **Verified items = blue badge**; editorial team curates thousands of verified foods, bulk is user-submitted. **[WEB]**
- **User submissions/edits:** Report button on an item (+ email support with barcode photo & correct nutrition). Premium users create "your own version" via Progress → Favorites. **Verified items can't be user-edited.** ⭐ MISSED: **Report does NOT work on AI/multimodal-tracked items** — a real moderation blind spot. **[WEB]**
- **Restaurant/branded:** barcode covers packaged goods; **restaurant-chain menu coverage is undocumented and likely thin** vs MyFitnessPal. **[UNVERIFIED]**

**HUMANS today:** **Gap** on data moat (USDA/OFF proxy, no proprietary DB, no verification loop) — but this is a known deferred decision. The exploitable angle: Lifesum's DB is smaller than MFP, unverified in bulk, and its AI-tracked items are excluded from the report/correction loop.

---

## 5. Nutrition Model & Scores

**What Lifesum does:**
- **Macros:** carbs, protein, fat + **net carbs**. Custom macro goals are **Premium**; macro *breakdown itself is Premium-gated* (calorie count is free). ⭐ MISSED — macros behind paywall is unusually aggressive. **[WEB]**
- **Net-calorie model by default:** burned calories (logged/synced) are added back to the goal; toggle **"Burned calories included"** off in Diary Settings. ⭐ MISSED. **[WEB — exclude-exercise-calories]**
- **Nutrient breadth:** calories, carbs, fiber, sugar (incl. added), fat, saturated fat, unsaturated fat, cholesterol, sodium, potassium, protein (~22 nutrients). **No individual vitamins/micros** (no vit C/iron/calcium) — a gap vs Cronometer. Sodium/fiber/cholesterol/potassium detail is effectively Premium. **[WEB — nutrition-tracker]**
- **Food/Meal/Day rating (three-level, plan-aware):** per-item rated **per 100 kcal** (keto: carbs per 100 g), inputs = protein/unsat-fat/fiber (increase) vs sat-fat/salt/sugar (minimize) + carbs + calorie density + food type; checkmark/x feedback; top tier "High Nutritional Value". Meal rating adds portion-size + guideline distribution; Day rating combines meals and tolerates "comfort food in moderation". Re-weights per active program (Standard/Keto/Fasting/Clean Eating/Scandinavian/Mediterranean; High Protein rewards >8 g protein/100 kcal). ⭐ MISSED — three-level structure + per-100-kcal normalization + NOT A–E. **[WEB — food-rating, helpshift 196]**
- **Life Score™:** **weekly**, **0–150**, **16 nutrition+exercise metrics**, five bands (Optimal 120–150 / Great 90–120 / Good 60–90 / Imbalanced 30–60 / Off Track 0–30), **updates every Monday** with WoW delta, seeded by the 41-Q Health Test. **Premium.** ⭐ MISSED (exact bands + Monday cadence + Health-Test seeding). **[WEB — life-score-ios; APK: `health-score/generate-weekly-score`]**

**HUMANS today:** **Parity/Ahead.** HUMANS already has 6-signal food rating, full nutrient breadth, and energy-balance (eaten vs watch burn = **Ahead** — Lifesum has no daily recovery concept). Lifesum is **Behind vs HUMANS conceptually** by *gating macros* — HUMANS should keep calories+macros free and gate elsewhere. HUMANS is **Behind** on: plan-aware rating (ours is static), the three-level (item/meal/day) rating granularity, and Life Score's whole-lifestyle weekly composite (ours is daily). The net-calorie toggle is a small, cheap parity item.

---

## 6. Water & Habits

**What Lifesum does:**
- **1-tap trackers** for water, fruit, vegetables (and fish); water + exercise are **free**. Configurable water goal + reminder pushes. Water writes to Health Connect/Apple Health. **[WEB/APK]**
- **Habit tracking:** `android.settings.habits`, habit diary card. Fruit/veg/fish trackers feed Life Score and are **auto-disabled while a meal plan is active**. ⭐ MISSED. **[WEB]**

**HUMANS today:** **Parity** on water. Habit-card breadth is a **minor Behind** but not strategic.

---

## 7. Fasting

**What Lifesum does:**
- **Fasting timer** + eating-window logging; feeds weekly Life Score. Protocols: **16:8 (morning & evening), 5:2, 6:1**. 5:2 caps intake at **500 kcal (women)/600 kcal (men)** on 2 days; 6:1 = one fast day/week. Fasting timer + protocols are **Premium**. **[WEB — how-it-works, list-of-plans]**

**HUMANS today:** **Parity** (HUMANS has 5:2/16:8 + timer). Lifesum adds 6:1 and specific 500/600-kcal caps — trivial to match. HUMANS is **Ahead** by not paywalling the timer.

---

## 8. Diet Plans / Programs

**What Lifesum does:** ⭐ MISSED — the "~44 plans" figure in prior docs is **not confirmed**; the authoritative help list yields **~24 core entries** (13 Programs + 11 Meal Plans), fanning to ~38 across the three goals. The 44 almost certainly counted goal-variants. **[WEB — list-of-all-programs-meal-plans]**

| Type | Entries |
|---|---|
| **Programs (13)** | Lifesum Standard, Clean Eating, High Protein, Mediterranean, Scandinavian, Climatarian, Vitality, Food For Strength, Ketogenic Easy/Medium/Strict, 5:2, 6:1 |
| **Meal Plans (11)** | Paleo, Sugar Detox, Eat like Denice, 3 Weeks Weight Loss, Keto Burn, Keto Maintain, Vegan for a Week, Protein Weight Loss, Hormonal Balance, 16:8 Morning Fasting, 16:8 Evening Fasting |

- Availability is **goal-scoped** (e.g. Food For Strength only Maintain/Gain; High Protein absent from Gain). **[WEB]**
- **Starting a plan changes 3 systems:** macro targets + food/meal/day rating logic + surfaced recipes/meal suggestions; also **disables Veg/Fruit/Fish trackers** while active. **[WEB]**
- **Programs (ongoing approach) vs Meal Plans (fixed pre-planned menus).** New users default to free **Lifesum Standard**; the rest are **Premium**. **[WEB]**
- APK confirms server plumbing: `plans/{id}/choose`, `usermealplans`, `usermealplans/{id}/overridemeals`, `usermealplans/{id}/reset`. **[APK]**
- **"Plan Store" naming is [UNVERIFIED]** — help docs call it the Programs/Meal Plans catalog; "PLAN_STORE" is an APK string. **[APK/WEB]**

**HUMANS today:** **Behind** on count (10 vs ~24) and on "start plan changes 3 systems" (ours changes targets + recipe match, not rating). **Parity** on per-slot overrides + persistence. Realistically, ~24 (not 44) is a much closer target than we thought.

---

## 9. Meal Plans (mechanics) & 10. Recipes

**Meal-plan mechanics:**
- Pre-planned menus, **~21-day** with ~4 pre-planned meals/day (marketing-sourced, **[PARTLY UNVERIFIED]**). Meal **swaps allowed** (can push macros over target). Framed as **flexible guidelines, explicitly "not tailored to your specific goals"** — ⭐ MISSED: **non-adaptive**. "Eat this every day" recurring toggle. **Grocery/shopping list** generated per plan (detail sparse). **[WEB]**

**Recipes:**
- Official site says **"hundreds"** of recipes ("new ones added all the time"). ⭐ MISSED — the "thousands"/"1,000+"/"~228" figures in prior docs are **[UNVERIFIED]**; Lifesum's own copy says hundreds. **[WEB — lifesum.com/features]**
- Each recipe: **image**, calories/macros/serving size, **one-tap log**, keyed to active plan, **smart filters**. APK: `RecipeApi`/`RecipeTagApi`. **[WEB/APK]**

**HUMANS today:** **Behind** on recipe count (48 vs "hundreds") and images (ours are icons — **Gap**), and on server-driven meal plans (ours client-side persisted+synced). **BUT** Lifesum's plans being *non-adaptive* narrows the real gap — an adaptive HUMANS plan could be a genuine differentiator. HUMANS **Parity** on one-tap log + per-slot swap.

---

## 11. Progress & Stats

**What Lifesum does:**
- **6 built-in body measurements:** Weight, Waist, Body fat, Chest, Arm, BMI + up to **4 custom (Premium)**. Weight+Waist free. History graphs per measurement; dated weight list; back-dating supported. **[WEB — body-measurements]**
- **Weekly recap = Life Score** (no separate email recap evidenced). ⭐ MISSED — **no dedicated progress-photo (before/after body-photo) feature**; Lifesum's only "photo" is meal-photo logging. **[WEB/INFER]**
- **Streaks:** present as "gentle nudges" (esp. fasting), not a hard gamified counter. **[WEB]**

**HUMANS today:** **Ahead** on daily recovery glance + "drivers" trend layer (Lifesum has neither). **Parity** on weight/measurements. **Open lane for both:** progress photos, weekly email recap.

---

## 12. Health Integrations

**What Lifesum does:**

| Apple Health | Direction |
|---|---|
| **Lifesum → HealthKit (writes)** | Food calories, Food nutrition, Weight, Water intake |
| **HealthKit → Lifesum (reads)** | Exercise calories, Steps, Active Calories, Exercise Time, Workouts, Weight |

- Only **Weight** is genuinely bidirectional; the rest are complementary one-way categories. Per-metric consent at setup. Third-party devices (**Oura, Withings, Runkeeper**) route **via Apple Health** on iOS. **[WEB — Apple Health article + App Store listing]**
- **Health Connect (Android):** writes Nutrition + Hydration; reads Exercises, Total calories burned, Steps. Fitbit/Samsung Health/Oura/Google Fit connect **via Health Connect**. **[WEB]**
- ⭐ **MISSED — food logged via Multimodal AI is NOT sent to Health Connect** ("currently not sent") — a data-portability gap in their flagship feature; by inference may affect Apple Health export too. **[WEB]**
- **Partners framework** (APK `v2/partners`): register→authenticate→settings→trigger→disconnect for Google Fit, Health Connect, Samsung Health, Oura, Polar (+ apple_health enum). **Garmin** ambiguous (iOS troubleshooting only, not on features page); **Polar** no confirmed integration. ⭐ correction to prior "Oura/Polar/Samsung/Fit". **[APK/WEB]**
- **Exercise logging** inside the app: yes, free tier; exercises savable as Favorites. **[WEB]**

**HUMANS today:** **Behind** — HUMANS is HealthKit read-only; Lifesum writes nutrition/water/weight back. Two-way write (esp. nutrition→HealthKit) is a concrete parity item. HUMANS is **Ahead** on the recovery/strain/sleep data half that Lifesum lacks entirely. Exploit: Lifesum's AI-logged food doesn't even reach Health Connect — a privacy/portability angle.

---

## 13. Reminders / Notifications / Re-engagement

**What Lifesum does:**
- **Water reminders** (configurable), meal reminders, per-plan meal feedback. Settings → Notification Settings with per-type toggles. **[WEB]**
- Early **notification opt-in** styled to mimic a system prompt (App Fuel). Late **ATT prompt**. **[WEB]**
- **APK re-engagement stack:** **MoEngage** CRM + **FCM** push + email; **AiTrackingBanner** ("DIARY_AI_TRACKING"), **ShowAiTrackingDefaultMethodPrompt** ("make AI your default", Accepted/Declined events), onboarding for AI tracking. ⭐ MISSED — the "make AI default" prompt is an explicit instrumented conversion mechanic. **[APK]**

**HUMANS today:** **Behind** on server-lifecycle CRM (MoEngage) and the instrumented "make AI default" nudge; HUMANS has local notifs + meal reminders. **Ahead** on retention breadth (widget/breathing/coach/multi-domain).

---

## 14. Widgets / Complications / Apple Watch

**What Lifesum does:**
- **Apple Watch app** — displays macros (fat/carbs/protein) + calorie/goal glance after phone logging; meal & weigh-in reminders; **complication support**. iOS 16+. **[WEB — helpshift Watch FAQ (cached) + App Store listing]**
- **iOS widgets + Watch complications** exist; both depend on **background app refresh** — documented pain point: throttled refresh → **stale calorie totals in widget/complication**. ⭐ MISSED. **[WEB — reviews]**
- **On-wrist logging depth is [UNVERIFIED]** (dedicated Watch FAQ 404'd). **Android home-screen widgets: [UNVERIFIED]**; Wear OS supported.

**HUMANS today:** **Ahead** — HUMANS has home-screen widget + Lock Screen/Watch complications for readiness/HUMANS Score (accessory widgets). Lifesum's are present but stale-prone. HUMANS should ensure timely widget refresh (the exact thing Lifesum gets dinged for).

---

## 15. Premium & Monetization

**What Lifesum does:**
- **US App Store IAP (live):** Monthly **$7.49** · 3-month **$14.99** · Annual **$49.99** (some sources cite $44.99 best rate; promos to ~$30.99; list up to $99.99 in some markets). All three marked **"Trial"**; length unpublished (**7 days** commonly cited, region-varying). ⭐ MISSED — the **3-month $14.99** SKU. **[WEB — App Store listing]**
- **Family Plan ~$59.99/yr for up to 5 users** — ⭐ MISSED, but **sources conflict** (one says no family plan); **[WEB/UNVERIFIED]**.
- **No lifetime option** found. **[INFER]**
- **Free tier is permanent + ad-supported** (banners, interstitials, in-diary ads). **[WEB]**
- **Gated behind Premium:** macros/macro breakdown, full recipe library, all Programs+Meal Plans (except free Lifesum Standard), meal plans+shopping lists, meal/food-fit rating, **Multimodal AI logging**, Favorites, fasting timer/protocols, custom macros, detailed per-nutrient breakdown, ad-free. **Free:** calorie logging, text search, quick-track, recents, water, exercise logging, weight+waist, 1 plan. ⭐ MISSED — **macros AND their own AI are paywalled** (aggressive). **[WEB]**
- **Barcode free-vs-paywalled: CONFLICT** — features page says free; some 2026 reviews say gated → possible A/B test. Flag for monitoring. **[WEB — CONFLICT]**
- **Stack (APK):** **RevenueCat** (remote paywalls + A/B, via `api-paywalls.revenuecat.com`; the "8-lives-cat" failover) + Play Billing + `v2/purchase` validation; **Amplitude** analytics **with session replay** (EU-hosted); **Adjust** attribution + install-referrer + FB SDK + Privacy Sandbox; **Firebase Remote Config** for flags/paywall AB. **[APK]**

**HUMANS today:** **Gap** (parked) — no live pricing, no paywall, no analytics/attribution/session-replay/lifecycle-CRM. HUMANS is **Ahead** on privacy (zero third-party trackers — a sellable position vs Lifesum's heavy stack + consent friction). Strategic read: Lifesum gates *basics* (macros, own AI) — HUMANS' proposed split (calories+macros free, metered AI free→unlimited Pro, never ads) is a cleaner, more generous position at ~$39.99/yr pushed.

---

## 16. Social Proof & Store Presence

**What Lifesum does:**
- iOS **4.6★ / ~151K ratings (US)** + Apple **Editors' Choice**; Google Play **~4.4★ / ~370K reviews / 25–30M installs**, #2 Health & Fitness. **[WEB — store listings]**
- **"65 million users"** claim (50M in Apr 2021 → 65M). Testimonials on site ("lost 7 lbs first week"). **[WEB]**
- ⭐ **Reputational risk:** the Feb-2025 AI multimodal launch **dominates recent negative reviews** — misidentification (cashews→shrimp), phantom logs (coffee from a background mug), barcode double/triple counting, ±6.5–7.3% calorie deviation, homemade-dish swings 300–500 kcal, "no in-app fix for wrong scanned data", removed per-meal calories, forced logouts. Sentiment: "fixed something that wasn't broken." **[WEB — App Store reviews + review sites]**

**HUMANS today:** **Gap** on store credibility/social proof (parked). The clear attack surface: **AI accuracy + portion estimation + not hiding per-meal calories** — HUMANS' confidence display + portion picker already target exactly Lifesum's weak spot.

---

## 17. Account, Sync, Settings, Data/GDPR

**What Lifesum does:**
- Cloud account, cross-device sync ("Lifesum Connect"); APK: `sync/check|read|update`, `convert_anonymous_user`, `changepass`, `recoverpass`. Units metric/imperial. **[WEB/APK]**
- ⭐ **Data export = only the past 7 days** of nutritional data (self-serve); **full-history export is support-request-only**. A meaningful portability limitation. **[WEB — knoji; help.lifesum.com export article]**
- **Reset Data** (Settings → Account Settings) wipes weight/measurements/diary but keeps "My Things". **GDPR:** honors deletion/erasure requests; consent via **Usercentrics** (APK). **[WEB/APK]**

**HUMANS today:** **Ahead on privacy posture** (no trackers, no consent friction). Neither has strong self-serve full export — HUMANS could differentiate with real export/portability given AI-logged Lifesum food doesn't even reach Health Connect.

---

## 18. Tech Stack & Backend

**What Lifesum does [APK]:**
- **Native Android Kotlin, mid-migration to Jetpack Compose** (MVI: Contract/State/Event/SideEffect per feature under `com.lifesum.android.*`), **+ a React Native layer** (`index.android.bundle` = Hermes bytecode) for onboarding, paywalls, AI chat, testimonials, carousels — using **RN Vision Camera + Skia frame processors**, Reanimated, Gesture Handler. **Three UI generations** coexist (a source of the "inconsistent" feel).
- **On-device ML Kit** barcode; bundled **SQLite food DB** (`ishape11database.sql`) for offline non-AI.
- **AI microservice:** a dedicated backend that ingests text/voice/photo/barcode and returns structured foods (APK strings reference OpenAI + Gemini). **Vendor/codename NOT publicly disclosed** — and it is **NOT** "8-lives-cat" (that's RevenueCat; see top correction). **[APK/WEB]**
- **Backend API:** `https://api.lifesum.com/v2/` — accounts/auth, `date/{date}`, `track/food|meals|quick|recipe|copy/{from}/{to}/{meal_type}`, `diary/meal_photo`, `foodipedia/food|edit_food|report_food`, `plans/*`, `usermealplans/*`, `health-score/generate-weekly-score`, `partners/*`, `sync/*`, `purchase`. **[APK]**
- **Growth/infra SDKs:** RevenueCat, Amplitude (+session replay), Adjust, MoEngage+FCM, Firebase Remote Config/Crashlytics, Usercentrics, Facebook SDK, Google Play Review API. **[APK]**

**HUMANS today:** **Ahead on platform fit** (100% native SwiftUI vs Lifesum's 3-generation hybrid with RN seams). **Gap** on the growth/measurement stack (parked; HUMANS' privacy-clean first-party funnel on Fly.io is the intended answer).

---

## Prioritized Gap List

Effort: **S** = days / no backend · **M** = weeks · **L** = backend/strategic. HUMANS-relative.

### P1 — do next (high signal, mostly cheap)
| # | Gap | Why | Effort |
|---|---|---|---|
| 1 | **Two-way HealthKit write** (nutrition, water, weight → Apple Health) | Lifesum's clearest integration edge; HUMANS is read-only | M |
| 2 | **Net-calorie toggle** ("include burned calories" on/off) | Trivial parity with Lifesum's default model | S |
| 3 | **"Make AI your default" prompt + instrument adoption** | Lifesum's explicit conversion mechanic; HUMANS has the pieces | S |
| 4 | **Wire RevenueCat paywall + Pro gates + trial** (metered AI free→unlimited, macros stay FREE, ~$39.99/yr pushed) | The parked revenue unlock; beat Lifesum by NOT gating basics | M |
| 5 | **Social-proof + "building your plan" onboarding screens** | Lifesum's activation edge; HUMANS has none | S |
| 6 | **Guarantee timely widget/complication refresh** | Exactly what Lifesum gets dinged for (stale totals) | S |

### P2 — high-impact
| # | Gap | Why | Effort |
|---|---|---|---|
| 7 | **Plan-aware food rating** (re-weight under keto/high-protein/etc.) | Lifesum's signature moat; ours is static | M |
| 8 | **Three-level rating (item / meal / day)** incl. portion+distribution at meal level | Matches Lifesum granularity | M |
| 9 | **Recipe images + expand 48 → ~150** with multi-axis filters | Lifesum "hundreds" w/ photos; ours icons | M |
| 10 | **Barcode into the AI composer** (fold in, like Lifesum chat) | Close the one logging-UX Behind | M |
| 11 | **Weekly whole-lifestyle composite recap** (nutrition+activity+water, WoW delta) | Lifesum Life Score cadence; ours daily-only | M |
| 12 | **One-question-per-screen cadence + goal branching** in onboarding | Lifesum momentum | M |
| 13 | **Privacy-clean first-party analytics funnel** (Fly.io, no third-party tracker) | Measurement without abandoning the privacy edge | M |

### P3 — strategic / backend
| # | Gap | Why | Effort |
|---|---|---|---|
| 14 | **Adaptive meal plans** (Lifesum's are explicitly non-adaptive) | Genuine differentiator, not just parity | L |
| 15 | **Proprietary/verified food DB + user-submission loop** | Lifesum's retention moat (but its bulk is unverified) | L |
| 16 | **Server lifecycle CRM** (streak-save, lapse win-back, trial-ending) | Match MoEngage-class hooks on own server | L |
| 17 | **Real full-history data export/portability** | Beat Lifesum's 7-day-only + AI-not-synced weakness | M |
| 18 | **Progress photos + weekly email recap** | Open lane — neither app has photos | M |

---

## Executive Summary

Lifesum is a mature, funnel-optimized nutrition tracker whose genuine moats are its **plan-aware three-level food rating** (per-100-kcal, re-weighted by active diet), its **weekly 0–150 Life Score** composite, a **~2M-source Foodipedia**, ~24 diet programs/meal plans, and a **textbook growth/monetization stack** (RevenueCat remote-A/B paywalls, Amplitude+session-replay, Adjust, MoEngage) — but it is **not** the product our prior docs described in several load-bearing specifics: its rating is **not Nutri-Score A–E**, the "8-lives-cat" backend is **RevenueCat, not its AI**, it has **~24 (not 44) plans**, "**hundreds**" (not thousands) of recipes, and it **paywalls its own basics** — macros, Favorites, and even its flagship Multimodal AI logging — while its Feb-2025 AI relaunch is the dominant source of recent 1-star reviews (misidentification, defaulted portions, removed per-meal calories, AI-logged food that doesn't even sync to Health Connect, 7-day-only export). The strategic read for HUMANS is unchanged but sharper: match the cheap parity items (two-way HealthKit, net-calorie toggle, plan-aware/three-level rating, recipe images, a paywall that gates AI-metering rather than basics), and press the privacy + accuracy + portion + timely-glance advantages precisely where Lifesum is weakest.

---

_Areas covered: **18** (all requested). Sources: 20.10.0 APK teardown + Sep-2026 web research (help.lifesum.com, lifesum.helpshift.com, lifesum.com, Apple App Store id286906691, Google Play com.sillens.shapeupclub, pageflows.com, review aggregators). Facts tagged [APK]/[WEB]/[INFER]/[UNVERIFIED] inline._
