# Physical Age — Peer-Reviewed Evidence Dossier

*HUMANS / FatLoss Coach · prepared by the Clinical Validation Scientist · 2026-09-29*
*Draft — internal. Pending Head of AI/ML review and CEO approval before any external use.*

---

## 0. How to read this dossier (scope and the honest headline)

**What this document is.** A component-by-component mapping of the HUMANS "Physical Age"
model (`FatLossCoach/Core/BodyMetrics.swift`, `fitnessAge(...)` and the `weeklyProgramme(...)`
engine) to the strongest available clinical evidence. Every citation was checked against the
primary source or a reputable secondary report; where an exact effect size could not be
verified against the primary paper in this pass, it is flagged **[TO VERIFY]**.

**The one thing the CEO must take away — the causal ceiling.** There are two different claims,
and only one of them is supported:

| Claim | Status |
|---|---|
| "Each metric in the model has a **strong, large-cohort / meta-analytic association with all-cause mortality**" | **SUPPORTED** — this is what the literature below establishes. |
| "Improving your number is **clinically proven to extend your lifespan**" | **NOT SUPPORTED by RCT.** Most of the underlying evidence is observational (prospective cohorts + meta-analyses of cohorts). Association ≠ causation. |
| "The **composite Physical Age score** is a validated clinical instrument / biological age" | **NOT SUPPORTED.** No composite wearable effective-age score (WHOOP Age, Hume, or ours) has been validated against an outcome cohort or an epigenetic clock by RCT. It is a **motivational estimate**, not a diagnostic or a life-expectancy prediction. |

This is not a hedge — it is the defensible scientific position, and it is the position that
**protects our claims posture** (we just passed a regulatory copy review that forbids
lifespan / medical / diagnostic claims). Every user-facing surface must keep the model
framed as a *fitness estimate*, never a "biological age", "normal range", diagnosis, or
lifespan predictor. The model's own code already does this (`FitnessAge` doc-comment:
"A motivational fitness-age estimate … NOT a clinical biological age"; the training-engine
note "WELLNESS logic only … not a clinical/biological age") — this dossier is the evidentiary
backing for keeping it that way.

**Evidence grading key used throughout.**

| Grade | Meaning |
|---|---|
| **A** | Meta-analysis of prospective cohorts, or multiple large prospective cohorts, consistent direction, >100k participants. Association robust; causation not proven by design. |
| **B** | Single large prospective cohort, or meta-analysis with heterogeneity / measurement caveats. |
| **C** | Cross-sectional, retrospective, or mechanistic/indirect evidence; or a coefficient that is an internal approximation rather than a directly-cited effect size. |
| **RCT-partial** | Some randomised-trial evidence exists for the *behaviour* (e.g. exercise improves fitness) but not for the *mortality endpoint via the composite score*. |

---

## 1. The method itself: effective age from all-cause-mortality hazard ratios

### 1.1 What the model does (from the code)

`Physical Age = chronological age + Σ (per-metric age impact)`, where each metric's impact in
years = **10 · ln(HR)**, HR being that metric's all-cause-mortality hazard ratio versus a
**health-optimized referent** (a value meeting public-health guidelines, not the population
average). Impacts are summed (not averaged), each clamped to a per-metric cap, and the total is
clamped to ±15 years (`BodyMetrics.fitnessAge`, lines ~354–452). Because the referent is
health-optimized, an *average* person correctly comes out **older** than their chronological
age — this is a deliberate, defensible design choice, not a bug.

### 1.2 Is the method sound and published?

**Yes — the translation is published and mathematically standard.** The "effective age"
construction rests on two premises:

1. **Gompertz law of mortality** — after early adulthood, all-cause mortality risk rises
   approximately log-linearly, roughly **+10% per year** (doubling every ~8–10 years). This is
   one of the oldest and best-replicated regularities in demography.
   - Gompertz B. (1825), foundational. Olshansky SJ, Carnes BA. **Ever since Gompertz.**
     *Demography.* 1997;34(1):1-15. Kirkwood TB. *Philos Trans R Soc Lond B.* 2015;370(1666).
     doi:10.1098/rstb.2014.0379. **Grade A** (established demographic law).
2. **HR → effective-age translation.** If baseline hazard grows at rate `c` per year of age
   (c ≈ 0.10 for all-cause mortality) and an exposure multiplies hazard by HR, then the
   equivalent age shift `t` solves `e^{ct} = HR`, i.e. **t = ln(HR)/c = ln(HR)/0.1 = 10·ln(HR)**.
   This is exactly the code's coefficient. The method is described and defended in:
   - **Spiegelhalter D. How old are you, really? Communicating chronic risk through 'effective
     age' of your body and organs.** *BMC Med Inform Decis Mak.* 2016;16:104.
     doi:10.1186/s12911-016-0342-z. **Grade A** for the method (peer-reviewed;
     the same basis as published "heart age" / "lung age" tools).
   - Translation caveats for older ages: **Pang M, Hanley JA.** *Am J Epidemiol.*
     2021;190(12):2664-2670. doi:10.1093/aje/kwab178 — warns that mortality-rate-ratio →
     remaining-life-expectancy is **not** a proportional mapping, especially in older adults.
     **This is the primary-source basis for our rule that Physical Age must never be presented
     as a life-expectancy prediction.**

**Two assumptions the method requires — and where ours is weakest.**
- (a) HR is roughly constant across ages. The literature shows this is *not* always true —
  e.g. the same step increment reduces mortality *more* in older adults (Paluch 2022; §2.3). Our
  code uses **fixed, age-independent coefficients** for most metrics (only VO2max uses an
  age/sex target table). This is a known simplification vs WHOOP, which age-adjusts several
  metrics. **Flagged in §4 as an approximation to improve.**
- (b) **Independence / no double-counting.** The code sums each metric's impact as if
  independent. But VO2max, RHR, steps, HR-zone time and lean mass are **strongly correlated**
  (a fit person scores well on all of them). The WHOOP white paper corrects this with structural
  equation modelling that shrinks correlated HRs so cardiovascular fitness isn't counted three
  times. **Our model does NOT do this** — it applies raw-ish coefficients and relies only on the
  per-metric caps and the ±15 y global clamp to limit inflation. **This is the single biggest
  methodological gap in our composite (see §4 and §5).**

**Verdict on the method:** The effective-age construction is sound, published, and correctly
implemented at the single-metric level. The composite's weakness is *aggregation* (correlation /
double-counting), not the translation formula.

---

## 2. The 9 metrics → all-cause mortality

Each subsection gives: the strongest evidence, the effect size with CI, design, cohort size,
population, grade, and whether **our coded coefficient is well-supported or an approximation**.

### 2.1 VO2 max / cardiorespiratory fitness  — *code cap ±8 y; impact = −0.398·(VO2 − age/sex target)*

- **Mandsager K, et al. Association of Cardiorespiratory Fitness With Long-term Mortality Among
  Adults Undergoing Exercise Treadmill Testing.** *JAMA Netw Open.* 2018;1(6):e183605.
  doi:10.1001/jamanetworkopen.2018.3605.
  **Verified against primary source:** retrospective cohort, **N = 122,007** patients, Cleveland
  Clinic, median 8.4 y follow-up, 13,637 deaths. Adjusted **HR 0.20 (95% CI 0.16–0.24)** elite vs
  low fitness; **HR 5.04 (4.10–6.20)** low vs elite. Adjacent categories HR 1.41 (1.34–1.49).
  **Design: retrospective cohort → Grade B** (referral population, not general public; very large).
- **Per-MET effect (the code's coefficient basis):** ~**13% lower all-cause mortality per 1 MET
  (~3.5 mL/kg/min)** increase, i.e. HR ≈ 0.87/MET. This is the widely-cited fitness dose-response
  (Kaminsky/FRIEND reference standards; Strasser & Burtscher 2018 *Front Biosci* review). The
  code's `−0.398·ΔVO2` = 10·ln(0.87)/3.5·ΔVO2 is arithmetically exact for HR 0.87/MET. **Grade A**
  for the direction and approximate magnitude; the precise 0.87/MET slope is a **literature
  consensus figure, not a single verified CI** → treat the 13%/MET as **[TO VERIFY]** to a named
  primary CI, but the effect is among the most robust in the field.
  - Kaminsky LA, Arena R, Myers J. *Mayo Clin Proc.* 2015;90(11):1515-23 (FRIEND reference
    standards — the age/sex VO2 target table in the code is WHOOP-Fig-4-derived, itself
    FRIEND-anchored). Weeldreyer NR, et al. *Br J Sports Med.* 2025;59(5):339-346
    (fitness/BMI/mortality meta-analysis).
- **Coefficient assessment:** **well-supported in direction and order of magnitude.** The age/sex
  target table (health-optimized, not population-average) is defensible. Caveat: VO2max on this
  app is usually **Apple Watch-estimated**, not lab-measured — device estimation error propagates
  into the years-impact and is not currently reflected in any uncertainty band shown to the user.

### 2.2 Resting heart rate — *code cap ±5 y; impact = 0.0862·(RHR − ref), ref 60 (M)/64 (F)*

- **Zhang D, Shen X, Qi X. Resting heart rate and all-cause and cardiovascular mortality in the
  general population: a meta-analysis.** *CMAJ.* 2016;188(3):E53-E63. doi:10.1503/cmaj.150535.
  **Verified against primary source:** meta-analysis of **40 prospective cohort studies,
  N = 1,246,203, 78,349 deaths.** Multivariable-adjusted **RR 1.09 (95% CI 1.07–1.12) per 10
  bpm** increment. **Design: meta-analysis of prospective cohorts → Grade A.**
- Supporting: Jensen MT, et al. (Copenhagen Male Study, 16-y follow-up). *Heart.*
  2013;99(12):882-7. doi:10.1136/heartjnl-2012-303375 — elevated RHR predicts mortality
  independent of fitness. Zhang D, Wang W, Li F. *CMAJ.* 2016;188(15):E384-E392 (RHR and CAD/
  stroke/sudden death).
- **Coefficient assessment: exactly correct.** `0.0862 = 10·ln(1.09)/10`. The code's per-10-bpm
  HR of 1.09 is the *verified* pooled estimate. This is our best-grounded coefficient.
  Caveat: the referent (60/64 bpm) is the health-optimized target, consistent with the
  method; fine. Correlation caveat: RHR overlaps heavily with VO2max (§1.2b) — summing both
  risks double-counting aerobic fitness.

### 2.3 Daily steps — *code cap +3/−1.5 y; impact = −0.30·(steps − 8000)/1000*

- **Paluch AE, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international
  cohorts.** *Lancet Public Health.* 2022;7(3):e219-e228. doi:10.1016/S2468-2667(21)00302-9.
  **Verified via primary + reputable secondary reporting:** ~**50,000 participants**, 15 cohorts.
  The three most-active step quartiles had **40–53% lower mortality** vs the least-active
  (lowest ~3,500/day; quartile means 5,800 / 7,800 / 10,900). **Benefit plateaus at
  ~6,000–8,000 steps/day for adults ≥60 and ~8,000–10,000/day for adults <60.**
  **Design: meta-analysis of prospective cohorts → Grade A.**
- Supporting: Stens NA, et al. *J Am Coll Cardiol.* 2023;82(15):1483-1494 (dose-response, steps →
  mortality/CV events). Sheng M, et al. *J Sport Health Sci.* 2021;10(6):620-628 (per-1,000-step
  and per-500-step dose-response).
- **Coefficient assessment: reasonable approximation with two caveats.** (i) The code's referent
  of **8,000/day is defensible** (matches the younger-adult plateau) and the benefit is
  asymmetrically clamped (benefit stops accruing past the plateau) — good. (ii) But the code
  uses a **single linear slope and a single 8,000 referent for all ages**, whereas the primary
  evidence shows the plateau and the per-step benefit are **age-dependent** (older adults get more
  benefit from fewer steps). **This is an approximation → improve by age-scaling the referent
  (see §4).**

### 2.4 Sleep duration — *code cap +3/−0.5 y; <7h → +1.0·(7−h); 7–9h → −0.5; >9h → 0*

- **Cappuccio FP, et al. Sleep duration and all-cause mortality: a systematic review and
  meta-analysis of prospective studies.** *Sleep.* 2010;33(5):585-92. doi:10.1093/sleep/33.5.585
  — U-shaped: short **and** long sleep both raise mortality. **Grade A** (meta-analysis of
  prospective cohorts).
- **Itani O, et al. Short sleep duration and health outcomes.** *Sleep Med.* 2017;32:246-256.
  doi:10.1016/j.sleep.2016.08.006 — short sleep → **~12% higher all-cause mortality** (RR≈1.12),
  plus diabetes/hypertension/CVD. **Grade A.**
- **Saint-Maurice PF, et al. Actigraphy-measured sleep duration, continuity, and timing with
  mortality in the UK Biobank.** *Sleep.* 2024;47(3):zsad312. doi:10.1093/sleep/zsad312 —
  **objectively-measured** (device) sleep shows an even stronger short-sleep→mortality signal
  than self-report. **Grade A** and **directly relevant** because HUMANS reads device sleep.
- Long-sleep caveat: Magee CA, et al. *Sleep Med.* 2013;14(7):591-6 — the long-sleep signal is
  likely **reverse causation** (illness causes long sleep), so the code correctly gives **no
  penalty above 9h** — a deliberately conservative, evidence-based choice that "avoids conflating
  correlation with causation".
- **Coefficient assessment: well-designed and honest.** The <7h penalty (+1.0 y per hour short)
  is a reasonable rendering of RR≈1.12 short-sleep; the 7–9h small credit and the >9h zero are
  each defensible against the specific literature. The −0.5 credit is modest and appropriate
  (§2.4 shows the 8–9h benefit over 7h is small and often non-significant). **Grade A behaviour,
  approximate coefficient.**

### 2.5 Sleep consistency / regularity — *code cap +3/−1.5 y; impact = −0.06·(score − 70)*

- **Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep
  duration: A prospective cohort study.** *Sleep.* 2024;47(1):zsad253. doi:10.1093/sleep/zsad253.
  **UK Biobank, >60,000 participants** with accelerometry. The most-regular sleepers had
  **~20–48% lower all-cause mortality**, ~16–39% lower cancer mortality, ~22–57% lower
  cardiometabolic mortality vs the most-irregular. **Design: large prospective cohort with
  objective measurement → Grade A** (single cohort, but very large and objectively measured; the
  headline finding that *regularity beats duration* is a notable, replicated-direction result).
- Mechanistic/supporting: Huang T, et al. (MESA). *J Am Coll Cardiol.* 2020;75(9):991-999
  (irregularity → CV events). Sletten TL, et al. (National Sleep Foundation consensus).
  *Sleep Health.* 2023;9(6):801-820.
- **Coefficient assessment: direction strongly supported; magnitude is an internal
  approximation.** The 70% referent matches WHOOP's threshold, and the −0.06 y per point slope
  is an **internal calibration, not a directly-cited HR** (the code caps the total at +3/−1.5 y).
  Our on-device "consistency" metric is a **bedtime MAD in minutes** converted to a 0–100 score —
  it is **not** the validated Sleep Regularity Index (SRI) used in the literature. **Flag: our
  consistency operationalisation differs from the published SRI → agreement between the two is
  unproven (see §4/§5).**

### 2.6 Physical activity / HR-zone time — *cardio Z1–3 cap +2/−2.5 y; intensity Z4–5 cap +1/−2 y*

- **Lee DH, et al. Long-Term Leisure-Time Physical Activity Intensity and All-Cause and
  Cause-Specific Mortality: A Prospective Cohort of US Adults.** *Circulation.*
  2022;146(7):523-534. doi:10.1161/CIRCULATIONAHA.121.058162 — NHS + HPFS (the Harvard cohorts),
  **~100,000 adults, up to 30 y follow-up.** Meeting activity guidelines → **~20–30% lower
  all-cause mortality**; both moderate and vigorous activity contribute. **Grade A** (two flagship
  prospective cohorts). *This is the Nurses' Health Study / Health Professionals Follow-up Study
  evidence the CEO specifically asked to anchor on.*
- **Ekelund U, et al.** harmonised-accelerometer meta-analyses (e.g. *BMJ* 2019) — objective
  activity, steep dose-response, mortality benefit down to light activity. **Grade A.**
- Vigorous "little is enough": Ahmadi MN, et al. *Eur Heart J.* 2022;43(46):4801-4814 — as little
  as **15–20 min/week vigorous → 18–24% lower mortality.** Supports the code's low Z4–5 referent
  (10 min/wk). Activity-by-age: Martinez-Gomez D, et al. *JAMA Netw Open.* 2024;7(11):e2446802
  (benefit grows with age).
- Public-health anchors for the referents: CDC / WHO **150 min/wk moderate or 75 min/wk vigorous.**
- **Coefficient assessment: referents well-anchored, slopes are internal approximations.** The
  100 min/wk Z1–3 and 10 min/wk Z4–5 referents map to WHOOP's guideline-derived thresholds and to
  the vigorous-activity literature. The piecewise slopes and caps are **internal calibrations**,
  not cited HRs. Zone minutes here are computed from **workout HR-zone data**, so a user who is
  active but doesn't log HR workouts will under-read on these levers — a **measurement-coverage**
  limitation, not an evidence one.

### 2.7 Strength / resistance training — *code cap +1/−1.5 y; <40 min/wk → +; U-shaped, benefit caps ~120 min/wk*

- **Momma H, et al. Muscle-strengthening activities are associated with lower risk and mortality
  in major non-communicable diseases: a systematic review and meta-analysis of cohort studies.**
  *Br J Sports Med.* 2022;56(13):755-763. doi:10.1136/bjsports-2021-105061.
  **Verified via primary + reputable secondary reporting:** muscle-strengthening → **10–17% lower
  all-cause mortality**, CVD, total cancer, diabetes; **J/U-shaped with maximum benefit at
  ~30–60 min/week** and no added benefit (possibly attenuating) beyond. **Grade A**
  (meta-analysis of prospective cohorts).
- **Shailendra P, et al. Resistance Training and Mortality Risk: A Systematic Review and
  Meta-Analysis.** *Am J Prev Med.* 2022;63(2):277-285. doi:10.1016/j.amepre.2022.03.020 —
  resistance training (alone, and with aerobic) → lower mortality. **Grade A.**
- Supporting: Saeidifard F, et al. (resistance training / mortality). Liu Y, et al. *Med Sci
  Sports Exerc.* 2019;51(3):499-508. **[Saeidifard exact citation TO VERIFY]**.
- **Coefficient assessment: referent and shape well-supported.** The **40 min/wk referent** and
  the **U-shape with benefit capping (~120 min/wk in code vs ~120 min = 2h in Momma)** are a
  faithful rendering of Momma's dose-response. Magnitude (±1/−1.5 y) is an internal calibration
  consistent with a 10–17% mortality signal. **Good.**

### 2.8 Lean body mass % / body fat % — *code cap ±4 y; impact = 0.1044·(fat% − ref), ref 20 (M)/33 (F)*

- **Padwal R, Leslie WD, Lix LM, Majumdar SR. Relationship Among Body Fat Percentage, Body Mass
  Index, and All-Cause Mortality: A Cohort Study.** *Ann Intern Med.* 2016;164(8):532-41.
  doi:10.7326/M15-1181. **Verified via reputable secondary reporting:** Manitoba **DXA cohort,
  ~54,420 adults ≥40 y.** High body-fat% → higher mortality (**HR ≈ 1.19 women, ≈ 1.59 men** for
  high vs lower body fat), **independent of BMI**. **Design: prospective/retrospective cohort with
  DXA → Grade B** (referral population for bone-density testing).
- **Jayedi A, et al. Body fat and risk of all-cause mortality: a systematic review and
  dose-response meta-analysis of prospective cohort studies.** *Int J Obes.* 2022;46(9):1573-1581.
  doi:10.1038/s41366-022-01165-5 — dose-response, higher body fat% → higher mortality.
  **Grade A** for direction. **Exact per-unit HR [TO VERIFY]** against the primary (the code's
  **HR ≈ 1.11 per +10% body fat** is the figure the WHOOP white paper attributes to this class of
  study; direction is A-grade, precise slope is TO VERIFY).
- Mechanistic: sarcopenia/frailty (Gielen 2023; Landi 2015), muscle mass ↔ metabolic health
  (Kim & Kim 2020). **Grade C** (mechanistic/indirect).
- **Coefficient assessment: direction well-supported, precise slope approximate; note a
  measurement subtlety.** `0.1044 = 10·ln(1.11)/10`, i.e. HR 1.11 per +10% body fat. The
  **U-shape caveat matters**: very *low* body fat also carries risk (Padwal's low-BMI arm), but
  the code is **monotonic** (more fat → older, less fat → younger without a low-end penalty),
  clamped at ±4 y. For a fat-loss app this is a **reasonable and safe simplification** (our users
  are almost never dangerously under-fat), but it is a simplification. Body fat% here comes from
  **Apple Health BIA / manual InBody entry**, which is hydration-sensitive and noisier than DXA —
  another uncaptured uncertainty.

### 2.9 HRV — *intentionally NOT in the Physical Age model*

**Correct and worth stating explicitly.** HRV is used elsewhere in the app (Recovery, Stress) but
is **deliberately excluded from Physical Age**, matching WHOOP Age's design. Rationale: HRV's
association with all-cause mortality is **less consistent and more confounded** (age, device,
measurement conditions, and it partly overlaps RHR) than the nine included metrics, and its
effective-age HR is not cleanly established. Excluding it is the conservative, defensible choice
and avoids adding a poorly-calibrated, correlated term to an already correlation-inflated sum
(§1.2b). The code comment states this intent; keep it.

---

## 3. The clinical programming rules (`weeklyProgramme(...)` and recovery gating)

These are the wellness rules layered on top of the age model. They are **training-science
heuristics**, not mortality claims, and should be graded as such.

### 3.1 Recovery-gating / acute:chronic workload ratio (ACWR)

- **Gabbett TJ. The training-injury prevention paradox.** *Br J Sports Med.* 2016;50(5):273-280.
  doi:10.1136/bjsports-2015-095788 — popularised the ACWR "sweet spot" (~0.8–1.3) and the
  spike-injury association. The code's zones (`<0.8 detraining`, `0.8–1.3 sweet spot`,
  `1.3–1.5 high`, `>1.5 danger`) mirror this directly.
- **Critiques (must be cited for honesty):** the ACWR concept has been substantially challenged —
  Impellizzeri FM, et al. (methodological critiques of ACWR, *BJSM* / *Sports Med* 2019–2021),
  and Lolli L, et al. on the mathematical coupling artefact. **[Exact critique citations TO
  VERIFY.]** Consensus now: ACWR is a **reasonable load-monitoring heuristic**, **not** a
  validated injury-prediction instrument. **Grade C** for the injury-prevention claim.
- **Assessment:** using ACWR + a red-recovery gate to **hold back / ease off** training is a
  **safe, conservative** use (it only ever *reduces* prescribed load on high-load/low-recovery
  days). It does not make an injury-prevention *claim* to the user, and the code phrases it softly
  ("eased off … a lighter day may help"). This is the right posture — do **not** upgrade it to a
  "prevents injury" claim.

### 3.2 Strength-priority-with-age (promote strength for 45+ with a strong aerobic base)

- Sarcopenia / muscle-mass-and-strength ↔ mortality and frailty: Momma 2022 (§2.7);
  Gielen E, et al. *Metabolism.* 2023;145:155638; Landi F, et al. *Clin Geriatr Med.*
  2015;31(3):367-74; D'Onofrio G, et al. *Prog Cardiovasc Dis.* 2023;77:25-36. **Grade A/B** for
  the muscle-mass ↔ mortality/frailty association.
- Guidance anchors: **ACSM** and **WHO** both recommend muscle-strengthening ≥2×/week for adults,
  with added emphasis for older adults (fall/frailty prevention). **Grade A** (guideline).
- **Assessment:** the rule (`age ≥ 45 && (low RHR || VO2 at target) && lean-mass headroom →
  promote strength over extra cardio`) is a **defensible training-science prioritisation** — "an
  already-fit aerobic system gets low marginal return from more cardio; muscle is the higher-value
  lever with age." It is framed as wellness ("often your highest-value focus … helps you keep
  muscle as you age"), not a medical directive. **Sound heuristic; keep the soft framing.**

### 3.3 Low-RHR-as-aerobic-fitness interpretation

- Low RHR reflects vagal tone / cardiovascular fitness: Carter JB, et al. *Sports Med.*
  2003;33(1):33-46 (endurance training lowers RHR via parasympathetic enhancement); Jensen 2013
  (§2.2). **Grade B** (physiological + cohort).
- **Assessment:** the code uses low RHR (≤ ref) as a signal of a **strong aerobic base** and
  therefore **caps "add more cardio"** and redirects effort to strength. This is a **legitimate
  physiological inference** (low resting HR is a well-established fitness marker). Caveat worth
  noting internally: a low RHR can occasionally be non-fitness (medication such as beta-blockers,
  or, rarely, pathology) — but because the consequence is only "do a bit less extra cardio, do a
  bit more strength", the **downside of a false-positive is negligible**, so the rule is safe.
  Do not let this ever become "your heart is healthy" (a health claim).

---

## 4. Coefficient audit — well-supported vs approximation (quick-reference)

| Metric | Coded coefficient | Support | Grade | Action |
|---|---|---|---|---|
| Resting HR | 0.0862/bpm (HR 1.09 per 10 bpm) | **Verified** vs Zhang 2016 CMAJ | **A** | Keep as-is |
| VO2 max | −0.398/(mL·kg⁻¹·min⁻¹) (HR 0.87/MET) | Direction/magnitude verified (Mandsager; FRIEND); precise slope consensus | A (dir) / B (slope) | Keep; add device-estimate uncertainty note |
| Sleep duration | +1.0/h short; −0.5 mid; 0 long | Matches Cappuccio/Itani/Saint-Maurice; long-sleep zero is deliberate | **A** (behaviour) | Keep |
| Steps | −0.30/1,000 vs 8,000 ref | Paluch magnitude verified; **age-independence is an approximation** | A (dir) / C (slope) | **Age-scale the referent** |
| Strength | ±1/−1.5 y vs 40 min/wk, U-shape | Matches Momma dose-response | **A** (dir) | Keep |
| Cardio Z1–3 | ±2/−2.5 y vs 100 min/wk | Referent guideline-anchored; slope internal | A (dir) / C (slope) | Keep; documents as calibration |
| Intensity Z4–5 | ±1/−2 y vs 10 min/wk | Ahmadi *Eur Heart J* supports low referent | A (dir) / C (slope) | Keep |
| Lean mass / fat% | 0.1044/% (HR 1.11 per 10% fat) | Direction A (Padwal/Jayedi); **precise slope [TO VERIFY]**; monotonic (no low-fat penalty) | A (dir) / C (slope) | Verify slope; note low-fat simplification |
| Sleep consistency | −0.06/point vs 70% | Direction A (Windred); **metric ≠ published SRI**; slope internal | A (dir) / C (impl.) | Reconcile our metric vs SRI |
| **Aggregation** | Σ of impacts, per-metric caps, ±15 y clamp | **No correlation/double-counting correction** (WHOOP uses SEM) | **C** | **Biggest gap — see §5** |

---

## 5. Validation roadmap — what would it take to actually validate OUR composite?

The component associations are strong (§2). What is **unvalidated is the composite score itself**.
A credible validation programme, in ascending order of rigour:

**Tier 0 — Internal analytical verification (do first, cheap).**
- Unit-test the coefficient arithmetic against the cited HRs (RHR/VO2/fat% are closed-form; assert
  `10·ln(HR)` reproduces the constants). Document every referent's source inline (mostly done).
- **Quantify the double-counting.** Compute the correlation matrix of the nine inputs on our own
  user data and estimate how much the summed score inflates vs an independence-corrected version
  (a lightweight analogue of WHOOP's SEM adjustment). This directly addresses the §1.2b gap and is
  the highest-value single analysis. Report as **EXPLORATORY** until a method is pre-registered.

**Tier 1 — Agreement vs an established metric (the realistic near-term bar).**
- Pre-register (before looking at results) an **agreement study of HUMANS Physical Age vs an
  established effective-age metric** on the same inputs — e.g. reproduce the WHOOP-Age reference
  computation on matched inputs, or agree against a published fitness-age equation
  (e.g. a NHANES-derived fitness-age model).
- **Correct methodology (non-negotiable, per our house standard):** report **Bland–Altman bias +
  95% limits of agreement** against a **pre-declared clinically-acceptable difference in years**,
  and an **ICC(2,1) — two-way random, absolute-agreement, single-measures — with its 95% CI**,
  interpreting the **CI lower bound**, not the point estimate. **Pearson r is banned as an
  agreement statistic.** Respect data structure: repeated measurements per user over time are
  **repeated measures**, not independent observations (1999 Bland–Altman variant).
- This answers "is our number a faithful implementation of the established method?" — **not**
  "does the number predict death", which Tier 3 would need.

**Tier 2 — Convergent / known-groups validity (observational, feasible).**
- Replicate WHOOP's own early-validation design on our data: does Physical-Age-delta track
  **self-rated health** (Idler & Benyamini; DeSalvo — both established SRH↔mortality proxies) and
  differ by self-reported chronic-condition status? Pre-specify the analysis (ANOVA/known-groups),
  label everything **EXPLORATORY** until a protocol is registered. This is *convergent validity*,
  not outcome validation, and must be described as such.

**Tier 3 — Outcome validation (the only thing that would justify a "predicts longevity" claim —
and we will almost certainly never do it).**
- A prospective cohort with **hard endpoints (mortality/morbidity) over years**, testing whether
  baseline Physical Age and *change* in Physical Age predict outcomes beyond chronological age.
  This is what no consumer wearable age score has done by RCT. **Out of scope for our resources.**
  Its absence is exactly why the composite must stay a **motivational estimate**, never a clinical
  claim.

**Evidence gaps to close (priority order):**
1. **Correlation / double-counting correction** in the sum (§1.2b) — the one real accuracy risk.
2. **Age-dependence** of the steps (and arguably activity) coefficients (§2.3).
3. **Sleep-consistency operationalisation** vs the validated SRI (§2.5).
4. **Input measurement error** (Watch-estimated VO2max, BIA body-fat, device sleep) is not
   propagated into any uncertainty shown to the user — consider a "± range" or confidence framing.
5. **[TO VERIFY]** items: precise per-MET VO2 HR/CI; Jayedi per-10% body-fat HR/CI; Saeidifard
   and the ACWR-critique citations.

---

## 6. Bottom line for the CEO

- **The building blocks are as strong as consumer-health evidence gets:** every one of the nine
  metrics has a **large prospective-cohort or meta-analytic association with all-cause mortality**
  (RHR, steps, activity, sleep, sleep-regularity, strength, VO2max, body-fat — Grades A/B), and
  the effective-age math (`10·ln(HR)`, Gompertz) is **published and correctly implemented**.
- **But "clinically proven to extend your life" is not a claim we can make.** The evidence is
  overwhelmingly **observational** (association, not causation), and **no composite wearable age
  score — ours, WHOOP's, or Hume's — has been validated against an outcome cohort or an epigenetic
  clock by RCT.** Physical Age is a **motivational, transparent fitness estimate**. That framing is
  already in the code and must stay on every user-facing surface.
- **The one genuine accuracy weakness** is that we **sum correlated metrics without a
  double-counting correction** (WHOOP applies structural-equation adjustment; we rely on caps + a
  ±15 y clamp). Closing that (Tier 0/1) is the highest-value next step and is cheap.
- **Claims posture: intact.** Nothing in the model or this dossier asserts a diagnosis, a "normal
  range", a life-expectancy prediction, or that HUMANS is a medical device. Keep it that way.

*Prepared as a draft for Head of AI/ML review and CEO approval. No external circulation, and no
real user data in any figure, without that approval and a verified consent basis.*
