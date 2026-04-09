# Plan Audit Report: AI Insights V2

**Audit Date**: 2026-04-10
**Plan Version**: `Docs/02_Planning/Specs/260410-ai-insights-v2-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The plan is thorough and well-structured with clear phasing, concrete file paths, and strong alignment with existing codebase patterns. The `InsightEngine` architecture correctly mirrors `StressInsightService`. However, there are 2 HIGH issues (missing `Identifiable` conformance for `.sheet(item:)`, and `ContextualActionBar` state enum gap) and several MEDIUM issues (font convention violations, missing `StressScoring` dependency, no `onAppear` auto-generation for daily card) that should be addressed before implementation.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

*None found.*

### HIGH (Should Fix Before Proceeding)

#### H1: `InsightCard` must conform to `Identifiable` AND `Hashable` for `.sheet(item:)`
- **Location**: Phase 4, Step 4.3 — `InsightsHubView` uses `.sheet(item: $selectedCard)`
- **Problem**: SwiftUI's `.sheet(item:)` requires `Binding<Item?>` where `Item: Identifiable`. The plan defines `InsightCard: Identifiable` which satisfies this. HOWEVER, `@State private var selectedCard: InsightCard?` requires `InsightCard` to be a value type (struct) — which it is. But `InsightChartData` contains arrays of tuples and closures-like associated values, making automatic `Equatable` synthesis impossible. SwiftUI will crash or behave unpredictably if it can't determine identity changes.
- **Impact**: Runtime crash or infinite sheet re-presentation.
- **Recommendation**: Either (a) make `InsightCard` use a separate `detailCardID: UUID?` state with a computed property to look up the card, avoiding `.sheet(item:)` entirely, or (b) manually conform `InsightCard` to `Equatable` using only `id` (since UUID is unique). Option (b) is simpler:
  ```swift
  extension InsightCard: Equatable {
      static func == (lhs: InsightCard, rhs: InsightCard) -> Bool { lhs.id == rhs.id }
  }
  extension InsightCard: Hashable {
      func hash(into hasher: inout Hasher) { hasher.combine(id) }
  }
  ```

#### H2: `ContextualBarState.stressActionable` navigates to insights but plan doesn't update the enum
- **Location**: Phase 5, Step 5.1 — HomeView contextual bar integration
- **Problem**: The `ContextualBarState` enum has a `.stressActionable(level:)` case whose `onSeeInsight` closure is called from the bar. The plan updates the `onSeeInsight` closure in HomeView (line 193-195) to navigate to `InsightsHubView`. However, the bar also has an `onStressTab` action for the same state. The plan should clarify that the `.stressActionable` state's "See Insight" button now opens the insights hub (not the old stress-only report), which is a UX change worth noting.
- **Impact**: Low risk of bugs, but UX change should be intentional.
- **Recommendation**: Add a note in Step 5.1 confirming this is the intended behaviour — the "See Insight" action from the stress-actionable bar state now opens the multi-domain hub rather than the old stress-only report.

### MEDIUM (Fix During Implementation)

#### M1: Font convention violation throughout plan
- **Location**: All view code snippets in Phase 4
- **Problem**: The plan uses `.font(.system(size: ..., weight: ..., design: .rounded))` directly. The project convention (per CLAUDE.md) is `.font(.r(.headline, .semibold))` — a custom extension. The existing `HomeAIInsightView` also uses `.system(size:)` directly, so this is an inherited pattern, but new code should follow the convention.
- **Impact**: Inconsistency with the rest of the codebase.
- **Recommendation**: Use `.r()` font extension where possible for semantic sizes (headline, subheadline, caption, etc.). Fall back to `.system(size:)` only for non-standard sizes that don't map to a semantic category. Note: the existing `HomeAIInsightView` also violates this — it was written before the convention was established.

#### M2: Missing `StressScoring` dependency awareness
- **Location**: Phase 2, Step 2.1
- **Problem**: `StressScoring.swift` contains "pure, stateless scoring functions shared by StressViewModel and StressInsightService" (per its comment). The plan removes `StressInsightService` but doesn't check if `StressScoring` has any coupling to it. Verified: `StressScoring` is used by `StressViewModel` independently and has no import/reference to `StressInsightService`. However, if `InsightEngine` needs to compute stress scores from raw data (not just read stored `StressReading.score`), it may need `StressScoring`.
- **Impact**: Low — `InsightEngine` reads pre-computed `StressReading.score` values, not raw vitals. But this should be noted.
- **Recommendation**: Add a note that `InsightEngine` consumes pre-computed `StressReading.score` and does not need `StressScoring`. If future detectors need to re-score, import `StressScoring`.

#### M3: No automatic insight generation on HomeView appear
- **Location**: Phase 5, Step 5.1
- **Problem**: The plan updates `onAppear` to call `insightEngine.bindContext(modelContext)` but does NOT add `Task { await insightEngine.generateInsights() }` to `onAppear`. The daily insight card will be empty until the user taps the sparkles icon or the contextual bar. The old `StressInsightService` also didn't auto-generate on appear (it only generated when `showAIInsight` was tapped), but the new `DailyInsightCard` is visible on the home screen and would show empty/nil state on every launch.
- **Impact**: User sees no daily insight card until they manually trigger generation. Defeats the purpose of the daily card.
- **Recommendation**: Add `Task { await insightEngine.generateInsights() }` to the `onAppear` block in HomeView, after `bindContext()`. The same-day cache prevents redundant regeneration.

#### M4: `InsightChartData` tuple associated values don't conform to `Sendable`
- **Location**: Phase 1, Step 1.1 — `InsightChartData` enum definition
- **Problem**: The enum uses tuple arrays like `[(date: Date, value: Double)]` as associated values. With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, these need to be `Sendable`. `Date` and `Double` are `Sendable`, and arrays of `Sendable` tuples are `Sendable`, so this should work. However, the `Color` type in `comparisonBars` is NOT `Sendable` in strict concurrency mode.
- **Impact**: Compiler warning or error with strict concurrency checking.
- **Recommendation**: Replace `Color` in `InsightChartData.comparisonBars` with a `WellnessDomain` or a string key, and resolve the colour in the view layer. Or, since the project uses approachable concurrency (not strict), this may not be an issue — but it's worth noting for future-proofing.

#### M5: Plan doesn't address `ProgressInsightsView` overlap
- **Location**: Architecture Changes table
- **Problem**: `ProgressInsightsView.swift` (found at `WellPlate/Features + UI/Progress/Views/`) is an existing view that provides nutrition-focused insights with charts (macro trends, time range selection, daily aggregates). The new `InsightsHubView` will have overlapping functionality (nutrition trend cards, macro radar). The plan doesn't mention whether `ProgressInsightsView` should be deprecated, merged, or left as-is.
- **Impact**: Two parallel insight UIs with overlapping functionality could confuse users.
- **Recommendation**: Add to Non-Goals: "ProgressInsightsView is not deprecated — it serves a different navigation path (from Food Journal). The new InsightsHubView provides cross-domain insights from the Home screen. Long-term consolidation is a future task."

#### M6: Radar chart complexity underestimated
- **Location**: Phase 3, Step 3.1 — `MacroRadarChart`
- **Problem**: The plan acknowledges radar charts are complex ("Start with a simpler grouped bar chart... Radar can be a polish iteration") in the Risks section, but the Implementation Steps include it as a primary chart type in Step 3.1. The checklist generator may treat it as required.
- **Impact**: Implementation slowdown on a non-essential chart type.
- **Recommendation**: Explicitly mark `MacroRadarChart` as optional/stretch in Step 3.1. Define `MacroGroupedBarChart` as the primary implementation for `.macroRadar` chart data, with the radar as a post-MVP enhancement.

### LOW (Consider for Future)

#### L1: No haptic feedback specification for insight card interactions
- **Location**: Phase 4
- **Problem**: The brainstorm mentioned "haptic feedback on discoveries" but the plan's view code doesn't include `HapticService` calls. The existing `HomeAIInsightView` doesn't use haptics either (only the footer regenerate button does).
- **Impact**: Minor UX polish gap.
- **Recommendation**: Add `HapticService.impact(.light)` on DailyInsightCard appear (when a new insight is surfaced for the first time today) and `HapticService.impact(.medium)` on regenerate.

#### L2: No accessibility considerations in chart components
- **Location**: Phase 3
- **Problem**: Charts are visual-only. The plan mentions "VoiceOver: Navigate InsightsHubView with VoiceOver — verify all cards are accessible" in testing but doesn't plan for `.accessibilityLabel` or `.accessibilityValue` on chart views.
- **Impact**: Charts will be invisible to VoiceOver users.
- **Recommendation**: Add `.accessibilityLabel` to each chart subview summarising the data (e.g., "Stress trend: declining from 72 to 48 over 7 days, average 58"). This can be a post-MVP task but should be tracked.

#### L3: `WellnessDaySummary` has 25+ fields — consider grouping
- **Location**: Phase 1, Step 1.1
- **Problem**: The struct has a flat list of 25+ optional fields. This makes construction verbose and error-prone.
- **Impact**: Code ergonomics, not functional.
- **Recommendation**: Consider nested structs for readability (`SleepData`, `NutritionData`, `ActivityData`, etc.) but this is a style preference, not a blocker. The flat structure matches the existing `StressInsightDaySummary` pattern.

---

## Missing Elements

- [ ] **Auto-generation on HomeView appear** — Daily card needs data without user action (see M3)
- [ ] **`InsightCard` Equatable/Hashable conformance** — Required for `.sheet(item:)` (see H1)
- [ ] **Explicit marking of MacroRadarChart as optional** — Avoid blocking implementation (see M6)
- [ ] **ProgressInsightsView relationship clarification** — Avoid confusion about overlapping UIs (see M5)

---

## Unverified Assumptions

- [ ] Foundation Models `@Generable` supports arrays of sub-schemas (e.g., `[_InsightSuggestionItem]`) — the existing `StressInsightService` uses `[_InsightSuggestion]` so this is validated by prior art. Risk: Low.
- [ ] Foundation Models can handle a batched prompt generating 5 narratives in one call — the plan has a fallback (individual calls), but batched generation hasn't been tested in this codebase. Risk: Medium.
- [ ] `async let` with 5 HealthKit fetches won't hit rate limits or permissions issues — the existing `StressInsightService` uses 4 concurrent fetches successfully. Adding 1 more (`exerciseMinutes`) should be fine. Risk: Low.
- [ ] 14-day lookback across 8 SwiftData models performs acceptably — the plan uses date-predicated `FetchDescriptor`s which should be indexed. Risk: Low.

---

## Questions for Clarification

1. Should the `DailyInsightCard` always show (even with skeleton state) or hide entirely when no insight is available? The plan implies `nil card + not generating = don't render` — is an empty state card preferable for consistent layout?
2. When the user has stress data but no food logs, should the hub show only stress/activity/sleep insights, or show "Enable food logging to unlock nutrition insights" CTAs alongside available insights?

---

## Recommendations

1. **Address H1 immediately** — Add `Equatable`/`Hashable` conformance to `InsightCard` using `id`-only comparison. This is a one-liner but critical for `.sheet(item:)`.
2. **Add auto-generation to `onAppear`** (M3) — Without this, the daily card feature is effectively invisible.
3. **Make MacroRadarChart explicitly optional** (M6) — Implement `MacroGroupedBarChart` first, radar later.
4. **Add ProgressInsightsView note to Non-Goals** (M5) — Prevents scope creep and clarifies intent.
5. **Fix font convention** (M1) — Use `.r()` extension in new view code for consistency.
