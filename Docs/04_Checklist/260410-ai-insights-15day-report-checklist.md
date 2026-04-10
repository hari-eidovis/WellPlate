# Implementation Checklist: 15-Day AI Insights Report

**Source Plan**: `Docs/02_Planning/Specs/260410-ai-insights-15day-report-plan-RESOLVED.md`
**Date**: 2026-04-11

---

## Pre-Implementation

- [ ] Read and understand the resolved plan
  - Verify: Can describe the 13 report sections, zero-tolerance rule, and FM call strategy
- [ ] Verify key files exist and note current line counts:
  - [ ] `WellPlate/Features + UI/Home/Models/InsightModels.swift` (193 lines — will modify)
  - [ ] `WellPlate/Core/Services/InsightEngine.swift` (834 lines — will modify)
  - [ ] `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` (172 lines — will modify)
  - [ ] `WellPlate/Core/Services/CorrelationMath.swift` (95 lines — reuse, no modify)
  - [ ] `WellPlate/Core/Services/StressScoring.swift` (87 lines — reuse, no modify)
  - [ ] `WellPlate/Features + UI/Home/Components/InsightCharts.swift` (380 lines — reuse, no modify)
  - Verify: All files exist and are readable
- [ ] Create the `ReportSections` directory:
  ```bash
  mkdir -p "WellPlate/Features + UI/Home/Views/ReportSections"
  ```
  - Verify: Directory exists. PBXFileSystemSynchronizedRootGroup auto-includes it (no pbxproj edit needed).

---

## Phase 1: Data Models & Types

### 1.1 — Create `ReportModels.swift`

- [ ] Create new file `WellPlate/Features + UI/Home/Models/ReportModels.swift`
- [ ] Define `FoodSymptomClassification` enum with cases: `.potentialTrigger`, `.potentialProtective`, `.neutral`
  - Verify: Enum compiles with `String` raw values
- [ ] Define `FoodSymptomLink` struct with fields: `id` (UUID), `symptomName`, `foodName`, `symptomDayCount`, `clearDayCount`, `symptomDayAppearances`, `clearDayAppearances`, `ratio` (Double), `classification` (FoodSymptomClassification). Conform to `Identifiable`.
  - Verify: Struct compiles
- [ ] Define `CrossCorrelation` struct with fields: `id` (UUID), `xName`, `yName`, `xDomain` (WellnessDomain), `yDomain` (WellnessDomain), `spearmanR`, `ciLow`, `ciHigh`, `pairedDays` (Int), `isSignificant` (Bool), `scatterPoints: [(x: Double, y: Double)]`. Conform to `Identifiable`.
  - Verify: Struct compiles
- [ ] Define `InterventionResult` struct with fields: `id` (UUID), `resetType` (String), `sessionCount` (Int), `avgPreStress`, `avgPostStress`, `avgDelta`, `hasMeasurableData` (Bool). Conform to `Identifiable`.
  - Verify: Struct compiles
- [ ] Define `ExperimentSummary` struct with fields: `id` (UUID), `name`, `hypothesis: String?`, `interventionType`, `baselineAvg: Double?`, `experimentAvg: Double?`, `delta: Double?`, `ciLow: Double?`, `ciHigh: Double?`, `isComplete` (Bool). Conform to `Identifiable`.
  - Verify: Struct compiles
- [ ] Define `ExecutiveSummaryNarrative` struct: `narrative` (String), `topWin` (String), `topConcern` (String)
  - Verify: Struct compiles
- [ ] Define `SectionNarrative` struct: `headline` (String), `narrative` (String)
  - Verify: Struct compiles
- [ ] Define `ActionRecommendation` struct: `title` (String), `rationale` (String), `domain` (String). Conform to `Identifiable` with `let id = UUID()`.
  - Verify: Struct compiles
- [ ] Define `ReportNarratives` struct: `executiveSummary` (ExecutiveSummaryNarrative), `sectionNarratives: [String: SectionNarrative]`, `actionPlan: [ActionRecommendation]`
  - Verify: Struct compiles
- [ ] Define `ReportContext` struct with fields: `days: [WellnessDaySummary]`, `goals: UserGoalsSnapshot`, `availableVitals: Set<VitalMetric>`, `foodSymptomLinks: [FoodSymptomLink]`, `crossCorrelations: [CrossCorrelation]`, `interventionResults: [InterventionResult]`, `experimentSummaries: [ExperimentSummary]`, `topFoods: [(name: String, count: Int, totalCalories: Int)]`, `perSupplementAdherence: [(name: String, rate: Double)]`, `dataQualityNote: String`
  - Verify: Struct compiles
- [ ] Define `ReportData` struct: `context: ReportContext`, `narratives: ReportNarratives`, `generatedAt: Date`
  - Verify: Struct compiles
- [ ] Define `ReportState` enum: `.idle`, `.generating(progress: Double)`, `.ready(ReportData)`, `.error(String)`
  - Verify: Enum compiles
- [ ] Define `ReportPromptContext` struct with `text: String` property (the pre-aggregated LLM prompt string)
  - Verify: Struct compiles
- [ ] **Build check**: Run `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: Build succeeds with 0 errors

### 1.2 — Define Foundation Models `@Generable` schemas

- [ ] In `ReportModels.swift`, add `#if canImport(FoundationModels)` + `import FoundationModels` guard block at the bottom of the file
- [ ] Define `@available(iOS 26, *) @Generable private struct _ReportExecutiveSummary` with `@Guide` annotated fields: `narrative`, `topWin`, `topConcern`
  - Verify: Compiles inside the `#if canImport(FoundationModels)` block
- [ ] Define `@available(iOS 26, *) @Generable private struct _ReportSectionNarrative` with `@Guide` annotated fields: `headline`, `narrative`
  - Verify: Compiles
- [ ] Define `@available(iOS 26, *) @Generable private struct _ReportActionPlan` with field `recommendations: [_ReportActionRecommendation]`
  - Verify: Compiles
- [ ] Define `@available(iOS 26, *) @Generable private struct _ReportActionRecommendation` with `@Guide` annotated fields: `title`, `rationale`, `domain`
  - Verify: Compiles
- [ ] Close `#endif`
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

### 1.3 — Extend `InsightModels.swift`

- [ ] Open `WellPlate/Features + UI/Home/Models/InsightModels.swift`
- [ ] Add new `var` fields with defaults to `WellnessDaySummary` (below line 155, before the closing `}`):
  ```swift
  // Report-specific fields (var with defaults — preserves memberwise init)
  var eatingTriggers: [String: Int] = [:]
  var mealTypes: [String: Int] = [:]
  var foodNames: [String] = []
  var coffeeType: String? = nil
  var mealTimestamps: [Date] = []
  var interventionSessions: [(type: String, stressDelta: Double?)] = []
  // Stress detail
  var stressMin: Double? = nil
  var stressMax: Double? = nil
  var stressReadingCount: Int = 0
  // Vitals
  var restingHeartRateAvg: Double? = nil
  var hrvAvg: Double? = nil
  var systolicBPAvg: Double? = nil
  var diastolicBPAvg: Double? = nil
  var respiratoryRateAvg: Double? = nil
  var daylightMinutes: Double? = nil
  ```
  - Verify: Fields are `var` (not `let`) with default values. Existing `InsightEngine` call site at line 212 is NOT modified.
- [ ] Add `case supplements` to `WellnessDomain` enum (after `cross`):
  - Add to the raw value list: `case stress, nutrition, sleep, activity, hydration, caffeine, mood, fasting, symptoms, cross, supplements`
  - Add `case .supplements:` to `label` → `"Supplements"`, `icon` → `"pill.fill"`, `accentColor` → `Color(hue: 0.72, saturation: 0.50, brightness: 0.80)`
  - Verify: All switch statements in `WellnessDomain` cover the new case (label, icon, accentColor)
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds — critically confirms the existing `InsightEngine` memberwise init call is NOT broken

---

## Phase 2: Data Builder Service

### 2.1 — Create `ReportDataBuilder.swift` scaffold

- [ ] Create new file `WellPlate/Core/Services/ReportDataBuilder.swift`
- [ ] Add `import Foundation`, `import SwiftData`
- [ ] Define `@MainActor final class ReportDataBuilder`
- [ ] Add public method signature: `func buildReportContext(modelContext: ModelContext, healthService: HealthKitServiceProtocol) async -> ReportContext?`
- [ ] Implement date window: `let calendar = Calendar.current; let today = calendar.startOfDay(for: .now); guard let windowStart = calendar.date(byAdding: .day, value: -14, to: today) else { return nil }; let interval = DateInterval(start: windowStart, end: .now)`
  - Verify: Window spans exactly 15 days (today + 14 prior)
- [ ] Implement SwiftData fetches (9 queries with date predicates):
  - `StressReading` where `timestamp >= windowStart`
  - `WellnessDayLog` where `day >= windowStart`
  - `FoodLogEntry` where `day >= windowStart`
  - `SymptomEntry` where `day >= windowStart`
  - `AdherenceLog` where `day >= windowStart`
  - `SupplementEntry` where `isActive == true` (no date filter)
  - `FastingSession` where `startedAt >= windowStart`, then filter `!isActive` (completed only)
  - `InterventionSession` where `startedAt >= windowStart`, then filter `completed == true`
  - `StressExperiment` (fetch all, filter for overlap with window in memory)
  - `UserGoals.current(in: modelContext)` → `UserGoalsSnapshot`
  - Verify: Each fetch uses `FetchDescriptor` with `#Predicate` and returns `[]` on failure (`(try? ctx.fetch(...)) ?? []`)
- [ ] Implement concurrent HealthKit fetches (11 `async let`):
  - steps, activeEnergy, exerciseMinutes, heartRate, restingHeartRate, HRV, BPsystolic, BPdiastolic, respiratoryRate, sleepSummaries, daylight
  - Each wrapped: `(try? await healthService.fetchX(for: interval)) ?? []`
  - Verify: All 11 fetches are `async let` with `await` on the tuple
- [ ] Build `availableVitals: Set<VitalMetric>`:
  - Check each HK vital result: if `!restingHRData.isEmpty` → insert `.restingHeartRate`; if `!hrvData.isEmpty` → insert `.hrv`; etc.
  - Verify: Empty results → metric NOT in set; non-empty → IS in set
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds (method can return `nil` for now)

### 2.2 — Implement per-day summary loop

- [ ] In `buildReportContext()`, iterate `stride(from: -14, through: 0, by: 1)` over day offsets
- [ ] For each day, build a `WellnessDaySummary` using the same pattern as `InsightEngine.buildWellnessContext()` (lines 168-240), including:
  - Stress: avg score, label
  - Sleep: hours, deep, REM, bedtime, wakeTime
  - Activity: steps, energy, exercise minutes, heartRate avg
  - Nutrition: calories, protein, carbs, fat, fiber, mealCount
  - Hydration/caffeine: waterGlasses, coffeeCups
  - Mood: label
  - Symptoms: names, maxSeverity
  - Fasting: hours, completed
  - Supplements: adherence rate
  - Verify: Core fields match InsightEngine output for same data
- [ ] After creating the `WellnessDaySummary`, mutate the new `var` fields:
  - `summary.eatingTriggers` = aggregate `dayFood.flatMap { $0.eatingTriggers ?? [] }` into `[String: Int]` count dict
  - `summary.mealTypes` = aggregate `dayFood.compactMap { $0.mealType }` into `[String: Int]` count dict
  - `summary.foodNames` = `dayFood.map(\.foodName)`
  - `summary.coffeeType` = `wellness?.coffeeType`
  - `summary.mealTimestamps` = `dayFood.map(\.createdAt)`
  - `summary.stressMin` = `dayReadings.map(\.score).min()`
  - `summary.stressMax` = `dayReadings.map(\.score).max()`
  - `summary.stressReadingCount` = `dayReadings.count`
  - Vitals: `summary.restingHeartRateAvg`, `.hrvAvg`, `.systolicBPAvg`, `.diastolicBPAvg`, `.respiratoryRateAvg`, `.daylightMinutes` from respective HK data arrays
  - Verify: New fields populated for days with data, remain default for days without
- [ ] Append each summary to `days` array
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

### 2.3 — Implement `computeFoodSymptomLinks()`

- [ ] Add private method `func computeFoodSymptomLinks(symptomEntries: [SymptomEntry], foodLogs: [FoodLogEntry], days: [WellnessDaySummary]) -> [FoodSymptomLink]`
- [ ] Group symptoms by name; filter to those with >= 3 occurrences
- [ ] For each qualifying symptom:
  - Identify symptom days (Set of dates)
  - Identify clear days (dates without this symptom that have food logs)
  - For each unique food across all days (require food appears >= 2 times total):
    - Count symptom-day appearances (same day OR `calendar.date(byAdding: .day, value: -1, to: symptomDay)`)
    - Count clear-day appearances
    - Compute ratio; guard div-by-zero (skip if clearDayAppearances == 0)
    - Classify: ratio > 2.0 → `.potentialTrigger`, ratio < 0.5 → `.potentialProtective`, else `.neutral`
  - Filter out `.neutral` links
  - Verify: Returns `[FoodSymptomLink]` with only trigger/protective entries
- [ ] Call from `buildReportContext()` and store result
  - Verify: Build succeeds

### 2.4 — Implement `computeCrossCorrelations()`

- [ ] Add private method `func computeCrossCorrelations(days: [WellnessDaySummary], availableVitals: Set<VitalMetric>) async -> [CrossCorrelation]`
- [ ] Define metric pairs array (13 pairs per plan), each with `xName`, `yName`, `xDomain`, `yDomain`, and extract closures on `WellnessDaySummary`
- [ ] Filter pairs: skip any involving an unavailable vital
- [ ] For each pair: extract paired values (days where both non-nil), require >= 5 pairs
- [ ] Compute `CorrelationMath.spearmanR()` and `CorrelationMath.bootstrapCI()` on `Task.detached(priority: .userInitiated)`
- [ ] Filter to `|r| >= 0.3` AND CI doesn't span zero
- [ ] Cap matrix metrics at 8 (highest data density)
- [ ] Sort by `|r|` descending
  - Verify: Returns `[CrossCorrelation]` with only significant entries; matrix metrics <= 8

### 2.5 — Implement `computeInterventionResults()`

- [ ] Add private method `func computeInterventionResults(sessions: [InterventionSession], readings: [StressReading]) -> [InterventionResult]`
- [ ] Group completed sessions by `resetType`
- [ ] For each session: find closest `StressReading` before `startedAt` within 4 hours, and after `startedAt + durationSeconds` within 4 hours
- [ ] If both found: delta = post.score - pre.score
- [ ] Aggregate per type: count, avg pre, avg post, avg delta, `hasMeasurableData = measuredSessionCount > 0`
  - Verify: Returns `[InterventionResult]`; sessions with no nearby readings → `hasMeasurableData = false`

### 2.6 — Implement `buildExperimentSummaries()`

- [ ] Add private method `func buildExperimentSummaries(experiments: [StressExperiment], windowStart: Date) -> [ExperimentSummary]`
- [ ] Filter to experiments overlapping the 15-day window
- [ ] Map to `ExperimentSummary` from cached fields
  - Verify: Returns `[ExperimentSummary]`

### 2.7 — Implement `computeTopFoods()` and `computePerSupplementAdherence()`

- [ ] `computeTopFoods(foodLogs: [FoodLogEntry]) -> [(name: String, count: Int, totalCalories: Int)]`: Group by `foodName`, count occurrences, sum calories, sort by count descending, take top 10
  - Verify: Returns top 10 foods
- [ ] `computePerSupplementAdherence(adherenceLogs: [AdherenceLog], supplements: [SupplementEntry]) -> [(name: String, rate: Double)]`: Group by supplementName, compute taken/total rate per supplement, sort by rate ascending (worst first)
  - Verify: Returns per-supplement rates

### 2.8 — Implement `buildPromptContext()`

- [ ] Add method `func buildPromptContext(from context: ReportContext) -> ReportPromptContext`
- [ ] Build compact text string (~500-800 words):
  - Period: date range, days with data, domains active
  - Per-domain stats: avg, range, goal%, trend direction
  - Top correlations: name + r-value
  - Top food-symptom links: food + symptom + ratio
  - Intervention results: type + avg delta
  - Experiment results: name + delta
  - Exclude any metric not in `availableVitals` or with zero data
  - Verify: Output text is < 1000 words and covers all active domains

### 2.9 — Assemble final `ReportContext`

- [ ] In `buildReportContext()`, call all sub-methods and assemble into `ReportContext(...)`
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; `buildReportContext()` returns a complete `ReportContext`

---

## Phase 3: Narrative Generation Service

### 3.1 — Create `ReportNarrativeGenerator.swift`

- [ ] Create new file `WellPlate/Core/Services/ReportNarrativeGenerator.swift`
- [ ] Add `import Foundation` + `#if canImport(FoundationModels)` / `import FoundationModels` / `#endif`
- [ ] Define `@MainActor final class ReportNarrativeGenerator`
- [ ] Add public method: `func generateNarratives(for context: ReportContext, promptContext: ReportPromptContext) async -> ReportNarratives`

### 3.2 — Implement Foundation Models path

- [ ] Add `@available(iOS 26, *)` private method `generateWithFM(...)` returning `ReportNarratives?`
- [ ] Guard `SystemLanguageModel.default.availability == .available`
- [ ] **FM Call 1 — Executive Summary**: Build prompt, create `LanguageModelSession()`, call `session.respond(to:, generating: _ReportExecutiveSummary.self)`, map to `ExecutiveSummaryNarrative`. Wrap in do/catch.
  - Verify: Matches pattern in `InsightEngine.swift` line 689
- [ ] **FM Calls 2-6 — Section Narratives**: Define priority list: `["stress", "nutrition", "sleep", "symptoms", "activity", "cross"]`. Loop over top 5 that have data. For each:
  - Build section-specific prompt with `buildSectionNarrativePrompt(sectionName:, sectionStats:, promptContext:)`
  - Create fresh `LanguageModelSession()` per call
  - Generate `_ReportSectionNarrative`
  - Store in `sectionNarratives[sectionName]`
  - On failure: fall through to template for that section
  - Verify: Each call is independent; failure of one doesn't block others
- [ ] **FM Call 7 — Action Plan**: Build prompt, create `LanguageModelSession()`, generate `_ReportActionPlan`, map to `[ActionRecommendation]`. Wrap in do/catch.
  - Verify: Returns 3-5 recommendations

### 3.3 — Implement template fallback

- [ ] Add private method `generateTemplates(for context: ReportContext, promptContext: ReportPromptContext) -> ReportNarratives`
- [ ] Executive summary template: rule-based from stats ("Over the past 15 days, your [top metric] has been [direction]...")
- [ ] Section narrative templates: per-section template strings referencing computed stats
- [ ] Action plan templates: top 3-5 rules based on goal gaps and correlation strength
  - Verify: Produces readable narratives without FM

### 3.4 — Wire up main method

- [ ] In `generateNarratives()`:
  - `if #available(iOS 26, *)` → try FM path; if returns nil → fall through
  - Fallback: return template narratives
  - Verify: Always returns a valid `ReportNarratives`
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

---

## Phase 4: ViewModel

### 4.1 — Create `ReportViewModel.swift`

- [ ] Create new file `WellPlate/Features + UI/Home/ViewModels/ReportViewModel.swift`
- [ ] Define `@MainActor final class AI15DayReportViewModel: ObservableObject`
- [ ] Add `@Published var reportState: ReportState = .idle`
- [ ] Add private properties: `dataBuilder = ReportDataBuilder()`, `narrativeGenerator = ReportNarrativeGenerator()`, `modelContext: ModelContext?`, `healthService: HealthKitServiceProtocol`
- [ ] Add `init(healthService: HealthKitServiceProtocol = HealthKitService())`
- [ ] Add `func bindContext(_ context: ModelContext)`
- [ ] Implement `func generateReport() async`:
  1. Check same-day cache: if `.ready` and generatedAt is today, return early
  2. Set `reportState = .generating(progress: 0)`
  3. Guard `modelContext` is non-nil
  4. Call `dataBuilder.buildReportContext(...)` → set progress 0.3
  5. Guard result non-nil (else set `.error`)
  6. Call `dataBuilder.buildPromptContext(from:)` → set progress 0.4
  7. Call `narrativeGenerator.generateNarratives(...)` → set progress 0.9
  8. Assemble `ReportData(context:, narratives:, generatedAt: .now)` → set progress 1.0
  9. Set `reportState = .ready(reportData)`
  10. Catch: set `reportState = .error(error.localizedDescription)`
  - Verify: State transitions are correct; progress updates monotonically
- [ ] Implement `func clearAndRegenerate() async`: reset `reportState = .idle`, call `generateReport()`
- [ ] Implement mock mode: if `AppConfig.shared.mockMode`, return hardcoded `ReportData` with mock values for all sections (15 days of varied data, 3 food-symptom links, 4 correlations, 1 intervention, 1 experiment, pre-written narratives)
  - Verify: Mock data exercises all section conditions
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

---

## Phase 5: Chart Components

### 5.1 — Create `ReportCharts.swift`

- [ ] Create new file `WellPlate/Features + UI/Home/Components/ReportCharts.swift`
- [ ] Add `import SwiftUI` + `import Charts`

- [ ] Implement `StatPillRow`:
  - Input: `[(label: String, value: String, color: Color?)]`
  - Layout: `HStack` of capsule pills with `.font(.system(size: 11, weight: .semibold, design: .rounded))`
  - Verify: Renders a horizontal row of stat capsules in Preview

- [ ] Implement `StressVolatilityChart`:
  - Input: `[(date: Date, min: Double, max: Double, avg: Double)]`
  - Chart: `RuleMark` vertical bars (min→max) + `PointMark` for avg
  - Verify: Renders range bars in Preview

- [ ] Implement `FactorDecompositionChart`:
  - Input: `[(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)]`
  - Chart: Stacked horizontal `BarMark` with 4 colors
  - Verify: Renders stacked bars in Preview

- [ ] Implement `MealTimingHeatmap`:
  - Input: `[(dayLabel: String, bucket: String, count: Int)]`
  - Chart: `RectangleMark` grid with color intensity
  - Verify: Renders 5-row heatmap in Preview

- [ ] Implement `BedtimeScatterChart`:
  - Input: `[(date: Date, bedtime: Date?, wakeTime: Date?)]`
  - Chart: Two `PointMark` series (bedtime=indigo, wake=orange)
  - Verify: Renders scatter points in Preview

- [ ] Implement `VitalTrendChart`:
  - Input: `points: [DailyMetricSample]`, `metric: VitalMetric`
  - Chart: `LineMark` + `AreaMark` gradient + `RuleMark` benchmark bands
  - Verify: Renders for each `VitalMetric` case in Preview

- [ ] Implement `SymptomTimelineChart`:
  - Input: `[(date: Date, maxSeverity: Int, count: Int, stressScore: Double?)]`
  - Chart: `PointMark` sized by count, colored by severity + optional stress `LineMark`
  - Verify: Renders bubble chart in Preview

- [ ] Implement `CorrelationMatrixChart`:
  - Input: `metrics: [String]` (max 8), `correlations: [(xIdx: Int, yIdx: Int, r: Double, isSignificant: Bool)]`
  - Chart: `RectangleMark` heatmap, blue→white→red scale, gray for non-significant
  - Labels: abbreviated max 6 chars
  - Verify: Renders 8x8 grid in Preview

- [ ] Implement `AdherenceGauge`:
  - Input: `rate: Double` (0-1), `label: String`
  - Layout: Custom arc (match `MilestoneRingView` pattern) + center text
  - Verify: Renders gauge ring in Preview

- [ ] Implement `FoodSensitivityRow`:
  - Input: `FoodSymptomLink`
  - Layout: food name, ratio badge (red trigger/green protective), appearance text
  - Verify: Renders row in Preview

- [ ] Implement `SymptomCategoryDonut`:
  - Input: `[(category: SymptomCategory, count: Int)]`
  - Chart: `SectorMark` with `SymptomCategory.color` (first `SectorMark` usage in project)
  - Verify: Renders donut chart in Preview

- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; all chart Previews render

---

## Phase 6: Report Section Views

### 6.1 — `ReportHeaderSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ReportHeaderSection.swift`
- [ ] Input: `ReportData`
- [ ] Layout: Title "Your 15-Day Wellness Report", date range subtitle, data quality badge
- [ ] Add `insightEntrance(index: 0)` animation
  - Verify: Renders header with correct date range in Preview

### 6.2 — `ExecutiveSummarySection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ExecutiveSummarySection.swift`
- [ ] Input: `ReportData`
- [ ] Layout: narrative text + topWin pill (green) + topConcern pill (amber)
  - Verify: Renders narrative and pills in Preview

### 6.3 — `StressDeepDiveSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.stressScore != nil }`
- [ ] Implement sub-views:
  - 2a: `TrendAreaChart` (existing) for stress trend + `StatPillRow`
  - 2b: `StressVolatilityChart` from `stressMin`/`stressMax` fields
  - 2c: `FactorDecompositionChart` — compute factor scores via `StressScoring` for top 3 best/worst days
  - 2d: Best vs worst day side-by-side cards
  - 2e: Intervention results (conditional: `!data.context.interventionResults.isEmpty`)
  - 2f: Experiment results (conditional: `!data.context.experimentSummaries.isEmpty`)
- [ ] Include section narrative from `data.narratives.sectionNarratives["stress"]`
  - Verify: All 6 sub-views render with mock data

### 6.4 — `NutritionSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/NutritionSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.totalCalories != nil }`
- [ ] Implement sub-views:
  - 3a: Calorie trend `BarMark` with goal line + color coding (green/amber/red)
  - 3b: `MacroGroupedBarChart` (existing) with averages vs goals
  - 3c: `MealTimingHeatmap` from `mealTimestamps`
  - 3d: Meal type distribution horizontal bars
  - 3e: Eating triggers frequency bars
  - 3f: Top foods ranked list from `data.context.topFoods`
  - 3g: Food variety score (unique foodNames count + benchmark label)
  - Verify: All 7 sub-views render with mock data

### 6.5 — `SleepSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SleepSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.sleepHours != nil }`
- [ ] Implement: stacked bars (deep/REM/core), deep sleep ratio line, `BedtimeScatterChart`, sleep-stress scatter (conditional >= 5 days)
  - Verify: All sub-views render

### 6.6 — `ActivitySection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ActivitySection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.steps != nil || $0.activeCalories != nil }`
- [ ] Implement: steps bars + rolling avg, energy area chart, exercise minutes with per-day goals, movement-stress scatter (conditional)
  - Verify: All sub-views render

### 6.7 — `VitalsSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/VitalsSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `!data.context.availableVitals.isEmpty`
- [ ] Loop over `data.context.availableVitals`: render `VitalTrendChart` per metric
  - Verify: Only available vitals render; empty vitals → section hidden entirely

### 6.8 — `HydrationCaffeineSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/HydrationCaffeineSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { ($0.waterGlasses ?? 0) > 0 || ($0.coffeeCups ?? 0) > 0 }`
- [ ] Implement: water bars + goal, coffee bars + goal + type distribution, caffeine-stress comparison (conditional)
  - Verify: All sub-views render

### 6.9 — `SymptomSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SymptomSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { !$0.symptomNames.isEmpty }`
- [ ] Implement: frequency bars, `SymptomTimelineChart`, `SymptomCategoryDonut`, food sensitivity table with `FoodSensitivityRow` components, symptom-stress scatter
- [ ] Add disclaimer text: "Correlations require more data to confirm" for links with < 7 paired days
  - Verify: Food sensitivity table renders with trigger/protective classifications

### 6.10 — `SupplementSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SupplementSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.supplementAdherence != nil }`
- [ ] Implement: `AdherenceGauge`, per-supplement breakdown bars (green/amber/red), adherence-symptom link (conditional)
  - Verify: All sub-views render

### 6.11 — `FastingSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/FastingSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.fastingHours != nil }`
- [ ] Implement: stat pills, duration bars, fasting-stress comparison (conditional)
  - Verify: Sub-views render

### 6.12 — `MoodSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/MoodSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `data.context.days.contains { $0.moodLabel != nil }`
- [ ] Implement: mood distribution bars, mood-stress dual-line overlay
  - Verify: Sub-views render

### 6.13 — `CrossDomainSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/CrossDomainSection.swift`
- [ ] Input: `ReportData`
- [ ] Condition: `!data.context.crossCorrelations.isEmpty`
- [ ] Implement: `CorrelationMatrixChart` (max 8 metrics), top 3 strongest link cards with `CorrelationScatterChart`
  - Verify: Matrix renders with correct colors; top 3 cards show scatter plots

### 6.14 — `ActionPlanSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ActionPlanSection.swift`
- [ ] Input: `ReportData`
- [ ] Always shown
- [ ] Implement: 3-5 recommendation cards with title, rationale, domain icon/color
  - Verify: Cards render with domain accent tints

- [ ] **Build check**: Run main scheme build after all section views
  - Verify: Build succeeds

---

## Phase 7: Main Report View & Navigation

### 7.1 — Create `AI15DayReportView.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/AI15DayReportView.swift`
- [ ] Add `@StateObject private var viewModel = AI15DayReportViewModel()`
- [ ] Add `@Environment(\.modelContext) private var modelContext`
- [ ] On appear: `viewModel.bindContext(modelContext); Task { await viewModel.generateReport() }`
- [ ] Switch on `viewModel.reportState`:
  - `.idle` / `.generating(let progress)`: Centered `ProgressView` + "Analyzing your wellness data..." + progress % text
  - `.ready(let data)`: `ScrollView > LazyVStack(spacing: 24)` with conditional sections (order per plan: header, exec summary, stress, nutrition, sleep, activity, vitals, hydration, symptoms, supplements, fasting, mood, cross-domain, action plan)
  - `.error`: Error text + "Retry" button
- [ ] Add `insightEntrance(index:)` on each section (incrementing index)
- [ ] Add footer: generated-at text + "Regenerate" button
- [ ] Set `.navigationTitle("Wellness Report")` + `.navigationBarTitleDisplayMode(.inline)`
  - Verify: View compiles; switches between states correctly

### 7.2 — Update `InsightsHubView.swift`

- [ ] Open `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`
- [ ] Add `@State private var showFullReport = false`
- [ ] In `cardFeed`, between `InsightsHubHeader` and `ForEach`, insert a "View 15-Day Report" card:
  - Sparkles icon + "Generate your comprehensive 15-day wellness report" text
  - `Button` that sets `showFullReport = true`
  - Style: branded card with `AppColors.brand` tint, rounded rect, `insightEntrance(index: 1)`
  - Offset ForEach entrance indices by +1
  - Verify: Card appears in the hub feed
- [ ] Add `.navigationDestination(isPresented: $showFullReport) { AI15DayReportView() }`
  - Verify: Tapping the card navigates to the report view

- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; navigation works

---

## Phase 8: Update InsightEngine

### 8.1 — Enrich `InsightEngine.buildWellnessContext()` with new fields

- [ ] Open `WellPlate/Core/Services/InsightEngine.swift`
- [ ] In the concurrent HealthKit fetch block (~line 153-158), add `async let` for:
  - `restingHRFetch = fetchRestingHRSafely(range: interval)`
  - `hrvFetch = fetchHRVSafely(range: interval)`
  - `systolicFetch = fetchSystolicSafely(range: interval)`
  - `diastolicFetch = fetchDiastolicSafely(range: interval)`
  - `respiratoryFetch = fetchRespiratorySafely(range: interval)`
  - `daylightFetch = fetchDaylightSafely(range: interval)`
  - Verify: Await them alongside existing tuple
- [ ] Add corresponding private safe-fetch methods (matching existing pattern at lines 254-272):
  - `fetchRestingHRSafely`, `fetchHRVSafely`, `fetchSystolicSafely`, `fetchDiastolicSafely`, `fetchRespiratorySafely`, `fetchDaylightSafely`
  - Verify: Each returns `(try? await healthService.fetchX(for:)) ?? []`
- [ ] In the per-day loop (after `days.append(WellnessDaySummary(...))`), change to:
  ```swift
  var summary = WellnessDaySummary(/* existing args unchanged */)
  summary.eatingTriggers = /* aggregate from dayFood */
  summary.mealTypes = /* aggregate from dayFood */
  summary.foodNames = dayFood.map(\.foodName)
  summary.coffeeType = wellness?.coffeeType
  summary.mealTimestamps = dayFood.map(\.createdAt)
  summary.stressMin = dayReadings.map(\.score).min()
  summary.stressMax = dayReadings.map(\.score).max()
  summary.stressReadingCount = dayReadings.count
  summary.restingHeartRateAvg = restingHRData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.hrvAvg = hrvData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.systolicBPAvg = systolicData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.diastolicBPAvg = diastolicData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.respiratoryRateAvg = respiratoryData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.daylightMinutes = daylightData.first { cal.isDate($0.date, inSameDayAs: dayStart) }?.value
  days.append(summary)
  ```
  - Verify: Existing `WellnessDaySummary(...)` init call is NOT changed — only post-mutation of `var` fields
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; existing InsightEngine behavior unchanged

---

## Post-Implementation

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 builds succeed with 0 errors
- [ ] Test mock mode: Set `AppConfig.shared.mockMode = true`, navigate Home → InsightsHub → "View 15-Day Report"
  - Verify: All 13 sections render with mock data; scroll is smooth
- [ ] Test section visibility: Modify mock data to remove food logs
  - Verify: Nutrition section disappears; other sections unaffected
- [ ] Test zero-tolerance: Modify mock data to clear all vitals
  - Verify: Vitals section hidden; no vital references in other sections
- [ ] Git commit with descriptive message
