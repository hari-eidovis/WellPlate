# Implementation Plan: 15-Day AI Insights Report

**Date**: 2026-04-10
**Source**: `Docs/01_Brainstorming/260410-ai-insights-15day-report-brainstorm.md`
**Status**: RESOLVED — ready for checklist

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| C1: `WellnessDaySummary` `let` fields break memberwise init | CRITICAL | New fields use `var` with defaults — existing call site untouched |
| H1: Dual model `ReportDaySummary` vs `WellnessDaySummary` | HIGH | Dropped `ReportDaySummary`. Extended `WellnessDaySummary` only. `ReportContext.days` is `[WellnessDaySummary]`. |
| H2: Batch FM call for ~10 section narratives | HIGH | Changed to per-section loop (top 5). ~7 FM calls total: 1 exec summary + 5 sections + 1 action plan. |
| H3: `ReportData` type undefined | HIGH | Explicitly defined in Step 1.1. |
| M1: Correlation matrix readability | MEDIUM | Capped at 8 metrics, abbreviated labels, `Canvas`-based fallback noted. |
| M2: `SectorMark` availability | MEDIUM | Confirmed iOS 17+. First usage in project acknowledged. |
| M3: Food-symptom day-before timezone | MEDIUM | Explicit `Calendar.current.date(byAdding:)` approach documented. |
| M4: 15-day vs 14-day window mismatch | MEDIUM | Acknowledged as intentional. Report header says "15 days"; hub says "14 days". |
| M5: Missing `coffeeType` in per-day summary | MEDIUM | Added `coffeeType: String?` to `WellnessDaySummary` extension. |
| M6: Intervention 2-hour window too narrow | MEDIUM | Widened to 4 hours. Show "insufficient readings" if all sessions skipped. |
| M7: No shimmer spec | MEDIUM | Use existing `ProgressView` pattern with progress %. Skip shimmer for V1. |
| L1: 20 new files | LOW | Accepted. `PBXFileSystemSynchronizedRootGroup` handles it. |
| L2: No accessibility plan | LOW | Deferred to V2. Note added. |
| L3: No unit tests for ReportDataBuilder | LOW | Deferred to V2. Note added. |

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
| 1 | `WellPlate/Features + UI/Home/Models/ReportModels.swift` | `ReportContext`, `FoodSymptomLink`, `CrossCorrelation`, `InterventionResult`, `ExperimentSummary`, `ReportPromptContext`, `ReportData`, `ReportState`, `ReportNarratives`, FM `@Generable` schemas |
| 2 | `WellPlate/Core/Services/ReportDataBuilder.swift` | Fetches all SwiftData + HealthKit data, builds `ReportContext` with per-day summaries, computes food-symptom links, cross-domain correlations, intervention deltas |
| 3 | `WellPlate/Core/Services/ReportNarrativeGenerator.swift` | Foundation Models structured output calls (7 calls: exec summary, top 5 section narratives, action plan) + template fallback |
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
| 20 | `WellPlate/Features + UI/Home/Components/ReportCharts.swift` | New chart components: `StressVolatilityChart`, `FactorDecompositionChart`, `MealTimingHeatmap`, `BedtimeScatterChart`, `VitalTrendChart`, `SymptomTimelineChart`, `CorrelationMatrixChart`, `AdherenceGauge`, `StatPillRow`, `FoodSensitivityRow` |

### Modified Files

| File | Change |
|---|---|
| `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` | Add navigation to `AI15DayReportView` (button in header or a "Full Report" card in the feed) |
| `WellPlate/Features + UI/Home/Models/InsightModels.swift` | Extend `WellnessDaySummary` with new `var` fields (with defaults); add `case supplements` to `WellnessDomain` |
| `WellPlate/Core/Services/InsightEngine.swift` | Update `buildWellnessContext()` to populate the new `WellnessDaySummary` fields (eating triggers, meal types, food names, coffee type, interventions) |

---

## Implementation Steps

### Phase 1: Data Models & Types (no UI, no service logic)

<!-- RESOLVED: C1 — New fields use `var` with defaults, keeping them out of the memberwise init. Existing InsightEngine call site remains untouched. -->
<!-- RESOLVED: H1 — Dropped ReportDaySummary entirely. WellnessDaySummary is the single per-day type used by both InsightEngine and ReportDataBuilder. -->
<!-- RESOLVED: H3 — ReportData explicitly defined in Step 1.1. -->
<!-- RESOLVED: M5 — coffeeType: String? added to WellnessDaySummary extension. -->

**1.1 Create `ReportModels.swift`** (File: `WellPlate/Features + UI/Home/Models/ReportModels.swift`)
- Action: Define all report-specific value types:
  - `ReportContext` — wraps shared types + report-specific computed data:
    ```swift
    struct ReportContext {
        let days: [WellnessDaySummary]      // Same type used by InsightEngine
        let goals: UserGoalsSnapshot
        let availableVitals: Set<VitalMetric>  // Which HK vitals have data
        let foodSymptomLinks: [FoodSymptomLink]
        let crossCorrelations: [CrossCorrelation]
        let interventionResults: [InterventionResult]
        let experimentSummaries: [ExperimentSummary]
        let dataQualityNote: String
    }
    ```
  - `ReportData` — final assembled output consumed by the view:
    ```swift
    struct ReportData {
        let context: ReportContext
        let narratives: ReportNarratives
        let generatedAt: Date
    }
    ```
  - `ReportNarratives` — all LLM/template-generated text:
    ```swift
    struct ReportNarratives {
        let executiveSummary: ExecutiveSummaryNarrative
        let sectionNarratives: [String: SectionNarrative]  // keyed by section name
        let actionPlan: [ActionRecommendation]
    }
    struct ExecutiveSummaryNarrative {
        let narrative: String
        let topWin: String
        let topConcern: String
    }
    struct SectionNarrative {
        let headline: String
        let narrative: String
    }
    struct ActionRecommendation {
        let title: String
        let rationale: String
        let domain: String
    }
    ```
  - `FoodSymptomLink`:
    ```swift
    enum FoodSymptomClassification: String {
        case potentialTrigger, potentialProtective, neutral
    }
    struct FoodSymptomLink: Identifiable {
        let id = UUID()
        let symptomName: String
        let foodName: String
        let symptomDayCount: Int        // total symptom days
        let clearDayCount: Int          // total clear days with food logs
        let symptomDayAppearances: Int  // times food appeared on symptom days
        let clearDayAppearances: Int    // times food appeared on clear days
        let ratio: Double               // symptomDayRate / clearDayRate
        let classification: FoodSymptomClassification
    }
    ```
  - `CrossCorrelation`:
    ```swift
    struct CrossCorrelation: Identifiable {
        let id = UUID()
        let xName: String
        let yName: String
        let xDomain: WellnessDomain
        let yDomain: WellnessDomain
        let spearmanR: Double
        let ciLow: Double
        let ciHigh: Double
        let pairedDays: Int
        let isSignificant: Bool
        let scatterPoints: [(x: Double, y: Double)]
    }
    ```
  - `InterventionResult`:
    ```swift
    struct InterventionResult: Identifiable {
        let id = UUID()
        let resetType: String
        let sessionCount: Int
        let avgPreStress: Double
        let avgPostStress: Double
        let avgDelta: Double  // post - pre (negative = improvement)
    }
    ```
  - `ExperimentSummary`:
    ```swift
    struct ExperimentSummary: Identifiable {
        let id = UUID()
        let name: String
        let hypothesis: String?
        let interventionType: String
        let baselineAvg: Double?
        let experimentAvg: Double?
        let delta: Double?
        let ciLow: Double?
        let ciHigh: Double?
        let isComplete: Bool
    }
    ```
  - `ReportPromptContext` — pre-aggregated text for LLM (computed property or method on `ReportContext`)
  - `ReportState` enum:
    ```swift
    enum ReportState {
        case idle
        case generating(progress: Double)
        case ready(ReportData)
        case error(String)
    }
    ```
- Why: Isolates all types in one file; views and services both import from here
- Dependencies: None
- Risk: Low

**1.2 Define Foundation Models `@Generable` schemas** (File: same `ReportModels.swift`)
- Action: Add `@Generable` structs guarded by `#if canImport(FoundationModels)` + `@available(iOS 26, *)`:
  - `_ReportExecutiveSummary` — narrative (String), topWin (String), topConcern (String)
  - `_ReportSectionNarrative` — headline (String), narrative (String)
  - `_ReportActionPlan` — recommendations: `[_ActionRecommendation]`
  - `_ActionRecommendation` — title (String), rationale (String), domain (String)
<!-- RESOLVED: H2 — Removed _ReportSectionNarratives batch schema. Section narratives now generated per-section using _ReportSectionNarrative (singular). -->
- Note: No batch `_ReportSectionNarratives` schema — section narratives are generated individually per-section, each using `_ReportSectionNarrative`.
- Why: Foundation Models requires `@Generable` types; per-section generation matches existing `InsightEngine` pattern
- Dependencies: 1.1
- Risk: Low

**1.3 Extend `InsightModels.swift`** (File: `WellPlate/Features + UI/Home/Models/InsightModels.swift`)
- Action:
  - Add new `var` fields with defaults to `WellnessDaySummary` (at the bottom of the struct):
    ```swift
    // Report-specific fields (var with defaults — does not affect memberwise init)
    var eatingTriggers: [String: Int] = [:]       // trigger name → count
    var mealTypes: [String: Int] = [:]            // meal type → count
    var foodNames: [String] = []                  // foods logged that day
    var coffeeType: String? = nil                 // coffee type for the day
    var interventionSessions: [(type: String, stressDelta: Double?)] = []
    ```
  - Add `case supplements` to `WellnessDomain` with:
    - `label: "Supplements"`, `icon: "pill.fill"`
    - `accentColor`: use a purple tone similar to `SupplementCategory.medication.color` — `Color(hue: 0.72, saturation: 0.50, brightness: 0.80)`
- Why: Shared type used by both `InsightEngine` and `ReportDataBuilder`. Using `var` with defaults keeps the existing memberwise init call in `InsightEngine.buildWellnessContext()` working without changes.
- Dependencies: None
- Risk: Low — additive only, `var` with defaults is invisible to existing callers

---

### Phase 2: Data Builder Service

**2.1 Create `ReportDataBuilder.swift`** (File: `WellPlate/Core/Services/ReportDataBuilder.swift`)
- Action: Create `@MainActor final class ReportDataBuilder` with:
  - `func buildReportContext(modelContext: ModelContext, healthService: HealthKitServiceProtocol) async -> ReportContext`
  - Internal structure:
    1. **Date window**: `Calendar.current.startOfDay(for: .now)` minus 14 days through today = 15-day window
    <!-- RESOLVED: M4 — 15-day window is intentional per brainstorm. Report header will say "15 days". InsightEngine hub uses 14 days. This is a deliberate difference. -->
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
    4. **Zero-tolerance filter**: Build `Set<VitalMetric>` of available vitals by checking each HK result `.isEmpty`. For each vital in `VitalMetric.allCases`, only include it if the corresponding fetch returned a non-empty array.
    5. **Per-day summary loop**: For each day in window, build a `WellnessDaySummary` (same pattern as `InsightEngine.buildWellnessContext()`), additionally populating:
       - `eatingTriggers`: Aggregate `FoodLogEntry.eatingTriggers` arrays for that day into a `[String: Int]` count dict
       - `mealTypes`: Aggregate `FoodLogEntry.mealType` for that day into a `[String: Int]` count dict
       - `foodNames`: Collect `FoodLogEntry.foodName` for that day into `[String]`
       - `coffeeType`: From `WellnessDayLog.coffeeType` for that day
       - `interventionSessions`: Find `InterventionSession` entries for that day, compute stress delta per session (using `computeSessionStressDelta()`)
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
     <!-- RESOLVED: M3 — day-before matching uses Calendar.current.date(byAdding: .day, value: -1, to:) explicitly -->
     - For each unique food logged across all days:
       - Count appearances on symptom days: food logged on same day as symptom OR on the day before symptom day (using `Calendar.current.date(byAdding: .day, value: -1, to: symptomDay)` for the "day before" check)
       - Count appearances on clear days
       - Require food to appear >= 2 times total to be considered (filter noise)
       - Compute frequency ratio: `(symptomDayAppearances / symptomDayCount) / (clearDayAppearances / clearDayCount)`
       - Guard against division by zero: skip if `clearDayCount == 0` or `clearDayAppearances == 0` (treat as neutral)
       - Classify: ratio > 2.0 = `.potentialTrigger`, ratio < 0.5 = `.potentialProtective`, else `.neutral`
     - Only return `.potentialTrigger` and `.potentialProtective` links (skip neutrals)
  3. Also compute macro-level Spearman correlations using `CorrelationMath.spearmanR()` for each symptom vs calories, protein, fiber, fat, caffeine, water, stress, sleep — store as additional `CrossCorrelation` entries tagged with `.symptoms` domain
- Why: Core differentiator — specific food tracking, not just macro-level
- Dependencies: 2.1, `CorrelationMath` (existing)
- Risk: Medium — edge cases around foods with very low frequency mitigated by >= 2 appearances filter

**2.3 Implement `computeCrossCorrelations()`** (File: same `ReportDataBuilder.swift`)
- Action: Private method that:
  1. Defines metric pairs, each with extract closures on `WellnessDaySummary`:
     - Sleep hours <-> Stress score
     - Steps <-> Stress score
     - Coffee cups <-> Stress score
     - Coffee cups <-> Sleep hours
     - Protein <-> Stress score
     - Fiber <-> Stress score
     - Water <-> Stress score
     - Exercise minutes <-> Stress score
     - Sleep hours <-> Steps
     - Calories <-> Steps
     - Fasting (binary: 1 if fastingHours != nil, 0 otherwise) <-> Stress score
     - Supplement adherence <-> Symptom max severity
     - Heart rate <-> Stress score (only if HR in `availableVitals`)
  2. Filters pairs based on `availableVitals` — skip any pair involving an excluded metric
  <!-- RESOLVED: M1 — Correlation matrix capped at 8 metrics max. Use abbreviated labels: "Sleep", "Stress", "Steps", "Coffee", "Protein", "Fiber", "Water", "Exercise". If more than 8 metrics available, pick the 8 with highest data density. -->
  3. Cap included metrics at 8 for the matrix visualization. If more than 8 have data, keep the 8 with the most data days. All correlations are still computed, but the matrix chart only shows top 8.
  4. For each pair: extract paired values for days where both metrics exist, require >= 5 pairs
  5. Compute `CorrelationMath.spearmanR()` and `CorrelationMath.bootstrapCI()` on `Task.detached`
  6. Filter to `|r| >= 0.3` AND CI doesn't span zero
  7. Build `CrossCorrelation` objects with scatter points
  8. Sort by `|r|` descending
- Why: Powers Section 12 (correlation matrix + top 3 links)
- Dependencies: 2.1, `CorrelationMath` (existing)
- Risk: Low — pattern is identical to `InsightEngine.detectCorrelations()`

**2.4 Implement `computeInterventionResults()`** (File: same `ReportDataBuilder.swift`)
<!-- RESOLVED: M6 — Widened window from 2 hours to 4 hours. Added "insufficient readings" fallback if all sessions have no nearby readings. -->
- Action: Private method that:
  1. Groups completed `InterventionSession` by `resetType`
  2. For each session: find the `StressReading` closest to (and before) `startedAt` within **4 hours**, and the `StressReading` closest to (and after) `startedAt + durationSeconds` within **4 hours**
  3. If both found, compute delta = post - pre
  4. Aggregate per reset type: count, avg pre, avg post, avg delta
  5. If ALL sessions for a reset type have no nearby readings, still include the `InterventionResult` with `sessionCount` set but `avgDelta` as 0 and a flag `hasMeasurableData: Bool = false` — the section view can show "X sessions completed, insufficient stress readings to measure effectiveness"
  6. Return `[InterventionResult]`
- Why: Shows whether PMR/sigh sessions actually reduce stress
- Dependencies: 2.1
- Risk: Low

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
  - Exclude any domain/metric not present in `availableVitals` or with zero data
  - Format as compact multi-line text (~500-800 words max)
- Why: Foundation Models has limited context; raw data is too large
- Dependencies: 2.1-2.5
- Risk: Low

---

### Phase 3: Narrative Generation Service

<!-- RESOLVED: H2 — Switched from 3 batch calls to per-section loop (top 5 sections). ~7 FM calls total. -->

**3.1 Create `ReportNarrativeGenerator.swift`** (File: `WellPlate/Core/Services/ReportNarrativeGenerator.swift`)
- Action: Create `@MainActor final class ReportNarrativeGenerator` with:
  - `func generateNarratives(for context: ReportContext, promptContext: ReportPromptContext) async -> ReportNarratives`
  - Foundation Models path (iOS 26+):
    - **Call 1: Executive Summary** — feed full prompt context, generate `_ReportExecutiveSummary`
    - **Calls 2-6: Section Narratives** — loop over the top 5 most data-rich sections. For each, create a focused prompt with that section's stats, generate `_ReportSectionNarrative`. Each call uses a fresh `LanguageModelSession()` (matching existing pattern in `InsightEngine` line 689).
    - **Call 7: Action Plan** — feed prompt context + top findings, generate `_ReportActionPlan`
    - Each call wrapped in do/catch; on failure, fall through to template for that specific item
  - Section priority for FM narrative generation (top 5 of these, based on data availability):
    1. Stress (if stress data exists)
    2. Nutrition (if food logs exist)
    3. Sleep (if sleep data exists)
    4. Symptoms (if symptom data exists)
    5. Activity (if step/energy data exists)
    6. Cross-Domain (if correlations found)
    7. Remaining sections use template-only narratives
  - Template fallback path (iOS < 26 or FM failure):
    - Executive summary: rule-based narrative from stats
    - Section narratives: per-section templates using the same pattern as `InsightEngine.templateNarrative()`
    - Action plan: top 3-5 rules based on goal gaps and correlation strength
- Why: Isolates LLM logic from data building and view rendering; per-section calls produce higher quality than batch
- Dependencies: 1.2 (Generable schemas), 2.6 (prompt context)
- Risk: Medium — ~7 FM calls at ~2-4 seconds each = ~14-28 seconds total. Progress bar essential.

**3.2 Build LLM prompt strings** (File: same `ReportNarrativeGenerator.swift`)
- Action: Private methods for each prompt type:
  - `buildExecutiveSummaryPrompt(promptContext:)` — instructs: "Write a 3-4 sentence executive summary of this person's 15-day wellness data. Reference specific numbers. Use 'may suggest' framing. No medical claims."
  - `buildSectionNarrativePrompt(sectionName:, sectionStats:, promptContext:)` — instructs: "Write a punchy headline (max 50 chars) and a 1-2 sentence narrative for the [sectionName] section. Reference the specific data provided. Use 'may suggest' framing."
  - `buildActionPlanPrompt(promptContext:)` — instructs: "Generate 3-5 specific actionable recommendations ranked by impact. Each must reference a data point. Use 'consider' framing."
- Why: Prompt quality is critical for narrative quality
- Dependencies: 3.1
- Risk: Low

---

### Phase 4: ViewModel

**4.1 Create `ReportViewModel.swift`** (File: `WellPlate/Features + UI/Home/ViewModels/ReportViewModel.swift`)
- Action: Create `@MainActor final class AI15DayReportViewModel: ObservableObject` with:
  - Published state: `@Published var reportState: ReportState = .idle`
  - Dependencies: `ReportDataBuilder`, `ReportNarrativeGenerator`, `ModelContext?`, `HealthKitServiceProtocol`
  - `bindContext(_ context: ModelContext)` — same pattern as `InsightEngine`
  - `generateReport() async`:
    1. Set `reportState = .generating(progress: 0)`
    2. Build `ReportContext` via `ReportDataBuilder` → set progress 0.3
    3. Build `ReportPromptContext` → set progress 0.4
    4. Generate narratives via `ReportNarrativeGenerator` → update progress incrementally per FM call (0.4 → 0.9)
    5. Assemble `ReportData(context:, narratives:, generatedAt: .now)` → set progress 1.0
    6. Set `reportState = .ready(reportData)`
    7. On error: set `reportState = .error(message)`
  - Same-day caching: if `reportState` is already `.ready` and `generatedAt` is today, skip regeneration
  - `clearAndRegenerate() async` — clears cache, re-runs
  <!-- RESOLVED: M7 — Loading state uses ProgressView + progress percentage, matching InsightsHubView.loadingView pattern. No shimmer for V1. -->
- Why: Standard MVVM — view observes state, VM orchestrates async work
- Dependencies: 2.1-2.6, 3.1
- Risk: Low

---

### Phase 5: Chart Components

**5.1 Create `ReportCharts.swift`** (File: `WellPlate/Features + UI/Home/Components/ReportCharts.swift`)
- Action: Build new chart components not already in `InsightCharts.swift`:

  **`StatPillRow`** — horizontal row of stat capsules (e.g., "Avg: 52", "Best: 28", "Worst: 78")
  - Input: `[(label: String, value: String, color: Color?)]`
  - Layout: `HStack` of capsule-shaped pills with `.font(.system(size: 11, weight: .semibold, design: .rounded))`

  **`StressVolatilityChart`** — daily min/max range bars
  - Input: `[(date: Date, min: Double, max: Double, avg: Double)]`
  - Chart: `RuleMark` vertical bar for each day (min to max), `PointMark` for avg
  - Color: Range bar in `.secondary.opacity(0.3)`, avg point in accent

  **`FactorDecompositionChart`** — stacked horizontal bars for high vs low stress days
  - Input: `[(label: String, exercise: Double, sleep: Double, diet: Double, screenTime: Double)]`
  - Chart: Stacked `BarMark` with 4 colors per factor (green=exercise, indigo=sleep, orange=diet, purple=screenTime)
  - Use: Section 2c

  **`MealTimingHeatmap`** — grid of day x time-bucket
  - Input: `[(dayIndex: Int, dayLabel: String, bucket: String, count: Int)]`
  - Chart: `RectangleMark` with color intensity mapped to count (0 = clear, 1 = light accent, 2+ = full accent)
  - Buckets: "6-10am", "10am-2pm", "2-6pm", "6-10pm", "10pm+"

  **`BedtimeScatterChart`** — bedtime/waketime consistency
  - Input: `[(date: Date, bedtime: Date?, wakeTime: Date?)]`
  - Chart: Two series of `PointMark` — indigo for bedtime, orange for wake
  - Y-axis: time of day (formatted as HH:mm via `.chartYAxis` with custom `AxisValueLabel`)

  **`VitalTrendChart`** — generic line chart for any vital metric
  - Input: `points: [DailyMetricSample]`, `metric: VitalMetric`
  - Chart: `LineMark` with accent color from `VitalMetric.accentColor`, `AreaMark` gradient fill
  - Benchmark: Add `RuleMark` bands using hardcoded normal ranges per `VitalMetric` case (e.g., HR: 60-100 BPM, HRV: 20-70ms)

  **`SymptomTimelineChart`** — bubble chart of symptom severity over time
  - Input: `[(date: Date, maxSeverity: Int, count: Int, stressScore: Double?)]`
  - Chart: `PointMark` sized by count, colored by severity (green < 4, yellow 4-6, red > 6); optional `LineMark` overlay for stress trend (secondary axis)

  <!-- RESOLVED: M1 — Correlation matrix capped at 8 metrics, abbreviated labels. Canvas-based fallback noted if Swift Charts heatmap is unreadable. -->
  **`CorrelationMatrixChart`** — heatmap grid of r-values
  - Input: `metrics: [String]` (max 8, abbreviated), `correlations: [(xIdx: Int, yIdx: Int, r: Double, isSignificant: Bool)]`
  - Chart: `RectangleMark` grid, color scale: blue (r = -1) → white (r = 0) → red (r = +1). Non-significant cells in light gray.
  - Labels: Use abbreviated names max 6 chars (e.g., "Sleep", "Stress", "Steps", "Coffee", "Protein", "Fiber", "Water", "Exerc.")
  - Fallback: If axis labels don't fit, switch to a `Canvas`-based custom renderer with rotated labels

  **`AdherenceGauge`** — circular gauge for supplement adherence
  - Input: `rate: Double` (0-1), `label: String`
  - Visual: Custom arc matching `MilestoneRingView` pattern — background circle + trim arc + center text

  **`FoodSensitivityRow`** — list row for a food-symptom link
  - Input: `FoodSymptomLink`
  - Layout: food name (bold), ratio badge (red for trigger, green for protective), "appeared X/Y symptom days vs X/Y clear days" subtext

  <!-- RESOLVED: M2 — SectorMark confirmed available on iOS 17+. First usage in this codebase. -->
  **`SymptomCategoryDonut`** — donut chart for symptom category breakdown
  - Input: `[(category: SymptomCategory, count: Int)]`
  - Chart: `SectorMark` (iOS 17+, first usage in project) with `SymptomCategory.color` per slice

- Why: Each section needs chart types not in the existing `InsightCharts.swift`
- Dependencies: None (pure SwiftUI views)
- Risk: Medium — many chart types, but each is self-contained. Correlation matrix and meal timing heatmap are the most complex.

---

### Phase 6: Report Section Views

Each section is a self-contained `View` that takes `ReportData` and renders conditionally. Every section receives the full `ReportData` value (it's a struct, cheap to pass) and extracts the slice it needs.

**6.1 `ReportHeaderSection.swift`**
- Input: `ReportData` (extracts date range, data quality info)
- Layout: Title "Your 15-Day Wellness Report", subtitle date range (formatted as "Mar 27 - Apr 10, 2026"), data quality badge ("Based on X days of data across Y domains")
- Animation: `insightEntrance(index: 0)`
- Dependencies: None
- Risk: Low

**6.2 `ExecutiveSummarySection.swift`**
- Input: `ReportData.narratives.executiveSummary`
- Layout: Large narrative text (`.r(.body, .regular)`), two highlight pills — topWin (green tint) and topConcern (amber tint)
- Conditional: Always shown (even if narrative is template-generated)
- Dependencies: 3.1 (narrative output)
- Risk: Low

**6.3 `StressDeepDiveSection.swift`**
- Input: `ReportData` (stress data from `context.days`, `context.interventionResults`, `context.experimentSummaries`)
- Condition: `data.context.days.contains { $0.stressScore != nil }`
- Sub-views:
  - 2a: `TrendAreaChart` (reuse existing) for daily avg stress + `StatPillRow` (new) for period avg, best day, worst day, trend direction
  - 2b: `StressVolatilityChart` (new) — compute per-day min/max from `StressReading` grouped by day. Need to pass the raw readings or pre-compute min/max in the per-day loop. **Decision**: pre-compute `stressMin: Double?` and `stressMax: Double?` fields — add as `var` with defaults on `WellnessDaySummary` (same C1 pattern)
  - 2c: `FactorDecompositionChart` (new) — compute factor scores per day using `StressScoring.exerciseScore()`, `.sleepScore()`, `.dietScore()`, `.screenTimeScore()`. Pick top 3 highest-stress days and top 3 lowest-stress days, show stacked factor bars side by side.
  - 2d: Best vs worst day — two side-by-side `VStack` cards. Best day = day with lowest avg stress, worst = highest. Each card shows: date, stress score, sleep hours, steps, calories, coffee cups, mood label. Highlight the biggest delta metric between the two.
  - 2e: Intervention results (conditional on `!data.context.interventionResults.isEmpty`): grouped `BarMark` for each reset type — pre (gray) vs post (accent) stress bars + delta label. If `hasMeasurableData == false`, show text: "X sessions completed — no nearby stress readings to measure effectiveness"
  - 2f: Experiment results (conditional on `!data.context.experimentSummaries.isEmpty`): hypothesis text + `ComparisonBarChart` (existing) for baseline vs experiment avg + CI text
- LLM narrative: section headline + narrative from `data.narratives.sectionNarratives["stress"]`
- Dependencies: 5.1 (charts), 2.4, 2.5
- Risk: Medium — most complex section with 6 sub-views

**6.4 `NutritionSection.swift`**
- Input: `ReportData` (food log data from `context.days`, `context.goals`)
- Condition: `data.context.days.contains { $0.totalCalories != nil }`
- Sub-views:
  - 3a: Calorie trend — `BarMark` daily calories with `RuleMark` goal line + `StatPillRow`. Bar color: green (within 10% of goal), amber (10-20%), red (>20%).
  - 3b: Macro radar — reuse `MacroGroupedBarChart` (existing) with 15-day averages vs goals
  - 3c: `MealTimingHeatmap` (new) — bucket `FoodLogEntry.createdAt` timestamps into 5 time slots per day. Data derived from `context.days[].foodNames` timestamps (need to store meal timestamps — **add `var mealTimestamps: [Date] = []` to `WellnessDaySummary`**)
  - 3d: Meal type distribution — horizontal `BarMark` from `context.days[].mealTypes` aggregated across all days
  - 3e: Eating triggers — horizontal `BarMark` from `context.days[].eatingTriggers` aggregated across all days. Simple ranked list.
  - 3f: Top foods — ranked list view (top 10 by count across all `foodNames`, with per-food calorie totals). Data from `FoodLogEntry` query — **`ReportDataBuilder` should also compute `topFoods: [(name: String, count: Int, totalCalories: Int)]` and store on `ReportContext`.**
  - 3g: Food variety score — count unique values across all `foodNames` arrays. Benchmark: < 10 = "Limited variety", 10-20 = "Moderate", 20+ = "Good variety"
- Dependencies: 5.1 (heatmap)
- Risk: Medium — many sub-charts but each is simple

**6.5 `SleepSection.swift`**
- Input: `ReportData` (sleep data from `context.days`, `context.goals`)
- Condition: `data.context.days.contains { $0.sleepHours != nil }`
- Sub-views:
  - 4a: Stacked `BarMark` (deep=purple, REM=indigo, core=blue per `SleepStage.color`) per night + `RuleMark` goal line + `StatPillRow`
  - 4b: Deep sleep ratio `LineMark` (deepSleepHours / sleepHours * 100) + benchmark `RuleMark` band at 15-20%
  - 4c: `BedtimeScatterChart` (new) + std deviation stat ("Your bedtime varies by +/- X minutes")
  - 4d: Sleep-stress scatter (conditional: >= 5 overlapping days with both sleep and next-day stress) — reuse `CorrelationScatterChart` with X = sleep hours, Y = next-day avg stress. Compute Spearman r.
- Dependencies: 5.1 (bedtime chart)
- Risk: Low

**6.6 `ActivitySection.swift`**
- Input: `ReportData` (activity data from `context.days`, `context.goals`)
- Condition: `data.context.days.contains { $0.steps != nil || $0.activeCalories != nil }`
- Sub-views:
  - 5a: Steps `BarMark` + goal `RuleMark` + 7-day rolling avg `LineMark` + `StatPillRow`
  - 5b: Active energy `AreaMark` (reuse `TrendAreaChart` with `activeEnergyGoalKcal` as goal line)
  - 5c: Exercise minutes `BarMark` with per-day goal `RuleMark` from `UserGoals.workoutMinutes(for:)` — compute weekday from each day's date
  - 5d: Movement-stress scatter (conditional: >= 5 days with both) — reuse `CorrelationScatterChart`
- Dependencies: None (reuses existing charts)
- Risk: Low

**6.7 `VitalsSection.swift`**
- Input: `ReportData` (vitals from `context.availableVitals`, HK data stored on `context.days`)
- Condition: `!data.context.availableVitals.isEmpty`
- Sub-views: For each `VitalMetric` in `availableVitals`, render a `VitalTrendChart` (new) with benchmark bands. Each sub-chart individually conditional. Section header: "Vitals".
- Note: Need to store vital data on `WellnessDaySummary`. Currently only `heartRateAvg` is there. **Add `var` fields**: `restingHeartRateAvg: Double? = nil`, `hrvAvg: Double? = nil`, `systolicBPAvg: Double? = nil`, `diastolicBPAvg: Double? = nil`, `respiratoryRateAvg: Double? = nil`, `daylightMinutes: Double? = nil`
- Dependencies: 5.1 (VitalTrendChart)
- Risk: Low — same chart template parameterized per metric

**6.8 `HydrationCaffeineSection.swift`**
- Input: `ReportData` (water/coffee data, goals)
- Condition: `data.context.days.contains { ($0.waterGlasses ?? 0) > 0 || ($0.coffeeCups ?? 0) > 0 }`
- Sub-views:
  - 7a: Water `BarMark` + goal `RuleMark` + `StatPillRow` (avg, days meeting goal, streak)
  - 7b: Coffee `BarMark` + goal `RuleMark` (coffeeDailyCups) + coffee type distribution (horizontal bar of type counts across the window from `coffeeType` field)
  - 7c: Caffeine-stress link (conditional: >= 5 days with both) — `ComparisonBarChart` (existing): avg stress on 0-2 cup days vs 3+ cup days + Spearman r badge
- Dependencies: None
- Risk: Low

**6.9 `SymptomSection.swift`**
- Input: `ReportData` (symptom data, food-symptom links, stress data)
- Condition: `data.context.days.contains { !$0.symptomNames.isEmpty }`
- Sub-views:
  - 8a: Symptom frequency horizontal `BarMark`, colored by `SymptomCategory.color`
  - 8b: `SymptomTimelineChart` (new) — severity bubbles with optional stress overlay
  - 8c: `SymptomCategoryDonut` (new, `SectorMark`) — % by category
  - 8d: **Food sensitivity table** — for each symptom with `FoodSymptomLink` entries, render a grouped list with `FoodSensitivityRow` components. Show "Potential triggers" (ratio > 2x) and "Potential protective" (ratio < 0.5x) separately. Include "Correlations require more data to confirm" disclaimer for any link with < 7 paired days.
  - 8e: Symptom-stress scatter — reuse `CorrelationScatterChart` (X = stress score, Y = severity)
- Dependencies: 5.1, 2.2
- Risk: Medium — food sensitivity table is the most novel UI component

**6.10 `SupplementSection.swift`**
- Input: `ReportData` (adherence data)
- Condition: `data.context.days.contains { $0.supplementAdherence != nil }`
- Sub-views:
  - 9a: `AdherenceGauge` (new) — overall % ring
  - 9b: Per-supplement horizontal `BarMark` sorted worst to best, colored green (>= 80%), amber (50-79%), red (< 50%). Data: **`ReportDataBuilder` should compute `perSupplementAdherence: [(name: String, rate: Double)]` and store on `ReportContext`.**
  - 9c: Adherence-symptom link (conditional: >= 5 days with both) — Spearman r stat
- Dependencies: 5.1
- Risk: Low

**6.11 `FastingSection.swift`**
- Input: `ReportData` (fasting data)
- Condition: `data.context.days.contains { $0.fastingHours != nil }`
- Sub-views:
  - 10a: `StatPillRow` (sessions, completion rate %, avg duration, longest) + duration `BarMark` per session
  - 10b: Fasting-stress comparison bars (conditional: >= 3 fasting + >= 3 non-fasting days) — reuse `ComparisonBarChart`
- Dependencies: None
- Risk: Low

**6.12 `MoodSection.swift`**
- Input: `ReportData` (mood data)
- Condition: `data.context.days.contains { $0.moodLabel != nil }`
- Sub-views:
  - 11a: Horizontal `BarMark` of mood distribution (count each `MoodOption` across all days)
  - 11b: Dual-line overlay — mood score (inverted: 4 - moodRaw, so higher = worse → aligns with stress) and stress score. Two `LineMark` series with different colors.
- Dependencies: None
- Risk: Low

**6.13 `CrossDomainSection.swift`**
- Input: `ReportData` (cross-correlations)
- Condition: `!data.context.crossCorrelations.isEmpty`
- Sub-views:
  - 12a: `CorrelationMatrixChart` (new) — heatmap with max 8 metrics
  - 12b: Top 3 cards — each with `CorrelationScatterChart` (existing), r-value badge, 1-sentence narrative from `data.narratives.sectionNarratives["cross_N"]` or inline template
- Dependencies: 5.1 (matrix chart)
- Risk: Medium — matrix chart is the most complex new chart component

**6.14 `ActionPlanSection.swift`**
- Input: `ReportData.narratives.actionPlan`
- Condition: Always shown
- Layout: 3-5 recommendation cards. Each card: rounded rect with `WellnessDomain` accent tint, title (`.r(.headline, .bold)`), rationale (`.r(.subheadline, .regular)`), domain icon badge.
- Dependencies: 3.1
- Risk: Low

---

### Phase 7: Main Report View & Navigation

**7.1 Create `AI15DayReportView.swift`** (File: `WellPlate/Features + UI/Home/Views/AI15DayReportView.swift`)
- Action: Main scrollable view that:
  - Takes `@StateObject var viewModel = AI15DayReportViewModel()`
  - On appear: `viewModel.bindContext(modelContext); Task { await viewModel.generateReport() }`
  - Switch on `viewModel.reportState`:
    - `.idle` / `.generating(let progress)`: Centered `ProgressView` + "Analyzing your wellness data..." text + progress percentage label (e.g., "42%"). Same pattern as `InsightsHubView.loadingView`.
    - `.ready(let data)`: Render `ScrollView > LazyVStack(spacing: 24)` of sections, each with `insightEntrance(index:)` animation. Conditionally include each section based on data availability checks.
    - `.error(let message)`: Error state with message + "Retry" button
  - Section rendering order (each conditional):
    1. `ReportHeaderSection` (always)
    2. `ExecutiveSummarySection` (always)
    3. `StressDeepDiveSection` (if stress data)
    4. `NutritionSection` (if food data)
    5. `SleepSection` (if sleep data)
    6. `ActivitySection` (if activity data)
    7. `VitalsSection` (if any vital has data)
    8. `HydrationCaffeineSection` (if water/coffee data)
    9. `SymptomSection` (if symptom data)
    10. `SupplementSection` (if adherence data)
    11. `FastingSection` (if fasting data)
    12. `MoodSection` (if mood data)
    13. `CrossDomainSection` (if correlations found)
    14. `ActionPlanSection` (always)
  - Footer: "Generated at HH:mm" + "Regenerate" button (reuse `InsightsHubFooter` pattern)
  - Pass `data` (the `ReportData` struct) to each section view
- Why: Single view file orchestrates the scroll layout; delegates to section views
- Dependencies: 4.1, 6.1-6.14
- Risk: Low

**7.2 Update `InsightsHubView.swift`** (File: `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`)
- Action: Add a "Full Report" navigation entry point:
  - Add `@State private var showFullReport = false`
  - In the `cardFeed`, add a "View 15-Day Report" card between the header and the insight cards (index 1). Style it as a prominent branded card with sparkles icon + "Generate your comprehensive 15-day wellness report" subtitle.
  - Add `.navigationDestination(isPresented: $showFullReport) { AI15DayReportView() }`
- Why: User navigates: Home → InsightsHub → Full Report
- Dependencies: 7.1
- Risk: Low

---

### Phase 8: Update InsightEngine for New Fields

**8.1 Update `InsightEngine.buildWellnessContext()`** (File: `WellPlate/Core/Services/InsightEngine.swift`)
- Action: In the per-day loop (around line 212-240), after creating the `WellnessDaySummary`, mutate the new `var` fields:
  ```swift
  var summary = WellnessDaySummary(
      // ... existing arguments unchanged ...
  )
  // Populate report-specific fields
  summary.eatingTriggers = // aggregate from dayFood[].eatingTriggers
  summary.mealTypes = // aggregate from dayFood[].mealType
  summary.foodNames = dayFood.map(\.foodName)
  summary.coffeeType = wellness?.coffeeType
  summary.mealTimestamps = dayFood.map(\.createdAt)
  // Vitals (fetch these in the async let block above)
  summary.restingHeartRateAvg = restingHRData.first { ... }?.value
  summary.hrvAvg = hrvData.first { ... }?.value
  // ... etc for other vitals
  days.append(summary)
  ```
  - Also add `async let` fetches for restingHeartRate, HRV, BP systolic/diastolic, respiratoryRate, daylight in the concurrent HK fetch block (matching the existing pattern for steps/energy/heartRate/exercise/sleep).
- Why: Keeps the shared `WellnessDaySummary` complete so both hub cards and the full report can use the same enriched data. Since new fields are `var` with defaults, the existing `WellnessDaySummary(...)` init call is untouched — we just mutate after creation.
- Dependencies: 1.3
- Risk: Low — additive changes to existing loop, no changes to existing arguments

---

### Phase 9: Build Verification & Mock Support

**9.1 Add mock report data** (File: `ReportViewModel.swift`)
- Action: When `AppConfig.shared.mockMode` is true, skip data building and return a hardcoded `ReportData` with representative mock values for all sections. Follow the same pattern as `InsightEngine.mockInsights()`. Include:
  - 15 days of mock `WellnessDaySummary` with varied data
  - 3 mock `FoodSymptomLink` entries (1 trigger, 1 protective, 1 neutral-filtered)
  - 4 mock `CrossCorrelation` entries
  - 1 mock `InterventionResult`
  - 1 mock `ExperimentSummary`
  - Pre-written `ReportNarratives` (no FM calls needed)
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

## Additional Fields on WellnessDaySummary (consolidated from Phase 6 discoveries)

During Phase 6 design, several additional `var` fields were identified as needed on `WellnessDaySummary`. All should be added in Step 1.3 alongside the others:

```swift
// Stress detail (for volatility chart)
var stressMin: Double? = nil
var stressMax: Double? = nil
var stressReadingCount: Int = 0

// Meal timing (for heatmap)
var mealTimestamps: [Date] = []

// Vitals (for vitals section)
var restingHeartRateAvg: Double? = nil
var hrvAvg: Double? = nil
var systolicBPAvg: Double? = nil
var diastolicBPAvg: Double? = nil
var respiratoryRateAvg: Double? = nil
var daylightMinutes: Double? = nil
```

## Additional Fields on ReportContext (consolidated from Phase 6 discoveries)

```swift
// Top foods (for nutrition section 3f)
var topFoods: [(name: String, count: Int, totalCalories: Int)] = []

// Per-supplement adherence (for supplement section 9b)
var perSupplementAdherence: [(name: String, rate: Double)] = []
```

These should be computed in `ReportDataBuilder` (Step 2.1) and added to `ReportContext` (Step 1.1).

---

## Testing Strategy

- **Build verification**: All 4 targets must compile cleanly
- **Mock mode testing**: Toggle `AppConfig.shared.mockMode = true`, navigate to InsightsHub → "View 15-Day Report", verify all sections render with mock data
- **Manual verification flows**:
  - Report with full data (all sections visible)
  - Report with minimal data (e.g., only food logs — verify only nutrition section + executive summary + action plan appear)
  - Report with zero HealthKit vitals — verify vitals section is completely hidden
  - Report with symptoms but no food logs — verify symptom section appears but food-sensitivity table shows empty state
  - Foundation Models availability check — verify template fallback renders correctly on iOS < 26
  - "Regenerate" button clears cache and re-generates
  - Scroll performance — no jank on 15-day report with all sections
<!-- RESOLVED: L2 — Accessibility deferred to V2. Note: all charts should eventually get accessibilityLabel with key stats. -->
<!-- RESOLVED: L3 — Unit tests for ReportDataBuilder deferred to V2. MockHealthKitService and MockDataInjector exist for future test setup. -->

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Foundation Models unavailable or slow (~14-28s for 7 calls) | Medium | Template fallback covers all calls. Progress bar updates per-call. Cache results same-day. |
| Large number of new files (20) | Medium | Each file is focused. `PBXFileSystemSynchronizedRootGroup` handles auto-inclusion. |
| Scroll performance with many charts | Medium | `LazyVStack` for deferred rendering. Charts in fixed frames. Heavy charts use `Canvas`. |
| Food-symptom ratio edge cases | Medium | Require food >= 2 appearances. Guard div-by-zero. "May be associated" language. |
| `WellnessDaySummary` struct growing large | Low | All new fields are `var` with defaults. Struct is stack-allocated. |
| Correlation matrix readability on small screens | Low | Capped at 8 metrics. Abbreviated labels. Canvas fallback if needed. |

---

## Implementation Order Summary

| Phase | Steps | New Files | Modified Files | Estimated Complexity |
|---|---|---|---|---|
| 1: Models | 1.1-1.3 | 1 new | 1 modified (InsightModels) | Low |
| 2: Data Builder | 2.1-2.6 | 1 new | 0 | High |
| 3: Narrative Gen | 3.1-3.2 | 1 new | 0 | Medium |
| 4: ViewModel | 4.1 | 1 new | 0 | Low |
| 5: Charts | 5.1 | 1 new | 0 | Medium-High |
| 6: Section Views | 6.1-6.14 | 14 new | 0 | Medium (individually low) |
| 7: Main View + Nav | 7.1-7.2 | 1 new | 1 modified (InsightsHubView) | Low |
| 8: InsightEngine Update | 8.1 | 0 | 1 modified (InsightEngine) | Low-Medium |
| 9: Mock + Build | 9.1-9.2 | 0 | 0 | Low |

---

## Success Criteria

- [ ] All 4 build targets compile cleanly
- [ ] Report renders as a single scrollable view from InsightsHub
- [ ] All 13 sections appear with mock data when `mockMode = true`
- [ ] Sections with zero data are completely hidden (no headers, no empty states)
- [ ] HealthKit metrics with 0 samples in window do not appear anywhere in the report
- [ ] Goal comparison lines/stats appear on every applicable section
- [ ] Food-symptom correlation table shows specific food names with trigger ratios
- [ ] Cross-domain correlation matrix renders correctly with max 8 metrics
- [ ] Foundation Models generates narratives on iOS 26+ (~7 calls, progress bar shown)
- [ ] Template fallback produces readable narratives on iOS < 26
- [ ] Scroll performance is smooth (no dropped frames on iPhone 15)
- [ ] Intervention effectiveness shows pre/post stress comparison (4-hour window)
- [ ] Report caches for same day; "Regenerate" clears and re-runs
- [ ] `WellnessDaySummary` changes do not break existing `InsightEngine` code (var with defaults)
