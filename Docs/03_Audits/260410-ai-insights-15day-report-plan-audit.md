# Plan Audit Report: 15-Day AI Insights Report

**Audit Date**: 2026-04-10
**Plan Version**: `Docs/02_Planning/Specs/260410-ai-insights-15day-report-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The plan is thorough, well-structured, and technically feasible. The data pipeline, LLM integration, and view architecture are sound and follow established codebase patterns. However, there are 1 critical issue (struct mutation breaking existing code), 3 high-priority issues (duplicate data model, missing `@Generable` constraint knowledge, report data flow gap), and several medium issues around performance and edge cases that should be addressed before implementation.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: `WellnessDaySummary` is a `let`-only struct with no explicit init — adding fields breaks the existing call site

- **Location**: Plan Step 1.3 — "Extend `InsightModels.swift`"
- **Problem**: `WellnessDaySummary` (line 118 of `InsightModels.swift`) uses all `let` properties with no explicit `init`. Swift generates a memberwise initializer with parameters in declaration order. Adding new `let` fields (even at the bottom) changes the memberwise init signature. The single call site in `InsightEngine.swift:212-240` passes all arguments positionally — it will break.
- **Impact**: Compile error in `InsightEngine.buildWellnessContext()` immediately upon adding any new field.
- **Recommendation**: Either:
  - **(A) Preferred**: Change the new fields to `var` with defaults (`var eatingTriggers: [String: Int] = [:]`) — this keeps them out of the memberwise init. OR
  - **(B)** Add an explicit `init` to `WellnessDaySummary` that gives the new fields default values, preserving backward compatibility with the existing call site. OR
  - **(C)** Update the `InsightEngine.buildWellnessContext()` call site simultaneously in Step 8.1.
  
  Approach (A) is simplest and the plan should explicitly state it. Approach (C) means Step 1.3 and Step 8.1 must be done atomically (they can't be in different phases).

---

### HIGH (Should Fix Before Proceeding)

#### H1: Plan introduces `ReportDaySummary` but also extends `WellnessDaySummary` — dual model confusion

- **Location**: Steps 1.1 and 1.3
- **Problem**: Step 1.1 defines a new `ReportDaySummary` type ("extends `WellnessDaySummary` concept but includes all report-specific per-day fields"). Step 1.3 adds fields to the existing `WellnessDaySummary`. The plan never clarifies the relationship — does `ReportDaySummary` wrap `WellnessDaySummary`? Duplicate it? Extend it? The `ReportContext` in 1.1 says `days: [ReportDaySummary]`, but the section views in Phase 6 aren't told which type they receive.
- **Impact**: Implementer will either create a confusing dual-model or waste time reconciling. If both exist, data will be aggregated twice.
- **Recommendation**: Choose one approach:
  - **(A) Preferred**: Drop `ReportDaySummary`. Extend `WellnessDaySummary` with the new fields (Step 1.3) and use it everywhere. `ReportContext.days` should be `[WellnessDaySummary]`. This avoids duplication and lets both `InsightEngine` and `ReportDataBuilder` produce the same type.
  - **(B)** Keep `ReportDaySummary` as a superset but make it contain a `WellnessDaySummary` plus extra fields — composition over duplication.

#### H2: `@Generable` structs must not contain arrays of `@Generable` — Foundation Models constraint

- **Location**: Step 1.2 — `_ReportSectionNarratives` containing `[_ReportSectionNarrative]`, `_ReportActionPlan` containing `[_ActionRecommendation]`
- **Problem**: Foundation Models `@Generable` supports arrays of `@Generable` types, but there's a practical limit. The existing codebase uses arrays (e.g., `_InsightNarrativeSchema` has `suggestions: [_InsightSuggestionItem]`), so arrays are supported. However, the `_ReportSectionNarratives` schema asks the model to generate narratives for ~10 sections in a single call — this is a very large structured output that may exceed the on-device model's reliable generation capacity. The existing `InsightEngine` generates one card at a time (line 685-703), not a batch.
- **Impact**: Single batch call for all sections may produce low-quality or truncated output. On-device models have shorter context than cloud models.
- **Recommendation**: Follow the existing pattern — generate section narratives one at a time (top 5 most important sections), not as a single batch. Change the 3-call architecture to: (1) Executive Summary, (2) Per-section narratives (loop, up to 5), (3) Action Plan. This increases calls from 3 to ~7 but each is small and reliable.

#### H3: `ReportData` type referenced but never defined

- **Location**: Steps 1.1, 4.1, 6.x, 7.1
- **Problem**: Multiple steps reference `ReportData` as the final output consumed by the view, but it's never defined in the plan. Step 1.1 lists types to create but `ReportData` is only mentioned in `ReportState.ready(ReportData)`. The section views in Phase 6 say they take "a slice of `ReportData`" but its structure is undefined.
- **Impact**: Implementer must invent the structure; section views won't know what to expect.
- **Recommendation**: Define `ReportData` explicitly in Step 1.1:
  ```swift
  struct ReportData {
      let context: ReportContext
      let narratives: ReportNarratives
      let generatedAt: Date
  }
  ```
  Each section view receives the full `ReportData` (it's a value type, cheap to pass) and extracts what it needs.

---

### MEDIUM (Fix During Implementation)

#### M1: Correlation matrix chart is architecturally complex for SwiftCharts

- **Location**: Step 5.1 — `CorrelationMatrixChart`
- **Problem**: Swift Charts `RectangleMark` heatmaps require careful axis configuration when labels are dynamic. With ~8-13 metrics on both axes, label readability is a concern on phone screens. The plan doesn't address rotation, truncation, or abbreviation of axis labels.
- **Impact**: Matrix may be unreadable on smaller screens.
- **Recommendation**: Limit matrix to top 8 metrics max. Use abbreviated labels (e.g., "Sleep", "Stress", "Steps" — not "Exercise Minutes"). Consider a `Canvas`-based custom renderer instead of Swift Charts for more layout control.

#### M2: `SectorMark` availability not verified

- **Location**: Step 6.9 — Symptom category breakdown "donut chart (`SectorMark` on iOS 17+)"
- **Problem**: `SectorMark` was introduced in iOS 17. The project targets iOS 26.1, so it's available, but the plan casually mentions it without confirming. More importantly, `SectorMark` is not used anywhere in the existing codebase (verified: 0 matches).
- **Impact**: Low — it will work, but it's a new API pattern for this codebase.
- **Recommendation**: Use it. It's fine for iOS 26+. Just note it's the first `SectorMark` usage in the project.

#### M3: Food-symptom "day before" matching needs timezone care

- **Location**: Step 2.2 — "same day, or day before for delayed reactions"
- **Problem**: "Day before" requires subtracting 1 calendar day from the symptom day, then checking if food was logged on that date. If the user's timezone changes (e.g., travel), `Calendar.current.startOfDay` could produce unexpected results. The existing codebase uses `Calendar.current` consistently, but the "day before" logic is novel.
- **Impact**: Edge case — could produce false positives in food-symptom links for users who travel.
- **Recommendation**: Use `Calendar.current.date(byAdding: .day, value: -1, to: symptomDay)` consistently. Document the assumption.

#### M4: 15-day window offset is wrong

- **Location**: Step 2.1 — "Calendar.current.startOfDay(for: .now) minus 14 days through today = 15-day window"
- **Problem**: This is actually correct (today + 14 previous days = 15 days). But the existing `InsightEngine` uses `lookbackDays = 14` which produces 14 days (not 15). The report uses 15. This inconsistency means the report and the hub cards will cover slightly different windows.
- **Impact**: Confusing if a user sees "14-day" insights in the hub and "15-day" in the report.
- **Recommendation**: Either align both to 15 days, or clearly label the report as "Last 15 days" and the hub as "Last 14 days". The brainstorm explicitly says 15 is the hard cap, so this is intentional.

#### M5: Missing `coffeeType` aggregation in data builder

- **Location**: Step 2.1 — data builder loop, and Section 7 (Hydration & Caffeine)
- **Problem**: Section 7b says "coffee type distribution" but neither `WellnessDaySummary` nor the proposed `ReportDaySummary` includes a `coffeeType` field. `WellnessDayLog` has `coffeeType: String?` but it's not carried into the per-day summary.
- **Impact**: Coffee type distribution chart won't have data.
- **Recommendation**: Add `coffeeType: String?` to the per-day summary, or aggregate coffee types directly from `WellnessDayLog` in the section view.

#### M6: Intervention stress delta depends on reading proximity — could yield few results

- **Location**: Step 2.4 — "find the closest StressReading before startedAt within 2 hours"
- **Problem**: `StressReading` is captured "whenever the computed stress value changes" (auto-refresh). If the user doesn't open the Stress tab before/after a PMR session, there may be no readings within the 2-hour window. The plan acknowledges "skip that session" but doesn't address the case where ALL sessions are skipped.
- **Impact**: Intervention effectiveness section may be empty even when sessions exist.
- **Recommendation**: Widen the window to 4 hours, or show the section header with "Not enough nearby stress readings to measure effectiveness" rather than hiding entirely.

#### M7: No loading shimmer / skeleton specified

- **Location**: Step 7.1 — `.generating` state shows "progress view with generationProgress bar + shimmer placeholders"
- **Problem**: "Shimmer placeholders" is vague. How many? What shape? The existing `InsightsHubView` uses a simple `ProgressView()` with text. No shimmer exists in the codebase.
- **Impact**: UI will look generic during generation. Not a blocker but affects polish.
- **Recommendation**: Use the same pattern as `InsightsHubView.loadingView` — centered `ProgressView` with descriptive text + progress percentage. Skip shimmer for V1.

---

### LOW (Consider for Future)

#### L1: 20 new files is high for a single feature

- **Location**: Entire plan
- **Problem**: 20 new files + 3 modified. This is the largest single-feature change proposed. While each file is focused, the sheer count increases merge risk and review burden.
- **Impact**: Low — the project uses `PBXFileSystemSynchronizedRootGroup` so no pbxproj conflicts. But code review will be lengthy.
- **Recommendation**: Consider merging some section views that are very small (e.g., `MoodSection` is ~40 lines, `FastingSection` is ~50 lines) into a single `MinorSections.swift` file. This is a style preference, not a blocker.

#### L2: No accessibility plan

- **Location**: Missing from plan entirely
- **Problem**: Charts are notoriously poor for VoiceOver. The plan doesn't mention `.accessibilityLabel` for any chart or stat pill.
- **Impact**: Low for V1, but should be addressed before App Store release.
- **Recommendation**: Add a note in each chart component to include `accessibilityLabel` with the key stat (e.g., "Stress trend: declining from 72 to 48 over 15 days").

#### L3: No unit test strategy for `ReportDataBuilder`

- **Location**: Testing Strategy section
- **Problem**: Testing strategy only mentions build verification and manual flows. `ReportDataBuilder` is a pure computation service that could be unit tested with `MockHealthKitService` and in-memory SwiftData context.
- **Impact**: Low for V1, but the food-symptom correlation logic is complex enough to warrant tests.
- **Recommendation**: Add as a future enhancement. The `MockHealthKitService` and `MockDataInjector` already exist in the codebase, making test setup straightforward.

---

## Missing Elements

- [x] `ReportData` type definition (H3)
- [x] `coffeeType` in per-day summary (M5)
- [ ] Explicit approach for `WellnessDaySummary` mutation (C1) — must be decided
- [ ] Relationship between `ReportDaySummary` and `WellnessDaySummary` (H1) — must be decided
- [ ] Foundation Models call strategy — batch vs per-section (H2) — must be decided
- [ ] Accessibility annotations for charts (L2) — defer to V2

## Unverified Assumptions

- [x] `SectorMark` available on target iOS — **verified**: iOS 17+, project targets iOS 26.1
- [x] `PBXFileSystemSynchronizedRootGroup` handles new subdirectories — **verified**: 6 occurrences in pbxproj
- [x] `MockHealthKitService` supports all vital fetch methods — **verified**: all methods present
- [x] `WellnessDaySummary` has no explicit init — **verified**: all `let` properties, memberwise init only
- [ ] Foundation Models can handle 7+ sequential calls without session degradation — Risk: Low (each call is independent `LanguageModelSession()`)
- [ ] `CorrelationMath.bootstrapCI` performance with 13 metric pairs x 1000 iterations — Risk: Low (existing code does this; 15 days of data is small)

## Questions for Clarification

None — all decisions were locked in the brainstorm. The issues above are implementation-level fixes, not requirement questions.

---

## Recommendations

1. **Fix C1 first**: Decide on `var` with defaults (approach A) for the new `WellnessDaySummary` fields. This is the cleanest solution and unblocks everything.
2. **Resolve H1**: Drop `ReportDaySummary`. Use extended `WellnessDaySummary` everywhere. `ReportContext.days` is `[WellnessDaySummary]`.
3. **Fix H2**: Switch to per-section FM calls (loop over top 5 sections) instead of single batch. Follow existing `InsightEngine` pattern.
4. **Define H3**: Add `ReportData` to the types list in Step 1.1.
5. **Merge Steps 1.3 and 8.1**: Since `WellnessDaySummary` changes and `InsightEngine` call-site update must happen together, combine them into one step to prevent a broken intermediate state.
