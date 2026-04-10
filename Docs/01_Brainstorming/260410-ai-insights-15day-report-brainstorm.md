# Brainstorm: 15-Day AI Insights Report — Full Data Report Generation

**Date**: 2026-04-10
**Status**: Ready for Planning
**Depends on**: `260410-ai-insights-v2-brainstorm.md` (Approach 4 selected)

---

## Scope & Decisions (Locked)

| Decision | Choice |
|---|---|
| Format | Single scrollable view inside the existing AI Insights view |
| LLM engine | Foundation Models only (on-device, iOS 26+); template fallback for < 26 |
| Max lookback | 15 days (hard cap) |
| Min data requirement | None — render whatever exists, omit empty sections |
| Missing metric rule | If a HealthKit metric (HRV, BP, respiratory rate, etc.) has **zero** samples in the 15-day window, exclude it from the report entirely — no placeholder, no "no data" card |
| Journal entries | Excluded from the report |
| Eating trigger depth | Surface-level only (frequency counts, no nutritional comparison across triggers) |
| Symptom-food correlation | Detailed section — track specific foods (not just macros) against symptoms |
| Goal comparison | Yes — every section where UserGoals defines a target compares actuals vs goals |
| Historical comparison | Skipped for V1 (no "this period vs last period") |
| Intervention data | Include PMR/sigh effectiveness based on before/after stress readings (ignore nil HR/HRV Watch fields) |

---

## Complete Data Pipeline

### Data Sources (15-day window)

Every piece of data the report can consume, organised by origin:

#### SwiftData Models

| Model | Fields Used | Aggregation |
|---|---|---|
| `FoodLogEntry` | foodName, calories, protein, carbs, fat, fiber, mealType, eatingTriggers, hungerLevel, presenceLevel, createdAt (for meal timing), logSource | Per-day totals + per-meal breakdown |
| `WellnessDayLog` | moodRaw, waterGlasses, exerciseMinutes, caloriesBurned, steps, stressLevel, coffeeCups, coffeeType | Per-day (one row per day) |
| `StressReading` | score, levelLabel, timestamp, source | Multiple per day — avg, min, max, count per day + intra-day volatility |
| `SymptomEntry` | name, category, severity, timestamp, notes | Per-day: max severity, symptom list; cross-period: frequency counts |
| `SupplementEntry` | name, dosage, category, scheduledTimes, activeDays, isActive | Reference data for adherence context |
| `AdherenceLog` | supplementName, supplementID, day, status (taken/skipped/pending) | Per-day adherence rate, per-supplement breakdown |
| `FastingSession` | startedAt, targetEndAt, actualEndAt, completed, scheduleType | Per-session: duration, completion; aggregate: completion rate, avg duration |
| `InterventionSession` | resetType, startedAt, durationSeconds, completed | Pre/post stress comparison (stress readings before vs after session timestamp) |
| `StressExperiment` | name, hypothesis, interventionType, startDate, durationDays, cachedBaselineAvg, cachedExperimentAvg, cachedDelta, cachedCILow, cachedCIHigh | Active/completed experiments within window |
| `UserGoals` | All goal fields | Reference for vs-goal comparisons |

#### HealthKit (via `HealthKitServiceProtocol`)

| Metric | Method | Unit | Inclusion Rule |
|---|---|---|---|
| Steps | `fetchSteps(for:)` | count | Include if >= 1 sample in 15 days |
| Active Energy | `fetchActiveEnergy(for:)` | kcal | Include if >= 1 sample |
| Exercise Minutes | `fetchExerciseMinutes(for:)` | min | Include if >= 1 sample |
| Heart Rate (avg) | `fetchHeartRate(for:)` | BPM | Include if >= 1 sample |
| Resting Heart Rate | `fetchRestingHeartRate(for:)` | BPM | Include if >= 1 sample in **all 15 days checked** — if any day has data, include; if zero days have data, exclude entirely |
| HRV (SDNN) | `fetchHRV(for:)` | ms | **Zero-tolerance**: exclude from report if 0 samples in window |
| BP Systolic | `fetchBloodPressureSystolic(for:)` | mmHg | Zero-tolerance |
| BP Diastolic | `fetchBloodPressureDiastolic(for:)` | mmHg | Zero-tolerance |
| Respiratory Rate | `fetchRespiratoryRate(for:)` | breaths/min | Zero-tolerance |
| Sleep | `fetchDailySleepSummaries(for:)` | hours + stages | Include if >= 1 night |
| Daylight | `fetchDaylight(for:)` | min | Zero-tolerance |

**Zero-tolerance rule**: Fetch all metrics. If the returned array is empty (`.isEmpty == true`), that metric does not appear anywhere in the report — not in section headers, not in correlations, not in the LLM prompt. This prevents the LLM from hallucinating about data it doesn't have.

---

## Report Sections (Top to Bottom Scroll Order)

### Section 0: Report Header

- Title: "Your 15-Day Wellness Report"
- Subtitle: date range "Mar 26 - Apr 10, 2026"
- Data quality badge: "Based on X days of data across Y domains"
- Animated entrance

---

### Section 1: Executive Summary

**Data used**: All domains (composite)
**Chart**: None (text only)
**LLM-generated**: Yes

A 3-4 sentence narrative summarising the entire 15-day period. Covers:
- Overall trajectory: improving / steady / declining
- Biggest win (e.g., "7-day water streak")
- Biggest concern (e.g., "protein consistently below goal")
- One cross-domain observation (e.g., "sleep and stress appear linked")

**Foundation Models prompt context**:
- Provide per-day summary array (all fields)
- Instruct: "Write a 3-4 sentence executive summary. Use 'may suggest' framing. No medical claims. Reference specific numbers. Mention the strongest positive habit and the most actionable area for improvement."

**`@Generable` schema**:
```swift
@Generable
struct ReportExecutiveSummary {
    @Guide(description: "3-4 sentence narrative summary of the 15-day period")
    var narrative: String
    @Guide(description: "Single strongest positive finding, max 60 chars")
    var topWin: String
    @Guide(description: "Single most actionable improvement area, max 60 chars")
    var topConcern: String
}
```

---

### Section 2: Stress Deep-Dive

**Data used**: `StressReading`, `WellnessDayLog.stressLevel`, stress factor scores (exercise, sleep, diet, screen time)
**Condition**: At least 1 `StressReading` exists in window
**Goal comparison**: N/A (no stress goal in UserGoals)

#### 2a. Stress Trend
- **Chart**: `LineMark` — 15-day daily average stress score
- **Annotations**: Horizontal band at 50 (moderate threshold)
- **Stat pills**: Period avg, best day (lowest), worst day (highest), trend direction

#### 2b. Stress Volatility
- **Chart**: `RuleMark` range bars — daily min/max stress spread
- **Metric**: Std deviation of intra-day readings averaged across period
- **Insight**: "Your stress varied by X points within a typical day"

#### 2c. Factor Decomposition
- **Chart**: Stacked horizontal `BarMark` — for the top 3 highest-stress days vs top 3 lowest-stress days
- Show which factors (exercise 0-25, sleep 0-25, diet 0-25, screen time 0-25) differed most
- Use `StressScoring.exerciseScore()`, `.sleepScore()`, `.dietScore()`, `.screenTimeScore()` to recompute per-day

#### 2d. Best vs Worst Day
- **Layout**: Two side-by-side cards
- **Content**: The day with lowest avg stress vs highest avg stress
  - Each card shows: stress score, sleep hours, steps, calories, coffee cups, mood
  - Highlight the biggest delta between the two days

#### 2e. Intervention Effectiveness (conditional)
- **Condition**: At least 1 completed `InterventionSession` in window
- **Method**: For each session, find the closest `StressReading` before `startedAt` and after `startedAt + durationSeconds`. Compute delta.
- **Chart**: Grouped `BarMark` — pre vs post stress for each session type (PMR, Sigh)
- **Stat**: Average stress reduction per intervention type
- **Note**: If pre/post readings don't exist within 2 hours of session, skip that session

#### 2f. Experiment Results (conditional)
- **Condition**: At least 1 `StressExperiment` overlapping the 15-day window
- **Content**: Hypothesis, baseline avg vs experiment avg, delta, confidence interval
- **Chart**: `BarMark` comparison — baseline vs experiment with CI error bars

---

### Section 3: Nutrition Intelligence

**Data used**: `FoodLogEntry` (all fields), `UserGoals` (calorie, macro goals)
**Condition**: At least 1 `FoodLogEntry` exists in window
**Goal comparison**: Calories, protein, carbs, fat, fiber vs UserGoals

#### 3a. Calorie Trend
- **Chart**: `BarMark` — daily total calories with `RuleMark` goal line
- **Stat pills**: Period avg, days over goal, days under goal, total deficit/surplus
- **Color**: Bars tinted green (within 10% of goal), amber (10-20% off), red (>20% off)

#### 3b. Macro Balance Radar
- **Chart**: Custom radar/spider chart (Canvas + Path)
- **Axes**: Protein, Carbs, Fat, Fiber (4-axis)
- **Layers**: Actual 15-day average (filled) vs Goal (outline)
- **Stat**: Per-macro: "Protein: 72g avg vs 150g goal (48%)"

#### 3c. Meal Timing Heatmap
- **Chart**: `RectangleMark` grid — X = day, Y = hour bucket (6am-10am, 10am-2pm, 2pm-6pm, 6pm-10pm, 10pm+)
- **Color intensity**: Number of meals logged in that bucket
- **Insight**: "You eat most frequently between X and Y"
- Derived from `FoodLogEntry.createdAt` timestamp

#### 3d. Meal Type Distribution
- **Chart**: Horizontal `BarMark` — count of breakfast / lunch / dinner / snack / untagged
- **Insight**: "You logged X breakfasts out of Y days" (detect meal skipping patterns)

#### 3e. Eating Triggers (Surface Level)
- **Chart**: Horizontal `BarMark` — frequency count of each `EatingTrigger` across all meals
- **Content**: Simple ranked list: "Hungry: 24 meals, Stressed: 8 meals, Bored: 5 meals"
- No cross-referencing with nutritional content (per user decision)

#### 3f. Top Foods
- **Layout**: Ranked list (top 10)
- **Content**: Most frequently logged foods by count, with total calories contributed
- **Insight**: "Your top 5 foods account for X% of total calories"

#### 3g. Food Variety Score
- **Metric**: Count of unique `foodName` values in window
- **Benchmark**: < 10 = "Limited variety", 10-20 = "Moderate", 20+ = "Good variety"

---

### Section 4: Sleep Report

**Data used**: `DailySleepSummary` (from HealthKit), `UserGoals.sleepGoalHours`
**Condition**: At least 1 sleep summary exists in window
**Goal comparison**: Total hours vs sleepGoalHours

#### 4a. Sleep Duration Trend
- **Chart**: Stacked `BarMark` — deep (purple), REM (indigo), core (blue) per night
- **Overlay**: `RuleMark` goal line at `sleepGoalHours`
- **Stat pills**: Period avg, nights meeting goal, best night, worst night

#### 4b. Deep Sleep Ratio
- **Chart**: `LineMark` — daily deep sleep % (deepHours / totalHours * 100)
- **Benchmark line**: 15-20% is healthy range
- **Trend**: First half vs second half comparison (already in InsightEngine)

#### 4c. Bedtime Consistency
- **Chart**: `PointMark` scatter — X = day, Y = bedtime (as hour:min)
- **Also**: Separate scatter for wake time
- **Metric**: Standard deviation of bedtime → "Your bedtime varies by +/- X minutes"
- **Insight**: Consistency score (low std dev = good)

#### 4d. Sleep-Stress Link (conditional)
- **Condition**: Both sleep and stress data exist for >= 5 overlapping days
- **Chart**: `PointMark` scatter — X = sleep hours, Y = next-day stress score
- **Stat**: Spearman r-value, "On 7h+ nights, your next-day stress averaged X vs Y"
- Uses `CorrelationMath.spearmanR()`

---

### Section 5: Activity & Movement

**Data used**: HealthKit steps, activeEnergy, exerciseMinutes; `UserGoals`
**Condition**: At least 1 step/energy sample exists
**Goal comparison**: Steps vs dailyStepsGoal, energy vs activeEnergyGoalKcal

#### 5a. Steps Trend
- **Chart**: `BarMark` — daily steps with `RuleMark` goal line
- **Overlay**: 7-day rolling average `LineMark`
- **Stat pills**: Period avg, days meeting goal, best day, total steps

#### 5b. Active Energy Trend
- **Chart**: `AreaMark` — daily active calories
- **Goal line**: `activeEnergyGoalKcal`

#### 5c. Exercise Minutes
- **Chart**: `BarMark` — daily exercise minutes
- **Goal**: Per-day workout goal from `UserGoals.workoutMinutes(for:)` (varies by weekday)
- **Insight**: "You met your exercise goal on X of Y planned workout days"

#### 5d. Movement-Stress Link (conditional)
- **Condition**: Steps + stress data for >= 5 days
- **Chart**: `PointMark` scatter — X = steps, Y = stress score
- **Stat**: Spearman r-value

---

### Section 6: Vitals Dashboard (conditional)

**Data used**: HealthKit heart rate, resting HR, HRV, BP, respiratory rate
**Condition**: Section appears ONLY if at least one vital metric has data
**Each sub-section**: Only rendered if that specific metric has >= 1 sample

#### 6a. Heart Rate Trend
- **Chart**: `LineMark` — daily avg HR
- **Stat**: Period avg, min day, max day

#### 6b. Resting Heart Rate Trend
- **Chart**: `LineMark` — daily resting HR
- **Stat**: Period avg + direction (lower is generally better)

#### 6c. HRV Trend
- **Chart**: `LineMark` — daily HRV (ms)
- **Stat**: Period avg + direction (higher is generally better)
- **Benchmark**: "Your HRV averaged Xms — typical range for your age is Y-Z"

#### 6d. Blood Pressure
- **Chart**: Dual `LineMark` — systolic (top) + diastolic (bottom) daily avg
- **Benchmark bands**: Normal (< 120/80), Elevated (120-129), High (130+)

#### 6e. Respiratory Rate
- **Chart**: `LineMark` — daily avg breaths/min
- **Normal band**: 12-20 breaths/min

---

### Section 7: Hydration & Caffeine

**Data used**: `WellnessDayLog.waterGlasses`, `.coffeeCups`, `.coffeeType`; `UserGoals`
**Condition**: At least 1 WellnessDayLog with waterGlasses > 0 or coffeeCups > 0
**Goal comparison**: Water vs waterDailyCups, coffee vs coffeeDailyCups

#### 7a. Water Intake Trend
- **Chart**: `BarMark` — daily water glasses with `RuleMark` goal line
- **Stat pills**: Period avg, days meeting goal, streak info

#### 7b. Coffee Intake Trend
- **Chart**: `BarMark` — daily coffee cups with `RuleMark` goal line (4 cups)
- **Coffee type breakdown**: Pie or horizontal bar of coffee types used

#### 7c. Caffeine-Stress Link (conditional)
- **Condition**: Coffee + stress data for >= 5 days
- **Chart**: Grouped comparison bars — avg stress on 0-2 cup days vs 3+ cup days
- **Stat**: Spearman r-value

---

### Section 8: Symptom Analysis & Food Sensitivity

**Data used**: `SymptomEntry`, `FoodLogEntry`, `StressReading`
**Condition**: At least 1 `SymptomEntry` exists in window

#### 8a. Symptom Frequency
- **Chart**: Horizontal `BarMark` — each symptom name ranked by occurrence count
- **Color**: By category (digestive = orange, pain = red, energy = amber, cognitive = purple)
- **Stat**: Total symptom days, most common symptom, avg severity

#### 8b. Symptom Severity Timeline
- **Chart**: `PointMark` — X = day, Y = max severity that day, size = number of symptoms
- **Overlay**: Stress trend line (secondary Y-axis) to visually show co-occurrence

#### 8c. Symptom Category Breakdown
- **Chart**: Donut/pie — % of symptom entries by category
- **Insight**: "68% of your symptoms are digestive"

#### 8d. Food-Symptom Correlations (Detailed)

This is the detailed section. Goes beyond macro-level to specific foods.

**Method**:
1. For each symptom that appeared >= 3 times in the window:
   - Identify all unique foods logged on symptom days (same day, or day before for delayed reactions)
   - Identify all unique foods logged on symptom-free days
   - Compute frequency ratio: `(food appears on symptom days %) / (food appears on non-symptom days %)`
   - Flag foods with ratio > 2.0 as "potential triggers"
   - Flag foods with ratio < 0.5 as "potential protective"
2. Also run existing `SymptomCorrelationEngine` for macro-level correlations (calories, protein, fiber, caffeine, water, stress, sleep, supplement adherence)

**Chart**: Table/list view for each symptom:
```
Bloating (appeared 6 days)
  Potential triggers:
    - Dairy (appeared 5/6 symptom days, only 2/9 clear days) — ratio 3.75x
    - White bread (4/6 vs 1/9) — ratio 6.0x
  Potential protective:
    - Greek yogurt (1/6 vs 5/9) — ratio 0.3x
  Macro correlations:
    - Fat: moderate positive (r=0.42)
    - Fiber: weak negative (r=-0.28)
```

**Caveats**: Display "Correlations require more data to confirm" for any finding with < 7 paired days. Use "may be associated" language.

#### 8e. Symptom-Stress Link
- **Chart**: `PointMark` scatter — X = stress score, Y = symptom severity
- **Stat**: Spearman r, "On high-stress days (60+), symptom severity averaged X vs Y on calm days"

---

### Section 9: Supplement Adherence

**Data used**: `SupplementEntry`, `AdherenceLog`
**Condition**: At least 1 active `SupplementEntry` exists

#### 9a. Overall Adherence Rate
- **Chart**: `Gauge` or progress ring — % taken vs scheduled across 15 days
- **Stat**: "You took X of Y scheduled doses (Z%)"

#### 9b. Per-Supplement Breakdown
- **Chart**: Horizontal `BarMark` — adherence % per supplement, sorted worst to best
- **Color**: Green (>= 80%), amber (50-79%), red (< 50%)

#### 9c. Adherence-Symptom Link (conditional)
- **Condition**: Both supplement and symptom data exist for >= 5 days
- **Method**: Spearman correlation between daily adherence rate and symptom severity
- **Insight**: "On days with 100% supplement adherence, symptom severity averaged X vs Y"

---

### Section 10: Fasting Performance

**Data used**: `FastingSession`
**Condition**: At least 1 completed `FastingSession` in window

#### 10a. Fasting Summary
- **Stat cards**: Total sessions, completion rate (%), avg actual duration vs target, longest fast
- **Chart**: `BarMark` — per-session duration with `RuleMark` at target

#### 10b. Fasting-Stress Link (conditional)
- **Condition**: >= 3 fasting days and >= 3 non-fasting days with stress data
- **Chart**: Comparison bars — avg stress on fasting days vs non-fasting days
- **Stat**: Delta + direction

---

### Section 11: Mood Overview

**Data used**: `WellnessDayLog.moodRaw`
**Condition**: At least 1 day with mood logged

#### 11a. Mood Distribution
- **Chart**: Horizontal `BarMark` — count of each MoodOption (0-4)
- **Stat**: Most common mood, mood logged X of 15 days

#### 11b. Mood-Stress Alignment
- **Chart**: Dual-axis `LineMark` — mood (inverted, lower=better) and stress score overlaid
- **Insight**: "Your mood self-report matches computed stress X% of the time"

---

### Section 12: Cross-Domain Correlations

**Data used**: All available domains
**Condition**: At least 2 domains have >= 5 days of data

#### 12a. Correlation Matrix
- **Chart**: Heatmap grid (`RectangleMark`) — rows and columns are metrics, color = r-value
  - Only include metrics that have data (per zero-tolerance rule)
  - Only color cells where |r| >= 0.3 AND CI doesn't span zero
  - Grey out / leave blank insignificant pairs

**Metric pairs to test** (filtered by availability):
- Sleep hours ↔ Stress score
- Steps ↔ Stress score
- Coffee cups ↔ Stress score
- Coffee cups ↔ Sleep hours
- Protein ↔ Stress score
- Fiber ↔ Stress score
- Water ↔ Stress score
- Exercise minutes ↔ Stress score
- Sleep hours ↔ Steps
- Calories ↔ Steps
- Fasting (binary) ↔ Stress score
- Supplement adherence ↔ Symptom severity
- Heart rate ↔ Stress score (if HR data exists)

#### 12b. Top 3 Strongest Links
- **Layout**: 3 highlight cards, each with:
  - Scatter plot (`PointMark`)
  - r-value badge
  - 1-sentence LLM-generated interpretation
  - "may suggest" disclaimer

---

### Section 13: Personalised Action Plan

**Data used**: All insights from sections above
**LLM-generated**: Yes (Foundation Models)

3-5 ranked, specific, actionable recommendations derived from the data. Not generic advice.

**Foundation Models prompt context**:
- Feed the top findings from each section (summary stats, not raw data)
- Instruct: "Based on these findings, generate 3-5 specific, actionable recommendations ranked by potential impact. Each recommendation must reference a specific data point. Use 'consider' and 'may help' framing. No medical advice."

**`@Generable` schema**:
```swift
@Generable
struct ReportActionPlan {
    @Guide(description: "3-5 actionable recommendations, most impactful first")
    var recommendations: [ActionRecommendation]
}

@Generable
struct ActionRecommendation {
    @Guide(description: "Short title, max 50 chars, e.g. 'Prioritize 7.5h sleep'")
    var title: String
    @Guide(description: "1-2 sentences explaining why, referencing specific data")
    var rationale: String
    @Guide(description: "Which wellness domain this targets")
    var domain: String
}
```

---

## Foundation Models Strategy

### Prompt Architecture

The report makes **3 Foundation Models calls** (batched, not per-section):

| Call | Input | Output Schema | Token Budget |
|---|---|---|---|
| 1. Executive Summary | Full `WellnessDaySummary` array (15 days, all fields) | `ReportExecutiveSummary` | ~2000 input tokens |
| 2. Section Narratives | Per-section summary stats (not raw data) | `ReportSectionNarratives` | ~1500 input tokens |
| 3. Action Plan | Top findings from all sections | `ReportActionPlan` | ~1000 input tokens |

### Pre-Aggregation for Prompt

Raw data is too large for on-device model context. Pre-aggregate into a `ReportPromptContext`:

```
Period: Mar 26 - Apr 10 (15 days, 12 with data)

Stress: avg 52, range 28-78, trending down, best day Apr 8 (28), worst Mar 29 (78)
Sleep: avg 6.8h, goal 8h, 4/12 nights met goal, deep sleep ratio 18% (improving)
Steps: avg 7,420, goal 10,000, 3/12 days met goal, trending up
Calories: avg 1,680, goal 2,000, protein avg 72g (goal 150g), fiber avg 18g (goal 30g)
Water: avg 5.2 cups, goal 8, met goal 2/12 days
Coffee: avg 2.8 cups, goal 4
Symptoms: Bloating 6 days (severity avg 5.2), Headache 3 days (severity avg 4.0)
Supplements: 68% adherence (Vitamin D best at 92%, Omega-3 worst at 41%)
Fasting: 4 sessions, 75% completion, avg 14.2h
Interventions: 3 PMR sessions, avg stress drop -8 points
Correlations: Sleep↔Stress r=-0.58, Coffee↔Stress r=0.34
Top trigger foods for Bloating: dairy (3.75x), white bread (6.0x)
```

This fits comfortably in Foundation Models context and gives the LLM everything it needs.

### Template Fallback (iOS < 26)

Each section has a rule-based template that generates narratives from the same pre-aggregated data:
- Trend: "[Metric] has been [rising/falling/steady] over 15 days, averaging [X] against a goal of [Y]."
- Correlation: "[A] and [B] show a [strength] [direction] association (r = [X])."
- Action: "Consider [action] — your data suggests [metric] may benefit from [change]."

---

## Data Model Additions

### `WellnessDaySummary` — Already Sufficient

The existing `WellnessDaySummary` in `InsightModels.swift` already captures all needed fields:
- stress, sleep (hours + deep + REM + bedtime + wake), steps, activeCalories, exerciseMinutes, heartRateAvg
- totalCalories, totalProteinG, totalCarbsG, totalFatG, totalFiberG, mealCount
- waterGlasses, coffeeCups, moodLabel, symptomNames, symptomMaxSeverity
- fastingHours, fastingCompleted, supplementAdherence, journalLogged

**Additions needed for the report**:
- `eatingTriggers: [String: Int]` — trigger frequency count per day
- `mealTypes: [String: Int]` — meal type count per day (breakfast: 1, lunch: 1, etc.)
- `foodNames: [String]` — list of foods logged that day (for food-symptom correlation)
- `interventionSessions: [(type: String, stressDelta: Double?)]` — intervention results per day

### New: `ReportContext` (extends `WellnessContext`)

```swift
struct ReportContext {
    let days: [WellnessDaySummary]  // Extended version
    let goals: UserGoalsSnapshot
    let availableVitals: Set<VitalMetricType>  // Which HK vitals have data
    let foodSymptomCorrelations: [FoodSymptomLink]
    let crossDomainCorrelations: [CrossCorrelation]
    let interventionResults: [InterventionResult]
    let experimentResults: [ExperimentResult]
    let dataQualityNote: String
}
```

### New: `FoodSymptomLink`

```swift
struct FoodSymptomLink {
    let symptomName: String
    let foodName: String
    let symptomDayAppearance: Int    // times food appeared on symptom days
    let clearDayAppearance: Int      // times food appeared on clear days
    let ratio: Double                // symptomDayRate / clearDayRate
    let classification: Classification // .potentialTrigger, .potentialProtective, .neutral
}
```

---

## View Architecture

```
InsightsHubView (existing)
└── AI15DayReportView (new, single scrollable view)
    ├── ReportHeaderSection
    ├── ExecutiveSummarySection
    ├── StressDeepDiveSection
    │   ├── StressTrendChart
    │   ├── StressVolatilityChart
    │   ├── FactorDecompositionChart
    │   ├── BestWorstDayComparison
    │   ├── InterventionEffectivenessChart (conditional)
    │   └── ExperimentResultsChart (conditional)
    ├── NutritionSection
    │   ├── CalorieTrendChart
    │   ├── MacroRadarChart
    │   ├── MealTimingHeatmap
    │   ├── MealTypeDistribution
    │   ├── EatingTriggerFrequency
    │   ├── TopFoodsList
    │   └── FoodVarietyScore
    ├── SleepSection
    │   ├── SleepDurationStackedChart
    │   ├── DeepSleepRatioChart
    │   ├── BedtimeConsistencyChart
    │   └── SleepStressLinkChart (conditional)
    ├── ActivitySection
    │   ├── StepsTrendChart
    │   ├── ActiveEnergyChart
    │   ├── ExerciseMinutesChart
    │   └── MovementStressLinkChart (conditional)
    ├── VitalsSection (conditional — only if any vital has data)
    │   ├── HeartRateChart (conditional)
    │   ├── RestingHRChart (conditional)
    │   ├── HRVChart (conditional)
    │   ├── BloodPressureChart (conditional)
    │   └── RespiratoryRateChart (conditional)
    ├── HydrationCaffeineSection
    │   ├── WaterTrendChart
    │   ├── CoffeeTrendChart
    │   └── CaffeineStressLinkChart (conditional)
    ├── SymptomSection (conditional)
    │   ├── SymptomFrequencyChart
    │   ├── SymptomSeverityTimeline
    │   ├── SymptomCategoryBreakdown
    │   ├── FoodSensitivityTable (detailed)
    │   └── SymptomStressLinkChart
    ├── SupplementSection (conditional)
    │   ├── OverallAdherenceGauge
    │   ├── PerSupplementBreakdown
    │   └── AdherenceSymptomLink (conditional)
    ├── FastingSection (conditional)
    │   ├── FastingSummaryCards
    │   └── FastingStressLink (conditional)
    ├── MoodSection (conditional)
    │   ├── MoodDistribution
    │   └── MoodStressAlignment
    ├── CrossDomainSection
    │   ├── CorrelationMatrix
    │   └── Top3StrongestLinks
    └── ActionPlanSection
        └── RecommendationCards (3-5)
```

---

## ViewModel

```swift
@MainActor
final class AI15DayReportViewModel: ObservableObject {
    @Published var reportState: ReportState = .idle  // .idle, .generating, .ready(ReportData), .error
    @Published var generationProgress: Double = 0    // 0-1 for progress indicator

    private let insightEngine: InsightEngine
    private var modelContext: ModelContext?

    func generateReport() async {
        // 1. Fetch all data (parallel HK + SwiftData)        → progress 0.3
        // 2. Build ReportContext (aggregation + correlations)  → progress 0.6
        // 3. Foundation Models calls (3 calls)                 → progress 0.9
        // 4. Assemble ReportData                               → progress 1.0
    }
}
```

---

## Performance Considerations

- **Data fetch**: All SwiftData queries use date-predicated `FetchDescriptor`. All HealthKit fetches run concurrently via `async let`.
- **Correlation computation**: `CorrelationMath.spearmanR()` + `bootstrapCI()` run on `Task.detached(priority: .userInitiated)` to avoid blocking main actor.
- **Food-symptom analysis**: O(foods * symptoms * days) — with 15 days, max ~50 unique foods, ~10 symptoms = ~7,500 comparisons. Trivial.
- **Foundation Models**: 3 sequential calls (structured output). Expected ~2-4 seconds each on A17+. Show progress bar.
- **Scroll performance**: Use `LazyVStack` for the report. Charts are rendered in fixed-size frames. Heavy charts (heatmap, radar) use `Canvas` for GPU rendering.
- **Caching**: Cache the generated report for the current day. Invalidate on new data entry (food log, supplement taken, etc.) or manual refresh.

---

## Open Questions for Planning Phase

1. Should the report have section anchors / table of contents at the top for quick navigation?
2. Should we support "share as image" for individual sections?
3. Should the report animate section-by-section as user scrolls (staggered entrance) or load all at once?
4. What's the loading UX while Foundation Models generates? Shimmer placeholders per section?
