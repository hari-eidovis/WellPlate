# Brainstorm: AI Insights V2 — Richer UI, Deeper Analysis, Foundation Model-Powered Intelligence

**Date**: 2026-04-10
**Status**: Ready for Planning

---

## Problem Statement

The current AI Insights feature (`HomeAIInsightView`) is a single-screen, stress-only report that:

1. **Limited scope** — Only analyses stress data with sleep/steps/calories as supporting signals. Ignores nutrition depth, symptom correlations, hydration patterns, fasting impact, journal sentiment, and supplement adherence.
2. **Static presentation** — Text-heavy cards with only 3 chart types (stress trend, sleep bars, step bars). No interactive charts, no drill-downs, no animations that invite exploration.
3. **Single report format** — One monolithic "last 10 days" report. No daily micro-insights, weekly summaries, trend alerts, or milestone celebrations.
4. **Passive delivery** — User must tap a sparkles icon to generate. No proactive nudges, no notification-worthy discoveries, no "something interesting happened" moments.
5. **No personalisation** — Same prompt structure for every user regardless of their goals, data richness, or engagement patterns.

The goal is to transform AI Insights from a stress report into a **comprehensive wellness intelligence hub** — visually engaging, data-rich, and powered by Foundation Models to surface patterns the user wouldn't spot on their own.

---

## Core Requirements

- **Multi-domain insights** — Cover all tracked data: stress, nutrition (macros, fiber, meal timing), sleep (total + deep), activity (steps, calories burned), hydration, caffeine, mood, symptoms, fasting, supplements, and journal entries.
- **Rich visualisations** — Interactive Swift Charts with drill-down, multi-metric overlays, correlation scatter plots, heatmaps, and trend sparklines.
- **Foundation Model intelligence** — Use on-device FoundationModels (`LanguageModelSession`) for narrative generation, pattern detection, and personalised coaching. Template fallback for iOS < 26.
- **Layered insight delivery** — Daily micro-insights (1-2 sentences), weekly deep-dives, monthly recaps, and real-time pattern alerts.
- **Engaging UX** — Swipeable card carousel, staggered entrance animations, haptic feedback on discoveries, and a "Spotify Wrapped"-inspired scrollable report for weekly/monthly.
- **Data privacy** — All analysis on-device via Foundation Models. No data leaves the phone.

---

## Constraints

- **iOS 26+ for Foundation Models** — Must have robust template fallback for iOS 18+.
- **HealthKit authorisation gaps** — Not all users grant all permissions. Insights must gracefully degrade.
- **On-device model limitations** — Foundation Models has token limits and latency. Can't send entire data history — must pre-aggregate.
- **SwiftData performance** — Fetching 30-90 days of FoodLogEntry, StressReading, etc. must be efficient. Use batch descriptors and pre-aggregation.
- **No medical claims** — Language must stay wellness/coaching, never diagnostic. "May suggest" not "causes".
- **Existing architecture** — Must fit within MVVM + Service Layer pattern. `StressInsightService` is the reference implementation.

---

## Approach 1: Multi-Domain Insight Cards with Tabbed Hub

**Summary**: Replace the single stress report with a tabbed insights hub. Each tab covers a domain (Overview, Nutrition, Sleep, Activity, Stress, Patterns). Each domain has its own set of insight cards and charts.

### UI Structure

```
InsightsHubView
├── Tab: Overview (curated top insights from all domains)
├── Tab: Nutrition (macro trends, meal timing, fiber/protein analysis)
├── Tab: Sleep (duration trends, deep sleep ratio, sleep-stress correlation)
├── Tab: Activity (step trends, exercise impact, sedentary alerts)
├── Tab: Stress (existing report + enhanced)
└── Tab: Patterns (cross-domain correlations)
```

### Insight Types per Domain

**Overview Tab:**
- "Insight of the Day" — single most interesting finding, LLM-generated headline
- Weekly wellness score trend (composite of all domains)
- 3 mini-cards: best improvement, biggest risk, streak achievement

**Nutrition Tab:**
- Macro balance radar chart (protein/carbs/fat/fiber vs. goals)
- Meal timing heatmap (when user eats vs. optimal windows)
- "Nutrition Score" trend line (composite of macro adherence)
- LLM-generated: "Your protein intake dropped 20% this week — here's why it matters for recovery"

**Sleep Tab:**
- Sleep duration trend with deep sleep overlay (stacked area chart)
- Sleep-stress scatter plot with correlation coefficient
- "Sleep Debt" tracker — accumulated shortfall vs. 8h target
- Bedtime consistency chart (actual vs. target)
- LLM: "Your deep sleep improved 15% after you started walking 8k+ steps — keep it up"

**Activity Tab:**
- Steps trend with goal line + rolling 7-day average
- Active calories vs. intake balance chart
- Exercise → next-day stress impact (lagged correlation)
- LLM: "Days you hit 8,000 steps, your next-day stress is 18% lower on average"

**Stress Tab:**
- Enhanced version of current report
- Factor contribution stacked bar (sleep, activity, caffeine, nutrition, mood)
- Stress heatmap by hour-of-day and day-of-week
- LLM: deeper narrative with specific day references

**Patterns Tab (most novel):**
- Cross-domain correlation matrix (visual heatmap of r-values)
- "Strongest Link" — the highest-confidence cross-domain correlation found
- "What-If" simulations: "If you slept 1h more, stress would likely drop by X based on your data"
- LLM-generated pattern story: weaves together 2-3 correlated signals into a narrative

### Charts & Visualisations

| Chart Type | Use Case | SwiftCharts API |
|---|---|---|
| Area + Line combo | Stress trend, sleep trend | `AreaMark` + `LineMark` |
| Stacked bar | Factor contribution, macro breakdown | `BarMark` with `.foregroundStyle(by:)` |
| Scatter plot | Sleep-stress, steps-stress correlations | `PointMark` + trend line `LineMark` |
| Radar/spider chart | Macro balance vs. goals | Custom `Path` in Canvas |
| Heatmap grid | Meal timing, stress by hour/day | `RectangleMark` with color scale |
| Sparkline | Inline mini-trends in card headers | Tiny `LineMark` in fixed frame |
| Gauge/Progress ring | Weekly scores, domain scores | `Gauge` or custom arc |
| Comparison bars | Fasting vs non-fasting, weekday vs weekend | Horizontal `BarMark` pairs |

**Pros**:
- Comprehensive coverage of all data domains
- Tabbed structure scales well — new domains can be added later
- Each tab can load independently (lazy loading)
- Familiar tab pattern for users

**Cons**:
- Large implementation scope — many views, many chart types
- Risk of overwhelming users with too much data
- Tab navigation adds depth — more taps to reach specific insights
- Foundation Models prompt complexity increases with more domains

**Complexity**: High
**Risk**: Medium (scope creep risk)

---

## Approach 2: Scrollable "Weekly Wrapped" Report + Daily Micro-Insights

**Summary**: Two complementary experiences: (1) a daily micro-insight card on the home screen that surfaces one interesting finding, and (2) a weekly "Wrapped"-style scrollable report that tells the story of your week with beautiful charts and LLM narratives.

### Daily Micro-Insight (Home Screen Card)

- Appears below wellness rings as a compact card
- One insight per day, rotated by priority:
  - Pattern discovery: "You've slept 30min longer on days you walk 8k+ steps"
  - Milestone: "5-day streak of hitting your water goal!"
  - Risk alert: "Stress trending up 3 days in a row — sleep dropped below 6h"
  - Nutrition nudge: "Fiber has been under 15g for 4 days"
  - Positive reinforcement: "Great protein consistency this week — averaging 85g/day"
- Tappable → expands to show supporting chart + "Learn more" → weekly report
- LLM generates the headline; template fallback uses structured rules

### Weekly Wrapped Report (Full Screen)

Scrollable, story-like experience inspired by Spotify Wrapped / Apple Fitness+ Monthly Summary:

```
Page 1: Hero — "Your Week in Review" + overall wellness score ring
Page 2: Nutrition Story — macro radar + key finding + LLM narrative
Page 3: Sleep Story — trend chart + deep sleep ratio + best/worst night
Page 4: Activity Story — step trend + exercise impact on stress
Page 5: Stress Story — trend + factor breakdown + LLM analysis
Page 6: Patterns — top 2-3 cross-domain discoveries with charts
Page 7: Wins & Goals — streaks, milestones, goal completions
Page 8: Coach's Note — LLM-generated 3-sentence personalised summary + 2 suggestions for next week
```

Each "page" is a full-width card that scrolls vertically, with staggered entrance animations (extending the existing `InsightEntrance` modifier).

### Chart Highlights

- **Wellness Score Ring** — animated composite ring (like Apple Watch activity) showing nutrition/sleep/activity/stress as segments
- **Macro Radar Chart** — 5-axis (calories, protein, carbs, fat, fiber) showing actual vs. goal
- **Correlation Spotlight** — scatter plot of the week's strongest correlation with r-value badge
- **Day-by-Day Timeline** — horizontal scroll of day bubbles with mood emoji + stress color + key metric

**Pros**:
- Story-driven format is highly engaging and shareable
- Daily micro-insights keep users coming back without overwhelming
- Two-tier approach: light (daily) and deep (weekly) — caters to different engagement levels
- Builds on existing `InsightEntrance` animation system
- Weekly cadence is natural for health reflection
- Smaller implementation surface than Approach 1 (fewer tabs/views)

**Cons**:
- Weekly report is only generated once per week — less immediate value for new users
- Daily micro-insight logic is non-trivial (prioritisation, deduplication, freshness)
- "Wrapped" format may feel gimmicky if content isn't genuinely insightful
- No on-demand deep-dive into specific domains

**Complexity**: Medium-High
**Risk**: Low-Medium

---

## Approach 3: Conversational AI Coach with Visual Responses

**Summary**: Instead of pre-built report screens, create a conversational interface where the user can ask questions about their health data and the AI responds with text + inline charts. Think "ChatGPT for your wellness data" but fully on-device.

### UI Structure

```
AICoachView
├── Suggested question pills: "How was my sleep this week?", "What's affecting my stress?"
├── Scrolling chat-like interface
│   ├── User question (text or tapped pill)
│   └── AI response: text narrative + optional inline chart
└── Text input field (free-form questions)
```

### How It Works

1. User taps a suggested question or types their own
2. Service aggregates relevant data (scoped to the question domain)
3. Foundation Models generates a response with structured output (text + chart directive)
4. View renders the text with an optional SwiftChart inline

### Example Interactions

**User**: "How was my sleep this week?"
**AI**: [Sleep bar chart for 7 days] "You averaged 6.8h this week, down from 7.2h last week. Tuesday and Wednesday were your shortest nights at 5.5h. Your deep sleep ratio held steady at 22%. On the bright side, your last 3 nights have been improving — keep that bedtime routine going."

**User**: "What's driving my stress up?"
**AI**: [Stress trend + factor contribution chart] "Your stress peaked on Wednesday at 78/100. The strongest signal is sleep — on days you slept under 6h, stress averaged 72 vs. 48 on 7h+ nights. Caffeine also shows a moderate link: 3+ cups correlated with next-day stress 15% higher."

**User**: "Am I eating enough protein?"
**AI**: [Protein trend line vs. goal] "You're averaging 68g/day against your 90g goal. That's a 24% shortfall. Your best days were Monday and Thursday when you logged chicken and Greek yogurt. Try adding a high-protein breakfast — eggs or a protein shake could close the gap."

### Suggested Questions (Context-Aware)

Questions adapt based on available data and recent patterns:
- New pattern detected → "I noticed something about your sleep and stress — want to hear?"
- Goal milestone → "You hit your water goal 5 days in a row — shall I show the impact?"
- Data gap → "You haven't logged food in 3 days — want tips for getting back on track?"

**Pros**:
- Highly personalised and exploratory — user drives the conversation
- Feels cutting-edge and modern (conversational AI trend)
- Naturally handles all data domains without needing separate tabs
- Foundation Models excels at conversational responses
- Question suggestions bridge the gap for users who don't know what to ask

**Cons**:
- Foundation Models latency makes conversation feel slow (each response = model inference)
- Token window limits complex multi-domain analysis in a single response
- Free-form input → unpredictable queries the model may struggle with
- Chat UI is harder to "scan" — no persistent dashboard of insights
- Risk of "empty conversation" if user has little data
- Much harder to implement template fallback for iOS < 26
- Users may not know what questions to ask beyond the suggestions

**Complexity**: High
**Risk**: High (UX uncertainty, model limitations)

---

## Approach 4: Hybrid — Weekly Report + Daily Cards + On-Demand Deep Dives

**Summary**: Combine the best of Approaches 1 and 2. Daily micro-insight card on home → weekly wrapped report → tappable sections that expand into domain-specific deep dives.

### Three-Layer Architecture

**Layer 1: Daily Insight Card (Home Screen)**
- Compact card below wellness rings
- LLM-generated single insight with supporting sparkline
- Tappable → opens the insight hub
- Updates daily; generates on `onAppear` with same-day cache

**Layer 2: Insights Hub (NavigationDestination)**
- "This Week" summary section at top (wellness score + key metrics)
- Scrollable insight cards organized by type, not domain:
  - **Trend Cards**: "Stress is trending down" with area chart
  - **Correlation Cards**: "Sleep and stress link" with scatter plot + r-value
  - **Milestone Cards**: "7-day water streak!" with confetti animation
  - **Alert Cards**: "Protein has been low for 5 days" with trend line
  - **Nutrition Cards**: Macro balance radar, meal timing analysis
  - **Pattern Cards**: "Fasting days show 8pts lower stress" with comparison bars
- Each card is a self-contained `InsightCard` with:
  - Icon + category label (header)
  - LLM-generated 1-2 sentence narrative
  - Embedded SwiftChart (context-appropriate type)
  - Optional "See Details" → deep dive

**Layer 3: Deep Dive Sheets (presented modally)**
- Triggered from "See Details" on any insight card
- Domain-specific analysis with:
  - Full-size interactive chart (zoomable, tappable data points)
  - Extended LLM narrative (3-5 sentences)
  - Historical comparison ("This week vs. last week")
  - Actionable suggestions (2-3 specific recommendations)

### Insight Generation Engine

```swift
// New unified service replacing StressInsightService
InsightEngine
├── WellnessContextBuilder     // Aggregates all data into InsightContext
├── InsightPrioritizer         // Ranks insights by novelty, significance, user goals
├── FoundationModelGenerator   // LLM narrative for top N insights
├── TemplateGenerator          // Fallback narratives for iOS < 26
└── InsightCache               // Same-day caching, weekly report persistence
```

**InsightContext** (expanded from `StressInsightContext`):
```
Per-day summary:
- Stress (score, label)
- Sleep (total, deep, bedtime, wake time)
- Activity (steps, active calories, exercise minutes)
- Nutrition (calories, protein, carbs, fat, fiber, meal count, meal times)
- Hydration (water glasses)
- Caffeine (cups, type)
- Mood (label)
- Symptoms (names, severities)
- Fasting (session duration, completed?)
- Supplements (adherence count)
- Journal (sentiment if Foundation Models available)
```

### Insight Types (Prioritised)

| Type | Trigger | Chart | Priority |
|---|---|---|---|
| Trend Alert | 3+ day directional trend in any metric | Area chart | High |
| Correlation Discovery | r > 0.3 or r < -0.3 with N >= 7 | Scatter plot | High |
| Goal Milestone | Streak >= 3 or first-time goal hit | Confetti + ring | Medium |
| Macro Imbalance | Any macro < 70% or > 130% of goal for 3+ days | Radar chart | Medium |
| Sleep Quality | Deep sleep ratio change > 15% week-over-week | Stacked bar | Medium |
| Fasting Impact | Sufficient fasting + non-fasting days to compare | Comparison bars | Low-Med |
| Symptom Pattern | Symptom frequency correlates with lifestyle factor | Heatmap | Low-Med |
| Positive Reinforcement | Consistent goal adherence in any domain | Sparkline + badge | Low |
| Nutrition Timing | Meal timing consistency or notable gaps | Timeline dots | Low |

### UI Polish Details

- **Card entrance**: Extend existing `InsightEntrance` modifier with parallax scroll effect
- **Chart animations**: Charts animate data points sequentially on appear
- **Haptic feedback**: Light impact on card appearance, medium on discovery cards
- **Pull-to-regenerate**: Regenerate insights with new randomisation seed
- **Empty states**: Beautiful illustrations per domain when data is insufficient
- **Dark mode**: Charts use `AppColors` tokens for consistent theming
- **Accessibility**: VoiceOver labels for all charts, large text support

**Pros**:
- Balanced depth — light daily card, medium hub, deep detail sheets
- Type-based (not domain-based) card organisation feels more discovery-oriented
- Prioritisation engine ensures the most interesting insights surface first
- Reusable `InsightCard` component scales to new insight types
- Builds naturally on existing `StressInsightService` architecture
- Template fallback is feasible per-card (small scope per template)
- Charts are context-appropriate, not one-size-fits-all

**Cons**:
- Still significant implementation work (though less than Approach 1)
- Prioritisation logic is complex and may need tuning
- Multiple Foundation Models calls for hub population (batch prompting needed)
- Deep dive sheets add navigation depth

**Complexity**: Medium-High
**Risk**: Low

---

## Edge Cases to Consider

- [ ] **New user (< 3 days of data)**: Show onboarding-style "Log for X more days to unlock insights" with progress indicator per domain
- [ ] **Selective HealthKit permissions**: Skip charts/insights for denied categories. Show "Enable sleep tracking to unlock sleep insights" CTAs
- [ ] **Foundation Models unavailable**: Template fallback must cover all insight types. Mark template-generated insights subtly (no "AI-generated" badge for templates)
- [ ] **Large data volume**: User with 90+ days of food logs — batch fetch with date predicates, not full table scan. Pre-aggregate daily summaries
- [ ] **Contradictory signals**: E.g., stress up but sleep improved. LLM prompt must handle nuance; template must not make conflicting claims
- [ ] **Missing single day in a streak**: "4 out of 5 days" should still count as notable, not be silently dropped
- [ ] **Timezone changes**: Travel could create apparent anomalies in daily aggregation. Use `Calendar.current` consistently
- [ ] **Same-day cache invalidation**: If user logs new data (e.g., a meal), daily insight should optionally refresh. Balance freshness vs. API cost
- [ ] **Insight fatigue**: If no new patterns emerge, don't show stale insights. Show "Your habits are consistent this week — keep going!" instead
- [ ] **Correlation =/= causation**: Every correlation insight must include disclaimer language. LLM prompt enforces "may suggest" framing

---

## Open Questions

- [ ] Should weekly report auto-generate every Monday, or only when user opens it?
- [ ] Should we add a "Share Insight" feature (screenshot/image export of a card)?
- [ ] How many Foundation Models calls per hub refresh? Batch into single multi-insight prompt or one-per-card?
- [ ] Should the daily micro-insight card replace the StressInsightCard or coexist?
- [ ] Do we want push notifications for high-priority discoveries? (e.g., "New pattern found — your caffeine and stress are linked")
- [ ] Should monthly recaps be a V2 addition or part of initial scope?
- [ ] What minimum data threshold per insight type? (Current: 2 stress days. Should nutrition insights need 5+ logged meals?)
- [ ] Should insights reference specific days by name ("Tuesday was your worst sleep") or keep it relative ("2 days ago")?

---

## Recommendation

**Approach 4: Hybrid — Weekly Report + Daily Cards + On-Demand Deep Dives**

This approach offers the best balance of:

1. **User engagement** — Daily card keeps users returning; hub rewards exploration
2. **Implementation feasibility** — Card-based architecture is modular; can ship incrementally (start with 3-4 insight types, add more)
3. **Data utilisation** — The unified `InsightEngine` aggregates all domains, unlike the current stress-only service
4. **Visual richness** — Each insight card carries its own chart type, creating visual variety
5. **Foundation Models fit** — On-device LLM generates card-level narratives (short, bounded) rather than full reports (long, risky)
6. **Progressive disclosure** — Light → Medium → Deep layers let users choose their depth

### Suggested Implementation Phases

**Phase 1 (MVP)**: InsightEngine + InsightContext builder + Daily micro-insight card on home + 4 insight card types (Trend Alert, Correlation, Goal Milestone, Positive Reinforcement) + InsightsHubView with scrollable cards

**Phase 2**: Weekly Wrapped report + 4 more insight types (Macro Imbalance, Sleep Quality, Fasting Impact, Symptom Pattern) + Deep dive sheets

**Phase 3**: Monthly recaps, Share feature, notification-based discovery alerts, "What-If" projections

---

## Research References

- Existing `StressInsightService` (523 lines) — reference for FoundationModels integration, `@Generable` schema pattern, data aggregation, and template fallback
- Existing `JournalPromptService` — reference for `LanguageModelSession` usage with `@Generable` structs
- Existing `NutritionNarratorService` — another FoundationModels integration point (nutrition coaching)
- Existing `SymptomCorrelationEngine` — Spearman correlation computation, CI calculation — reusable for cross-domain correlations
- Existing `FastingInsightChart` — comparison bar visualisation for fasting vs. non-fasting days
- Apple FoundationModels framework docs — `@Generable`, `@Guide`, `LanguageModelSession.respond(to:generating:)`
- Swift Charts — `AreaMark`, `LineMark`, `BarMark`, `PointMark`, `RectangleMark` for all chart types
- `StressInsightDaySummary` — already captures 16 data fields per day; extend with symptoms, fasting, supplements
