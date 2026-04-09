# Implementation Checklist: AI Insights V2 (RESOLVED)

**Source Plan**: `Docs/02_Planning/Specs/260410-ai-insights-v2-plan-RESOLVED.md`
**Date**: 2026-04-10

## Checklist Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|---|---|---|---|
| C1 | CRITICAL | `bootstrapCI` internal `spearmanR` call won't compile in enum namespace | Added explicit sub-bullet in Step 1.2: verify internal `spearmanR` call resolves within enum scope, declare `spearmanR` before `bootstrapCI` in file |
| H1 | HIGH | `InsightsHubHeader` and `InsightsHubFooter` never defined in checklist | Added explicit sub-bullets in Step 4.3 to define both as private structs inside `InsightsHubView.swift` |
| H2 | HIGH | `interpretationLabel` line reference (212) points to deleted declaration, not call site (118) | Corrected Step 1.3: call site is line ~118, removed misleading 212 reference |
| M1 | MEDIUM | `@MainActor` safe-fetch helpers + `async let` concurrency threading concern | Added note in Step 2.1: safe-fetch helpers must follow existing `StressInsightService` pattern (private helper methods) |
| M2 | MEDIUM | Step 6.1 grep exception note timing confusion | Added note: "Run this grep after Phase 5 is complete" |
| M3 | MEDIUM | `DailyInsightCard` insertion line ~149 is inside QuickStatsRow args | Corrected to: "after closing `)` of `QuickStatsRow` around line ~150, before `.padding(.bottom, 32)`" |
| M4 | MEDIUM | `InsightEntrance` access level justification misleading (mentions InsightDetailSheet) | Simplified to: "so `InsightsHubView` can use it from a different file" |
| L1 | LOW | No `#Preview` blocks for new views | Added `#Preview` sub-bullets to Steps 4.1, 4.2, 4.3, 4.4 |
| L2 | LOW | `dailyInsight` mock card may not have `.sparkline` chartData | Added sub-bullet in Step 2.6: ensure first mock card uses `.sparkline` |
| L3 | LOW | No `scenePhase` re-generation test | Added scene phase test to post-implementation verification |
| Design | N/A | Stress-only gate blocks users with only nutrition/sleep/activity data | Relaxed gate: require data from any 2+ domains, not stress specifically |

---

## Pre-Implementation

- [ ] Read the resolved plan in full
- [ ] Verify affected files exist:
  - [ ] `WellPlate/Core/Services/StressInsightService.swift` (to be replaced)
  - [ ] `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift` (to be replaced)
  - [ ] `WellPlate/Features + UI/Home/StressInsightReport.swift` (to be replaced)
  - [ ] `WellPlate/Core/Services/SymptomCorrelationEngine.swift` (to be modified)
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift` (to be modified)
  - [ ] `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift` (verify — no changes needed)
- [ ] Note: `WellPlate/Features + UI/Home/Models/` directory does not exist — will be created with first file. `PBXFileSystemSynchronizedRootGroup` auto-includes new files; no pbxproj edits needed.

---

## Phase 1: Data Models & Correlation Utility

### 1.1 — Create InsightModels.swift

- [ ] Create file `WellPlate/Features + UI/Home/Models/InsightModels.swift`
- [ ] Define `WellnessDomain` enum with cases: `stress`, `nutrition`, `sleep`, `activity`, `hydration`, `caffeine`, `mood`, `fasting`, `symptoms`, `cross`
  - [ ] Add computed properties: `label` (display name), `icon` (SF Symbol), `accentColor` (from `AppColors` tokens)
  - Verify: each case returns a non-empty label, valid SF Symbol, and non-nil Color
- [ ] Define `InsightType` enum with cases: `trend`, `correlation`, `milestone`, `imbalance`, `sleepQuality`, `reinforcement`
  - [ ] Add computed properties: `label`, `icon`
  - Verify: each case returns a non-empty label and valid SF Symbol
- [ ] Define `InsightChartData` enum with cases:
  - [ ] `.trendLine(points: [(date: Date, value: Double)], goalLine: Double?, metricLabel: String, unit: String)`
  - [ ] `.correlationScatter(points: [(x: Double, y: Double)], r: Double, xLabel: String, yLabel: String)`
  - [ ] `.comparisonBars(bars: [(label: String, value: Double, domain: WellnessDomain)], highlight: Int?)` — uses `WellnessDomain` not `Color`
  - [ ] `.macroRadar(actual: [String: Double], goals: [String: Double])`
  - [ ] `.milestoneRing(current: Int, target: Int, streakLabel: String)`
  - [ ] `.sparkline(points: [Double])`
  - Verify: all associated values use `Sendable` types (no `Color`)
- [ ] Define `InsightCard` struct conforming to `Identifiable`, `Equatable`, `Hashable`:
  - [ ] Properties: `id: UUID`, `type: InsightType`, `domain: WellnessDomain`, `headline: String`, `narrative: String`, `chartData: InsightChartData`, `priority: Double`, `isLLMGenerated: Bool`, `generatedAt: Date`, `detailSuggestions: [String]`
  - [ ] Manual `Equatable`: `static func == (lhs:rhs:) -> Bool { lhs.id == rhs.id }`
  - [ ] Manual `Hashable`: `func hash(into:) { hasher.combine(id) }`
  - Verify: `InsightCard` can be used in `@State var selectedCard: InsightCard?` and `.sheet(item:)`
- [ ] Define `WellnessDaySummary` struct with all 25+ fields as specified in plan (stress, sleep, activity, nutrition, hydration, caffeine, mood, symptoms, fasting, supplements, journal)
  - Verify: all fields are optional where data may be missing (except `date`, `mealCount`, `symptomNames`, `journalLogged`)
- [ ] Define `WellnessContext` struct with: `days: [WellnessDaySummary]`, `goals: UserGoalsSnapshot`, `dataQualityNote: String`
- [ ] Define `UserGoalsSnapshot` struct with `init(from goals: UserGoals)` that copies all relevant goal values
  - Verify: `UserGoalsSnapshot` copies: `calorieGoal`, `proteinGoalGrams`, `carbsGoalGrams`, `fatGoalGrams`, `fiberGoalGrams`, `waterDailyCups`, `coffeeDailyCups`, `dailyStepsGoal`, `activeEnergyGoalKcal`, `sleepGoalHours`
- [ ] Build main target to verify no compile errors
  - Verify: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build` succeeds

### 1.2 — Create CorrelationMath.swift

- [ ] Create file `WellPlate/Core/Services/CorrelationMath.swift`
- [ ] Define `enum CorrelationMath` (caseless, utility namespace)
<!-- RESOLVED: C1 — File ordering matters. Declare functions in this order so internal calls resolve: ranks → pearsonR → spearmanR → bootstrapCI → interpretationLabel. The bootstrapCI body calls spearmanR() as a bare name — within the same enum scope this resolves correctly as long as spearmanR is declared above bootstrapCI. -->
- [ ] Copy `ranks(of:)` from `SymptomCorrelationEngine.swift` lines 153-171 → make `nonisolated private static`
- [ ] Copy `pearsonR(_:_:)` from lines 173-183 → make `nonisolated private static`
- [ ] Copy `spearmanR(_:_:)` from lines 146-151 → make `nonisolated static`
- [ ] Copy `bootstrapCI(symptomValues:factorValues:iterations:)` from lines 187-208 → rename params to `xValues:yValues:iterations:` → make `nonisolated static`
  - [ ] Verify the internal call `spearmanR(sX, sY)` on line ~201 of the copied body resolves correctly within `CorrelationMath` enum scope (no `Self.` prefix needed since `spearmanR` is declared above)
- [ ] Copy `interpretationLabel(r:ciSpansZero:)` from lines 212-222 → make `nonisolated static`
  - Verify: all 5 functions compile; no `SymptomCorrelationEngine` references remain in the new file
- [ ] Build main target
  - Verify: build succeeds

### 1.3 — Update SymptomCorrelationEngine to use shared CorrelationMath

- [ ] Open `WellPlate/Core/Services/SymptomCorrelationEngine.swift`
- [ ] Delete the private static functions (lines 146-223): `spearmanR`, `ranks`, `pearsonR`, `bootstrapCI`, `interpretationLabel`
<!-- RESOLVED: H2 — Corrected line references. Call sites are at lines ~111, ~113, ~118 (before deletion). Line 212 was the function declaration, not a call site. -->
- [ ] Update line ~111: replace `Self.spearmanR(...)` with `CorrelationMath.spearmanR(...)`
- [ ] Update line ~113: replace `Self.bootstrapCI(symptomValues: symptomValues, factorValues: factorValues)` with `CorrelationMath.bootstrapCI(xValues: symptomValues, yValues: factorValues)`
- [ ] Update line ~118: replace `Self.interpretationLabel(...)` with `CorrelationMath.interpretationLabel(...)`
  - Verify: no remaining `Self.spearman`, `Self.ranks`, `Self.pearson`, `Self.bootstrap`, `Self.interpretation` references in the file
- [ ] Build main target
  - Verify: build succeeds — `SymptomCorrelationEngine` compiles with delegated calls

---

## Phase 2: InsightEngine Service

### 2.1 — Create InsightEngine scaffold and data aggregation

- [ ] Create file `WellPlate/Core/Services/InsightEngine.swift`
- [ ] Add imports: `Foundation`, `SwiftData`, `Combine`, conditional `FoundationModels`
- [ ] Define `@MainActor final class InsightEngine: ObservableObject`
- [ ] Add `@Published` properties: `insightCards: [InsightCard]`, `dailyInsight: InsightCard?`, `isGenerating: Bool`, `insufficientData: Bool`
- [ ] Add private properties: `modelContext: ModelContext?`, `healthService: HealthKitServiceProtocol`, `lookbackDays: Int = 14`
- [ ] Add `init(healthService:)` with default `HealthKitService()`
- [ ] Add `func bindContext(_ context: ModelContext)` — assigns `modelContext`
- [ ] Add stub `func generateInsights() async` and `func clearAndRegenerate() async`
- [ ] Implement `private func buildWellnessContext() async -> WellnessContext?`:
  - [ ] Fetch `UserGoals.current(in:)` → create `UserGoalsSnapshot`
  - [ ] Calculate `windowStart` = 14 days before `startOfToday`
  <!-- RESOLVED: Design concern — Relaxed gate check from stress-only to multi-domain. -->
  - [ ] Multi-domain gate check: count how many domains have data in the window (stress readings, food logs, sleep summaries, wellness day logs with steps > 0). Require >= 2 domains with >= 2 days of data each. This replaces the old stress-only gate so users with nutrition + sleep data (but no stress readings) still get insights.
  - [ ] Concurrent HealthKit fetches via `async let` (5 fetches):
    - [ ] `fetchSleepSafely` → `[DailySleepSummary]`
    - [ ] `fetchDailyStepsSafely` → `[DailyMetricSample]`
    - [ ] `fetchDailyEnergySafely` → `[DailyMetricSample]`
    - [ ] `fetchHeartRateSafely` → `[DailyMetricSample]`
    - [ ] `fetchExerciseMinutesSafely` → `[DailyMetricSample]`
  - [ ] SwiftData fetches with `>= windowStart` predicates (6 fetches):
    - [ ] `WellnessDayLog`
    - [ ] `FoodLogEntry`
    - [ ] `SymptomEntry`
    - [ ] `FastingSession`
    - [ ] `AdherenceLog`
    - [ ] `JournalEntry`
  - [ ] Build per-day `WellnessDaySummary` array in a loop from `-(lookbackDays-1)` to `0`
  - [ ] Build `dataQualityNote` for missing categories
  - [ ] Return `WellnessContext(days:goals:dataQualityNote:)`
<!-- RESOLVED: M1 — Safe-fetch helpers must follow the existing StressInsightService pattern: private helper methods that call healthService directly. This satisfies the compiler for async let concurrent usage per CLAUDE.md's "Use async let with private helper methods" guidance. -->
- [ ] Add 5 private safe-fetch helpers (copy pattern from `StressInsightService` lines 433-447):
  - [ ] `fetchSleepSafely(range:) async -> [DailySleepSummary]`
  - [ ] `fetchDailyStepsSafely(range:) async -> [DailyMetricSample]`
  - [ ] `fetchDailyEnergySafely(range:) async -> [DailyMetricSample]`
  - [ ] `fetchHeartRateSafely(range:) async -> [DailyMetricSample]`
  - [ ] `fetchExerciseMinutesSafely(range:) async -> [DailyMetricSample]`
  - Verify: each helper uses `(try? await healthService.fetchX(for: range)) ?? []` — same private helper method pattern as `StressInsightService`
- [ ] Build main target
  - Verify: build succeeds

### 2.2 — Implement insight detectors

- [ ] Add `private func detectTrends(context: WellnessContext) -> [InsightCard]`
  - [ ] Check metrics: stressScore, sleepHours, steps, totalCalories, waterGlasses, coffeeCups
  - [ ] For each: extract non-nil values, check 3+ day monotonic trend, calculate % change
  - [ ] Create `InsightCard` with `.trend` type, `.trendLine` chartData
  - Verify: with mock context of 5 days decreasing sleep, produces at least 1 trend card
- [ ] Add `private func detectCorrelations(context: WellnessContext) -> [InsightCard]`
  - [ ] Define pairs: (sleep, stress), (steps, stress), (coffee, stress), (protein, stress), (fiber, stress), (water, stress), (sleep, steps)
  - [ ] For each pair: build paired arrays, require N >= 7, compute via `CorrelationMath.spearmanR` + `bootstrapCI`
  - [ ] Create card if |r| >= 0.3 AND CI doesn't span zero
  - [ ] Use `.correlationScatter` chartData
  - Verify: with mock data where sleep and stress are inversely correlated, produces a correlation card
- [ ] Add `private func detectMilestones(context: WellnessContext) -> [InsightCard]`
  - [ ] Check streaks for: water >= goal, steps >= goal, calories within +/-10%, sleep >= goal
  - [ ] Count consecutive days from most recent meeting threshold
  - [ ] Create card if streak >= 3 with `.milestoneRing` chartData
  - Verify: with mock data of 5 consecutive days hitting water goal, produces a milestone card
- [ ] Add `private func detectImbalances(context: WellnessContext) -> [InsightCard]`
  - [ ] For each macro: compute 7-day avg, compare to `UserGoalsSnapshot`
  - [ ] Create card if avg < 70% of goal for 3+ days with `.macroRadar` chartData
  - Verify: with mock protein at 50% of goal, produces an imbalance card
- [ ] Add `private func detectSleepQuality(context: WellnessContext) -> [InsightCard]`
  - [ ] Split lookback into halves, compare deep sleep ratio
  - [ ] Create card if change > 15% with `.comparisonBars` chartData
  - Verify: with mock data showing improved deep sleep in second half, produces a sleep quality card
- [ ] Add `private func detectReinforcements(context: WellnessContext) -> [InsightCard]`
  - [ ] Check if any metric is at/above goal for 5+ of last 7 days
  - [ ] Create card with `.sparkline` chartData
  - Verify: with mock data of consistent water logging, produces a reinforcement card
- [ ] Build main target
  - Verify: build succeeds

### 2.3 — Implement insight prioritisation

- [ ] Add `private func prioritise(_ cards: [InsightCard]) -> [InsightCard]`
  - [ ] Sort by `priority` descending
  - [ ] Tiebreak by type order: correlation > trend > imbalance > sleepQuality > milestone > reinforcement
  - [ ] Deduplicate: if two cards cover the same domain+metric, keep higher priority
  - [ ] Cap at 12 cards maximum
  - Verify: given 15 mock cards of mixed types, returns 12 sorted by priority

### 2.4 — Implement Foundation Models narrative generation

- [ ] Add `#if canImport(FoundationModels)` block at file bottom
- [ ] Define `@available(iOS 26, *) @Generable private struct _InsightNarrativeSchema` with:
  - [ ] `headline: String` with `@Guide`
  - [ ] `narrative: String` with `@Guide`
  - [ ] `suggestions: [_InsightSuggestionItem]` with `@Guide`
- [ ] Define `@available(iOS 26, *) @Generable private struct _InsightSuggestionItem` with `text: String`
- [ ] Add `private func generateNarratives(_ cards: [InsightCard], context: WellnessContext) async -> [InsightCard]`
  - [ ] Check iOS 26 availability + `SystemLanguageModel.default.availability == .available`
  - [ ] Build prompt describing top 5 cards' data + type
  - [ ] Try batched FM call; on failure try individual calls; on failure use templates
  - [ ] Update each card's headline, narrative, and detailSuggestions from FM response
  - [ ] Mark `isLLMGenerated = true` for FM-generated cards
  - Verify: compiles with `#if canImport(FoundationModels)` guard

### 2.5 — Implement template fallback narratives

- [ ] Add `private func templateNarrative(for card: InsightCard, context: WellnessContext) -> (headline: String, narrative: String, suggestions: [String])`
- [ ] Implement templates for each `InsightType`:
  - [ ] `.trend` — "Sleep has dropped 3 days in a row" / "Steps trending up this week"
  - [ ] `.correlation` — "On days you slept 7h+, stress was X% lower"
  - [ ] `.milestone` — "5-day water goal streak!"
  - [ ] `.imbalance` — "Protein has averaged Xg/day — Y% below your Zg goal"
  - [ ] `.sleepQuality` — "Deep sleep improved X% compared to last week"
  - [ ] `.reinforcement` — "Great consistency on [metric] this week"
  - Verify: each switch case returns non-empty headline, narrative, and 2 suggestions

### 2.6 — Implement mock mode and caching

- [ ] Add same-day cache check at top of `generateInsights()`:
  ```swift
  if let first = insightCards.first, Calendar.current.isDateInToday(first.generatedAt) { return }
  ```
- [ ] Add mock mode check:
  ```swift
  if AppConfig.shared.mockMode { let mocks = mockInsights(); insightCards = mocks; dailyInsight = mocks.first; return }
  ```
- [ ] Implement `private func mockInsights() -> [InsightCard]`
  - [ ] Generate 6-8 mock cards covering each InsightType at least once
  - [ ] Use realistic data (reference `StressInsightService.mockReport()` for patterns)
  - [ ] Include varied `WellnessDomain` values
  <!-- RESOLVED: L2 — Ensure first mock card (set as dailyInsight) uses .sparkline chartData so DailyInsightCard's sparkline slot renders during testing. -->
  - [ ] Ensure the first mock card uses `.sparkline` chartData so `DailyInsightCard` renders the sparkline on the home screen
  - Verify: `mockInsights()` returns 6+ cards, each with valid chartData and non-empty narratives

### 2.7 — Wire up generateInsights() orchestration

- [ ] Implement full `generateInsights()` body:
  - [ ] Guard `modelContext != nil`
  - [ ] Same-day cache check
  - [ ] Set `isGenerating = true`, defer `isGenerating = false`
  - [ ] Mock mode branch
  - [ ] Call `buildWellnessContext()` — if nil, set `insufficientData = true` and return
  - [ ] Call all 6 detectors, collect cards
  - [ ] Call `prioritise()`
  - [ ] Call `generateNarratives()` (FM or template)
  - [ ] Assign `insightCards` and `dailyInsight`
- [ ] Implement `clearAndRegenerate()`: clear state, call `generateInsights()`
  - Verify: with mock mode on, `generateInsights()` populates `insightCards` and `dailyInsight`
- [ ] Build main target
  - Verify: build succeeds

---

## Phase 3: Chart Components

### 3.1 — Create InsightCharts.swift

- [ ] Create file `WellPlate/Features + UI/Home/Components/InsightCharts.swift`
- [ ] Add `import SwiftUI` and `import Charts`
- [ ] Implement `TrendAreaChart`:
  - [ ] Input: `points`, `goalLine`, `metricLabel`, `unit`, `accentColor`
  - [ ] Body: `AreaMark` + `LineMark` + `PointMark` + optional `RuleMark` for goal
  - [ ] Axis labels use `.r(.caption2, .medium)` or `.system(size: 9, design: .rounded)`
  - [ ] Interpolation: `.catmullRom`
  - [ ] Frame height: 130
  - [ ] Add `#Preview` with sample 7-day trend data
  - Verify: Preview compiles and renders chart with sample data
- [ ] Implement `CorrelationScatterChart`:
  - [ ] Input: `points`, `r`, `xLabel`, `yLabel`
  - [ ] Body: `PointMark` for each point + `LineMark` for linear regression line
  - [ ] r-value badge overlay: `Text(String(format: "r = %.2f", r))`
  - [ ] Frame height: 150
  - [ ] Add `#Preview` with sample scatter data
  - Verify: Preview compiles and renders scatter with trend line
- [ ] Implement `ComparisonBarChart`:
  - [ ] Input: `bars: [(label: String, value: Double, domain: WellnessDomain)]`, `highlight: Int?`
  - [ ] Body: horizontal `BarMark` per bar, colour resolved via `bar.domain.accentColor`
  - [ ] Frame height: 80
  - [ ] Add `#Preview`
  - Verify: Preview compiles
- [ ] Implement `MacroGroupedBarChart` (primary for `.macroRadar` data):
  - [ ] Input: `actual: [String: Double]`, `goals: [String: Double]`
  - [ ] Body: grouped vertical `BarMark` — actual (brand colour) + goal (secondary.opacity(0.3)) per macro
  - [ ] Frame height: 130
  - [ ] Add `#Preview` with protein/carbs/fat/fiber sample data
  - Verify: Preview compiles with grouped bars
- [ ] Implement `MilestoneRingView`:
  - [ ] Input: `current`, `target`, `streakLabel`
  - [ ] Body: circular arc (`Circle().trim(from:to:)`) with text centre showing streak count
  - [ ] Animate arc on appear via `@State appeared` + `.animation`
  - [ ] Frame: 80x80
  - [ ] Add `#Preview`
  - Verify: Preview compiles and ring animates
- [ ] Implement `SparklineView`:
  - [ ] Input: `points: [Double]`, `accentColor`
  - [ ] Body: tiny `LineMark`, no axes, no labels, `.catmullRom` interpolation
  - [ ] Frame: 60x24
  - [ ] Add `#Preview`
  - Verify: Preview compiles
- [ ] Build main target
  - Verify: build succeeds

---

## Phase 4: View Layer

### 4.1 — Create InsightCardView.swift

- [ ] Create file `WellPlate/Features + UI/Home/Components/InsightCardView.swift`
- [ ] Define `struct InsightCardView: View` with `card: InsightCard`, `onDetailsTap: (() -> Void)?`
- [ ] Implement body:
  - [ ] Header: domain icon + domain label (uppercased, tracking 1.0) + type badge capsule
  - [ ] Headline: `.r(.headline, .bold)`
  - [ ] Chart: `@ViewBuilder func chartView(for:)` switching on all `InsightChartData` cases
    - [ ] `.macroRadar` maps to `MacroGroupedBarChart`
  - [ ] Narrative: `.r(.subheadline, .regular)`, `.secondary`
  - [ ] Optional "See Details" button with domain accent colour
- [ ] Card background: `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 12, y: 4)`
<!-- RESOLVED: M4 — Simplified access level justification. -->
- [ ] Move `InsightEntrance` modifier from `HomeAIInsightView.swift` lines 602-623 to bottom of this file
  - [ ] Copy `private struct InsightEntrance: ViewModifier` and `extension View { func insightEntrance(index:) }`
  - [ ] Change access from `private` to `internal` so `InsightsHubView` can use it from a different file
  - Verify: modifier compiles as `internal`
<!-- RESOLVED: L1 — Added #Preview block. -->
- [ ] Add `#Preview` block using a mock `InsightCard` with `.trendLine` chartData
- [ ] Build main target
  - Verify: build succeeds

### 4.2 — Create DailyInsightCard.swift

- [ ] Create file `WellPlate/Features + UI/Home/Components/DailyInsightCard.swift`
- [ ] Define `struct DailyInsightCard: View` with `card: InsightCard?`, `isGenerating: Bool`, `onTap: () -> Void`
- [ ] Implement body:
  - [ ] `isGenerating` state: skeleton shimmer placeholder (ProgressView or redacted modifier)
  - [ ] `card != nil` state: `Button(action: onTap)` with `HStack` — icon circle, headline + narrative VStack, optional sparkline, chevron
  - [ ] `nil card + not generating` state: don't render (empty `EmptyView()`)
- [ ] Fonts: `.r(.subheadline, .bold)` for headline, `.r(.caption, .regular)` for narrative
- [ ] Card background: `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 12, y: 4)`
<!-- RESOLVED: L1 — Added #Preview block. -->
- [ ] Add `#Preview` with a mock `InsightCard` using `.sparkline` chartData
- [ ] Build main target
  - Verify: build succeeds

### 4.3 — Create InsightsHubView.swift

- [ ] Create file `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`
- [ ] Define `struct InsightsHubView: View` with `@ObservedObject var engine: InsightEngine`
- [ ] Add `@State private var selectedCard: InsightCard?`
<!-- RESOLVED: H1 — Explicitly define InsightsHubHeader and InsightsHubFooter as private structs. -->
- [ ] Define `private struct InsightsHubHeader: View` inside this file:
  - [ ] Input: `cardCount: Int`
  - [ ] Body: VStack with "Your Insights" (or header text), "Last 14 days" subtitle, and card count badge
- [ ] Define `private struct InsightsHubFooter: View` inside this file:
  - [ ] Input: `@ObservedObject var engine: InsightEngine`
  - [ ] Body: VStack with `generatedAt` timestamp text and Regenerate button calling `Task { await engine.clearAndRegenerate() }`
  - [ ] Regenerate button: `HapticService.impact(.light)` on tap, disabled while `engine.isGenerating`
- [ ] Implement main body with 3 states:
  - [ ] Loading: `ProgressView` + "Analyzing your wellness data..." label
  - [ ] Insufficient data: sparkles icon + "Not Enough Data" + guidance text
  - [ ] Loaded: `ScrollView` → `LazyVStack(spacing: 14)` containing:
    - [ ] `InsightsHubHeader(cardCount: engine.insightCards.count)` with `.insightEntrance(index: 0)`
    - [ ] `ForEach` over `engine.insightCards` rendering `InsightCardView` with `.insightEntrance(index:)`
    - [ ] `InsightsHubFooter(engine: engine)` with `.insightEntrance(index:)`
- [ ] Add `.navigationTitle("Your Insights")` + `.navigationBarTitleDisplayMode(.inline)`
- [ ] Add `.sheet(item: $selectedCard) { card in InsightDetailSheet(card: card, engine: engine) }`
<!-- RESOLVED: L1 — Added #Preview block. -->
- [ ] Add `#Preview` with a mock `InsightEngine` populated via mock mode
- [ ] Build main target
  - Verify: build succeeds

### 4.4 — Create InsightDetailSheet.swift

- [ ] Create file `WellPlate/Features + UI/Home/Views/InsightDetailSheet.swift`
- [ ] Define `struct InsightDetailSheet: View` with `card: InsightCard`, `@ObservedObject var engine: InsightEngine`
- [ ] Add `@Environment(\.dismiss) private var dismiss`
- [ ] Implement body:
  - [ ] `NavigationStack` wrapping `ScrollView` → `VStack(alignment: .leading, spacing: 20)`
  - [ ] Domain header with icon + label
  - [ ] Full headline: `.r(.title3, .bold)`
  - [ ] Full-size chart (same type as card, larger frame — multiply height by ~1.5)
  - [ ] Extended narrative text
  - [ ] Suggestions list: `ForEach(card.detailSuggestions)` with checkmark icons
  - [ ] Caution note: "Correlation does not imply causation." (for `.correlation` type cards)
  - [ ] `.navigationTitle(card.domain.label)` + `.navigationBarTitleDisplayMode(.inline)`
  - [ ] Toolbar "Done" button calling `dismiss()`
<!-- RESOLVED: L1 — Added #Preview block. -->
- [ ] Add `#Preview` with a mock correlation-type `InsightCard`
- [ ] Build main target
  - Verify: build succeeds

---

## Phase 5: HomeView Integration

### 5.1 — Update HomeView.swift

- [ ] Open `WellPlate/Features + UI/Home/Views/HomeView.swift`
- [ ] Replace `@StateObject private var insightService = StressInsightService()` (line ~61) with:
  ```swift
  @StateObject private var insightEngine = InsightEngine()
  ```
- [ ] Replace `@State private var showAIInsight = false` (line ~54) with:
  ```swift
  @State private var showInsightsHub = false
  ```
<!-- RESOLVED: M3 — Corrected insertion point. Insert after closing ) of QuickStatsRow (line ~150), before .padding(.bottom, 32). -->
- [ ] Add `DailyInsightCard` to `LazyVStack` after the closing `)` of `QuickStatsRow` (around line ~150), before `.padding(.bottom, 32)`:
  ```swift
  // 5. Daily AI Insight
  DailyInsightCard(
      card: insightEngine.dailyInsight,
      isGenerating: insightEngine.isGenerating
  ) {
      showInsightsHub = true
  }
  .padding(.horizontal, 16)
  ```
  - Verify: card appears between QuickStatsRow and the bottom padding
- [ ] Update header sparkles icon action (lines ~364-368):
  ```swift
  Button {
      HapticService.impact(.light)
      showInsightsHub = true
      Task { await insightEngine.generateInsights() }
  } label: {
      headerIcon("sparkles")
  }
  ```
- [ ] Update contextual bar `onSeeInsight` closure (lines ~193-195):
  ```swift
  onSeeInsight: {
      showInsightsHub = true
      Task { await insightEngine.generateInsights() }
  }
  ```
  - Note: "See Insight" from `.stressActionable` bar state now opens multi-domain hub. This is intentional. `onStressTab` still navigates to the dedicated Stress tab.
- [ ] Update `navigationDestination` (lines ~228-229):
  ```swift
  .navigationDestination(isPresented: $showInsightsHub) {
      InsightsHubView(engine: insightEngine)
  }
  ```
  - [ ] Remove old: `.navigationDestination(isPresented: $showAIInsight) { HomeAIInsightView(insightService: insightService) }`
- [ ] Update `onAppear` (line ~239):
  ```swift
  insightEngine.bindContext(modelContext)
  Task { await insightEngine.generateInsights() }
  ```
  - Note: auto-generation ensures DailyInsightCard has content on launch. Same-day cache prevents redundant work.
  - [ ] Remove old: `insightService.bindContext(modelContext)`
- [ ] Search and remove ALL remaining references to `insightService` and `showAIInsight` in the file
  - Verify: `grep -n "insightService\|showAIInsight\|StressInsightService\|HomeAIInsightView" HomeView.swift` returns no matches
- [ ] Build main target
  - Verify: build succeeds

### 5.2 — Verify ContextualActionBar.swift (no changes needed)

- [ ] Confirm `ContextualActionBar.swift` receives `onSeeInsight` as a closure parameter — it doesn't reference `InsightEngine` or `StressInsightService` directly
  - Verify: `grep -n "InsightService\|InsightEngine" ContextualActionBar.swift` returns no matches

---

## Phase 6: Cleanup & Polish

### 6.1 — Delete old files

<!-- RESOLVED: M2 — This grep runs AFTER Phase 5 is complete. All HomeView references are already updated. -->
- [ ] Delete `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift`
  - Verify: file no longer exists at that path
- [ ] Delete `WellPlate/Core/Services/StressInsightService.swift`
  - Verify: file no longer exists at that path
- [ ] Delete `WellPlate/Features + UI/Home/StressInsightReport.swift`
  - Verify: file no longer exists at that path
- [ ] Search entire codebase for dangling references (run after all deletions + Phase 5 changes):
  - [ ] `grep -r "StressInsightService" WellPlate/` — should return 0 results (except `StressScoring.swift` comment on line 5, which is just a comment and is fine)
  - [ ] `grep -r "StressInsightReport" WellPlate/` — should return 0 results
  - [ ] `grep -r "HomeAIInsightView" WellPlate/` — should return 0 results
  - [ ] `grep -r "StressInsightDaySummary" WellPlate/` — should return 0 results

### 6.2 — Final build verification

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: all 4 targets build successfully with 0 errors

---

## Post-Implementation Verification

- [ ] **Mock mode test**: Enable `AppConfig.shared.mockMode` → launch → DailyInsightCard visible on home with sparkline → tap → InsightsHubView shows 6+ cards → tap card → InsightDetailSheet opens
- [ ] **Empty state test**: Disable mock mode on fresh simulator → "Not Enough Data" empty state shows
- [ ] **Auto-generation test**: Cold launch → DailyInsightCard populates without manual trigger
- [ ] **Same-day cache test**: Navigate away and back → insights don't regenerate (no loading spinner)
<!-- RESOLVED: L3 — Added scene phase test. -->
- [ ] **Scene phase test**: Background and re-foreground the app on the same day → insights should not regenerate (same-day cache prevents it)
- [ ] **Regenerate test**: In InsightsHubView → tap Regenerate → new cards appear
- [ ] **Dark mode test**: Toggle dark mode → all charts and cards render correctly
- [ ] **Chart types test**: Verify at least 4 chart types render (trend area, scatter, comparison bars, sparkline)
- [ ] Git commit
