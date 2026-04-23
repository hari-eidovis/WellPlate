# Stress Algorithm — Scope of Improvements Brainstorm

**Date:** 2026-04-20
**Status:** Brainstorm — pending strategy/plan
**Grounded in:**
- [Stress Algorithm Calibration Research](../06_Miscellaneous/Stress%20Algorithm%20Calibration%20Research.md) (15-section evidence review)
- [260410-stress-algorithm-v2-brainstorm.md](./260410-stress-algorithm-v2-brainstorm.md) (prior architecture brainstorm)
- Current implementation: `WellPlate/Core/Services/StressScoring.swift`, `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, `WellPlate/Models/StressModels.swift`

---

## 1. Current State (as of v1 in production)

**What we do today**

| Dimension | Implementation |
|---|---|
| Factors scored | 4 — Exercise, Sleep, Diet, Screen Time |
| Factor range | Each 0–25, total 0–100 |
| Direction | Unidirectional — factors can only *add* stress (0) or stay neutral |
| Inversion | `stressContribution = higherIsBetter ? (25 − score) : score` — exercise/sleep/diet flipped into stress; screen time added directly |
| Missing data | Neutral 12.5/25 for exercise/sleep/diet; 0 for screen time |
| Physiology | HRV, RHR, HR shown in UI but **not** in score |
| Personalization | None — fixed thresholds, no gender / age / baseline awareness |
| Level mapping | 0–20 Excellent, 21–40 Good, 41–60 Moderate, 61–80 High, 81+ Very High |

**What we collect but don't use in the score (13 factors)**
HRV, Resting HR, Heart Rate avg, Caffeine (coffee cups), Hydration, Mood, Symptoms, Circadian Regularity (SRI), Daylight, Calories, Fasting state, Journaling, Eating Triggers, Hunger, Mindful Eating, Supplement Adherence.

---

## 2. Gap Analysis — Research vs Current

### A. Structural Gaps (hardest to patch later, highest leverage)

| # | Gap | Research finding | Current behavior | Severity |
|---|---|---|---|---|
| A1 | **Unidirectional scoring** | Good sleep, exercise, hydration, HRV actively *lower* cortisol by 15–50% | Best-case factor contributes **0** stress; can never subtract | 🔴 Critical |
| A2 | **No physiological signal** | HRV–cortisol correlation r = −0.50 to −0.68. Industry weights HRV 30–50% of readiness | HRV/RHR/HR fetched but ignored in score | 🔴 Critical |
| A3 | **No personal baselines** | RHR day-to-day noise is ±3 bpm; HRV must be compared to 30-day personal avg | Nothing baselined | 🔴 Critical |
| A4 | **Equal factor weighting** | Sleep deprivation ≈ 10× the cortisol impact of mild dietary imbalance | Exercise = Sleep = Diet = Screen (25 each) | 🟠 High |
| A5 | **Missing-data neutral (12.5)** | Silently injects a "meh" score when user just forgot to log | Users with no food log get free 12.5 "diet stress" | 🟠 High |
| A6 | **No gender awareness** | Sleep sensitivity +30%, caffeine half-life ×2 on OCP, somatization +20% in women | Single model for all users | 🟠 High |

### B. Factor-Level Calibration Gaps (research-backed thresholds we're missing)

| Factor | Current | Research-backed |
|---|---|---|
| Steps | Linear to 10k target | Benefits plateau at **5k–7k**; 7k = −22% depression risk; 15k+ = overtraining risk |
| Sleep | Peak 7–9h, piecewise linear | Confirmed U-shape; **<4h = +40% cortisol nadir**, >10h = inflammation marker |
| Deep sleep | Ratio bonus `deep/total ≥ 18%` | Absolute threshold: **<45 min = incomplete cortisol clearance**; declines with age (20%→10% from 20s to 60s) |
| Screen time | `hours × 2`, capped at 25 | Evening exposure (1–2h pre-bed) has **3× impact** of daytime; >4h = high-stress profile |
| Diet | Macro-only (protein/fiber/fat/carbs) | Sugar/GI, magnesium, omega-3, B-vitamins, caloric deficit (<1200 kcal) all matter |
| Caffeine | Not scored | **Single cup = +50% cortisol**; tolerance only to morning dose; OCP doubles half-life |
| Hydration | Not scored | **<1.5 L/day = 50% higher cortisol reactivity** — systemic multiplier on ALL stressors |
| Circadian (SRI) | Not scored | **Stronger mortality predictor than duration** (UK Biobank); median SRI ~81 |
| Daylight | Not scored | 10–20 min morning light → **CAR +20–40%** |
| Mood | Not scored | r ~0.7 with cortisol; gender-differential (women: limbic, weaker cortisol link) |
| Symptoms | Not scored | Headache/GI = blunted cortisol (burnout); TMJ = elevated; fatigue = flattened curve |

### C. Missing Compound & Contextual Logic

- **Burnout signature**: rising RHR + falling HRV simultaneously = strongest physiological signal. Not detected.
- **Overtraining**: 50%+ spike in active energy vs 7-day avg. Not flagged.
- **Stress Paradox**: large gap between subjective mood and physiological HRV. Not surfaced.
- **Fasted-exercise amplifier**: vigorous workout + >16h fast = meaningful cortisol spike. Not modeled.
- **Evening-weighted screen time**: post-9 PM / pre-bedtime hours carry more weight. Not modeled.
- **Hydration as a multiplier**: dehydration amplifies all other stressors by ~25%. Not modeled.
- **Menstrual cycle offset**: mid-luteal HRV baseline shifts ~12% lower. Not modeled.

### D. UX & Trust Gaps

- No "confidence" indicator — users can't tell when the score is calibrating vs reliable.
- Score doesn't explain *why* it changed day-to-day.
- No "top stressors vs top boosters" framing — currently only top stressors.
- Age-based thresholds missing (deep-sleep target should scale down for 45+).
- No OCP / cycle-tracking onboarding → caffeine/HRV misread for ~30% of female users.

---

## 3. Improvement Scope — Grouped by Ambition

### Tier 0 — Quick Wins (days of work, no architectural change)

| Scope | What | Cost | Value |
|---|---|---|---|
| Q1 | Re-weight current 4 factors (Sleep 35, Exercise 25, Diet 20, Screen Time 20) | Trivial | Medium — better alignment with research |
| Q2 | Fix missing-data defaults: return `nil` (not 12.5) + shrink total pool | Small | High — stops silent phantom stress |
| Q3 | Step target 10k → 7k for peak score | Trivial | Medium — unlocks "optimal" for majority |
| Q4 | Add deep-sleep absolute threshold (45 min) as a hard floor, not just ratio | Small | Medium |
| Q5 | Evening screen-time multiplier (×1.5 for hours after 21:00 when we have timeline data) | Small | Medium |
| Q6 | Add "confidence" badge based on # of factors with real data | Small | High UX trust |

### Tier 1 — Bipolar Scoring (unlocks "active recovery")

| Scope | What | Cost | Value |
|---|---|---|---|
| B1 | Migrate each factor from `[0, 25]` → bipolar `[−1.0, +1.0]` signal | Medium | 🔴 Critical — research-alignment cornerstone |
| B2 | Final mapping `display = clamp(0, 100, 50 + raw/2)` — 50 = neutral, <50 = recovering | Small | Drives B1's value |
| B3 | Adjust StressLevel bands (add "Balanced" zone 41–55) | Trivial | Medium |
| B4 | Score smoothing `0.7 × today + 0.3 × yesterday` to reduce volatility | Small | High — avoids whipsaw UX |

### Tier 2 — Expand Factor Set (iPhone-only, no Watch needed)

| Scope | Factors to add | Data source | Cost |
|---|---|---|---|
| E1 | Caffeine | `WellnessDayLog.coffeeCups` | Small — data exists |
| E2 | Hydration | `WellnessDayLog.waterGlasses` | Small — data exists |
| E3 | Mood | `WellnessDayLog.moodRaw` + HK State of Mind | Small — data exists |
| E4 | Circadian Regularity (SRI) | `CircadianService` (already computed) | Small — service exists |
| E5 | Daylight | HK `.timeInDaylight` | Medium — new HK pull |
| E6 | Symptoms | `SymptomEntry` with severity + type multipliers | Medium |
| E7 | Calories | `FoodLogEntry.calories` | Trivial — data exists |

### Tier 3 — Physiological Layer (Apple Watch, calibrated)

| Scope | What | Cost | Value |
|---|---|---|---|
| P1 | HRV baseline service — 7-day activation, 30-day rolling avg | Medium | 🔴 Core |
| P2 | RHR baseline service — 7-day rolling avg | Small | 🔴 Core |
| P3 | HRV / RHR / HR scoring against **personal deviation** (not population) | Medium | 🔴 Core |
| P4 | Two-mode architecture: Base (iPhone) ↔ Enhanced (Watch) with weight absorption | Medium-Large | 🔴 Core |
| P5 | Calibrating / Fully Calibrated UI states | Small | High UX |

### Tier 4 — Compound & Contextual Modifiers

| Scope | What | Cost |
|---|---|---|
| C1 | Hydration as a systemic multiplier (`×1.25` on positive raw when <4 glasses) | Small |
| C2 | Burnout detector (↑RHR + ↓HRV concurrent → +2.0 penalty + insight card) | Small |
| C3 | Overtraining detector (active energy spike + physio strain) | Medium |
| C4 | Stress Paradox insight (mood vs HRV gap >40%) | Medium — UI design |
| C5 | Active-fasting dynamic modifier (phase-based curve) | Medium |
| C6 | Tier-4 micro-modifiers (journaling −1, mindful eating −0.5, stress-eating triggers +1.5) | Small |
| C7 | Trend adjustment (last 3d avg vs days 4–7) | Small |

### Tier 5 — Personalization

| Scope | What | Cost |
|---|---|---|
| S1 | Gender coefficients applied to weights (re-normalize to 100) | Small |
| S2 | Onboarding question: OCP / hormonal contraception → +50% caffeine half-life | Small |
| S3 | Age-band thresholds for deep sleep + HRV quintile fallback | Small |
| S4 | Menstrual cycle tracking integration → 1.12× HRV offset in mid-luteal phase | Large — blocked on cycle UX |
| S5 | Evening-chronotype detection (shift SRI penalty for night owls) | Research-dependent |

### Tier 6 — UX, Trust & Explainability

| Scope | What | Cost |
|---|---|---|
| U1 | Score confidence badge (Low / Medium / High based on factor coverage) | Small |
| U2 | "Why did my score change?" — day-over-day diff of top 2 factors | Medium |
| U3 | "Top stressors" + **"Top boosters"** (symmetric) — only possible post-bipolar | Small (post-B1) |
| U4 | Learning-phase banner "Calibrating (Day 3/7)" + what unlocks on day 7 | Small |
| U5 | Per-factor drill-down showing research basis ("why caffeine matters") | Medium |

---

## 4. Suggested Staged Rollout

```
Phase 1 (1–2 weeks)  →  Quick wins Q1–Q6 + Tier 2 factors E1, E2, E3, E7
                         (caffeine, hydration, mood, calories from SwiftData)
                         Score still unidirectional, but much richer.

Phase 2 (2–3 weeks)  →  Bipolar migration (B1–B4) + UX confidence (U1, U4)
                         Unlock "Balanced" zone and active recovery.

Phase 3 (2–3 weeks)  →  Circadian (E4), Daylight (E5), Symptoms (E6)
                         + Compound modifiers C1, C2, C6
                         + Gender coefficients S1, S2

Phase 4 (3–4 weeks)  →  Physiological layer P1–P5 (Base ↔ Enhanced mode)
                         + Burnout/Paradox insights C3, C4
                         + Explainability U2, U3, U5

Phase 5 (deferred)   →  Fasting modifier C5, menstrual cycle S4, chronotype S5
```

Each phase is shippable on its own — nothing in phase N+1 depends on phase N+2.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Bipolar migration shifts every existing user's score overnight | Ship behind `AppConfig.stressAlgorithmV2` feature flag; run v1 + v2 in shadow for 7 days; surface in-app "Your score got smarter" explainer |
| Widget / AI report / mock data all depend on `totalScore` shape | Keep `totalScore: Double` API stable; change internals only. Update `StressMockSnapshot` + widget mock in lockstep |
| Research thresholds are population averages — not everyone fits | Personal baselines (P1–P3) fix this; until then, surface "calibrating" state |
| More factors → more silent failures (e.g. no caffeine log ≠ 0 cups) | Distinguish **"no data"** from **"explicit zero"** per factor; weight redistribution on missing |
| AI report and home insights read stress — their prompts may break | Audit `ReportNarrativeGenerator`, `InsightEngine`, `StressDeepDiveSection` during Phase 2 migration |
| Score volatility from new bipolar model | B4 smoothing + trend adjustment dampen day-to-day whipsaw |

---

## 6. Open Questions

1. **Should v2 fully replace v1**, or is there a case for keeping a "Simple" mode for users without HealthKit permissions? (Research suggests calibrated > uncalibrated, even with fewer inputs.)
2. **Do we want REM sleep as a separate factor** (9 pts → 6 Deep + 3 REM) or roll it into one "architecture" score?
3. **Which tier surfaces as the default home-screen stress summary** — is there room for a "resilience score" separate from "stress score"?
4. **Do we need a cortisol-model consent screen** given we're making quasi-medical claims? Legal review?
5. **How does this interact with Stress Lab experiments** — should v2 scores invalidate in-flight experiments, or annotate them with "algorithm changed"?
6. **Gender data source** — do we have a reliable gender field in onboarding, or is this blocked?
7. **Should we expose a "honest mode"** where the score degrades gracefully (e.g. shows "insufficient data" instead of imputing)?

---

## 7. Decision Points for Strategy Phase

Before we commit a strategy doc, we need explicit decisions on:

1. **Unidirectional (v1.1 tweaks) vs Bipolar (v2 rewrite)** — scope-defining choice
2. **Phase 1 factor set** — which subset of E1–E7 ships first
3. **Watch-required or Watch-optional** — does physiological data get a dedicated separate "Recovery Score", or is it folded into the main stress score via weight absorption?
4. **Rollout strategy** — big-bang with flag, or gradual per-factor
5. **Mock-mode parity** — does mock data need new signals from day one, or does it layer in per phase?

---

## Appendix A — Direct Mapping: Current → Proposed

```
Current                           →   Proposed (Phase 2+)
----------------------------------------------------------------
exerciseScore(steps, energy)      →   bipolar signal + overtraining flag
sleepScore(summary)               →   bipolar signal + age-adjusted deep target + REM
dietScore(protein, fiber, ...)    →   bipolar signal + GI/sugar + calorie U-curve
screenTimeScore(hours)            →   bipolar signal + evening multiplier
                                  +   caffeineScore(cups, OCP, time-of-day)
                                  +   hydrationScore(glasses)  [+ multiplier]
                                  +   moodScore(mood, gender)
                                  +   circadianScore(SRI)
                                  +   daylightScore(minutes)
                                  +   symptomScore(type, severity)
                                  +   calorieScore(kcal, gender)
                                  +   hrvScore(value, baseline)        [Watch]
                                  +   rhrScore(value, baseline)        [Watch]
                                  +   fastingModifier(phase, hours)    [if active]
                                  +   burnoutDetector(rhrTrend, hrvTrend)
                                  +   tier4Modifiers(journal, triggers, presence)

totalScore (sum of 4)             →   Σ(weight × signal) × hydrationMult + modifiers
                                     → display = clamp(0,100, 50 + raw/2)
```

---

**Next step:** Pick one of the Phase 1 scopes and run `/develop strategize <scope>` to commit to an approach before planning.
