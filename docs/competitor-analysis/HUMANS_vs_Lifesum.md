# HUMANS vs Lifesum — Deep Analysis (parked reference)

_Snapshot as of **HUMANS build 42** vs **Lifesum 20.10.0**. Grouped by Key Function → Sub-function.
Rows marked ⬆ improved in builds 38–42. Sources: full Lifesum APK teardown +
web research (see `~/Downloads/Lifesum_20.10.0_Analysis.md` and
`~/Downloads/HUMANS_vs_Lifesum_DeepAnalysis.md`)._

## Status legend
- **Ahead** = HUMANS is deeper · **Match** = parity · 🟡 **Behind** = Lifesum somewhat deeper · ❌ **Gap** = Lifesum has it, we don't (or a big gap)

## Full comparison (67 rows)

| # | Function / Sub-dimension | Lifesum | HUMANS | Verdict |
|---|---|---|---|---|
| **AI MEAL LOGGING** | | | | |
| 1 | Photo / library logging | ✅ | ✅ | Match |
| 2 | Voice logging | ✅ | ✅ SFSpeech (on-device) | Match |
| 3 | Text logging | ✅ | ✅ | Match |
| 4 | Barcode into the AI flow | ✅ inside chat | 🟡 separate entry | 🟡 Behind |
| 5 ⬆ | Unified single surface | ✅ multi-turn chat | ✅ "Log with AI" composer (primary) | Match |
| 6 ⬆ | Correction / iteration | ✅ chat follow-up | ✅ "Not quite? Adjust it" re-estimate | Match |
| 7 | Confidence surfaced | ❌ | ✅ shown | Ahead |
| 8 | AI model | ✅ OpenAI+Gemini | ✅ Claude | Match |
| 9 ⬆ | Portion refinement | ❌ standard serving | ✅ ½/1/1.5/2× picker | Ahead |
| 10 ⬆ | AI as the default | ✅ aggressive | 🟡 hero + nudge + instrumented | 🟡 Behind |
| 11 ⬆ | Offline non-AI logging | ✅ bundled DB | ✅ 85-food DB + local search | Match |
| 12 | Signup friction to try AI | 🟡 account | ✅ Sign in with Apple | Ahead |
| **FOOD DATA & QUALITY** | | | | |
| 13 | Proprietary food DB | ✅ Foodipedia | ❌ USDA/OFF proxy | ❌ Gap |
| 14 | Verified / moderated | ✅ | ❌ (deferred) | ❌ Gap |
| 15 ⬆ | Offline food DB | ✅ full bundled | 🟡 85 curated core | 🟡 Behind |
| 16 ⬆ | Nutrient breadth (fibre/sugar/sodium/sat-fat) | ✅ | ✅ 6-signal | Match |
| 17 ⬆ | Food rating A–E | ✅ 6-nutrient | ✅ 6-signal | Match |
| 18 ⬆ | Rating inputs depth | ✅ | ✅ | Match |
| 19 | Plan-aware rating | ✅ | ❌ static | ❌ Gap |
| 20 | Aggregate diet score | ✅ weekly 0–150 | 🟡 daily Life Score 0–100 | 🟡 Behind |
| 21 | Macros + targets | ✅ | ✅ | Match |
| 22 | Calorie / energy balance | 🟡 | ✅ eaten vs watch burn | Ahead |
| 23 | Water tracking | ✅ | ✅ | Match |
| **PLANS & RECIPES** | | | | |
| 24 | Diet programs (count) | ✅ ~44 | 🟡 10 | 🟡 Behind |
| 25 | Fasting (5:2 / 16:8) | ✅ | ✅ + timer | Match |
| 26 | What "start plan" changes | ✅ 3 systems | 🟡 targets + recipe match | 🟡 Behind |
| 27 ⬆ | Adaptive / persisted meal plans | ✅ server-driven | 🟡 persisted + synced (client) | 🟡 Behind |
| 28 ⬆ | Per-meal overrides + persistence | ✅ | ✅ per-slot swap, saved | Match |
| 29 ⬆ | Recipes (count) | ✅ ~228 | 🟡 48 | 🟡 Behind |
| 30 | Recipe images | ✅ photos | ❌ icons | ❌ Gap |
| 31 | Recipe filtering | ✅ multi-axis | 🟡 category + plan | 🟡 Behind |
| 32 | One-tap recipe log | ✅ | ✅ | Match |
| **ONBOARDING & ACTIVATION** | | | | |
| 33 | Flow pacing | ✅ light + branching | 🟡 9 dense screens | 🟡 Behind |
| 34 | Personalization input breadth | 🟡 | ✅ (~45, mood/meds) | Ahead |
| 35 | Inputs → living content | ✅ | 🟡 | 🟡 Behind |
| 36 ⬆ | Uses med/mood signal | 🟡 doesn't collect | ✅ eases deficit + med notes | Ahead |
| 37 | Visual polish | ✅ photography + Lottie | 🟡 utilitarian forms | 🟡 Behind |
| 38 | Feature explainers / previews | ✅ | ❌ (parked) | ❌ Gap |
| 39 | Social proof (testimonials/ratings) | ✅ | ❌ (parked) | ❌ Gap |
| 40 | Store credibility (4.6★/151K/EC) | ✅ | ❌ | ❌ Gap |
| 41 | Health connect (2-way) | ✅ read+write | 🟡 read only | 🟡 Behind |
| 42 | Onboarding paywall | ✅ | ❌ (parked) | ❌ Gap |
| 43 | Speed to first "aha" | ✅ plan + AI moment | 🟡 goal + HUMANS Score | 🟡 Behind |
| **MONETIZATION & GROWTH** | | | | |
| 44 | Live pricing / tiers | ✅ | ❌ (parked) | ❌ Gap |
| 45 | Free vs premium gating | ✅ | ❌ (parked) | ❌ Gap |
| 46 | Remote + A/B paywall | ✅ | ❌ (parked) | ❌ Gap |
| 47 | Product analytics | ✅ Amplitude | ❌ (aiLogCount only) | ❌ Gap |
| 48 | Session replay | ✅ | ❌ | ❌ Gap |
| 49 | Attribution / paid UA | ✅ | ❌ | ❌ Gap |
| 50 | Lifecycle CRM push | ✅ MoEngage | 🟡 local notifs + meal reminders | 🟡 Behind |
| 51 | In-app review prompt | ✅ | ❌ | ❌ Gap |
| 52 | Streaks | ✅ | ✅ | Match |
| 53 | Retention feature breadth | 🟡 food-only | ✅ widget/breathing/coach/celebrations | Ahead |
| 54 | Referral / share loop | ❌ | ❌ (parked) | Both lack |
| 55 | Privacy (no third-party trackers) | 🟡 heavy stack | ✅ zero trackers | Ahead |
| **UX / IA / INTERACTION** | | | | |
| 56 | Daily recovery glance | ❌ | ✅ 0-tap on Today | Ahead |
| 57 | Diet-plan depth (Plan Store/shopping) | ✅ | 🟡 | 🟡 Behind |
| 58 | Drill-down consistency | 🟡 3 UI gens | ✅ uniform | Ahead |
| 59 | Trend "drivers" (explains *why*) | 🟡 | ✅ | Ahead |
| 60 ⬆ | Single synthesized score | ✅ weekly | ✅ daily HUMANS Score | Match |
| 61 | Motion / delight | ✅ Lottie/Reanimated | 🟡 restrained + reward pop | 🟡 Behind |
| 62 | Design-system maturity | ✅ proven | 🟡 young | 🟡 Behind |
| 63 | Design distinctiveness | 🟡 | ✅ cohesive glass | Ahead |
| 64 | Native platform fit / a11y | 🟡 hybrid RN | ✅ 100% native | Ahead |
| 65 | Home-screen widget | ❌ | ✅ | Ahead |
| 66 ⬆ | Lock Screen / Watch complication | ❌ | ✅ accessory widgets | Ahead |
| 67 | Designed empty states | ✅ | 🟡 | 🟡 Behind |

## Tally — before vs now

| Verdict | Build 37 | Build 42 | Δ |
|---|---|---|---|
| Ahead (HUMANS deeper) | 12 | 15 | +3 |
| Match | 9 | 17 | +8 |
| 🟡 Behind | 18 | 19 | +1 |
| ❌ Gap | 24 | 15 | −9 |
| Both lack | 4 | 1 | — |

## What remains (the 15 ❌ gaps), classified
- **Parked by decision (11):** monetization (live pricing, free/premium gating, remote+A/B paywall, product analytics, session replay, attribution/paid UA, in-app review = 7 + onboarding paywall) and onboarding social proof (feature explainers, testimonials, store credibility).
- **Deferred, weak near-term ROI (2):** food-verification/user-submission moat; plan-aware food rating.
- **Un-parked content/backend (2):** proprietary food DB; recipe images.

**Net:** every gap that isn't monetization, social proof, or a data-moat backend is now closed or matched.

## Parked backlog (to revisit)
When ready to resume, the two clusters to pick up are:
1. **Monetization** — wire the scaffolded RevenueCat: paywall + Free/Pro gates (metered AI 3/day, macros Pro) at ~$39.99/yr + 7-day trial; remote A/B; privacy-clean first-party funnel on Fly.io; referral/share-card loop (open lane — neither app has it).
2. **Onboarding activation** — social proof (testimonials + ratings + store credibility), feature-explainer/"building your plan" screens, one-question-per-screen cadence + goal branching.

Deferred: food-verification moat, plan-aware rating, recipe photos, proprietary food DB.

_Change log: builds 38 (6-signal rating + server), 39 (AI-default nudge, reward motion), 40 (AI correction turn, portion picker, HUMANS Score, Lock Screen widgets), 41 (med/mood signal, offline food DB, recipes→48), 42 (persisted meal plan + per-slot swap + sync)._
