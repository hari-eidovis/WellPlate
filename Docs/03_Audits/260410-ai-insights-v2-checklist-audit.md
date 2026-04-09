# Checklist Audit Report: AI Insights V2

**Audit Date**: 2026-04-10
**Checklist**: `Docs/04_Checklist/260410-ai-insights-v2-checklist.md`
**Source Plan**: `Docs/02_Planning/Specs/260410-ai-insights-v2-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is comprehensive and well-structured, correctly phasing work in dependency order. Every major plan step has a corresponding checklist item. However, four issues require attention: two HIGH issues around an undeclared `InsightsHubHeader`/`InsightsHubFooter` subview gap and a parameter rename mismatch in the `CorrelationMath.bootstrapCI` call site that will cause a compile error, and two MEDIUM issues around a missing `DetectedChanges`/`Task.detached` threading note and the `SymptomCorrelationEngine` `@MainActor` class not being able to call a `nonisolated` static function from a `Task.detached` block the way the checklist describes.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: `bootstrapCI` parameter rename creates a silent call-site mismatch in `SymptomCorrelationEngine`
- **Location**: Checklist step 1.2 (CorrelationMath.swift creation) and step 1.3 (SymptomCorrelationEngine update)
- **Problem**: The existing `SymptomCorrelationEngine` calls `Self.bootstrapCI(symptomValues:factorValues:iterations:)` at line 113. The plan renames the parameters in `CorrelationMath` to `xValues:yValues:iterations:`. Step 1.3 of the checklist says to update line ~114 with `CorrelationMath.bootstrapCI(xValues:yValues:)`. However, the `Task.detached` closure at line 111 also calls `spearmanR(sX, sY)` internally (line 201 in the source) — the extracted `CorrelationMath.bootstrapCI` itself will internally call `CorrelationMath.spearmanR`. The checklist does not instruct the implementer to update this *internal* reference inside the extracted `bootstrapCI` body. If the implementer does a literal copy-paste of lines 187-208, the body still calls `spearmanR(sX, sY)` as a bare function, not `CorrelationMath.spearmanR(sX, sY)`. This will fail to compile inside the `enum CorrelationMath` namespace (unresolved identifier).
- **Impact**: Build failure at step 1.2 or 1.3.
- **Recommendation**: Add an explicit sub-bullet to step 1.2: "Within the copied `bootstrapCI` body, update the internal call from `spearmanR(sX, sY)` to `CorrelationMath.spearmanR(sX, sY)` (or simply `spearmanR(sX, sY)` since it is in the same enum scope — verify which the compiler accepts)." Actually within the same `enum` scope a bare `spearmanR(sX, sY)` call will resolve correctly, but only if `spearmanR` is defined before `bootstrapCI` in the file. Add a file-order note.

---

### HIGH (Should Fix Before Proceeding)

#### H1: `InsightsHubHeader` and `InsightsHubFooter` are referenced but never defined
- **Location**: Checklist step 4.3 (`InsightsHubView.swift`), verified against plan lines 788-801
- **Problem**: The plan's `InsightsHubView` code references two subviews, `InsightsHubHeader(cardCount:)` and `InsightsHubFooter(engine:)`, as if they already exist. Neither is defined anywhere in the checklist steps, nor are they called out as sub-structs to implement inside step 4.3. The checklist step 4.3 says "Hub header (subtitle: 'Last 14 days', card count)" and "Hub footer with generatedAt text and Regenerate button" as bullet points describing what to build, but does not make these separate named structs. However, the plan's code snippet uses them as distinct named view types. An implementer who follows the plan code snippet exactly will get compile errors on undefined types.
- **Impact**: Build failure after step 4.3 if the implementer copies the plan's code verbatim. If instead they inline the header/footer as anonymous `VStack` sections, the plan and checklist are inconsistent about the structure.
- **Recommendation**: Add explicit sub-bullets to step 4.3: "Define `private struct InsightsHubHeader: View` with `cardCount: Int` property" and "Define `private struct InsightsHubFooter: View` with `engine: InsightEngine` property and a Regenerate button calling `engine.clearAndRegenerate()`." Alternatively, note that these can be inlined as `VStack` sections without separate struct definitions.

#### H2: Step 1.3 line references are fragile and may be wrong after step 1.2 edits
- **Location**: Checklist step 1.3 — "Update line ~111", "Update line ~114", "Update line ~118", "Update line ~212"
- **Problem**: The SymptomCorrelationEngine source has been confirmed at exact lines (146-223 for the private funcs, 111-118 for the call sites). However, the checklist instructs the implementer to delete lines 146-223 in step 1.3 *after* already having confirmed the file is unmodified in step 1.2. The line numbers cited for the call sites (111, 114, 118) are correct against the current source. BUT `interpretationLabel` is called at line 118 in the current file, while the plan/checklist says "Update line ~212" for the `interpretationLabel` reference — line 212 is in the *private function body* that will be deleted, not the call site. Inspecting the source: the call site for `interpretationLabel` is at line 118 (`let interp = Self.interpretationLabel(...)`), not 212. Line 212 is the function declaration itself.
- **Impact**: Implementer may look for the wrong line for the `interpretationLabel` replacement, causing confusion or a missed update.
- **Recommendation**: Correct the checklist: "Update line ~118: replace `Self.interpretationLabel(...)` with `CorrelationMath.interpretationLabel(...)`." The "Update line ~212" note in step 1.3 bullet 4 should be removed or clarified — the function at line 212 is being deleted, not updated.

---

### MEDIUM (Fix During Implementation)

#### M1: Step 2.1 `buildWellnessContext` gate check uses `StressReading` but `@MainActor` fetch is not addressed
- **Location**: Checklist step 2.1 — "Gate check: fetch `StressReading` where `timestamp >= windowStart` — require >= 2 unique days"
- **Problem**: `InsightEngine` is `@MainActor`. SwiftData fetches performed directly on `@MainActor` with `try modelContext.fetch(...)` are synchronous and fine. However, the checklist also mandates 5 concurrent HealthKit fetches via `async let`. HealthKit service methods throw; the safe-fetch helpers suppress throws with `try?`. But the 5 `async let` calls are all `nonisolated` HealthKit calls — they will run off the main actor by default in `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` mode only if the called methods are themselves `nonisolated`. The existing `StressInsightService` solves this with private helper methods per CLAUDE.md's `async let` guidance. The checklist mentions copying "the pattern from `StressInsightService` lines 433-447" which is correct. However, it does not explicitly warn the implementer that the safe-fetch helpers themselves must be `nonisolated` (or at least callable in concurrent context). If the implementer marks them as regular `private func` on `@MainActor`, the compiler will complain about using `async let` to call them concurrently.
- **Impact**: Potential compiler error or unintended main-actor serialisation of HealthKit calls.
- **Recommendation**: Add a sub-bullet under step 2.1 helper definitions: "Mark each safe-fetch helper as `nonisolated` if needed, or confirm that the pattern from `StressInsightService` (which calls `healthService` methods directly) satisfies the compiler with `async let`." Reference CLAUDE.md's note: "Use `async let` with private helper methods."

#### M2: Step 6.1 cleanup grep exception claim needs verification
- **Location**: Checklist step 6.1 — "`grep -r "StressInsightService" WellPlate/` — should return 0 results (except `StressScoring.swift` comment, which is just a comment and is fine)"
- **Problem**: The audit verified that `StressScoring.swift` contains the text "StressInsightService" only in a comment (line 5: "shared by StressViewModel and StressInsightService"). However, `HomeView.swift` currently also references `StressInsightService` (confirmed at line 63: `@StateObject private var insightService = StressInsightService()`). After step 5.1 the HomeView reference will be gone, which is correct sequencing. But the grep exception note in step 6.1 only mentions `StressScoring.swift` — if the implementer runs the grep *before* completing step 5.1 (e.g., checking intermediate state), they will see a HomeView result and be confused. This is a sequencing documentation issue.
- **Impact**: Implementer confusion; not a build failure.
- **Recommendation**: Add a note: "This grep is run after Phase 5 is complete. The only expected remaining match is the comment in `StressScoring.swift`."

#### M3: `DailyInsightCard` placement in LazyVStack is ambiguous after layout change
- **Location**: Checklist step 5.1 — "Add `DailyInsightCard` to `LazyVStack` after `QuickStatsRow` (around line ~149)"
- **Problem**: Inspecting `HomeView.swift`, the `LazyVStack` ends at line 163 with `.padding(.bottom, 32)` immediately after `QuickStatsRow` (lines 138-150). There is no content after `QuickStatsRow` in the stack other than the bottom padding. Line 149 is inside the `QuickStatsRow` initialiser, not after it. The actual insertion point is after line 150 (closing parenthesis of `QuickStatsRow`) and before line 163 (`.padding(.bottom, 32)`). The line number hint `~149` will direct the implementer to insert inside the `QuickStatsRow` call, causing a compile error.
- **Impact**: Implementer inserts the `DailyInsightCard` in the wrong location on first attempt, causing a parse error.
- **Recommendation**: Update the line hint: "Add after the closing `)` of `QuickStatsRow` (currently line ~150), before the `.padding(.bottom, 32)` closure of `LazyVStack`."

#### M4: Step 4.1 `InsightEntrance` access level change is incomplete
- **Location**: Checklist step 4.1 — "Change access from `private` to `internal` so `InsightsHubView` and `InsightDetailSheet` can use it"
- **Problem**: The `InsightEntrance` modifier and its `View` extension are both `private` in `HomeAIInsightView.swift`. The plan and checklist say to move them to the bottom of `InsightCardView.swift` with `internal` access. However, `InsightDetailSheet` will call `.insightEntrance(index:)` — but inspecting the plan's `InsightDetailSheet` code (step 4.4), there is no use of `.insightEntrance` within it. Only `InsightsHubView` uses `.insightEntrance`. The checklist step 4.4 does not add `.insightEntrance` to any element in the detail sheet. This is fine, but the access level justification ("so InsightDetailSheet can use it") is misleading and may cause an implementer to wonder if they forgot something in step 4.4.
- **Impact**: Minor confusion, no build failure.
- **Recommendation**: Simplify the note: "Change access from `private` to `internal` (or `fileprivate`) so `InsightsHubView` can use it from a different file."

---

### LOW (Consider for Future)

#### L1: No Previews specified for new views
- **Location**: Steps 3.1, 4.1, 4.2, 4.3, 4.4
- **Problem**: The checklist includes "Verify: Preview compiles with sample data" for chart components but does not include explicit steps to write `#Preview` blocks for `InsightCardView`, `DailyInsightCard`, `InsightsHubView`, or `InsightDetailSheet`. Without previews, the implementer must launch the simulator for every UI change, slowing iteration.
- **Recommendation**: Add a sub-bullet to each view creation step: "Add `#Preview` block using mock `InsightCard` data."

#### L2: Mock mode `mockInsights()` does not specify how sparkline data is surfaced in `DailyInsightCard`
- **Location**: Checklist step 2.6
- **Problem**: `DailyInsightCard` uses `card.chartData` and checks `if case .sparkline(let points) = card.chartData` to show the sparkline on the right side. However, if `dailyInsight` is set to the first `InsightCard` from mock data and that card has `.trendLine` chart data (not `.sparkline`), the sparkline will not appear in the daily card. The checklist says "generate 6-8 mock cards covering each InsightType at least once" but does not require the `dailyInsight` (first card) to specifically use `.sparkline` chart data. The daily card will still render but without the right-side sparkline, which is the most visually distinctive feature.
- **Recommendation**: Add a sub-bullet: "Ensure at least one mock card (ideally the first, to be set as `dailyInsight`) uses `.sparkline` chart data so `DailyInsightCard`'s sparkline slot renders during testing."

#### L3: `scenePhase` re-generation not addressed
- **Location**: Post-implementation verification section
- **Problem**: The checklist tests same-day cache when navigating away and back within the app. But `HomeView` already listens to `scenePhase` changes (confirmed in source). There is no post-implementation check that `generateInsights()` does not re-fire when the app is foregrounded on the same day (e.g., via `onChange(of: scenePhase)`). If a future developer adds scene phase triggering, the same-day cache will handle it — but this is worth a test case.
- **Recommendation**: Add a post-implementation test: "Scene phase test: Background and re-foreground the app on the same day — insights should not regenerate (same-day cache prevents it)."

---

## Missing Elements

- [ ] `InsightsHubHeader` and `InsightsHubFooter` view definitions are not called out as discrete implementation tasks (see H1)
- [ ] No instruction to update the internal `spearmanR` call inside the extracted `bootstrapCI` body (see C1)
- [ ] No `#Preview` blocks specified for any of the 4 new view files
- [ ] No mention of `MoodCheckInCard` (referenced in `HomeView.swift`) potentially needing scroll position management now that `DailyInsightCard` adds height below `QuickStatsRow`

## Unverified Assumptions

- [ ] `UserGoals.current(in:)` static method exists and returns a non-nil value — Risk: Low (confirmed used in `GoalsViewModel` at line 14)
- [ ] All 6 SwiftData model types (`WellnessDayLog`, `FoodLogEntry`, `SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry`) exist in the Models directory — Risk: Low (confirmed all 4 checked exist; `WellnessDayLog` and `FoodLogEntry` confirmed from HomeView @Query)
- [ ] `FoundationModels` framework with `@Generable` and `@Guide` attributes is available in the Xcode 26 SDK used — Risk: Low (project targets iOS 26.1 per memory)
- [ ] `StressInsightCard.swift` component (confirmed to exist at `WellPlate/Features + UI/Home/Components/StressInsightCard.swift`) does not reference `StressInsightService` directly and does not need to be deleted — Risk: Low (not mentioned in cleanup; likely safe)

## Questions for Clarification

1. Should `InsightsHubHeader` and `InsightsHubFooter` be private sub-structs inside `InsightsHubView.swift`, or standalone files? The plan code uses them as if they exist, but never defines them.
2. Step 2.1 specifies the gate check requires ">=2 unique days" of `StressReading`. Should `insufficientData` also be set to `true` when a domain like nutrition has zero data, or only when the stress baseline is missing? The plan says the gate is specifically stress-based, but this seems overly restrictive for a multi-domain insights engine — a user could have rich sleep/activity data but no stress readings.
3. The `DailyInsightCard` renders `EmptyView()` when `card == nil && !isGenerating`. Is the intent for the card slot to collapse completely (no height) in this state, or show a static placeholder? Confirming this will determine whether `LazyVStack` spacing needs adjustment for the nil case.

## Recommendations

1. Fix C1 (internal `spearmanR` call in copied `bootstrapCI`) before handing checklist to implementer — this is a guaranteed build failure.
2. Fix H1 (add `InsightsHubHeader`/`InsightsHubFooter` sub-steps) — otherwise the implementer will be left guessing at the structure of two undeclared types while already deep in Phase 4.
3. Fix H2 (correct the `interpretationLabel` line reference from 212 to 118) — the wrong line number points directly at the function being deleted, not the call site.
4. Clarify the `DailyInsightCard` insertion line number in step 5.1 to avoid a first-attempt parse error.
5. Consider whether the stress-only gate check in `buildWellnessContext` is the right design for a multi-domain engine — if the user has no stress data but does have food/sleep/activity data, `insufficientData` will be `true` and the hub will show an empty state, defeating the purpose of multi-domain insights.
