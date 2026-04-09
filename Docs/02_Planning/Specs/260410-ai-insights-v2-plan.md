# Implementation Plan: AI Insights V2

## Overview

Replace the stress-only `HomeAIInsightView` with a three-layer progressive disclosure insights system: (1) a compact `DailyInsightCard` on the home screen, (2) a scrollable `InsightsHubView` showing prioritised insight cards across all wellness domains, and (3) `InsightDetailSheet` for deep dives. All powered by a unified `InsightEngine` service that aggregates data from 8 SwiftData models + HealthKit, detects patterns/trends/correlations/milestones, generates narratives via Foundation Models (with template fallback), and caches results per day.

## Requirements

- Multi-domain insights covering: stress, nutrition (macros, fiber, meal count), sleep (total, deep), activity (steps, calories), hydration, caffeine, mood, symptoms, and fasting
- 6 insight types: Trend Alert, Correlation Discovery, Goal Milestone, Macro Imbalance, Sleep Quality, Positive Reinforcement
- Charts per insight type: area trend, scatter plot, comparison bars, macro radar, milestone ring, sparkline
- Foundation Models narrative generation with `@Generable` + template fallback for iOS < 26
- Same-day caching; 14-day lookback window
- Staggered entrance animations; haptic feedback on generation
- Mock mode support matching the `AppConfig.shared.mockMode` pattern
- Graceful degradation when data is insufficient per insight type

## Architecture Changes

| File | Action | Description |
|---|---|---|
| `WellPlate/Features + UI/Home/Models/InsightModels.swift` | **Create** | Value types: `WellnessDaySummary`, `InsightCard`, `InsightType`, `WellnessDomain`, `InsightChartData` |
| `WellPlate/Core/Services/InsightEngine.swift` | **Create** | Unified insight generation service: data aggregation, detection, prioritisation, FM narratives, template fallback |
| `WellPlate/Core/Services/CorrelationMath.swift` | **Create** | Extract Spearman + bootstrap CI from `SymptomCorrelationEngine` into a shared utility |
| `WellPlate/Features + UI/Home/Components/InsightCharts.swift` | **Create** | Reusable chart subviews: `TrendAreaChart`, `CorrelationScatterChart`, `ComparisonBarChart`, `MacroRadarChart`, `MilestoneRingView`, `SparklineView` |
| `WellPlate/Features + UI/Home/Components/InsightCardView.swift` | **Create** | Reusable card component rendering any `InsightCard` |
| `WellPlate/Features + UI/Home/Components/DailyInsightCard.swift` | **Create** | Compact home screen card with sparkline and headline |
| `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` | **Create** | Scrollable feed of `InsightCardView` instances |
| `WellPlate/Features + UI/Home/Views/InsightDetailSheet.swift` | **Create** | Deep-dive modal with full-size chart + extended narrative + suggestions |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | **Modify** | Replace `StressInsightService` with `InsightEngine`, add `DailyInsightCard`, update navigation |
| `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift` | **Modify** | Update `onSeeInsight` to navigate to new `InsightsHubView` |
| `WellPlate/Core/Services/SymptomCorrelationEngine.swift` | **Modify** | Delegate Spearman/CI to shared `CorrelationMath` |

---

## Implementation Steps

### Phase 1: Data Models & Correlation Utility

#### Step 1.1: Create `InsightModels.swift`
**File**: `WellPlate/Features + UI/Home/Models/InsightModels.swift`
**Action**: Create new file with all value types the system needs
**Dependencies**: None
**Risk**: Low

```swift
// WellnessDomain — which health domain an insight covers
enum WellnessDomain: String, CaseIterable {
    case stress, nutrition, sleep, activity, hydration, caffeine, mood, fasting, symptoms, cross
    
    var label: String { ... }   // "Stress", "Nutrition", etc.
    var icon: String { ... }    // SF Symbol per domain
    var accentColor: Color { ... } // From AppColors tokens
}

// InsightType — what kind of insight this is
enum InsightType: String, CaseIterable {
    case trend          // 3+ day directional change
    case correlation    // Cross-domain r-value finding
    case milestone      // Streak or first-time goal hit
    case imbalance      // Macro/sleep/hydration deficit
    case sleepQuality   // Deep sleep ratio or consistency change
    case reinforcement  // Positive habit acknowledgement
    
    var label: String { ... }   // "Trend", "Pattern", etc.
    var icon: String { ... }    // SF Symbol per type
}

// InsightChartData — drives which chart renders in the card
enum InsightChartData {
    case trendLine(points: [(date: Date, value: Double)], goalLine: Double?, metricLabel: String, unit: String)
    case correlationScatter(points: [(x: Double, y: Double)], r: Double, xLabel: String, yLabel: String)
    case comparisonBars(bars: [(label: String, value: Double, color: Color)], highlight: Int?)
    case macroRadar(actual: [String: Double], goals: [String: Double])
    case milestoneRing(current: Int, target: Int, streakLabel: String)
    case sparkline(points: [Double])  // For compact DailyInsightCard
}

// InsightCard — single insight to render
struct InsightCard: Identifiable {
    let id: UUID
    let type: InsightType
    let domain: WellnessDomain
    let headline: String              // Max ~60 chars
    let narrative: String             // 1-3 sentences
    let chartData: InsightChartData
    let priority: Double              // 0-1, higher = more important
    let isLLMGenerated: Bool
    let generatedAt: Date
    let detailSuggestions: [String]   // For InsightDetailSheet (2-3 items)
}

// WellnessDaySummary — expanded from StressInsightDaySummary
// One per calendar day in the lookback window
struct WellnessDaySummary {
    let date: Date
    // Stress
    let stressScore: Double?
    let stressLabel: String?
    // Sleep
    let sleepHours: Double?
    let deepSleepHours: Double?
    let remSleepHours: Double?
    let bedtime: Date?
    let wakeTime: Date?
    // Activity
    let steps: Int?
    let activeCalories: Int?
    let exerciseMinutes: Int?
    let heartRateAvg: Double?
    // Nutrition
    let totalCalories: Int?
    let totalProteinG: Double?
    let totalCarbsG: Double?
    let totalFatG: Double?
    let totalFiberG: Double?
    let mealCount: Int
    // Hydration & Caffeine
    let waterGlasses: Int?
    let coffeeCups: Int?
    // Mood
    let moodLabel: String?
    // Symptoms
    let symptomNames: [String]
    let symptomMaxSeverity: Int?
    // Fasting
    let fastingHours: Double?
    let fastingCompleted: Bool?
    // Supplements
    let supplementAdherence: Double?  // 0-1 ratio of taken/scheduled
    // Journal
    let journalLogged: Bool
}

// WellnessContext — full aggregated context for insight generation
struct WellnessContext {
    let days: [WellnessDaySummary]         // Oldest first
    let goals: UserGoalsSnapshot           // Immutable copy of UserGoals at generation time
    let dataQualityNote: String            // Describes missing categories
}

// UserGoalsSnapshot — immutable copy (avoids SwiftData threading issues)
struct UserGoalsSnapshot {
    let calorieGoal: Int
    let proteinGoalGrams: Int
    let carbsGoalGrams: Int
    let fatGoalGrams: Int
    let fiberGoalGrams: Int
    let waterDailyCups: Int
    let coffeeDailyCups: Int
    let dailyStepsGoal: Int
    let activeEnergyGoalKcal: Int
    let sleepGoalHours: Double
    
    init(from goals: UserGoals) { ... }
}
```

#### Step 1.2: Create `CorrelationMath.swift`
**File**: `WellPlate/Core/Services/CorrelationMath.swift`
**Action**: Extract Spearman + bootstrap CI from `SymptomCorrelationEngine` into a `nonisolated` enum
**Dependencies**: None
**Risk**: Low

Extract these functions from `SymptomCorrelationEngine.swift` (lines 146-223):
- `spearmanR(_:_:) -> Double`
- `ranks(of:) -> [Double]`
- `pearsonR(_:_:) -> Double`
- `bootstrapCI(xValues:yValues:iterations:) -> (low: Double, high: Double)`
- `interpretationLabel(r:ciSpansZero:) -> String`

Place in:
```swift
enum CorrelationMath {
    nonisolated static func spearmanR(_ x: [Double], _ y: [Double]) -> Double { ... }
    nonisolated static func bootstrapCI(xValues: [Double], yValues: [Double], iterations: Int = 1000) -> (low: Double, high: Double) { ... }
    nonisolated static func interpretationLabel(r: Double, ciSpansZero: Bool) -> String { ... }
    // Private helpers: ranks(of:), pearsonR(_:_:)
}
```

#### Step 1.3: Update `SymptomCorrelationEngine` to use shared `CorrelationMath`
**File**: `WellPlate/Core/Services/SymptomCorrelationEngine.swift`
**Action**: Replace private `spearmanR`, `ranks`, `pearsonR`, `bootstrapCI`, `interpretationLabel` calls with `CorrelationMath.*`
**Dependencies**: Step 1.2
**Risk**: Low — pure delegation, no logic change

Remove lines 146-223 (the private static funcs). Update line 111-115:
```swift
let (r, ciLow, ciHigh) = await Task.detached(priority: .userInitiated) {
    let r = CorrelationMath.spearmanR(symptomValues, factorValues)
    let (lo, hi) = CorrelationMath.bootstrapCI(xValues: symptomValues, yValues: factorValues)
    return (r, lo, hi)
}.value
```

Update line 212:
```swift
let interp = CorrelationMath.interpretationLabel(r: r, ciSpansZero: ciSpansZero)
```

---

### Phase 2: InsightEngine Service

#### Step 2.1: Create `InsightEngine.swift` — scaffold and data aggregation
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Create the main service with `@Published` state, `bindContext()`, and `buildWellnessContext()`
**Dependencies**: Step 1.1
**Risk**: Medium — largest single file; many SwiftData + HealthKit fetches

```swift
import Foundation
import SwiftData
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class InsightEngine: ObservableObject {
    
    // MARK: - Published State
    @Published var insightCards: [InsightCard] = []
    @Published var dailyInsight: InsightCard?
    @Published var isGenerating: Bool = false
    @Published var insufficientData: Bool = false
    
    // MARK: - Dependencies
    private var modelContext: ModelContext?
    private let healthService: HealthKitServiceProtocol
    private let lookbackDays: Int = 14
    
    init(healthService: HealthKitServiceProtocol = HealthKitService()) {
        self.healthService = healthService
    }
    
    func bindContext(_ context: ModelContext) {
        modelContext = context
    }
    
    // MARK: - Public API
    func generateInsights() async { ... }
    func clearAndRegenerate() async { ... }
    
    // MARK: - Data Aggregation
    private func buildWellnessContext() async -> WellnessContext? { ... }
}
```

**`buildWellnessContext()` implementation** — follows the exact pattern from `StressInsightService.buildContext()` (lines 103-199) but expanded:

1. Fetch `UserGoals.current(in:)` → create `UserGoalsSnapshot`
2. Gate check: fetch `StressReading` in window — require >= 2 days with readings (same as current)
3. Concurrent HealthKit fetches using `async let`:
   - `fetchSleepSafely` → `[DailySleepSummary]` (reuse pattern from StressInsightService line 433)
   - `fetchDailyStepsSafely` → `[DailyMetricSample]`
   - `fetchDailyEnergySafely` → `[DailyMetricSample]`
   - `fetchHeartRateSafely` → `[DailyMetricSample]`
   - `fetchExerciseMinutesSafely` → `[DailyMetricSample]` (NEW — uses `healthService.fetchExerciseMinutes`)
4. SwiftData fetches with date predicates (all `>= windowStart`):
   - `WellnessDayLog`
   - `FoodLogEntry`
   - `SymptomEntry`
   - `FastingSession` (filter `isActive == false` for completed sessions)
   - `AdherenceLog`
   - `JournalEntry`
5. Build per-day `WellnessDaySummary` array (same loop structure as StressInsightService lines 143-185, expanded with new fields):
   - Symptoms: filter `SymptomEntry` by day → collect unique names, max severity
   - Fasting: filter `FastingSession` by day → total hours, completed flag
   - Supplements: filter `AdherenceLog` by day → taken/total ratio
   - Journal: check if `JournalEntry` exists for day
   - Sleep: extract `bedtime` and `wakeTime` from `DailySleepSummary`
   - Exercise minutes from HealthKit fetch
6. Build `dataQualityNote` (same pattern as StressInsightService lines 189-198)

#### Step 2.2: Implement insight detectors
**File**: `WellPlate/Core/Services/InsightEngine.swift` (private extension)
**Action**: Add 6 detector methods that scan `WellnessContext` and produce `[InsightCard]`
**Dependencies**: Step 2.1, Step 1.2
**Risk**: Medium — algorithm correctness

Each detector is a `private func detect*(context:) -> [InsightCard]` method:

**1. `detectTrends`** — 3+ day directional trends
```
For each metric (stressScore, sleepHours, steps, totalCalories, waterGlasses, coffeeCups):
  - Extract non-nil values with dates
  - If last 3+ values are monotonically increasing or decreasing:
    - Calculate % change from first to last
    - Create InsightCard with .trend type
    - chartData: .trendLine with the metric's points over full window
    - priority: based on % change magnitude and domain importance
  - Minimum: 3 consecutive days with data
```

**2. `detectCorrelations`** — cross-domain Spearman r-values
```
Define pairs: (sleepHours, stressScore), (steps, stressScore), (coffeeCups, stressScore),
              (totalProteinG, stressScore), (totalFiberG, stressScore),
              (waterGlasses, stressScore), (sleepHours, steps)
For each pair:
  - Build paired arrays from days where both values exist
  - If N >= 7: compute Spearman r + bootstrap CI via CorrelationMath
  - If |r| >= 0.3 AND CI doesn't span zero: create InsightCard with .correlation type
  - chartData: .correlationScatter with (x, y) points + r value
  - priority: based on |r| and N
```

**3. `detectMilestones`** — streaks and first-time goal achievements
```
Check streaks for: water >= goal, steps >= goal, calories within ±10% of goal, sleep >= goal
For each metric:
  - Count consecutive days (from most recent) meeting the threshold
  - If streak >= 3: create InsightCard with .milestone type
  - chartData: .milestoneRing(current: streakDays, target: 7, label: "Water Streak")
  - priority: higher for longer streaks
Also check: first-ever day hitting a goal (compare against full lookback)
```

**4. `detectImbalances`** — macro/nutrition deficits
```
For each macro (protein, fiber, fat, carbs):
  - Calculate average over last 7 days with food logs
  - Compare to goal from UserGoalsSnapshot
  - If avg < 70% of goal for 3+ days: create InsightCard with .imbalance type
  - chartData: .macroRadar(actual: {...}, goals: {...}) OR
               .trendLine for the specific macro
  - priority: based on how far below goal
Also check: calorie surplus/deficit, hydration deficit
```

**5. `detectSleepQuality`** — deep sleep ratio changes
```
  - Split lookback into first half vs. second half
  - Compare avg deep sleep ratio (deep / total) between halves
  - If change > 15%: create InsightCard with .sleepQuality type
  - Also check: bedtime consistency (stddev of bedtime minutes-from-midnight)
  - chartData: .comparisonBars for "This week" vs "Last week" deep sleep
  - priority: medium
```

**6. `detectReinforcements`** — positive habit acknowledgement
```
  - If any metric has been consistently at or above goal for 5+ of the last 7 days:
    create InsightCard with .reinforcement type
  - Headline: "Consistent [metric] — keep going!"
  - chartData: .sparkline of the metric values
  - priority: low (should not crowd out discoveries)
```

#### Step 2.3: Implement insight prioritisation
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Add `prioritise(_:)` method
**Dependencies**: Step 2.2
**Risk**: Low

```swift
private func prioritise(_ cards: [InsightCard]) -> [InsightCard] {
    // Sort by priority descending
    // Tiebreak: .correlation > .trend > .imbalance > .sleepQuality > .milestone > .reinforcement
    // Deduplicate: if two insights cover the same metric, keep higher priority
    // Cap at 12 cards for the hub
    // Set dailyInsight to cards.first
}
```

#### Step 2.4: Implement Foundation Models narrative generation
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Add FM narrative generation using `@Generable` schema
**Dependencies**: Step 2.3
**Risk**: Medium — FM latency, quality

```swift
#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _InsightNarrativeSchema {
    @Guide(description: "Short punchy headline, max 60 chars, no medical claims")
    var headline: String
    @Guide(description: "1-2 sentence narrative. Use 'may suggest' or 'appears linked'. No diagnosis or medical language.")
    var narrative: String
    @Guide(description: "2 specific actionable suggestions based on the data")
    var suggestions: [_InsightSuggestionItem]
}

@available(iOS 26, *)
@Generable
private struct _InsightSuggestionItem {
    @Guide(description: "One specific, actionable suggestion")
    var text: String
}
#endif
```

**Batching strategy**: Build a single prompt describing the top 5 insight cards' data context + type, ask model to generate narratives for all 5. Parse structured output back to update each card's headline and narrative.

If batched call fails, fall back to individual calls for each card. If all FM fails, fall back to templates.

#### Step 2.5: Implement template fallback narratives
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Add deterministic template narrative generation per insight type
**Dependencies**: Step 2.2
**Risk**: Low

```swift
private func templateNarrative(for card: InsightCard, context: WellnessContext) -> (headline: String, narrative: String, suggestions: [String]) {
    switch card.type {
    case .trend:
        // "Sleep has dropped 3 days in a row" / "Steps trending up this week"
        // Use domain + direction to pick template
    case .correlation:
        // "On days you slept 7h+, stress was X% lower"
        // Use x/y labels + r direction
    case .milestone:
        // "5-day water goal streak!"
    case .imbalance:
        // "Protein has averaged Xg/day — Y% below your Zg goal"
    case .sleepQuality:
        // "Deep sleep improved X% compared to last week"
    case .reinforcement:
        // "Great consistency on [metric] this week — keep it up"
    }
}
```

#### Step 2.6: Implement mock mode and caching
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Add `mockInsights()` method and same-day cache check
**Dependencies**: Step 2.4, Step 2.5
**Risk**: Low

Cache: same pattern as `StressInsightService.generateInsight()` lines 52-66:
```swift
if let existing = insightCards.first, Calendar.current.isDateInToday(existing.generatedAt) {
    return
}
```

Mock mode: `if AppConfig.shared.mockMode { insightCards = mockInsights(); return }`
Generate 6-8 mock `InsightCard` instances covering each type with realistic data.

#### Step 2.7: Wire up `generateInsights()` orchestration
**File**: `WellPlate/Core/Services/InsightEngine.swift`
**Action**: Implement the main public method that ties all steps together
**Dependencies**: Steps 2.1-2.6
**Risk**: Low

```swift
func generateInsights() async {
    guard modelContext != nil else { return }
    if let first = insightCards.first, Calendar.current.isDateInToday(first.generatedAt) { return }
    
    isGenerating = true
    defer { isGenerating = false }
    
    if AppConfig.shared.mockMode {
        let mocks = mockInsights()
        insightCards = mocks
        dailyInsight = mocks.first
        return
    }
    
    guard let context = await buildWellnessContext() else {
        insufficientData = true
        return
    }
    
    // Detect all insights
    var cards: [InsightCard] = []
    cards.append(contentsOf: detectTrends(context: context))
    cards.append(contentsOf: detectCorrelations(context: context))
    cards.append(contentsOf: detectMilestones(context: context))
    cards.append(contentsOf: detectImbalances(context: context))
    cards.append(contentsOf: detectSleepQuality(context: context))
    cards.append(contentsOf: detectReinforcements(context: context))
    
    // Prioritise and cap
    cards = prioritise(cards)
    
    // Generate narratives (FM or template)
    cards = await generateNarratives(cards, context: context)
    
    insightCards = cards
    dailyInsight = cards.first
}
```

---

### Phase 3: Chart Components

#### Step 3.1: Create `InsightCharts.swift`
**File**: `WellPlate/Features + UI/Home/Components/InsightCharts.swift`
**Action**: Create 6 reusable chart subviews using Swift Charts
**Dependencies**: Step 1.1 (for `InsightChartData`)
**Risk**: Medium — chart styling needs iteration

**`TrendAreaChart`** — Area + Line + Point combo (based on `InsightStressTrendCard` pattern):
```swift
struct TrendAreaChart: View {
    let points: [(date: Date, value: Double)]
    let goalLine: Double?
    let metricLabel: String
    let unit: String
    let accentColor: Color
    // Body: AreaMark + LineMark + optional RuleMark for goal
    // Frame height: 130
}
```

**`CorrelationScatterChart`** — Scatter with trend line:
```swift
struct CorrelationScatterChart: View {
    let points: [(x: Double, y: Double)]
    let r: Double
    let xLabel: String
    let yLabel: String
    // Body: PointMark for each point + LineMark for linear regression line
    // r-value badge overlay
    // Frame height: 150
}
```

**`ComparisonBarChart`** — Horizontal bars for A vs B comparisons:
```swift
struct ComparisonBarChart: View {
    let bars: [(label: String, value: Double, color: Color)]
    let highlight: Int?
    // Body: BarMark (horizontal) per bar
    // Frame height: 80
}
```

**`MacroRadarChart`** — 5-axis radar (Custom Canvas path, not Swift Charts):
```swift
struct MacroRadarChart: View {
    let actual: [String: Double]  // protein, carbs, fat, fiber, calories (normalised 0-1)
    let goals: [String: Double]   // same axes
    // Body: Canvas with:
    //   - Goal polygon (dashed stroke)
    //   - Actual polygon (filled with accent.opacity(0.2), stroked accent)
    //   - Axis labels at each vertex
    // Frame: 160x160
}
```

**`MilestoneRingView`** — Animated ring with streak count:
```swift
struct MilestoneRingView: View {
    let current: Int
    let target: Int
    let streakLabel: String
    // Body: Circle arc (progress = current/target) with text center
    // Animate on appear
    // Frame: 80x80
}
```

**`SparklineView`** — Compact inline trend (for DailyInsightCard):
```swift
struct SparklineView: View {
    let points: [Double]
    let accentColor: Color
    // Body: tiny LineMark, no axes, no labels
    // Frame: 60x24
}
```

All chart views follow existing colour conventions:
- Use `AppColors.brand`, `.success`, `.error`, `.warning` for semantic colouring
- Axis labels: `.font(.system(size: 9, design: .rounded))`
- Interpolation: `.catmullRom` for line charts (matching existing pattern)

---

### Phase 4: View Layer

#### Step 4.1: Create `InsightCardView.swift`
**File**: `WellPlate/Features + UI/Home/Components/InsightCardView.swift`
**Action**: Create reusable card that renders any `InsightCard`
**Dependencies**: Phase 3 (charts), Step 1.1 (models)
**Risk**: Low

```swift
struct InsightCardView: View {
    let card: InsightCard
    var onDetailsTap: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: domain icon + domain label + type badge
            HStack(spacing: 6) {
                Image(systemName: card.domain.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(card.domain.accentColor)
                Text(card.domain.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(card.domain.accentColor)
                    .tracking(1.0)
                Spacer()
                Text(card.type.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }
            
            // Headline
            Text(card.headline)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Chart — switch on chartData
            chartView(for: card.chartData)
            
            // Narrative
            Text(card.narrative)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Details button (optional)
            if onDetailsTap != nil {
                Button { onDetailsTap?() } label: {
                    HStack(spacing: 4) {
                        Text("See Details")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(card.domain.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }
    
    @ViewBuilder
    private func chartView(for data: InsightChartData) -> some View {
        switch data {
        case .trendLine(let points, let goal, let label, let unit):
            TrendAreaChart(points: points, goalLine: goal, metricLabel: label, unit: unit, accentColor: card.domain.accentColor)
        case .correlationScatter(let points, let r, let xLabel, let yLabel):
            CorrelationScatterChart(points: points, r: r, xLabel: xLabel, yLabel: yLabel)
        case .comparisonBars(let bars, let highlight):
            ComparisonBarChart(bars: bars, highlight: highlight)
        case .macroRadar(let actual, let goals):
            MacroRadarChart(actual: actual, goals: goals)
        case .milestoneRing(let current, let target, let label):
            MilestoneRingView(current: current, target: target, streakLabel: label)
        case .sparkline(let points):
            SparklineView(points: points, accentColor: card.domain.accentColor)
        }
    }
}
```

#### Step 4.2: Create `DailyInsightCard.swift`
**File**: `WellPlate/Features + UI/Home/Components/DailyInsightCard.swift`
**Action**: Compact home-screen card with sparkline
**Dependencies**: Step 4.1
**Risk**: Low

```swift
struct DailyInsightCard: View {
    let card: InsightCard?
    let isGenerating: Bool
    var onTap: () -> Void
    
    var body: some View {
        if isGenerating {
            // Skeleton loading state: shimmer placeholder
        } else if let card {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    // Left: icon in coloured circle
                    ZStack {
                        Circle()
                            .fill(card.domain.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: card.type.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(card.domain.accentColor)
                    }
                    
                    // Center: headline + brief narrative
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.headline)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(card.narrative)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Right: sparkline (if available) or chevron
                    if case .sparkline(let points) = card.chartData, !points.isEmpty {
                        SparklineView(points: points, accentColor: card.domain.accentColor)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
        }
        // nil card + not generating = don't render (insufficient data)
    }
}
```

#### Step 4.3: Create `InsightsHubView.swift`
**File**: `WellPlate/Features + UI/Home/Views/InsightsHubView.swift`
**Action**: Scrollable hub of insight cards with header, empty state, and regenerate
**Dependencies**: Step 4.1, Phase 2
**Risk**: Low

```swift
struct InsightsHubView: View {
    @ObservedObject var engine: InsightEngine
    @State private var selectedCard: InsightCard?
    
    var body: some View {
        ZStack {
            if engine.isGenerating {
                loadingView   // Reuse pattern from HomeAIInsightView
            } else if engine.insufficientData {
                insufficientDataView  // Reuse pattern from HomeAIInsightView
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Header
                        InsightsHubHeader(cardCount: engine.insightCards.count)
                            .insightEntrance(index: 0)
                        
                        // Insight cards
                        ForEach(Array(engine.insightCards.enumerated()), id: \.element.id) { idx, card in
                            InsightCardView(card: card) {
                                selectedCard = card
                            }
                            .insightEntrance(index: idx + 1)
                        }
                        
                        // Footer with regenerate button
                        InsightsHubFooter(engine: engine)
                            .insightEntrance(index: engine.insightCards.count + 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Your Insights")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedCard) { card in
            InsightDetailSheet(card: card, engine: engine)
        }
    }
}
```

Note: Reuse the `InsightEntrance` modifier extracted from `HomeAIInsightView.swift` (lines 602-623). Move it to a shared location or keep in `InsightsHubView` since the old view will be removed.

#### Step 4.4: Create `InsightDetailSheet.swift`
**File**: `WellPlate/Features + UI/Home/Views/InsightDetailSheet.swift`
**Action**: Modal deep-dive with full-size chart + extended narrative + suggestions
**Dependencies**: Step 4.1, Phase 3
**Risk**: Low

```swift
struct InsightDetailSheet: View {
    let card: InsightCard
    @ObservedObject var engine: InsightEngine
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Domain + type header
                    // Full headline
                    // Full-size chart (same chart type but larger frame)
                    // Extended narrative
                    // Suggestions list (card.detailSuggestions)
                    // Caution note: "Correlation does not imply causation."
                }
                .padding(20)
            }
            .navigationTitle(card.domain.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

Make `InsightCard` conform to `Identifiable` (already does) for `.sheet(item:)`.

---

### Phase 5: HomeView Integration

#### Step 5.1: Update `HomeView.swift`
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`
**Action**: Replace `StressInsightService` with `InsightEngine`, add `DailyInsightCard`, update navigation
**Dependencies**: All previous phases
**Risk**: Medium — core view modification

Changes:
1. **Replace StateObject** (line 61):
   ```swift
   // OLD: @StateObject private var insightService = StressInsightService()
   @StateObject private var insightEngine = InsightEngine()
   ```

2. **Add DailyInsightCard** to `LazyVStack` after QuickStatsRow (around line 149):
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

3. **Replace navigation state** (line 54):
   ```swift
   // OLD: @State private var showAIInsight = false
   @State private var showInsightsHub = false
   ```

4. **Update navigationDestination** (line 228-229):
   ```swift
   // OLD: .navigationDestination(isPresented: $showAIInsight) { HomeAIInsightView(insightService: insightService) }
   .navigationDestination(isPresented: $showInsightsHub) {
       InsightsHubView(engine: insightEngine)
   }
   ```

5. **Update header icon action** (lines 364-368):
   ```swift
   Button {
       HapticService.impact(.light)
       showInsightsHub = true
       Task { await insightEngine.generateInsights() }
   } label: {
       headerIcon("sparkles")
   }
   ```

6. **Update onAppear** (line 239):
   ```swift
   // OLD: insightService.bindContext(modelContext)
   insightEngine.bindContext(modelContext)
   ```

7. **Update contextual bar `onSeeInsight`** (lines 193-195):
   ```swift
   onSeeInsight: {
       showInsightsHub = true
       Task { await insightEngine.generateInsights() }
   }
   ```

8. **Remove old insightService references**: Remove any remaining `insightService` usage. The `showAIInsight` state and its `navigationDestination` to `HomeAIInsightView` are fully replaced.

#### Step 5.2: Update `ContextualActionBar.swift` (if needed)
**File**: `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift`
**Action**: Verify the `onSeeInsight` closure is called correctly — no changes needed to ContextualActionBar itself since the closure is passed from HomeView.
**Dependencies**: Step 5.1
**Risk**: Low

---

### Phase 6: Cleanup & Polish

#### Step 6.1: Move `InsightEntrance` modifier to shared location
**File**: `WellPlate/Features + UI/Home/Components/InsightCardView.swift` (bottom of file)
**Action**: Move the `InsightEntrance` ViewModifier + `.insightEntrance(index:)` extension from `HomeAIInsightView.swift` into `InsightCardView.swift` (or a dedicated shared file) so both `InsightsHubView` and `InsightDetailSheet` can use it.
**Dependencies**: Step 4.1
**Risk**: Low

#### Step 6.2: Delete old files
**File**: Multiple
**Action**: Remove deprecated files
**Dependencies**: Step 5.1 (confirm new code works first)
**Risk**: Low

Files to remove:
- `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift` — replaced by `InsightsHubView`
- `WellPlate/Core/Services/StressInsightService.swift` — replaced by `InsightEngine`
- `WellPlate/Features + UI/Home/StressInsightReport.swift` — replaced by `InsightModels.swift`

#### Step 6.3: Build verification
**Action**: Run all build targets
**Dependencies**: All steps
**Risk**: Low

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

---

## Testing Strategy

### Build Verification
- All 4 xcodebuild targets must pass (main app + 3 extensions)

### Manual Verification Flows
1. **Mock mode**: Enable `AppConfig.shared.mockMode` → launch app → verify DailyInsightCard appears on home → tap → InsightsHubView shows 6+ cards with charts → tap any card → InsightDetailSheet opens
2. **Insufficient data**: Disable mock mode on fresh simulator with no data → verify "Not Enough Data" empty state
3. **Real data**: On device with HealthKit data + food logs → verify insights generate with real data
4. **iOS < 26 fallback**: Build for iOS 18 target → verify template narratives render (no FM calls)
5. **Regenerate**: In InsightsHubView → tap Regenerate → verify loading state → new cards appear
6. **Same-day cache**: Navigate away and back → verify insights don't regenerate
7. **Dark mode**: Toggle dark mode → verify all charts and cards render correctly
8. **VoiceOver**: Navigate InsightsHubView with VoiceOver → verify all cards are accessible

---

## Risks & Mitigations

- **Risk**: InsightEngine `buildWellnessContext()` is slow with 8 SwiftData fetches + 5 HealthKit fetches
  - Mitigation: All HealthKit fetches use `async let` for concurrency. SwiftData fetches use date-predicated `FetchDescriptor`s. Total: ~1-2s expected, hidden behind loading state.

- **Risk**: Foundation Models batched narrative quality may be poor
  - Mitigation: Fall back to individual FM calls. If those fail, template narratives are always available. Template quality is acceptable (proven by existing StressInsightService).

- **Risk**: CorrelationMath extraction breaks SymptomCorrelationEngine
  - Mitigation: Pure extraction — move functions, update call sites, no logic changes. Build verifies.

- **Risk**: Too many insights overwhelm the hub
  - Mitigation: `prioritise()` caps at 12 cards. Daily card shows only top 1. Users can always "See Details" for depth.

- **Risk**: Radar chart (Canvas-based) is complex to implement
  - Mitigation: Start with a simpler grouped bar chart for macro breakdown. Radar can be a polish iteration.

---

## Success Criteria

- [ ] `DailyInsightCard` visible on home screen below QuickStatsRow in mock mode
- [ ] Tapping DailyInsightCard navigates to InsightsHubView
- [ ] InsightsHubView shows 6+ insight cards in mock mode
- [ ] Each insight card shows: domain header, headline, chart, narrative
- [ ] At least 4 chart types render correctly (trend, scatter, comparison, sparkline)
- [ ] Tapping "See Details" on a card opens InsightDetailSheet with suggestions
- [ ] Regenerate button clears and regenerates insights
- [ ] Empty state shown when insufficient data
- [ ] Foundation Models generates narratives on iOS 26+ with model availability
- [ ] Template fallback produces readable narratives when FM unavailable
- [ ] `CorrelationMath` shared utility used by both InsightEngine and SymptomCorrelationEngine
- [ ] All 4 build targets pass
- [ ] Old files removed: `HomeAIInsightView`, `StressInsightService`, `StressInsightReport`
