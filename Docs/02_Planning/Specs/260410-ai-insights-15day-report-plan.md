# Implementation Plan: 15-Day AI Insights Report

**Date**: 2026-04-10
**Source**: `Docs/01_Brainstorming/260410-ai-insights-15day-report-brainstorm.md`
**Status**: Ready for Audit

---

## Overview

Build a comprehensive 15-day wellness report as a single scrollable view inside the existing `InsightsHubView`. The report uses every data source in the app — food logs, stress readings, HealthKit vitals, sleep, activity, symptoms, supplements, fasting, mood, and interventions — to produce 13 conditional sections with charts, goal comparisons, cross-domain correlations, a detailed food-symptom sensitivity analysis, and LLM-generated narratives via Foundation Models. Sections with zero data are hidden entirely (zero-tolerance rule for HealthKit metrics).

---

## Requirements

- Single scrollable `AI15DayReportView` accessible from `InsightsHubView`
- 15-day hard cap lookback window; no minimum data requirement
- Foundation Models (on-device, iOS 26+) for narrative generation; template fallback for < 26
- Zero-tolerance: any HealthKit metric with 0 samples in the window is excluded from the entire report (sections, correlations, LLM prompts)
- Goal comparison on every section where `UserGoals` defines a target
- Detailed food-symptom correlation section (specific foods, not just macros)
- Eating triggers: surface-level only (frequency counts)
- No journal entries, no historical period comparison
- Intervention effectiveness based on stress readings (ignore nil Watch biometric fields)

---

## Architecture Changes

### New Files

| # | File Path | Purpose |
|---|---|---|
| 1 | `WellPlate/Features + UI/Home/Models/ReportModels.swift` | `ReportContext`, `ReportSectionData`, `FoodSymptomLink`, `CrossCorrelation`, `InterventionResult`, `ExperimentSummary`, `ReportPromptContext`, FM `@Generable` schemas |
| 2 | `WellPlate/Core/Services/ReportDataBuilder.swift` | Fetches all SwiftData + HealthKit data, builds `ReportContext` with per-day summaries, computes food-symptom links, cross-domain correlations, intervention deltas |
| 3 | `WellPlate/Core/Services/ReportNarrativeGenerator.swift` | Foundation Models structured output calls (3 calls: executive summary, section narratives, action plan) + template fallback |
| 4 | `WellPlate/Features + UI/Home/ViewModels/ReportViewModel.swift` | `AI15DayReportViewModel` — orchestrates data build + narrative gen, publishes `ReportState` |
| 5 | `WellPlate/Features + UI/Home/Views/AI15DayReportView.swift` | Main scrollable view — routes to section sub-views based on data availability |
| 6 | `WellPlate/Features + UI/Home/Views/ReportSections/ReportHeaderSection.swift` | Title, date range, data quality badge |
| 7 | `WellPlate/Features + UI/Home/Views/ReportSections/ExecutiveSummarySection.swift` | LLM-generated 3-4 sentence narrative + top win / top concern pills |
| 8 | `WellPlate/Features + UI/Home/Views/ReportSections/StressDeepDiveSection.swift` | Stress trend, volatility, factor decomposition, best/worst day, intervention, experiment |
| 9 | `WellPlate/Features + UI/Home/Views/ReportSections/NutritionSection.swift` | Calorie trend, macro radar, meal timing heatmap, meal type dist, triggers, top foods, variety |
| 10 | `WellPlate/Features + UI/Home/Views/ReportSections/SleepSection.swift` | Duration stacked bars, deep sleep ratio, bedtime consistency, sleep-stress link |
| 11 | `WellPlate/Features + UI/Home/Views/ReportSections/ActivitySection.swift` | Steps, energy, exercise minutes, movement-stress link |
| 12 | `WellPlate/Features + UI/Home/Views/ReportSections/VitalsSection.swift` | Conditional vital charts (HR, resting HR, HRV, BP, respiratory rate) |
| 13 | `WellPlate/Features + UI/Home/Views/ReportSections/HydrationCaffeineSection.swift` | Water/coffee trends, caffeine-stress link |
| 14 | `WellPlate/Features + UI/Home/Views/ReportSections/SymptomSection.swift` | Frequency, severity timeline, category breakdown, food sensitivity table, symptom-stress |
| 15 | `WellPlate/Features + UI/Home/Views/ReportSections/SupplementSection.swift` | Overall adherence, per-supplement breakdown, adherence-symptom link |
| 16 | `WellPlate/Features + UI/Home/Views/ReportSections/FastingSection.swift` | Summary stats, fasting-stress link |
| 17 | `WellPlate/Features + UI/Home/Views/ReportSections/MoodSection.swift` | Distribution, mood-stress alignment |
| 18 | `WellPlate/Features + UI/Home/Views/ReportSections/CrossDomainSection.swift` | Correlation matrix heatmap, top 3 strongest links |
| 19 | `WellPlate/Features + UI/Home/Views/ReportSections/ActionPlanSection.swift` | LLM-generated 3-5 recommendations |
| 20 | `WellPlate/Features + UI/Home/Components/ReportCharts.swift` | New chart components: `StressVolatilityChart`, `FactorDecompositionChart`, `MealTimingHeatmap`, `BedtimeScatterChart`, `VitalTrendChart`, `SymptomTimelineChart`, `CorrelationMatrixChart`, `AdherenceGauge`, `StatPillRow` |

### Modified Files

| File | Change |
|---|---|
| `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` | Add navigation to `AI15DayReportView` (button in header or a "Full Report" card in the feed) |
| `WellPlate/Features + UI/Home/Models/InsightModels.swift` | Extend `WellnessDaySummary` with: `eatingTriggers: [String: Int]`, `mealTypes: [String: Int]`, `foodNames: [String]`, `interventionSessions: [(type: String, stressDelta: Double?)]`; extend `WellnessDomain` with `.supplements` case |
| `WellPlate/Core/Services/InsightEngine.swift` | Update `buildWellnessContext()` to populate the new `WellnessDaySummary` fields (eating triggers, meal types, food names, interventions) so both the hub cards and the report share the same data path |

---

## Implementation Steps

### Phase 1: Data Models & Types (no UI, no service logic)

**1.1 Create `ReportModels.swift`** (File: `WellPlate/Features + UI/Home/Models/ReportModels.swift`)
- Action: Define all value types the report needs:
  - `ReportContext` — wraps `[ReportDaySummary]`, `UserGoalsSnapshot`, `Set<VitalMetric>` (available vitals), `[FoodSymptomLink]`, `[CrossCorrelation]`, `[InterventionResult]`, `[ExperimentSummary]`, `dataQualityNote: String`
  - `ReportDaySummary` — extends `WellnessDaySummary` concept but includes all report-specific per-day fields: stress (avg, min, max, readingCount), sleep (hours, deep, REM, bedtime, wakeTime), activity (steps, energy, exerciseMin), nutrition (calories, protein, carbs, fat, fiber, mealCount), food detail (mealTypes dict, eatingTriggers dict, foodNames array), hydration (waterGlasses, coffeeCups, coffeeType), mood (raw Int?), symptoms (names, maxSeverity), fasting (hours, completed), supplements (adherence rate), intervention sessions list
  - `FoodSymptomLink` — symptomName, foodName, symptomDayCount, clearDayCount, symptomDayAppearances, clearDayAppearances, ratio, classification enum (.potentialTrigger, .potentialProtective, .neutral)
  - `CrossCorrelation` — xName, yName, xDomain, yDomain, spearmanR, ciLow, ciHigh, pairedDays, isSignificant, scatterPoints
  - `InterventionResult` — resetType (String), sessionCount, avgPreStress, avgPostStress, avgDelta
  - `ExperimentSummary` — name, hypothesis, interventionType, baselineAvg, experimentAvg, delta, ciLow, ciHigh, isComplete
  - `ReportPromptContext` — pre-aggregated text summary for LLM prompts (computed from `ReportContext`)
  - `ReportState` enum — `.idle`, `.generating(progress: Double)`, `.ready(ReportData)`, `.error(String)`
  - `ReportData` — holds all section data + generated narratives, the final output consumed by the view
- Why: Isolates all types in one file; views and services both import from here
- Dependencies: None
- Risk: Low

**1.2 Define Foundation Models `@Generable` schemas** (File: same `ReportModels.swift`)
- Action: Add `@Generable` structs guarded by `#if canImport(FoundationModels)` + `@available(iOS 26, *)`:
  - `_ReportExecutiveSummary` — narrative (String), topWin (String), topConcern (String)
  - `_ReportSectionNarrative` — sectionName (String), headline (String), narrative (String)
  - `_ReportSectionNarratives` — sections: `[_ReportSectionNarrative]`
  - `_ReportActionPlan` — recommendations: `[_ActionRecommendation]`
  - `_ActionRecommendation` — title (String), rationale (String), domain (String)
- Why: Foundation Models requires `@Generable` types to be concrete, non-generic, and file-local is fine
- Dependencies: 1.1
- Risk: Low

**1.3 Extend `InsightModels.swift`** (File: `WellPlate/Features + UI/Home/Models/InsightModels.swift`)
- Action:
  - Add new fields to `WellnessDaySummary`: `eatingTriggers: [String: Int]` (default `[:]`), `mealTypes: [String: Int]` (default `[:]`), `foodNames: [String]` (default `[]`), `interventionSessions: [(type: String, stressDelta: Double?)]` (default `[]`)
  - Add `case supplements` to `WellnessDomain` with label "Supplements", icon "pill.fill", accentColor
- Why: Shared type used by both `InsightEngine` (hub cards) and `ReportDataBuilder` (full report)
- Dependencies: None
- Risk: Low — additive only, all new fields have defaults so existing callers are unaffected

---

### Phase 2: Data Builder Service

**2.1 Create `ReportDataBuilder.swift`** (File: `WellPlate/Core/Services/ReportDataBuilder.swift`)
- Action: Create `@MainActor final class ReportDataBuilder` with:
  - `func buildReportContext(modelContext: ModelContext, healthService: HealthKitServiceProtocol) async -> ReportContext`
  - Internal structure:
    1. **Date window**: `Calendar.current.startOfDay(for: .now)` minus 14 days through today = 15-day window
    2. **SwiftData fetches** (all with date-predicated `FetchDescriptor`):
       - `StressReading` where `timestamp >= windowStart`
       - `WellnessDayLog` where `day >= windowStart`
       - `FoodLogEntry` where `day >= windowStart`
       - `SymptomEntry` where `day >= windowStart`
       - `AdherenceLog` where `day >= windowStart`
       - `SupplementEntry` where `isActive == true`
       - `FastingSession` where `startedAt >= windowStart` (filter `!isActive` after fetch)
       - `InterventionSession` where `startedAt >= windowStart` (filter `completed` after fetch)
       - `StressExperiment` where `startDate <= now` (filter for overlap with window)
       - `UserGoals.current(in:)` → `UserGoalsSnapshot`
    3. **HealthKit fetches** (all concurrent via `async let`):
       - Steps, activeEnergy, exerciseMinutes, heartRate, restingHeartRate, HRV, BPsystolic, BPdiastolic, respiratoryRate, sleepSummaries, daylight
       - Each wrapped in try/catch returning empty array on failure
    4. **Zero-tolerance filter**: Build `Set<VitalMetric>` of available vitals by checking each HK result `.isEmpty`
    5. **Per-day summary loop**: For each day in window, aggregate all data into a `ReportDaySummary`
    6. **Food-symptom correlation** (call `computeFoodSymptomLinks()`)
    7. **Cross-domain correlations** (call `computeCrossCorrelations()`)
    8. **Intervention results** (call `computeInterventionResults()`)
    9. **Experiment summaries** (call `buildExperimentSummaries()`)
    10. **Assemble `ReportContext`**
- Why: Separates data fetching/aggregation from narrative generation and view logic
- Dependencies: 1.1, 1.3
- Risk: Medium — many data sources, but each fetch is straightforward and follows existing patterns in `InsightEngine.buildWellnessContext()`

**2.2 Implement `computeFoodSymptomLinks()`** (File: same `ReportDataBuilder.swift`)
- Action: Private method that:
  1. Groups `SymptomEntry` by name, filters to symptoms with >= 3 occurrences
  2. For each qualifying symptom:
     - Identify symptom days (dates with that symptom)
     - Identify clear days (dates without that symptom that have food logs)
     - For each unique food logged across all days:
       - Count appearances on symptom days (same day OR day before for delayed reactions)
       - Count appearances on clear days
       - Compute frequency ratio: `(symptomDayAppearances / symptomDayCount) / (clearDayAppearances / clearDayCount)`
       - Guard against division by zero (skip if clearDayCount == 0 or clearDayAppearances == 0)
       - Classify: ratio > 2.0 = `.potentialTrigger`, ratio < 0.5 = `.potentialProtective`, else `.neutral`
     - Only return `.potentialTrigger` and `.potentialProtective` links (skip neutrals)
  3. Also compute macro-level Spearman correlations using `CorrelationMath.spearmanR()` for each symptom vs calories, protein, fiber, fat, caffeine, water, stress, sleep — reuse `SymptomCorrelationEngine` pattern but inline (no need to instantiate the full engine)
- Why: Core differentiator of this report — specific food tracking, not just macro-level
- Dependencies: 2.1, `CorrelationMath` (existing)
- Risk: Medium — edge cases around days with no food logs, symptoms that span midnight, foods with very low frequency. Mitigate by requiring food to appear >= 2 times total to be considered.

**2.3 Implement `computeCrossCorrelations()`** (File: same `ReportDataBuilder.swift`)
- Action: Private method that:
  1. Defines metric pairs (same list as brainstorm Section 12), each with extract closures on `ReportDaySummary`
  2. Filters pairs based on `availableVitals` — skip any pair involving an excluded metric
  3. For each pair: extract paired values for days where both metrics exist, require >= 5 pairs
  4. Compute `CorrelationMath.spearmanR()` and `CorrelationMath.bootstrapCI()` on `Task.detached`
  5. Filter to `|r| >= 0.3` AND CI doesn't span zero
  6. Build `CrossCorrelation` objects with scatter points
  7. Sort by `|r|` descending
- Why: Powers Section 12 (correlation matrix + top 3 links)
- Dependencies: 2.1, `CorrelationMath` (existing)
- Risk: Low — pattern is identical to `InsightEngine.detectCorrelations()`

**2.4 Implement `computeInterventionResults()`** (File: same `ReportDataBuilder.swift`)
- Action: Private method that:
  1. Groups completed `InterventionSession` by `resetType`
  2. For each session: find the `StressReading` closest to (and before) `startedAt` within 2 hours, and the `StressReading` closest to (and after) `startedAt + durationSeconds` within 2 hours
  3. If both found, compute delta = post - pre
  4. Aggregate per reset type: count, avg pre, avg post, avg delta
  5. Return `[InterventionResult]`
- Why: Shows whether PMR/sigh sessions actually reduce stress
- Dependencies: 2.1
- Risk: Low — straightforward time-window matching

**2.5 Implement `buildExperimentSummaries()`** (File: same `ReportDataBuilder.swift`)
- Action: Private method that:
  1. Filters `StressExperiment` to those overlapping the 15-day window
  2. For each: read cached baseline/experiment/delta/CI fields
  3. Return `[ExperimentSummary]`
- Why: Surfaces active/completed stress experiments in the report
- Dependencies: 2.1
- Risk: Low

**2.6 Implement `buildPromptContext()`** (File: same `ReportDataBuilder.swift`)
- Action: Method that takes a `ReportContext` and produces a `ReportPromptContext` (pre-aggregated text string for LLM):
  - Period summary: date range, days with data, domains active
  - Per-domain summary stats: avg, range, goal comparison, trend direction
  - Top correlations (name + r-value)
  - Top food-symptom links
  - Intervention results summary
  - Experiment results summary
  - Format as compact multi-line text (~500-800 words max)
- Why: Foundation Models has limited context; raw data is too large
- Dependencies: 2.1-2.5
- Risk: Low

---

### Phase 3: Narrative Generation Service

**3.1 Create `ReportNarrativeGenerator.swift`** (File: `WellPlate/Core/Services/ReportNarrativeGenerator.swift`)
- Action: Create `@MainActor final class ReportNarrativeGenerator` with:
  - `func generateNarratives(for context: ReportContext, promptContext: ReportPromptContext) async -> ReportNarratives`
  - `ReportNarratives` struct containing:
    - `executiveSummary: (narrative: String, topWin: String, topConcern: String)`
    - `sectionNarratives: [String: (headline: String, narrative: String)]` — keyed by section name
    - `actionPlan: [(title: String, rationale: String, domain: String)]`
  - Foundation Models path (iOS 26+):
    - Call 1: Executive Summary — feed full prompt context, generate `_ReportExecutiveSummary`
    - Call 2: Section Narratives — feed prompt context + list of active sections, generate `_ReportSectionNarratives`
    - Call 3: Action Plan — feed prompt context + top findings, generate `_ReportActionPlan`
    - Each call wrapped in do/catch; on failure, fall through to template
  - Template fallback path (iOS < 26 or FM failure):
    - Executive summary: rule-based narrative from stats
    - Section narratives: per-section templates using the same pattern as `InsightEngine.templateNarrative()`
    - Action plan: top 3-5 rules based on goal gaps and correlation strength
- Why: Isolates LLM logic from data building and view rendering; makes template fallback clean
- Dependencies: 1.2 (Generable schemas), 2.6 (prompt context)
- Risk: Medium — Foundation Models can fail or produce poor output. Template fallback must be complete.

**3.2 Build LLM prompt strings** (File: same `ReportNarrativeGenerator.swift`)
- Action: Private methods for each of the 3 prompts:
  - `buildExecutiveSummaryPrompt(promptContext:)` — instructs: "Write a 3-4 sentence executive summary of this person's 15-day wellness data. Reference specific numbers. Use 'may suggest' framing. No medical claims."
  - `buildSectionNarrativesPrompt(promptContext:, activeSections:)` — instructs: "For each of these sections, write a punchy headline (max 50 chars) and a 1-2 sentence narrative."
  - `buildActionPlanPrompt(promptContext:)` — instructs: "Generate 3-5 specific actionable recommendations ranked by impact. Each must reference a data point. Use 'consider' framing."
- Why: Prompt quality is critical for narrative quality
- Dependencies: 3.1
- Risk: Low

---

### Phase 4: ViewModel

**4.1 Create `ReportViewModel.swift`** (File: `WellPlate/Features + UI/Home/ViewModels/ReportViewModel.swift`)
- Action: Create `@MainActor final class AI15DayReportViewModel: ObservableObject` with:
  - Published state: `reportState: ReportState`, `generationProgress: Double`
  - Dependencies: `ReportDataBuilder`, `ReportNarrativeGenerator`, `ModelContext?`, `HealthKitServiceProtocol`
  - `bindContext(_ context: ModelContext)` — same pattern as `InsightEngine`
  - `generateReport() async`:
    1. Set `reportState = .generating(progress: 0)`
    2. Build `ReportContext` via `ReportDataBuilder` → progress 0.4
    3. Build `ReportPromptContext` → progress 0.5
    4. Generate narratives via `ReportNarrativeGenerator` → progress 0.9
    5. Assemble `ReportData` (combine context + narratives) → progress 1.0
    6. Set `reportState = .ready(reportData)`
    7. On error: set `reportState = .error(message)`
  - Same-day caching: if `reportState` is already `.ready` and generated today, skip regeneration
  - `clearAndRegenerate() async` — clears cache, re-runs
- Why: Standard MVVM — view observes state, VM orchestrates async work
- Dependencies: 2.1-2.6, 3.1
- Risk: Low

---

### Phase 5: Chart Components

**5.1 Create `ReportCharts.swift`** (File: `WellPlate/Features + UI/Home/Components/ReportCharts.swift`)
- Action: Build new chart components not already in `InsightCharts.swift`:

  **`StatPillRow`** — horizontal row of stat capsules (e.g., "Avg: 52", "Best: 28", "Worst: 78")
  - Input: `[(label: String, value: String, color: Color?)]`
  - Layout: `HStack` of capsule-shaped pills

  **`StressVolatilityChart`** — daily min/max range bars
  - Input: `[(date: Date, min: Double, max: Double, avg: Double)]`
  - Chart: `RuleMark` for each day (min to max), `PointMark` for avg
  - Color: Range bar in `.secondary.opacity(0.3)`, avg point in accent

  **`FactorDecompositionChart`** — stacked horizontal bars for high vs low stress days
  - Input: `[(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)]`
  - Chart: Stacked `BarMark` with 4 colors per factor
  - Use: Section 2c

  **`MealTimingHeatmap`** — grid of day x time-bucket
  - Input: `[(dayIndex: Int, bucket: String, count: Int)]`
  - Chart: `RectangleMark` with color intensity mapped to count
  - Buckets: "6-10am", "10am-2pm", "2-6pm", "6-10pm", "10pm+"

  **`BedtimeScatterChart`** — bedtime/waketime consistency
  - Input: `[(date: Date, bedtime: Date?, wakeTime: Date?)]`
  - Chart: Two series of `PointMark` — blue for bedtime, orange for wake
  - Y-axis: time of day (formatted as HH:mm)

  **`VitalTrendChart`** — generic line chart for any vital metric
  - Input: `points: [DailyMetricSample]`, `metric: VitalMetric`
  - Chart: `LineMark` with accent color from `VitalMetric.accentColor`
  - Adds benchmark bands using `VitalMetric.normalRange` parsing or hardcoded ranges

  **`SymptomTimelineChart`** — bubble chart of symptom severity over time
  - Input: `[(date: Date, maxSeverity: Int, count: Int, stressScore: Double?)]`
  - Chart: `PointMark` sized by count, colored by severity; optional `LineMark` overlay for stress

  **`CorrelationMatrixChart`** — heatmap grid of r-values
  - Input: `[(xLabel: String, yLabel: String, r: Double, isSignificant: Bool)]`
  - Chart: `RectangleMark` grid, color scale blue (negative) → white (zero) → red (positive)
  - Grey out non-significant cells

  **`AdherenceGauge`** — circular gauge for supplement adherence
  - Input: `rate: Double` (0-1), `label: String`
  - Visual: `Gauge` or custom arc similar to `MilestoneRingView`

  **`FoodSensitivityRow`** — list row for a food-symptom link
  - Input: `FoodSymptomLink`
  - Layout: food name, ratio badge, "appeared X/Y symptom days vs X/Y clear days"

- Why: Each section needs chart types not in the existing `InsightCharts.swift`
- Dependencies: None (pure SwiftUI views)
- Risk: Medium — many chart types, but each is a self-contained SwiftUI view using standard Swift Charts APIs. The heatmap and correlation matrix are the most complex.

---

### Phase 6: Report Section Views

Each section is a self-contained `View` that takes a slice of `ReportData` and renders conditionally.

**6.1 `ReportHeaderSection.swift`**
- Input: date range, data quality info (days with data, domain count)
- Layout: Title "Your 15-Day Wellness Report", subtitle date range, data quality badge
- Animation: `insightEntrance(index: 0)`
- Dependencies: None
- Risk: Low

**6.2 `ExecutiveSummarySection.swift`**
- Input: narrative string, topWin string, topConcern string
- Layout: Large narrative text, two highlight pills (win in green, concern in amber)
- Conditional: Always shown (even if narrative is template-generated)
- Dependencies: 3.1 (narrative output)
- Risk: Low

**6.3 `StressDeepDiveSection.swift`**
- Input: `ReportContext` stress data slice
- Condition: `reportContext.days.contains { $0.stressScore != nil }`
- Sub-views:
  - 2a: `TrendAreaChart` (reuse existing) for stress trend + stat pills
  - 2b: `StressVolatilityChart` (new) for daily min/max
  - 2c: `FactorDecompositionChart` (new) — compute factor scores per day using `StressScoring.exerciseScore()`, `.sleepScore()`, `.dietScore()`, `.screenTimeScore()`; pick top 3 best + top 3 worst days
  - 2d: Best vs worst day — two side-by-side cards with key metrics
  - 2e: `InterventionResult` section (conditional on `!interventionResults.isEmpty`)
  - 2f: `ExperimentSummary` section (conditional on `!experimentSummaries.isEmpty`)
- LLM narrative: section headline + narrative from `ReportNarratives.sectionNarratives["stress"]`
- Dependencies: 5.1 (charts), 2.4, 2.5
- Risk: Medium — most complex section with 6 sub-views

**6.4 `NutritionSection.swift`**
- Input: food log data from `ReportContext`, goals
- Condition: `reportContext.days.contains { $0.totalCalories != nil }`
- Sub-views:
  - 3a: Calorie trend — `BarMark` daily calories, `RuleMark` goal line, stat pills. Bar color: green (within 10% of goal), amber (10-20%), red (>20%)
  - 3b: Macro radar — reuse `MacroGroupedBarChart` (existing) with 15-day averages vs goals
  - 3c: `MealTimingHeatmap` (new) — bucket `FoodLogEntry.createdAt` into 5 time slots per day
  - 3d: Meal type distribution — horizontal `BarMark` of breakfast/lunch/dinner/snack/untagged counts
  - 3e: Eating triggers — horizontal `BarMark` of trigger frequency from `eatingTriggers` aggregation
  - 3f: Top foods — ranked list view (top 10 by count, with calories)
  - 3g: Food variety score — count unique foodNames, show benchmark label
- Dependencies: 5.1 (heatmap)
- Risk: Medium — many sub-charts but each is simple

**6.5 `SleepSection.swift`**
- Input: sleep summaries from `ReportContext`, goals
- Condition: `reportContext.days.contains { $0.sleepHours != nil }`
- Sub-views:
  - 4a: Stacked `BarMark` (deep/REM/core) per night + `RuleMark` goal line + stat pills
  - 4b: Deep sleep ratio `LineMark` + benchmark band (15-20%)
  - 4c: `BedtimeScatterChart` (new) + std deviation stat
  - 4d: Sleep-stress scatter (conditional: >= 5 overlapping days) — reuse `CorrelationScatterChart` with sleep hours vs next-day stress
- Dependencies: 5.1 (bedtime chart)
- Risk: Low

**6.6 `ActivitySection.swift`**
- Input: steps, energy, exercise data from `ReportContext`, goals
- Condition: `reportContext.days.contains { $0.steps != nil || $0.activeCalories != nil }`
- Sub-views:
  - 5a: Steps `BarMark` + goal `RuleMark` + 7-day rolling average `LineMark` + stat pills
  - 5b: Active energy `AreaMark` (reuse `TrendAreaChart`)
  - 5c: Exercise minutes `BarMark` with per-day goal from `UserGoals.workoutMinutes(for:)` — need to map weekday index for each day
  - 5d: Movement-stress scatter (conditional) — reuse `CorrelationScatterChart`
- Dependencies: None (reuses existing charts)
- Risk: Low

**6.7 `VitalsSection.swift`**
- Input: `ReportContext.availableVitals`, HK data arrays
- Condition: `!reportContext.availableVitals.isEmpty`
- Sub-views: For each `VitalMetric` in `availableVitals`, render a `VitalTrendChart` (new) with appropriate benchmark bands. Each sub-chart is individually conditional.
- Section header: "Vitals"
- Dependencies: 5.1 (VitalTrendChart)
- Risk: Low — same chart template parameterized per metric

**6.8 `HydrationCaffeineSection.swift`**
- Input: water/coffee data from `ReportContext`, goals
- Condition: `reportContext.days.contains { ($0.waterGlasses ?? 0) > 0 || ($0.coffeeCups ?? 0) > 0 }`
- Sub-views:
  - 7a: Water `BarMark` + goal line + stat pills
  - 7b: Coffee `BarMark` + goal line + coffee type distribution (small horizontal bar or pill list)
  - 7c: Caffeine-stress link (conditional: >= 5 days with both) — compare avg stress on low-coffee vs high-coffee days using `ComparisonBarChart` (existing)
- Dependencies: None
- Risk: Low

**6.9 `SymptomSection.swift`**
- Input: symptom entries, food-symptom links, stress data from `ReportContext`
- Condition: `!reportContext.foodSymptomCorrelations.isEmpty || reportContext.days.contains { !$0.symptomNames.isEmpty }`
- Sub-views:
  - 8a: Symptom frequency horizontal `BarMark`, colored by category
  - 8b: `SymptomTimelineChart` (new) — severity bubbles with optional stress overlay
  - 8c: Category breakdown — donut chart (`SectorMark` on iOS 17+) or horizontal bar
  - 8d: **Food sensitivity table** — for each symptom, list `FoodSymptomLink` entries using `FoodSensitivityRow` component. Group by symptom. Show trigger ratios. Include macro-level Spearman correlations below.
  - 8e: Symptom-stress scatter — reuse `CorrelationScatterChart`
- Dependencies: 5.1, 2.2
- Risk: Medium — the food sensitivity table is the most novel UI component

**6.10 `SupplementSection.swift`**
- Input: adherence data from `ReportContext`
- Condition: adherence logs exist
- Sub-views:
  - 9a: `AdherenceGauge` (new) — overall % ring
  - 9b: Per-supplement horizontal `BarMark` sorted worst to best, colored by adherence tier
  - 9c: Adherence-symptom link (conditional: >= 5 days with both) — Spearman r
- Dependencies: 5.1
- Risk: Low

**6.11 `FastingSection.swift`**
- Input: fasting sessions from `ReportContext`
- Condition: at least 1 completed session
- Sub-views:
  - 10a: Summary stat pills + duration `BarMark` per session
  - 10b: Fasting-stress comparison bars (conditional: >= 3 fasting + >= 3 non-fasting days) — reuse `ComparisonBarChart`
- Dependencies: None
- Risk: Low

**6.12 `MoodSection.swift`**
- Input: mood data from `ReportContext`
- Condition: `reportContext.days.contains { $0.moodLabel != nil }`
- Sub-views:
  - 11a: Horizontal `BarMark` of mood distribution (MoodOption counts)
  - 11b: Dual-line overlay — mood (inverted) and stress score — reuse `TrendAreaChart` pattern with two series
- Dependencies: None
- Risk: Low

**6.13 `CrossDomainSection.swift`**
- Input: `[CrossCorrelation]` from `ReportContext`
- Condition: `!reportContext.crossDomainCorrelations.isEmpty`
- Sub-views:
  - 12a: `CorrelationMatrixChart` (new) — heatmap grid
  - 12b: Top 3 cards — each with `CorrelationScatterChart` (existing), r-value badge, 1-sentence narrative
- Dependencies: 5.1 (matrix chart), 3.1 (narrative for top 3)
- Risk: Medium — matrix chart is the most complex new chart component

**6.14 `ActionPlanSection.swift`**
- Input: `ReportNarratives.actionPlan`
- Condition: Always shown
- Layout: 3-5 recommendation cards, each with title, rationale, domain icon+color
- Style: Each card is a `VStack` in a rounded rect with domain accent tint
- Dependencies: 3.1
- Risk: Low

---

### Phase 7: Main Report View & Navigation

**7.1 Create `AI15DayReportView.swift`** (File: `WellPlate/Features + UI/Home/Views/AI15DayReportView.swift`)
- Action: Main scrollable view that:
  - Takes `@StateObject var viewModel: AI15DayReportViewModel`
  - On appear: `viewModel.bindContext(modelContext); Task { await viewModel.generateReport() }`
  - Switch on `viewModel.reportState`:
    - `.idle` / `.generating`: Show progress view with `generationProgress` bar + shimmer placeholders
    - `.ready(let data)`: Render `ScrollView > LazyVStack` of sections, each with `insightEntrance(index:)` animation
    - `.error`: Error state with retry button
  - Section rendering: conditionally include each section based on data availability
  - Pass the relevant slice of `ReportData` to each section view
  - Footer: "Generated at HH:mm" + "Regenerate" button (same pattern as `InsightsHubFooter`)
- Why: Single view file orchestrates the scroll layout; delegates to section views
- Dependencies: 4.1, 6.1-6.14
- Risk: Low

**7.2 Update `InsightsHubView.swift`** (File: `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`)
- Action: Add a "Full Report" navigation entry point:
  - Add `@State private var showFullReport = false`
  - In the `cardFeed`, add a prominent card/button after the header (or as the last item before footer) that says "View 15-Day Report"
  - Add `.navigationDestination(isPresented: $showFullReport) { AI15DayReportView() }`
  - Pass the `insightEngine.healthService` reference to the report VM, or instantiate the report VM with its own service
- Why: User navigates: Home → InsightsHub → Full Report
- Dependencies: 7.1
- Risk: Low

---

### Phase 8: Update InsightEngine for New Fields

**8.1 Update `InsightEngine.buildWellnessContext()`** (File: `WellPlate/Core/Services/InsightEngine.swift`)
- Action: In the per-day loop, populate the new `WellnessDaySummary` fields:
  - `eatingTriggers`: Aggregate from `FoodLogEntry.eatingTriggers` arrays for that day → count dict
  - `mealTypes`: Aggregate from `FoodLogEntry.mealType` for that day → count dict
  - `foodNames`: Collect `FoodLogEntry.foodName` for that day → array
  - `interventionSessions`: Find `InterventionSession` entries for that day, compute stress delta per session (same logic as 2.4 but inline)
- Why: Keeps the shared `WellnessDaySummary` complete so both hub cards and report can use the same data
- Dependencies: 1.3
- Risk: Low — additive changes to existing loop

---

### Phase 9: Build Verification & Mock Support

**9.1 Add mock report data** (File: `ReportViewModel.swift`)
- Action: When `AppConfig.shared.mockMode` is true, skip data building and return a hardcoded `ReportData` with representative mock values for all sections. Follow the same pattern as `InsightEngine.mockInsights()`.
- Why: Enables UI development and testing without real data
- Dependencies: 4.1
- Risk: Low

**9.2 Build verification**
- Action: Run all 4 build targets:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
- Why: Ensures no compilation errors across all targets
- Dependencies: All phases
- Risk: Low

---

## Testing Strategy

- **Build verification**: All 4 targets must compile cleanly
- **Mock mode testing**: Toggle `AppConfig.shared.mockMode = true`, navigate to InsightsHub → Full Report, verify all sections render with mock data
- **Manual verification flows**:
  - Report with full data (all sections visible)
  - Report with minimal data (e.g., only food logs — verify only nutrition section + executive summary appear)
  - Report with zero HealthKit vitals — verify vitals section is completely hidden
  - Report with symptoms but no food logs — verify symptom section appears but food-sensitivity table shows "no food data"
  - Foundation Models availability check — verify template fallback renders correctly on iOS < 26
  - "Regenerate" button clears cache and re-generates
  - Scroll performance — no jank on 15-day report with all sections

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Foundation Models unavailable or slow | Medium | Template fallback covers all 3 LLM calls. Show progress bar during generation. Cache results for same-day. |
| Large number of new files (20) | Medium | Each file is focused and self-contained. Phase structure ensures incremental buildability. |
| Scroll performance with many charts | Medium | Use `LazyVStack` for deferred rendering. Charts in fixed frames. Heavy charts (heatmap, radar) use `Canvas`. |
| Food-symptom ratio edge cases | Medium | Require food to appear >= 2 times total. Guard against div-by-zero. Show "may be associated" language. |
| `WellnessDaySummary` struct growing large | Low | All new fields have defaults. Struct is stack-allocated and only lives during report generation. |
| Correlation matrix with many empty cells | Low | Only render cells for available metrics. Use `availableVitals` set to filter. |

---

## Implementation Order Summary

| Phase | Steps | New Files | Estimated Complexity |
|---|---|---|---|
| 1: Models | 1.1-1.3 | 1 new + 1 modified | Low |
| 2: Data Builder | 2.1-2.6 | 1 new | High |
| 3: Narrative Gen | 3.1-3.2 | 1 new | Medium |
| 4: ViewModel | 4.1 | 1 new | Low |
| 5: Charts | 5.1 | 1 new | Medium-High |
| 6: Section Views | 6.1-6.14 | 14 new | Medium (individually low, volume high) |
| 7: Main View + Nav | 7.1-7.2 | 1 new + 1 modified | Low |
| 8: InsightEngine Update | 8.1 | 0 new + 1 modified | Low |
| 9: Mock + Build | 9.1-9.2 | 0 new | Low |

---

## Success Criteria

- [ ] All 4 build targets compile cleanly
- [ ] Report renders as a single scrollable view from InsightsHub
- [ ] All 13 sections appear with mock data when `mockMode = true`
- [ ] Sections with zero data are completely hidden (no headers, no empty states)
- [ ] HealthKit metrics with 0 samples in window do not appear anywhere in the report
- [ ] Goal comparison lines/stats appear on every applicable section
- [ ] Food-symptom correlation table shows specific food names with trigger ratios
- [ ] Cross-domain correlation matrix renders correctly with only available metrics
- [ ] Foundation Models generates narratives on iOS 26+
- [ ] Template fallback produces readable narratives on iOS < 26
- [ ] Scroll performance is smooth (no dropped frames on iPhone 15)
- [ ] Intervention effectiveness shows pre/post stress comparison
- [ ] Report caches for same day; "Regenerate" clears and re-runs
