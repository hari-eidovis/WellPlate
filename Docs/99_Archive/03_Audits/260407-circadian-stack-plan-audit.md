# Plan Audit Report: F3. Circadian Stack

**Audit Date**: 2026-04-07
**Plan Version**: `Docs/02_Planning/Specs/260407-circadian-stack-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The plan is well-structured, follows established codebase patterns, and correctly identifies most affected files. However, it has one critical gap around `DailySleepSummary` memberwise init compatibility and several high-priority omissions — most notably a missing call site, inconsistent score types, and unclear `timeInDaylight` unit handling. All issues are fixable without changing the overall approach.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. `DailySleepSummary` memberwise init will break existing call sites unless defaults are specified

- **Location**: Step 1.1 — Extend `DailySleepSummary`
- **Problem**: The plan shows adding `let bedtime: Date?` and `let wakeTime: Date?` to the struct. Swift auto-generates a memberwise init including ALL stored properties in declaration order. Without explicit default values (`= nil`), every existing construction site must be updated to pass the new parameters — including sites the plan doesn't mention.
- **Impact**: Build failure in at least 4 call sites:
  1. `HealthKitService.swift:168` — plan covers this ✅
  2. `StressMockSnapshot.swift:63` (`sleepToday`) — plan does NOT mention this ❌
  3. `StressMockSnapshot.swift:157` (30-day history loop) — plan covers this ✅
  4. `SleepStageBarView.swift:62` (#Preview) — plan does NOT mention this ❌
- **Recommendation**: Declare with default values: `let bedtime: Date? = nil` and `let wakeTime: Date? = nil`. This preserves backward compatibility for all existing call sites. Alternatively, explicitly list ALL 4 construction sites in the plan. The default value approach is strongly preferred — it's safer and future-proof.

---

### HIGH (Should Fix Before Proceeding)

#### H1. Missing call site: `StressMockSnapshot.sleepToday` (line 63)

- **Location**: Step 1.6
- **Problem**: Step 1.6 discusses updating the 30-day history sleep array (line 152–159) and adding daylight data, but never mentions updating the standalone `sleepToday` summary (line 63) which is used for today's factor scoring. If defaults are used (C1 fix), this is automatically handled. If not, this is a build failure.
- **Impact**: Build failure or, if defaults are used, `sleepToday` will have `nil` bedtime/wakeTime — which is correct for a "today" snapshot since today's sleep is the most recent summary, but it means mock mode won't show bedtime data for "tonight."
- **Recommendation**: If using `= nil` defaults (C1), this is fine. Otherwise, explicitly update `sleepToday` to include bedtime/wakeTime mock values.

#### H2. Missing call site: `SleepStageBarView` #Preview (line 62)

- **Location**: Step 1.1 (ripple effect)
- **Problem**: The plan lists `SleepStageBarView.swift` as "possibly affected" in the strategy but doesn't include it in the implementation steps. The #Preview macro constructs a `DailySleepSummary` directly.
- **Impact**: Build failure if defaults are not used.
- **Recommendation**: Either use `= nil` defaults (C1, resolves this automatically) or add an explicit step to update the preview.

#### H3. `CircadianResult` score types use `Int` — codebase uses `Double` for scores

- **Location**: Step 2.1 — `CircadianService.CircadianResult`
- **Problem**: The result struct defines `score: Int`, `regularityScore: Int`, `daylightScore: Int?`. The existing codebase consistently uses `Double` for all scoring values (`StressScoring` returns `Double`, `StressFactorResult.score` is `Double`, `StressViewModel.totalScore` is `Double`).
- **Impact**: Not a build failure, but an inconsistency that will require `Double(...)` conversions in views and potentially lose precision during SRI calculation. May cause future confusion.
- **Recommendation**: Use `Double` for all score fields in `CircadianResult` to match codebase conventions. Format to `Int` in the view layer only (e.g., `Text("\(Int(result.score))")`).

#### H4. `timeInDaylight` unit verification needed

- **Location**: Step 1.4 — `fetchDaylight` uses `.minute()`
- **Problem**: The plan uses `HKUnit.minute()` for `fetchDailySum`. HealthKit's `timeInDaylight` stores data as a time quantity. The correct unit must be verified — Apple's documentation references this as "time" but doesn't always specify the stored unit. If the underlying data is in seconds (common for HK time quantities), requesting `.minute()` via `doubleValue(for:)` should still work (HealthKit converts automatically), but this is an unverified assumption.
- **Impact**: If unit conversion fails, daylight values will be 0 or nonsensical. Low probability since HealthKit handles unit conversion, but the plan should acknowledge this.
- **Recommendation**: Add a verification step: after first successful `fetchDaylight` call, log the raw value and confirm it's in a reasonable range (5–120 minutes/day). Include this in the manual testing checklist.

---

### MEDIUM (Fix During Implementation)

#### M1. SRI formula: equal weighting of bedtime and wake time SD

- **Location**: Step 2.1 — SRI formula
- **Problem**: The plan averages bedtime SD and wake time SD equally. The brainstorm's open questions note that "research suggests wake time consistency is more important for circadian entrainment." Weighting wake time more heavily (e.g., 60/40 or 70/30) would better reflect the science.
- **Impact**: Score accuracy for users with consistent wake times but variable bedtimes (alarm users). Low urgency — can be tuned later.
- **Recommendation**: Consider 60/40 weighting (wake:bed) during implementation. Or start with equal weights and log both SDs for future tuning.

#### M2. Accessibility not addressed

- **Location**: Steps 4.1, 4.2 (CircadianCardView, CircadianDetailView)
- **Problem**: No mention of VoiceOver labels, accessibility traits, or chart accessibility. The existing factor cards and vitals grid presumably handle this (or don't), but the plan should at minimum match whatever the existing views do.
- **Impact**: Accessibility regression if existing views have VoiceOver support and new views don't.
- **Recommendation**: Add a note to follow the same accessibility pattern as existing `StressFactorCardView` / `vitalsGridSection`.

#### M3. No error state for HealthKit `timeInDaylight` authorization denial

- **Location**: Step 1.4, Step 3.1
- **Problem**: The plan says "If the user previously denied daylight, we get zero samples and degrade gracefully." This is correct, but it should clarify: HealthKit doesn't tell you *why* you got zero samples (denial vs. no Watch vs. no data). The graceful degradation path (regularity-only) handles all three identically, which is the right UX — but the plan should state this explicitly.
- **Impact**: None functionally. Clarity issue only.
- **Recommendation**: Add a note: "Zero daylight samples = no Watch, authorization denied, or genuinely zero daylight. All three degrade identically to regularity-only mode. No distinction is made or shown to the user."

#### M4. `showInsights = false` + `activeSheet = .circadian` animation timing

- **Location**: Step 4.3 — Action C
- **Problem**: Dismissing the insights sheet (`showInsights = false`) and immediately setting `activeSheet = .circadian` may cause SwiftUI to attempt two sheet transitions simultaneously. The existing factor cards in `factorsSection` already use this pattern (`activeSheet = sheet; showInsights = false`), so if it works there, it works here. But this should be verified during implementation.
- **Impact**: Potential janky transition or sheet not appearing. Low probability since existing code uses this pattern.
- **Recommendation**: Test during implementation. If sheet transition is janky, wrap `activeSheet` assignment in `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)` — same workaround used elsewhere in the codebase if needed.

---

### LOW (Consider for Future)

#### L1. Circadian Score level labels not defined

- **Location**: Step 4.1, 4.2
- **Problem**: The plan references showing a score but doesn't define circadian quality labels (e.g., "Excellent / Good / Fair / Poor"). The existing `StressLevel` and `SleepQuality` enums map scores to labels. `CircadianResult` should include a label or the view should derive one.
- **Impact**: UX inconsistency — other scores have descriptive labels.
- **Recommendation**: Add a `level` property to `CircadianResult` (e.g., `Aligned / Adjusting / Disrupted`) or compute it in the view from the score.

#### L2. No dark mode consideration for chart colors

- **Location**: Step 4.2 — CircadianDetailView charts
- **Problem**: Chart colors for the sleep regularity and daylight bars aren't specified. The existing codebase uses `SleepStage.color`, `BurnMetric.accentColor`, etc. for chart colors.
- **Impact**: Charts may look inconsistent if generic colors are used.
- **Recommendation**: Define semantic colors for circadian sub-scores (regularity → indigo/purple tones matching sleep, daylight → warm amber/gold).

#### L3. 30-day fetch for 7-day scoring is over-fetching for the card

- **Location**: Step 3.1
- **Problem**: The plan fetches 30 days of daylight data (`thirtyDayRange`) but only uses the last 7 for scoring. This is intentional (for the detail view charts showing 30-day trends), but it means the CircadianService computes over filtered data. The plan correctly notes this ("Using the 30-day range for fetching but filtering to 7 days for scoring"). No issue, just confirming.
- **Impact**: None — this is by design.

---

## Missing Elements

- [ ] Default values for `bedtime` and `wakeTime` in `DailySleepSummary` declaration (C1)
- [ ] Explicit update for `StressMockSnapshot.sleepToday` (H1, resolved if C1 is fixed with defaults)
- [ ] Explicit update for `SleepStageBarView` #Preview (H2, resolved if C1 is fixed with defaults)
- [ ] Circadian quality level labels (L1 — can be added during implementation)
- [ ] `DEBUG` log statements for circadian scoring (match the existing logging pattern in `loadData()`)

---

## Unverified Assumptions

- [ ] `HKQuantityTypeIdentifier.timeInDaylight` exists and is available on iOS 26 — **Risk: Low** (documented in Apple's HealthKit framework since iOS 17)
- [ ] `HKUnit.minute()` is the correct unit for `fetchDailySum` on daylight data — **Risk: Low** (HealthKit auto-converts time units, but verify with real device)
- [ ] `showInsights = false` + `activeSheet = .circadian` works without animation conflicts — **Risk: Low** (same pattern used by existing factor cards)
- [ ] Adding `.timeInDaylight` to `readTypes` doesn't trigger a new authorization prompt for existing users — **Risk: Low** (HealthKit batches all types into one request; new types are silently included)

---

## Questions for Clarification

1. Should `CircadianResult` scores use `Double` (matching codebase) or `Int` (as planned)?
2. Should SRI weight wake time more heavily than bedtime (research suggests wake consistency matters more)?
3. Should the circadian card appear in `StressImmersiveView` as well, or only in the insights sheet?

---

## Recommendations

1. **Fix C1 first**: Declare `let bedtime: Date? = nil` and `let wakeTime: Date? = nil` in the struct. This resolves C1, H1, and H2 in one line.
2. **Use `Double` for scores**: Match the codebase convention (H3).
3. **Add `#if DEBUG` logging**: In StressViewModel after computing circadian, add a log line matching the existing factor logging format.
4. **Test `timeInDaylight` on a real Watch-paired device** before marking the feature as complete.
5. **Add circadian level label** (e.g., `Aligned / Adjusting / Disrupted`) to `CircadianResult` for consistent UX.
