# Strategy: Stress Algorithm Overhaul — Phased Rollout of Tiers 0–6

**Date:** 2026-04-20
**Source brainstorm:** [260420-stress-algorithm-improvements-brainstorm.md](../../01_Brainstorming/260420-stress-algorithm-improvements-brainstorm.md)
**Prior architecture brainstorm:** [260410-stress-algorithm-v2-brainstorm.md](../../01_Brainstorming/260410-stress-algorithm-v2-brainstorm.md)
**Research basis:** [Stress Algorithm Calibration Research](../../06_Miscellaneous/Stress%20Algorithm%20Calibration%20Research.md)
**Status:** Ready for Planning

---

## 1. Chosen Approach — "Bipolar v2 Behind a Flag, Built Incrementally"

Commit to the **v2 bipolar rewrite** described in the 260410 brainstorm as the final shape of the algorithm, but do NOT land it as a single big-bang migration. Instead, ship it as a **new parallel scoring service (`StressScoringV2`)** gated by `AppConfig.stressAlgorithmV2`, grown over 5 phases, running in *shadow mode* alongside v1 for at least the first two phases so we can observe divergence before we flip the default.

**Why v2 rewrite over patching v1 in place:**

1. Tiers 0 and 1 *look* like small patches, but re-weighting + fixing missing-data semantics + bipolar signals changes every `stressContribution` value we have ever persisted — there is no "safe" patch to v1 that preserves historical comparability, so we may as well build the right shape.
2. The brainstorm already has a fully specified bipolar architecture (signal curves, weight tables, gender coefficients, two-mode absorption) — we are sequencing work that has already been designed, not re-deciding structure.
3. Patching v1 forces us to keep the `[0,25]` per-factor convention, which makes Tier 1 (bipolar) and Tier 3 (physio absorption) impossible without a second rewrite later — roughly double the work.
4. A parallel `StressScoringV2` service keeps v1 on production for the widget, AI reports, and `StressReading` history, so user-facing stability is decoupled from algorithm maturity.
5. Shadow-scoring (computing both, logging the delta, displaying only v1) lets us validate research-based curves against real user data on our own device before any user sees the new number.

**Key trade-offs accepted:**

- We carry two scoring implementations for ~8–12 weeks. Acceptable — `StressScoring.swift` is 88 lines and `StressScoringV2` lives beside it without touching the consumer.
- No A/B test infra — single-developer project, we ship to our own device first and flip the flag when confidence is high.
- `StressReading` rows logged during Phase 1–2 will be v1 scores; we do not backfill. Acceptable — we only need 7 days of history to calibrate baselines and users won't notice.

---

## 2. Phase Map — 5 Phases, Each 1–3 Weeks Solo

| Phase | Tiers covered | Duration | Default user sees | Flag state |
|---|---|---|---|---|
| **P1 — Foundation & Quick Wins** | Tier 0 (all 6 items) + Tier 6 confidence badge (U1, U4) | 1–2 weeks | v1 with fixes | v2 off |
| **P2 — Bipolar Rewrite (Behavioral Only)** | Tier 1 (B1–B4) + Tier 2 behavioral subset (E1, E2, E3, E7) + Tier 6 (U3 Top Boosters) | 2–3 weeks | v1 still default; v2 shadow-logged; dev toggle reveals v2 | v2 built, off by default |
| **P3 — Expand Signals & Personalize** | Tier 2 remainder (E4 Circadian, E5 Daylight, E6 Symptoms) + Tier 5 (S1 gender, S2 OCP, S3 age bands) + compound modifiers C1 (hydration mult), C6 (tier-4 micros), C7 (trend) | 2–3 weeks | v2 **flipped on** as default; v1 kept as fallback | v2 on |
| **P4 — Physiological Layer** | Tier 3 (P1–P5) full two-mode architecture + Tier 4 burnout/overtraining/paradox detectors (C2, C3, C4) + Tier 6 explainability (U2, U5) | 3 weeks | Enhanced mode unlocks after 7-day calibration | v2 on, physio activates automatically |
| **P5 — Deferred Personalization** | Tier 4 C5 (fasting modifier) + Tier 5 S4 (cycle), S5 (chronotype) | Deferred — ship as research permits | Unchanged unless user opts in | v2 on |

Each phase is independently shippable — we can stop after any phase and the app remains coherent.

---

## 3. Phase Details

### Phase 1 — Foundation & Quick Wins (1–2 weeks)

**Why this before the next:** Tier 0 fixes hurt the most in the current app (phantom 12.5 diet stress, sedentary-friendly 7k target missing, no confidence signal) and unblock P2 by establishing the "has valid data" plumbing v2 will need anyway.

**Scope:**
- Q1 Re-weight v1: Sleep 35 / Exercise 25 / Diet 20 / Screen Time 20 (still `maxScore` per factor; total 100)
- Q2 Missing-data semantics: `StressFactorResult.hasValidData = false` → exclude from denominator AND numerator, normalize remaining weights to 100. Eliminate the 12.5 neutral default inside `StressScoring.swift:15`, `:26`, `:56`.
- Q3 Step target 10k → 7k for peak (`StressScoring.swift:17` — change `10_000.0` → `7_000.0`)
- Q4 Deep-sleep floor: add 45-min absolute threshold branch in `StressScoring.swift:41-46` alongside the existing ratio bonus
- Q5 Evening screen-time multiplier: touch `refreshScreenTimeFactor()` in `StressViewModel.swift:615` to multiply ×1.5 for hours logged after 21:00 (depends on `ScreenTimeManager` exposing timeline buckets — verify first; if not available, defer to P2)
- Q6 / U1 / U4 Confidence badge: compute `Low/Medium/High` from count of factors with `hasValidData = true` and surface on `StressView`

**Affected files:**
- `WellPlate/Core/Services/StressScoring.swift` — rewrite all 4 factor functions to return `nil` (not 12.5) when missing
- `WellPlate/Models/StressModels.swift:111-114` — `stressContribution` denominator logic respects weight
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:79-85` — `totalScore` becomes weighted sum with missing-factor redistribution
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add confidence badge UI
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — add "sparse data" snapshot variant to exercise the new missing-data paths

**Exit gate:**
- A user with zero food logs sees diet excluded from both factor list weight AND stress contribution (no phantom 12.5 anywhere in the UI or widget)
- Stress score for an average user shifts by ≤5 points on the same inputs vs old algorithm (proves re-weight didn't whipsaw)
- Confidence badge shows Low when <3 factors have data, High when 4/4
- Widget, home insight card, and AI report all still render with the new `totalScore` shape

**Shippable value:** Users with sparse logs stop seeing a misleading 50/100. Active users with 7k steps stop being told they're sedentary.

**Decision points to resolve before starting:**
- Q5 feasibility — confirm `ScreenTimeManager` exposes hourly breakdown; if not, Q5 moves to P2 and P1 keeps 5 items.
- Brainstorm Open Q7 ("honest mode") — default to YES for Q2: if <2 factors have valid data, show "Log more to see your stress score" instead of a number.

---

### Phase 2 — Bipolar Rewrite + Behavioral Expansion (2–3 weeks)

**Why this before the next:** Bipolar signals are the structural cornerstone of the research-aligned model; everything downstream (gender coefficients, compound modifiers, physio absorption, Top Boosters) is expressed in the `[-1.0, +1.0]` space. Expanding the factor set here and not earlier avoids redoing the same signals twice.

**Scope:**
- B1 New `StressScoringV2` service with bipolar `[-1, +1]` signal per factor (curves from 260410 brainstorm, not re-specified here)
- B2 Display mapping `display = clamp(0, 100, 50 + raw/2)` with 50 = neutral
- B3 Add `StressLevel.balanced` case (41–55 band); shift existing band thresholds per brainstorm Layer 4 table
- B4 Score smoothing `0.7 × today + 0.3 × yesterday` from `StressReading` history
- E1 Caffeine factor (`WellnessDayLog.coffeeCups`) — curve per brainstorm
- E2 Hydration factor (`WellnessDayLog.waterGlasses`) — curve only; **multiplier behavior deferred to P3** so Phase 2 isolates the bipolar migration
- E3 Mood factor (`WellnessDayLog.moodRaw`)
- E7 Calories factor (`FoodLogEntry.calories` sum)
- U3 "Top Boosters" — now meaningful because signals can be negative
- Shadow logging: compute v2 every `loadData()` call, write to a dedicated `StressScoreShadowLog` SwiftData model with `{v1, v2, delta, factorsUsed, date}` for dev inspection

**Affected files:**
- NEW `WellPlate/Core/Services/StressScoringV2.swift` — bipolar signal functions per factor (siblings of `StressScoring.swift`)
- NEW `WellPlate/Core/Services/StressScoringV2Weights.swift` — weight tables (base mode; gender multipliers added in P3)
- NEW `WellPlate/Models/StressScoreShadowLog.swift` — debug-only shadow storage
- `WellPlate/Core/AppConfig.swift:14-22` — add `stressAlgorithmV2: Bool` flag key + computed property following the existing `mockMode` DEBUG pattern
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — inject factory: when v2 flag on, read from `StressScoringV2`; when off, read from v1; always shadow-compute v2
- `WellPlate/Models/StressModels.swift` — add `.balanced` case to `StressLevel` guarded so v1 still maps cleanly (v1 score never lands in 41–55 vs moderate, but handle defensively)
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add Top Boosters section (negative-signal factors)
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — add `coffeeCups`, `waterGlasses`, `moodRaw` fields (currently absent per file read)

**Exit gate:**
- `AppConfig.stressAlgorithmV2 = true` in DEBUG produces a coherent 0–100 score for the default mock snapshot with all 8 factors contributing
- Shadow log shows v1 vs v2 delta <20 points on median day for the dev's real HealthKit data over 7 days
- Top Boosters card shows ≥1 factor when user has good sleep or exercise
- Widget/home insight/`ReportNarrativeGenerator.swift:111-149` read `totalScore` unchanged (double 0–100) — no breaks
- Unit tests (if wired) or at minimum a `StressScoringV2Preview` SwiftUI preview exercising edge cases: all missing, all optimal, all terrible

**Shippable value (to the dev, not user):** End of Phase 2 we have the real algorithm running in shadow, validated against 7 days of real data, with a flag ready to flip. User still sees v1.

**Decision points:**
- Brainstorm Open Q5 — do shadow v2 changes invalidate in-flight Stress Lab experiments? Default: **no**, shadow doesn't affect displayed score so experiments are untouched. Revisit at P3 flip.
- Brainstorm Open Q7 — formalize "honest mode" threshold for v2: require ≥3 factors across ≥2 tiers (carry 260410 brainstorm's rule forward).
- Dietary Tier 2 split — 260410 brainstorm treats "Diet Quality" and "Calories" separately; in P2 we keep that split but still reuse `StressScoring.dietScore` macro logic as the bipolar curve source.

---

### Phase 3 — Flip to v2 + Expand Signals + Personalize (2–3 weeks)

**Why this before the next:** v2 needs a flag flip and a broader factor set to be defensible before physio adds its weight-absorption complexity. Circadian/daylight/symptoms come from iPhone-only data — cheap signal wins. Personalization (gender, age, OCP) is mostly weight-table work and delivers noticeable accuracy for ~50% of users without new data.

**Scope:**
- E4 Circadian factor — `CircadianService.CircadianResult.regularityScore` already computed; just add bipolar signal + weight (10 pts; redistributed to Sleep+Exercise+Screen+Mood on days 1–6 per brainstorm weight table)
- E5 Daylight factor — HealthKit `.timeInDaylight` already fetched via `fetchDaylightHistorySafely(range:)` (`StressViewModel.swift:543`)
- E6 Symptoms factor — query `SymptomEntry` SwiftData model with type multipliers from brainstorm (headache/GI ×1.2, muscle ×1.0, fatigue ×1.1)
- C1 Hydration multiplier — apply ×1.25/×1.10/×1.00/×1.05 to the positive portion of raw score (Layer 3 in brainstorm)
- C6 Tier-4 micro-modifiers — journaling −1, mindful eating −0.5, eating triggers +1.5, hunger <3 +1, supplement adherence ±0.5 (cap ±5)
- C7 Trend adjustment — avg(last 3d) vs avg(days 4–7), cap ±3, applied only to factors with 7-day history
- S1 Gender coefficients — extend `UserGoals` or dedicated `UserProfile` SwiftData model with `gender: String?`; apply per-factor multipliers (brainstorm Layer 2 table) then re-normalize weights to 100
- S2 OCP onboarding question → caffeine coefficient 1.5 for this cohort
- S3 Age bands — deep-sleep threshold lowers for 45+ users; HRV population quintile fallback prepared for P4
- **Flip default:** `AppConfig.stressAlgorithmV2 = true` becomes the default in DEBUG, and the release build follows one build cycle later

**Affected files:**
- `WellPlate/Core/Services/StressScoringV2.swift` — add Circadian / Daylight / Symptoms signals, trend math, Tier-4 modifiers
- `WellPlate/Core/Services/StressScoringV2Weights.swift` — gender coefficient tables, age-band adjustments, OCP coefficient
- `WellPlate/Models/UserGoals.swift:4` or NEW `WellPlate/Models/UserProfile.swift` — add `gender`, `birthYear`, `usesHormonalContraception` fields (SwiftData migration: additive only, default nil/false)
- `WellPlate/Features + UI/Onboarding/` — 2 new onboarding screens (gender, OCP question — gated "prefer not to say" option)
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — fetch `SymptomEntry`, pass user profile into scoring
- `WellPlate/Core/Services/WidgetRefreshHelper.swift:42-53` — confirm `WidgetStressData` still consumes just `totalScore + levelRaw + factors` (it does today — unchanged)
- `WellPlate/Core/Services/ReportNarrativeGenerator.swift:111-149` — prompts still read `stressScore` (scalar) unchanged, but verify narrative handles 41–55 "Balanced" band gracefully

**Exit gate:**
- v2 is the default scorer; v1 remains in code as a fallback only triggered by DEBUG toggle
- A female user with OCP sees caffeine penalty ~50% stronger than a male user with identical intake
- Symptoms factor active when user has logged symptoms; otherwise cleanly excluded via the missing-data redistribution from P1
- Hydration at 3 glasses visibly amplifies a high-stress day relative to 8 glasses (verified in shadow log)
- Score volatility day-over-day is within ±12 points on median after B4 smoothing — measured on dev's 14-day shadow log window

**Shippable value:** First time users see a research-aligned score with "Balanced" band, Top Boosters, and gender-aware weighting. This is the phase where external testers (if any) should first see v2.

**Decision points:**
- Brainstorm Open Q6 — gender data source. Default: add to onboarding in P3; existing users get a one-time prompt. If blocked (legal, design bandwidth), S1/S2 regress to Phase 4 and we ship P3 with Tier 2 + modifiers only.
- Brainstorm Open Q4 — cortisol-model consent screen. Default: **no medical claims**, use "stress indicator" phrasing; add legal disclaimer card reachable from `/u5` drill-down.
- Decide whether `StressLevel.balanced` label appears in widget (small widget real estate is tight) — default: yes, it's just a string.

---

### Phase 4 — Physiological Layer (3 weeks)

**Why this before the next:** Tier 3 is the gateway to Tier 4's compound detectors (burnout = RHR trend + HRV trend; overtraining = energy spike + HRV drop; Stress Paradox = mood ↔ HRV gap). These detectors cannot exist without personal baselines, so Tier 3 and the Tier-4 items that *depend on physio* belong in the same phase. Fasting modifier (C5) and cycle tracking (S4/S5) stay deferred because they need UX work beyond scoring.

**Scope:**
- P1 HRV baseline service — 30-day rolling avg; 7-day activation threshold
- P2 RHR baseline service — 7-day rolling avg; 5-day activation
- P3 Personal-deviation scoring for HRV/RHR/HR (not population averages) — curves from 260410 brainstorm
- P4 **Two-mode architecture** — Base mode (behavioral only, 90 pts → normalized to 100) vs Enhanced mode (physio active, 10 pts absorbed from overlapping behavioral factors per brainstorm absorption table)
- P5 Calibrating / Fully Calibrated UI states
- C2 Burnout detector — concurrent ↑RHR + ↓HRV → +2.0 penalty + insight card
- C3 Overtraining detector — active energy spike (≥1.5× 7-day avg) + physio strain → flag
- C4 Stress Paradox — |mood-derived signal − HRV-derived signal| > 0.4 → insight card (two sub-cases: anxiety vs "wired but tired")
- U2 "Why did my score change?" — day-over-day diff of top 2 factors (by contribution magnitude)
- U5 Per-factor drill-down — research rationale sheet per factor (static copy from research doc)

**Affected files:**
- NEW `WellPlate/Core/Services/PhysioBaselineService.swift` — computes 7d/30d rolling baselines from `hrvHistory`, `restingHRHistory`, `heartRateHistory` already in `StressViewModel`
- `WellPlate/Core/Services/StressScoringV2.swift` — add `hrvSignal(value, baseline)`, `rhrSignal(value, baseline)`, `heartRateSignal(value, baseline)`
- `WellPlate/Core/Services/StressScoringV2Weights.swift` — Enhanced-mode weight table (brainstorm Layer 2 absorption matrix)
- `WellPlate/Core/Services/InsightEngine.swift` — register burnout/overtraining/paradox detectors as new `InsightCard` types
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — Calibrating badge (Day N/7), Enhanced-mode indicator, factor drill-down sheets
- NEW `WellPlate/Features + UI/Stress/Views/FactorRationaleSheet.swift` — U5 research copy
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — add "Day 5 calibrating" and "Fully calibrated" snapshot variants

**Exit gate:**
- New user sees Base mode for first 7 days, then smoothly transitions to Enhanced mode without a score jump >8 points (validated in shadow log during transition week)
- Burnout detector fires when dev synthesizes +10bpm RHR + −20% HRV in mock data
- "Why score changed" shows 2 factors with signed contribution deltas
- Widget weekly sparkline (`WidgetRefreshHelper.swift:23-33`) continues rendering — no schema change
- `StressReading` table stops double-logging near-identical scores (smoothing from P2 combined with Base↔Enhanced transition shouldn't generate spurious rows)

**Shippable value:** Algorithm now matches Oura/Whoop research rigor. Burnout/overtraining/paradox insights are unique to WellPlate's multi-modal logging. This is the "the score actually means something" moment.

**Decision points:**
- Brainstorm Open Q1 — keep a Simple / iPhone-only mode or force Enhanced when Watch present? Default: **always fold physio in via absorption** (single score path per brainstorm), show "Fully Calibrated" badge when physio active. Separate "Recovery Score" (Open Q3) deferred to post-P5.
- Brainstorm Open Q2 — REM as separate factor? Default: **no**, keep Deep Sleep as the single architecture signal, revisit if research shows independent predictive power in dev's own data.
- Whether to retire v1 entirely at end of P4 or keep it as DEBUG-only fallback — default: DEBUG-only fallback for one release then delete.

---

### Phase 5 — Deferred Personalization (ship as research/UX permits)

**Why this last:** Each item here is gated on work outside the scoring service (fasting UX exists but cycle tracking is unbuilt; chronotype requires sleep-time clustering research).

**Scope:**
- C5 Active-fasting dynamic modifier — hour-by-hour curve (brainstorm Layer 3 table), experience dampening, fasted-exercise amplifier
- S4 Menstrual cycle tracking — requires cycle UX (brainstorm notes this is blocked on cycle UX). 1.12× HRV offset during mid-luteal
- S5 Chronotype detection — shift SRI penalty for night owls

**Affected files:** TBD — contingent on cycle tracking feature existing.

**Exit gate:** Deferred — re-plan when one of the three unblockers lands.

---

## 4. Migration & Compatibility

### Feature flag

- Key: `AppConfig.stressAlgorithmV2` (UserDefaults-backed, DEBUG-togglable, defaults to `false` in P1–P2, `true` from P3 onward). Follows the existing `mockMode` pattern at `AppConfig.swift:29-46`.
- Release toggle in Profile → Debug section so the dev can compare on real device.

### Shadow scoring window (P2 → P3 flip)

- Both v1 and v2 compute on every `StressViewModel.loadData()` call.
- Only v1 renders to UI / widget / `StressReading`.
- v2 result + raw signals + selected weights get written to `StressScoreShadowLog` (new SwiftData model, DEBUG-only).
- **Flip criterion:** 7 consecutive days on dev's own HealthKit data where `|v2 - v1| ≤ 20` with no NaN/clamping errors. If divergence stays >25, re-tune signal curves before flip.

### Fallback

- v2 catches internal errors and degrades to v1 for that compute (logged to `WPLogger.stress`). Keeps the app from ever showing "—" for stress once a score has existed.
- If fewer than 3 factors have `hasValidData`, show "Log more to see your stress score" instead of a number (honest-mode default).

### Mock-mode parity

- `StressMockSnapshot.default` (see `StressMockSnapshot.swift:49`) gets extended per phase:
  - P1: add `hasValidData` variants (sparse-data snapshot)
  - P2: add `coffeeCups`, `waterGlasses`, `moodRaw`, `calories`
  - P3: add `symptoms: [SymptomEntry]`, gender/age/OCP metadata
  - P4: add `hrvBaseline`, `rhrBaseline`, "calibrating day N" variants, synthetic burnout/overtraining fixtures
- Mock data must ship in the SAME commit as the scoring changes — no phase lands without its fixture updates.

### AI report compatibility (`ReportNarrativeGenerator.swift:111-149`)

- Narrative reads `day.stressScore` as scalar `0–100` and computes avg/trend — **shape unchanged**, no prompt rewrite needed through P4.
- Audit P3 flip: ensure narrative copes with the new "Balanced" band (41–55) — likely just add one case to trend/label mapping.
- P4 adds new `InsightCard` types (burnout/overtraining/paradox); these flow through `InsightEngine` → existing card rendering, no report changes required.

### Widget compatibility (`WidgetRefreshHelper.swift`, `SharedStressData.swift`)

- `WidgetStressData.totalScore: Double` and `factors: [WidgetStressFactor]` shape — keep stable through P4.
- Factor `score` and `maxScore` in widget model (`WidgetStressFactor.score`, `:maxScore`) can stay at 0–25 scale for display even after v2 internally goes bipolar — viewmodel normalizes before passing to widget.
- Weekly sparkline reads `StressReading.score` — no schema change.

### `StressReading` history

- Do not backfill historical rows on flip. Old rows = v1 scores, new rows = v2. One-time UX note optional: "Your stress score got smarter on [date]".

---

## 5. Tier Dependency Matrix

| Tier | Depends on | Rationale |
|---|---|---|
| Tier 0 | — | Purely fixes in v1 |
| Tier 1 (bipolar) | Tier 0's missing-data plumbing | B1 needs per-factor `hasValidData` to redistribute weights |
| Tier 2 E1–E3, E7 | Tier 1 | Expressed in bipolar signals |
| Tier 2 E4–E6 | Tier 1 + new HK pulls | Symptoms need SwiftData query path |
| Tier 3 physio (P1–P5) | Tier 1's weight infra + Tier 2 complete | Absorption table operates on full base weight set |
| Tier 4 C1 hydration mult | Tier 1 (needs signed raw score) | Can't multiply a unidirectional score meaningfully |
| Tier 4 C2 burnout, C3 overtraining, C4 paradox | **Tier 3 physio baselines active** | Detectors rely on personal RHR/HRV trends |
| Tier 4 C5 fasting | None of above strictly — but UX-dependent | Deferred for priority reasons, not technical |
| Tier 4 C6 micro-modifiers | Tier 1 (works in signed space) | |
| Tier 4 C7 trend | Tier 1 + 7+ days of shadow/v2 history | |
| Tier 5 S1–S3 | Tier 1 + onboarding fields | Weight coefficients only apply post-bipolar |
| Tier 5 S4 cycle | Tier 3 physio + cycle-tracking UX | HRV offset needs personal baseline to offset |
| Tier 5 S5 chronotype | Tier 2 E4 circadian | Shifts SRI penalty, not a new signal |
| Tier 6 U1 confidence | Tier 0 missing-data plumbing | Coverage counter |
| Tier 6 U2 "why changed" | Tier 1 signed factor deltas | |
| Tier 6 U3 Top Boosters | Tier 1 (signed signals) | Unidirectional has nothing negative to boost |
| Tier 6 U4 calibrating banner | Tier 3 | Has real meaning only once baselines matter |
| Tier 6 U5 per-factor rationale | Static copy only | Can ship anytime but naturally belongs with drill-downs (P4) |

**Hard gates:** Tier 3 → Tier 4 compound detectors, Tier 5 S4 → cycle-tracking UX existing, Tier 4 C5 → `FastingSession` model already shipped (verify).

---

## 6. Existing Files — Touch Summary

| File | Phases touched | Nature of change |
|---|---|---|
| `WellPlate/Core/Services/StressScoring.swift:14-76` | P1 only | Re-weight, kill 12.5 defaults, step 7k, deep-sleep 45-min floor. Deprecated after P3 flip. |
| NEW `WellPlate/Core/Services/StressScoringV2.swift` | P2 build, P3–P4 extend | Bipolar signal implementations |
| NEW `WellPlate/Core/Services/StressScoringV2Weights.swift` | P2 build, P3 gender/age, P4 enhanced mode | Weight tables & coefficient math |
| `WellPlate/Core/AppConfig.swift:14-22, 29-46` | P2 | Add `stressAlgorithmV2` flag following `mockMode` pattern |
| `WellPlate/Models/StressModels.swift:12-27, 111-114` | P1 (missing-data), P2 (add `.balanced`) | Add `.balanced` case, rework `stressContribution` |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift:79-85, 159-319` | P1–P4 | `totalScore` becomes weighted; inject profile; pass to V2; new factors (caffeine/hydration/mood/calories/circadian/daylight/symptoms); physio baselines |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | P1 badge, P2 boosters, P4 drill-downs | Confidence badge, Top Boosters, Calibrating state |
| `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift:12-47` | P1–P4 | Add fixture fields per phase |
| `WellPlate/Core/Services/WidgetRefreshHelper.swift:7-56` | Audit only P2, P4 | Verify `WidgetStressData` shape holds; no schema changes planned |
| `WellPlate/Core/Services/ReportNarrativeGenerator.swift:111-149` | Audit P3 | Confirm "Balanced" band handling |
| `WellPlate/Core/Services/InsightEngine.swift` | P4 | Register burnout/overtraining/paradox detectors |
| `WellPlate/Core/Services/CircadianService.swift` | P3 | Already computes SRI — just consume in V2 signal |
| NEW `WellPlate/Core/Services/PhysioBaselineService.swift` | P4 | 7d/30d rolling avg service |
| NEW `WellPlate/Models/StressScoreShadowLog.swift` | P2 (DEBUG) | Shadow comparison storage |
| `WellPlate/Models/UserGoals.swift:4-41` or NEW `UserProfile.swift` | P3 | Add gender / birth year / OCP fields |
| `WellPlate/Features + UI/Onboarding/` | P3 | 1–2 new screens for profile fields |

---

## 7. Success Metrics for the Rollout

Track these on dev's own device through shadow log + spot checks. No analytics infra needed for a single-developer project.

| Metric | Target | Measured where |
|---|---|---|
| **Factor coverage** — avg # of factors with valid data per day | ≥ 7 of 11 in Base mode, ≥ 9 of 14 in Enhanced mode | `StressScoreShadowLog.factorsUsed` count |
| **Score volatility** — day-over-day delta | 95th pct ≤ 15 points after B4 smoothing | Rolling stddev of `StressReading.score` across 14-day windows |
| **Base ↔ Enhanced transition** — score shift on Day 7 when physio activates | ≤ 8 points absolute | Inspect shadow log at Day 7 boundary |
| **Honest-mode triggers** — days showing "Log more" instead of a number | ≤ 1 per week for an actively-logging user | Count of fall-throughs |
| **v1 → v2 shadow delta** (pre-flip) | Median `|v2-v1|` ≤ 15 pts over 7 days, none >30 | `StressScoreShadowLog.delta` |
| **Top Boosters coverage** — days where at least 1 factor reports negative signal | ≥ 5 of 7 for a user with any healthy behavior | Post-flip UI inspection |
| **Widget / AI report regression** | Zero crashes or rendering issues through all 4 phases | Build + manual run after each phase |
| **Qualitative trust signal** — "does this score match how I actually feel today?" gut check | ≥ 4 of 7 days feel accurate by P4 exit | Dev judgement, logged as text note |

**Definition of "rollout complete":** End of P4 with v2 on by default in release builds, v1 deleted from Services, all mock fixtures updated, and at least 14 days of volatility data meeting the targets above.

---

## 8. Open Risks

| Risk | Mitigation |
|---|---|
| Shadow scoring divergence stays >25 points indefinitely — research curves don't fit real user data | Allow curve retuning in P3 before flipping default; hold flip until delta converges |
| Adding 8+ new factors inflates `loadData()` runtime and UI blocks main actor | Each factor adds a SwiftData fetch or scalar math — trivial; but profile with Instruments at end of P3 to confirm |
| SwiftData migration for `UserProfile`/gender fields breaks existing users | Additive-only fields with defaults; brainstorm's ModelContainer init (`CLAUDE.md` key file) handles this pattern already |
| "Balanced" band confuses users ("why isn't 50 'good'?") — semantic shift from current | U4 calibrating banner + one-time "Your score got smarter" explainer at P3 flip |
| Physio activation Day 7 feels like a magic jump (brainstorm Open Q risk) | Absorption table re-normalizes total to 100; smoothing B4 + gradual baseline warmup over days 4–7 keep shift ≤8 pts |
| Burnout / Stress Paradox insights become spammy | Rate-limit insight card generation in `InsightEngine` to ≤1 per type per week; require concurrent RHR↑+HRV↓ for 2 days before firing |
| Single-dev, no automated tests → regressions in downstream widget/AI report go unnoticed | Manual smoke test checklist at end of each phase: open widget, generate AI report, flip mock mode, compare before/after screenshots |
| Feature flag debt — v1 lingers as dead code | Hard-commit to deleting `StressScoring.swift` one release after P4 ships |

---

## 9. Non-Goals for This Strategy

- **Not** a cross-platform rewrite — iOS only, no watchOS companion app scope.
- **Not** adding Stress Lab experiment annotations in v2 output (brainstorm Open Q5) — handle separately.
- **Not** a "Recovery Score" split (brainstorm Open Q3) — v2 stays a single 0–100 score; recovery is the <50 half of the scale.
- **Not** a medical claim / cortisol estimator — we say "stress indicator", not "cortisol level".
- **Not** backfilling historical `StressReading` rows with v2 scores on flip.
- **Not** multi-user cloud sync of baselines — per-device personal baseline only.
- **Not** Tier 5 items C5/S4/S5 in the main sequence — they are explicitly deferred to P5 pending UX/research unblockers.

---

## 10. Ready-for-Planning Checklist

Before `/develop plan` runs for any phase, these must be true:

- [ ] Brainstorm decision points for that phase (§3, each phase's "Decision points") are resolved and noted in the plan doc
- [ ] Previous phase's exit gate has been met (not just shipped — gate criteria verified on dev device)
- [ ] Mock-mode fixtures for the phase's new signals exist in `StressMockSnapshot`
- [ ] Shadow log (P2+) shows the target delta/volatility bounds

---

**Next step:** Run `/develop plan` against Phase 1 (Tier 0 + U1/U4) to get the detailed implementation plan for the Foundation phase.
