# Plan Audit Report: Hydration Timing in Stress Engine

**Audit Date:** 2026-05-27
**Plan Audited:** [`Docs/02_Planning/Specs/260527-hydration-timing-stress-plan.md`](../02_Planning/Specs/260527-hydration-timing-stress-plan.md)
**Auditor:** audit agent
**Verdict:** **NEEDS REVISION** — one CRITICAL compile-blocker, two HIGH calibration issues, several MEDIUM polish items. None are architectural; all are fixable in-place during `/develop resolve`.

---

## Executive Summary

The plan's data-model and writer changes are sound and additive. The engine extension is well-shaped (bolus + late-bunch + backfill clamp, hard-capped at `Weights.hydration = 5`). However, the plan misreads the surrounding scoring function and asserts that `now: Date` is "already in scope" at the `hydrationPoints` call site — it is not. Threading `now` requires changes the plan doesn't enumerate, or (preferred) dropping the `now` param entirely because the function never actually uses `now` distinctly from the timestamps themselves. Two calibration issues also need attention before implementation: the bolus penalty as drafted punishes legitimate pre-workout hydration, and the backfill-clamp condition `r >= 0.5` quietly inflates penalties in the mid-r band, which may or may not be intended but is undocumented.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. `allFactors` does not have `now` in scope — plan Step 2.3 will not compile as written
- **Location:** Plan §Implementation Steps · Phase 2 · 2.3 ("Pass `now` from the call site"); also implicit in 2.2's signature change.
- **Problem:** The plan changes `hydrationPoints` to require `now: Date`, then claims at Step 2.3 that "the surrounding `allFactors(inputs:now:)` (or equivalent — confirm at line 800-815) already has `now` in scope." Source-code check shows `allFactors` is declared `static func allFactors(inputs: StressInputs) -> [FactorPoints]` at `StressScoring.swift:805` — no `now`. The three callers (`engagementPenalty:613`, `engagementBreakdown:658`, `computeStress:827`) each *have* `now` in their own bodies but do not pass it to `allFactors`. The call site at `:812` is inside `allFactors` and cannot reference `now` without a signature change to `allFactors` itself, which cascades to all three callers.
- **Impact:** Code won't compile. Beyond the immediate fix, this is a load-bearing assumption error — the auditor should not approve the plan as written.
- **Recommendation:** Pick one of two paths and update Steps 2.2 + 2.3 accordingly:
  - **(Preferred) Drop the `now` parameter from `hydrationPoints`.** The function never uses `now` for anything except — in the draft — symmetry with `engagementPenalty`. Every distribution check operates on `input.timestamps` directly via `Calendar.current.component(.hour, from: $0)`, which does not need `now`. Result: zero changes to `allFactors` and its three callers; only the `hydrationPoints(input:goal:)` body changes.
  - **(Alternative) Thread `now: Date` through `allFactors`.** Update its signature to `static func allFactors(inputs: StressInputs, now: Date) -> [FactorPoints]` and update all three call sites (`:615`, `:660`, `:827`). This is a wider blast radius but keeps the option of future time-aware factors open.

The plan's "Calendar.current in pure function reduces testability" risk row already concedes the impurity is pre-existing, which supports the simpler preferred path.

---

### HIGH (Should Fix Before Proceeding)

#### H1. Bolus penalty punishes legitimate intentional hydration
- **Location:** Plan §2.2 — bolus ladder `burst >= 3 → +1`, `>= 4 → +2`, `>= 6 → +3`.
- **Problem:** A user doing pre-workout hydration (3 glasses in 30 minutes at 09:00, goal=8) lands at `glasses=3`, `r=0.375`, base `pts=3`, bolus `+1` → **total 4**, vs. the previous **3**. We've made a hydration-positive behavior look *worse* than logging the exact same intake with a 1-hour gap. The bolus ladder fires regardless of total intake or time of day.
- **Impact:** Engine signal becomes anti-correlated with healthy intent. Users who notice (especially via the StressView factor breakdown) may stop logging quick clusters honestly to avoid the hit — which is exactly the gaming behavior the schema change was meant to *prevent*.
- **Recommendation:** Make the bolus penalty conditional on context — at least one of:
  - **Gate by `r >= 0.6`** so bolus only fires once the user is past the "trying to catch up" zone. Below 0.6, no bolus penalty; the base ratio penalty (3 or 5) already reflects "not enough water."
  - **Or gate by time of day** — only apply bolus after 18:00, when fast intake genuinely correlates with sleep disruption.
  - **Or both.** Whichever, the choice and threshold should be stated explicitly in the plan body (not just inline in code) so the resolve / audit cycle can challenge it.

#### H2. Backfill clamp condition `r >= 0.5` silently inflates the r∈[0.5, 0.8) band
- **Location:** Plan §2.2 — `if let lo = ts.min(), let hi = ts.max(), hi.timeIntervalSince(lo) < 600, r >= 0.5 { pts = max(pts, 3) }`.
- **Problem:** The clamp is described as "prevent the goal-ratio reward from firing when timestamps are clustered." In practice the comparison `max(pts, 3)` *increases* the penalty in both the goal-met zone (r≥0.8, base 0 → 3) **and** the partial-credit zone (0.5≤r<0.8, base 1 → 3). The plan body doesn't acknowledge the second behavior, which is a 2-point silent jump for users who logged, say, 5 of 8 glasses all at once.
- **Impact:** Could be intentional ("backfilling 5 glasses at once should also be suspect") or accidental. As-written, the plan reads as if only the reward case (r≥0.8) is targeted. Future maintainers will not know which is the design.
- **Recommendation:** Either:
  - Tighten condition to `r >= 0.8` so the clamp only suppresses unearned zero-penalty rewards (matches the prose description), **or**
  - Keep `r >= 0.5` and explicitly document in the plan that the clamp also lifts mid-band penalties to encourage realistic logging. Either is defensible; the silence is what's wrong.

---

### MEDIUM (Fix During Implementation)

#### M1. `detail` string offers no UX explanation when distribution penalties fire
- **Location:** Plan §2.2 — `let detail = "\(input.glasses) of \(goalSafe) glasses"`.
- **Problem:** A user who logged 8 of 8 glasses and sees the hydration factor reading "+4" with detail "8 of 8 glasses" has no way to understand why. StressView shows the detail string directly on the factor card.
- **Recommendation:** Append a hint when distribution penalties fire — e.g., `"8 of 8 glasses · logged in burst"` or `"... · mostly after 21:00"`. Bonus: makes manual smoke-tests in Phase 4 instantly verifiable without a debugger.

#### M2. `MockDataInjector` never exercises the bolus or late-bunch paths
- **Location:** Plan §3.1 — `spreadTimestamps` distributes evenly across 08:00–22:00.
- **Problem:** The 30 seeded rows will all look like "healthy" distribution. The new code paths only run if the dev manually constructs a bad day via `StressMockSnapshot`, which is not the default preview path on Home/Stress tabs in mock mode.
- **Recommendation:** In `MockDataInjector`, seed at least 2-3 days (e.g., `offset % 10 == 0` and `offset % 10 == 1`) with clustered late timestamps so the bolus/late penalty surfaces in default mock previews. Lets reviewers see the factor without code-level intervention.

#### M3. Magic numbers should be named constants
- **Location:** Plan §2.2 — `3600`, `600`, `21`, `[3, 4, 6]` ladder, `0.5` percentage, `0.5` r-floor.
- **Problem:** Tuning during Phase 4 ("threshold-tuning needed") becomes a grep hunt across an inline switch. Tests can't import the numbers symbolically.
- **Recommendation:** Add a small private enum next to `Weights`:
  ```swift
  private enum HydrationDistribution {
      static let bolusWindow: TimeInterval = 3600
      static let bolusThresholds: [(Int, Double)] = [(6, 3), (4, 2), (3, 1)]
      static let lateHourCutoff: Int = 21
      static let lateRatioMin: Double = 0.5
      static let lateGlassesMin: Int = 4
      static let backfillSpan: TimeInterval = 600
      static let backfillRatioMin: Double = 0.5
      static let backfillFloor: Double = 3
      static let distributionMinTimestamps: Int = 3
  }
  ```
- **Why:** Stress engine tuning has historically required several iterations (see `260420-stress-algorithm-phase1-plan.md` and `260509-stress-algorithm-v3-plan.md`); naming constants now avoids a refactor later.

#### M4. Schema-invariant `assert` would mis-fire on legacy rows
- **Location:** Plan §Risks & Mitigations — "Debug-only `assert(log.waterGlasses == log.waterLogTimestamps.count)` in `StressViewModel.loadData`."
- **Problem:** Legacy rows (and rows freshly created via the new code before any glasses are logged) will have `waterGlasses > 0` and `waterLogTimestamps.count == 0` in two specific cases:
  - Pre-migration data (default `[]` decoded into rows that had nonzero `waterGlasses` before the schema change).
  - The `WellnessDayLog` init that supplies `waterGlasses` but defaults `waterLogTimestamps = []` — used by `MockDataInjector` *before* the Phase 3.1 update lands, and by any test fixture that hasn't been updated yet.
- **Recommendation:** Change the assert to: `assert(log.waterLogTimestamps.isEmpty || log.waterLogTimestamps.count == log.waterGlasses)`. This lets legacy/empty arrays through while still catching post-write drift.

#### M5. SwiftData lightweight migration is asserted but not verified
- **Location:** Plan §Phase 1 · 1.1, Risks table.
- **Problem:** The plan claims "default value makes the SwiftData migration automatic." This is the documented behavior for property additions with defaults under SwiftData on iOS 17.4+, but the project targets iOS 26.1, and Cadence's `WellnessDayLog` is a real persisted store with prior user data. There's no explicit verification step in Phase 4.
- **Recommendation:** Add to Phase 4 manual verification: "Launch on a simulator with an existing CadenceApp build's `default.store` already containing `WellnessDayLog` rows — confirm the app launches, those rows load with `waterLogTimestamps == []`, and writing a new glass appends correctly." If migration fails, document the DEBUG-only fallback (delete-and-reseed) before merging.

---

### LOW (Consider for Future)

#### L1. `timestamps.count >= 3` gate skips 1–2 glass days — confirmed safe, but worth a comment
- **Location:** Plan §2.2 — `if ts.count >= 3 { ... }`.
- **Analysis:** For 1–2 glasses, base penalty is already at maximum (r<0.3 → 5). No room for further penalty without breaching the `Weights.hydration = 5` cap, so skipping is mathematically safe.
- **Recommendation:** Add a 1-line code comment explaining why the gate is safe so a future reader doesn't try to "fix" it.

#### L2. Bolus penalty is purely count-based; ignores glass size
- **Location:** Plan §2.2.
- **Problem:** `WaterDetailView` already accepts `cupSizeML: 250` in its initializer (line 298). If cup size is ever surfaced as a user setting, "6 small glasses in an hour" and "6 large glasses in an hour" become very different physiologically.
- **Recommendation:** Defer. Note the dependency so a future cup-size feature lands with hydration weighting in scope.

#### L3. No call-site enumeration for *read* paths
- **Observation:** The plan correctly identifies all four `waterGlasses` *write* paths. It does not enumerate the eight+ *read* paths (`InsightEngine`, `ReportDataBuilder`, `SymptomCorrelationEngine`, `WellnessReportGenerator`, `ProgressInsightsView`, `WellnessCalendarView`, etc.) that currently read `waterGlasses` only. None of them need to change today, but a brief "read paths intentionally untouched" line in the plan would document the conscious scope choice.

#### L4. Phase 4 case-3 timing is wrong
- **Location:** Plan §Phase 4 — "Tap +1 eight times within 10 seconds. Hydration factor should clamp to ≥3 (not 0)."
- **Problem:** Eight rapid taps at `goal=8` gives r=1.0, base pts=0, plus backfill clamp lifts to **3**. The plan says "≥3", which is technically right, but the actual expected value is exactly `max(3, base + bolus + late)`. If it's afternoon, bolus burst=8 → +3, so total would be 0+3 = 3 → clamp no-op → 3. If it's after 21:00, +1 late as well → 0+3+1 = 4. Document the expected value precisely per time-of-day, otherwise the smoke test is too loose to catch a bug.

#### L5. Pure-function purity is acknowledged-as-broken but not fixed
- **Location:** Plan §Risks.
- **Recommendation:** Acceptable as-is. Noted in case a future engine refactor parameterizes `Calendar` (e.g., for replay-style tests).

---

## Missing Elements

- [ ] Explicit decision on how to resolve C1 (drop `now` param vs. thread it through `allFactors`).
- [ ] Documented design intent for H2 (does the backfill clamp target only r≥0.8 or also mid-band?).
- [ ] Cup-size dependency note (L2).
- [ ] Migration verification step in Phase 4 (M5).
- [ ] Precise expected-value table for Phase 4 smoke cases (L4).
- [ ] One-line "read paths intentionally untouched" scope statement (L3).

---

## Unverified Assumptions

- [ ] **SwiftData lightweight migration adds `[Date] = []` automatically on iOS 26.1.** Risk: Medium. Verified pattern: yes for scalar properties with defaults; arrays of `Date` are less common but follow the same `@Attribute` rules. Recommend Phase 4 verification step.
- [ ] **No code path mutates `waterGlasses` outside the four enumerated writers.** Risk: Low. Verified by `grep -rn 'waterGlasses\s*=' Cadence` during planning — only four assignment sites found, all enumerated.
- [ ] **`StressMockSnapshot.recentWellnessLogs` builder is the only `WellnessDayLog` constructor in the snapshot file.** Risk: Low. The plan flags six `waterGlasses:` sites and instructs the implementer to check each — adequate guidance.
- [ ] **`WaterDetailView.toggleGlass(at:)` already routes through `updateGlasses(_:)`.** Risk: Low. Confirmed at `WaterDetailView.swift:259-268` — both branches call `updateGlasses(_:)`.

---

## Questions for Clarification

1. **C1 resolution:** Drop `now` from `hydrationPoints` (preferred — simpler) or thread `now` through `allFactors` (broader change)?
2. **H1 calibration:** Gate the bolus penalty by `r ≥ 0.6`, by `hour ≥ 18`, both, or neither?
3. **H2 intent:** Does the backfill clamp target only the goal-met case (r ≥ 0.8) or also the mid-band (r ∈ [0.5, 0.8))?
4. **M2 mock coverage:** Acceptable to add 2–3 "bad-distribution" days to `MockDataInjector` in addition to the new `StressMockSnapshot` scenario, or keep mock injector "healthy-only"?

---

## Recommendations (Prioritized)

1. **Fix C1** before any implementation begins — chose the simpler "drop `now`" path unless there's a near-term plan that needs time-of-day awareness in `hydrationPoints`.
2. **Decide H1 calibration** explicitly in the resolve doc. The current ladder will frustrate active users; gating by `r` or hour is a small change with big UX upside.
3. **Decide H2** — document the design or tighten the condition.
4. **Adopt M3 (named constants)** before merging. Cheap, materially helps testing and tuning.
5. **Adopt M4 (fixed assert)** to avoid false positives on legacy rows.
6. **Add M5 migration verification step** to Phase 4.
7. Optional polish (M1, M2, L1, L4) can roll into implementation without further audit.

---

## Verdict Detail

The plan is one well-targeted resolve pass away from green. There's no architectural rework, no schema redesign, no scope ambiguity — just a misread function signature, two calibration decisions to make explicit, and a handful of polish items. Recommended next step: **`/develop resolve Docs/03_Audits/260527-hydration-timing-stress-plan-audit.md`**.
