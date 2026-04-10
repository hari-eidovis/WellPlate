# Implementation Checklist: 15-Day AI Insights Report

**Source Plan**: `Docs/02_Planning/Specs/260410-ai-insights-15day-report-plan-RESOLVED.md`
**Date**: 2026-04-11
**Status**: RESOLVED — ready for implementation

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| C1: `@Generable` private structs in wrong file | CRITICAL | Moved from Step 1.2 (`ReportModels.swift`) to Step 3.1 (`ReportNarrativeGenerator.swift`). Step 1.2 removed entirely. Matches existing codebase pattern. |
| H1: Missing `async let` tuple destructuring in Step 8.1 | HIGH | Added explicit second `await` tuple with concrete syntax for 6 new vital fetches. |
| M1: `#Predicate` vs in-memory filter ambiguity | MEDIUM | Added "(in-memory, NOT `#Predicate`)" annotations to all post-fetch filters. |
| M2: `eatingTriggers` aggregation pattern unspecified | MEDIUM | Added concrete `Dictionary(..., uniquingKeysWith: +)` pattern. |
| M3: No intermediate build check in Phase 6 | MEDIUM | Added build check after Step 6.4 (NutritionSection). |
| M4: Missing `journalLogged` in per-day summary | MEDIUM | Added `journalLogged: false` to memberwise init (journal excluded from report). |
| M5: Entrance index offset incomplete | MEDIUM | Added explicit index math: ForEach `idx + 2`, footer `count + 2`. |
| L1: No `#Preview` for section views | LOW | Added `#Preview` requirement to each section step. |
| L2: `@Guide` descriptions unspecified | LOW | Added concrete `@Guide` description strings to Step 3.1. |

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
- [ ] Define `FoodSymptomClassification` enum with cases: `.potentialTrigger`, `.potentialProtective`, `.neutral`. Conform to `String`.
  - Verify: Enum compiles
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

<!-- RESOLVED: C1 — Step 1.2 (@Generable schemas) REMOVED from here. Schemas moved to Step 3.1 (ReportNarrativeGenerator.swift) where they are consumed. This matches the existing codebase pattern: all @Generable private structs live in the same file as the service that calls session.respond(to:, generating:). -->

### 1.2 — Extend `InsightModels.swift`

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
  - Update case list: `case stress, nutrition, sleep, activity, hydration, caffeine, mood, fasting, symptoms, cross, supplements`
  - Add `case .supplements:` to ALL three switch statements: `label` → `"Supplements"`, `icon` → `"pill.fill"`, `accentColor` → `Color(hue: 0.72, saturation: 0.50, brightness: 0.80)`
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
  - `StressReading` where `timestamp >= windowStart` via `#Predicate`
  - `WellnessDayLog` where `day >= windowStart` via `#Predicate`
  - `FoodLogEntry` where `day >= windowStart` via `#Predicate`
  - `SymptomEntry` where `day >= windowStart` via `#Predicate`
  - `AdherenceLog` where `day >= windowStart` via `#Predicate`
  - `SupplementEntry` — fetch all, then **in-memory** filter `isActive == true`
  - `FastingSession` where `startedAt >= windowStart` via `#Predicate`, then **in-memory** filter `.filter { !$0.isActive }` (`.isActive` is a computed property — cannot use in `#Predicate`)
  <!-- RESOLVED: M1 — Explicitly marked in-memory filters vs #Predicate -->
  - `InterventionSession` where `startedAt >= windowStart` via `#Predicate`, then **in-memory** filter `.filter { $0.completed }` (`completed` is a stored Bool so `#Predicate` could work, but post-filtering is simpler and consistent)
  - `StressExperiment` — fetch all, then **in-memory** filter for overlap with window
  - `UserGoals.current(in: modelContext)` → `UserGoalsSnapshot`
  - Verify: Each fetch uses `FetchDescriptor` with `#Predicate` where possible, returns `[]` on failure (`(try? ctx.fetch(...)) ?? []`)
- [ ] Implement concurrent HealthKit fetches (11 `async let`):
  - steps, activeEnergy, exerciseMinutes, heartRate, restingHeartRate, HRV, BPsystolic, BPdiastolic, respiratoryRate, sleepSummaries, daylight
  - Each wrapped: `(try? await healthService.fetchX(for: interval)) ?? []`
  - Verify: All 11 fetches are `async let` with `await` on the tuples
- [ ] Build `availableVitals: Set<VitalMetric>`:
  - Check each HK vital result: if `!restingHRData.isEmpty` → insert `.restingHeartRate`; if `!hrvData.isEmpty` → insert `.hrv`; if `!systolicData.isEmpty` → insert `.systolicBP`; if `!diastolicData.isEmpty` → insert `.diastolicBP`; if `!respiratoryData.isEmpty` → insert `.respiratoryRate`
  - Also check core metrics: if `!heartRateData.isEmpty` → insert `.heartRate`
  - Verify: Empty results → metric NOT in set; non-empty → IS in set
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds (method can return `nil` for now)

### 2.2 — Implement per-day summary loop

<!-- RESOLVED: M4 — Added journalLogged: false to memberwise init since journal is excluded from report -->
<!-- RESOLVED: M2 — Added concrete Dictionary(..., uniquingKeysWith: +) pattern for trigger aggregation -->

- [ ] In `buildReportContext()`, iterate `stride(from: -14, through: 0, by: 1)` over day offsets
- [ ] For each day, build a `WellnessDaySummary` using the same pattern as `InsightEngine.buildWellnessContext()` (lines 168-240), including:
  - Stress: avg score, label (from `WellnessDayLog.stressLevel`)
  - Sleep: hours, deep, REM, bedtime, wakeTime (from sleep summaries)
  - Activity: steps, energy, exercise minutes, heartRate avg
  - Nutrition: calories, protein, carbs, fat, fiber, mealCount
  - Hydration/caffeine: waterGlasses, coffeeCups
  - Mood: label (from `WellnessDayLog.mood?.label`)
  - Symptoms: names, maxSeverity
  - Fasting: hours, completed
  - Supplements: adherence rate
  - **`journalLogged: false`** — journal is excluded from the report; pass `false` to satisfy the `let` field
  - Verify: Core fields match InsightEngine output for same data
- [ ] After creating the `WellnessDaySummary`, mutate the new `var` fields:
  - `summary.eatingTriggers`:
    ```swift
    let triggerStrings = dayFood.flatMap { $0.eatingTriggers ?? [] }
    summary.eatingTriggers = Dictionary(triggerStrings.map { ($0, 1) }, uniquingKeysWith: +)
    ```
  - `summary.mealTypes`:
    ```swift
    let typeStrings = dayFood.compactMap { $0.mealType }
    summary.mealTypes = Dictionary(typeStrings.map { ($0, 1) }, uniquingKeysWith: +)
    ```
  - `summary.foodNames` = `dayFood.map(\.foodName)`
  - `summary.coffeeType` = `wellness?.coffeeType`
  - `summary.mealTimestamps` = `dayFood.map(\.createdAt)`
  - `summary.stressMin` = `dayReadings.map(\.score).min()`
  - `summary.stressMax` = `dayReadings.map(\.score).max()`
  - `summary.stressReadingCount` = `dayReadings.count`
  - Vitals: `summary.restingHeartRateAvg`, `.hrvAvg`, `.systolicBPAvg`, `.diastolicBPAvg`, `.respiratoryRateAvg`, `.daylightMinutes` — each from respective HK data arrays matched by `calendar.isDate($0.date, inSameDayAs: dayStart)`
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
    - Compute ratio; guard div-by-zero (skip if clearDayAppearances == 0 or clearDayCount == 0)
    - Classify: ratio > 2.0 → `.potentialTrigger`, ratio < 0.5 → `.potentialProtective`, else `.neutral`
  - Filter out `.neutral` links
  - Verify: Returns `[FoodSymptomLink]` with only trigger/protective entries
- [ ] Call from `buildReportContext()` and store result
  - Verify: Build succeeds

### 2.4 — Implement `computeCrossCorrelations()`

- [ ] Add private method `func computeCrossCorrelations(days: [WellnessDaySummary], availableVitals: Set<VitalMetric>) async -> [CrossCorrelation]`
- [ ] Define metric pairs array (13 pairs per plan), each with `xName`, `yName`, `xDomain`, `yDomain`, and extract closures on `WellnessDaySummary`
- [ ] Filter pairs: skip any involving a vital not in `availableVitals`
- [ ] For each pair: extract paired values (days where both non-nil), require >= 5 pairs
- [ ] Compute `CorrelationMath.spearmanR()` and `CorrelationMath.bootstrapCI()` on `Task.detached(priority: .userInitiated)`
- [ ] Filter to `|r| >= 0.3` AND CI doesn't span zero (`!(ciLow < 0 && ciHigh > 0)`)
- [ ] Cap matrix metrics at 8 (keep metrics with highest data-day count)
- [ ] Sort by `|r|` descending
  - Verify: Returns `[CrossCorrelation]` with only significant entries; matrix metrics <= 8

### 2.5 — Implement `computeInterventionResults()`

- [ ] Add private method `func computeInterventionResults(sessions: [InterventionSession], readings: [StressReading]) -> [InterventionResult]`
- [ ] Filter to `sessions.filter { $0.completed }` (in-memory)
- [ ] Group by `resetType`
- [ ] For each session: find closest `StressReading` before `startedAt` within 4 hours, and closest after `startedAt + TimeInterval(durationSeconds)` within 4 hours
- [ ] If both found: delta = post.score - pre.score
- [ ] Aggregate per type: count, avg pre, avg post, avg delta, `hasMeasurableData = measuredSessionCount > 0`
  - Verify: Returns `[InterventionResult]`; sessions with no nearby readings → `hasMeasurableData = false`

### 2.6 — Implement `buildExperimentSummaries()`

- [ ] Add private method `func buildExperimentSummaries(experiments: [StressExperiment], windowStart: Date) -> [ExperimentSummary]`
- [ ] Filter to experiments where `startDate <= .now` AND `endDate >= windowStart` (overlaps window)
- [ ] Map to `ExperimentSummary` from cached fields (`cachedBaselineAvg`, `cachedExperimentAvg`, `cachedDelta`, `cachedCILow`, `cachedCIHigh`)
  - Verify: Returns `[ExperimentSummary]`

### 2.7 — Implement `computeTopFoods()` and `computePerSupplementAdherence()`

- [ ] `computeTopFoods(foodLogs: [FoodLogEntry]) -> [(name: String, count: Int, totalCalories: Int)]`:
  - Group by `foodName`
  - For each group: count = entries.count, totalCalories = entries.map(\.calories).reduce(0, +)
  - Sort by count descending, take top 10
  - Verify: Returns top 10 foods sorted by frequency
- [ ] `computePerSupplementAdherence(adherenceLogs: [AdherenceLog], supplements: [SupplementEntry]) -> [(name: String, rate: Double)]`:
  - Group adherence logs by `supplementName`
  - For each group: rate = (logs with status "taken").count / total.count
  - Sort by rate ascending (worst first)
  - Verify: Returns per-supplement rates, worst first

### 2.8 — Implement `buildPromptContext()`

- [ ] Add method `func buildPromptContext(from context: ReportContext) -> ReportPromptContext`
- [ ] Build compact text string (~500-800 words):
  - Period: date range, days with data, domains active
  - Per-domain stats: avg, range, goal%, trend direction
  - Top correlations: name + r-value (top 3)
  - Top food-symptom links: food + symptom + ratio (top 5)
  - Intervention results: type + avg delta
  - Experiment results: name + delta
  - Exclude any metric not in `availableVitals` or with zero data
  - Wrap in `ReportPromptContext(text: ...)`
  - Verify: Output text < 1000 words, covers all active domains, omits absent ones

### 2.9 — Assemble final `ReportContext`

- [ ] In `buildReportContext()`, call all sub-methods and assemble:
  ```swift
  return ReportContext(
      days: days,
      goals: goals,
      availableVitals: availableVitals,
      foodSymptomLinks: computeFoodSymptomLinks(...),
      crossCorrelations: await computeCrossCorrelations(...),
      interventionResults: computeInterventionResults(...),
      experimentSummaries: buildExperimentSummaries(...),
      topFoods: computeTopFoods(...),
      perSupplementAdherence: computePerSupplementAdherence(...),
      dataQualityNote: qualityNote
  )
  ```
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; `buildReportContext()` returns a complete `ReportContext`

---

## Phase 3: Narrative Generation Service

<!-- RESOLVED: C1 — @Generable schemas now defined HERE in ReportNarrativeGenerator.swift (not ReportModels.swift). All @Generable private structs must live in the same file as the LanguageModelSession call that uses them. -->

### 3.1 — Create `ReportNarrativeGenerator.swift` with `@Generable` schemas

- [ ] Create new file `WellPlate/Core/Services/ReportNarrativeGenerator.swift`
- [ ] Add `import Foundation`
- [ ] Add `#if canImport(FoundationModels)` + `import FoundationModels` + `#endif` at top
- [ ] Define `@MainActor final class ReportNarrativeGenerator`
- [ ] Add public method: `func generateNarratives(for context: ReportContext, promptContext: ReportPromptContext) async -> ReportNarratives`
- [ ] At the bottom of the file, inside `#if canImport(FoundationModels)` block, define the `@Generable` schemas:
  <!-- RESOLVED: L2 — Added concrete @Guide descriptions -->
  ```swift
  #if canImport(FoundationModels)
  @available(iOS 26, *)
  @Generable
  private struct _ReportExecutiveSummary {
      @Guide(description: "3-4 sentence narrative summary of the 15-day wellness period. Reference specific numbers. Use 'may suggest' framing. No medical claims.")
      var narrative: String
      @Guide(description: "Single strongest positive finding from the period, max 60 chars")
      var topWin: String
      @Guide(description: "Single most actionable improvement area, max 60 chars")
      var topConcern: String
  }

  @available(iOS 26, *)
  @Generable
  private struct _ReportSectionNarrative {
      @Guide(description: "Punchy headline for this section, max 50 chars, no medical claims")
      var headline: String
      @Guide(description: "1-2 sentence narrative for this section. Reference specific data points. Use 'may suggest' or 'appears linked' framing.")
      var narrative: String
  }

  @available(iOS 26, *)
  @Generable
  private struct _ReportActionPlan {
      @Guide(description: "3-5 specific actionable recommendations ranked by potential impact")
      var recommendations: [_ReportActionRecommendation]
  }

  @available(iOS 26, *)
  @Generable
  private struct _ReportActionRecommendation {
      @Guide(description: "Short action title, max 50 chars, e.g. 'Prioritize 7.5h sleep'")
      var title: String
      @Guide(description: "1-2 sentences explaining why this matters, referencing a specific data point from the report")
      var rationale: String
      @Guide(description: "Which wellness domain this targets: stress, nutrition, sleep, activity, hydration, caffeine, symptoms, supplements, fasting, or mood")
      var domain: String
  }
  #endif
  ```
  - Verify: All 4 schemas compile inside the `#if canImport(FoundationModels)` block. All are `private` and in the same file as the service.

### 3.2 — Implement Foundation Models path

- [ ] Add `@available(iOS 26, *)` private method `generateWithFM(for context: ReportContext, promptContext: ReportPromptContext) async -> ReportNarratives?`
- [ ] Guard: `guard case .available = SystemLanguageModel.default.availability else { return nil }`
- [ ] **FM Call 1 — Executive Summary**: Build prompt via `buildExecutiveSummaryPrompt(promptContext:)`. Create `LanguageModelSession()`. Call `session.respond(to: prompt, generating: _ReportExecutiveSummary.self)`. Map `result.content` to `ExecutiveSummaryNarrative`. Wrap in do/catch; on failure log warning and set to nil.
  - Verify: Matches pattern in `InsightEngine.swift` line 689
- [ ] **FM Calls 2-6 — Section Narratives**: Define priority list: `["stress", "nutrition", "sleep", "symptoms", "activity", "cross"]`. Determine which have data by checking `ReportContext`. Loop over top 5 that have data. For each:
  - Build section-specific prompt via `buildSectionNarrativePrompt(sectionName:, promptContext:)`
  - Create **fresh** `LanguageModelSession()` per call (do NOT reuse sessions)
  - Call `session.respond(to: prompt, generating: _ReportSectionNarrative.self)`
  - Map to `SectionNarrative` and store in `sectionNarratives[sectionName]`
  - On do/catch failure: log warning, skip (that section gets template fallback later)
  - Verify: Each call is independent; failure of one doesn't block others
- [ ] **FM Call 7 — Action Plan**: Build prompt via `buildActionPlanPrompt(promptContext:)`. Create `LanguageModelSession()`. Call `session.respond(to: prompt, generating: _ReportActionPlan.self)`. Map `result.content.recommendations` to `[ActionRecommendation]`. Wrap in do/catch.
  - Verify: Returns 3-5 recommendations
- [ ] Assemble `ReportNarratives` from FM results. For any nil executive summary or empty action plan, fall through to template in 3.3.

### 3.3 — Implement template fallback

- [ ] Add private method `generateTemplates(for context: ReportContext, promptContext: ReportPromptContext) -> ReportNarratives`
- [ ] Executive summary template: rule-based from stats. Pattern: "Over the past 15 days, [strongest metric direction]. [Top win]. [Top concern area could use attention]."
- [ ] Section narrative templates: per-section template strings. Pattern: "[Metric] averaged [X] over 15 days against a goal of [Y] ([percent]% of target)."
- [ ] Action plan templates: top 3-5 rules based on goal gaps (largest % below goal) and correlation strength (highest |r|)
  - Verify: Produces readable, data-specific narratives without FM

### 3.4 — Wire up main method

- [ ] In `generateNarratives()`:
  ```swift
  if #available(iOS 26, *) {
      if let fmResult = await generateWithFM(for: context, promptContext: promptContext) {
          return fmResult
      }
  }
  return generateTemplates(for: context, promptContext: promptContext)
  ```
  - Verify: Always returns a valid `ReportNarratives`; never crashes
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

---

## Phase 4: ViewModel

### 4.1 — Create `ReportViewModel.swift`

- [ ] Create new file `WellPlate/Features + UI/Home/ViewModels/ReportViewModel.swift`
- [ ] Define `@MainActor final class AI15DayReportViewModel: ObservableObject`
- [ ] Add `@Published var reportState: ReportState = .idle`
- [ ] Add private properties: `let dataBuilder = ReportDataBuilder()`, `let narrativeGenerator = ReportNarrativeGenerator()`, `var modelContext: ModelContext?`, `let healthService: HealthKitServiceProtocol`
- [ ] Add `init(healthService: HealthKitServiceProtocol = HealthKitService())`
- [ ] Add `func bindContext(_ context: ModelContext)` that stores context
- [ ] Implement `func generateReport() async`:
  1. Same-day cache check: if `reportState` is `.ready(let data)` and `Calendar.current.isDateInToday(data.generatedAt)`, return early
  2. Set `reportState = .generating(progress: 0)`
  3. Guard `let ctx = modelContext` else set `.error("No data context")` and return
  4. Call `dataBuilder.buildReportContext(modelContext: ctx, healthService: healthService)` → set `reportState = .generating(progress: 0.3)`
  5. Guard result non-nil else set `.error("Insufficient data")` and return
  6. Call `dataBuilder.buildPromptContext(from: context)` → set `reportState = .generating(progress: 0.4)`
  7. Call `narrativeGenerator.generateNarratives(for: context, promptContext: promptCtx)` → set `reportState = .generating(progress: 0.9)`
  8. Assemble `ReportData(context: context, narratives: narratives, generatedAt: .now)` → set `reportState = .generating(progress: 1.0)`
  9. Set `reportState = .ready(reportData)`
  - Verify: State transitions are correct; progress updates monotonically
- [ ] Implement `func clearAndRegenerate() async`: reset `reportState = .idle`, call `await generateReport()`
- [ ] Implement mock mode: at top of `generateReport()`, check `AppConfig.shared.mockMode`. If true, build hardcoded `ReportData` with:
  - 15 days of varied `WellnessDaySummary` mock data (some days with stress, some with food, some with symptoms, etc.)
  - 3 `FoodSymptomLink` entries (1 trigger, 1 protective)
  - 4 `CrossCorrelation` entries (sleep-stress, coffee-stress, steps-stress, protein-stress)
  - 1 `InterventionResult` (PMR, hasMeasurableData: true)
  - 1 `ExperimentSummary`
  - 5 `topFoods`, 3 `perSupplementAdherence`
  - Pre-written `ReportNarratives` (no FM calls)
  - Set `.ready(mockData)` and return
  - Verify: Mock data exercises all section visibility conditions
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
  - Add `#Preview` with sample data
  - Verify: Renders a horizontal row of stat capsules in Preview

- [ ] Implement `StressVolatilityChart`:
  - Input: `[(date: Date, min: Double, max: Double, avg: Double)]`
  - Chart: `RuleMark` vertical bars (min→max) + `PointMark` for avg
  - Add `#Preview`
  - Verify: Renders range bars in Preview

- [ ] Implement `FactorDecompositionChart`:
  - Input: `[(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)]`
  - Chart: Stacked horizontal `BarMark` with 4 colors (green/indigo/orange/purple)
  - Add `#Preview`
  - Verify: Renders stacked bars in Preview

- [ ] Implement `MealTimingHeatmap`:
  - Input: `[(dayLabel: String, bucket: String, count: Int)]`
  - Chart: `RectangleMark` grid with color intensity (0=clear, 1+=accent opacity)
  - Add `#Preview`
  - Verify: Renders 5-row heatmap in Preview

- [ ] Implement `BedtimeScatterChart`:
  - Input: `[(date: Date, bedtime: Date?, wakeTime: Date?)]`
  - Chart: Two `PointMark` series (bedtime=indigo, wake=orange)
  - Add `#Preview`
  - Verify: Renders scatter points in Preview

- [ ] Implement `VitalTrendChart`:
  - Input: `points: [DailyMetricSample]`, `metric: VitalMetric`
  - Chart: `LineMark` + `AreaMark` gradient + `RuleMark` benchmark bands per `VitalMetric`
  - Add `#Preview` for heartRate case
  - Verify: Renders for a sample `VitalMetric`

- [ ] Implement `SymptomTimelineChart`:
  - Input: `[(date: Date, maxSeverity: Int, count: Int, stressScore: Double?)]`
  - Chart: `PointMark` sized by count, colored by severity (green<4, yellow 4-6, red>6) + optional stress `LineMark`
  - Add `#Preview`
  - Verify: Renders bubble chart in Preview

- [ ] Implement `CorrelationMatrixChart`:
  - Input: `metrics: [String]` (max 8), `correlations: [(xIdx: Int, yIdx: Int, r: Double, isSignificant: Bool)]`
  - Chart: `RectangleMark` heatmap, blue(-1)→white(0)→red(+1), gray for non-significant
  - Labels: abbreviated max 6 chars
  - Add `#Preview` with 6x6 sample matrix
  - Verify: Renders grid with correct color scale

- [ ] Implement `AdherenceGauge`:
  - Input: `rate: Double` (0-1), `label: String`
  - Layout: Custom arc matching `MilestoneRingView` pattern (line 266 of InsightCharts.swift) + center text %
  - Add `#Preview`
  - Verify: Renders gauge ring

- [ ] Implement `FoodSensitivityRow`:
  - Input: `FoodSymptomLink`
  - Layout: food name (bold), ratio badge (red for `.potentialTrigger`, green for `.potentialProtective`), "appeared X/Y symptom days vs X/Y clear days"
  - Add `#Preview`
  - Verify: Renders row

- [ ] Implement `SymptomCategoryDonut`:
  - Input: `[(category: SymptomCategory, count: Int)]`
  - Chart: `SectorMark` with `SymptomCategory.color` per slice, `angularInset: 1.5` for donut gaps
  - Add `#Preview`
  - Verify: Renders donut chart (first `SectorMark` usage in project)

- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds

---

## Phase 6: Report Section Views

<!-- RESOLVED: L1 — Every section step now includes #Preview requirement -->
<!-- RESOLVED: M3 — Added intermediate build check after Step 6.4 -->

### 6.1 — `ReportHeaderSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ReportHeaderSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Layout: Title "Your 15-Day Wellness Report", date range subtitle (first day...last day formatted as "MMM d — MMM d, yyyy"), data quality badge ("Based on X days of data across Y domains")
- [ ] Add `#Preview` with mock `ReportData`
  - Verify: Renders header with correct date range

### 6.2 — `ExecutiveSummarySection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ExecutiveSummarySection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Layout: narrative text (`.r(.body, .regular)`) + topWin pill (green background) + topConcern pill (amber background)
- [ ] Add `#Preview`
  - Verify: Renders narrative and pills

### 6.3 — `StressDeepDiveSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.stressScore != nil }`
- [ ] Implement sub-views:
  - 2a: `TrendAreaChart` (existing, from InsightCharts.swift) for daily avg stress + `StatPillRow` (period avg, best day, worst day, trend)
  - 2b: `StressVolatilityChart` from `stressMin`/`stressMax` fields
  - 2c: `FactorDecompositionChart` — compute factor scores via `StressScoring.exerciseScore()`, `.sleepScore()`, `.dietScore()`, `.screenTimeScore()` for top 3 best/worst stress days
  - 2d: Best vs worst day — two side-by-side `VStack` cards with key metrics comparison
  - 2e: Intervention results (conditional: `!data.context.interventionResults.isEmpty`) — grouped bar comparison or text if `!hasMeasurableData`
  - 2f: Experiment results (conditional: `!data.context.experimentSummaries.isEmpty`) — hypothesis + `ComparisonBarChart`
- [ ] Include section narrative from `data.narratives.sectionNarratives["stress"]` if present
- [ ] Add `#Preview`
  - Verify: All 6 sub-views render with mock data

### 6.4 — `NutritionSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/NutritionSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.totalCalories != nil }`
- [ ] Implement sub-views:
  - 3a: Calorie trend — vertical `BarMark` daily calories + `RuleMark` goal line. Color: green (within 10% of goal), amber (10-20%), red (>20%)
  - 3b: `MacroGroupedBarChart` (existing) with 15-day averages vs goals
  - 3c: `MealTimingHeatmap` — bucket `mealTimestamps` into 5 time slots per day
  - 3d: Meal type distribution — horizontal `BarMark` from aggregated `mealTypes`
  - 3e: Eating triggers — horizontal `BarMark` from aggregated `eatingTriggers`
  - 3f: Top foods ranked list from `data.context.topFoods`
  - 3g: Food variety — unique count across all `foodNames` + benchmark label
- [ ] Include section narrative from `data.narratives.sectionNarratives["nutrition"]`
- [ ] Add `#Preview`
  - Verify: All 7 sub-views render with mock data

- [ ] **Intermediate build check**: Run main scheme build
  - Verify: Build succeeds (catches issues in the two most complex sections early)

### 6.5 — `SleepSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SleepSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.sleepHours != nil }`
- [ ] Implement: stacked `BarMark` (deep/REM/core with `SleepStage.color`), deep sleep ratio `LineMark` + 15-20% benchmark band, `BedtimeScatterChart` + std dev stat, sleep-stress scatter (conditional: >= 5 days with both)
- [ ] Add `#Preview`
  - Verify: All sub-views render

### 6.6 — `ActivitySection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ActivitySection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.steps != nil || $0.activeCalories != nil }`
- [ ] Implement: steps bars + 7-day rolling avg, energy area chart (reuse `TrendAreaChart`), exercise minutes with per-day goals via `UserGoals.workoutMinutes(for:)`, movement-stress scatter (conditional)
- [ ] Add `#Preview`
  - Verify: All sub-views render

### 6.7 — `VitalsSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/VitalsSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `!data.context.availableVitals.isEmpty`
- [ ] Loop over `data.context.availableVitals.sorted(by: { $0.rawValue < $1.rawValue })`: render `VitalTrendChart` per metric, extracting data points from `data.context.days` using the matching `var` field (e.g., `.heartRate` → `heartRateAvg`, `.hrv` → `hrvAvg`)
- [ ] Add `#Preview`
  - Verify: Only available vitals render; section hidden if `availableVitals` empty

### 6.8 — `HydrationCaffeineSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/HydrationCaffeineSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { ($0.waterGlasses ?? 0) > 0 || ($0.coffeeCups ?? 0) > 0 }`
- [ ] Implement: water bars + goal `RuleMark`, coffee bars + goal + coffee type distribution from `coffeeType` field, caffeine-stress `ComparisonBarChart` (conditional: >= 5 days)
- [ ] Add `#Preview`
  - Verify: All sub-views render

### 6.9 — `SymptomSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SymptomSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { !$0.symptomNames.isEmpty }`
- [ ] Implement: frequency horizontal bars (colored by `SymptomCategory`), `SymptomTimelineChart`, `SymptomCategoryDonut`, food sensitivity table using `FoodSensitivityRow` grouped by symptom name, symptom-stress `CorrelationScatterChart`
- [ ] Add disclaimer: "Correlations require more data to confirm — these patterns may change with additional tracking."
- [ ] Add `#Preview`
  - Verify: Food sensitivity table renders with trigger/protective classifications

### 6.10 — `SupplementSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/SupplementSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.supplementAdherence != nil }`
- [ ] Implement: `AdherenceGauge` for overall rate, per-supplement horizontal `BarMark` from `data.context.perSupplementAdherence` (green>=80%, amber 50-79%, red<50%), adherence-symptom Spearman r (conditional)
- [ ] Add `#Preview`
  - Verify: All sub-views render

### 6.11 — `FastingSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/FastingSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.fastingHours != nil }`
- [ ] Implement: `StatPillRow` (sessions, completion %, avg duration, longest), duration `BarMark` per session, fasting-stress `ComparisonBarChart` (conditional: >= 3 fasting + >= 3 non-fasting days)
- [ ] Add `#Preview`
  - Verify: Sub-views render

### 6.12 — `MoodSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/MoodSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `data.context.days.contains { $0.moodLabel != nil }`
- [ ] Implement: mood distribution horizontal `BarMark` (count per `MoodOption`), dual `LineMark` overlay for mood (inverted) and stress
- [ ] Add `#Preview`
  - Verify: Sub-views render

### 6.13 — `CrossDomainSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/CrossDomainSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Condition: `!data.context.crossCorrelations.isEmpty`
- [ ] Implement: `CorrelationMatrixChart` (max 8 metrics), top 3 strongest link cards each with `CorrelationScatterChart` (existing) + r-value badge + inline narrative
- [ ] Add "Correlation does not imply causation" disclaimer
- [ ] Add `#Preview`
  - Verify: Matrix renders; top 3 cards show scatter plots

### 6.14 — `ActionPlanSection.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/ReportSections/ActionPlanSection.swift`
- [ ] Input: `let data: ReportData`
- [ ] Always shown (no condition)
- [ ] Implement: 3-5 recommendation cards. Each: rounded rect with `WellnessDomain` accent tint (map `domain` string to `WellnessDomain` case), title (`.r(.headline, .bold)`), rationale (`.r(.subheadline, .regular)`), domain icon badge
- [ ] Add `#Preview`
  - Verify: Cards render with domain accent tints

- [ ] **Build check**: Run main scheme build after all section views
  - Verify: Build succeeds

---

## Phase 7: Main Report View & Navigation

### 7.1 — Create `AI15DayReportView.swift`

- [ ] Create `WellPlate/Features + UI/Home/Views/AI15DayReportView.swift`
- [ ] Add `@StateObject private var viewModel = AI15DayReportViewModel()`
- [ ] Add `@Environment(\.modelContext) private var modelContext`
- [ ] On `.onAppear`: `viewModel.bindContext(modelContext); Task { await viewModel.generateReport() }`
- [ ] Switch on `viewModel.reportState`:
  - `.idle` / `.generating(let progress)`: Centered `ProgressView()` + "Analyzing your wellness data..." (`.r(.subheadline, .regular)`) + progress % text (e.g., "42%")
  - `.ready(let data)`: `ScrollView > LazyVStack(spacing: 24)` with conditional sections:
    1. `ReportHeaderSection(data: data)` (always)
    2. `ExecutiveSummarySection(data: data)` (always)
    3. `StressDeepDiveSection(data: data)` (if stress data)
    4. `NutritionSection(data: data)` (if food data)
    5. `SleepSection(data: data)` (if sleep data)
    6. `ActivitySection(data: data)` (if activity data)
    7. `VitalsSection(data: data)` (if any vital)
    8. `HydrationCaffeineSection(data: data)` (if water/coffee)
    9. `SymptomSection(data: data)` (if symptoms)
    10. `SupplementSection(data: data)` (if adherence)
    11. `FastingSection(data: data)` (if fasting)
    12. `MoodSection(data: data)` (if mood)
    13. `CrossDomainSection(data: data)` (if correlations)
    14. `ActionPlanSection(data: data)` (always)
  - `.error(let msg)`: Error text + "Retry" button calling `Task { await viewModel.clearAndRegenerate() }`
- [ ] Add `insightEntrance(index:)` on each visible section (use enumerated counter for visible-only sections)
- [ ] Add footer: generated-at time + "Regenerate" `Button` (matching `InsightsHubFooter` pattern)
- [ ] Set `.navigationTitle("Wellness Report")` + `.navigationBarTitleDisplayMode(.inline)`
- [ ] Add `.padding(.horizontal, 16)` + `.padding(.vertical, 20)` on LazyVStack
  - Verify: View compiles; all 3 states render correctly

### 7.2 — Update `InsightsHubView.swift`

<!-- RESOLVED: M5 — Explicit entrance index math: report card at index 1, ForEach items at idx+2, footer at count+2 -->

- [ ] Open `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`
- [ ] Add `@State private var showFullReport = false`
- [ ] In `cardFeed` body, between `InsightsHubHeader` (index 0) and `ForEach`, insert a "Full Report" card:
  ```swift
  Button {
      HapticService.impact(.light)
      showFullReport = true
  } label: {
      HStack(spacing: 12) {
          Image(systemName: "sparkles")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(AppColors.brand)
          VStack(alignment: .leading, spacing: 4) {
              Text("15-Day Wellness Report")
                  .font(.r(.headline, .bold))
                  .foregroundStyle(.primary)
              Text("Comprehensive analysis across all your data")
                  .font(.r(.caption, .regular))
                  .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.tertiary)
      }
      .padding(18)
      .background(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(AppColors.brand.opacity(0.08))
      )
  }
  .buttonStyle(.plain)
  .insightEntrance(index: 1)
  ```
- [ ] Update ForEach entrance indices: change `insightEntrance(index: idx + 1)` → `insightEntrance(index: idx + 2)`
- [ ] Update footer entrance index: change `insightEntrance(index: engine.insightCards.count + 1)` → `insightEntrance(index: engine.insightCards.count + 2)`
- [ ] Add navigation destination (inside the same `NavigationStack` as existing destinations):
  ```swift
  .navigationDestination(isPresented: $showFullReport) {
      AI15DayReportView()
  }
  ```
  - Verify: Card appears in hub; tapping navigates to report; entrance animations stagger correctly

- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; navigation works

---

## Phase 8: Update InsightEngine

<!-- RESOLVED: H1 — Added explicit second await tuple for 6 new vital fetches -->

### 8.1 — Enrich `InsightEngine.buildWellnessContext()` with new fields

- [ ] Open `WellPlate/Core/Services/InsightEngine.swift`
- [ ] Add 6 new private safe-fetch methods (after existing ones at ~line 272), matching the existing pattern:
  ```swift
  private func fetchRestingHRSafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchRestingHeartRate(for: range)) ?? []
  }
  private func fetchHRVSafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchHRV(for: range)) ?? []
  }
  private func fetchSystolicSafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchBloodPressureSystolic(for: range)) ?? []
  }
  private func fetchDiastolicSafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchBloodPressureDiastolic(for: range)) ?? []
  }
  private func fetchRespiratorySafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchRespiratoryRate(for: range)) ?? []
  }
  private func fetchDaylightSafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchDaylight(for: range)) ?? []
  }
  ```
  - Verify: 6 new methods compile, each returns `[DailyMetricSample]`
- [ ] In the concurrent HealthKit fetch block (~line 153-158), add a **second set** of `async let` declarations:
  ```swift
  // Existing (unchanged):
  async let sleepFetch = fetchSleepSafely(range: interval)
  async let stepsFetch = fetchDailyStepsSafely(range: interval)
  async let energyFetch = fetchDailyEnergySafely(range: interval)
  async let heartRateFetch = fetchHeartRateSafely(range: interval)
  async let exerciseFetch = fetchExerciseMinutesSafely(range: interval)
  // NEW:
  async let restingHRFetch = fetchRestingHRSafely(range: interval)
  async let hrvFetch = fetchHRVSafely(range: interval)
  async let systolicFetch = fetchSystolicSafely(range: interval)
  async let diastolicFetch = fetchDiastolicSafely(range: interval)
  async let respiratoryFetch = fetchRespiratorySafely(range: interval)
  async let daylightFetch = fetchDaylightSafely(range: interval)
  ```
- [ ] Update the await to use **two separate tuples** (keep existing tuple, add new one):
  ```swift
  // Existing tuple (unchanged):
  let (sleepSummaries, stepsData, energyData, heartRateData, exerciseData) = await (sleepFetch, stepsFetch, energyFetch, heartRateFetch, exerciseFetch)
  // NEW tuple:
  let (restingHRData, hrvData, systolicData, diastolicData, respiratoryData, daylightData) = await (restingHRFetch, hrvFetch, systolicFetch, diastolicFetch, respiratoryFetch, daylightFetch)
  ```
  - Verify: Both tuples compile; all 11 HK fetches run concurrently
- [ ] In the per-day loop, change `days.append(WellnessDaySummary(...))` to create a mutable `var` and mutate:
  ```swift
  var summary = WellnessDaySummary(
      /* ALL existing arguments exactly as they are — do NOT change this call */
  )
  // Mutate new var fields:
  let triggerStrings = dayFood.flatMap { $0.eatingTriggers ?? [] }
  summary.eatingTriggers = Dictionary(triggerStrings.map { ($0, 1) }, uniquingKeysWith: +)
  let typeStrings = dayFood.compactMap { $0.mealType }
  summary.mealTypes = Dictionary(typeStrings.map { ($0, 1) }, uniquingKeysWith: +)
  summary.foodNames = dayFood.map(\.foodName)
  summary.coffeeType = wellness?.coffeeType
  summary.mealTimestamps = dayFood.map(\.createdAt)
  summary.stressMin = dayReadings.map(\.score).min()
  summary.stressMax = dayReadings.map(\.score).max()
  summary.stressReadingCount = dayReadings.count
  summary.restingHeartRateAvg = restingHRData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.hrvAvg = hrvData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.systolicBPAvg = systolicData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.diastolicBPAvg = diastolicData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.respiratoryRateAvg = respiratoryData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  summary.daylightMinutes = daylightData.first { calendar.isDate($0.date, inSameDayAs: dayStart) }?.value
  days.append(summary)
  ```
  - Verify: The `WellnessDaySummary(...)` memberwise init call has ZERO changes. Only the `var` mutations after it are new. Existing behavior is preserved.
- [ ] **Build check**: Run main scheme build
  - Verify: Build succeeds; existing InsightEngine hub cards still work correctly

---

## Post-Implementation

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: All 4 builds succeed with 0 errors
- [ ] Test mock mode: Set `AppConfig.shared.mockMode = true`, navigate Home → InsightsHub → "View 15-Day Report"
  - Verify: All 13+ sections render with mock data; scroll is smooth; entrance animations stagger
- [ ] Test section visibility: Modify mock data to remove food logs (clear `totalCalories`, `foodNames`, etc.)
  - Verify: Nutrition section disappears; other sections unaffected
- [ ] Test zero-tolerance: Modify mock data to set `availableVitals = []`
  - Verify: Vitals section hidden entirely; no vital references in cross-domain correlations
- [ ] Test regenerate: Tap "Regenerate" button
  - Verify: Progress view appears, report regenerates, new timestamp shown
- [ ] Git commit with descriptive message
