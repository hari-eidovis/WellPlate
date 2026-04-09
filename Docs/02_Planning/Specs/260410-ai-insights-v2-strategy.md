# Strategy: AI Insights V2

**Date**: 2026-04-10
**Source**: `Docs/01_Brainstorming/260410-ai-insights-v2-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Hybrid: Daily Micro-Insight Card + Insights Hub + On-Demand Deep Dives** (Brainstorm Approach 4)

A three-layer progressive disclosure architecture: (1) a compact daily insight card on the home screen that surfaces the single most interesting finding with an embedded sparkline, (2) an Insights Hub — a scrollable feed of prioritised insight cards spanning all wellness domains, each with its own chart and LLM-generated narrative, and (3) tappable deep-dive sheets for extended analysis of any insight. The entire system runs on a unified `InsightEngine` service that replaces the current stress-only `StressInsightService`, aggregating data from all SwiftData models + HealthKit into a rich `WellnessContext`, then generating and ranking insight cards by novelty and significance.

---

## Rationale

### Why Approach 4 over alternatives

1. **vs. Tabbed Hub (Approach 1)**: Domain-based tabs are rigid — they force the user to navigate to "Sleep" to see a sleep-stress correlation that actually spans both domains. Card-based feeds sorted by priority surface the most interesting insights first, regardless of domain. Also, the tabbed approach roughly doubles the view count for the same insight coverage.

2. **vs. Weekly Wrapped only (Approach 2)**: A weekly-only cadence leaves new users waiting 7 days for value. The daily micro-insight card provides immediate feedback from day 2. The weekly wrapped format is still valuable — it can be added as a Phase 2 enhancement within this same architecture (the hub already aggregates the data).

3. **vs. Conversational AI (Approach 3)**: Foundation Models latency (~2-4s per inference) makes conversation feel sluggish. Free-form input creates unpredictable queries the on-device model may hallucinate on. The card-based approach pre-structures the LLM's task (short, bounded narratives per card) which produces higher quality output. Template fallback for iOS < 26 is also much more tractable per-card than per-conversation.

### Trade-offs accepted

- **More upfront implementation** than a simple stress report enhancement — justified because the current feature is a dead-end that can't scale to new domains without a rewrite.
- **Multiple Foundation Models calls** per hub refresh (one per card narrative) — mitigated by same-day caching, prioritisation (only top N cards get LLM narratives), and `Task` concurrency.
- **Retiring `StressInsightService`** — its data aggregation and LLM integration patterns are preserved in the new `InsightEngine`; the view-layer `HomeAIInsightView` is replaced by `InsightsHubView`.

---

## Affected Files & Components

### New Files (to be created)

| File | Purpose |
|---|---|
| `WellPlate/Core/Services/InsightEngine.swift` | Unified insight generation service. Replaces `StressInsightService`. Contains: data aggregation (`WellnessContextBuilder`), insight detection, prioritisation, FM generation, template fallback, caching. |
| `WellPlate/Features + UI/Home/Models/InsightModels.swift` | Value types: `WellnessContext`, `WellnessDaySummary` (expanded `StressInsightDaySummary`), `InsightCard` (type, headline, narrative, chartData, priority), `InsightType` enum |
| `WellPlate/Features + UI/Home/Views/InsightsHubView.swift` | Scrollable feed of `InsightCardView` instances. Replaces `HomeAIInsightView`. |
| `WellPlate/Features + UI/Home/Components/InsightCardView.swift` | Reusable card component — renders any `InsightCard` with appropriate chart + narrative |
| `WellPlate/Features + UI/Home/Components/DailyInsightCard.swift` | Compact home-screen card showing top insight with sparkline. Taps → InsightsHubView |
| `WellPlate/Features + UI/Home/Components/InsightCharts.swift` | Chart subviews: `TrendAreaChart`, `CorrelationScatterChart`, `MacroRadarChart`, `ComparisonBarChart`, `MilestoneRing` |
| `WellPlate/Features + UI/Home/Views/InsightDetailSheet.swift` | Deep-dive modal: full-size chart + extended narrative + suggestions |

### Modified Files

| File | Change |
|---|---|
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | Replace `showAIInsight` → `showInsightsHub`. Add `DailyInsightCard` to the `LazyVStack`. Replace `@StateObject insightService = StressInsightService()` → `@StateObject insightEngine = InsightEngine()`. Update `onAppear` and header icon action. |
| `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift` | Update `onSeeInsight` to navigate to `InsightsHubView` instead of `HomeAIInsightView`. |
| `WellPlate/Features + UI/Home/StressInsightReport.swift` | Keep as-is initially — `InsightEngine` can produce a backwards-compatible `StressInsightReport` for the transition. Mark deprecated after migration. |

### Files to Eventually Remove (post-migration)

| File | Reason |
|---|---|
| `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift` | Replaced by `InsightsHubView` |
| `WellPlate/Core/Services/StressInsightService.swift` | Replaced by `InsightEngine` |
| `WellPlate/Features + UI/Home/StressInsightReport.swift` | Replaced by `InsightModels.swift` |

### Files to Reuse (patterns/code to extract)

| File | What to reuse |
|---|---|
| `StressInsightService.swift` | HealthKit fetch helpers, `buildContext()` aggregation pattern, `@Generable` schema pattern, mock report generation, template report logic |
| `SymptomCorrelationEngine.swift` | Spearman correlation computation, CI calculation — extract into a shared `CorrelationMath` utility |
| `StressAnalyticsHelper.swift` | `dailyAveragesByDate()` — generalise for any metric |
| `HomeAIInsightView.swift` | `InsightEntrance` staggered animation modifier, card background style, chart colour functions |

---

## Architectural Direction

### Service Layer

```
InsightEngine (@MainActor, ObservableObject)
├── @Published insightCards: [InsightCard]        // Prioritised list for hub
├── @Published dailyInsight: InsightCard?          // Top card for home screen
├── @Published isGenerating: Bool
│
├── bindContext(_ context: ModelContext)            // Same pattern as StressInsightService
├── generateInsights() async                       // Main entry point
├── clearAndRegenerate() async
│
├── (private) buildWellnessContext() async → WellnessContext?
│   ├── SwiftData fetches: StressReading, WellnessDayLog, FoodLogEntry, 
│   │   SymptomEntry, FastingSession, SupplementEntry, AdherenceLog, JournalEntry
│   └── HealthKit fetches: sleep, steps, energy, heartRate (reuse safe fetch pattern)
│
├── (private) detectInsights(_ context: WellnessContext) → [InsightCard]
│   ├── TrendDetector        — 3+ day directional trends in any metric
│   ├── CorrelationDetector  — cross-domain r-value computation (reuse Spearman from SymptomCorrelationEngine)
│   ├── MilestoneDetector    — streak detection, first-time goal hits
│   ├── ImbalanceDetector    — macro adherence, sleep debt, hydration deficit
│   └── PatternDetector      — fasting impact, meal timing, caffeine-stress link
│
├── (private) prioritise(_ cards: [InsightCard]) → [InsightCard]
│   // Score by: novelty (haven't shown before), significance (effect size), 
│   // actionability, data confidence (N days)
│
├── (private) generateNarratives(_ cards: [InsightCard], context: WellnessContext) async → [InsightCard]
│   // Top N cards get Foundation Models narrative; rest get template narrative
│   // Single batched FM call with multi-insight prompt (reduces model calls)
│
└── (private) templateNarrative(for card: InsightCard) → String
    // Deterministic fallback for iOS < 26 or FM failure
```

### Data Model

```swift
// WellnessDaySummary — expanded from StressInsightDaySummary
// Adds: symptomNames, symptomMaxSeverity, fastingHours, fastingCompleted, 
//       supplementAdherence, journalLogged, bedtime, wakeTime

// InsightCard
struct InsightCard: Identifiable {
    let id: UUID
    let type: InsightType           // .trend, .correlation, .milestone, .imbalance, .pattern, .reinforcement
    let domain: WellnessDomain      // .stress, .nutrition, .sleep, .activity, .hydration, .fasting, .symptoms, .cross
    let headline: String            // Short, punchy (max 60 chars)
    let narrative: String           // 1-3 sentences, LLM or template generated
    let chartData: InsightChartData // enum with associated values per chart type
    let priority: Double            // 0-1, higher = more important
    let isLLMGenerated: Bool
    let generatedAt: Date
}

// InsightChartData — drives which chart subview renders
enum InsightChartData {
    case trendLine(points: [(Date, Double)], goalLine: Double?, label: String)
    case correlationScatter(points: [(Double, Double)], r: Double, xLabel: String, yLabel: String)
    case comparisonBars(bars: [(String, Double)], highlight: Int?)
    case macroRadar(actual: [String: Double], goals: [String: Double])
    case milestoneRing(current: Int, target: Int, label: String)
    case heatmapGrid(rows: [String], cols: [String], values: [[Double]])
}
```

### View Layer

```
HomeView
├── DailyInsightCard(engine.dailyInsight)      // Compact, tappable
│   └── NavigationDestination → InsightsHubView
│
InsightsHubView(engine: InsightEngine)
├── Header: "Your Insights" + date range + regenerate button
├── LazyVStack of InsightCardView instances
│   ├── InsightCardView(card: InsightCard)
│   │   ├── Header: icon + domain label + type badge
│   │   ├── Headline text
│   │   ├── Chart: switch on card.chartData → appropriate chart subview
│   │   ├── Narrative text
│   │   └── "Details" button → InsightDetailSheet
│   └── .insightEntrance(index:) modifier (reuse existing)
│
InsightDetailSheet(card: InsightCard, context: WellnessContext)
├── Full-size interactive chart
├── Extended narrative (LLM-generated, 3-5 sentences)
├── "This week vs. last week" comparison
└── 2-3 actionable suggestions
```

### Foundation Models Integration

Follow the established `@Generable` + `LanguageModelSession` pattern from `StressInsightService` and `JournalPromptService`:

```swift
@Generable
struct _InsightNarrativeSchema {
    @Guide(description: "Punchy headline, max 60 chars, no medical claims")
    var headline: String
    
    @Guide(description: "1-3 sentence narrative using 'may suggest' framing")
    var narrative: String
}
```

**Batching strategy**: Rather than one FM call per card, build a single prompt with the top 5 insights' data summaries and ask the model to generate narratives for all 5 in one call. This reduces latency from 5 x 3s = 15s to ~4s.

---

## Design Constraints

1. **Follow existing MVVM + Service Layer pattern**. `InsightEngine` is a `@MainActor final class: ObservableObject` with `@Published` properties, just like `StressInsightService`.

2. **Same-day caching**. Use the same `Calendar.current.isDateInToday(generatedAt)` pattern from `StressInsightService` to avoid regenerating insights on every navigation.

3. **ModelContext injection via `bindContext()`**. Same pattern as `StressInsightService` and `HomeViewModel`. Called in `HomeView.onAppear`.

4. **FoundationModels + template fallback**. Every insight type must have a deterministic template fallback. `#if canImport(FoundationModels)` guard, `@available(iOS 26, *)` check, `SystemLanguageModel.default.availability` gate.

5. **No medical language**. All prompts and templates must use "may suggest", "appears linked", "correlates with" — never "causes", "diagnoses", or "treats".

6. **UI tokens from `AppColors`**. Cards use `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 12, y: 4)`. Charts use `AppColors.brand`, `.success`, `.error`, `.warning`.

7. **Staggered entrance animations**. Reuse and extend the existing `InsightEntrance` modifier from `HomeAIInsightView`.

8. **PBXFileSystemSynchronizedRootGroup**. New files placed under `WellPlate/` are auto-included in the build. No pbxproj edits needed.

9. **Minimum data thresholds**. Each insight type defines its own threshold (e.g., trends need 3+ days, correlations need 7+ paired days). Graceful empty state when insufficient data.

10. **Lookback window: 14 days** (expanded from current 10) for richer trend and correlation detection. Deep dives can extend to 30 days.

---

## Non-Goals

- **Push notifications for insights** — Out of scope. No UNUserNotification integration.
- **Monthly recaps / "Wrapped" report** — Phase 2 enhancement. Not in initial implementation.
- **Share/export insights** — Not in scope. No image rendering or share sheet.
- **Conversational interface** — Rejected in brainstorm. Cards, not chat.
- **Widget integration** — Insights in `WellPlateWidget` is a separate feature.
- **Apple Watch insights** — Separate feature tracked in the Apple Watch brainstorm.
- **Custom user goals per insight** — Use existing `UserGoals` thresholds. No new goal-setting UI.
- **Editing `StressView` or `BurnView`** — Those views are not affected. Only the Home screen insights path changes.

---

## Open Risks

1. **Foundation Models batched output quality** — Generating 5 narratives in one prompt may reduce quality vs. individual calls. Mitigation: test both approaches; fall back to individual calls if batch quality is poor.

2. **SwiftData fetch performance with 14-day window across 8 model types** — Mitigation: use date-predicated `FetchDescriptor`s (not full table scans), and run fetches concurrently with `async let`.

3. **Insight prioritisation tuning** — The scoring algorithm may not surface the "right" insights initially. Mitigation: start with simple heuristics (novelty + effect size), iterate based on testing.

4. **Correlation false positives with small N** — With only 7-14 data points, Spearman correlations can be noisy. Mitigation: require minimum N=7, display confidence intervals, always include "correlation =/= causation" disclaimer.

5. **Migration path from `StressInsightService`** — Users who tap the sparkles icon currently get the stress report. During migration, `InsightEngine` should produce a superset of the old report's data. Mitigation: keep `StressInsightReport` as a deprecated compatibility shim during the transition.
