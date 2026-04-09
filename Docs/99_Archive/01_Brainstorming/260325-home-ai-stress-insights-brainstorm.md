# Brainstorm: Home AI Stress Insights

**Date**: 2026-03-25
**Status**: Ready for Planning

---

## Problem Statement

Add an AI entry point on the Home screen header, beside the existing calendar button. Tapping it should open a new insight surface that analyzes the user's last 3 to 5 days of stress-related data and produces a concise, visually strong "wrap" style report. The report should explain what appears to be pushing stress up or down, highlight positive and negative patterns, and suggest concrete next actions to reduce stress.

This is an on-demand, user-triggered feature — not a push notification or ambient widget. The user asks, we analyze, we respond. If there is not enough data to produce meaningful patterns, we show a clear message rather than a degraded or hallucinated report.

---

## Core Requirements

- AI entry point on the Home screen header (beside the calendar button)
- On-demand trigger — user initiates the report, not auto-pushed
- Analyzes recent stress-related data (target window: last 3 days minimum, up to 5 days)
- "Spotify Wrapped"-style visual output: cards, headline, narrative summary
- Hard gate: show "not enough data" message when the minimum threshold is not met
- Graceful degradation: template fallback when Foundation Models is unavailable
- Must not produce medical claims — only patterns, signals, and suggestions
- All AI processing must stay on-device (Apple Foundation Models, not Groq cloud)

---

## Constraints

- The app already uses `FoundationModels` behind `#if canImport(FoundationModels)` and `#available(iOS 26, *)` gates. This feature must follow the same availability and fallback pattern instead of assuming Apple Intelligence is always present.
- Apple recommends structured generation and explicit availability checking for Foundation Models. The model should not be the sole source of truth for ranking stress drivers or making causal claims.
- Current stored data is useful but uneven:
  - `StressReading` gives historical stress snapshots with timestamps.
  - `WellnessDayLog` stores daily stress label, water, coffee, steps, calories burned, and mood.
  - `FoodLogEntry` stores nutrition plus meal context such as meal type, triggers, hunger, and reflection.
  - `StressViewModel` can fetch recent HealthKit histories, but the app does not currently persist daily factor breakdowns like sleep contribution, diet contribution, or screen-time contribution.
- `ScreenTimeManager` currently exposes today's threshold-based screen time reading via shared App Group data. It is not yet a clean historical dataset for 3 to 5 day analysis.
- The feature is wellness guidance, not diagnosis. Copy must avoid medical certainty and should frame outputs as patterns, signals, and suggestions.
- The repo has ongoing stress-view work in progress, so this integration should minimize overlap with active edits in `StressView` unless the planner explicitly chooses to share logic there.
- Foundation Models runs on-device — data does not leave the device, and there is no per-call cost. However, not all iOS 26 devices have Apple Intelligence, so the feature must degrade to a template fallback without showing an error.

---

## Data Budget Analysis

On-device Foundation Models has a practical context window. The goal is maximum signal, minimum noise. Never send raw arrays — always pre-aggregate on device before any model call.

| Data Type | Recommended Window | What to Send |
|---|---|---|
| Stress readings | Last 3–5 days | Daily avg score + dominant factor label |
| Food logs | Last 3–5 days | Daily aggregates: calories, protein %, fiber g, meal count |
| WellnessDayLog | Last 3–5 days | Water ml, coffee count, steps, mood, stress label per day |
| Sleep (HealthKit) | Last 3–5 nights | Duration hours + quality flag per night |
| Activity/Burn (HealthKit) | Last 3–5 days | Active calories per day |
| Vitals (HealthKit) | Last 3–5 days | Daily avg HR, HRV, respiratory rate |
| Screen time | Last 3–5 days | Threshold crossed: yes/no per day (do not send raw hours if unavailable) |

Estimated token budget for 5-day aggregated summary: ~300–500 tokens input. Well within on-device model limits.

**Do not send:** raw `FoodLogEntry` arrays, individual HK samples, timestamps within a day, or unbounded `StressReading` history.

---

## Minimum Data Threshold (the "not enough data" gate)

Gate logic should run before any analysis or model call:

```
< 2 days of StressReading data               → "not enough data" screen
≥ 2 days but < 3 complete days               → "early signals only" mode with low-confidence framing
≥ 3 days with at least 2 factor categories   → full report
```

A "factor category" is met when the user has at least one of: food logs, sleep data, HK activity data, or WellnessDayLog entries for that day. Screen time is optional in V1.

---

## Impacted Targets

- `WellPlate` (primary)
- Shared models and services inside the main app target
- `ScreenTimeMonitor` only if we decide to persist daily threshold snapshots for historical analysis
- `ScreenTimeReport` as a reference surface only; likely no initial code changes
- `WellPlateWidget` only as a later follow-on if we want a compact AI insight teaser

---

## Current Codebase Fit

- Home header UI is currently owned inside `HomeView`, not `HomeHeaderView`, so the new button belongs in `WellPlate/Features + UI/Home/Views/HomeView.swift`.
- The app already has two Foundation Models service patterns to reference:
  - `MealCoachService` — structured extraction via `@Generable`, private schema, sentinel strings instead of `Optional` (required by `@Generable`), silent fallback on unsupported devices
  - `NutritionNarratorService` — `@MainActor final class`, tiered voice/output fallback, published state (`isGenerating`, `isSpeaking`), template narrative on iOS < 26
- The stress domain already computes factor scores locally and persists top-level stress snapshots, which is a strong base for a hybrid insight pipeline.
- The major missing piece is recent-day attribution. V1 either needs to reconstruct recent days on demand from SwiftData and HealthKit, or start persisting daily insight snapshots.

---

## Approach 1: Prompt the Model With Raw Recent Data

**Summary**: Collect the last 3 to 5 days of raw meals, wellness logs, stress readings, and factor text, then ask Foundation Models to directly write the report and identify the strongest stress drivers.

**Pros**:
- Fastest path to a visible AI feature
- Smallest amount of new analysis code
- Most flexible output style for a "Spotify Wrapped" feel

**Cons**:
- Highest hallucination risk for "what affected stress the most"
- Hard to test because the model decides both analysis and narrative
- Raw prompts become noisy quickly as logs grow
- Missing or partial data may cause the model to overstate weak signals
- Weak fallback story on unsupported devices (nothing to fall back to if the model decides everything)

**Complexity**: Medium
**Risk**: High

---

## Approach 2: Hybrid Deterministic Analysis + Foundation Models Narrative

**Summary**: Build a local analysis pipeline that computes the recent trend, strongest negative factors, strongest positive factors, major gaps, and notable behaviors across 3 to 5 days. Feed only that compact summary into Foundation Models to generate a structured report and user-friendly suggestions.

**Pros**:
- Best balance of reliability and product feel
- Deterministic logic owns rankings, trends, and guardrails — model cannot invent a cause
- Smaller prompts and more stable outputs
- Easy fallback: keep the same cards and swap generated prose for template prose
- Matches the existing service pattern already used in the repo (`MealCoachService`, `NutritionNarratorService`)
- Privacy: the compact summary sent to the model contains no raw food names or personal identifiers — only numeric aggregates and factor rankings

**Cons**:
- Requires new analysis models and aggregation code
- Needs a clear answer for historical screen-time support
- Requires careful wording so the model does not turn correlation into certainty

**Complexity**: Medium
**Risk**: Medium

---

## Approach 3: Snapshot-First Insight System

**Summary**: Introduce a persisted daily snapshot model for stress insights, such as daily factor contributions, confidence flags, and top events. The AI view then reads those snapshots and uses Foundation Models only for packaging the recap.

**Pros**:
- Strongest long-term architecture for weekly and monthly recaps
- Best data quality for ranking what changed over time
- Reusable for widgets, notifications, and progress surfaces later
- Minimizes expensive on-demand rebuilding once the snapshot exists

**Cons**:
- Slowest path to user-visible value
- Needs schema work and migration planning
- New users have no meaningful history until enough days accumulate
- Still needs a backfill plan for existing users

**Complexity**: High
**Risk**: Medium

---

## UI Approach Exploration

Three distinct presentation modes to consider:

### Option A: Push Navigation (Recommended for V1)
Tapping the AI button pushes a new view onto the navigation stack. Feels native, uses existing navigation patterns in the app. Back button returns to Home. Editorial layout with scroll.

### Option B: Full-Screen Sheet
`.fullScreenCover` — immersive, feels like a special event (closer to Spotify Wrapped). Adds a dismiss button. More surface area for card animation. Slightly heavier than a push.

### Option C: Modal Bottom Sheet
Partial sheet from the bottom. Familiar iOS pattern. Constrains content height — may feel cramped for a multi-card wrap report.

**Recommendation**: Push navigation for V1 (matches current Home and Stress navigation patterns). Full-screen sheet is worth revisiting for a "monthly recap" variant if this feature evolves.

---

## Structured Generation Schema

Following the `MealCoachService` pattern — a private `@Generable` struct, sentinel strings instead of `Optional`, and a clean public output type:

```swift
@available(iOS 26, *)
@Generable
private struct _StressInsightSchema {
    @Guide(description: "Short editorial headline, max 12 words, no medical claims")
    var headline: String

    @Guide(description: "2–3 sentence summary of the stress pattern this period")
    var summary: String

    @Guide(description: "The factor that most helped stress, e.g. 'consistent sleep'")
    var strongestPositiveFactor: String

    @Guide(description: "The factor that most drove stress up, e.g. 'late screen time'")
    var strongestNegativeFactor: String

    @Guide(description: "Array of 2–3 specific, actionable suggestions")
    var suggestions: [String]

    @Guide(description: "Confidence note when data is thin, or empty string if data is sufficient")
    var cautionNote: String
}
```

Public output type (no `@Generable` dependency in the domain layer):

```swift
struct StressInsightReport {
    let headline: String
    let summary: String
    let strongestPositiveFactor: String
    let strongestNegativeFactor: String
    let suggestions: [String]
    let cautionNote: String
    let generatedAt: Date
    let isTemplateGenerated: Bool  // true when model was unavailable
}
```

---

## Recommended V1 Shape

- Use **Approach 2** for V1.
- Reconstruct the last **3 days** on demand first, not 5, because current data quality is uneven and 3 days reduces noise and implementation cost.
- Keep all driver ranking **deterministic and local**:
  - stress trend from `StressReading`
  - nutrition quality from `FoodLogEntry` (fiber, protein %, meal count)
  - coffee and hydration patterns from `WellnessDayLog`
  - exercise and sleep pulled from HealthKit history
  - screen time only if present with acceptable confidence (at least 2 of 3 days populated)
- Send a compact analysis object into Foundation Models for:
  - headline
  - short summary paragraph
  - "best helper" and "biggest stressor" framing
  - 2 to 3 suggestions
- Also support a non-AI fallback that renders the same insight cards with deterministic template copy.
- Treat a future persisted snapshot model (Approach 3) as **Phase 2** once V1 proves useful.

---

## Suggested V1 Output Shape (Card Layout)

```
[ AI Sparkles Header: "Your Last 3 Days" ]

[ Hero card: stress trend — "Stress trended up on 2 of 3 days" ]

[ Green card: biggest positive — "Your sleep was consistent this week" ]

[ Red/amber card: biggest negative — "Late-night screen time spiked twice" ]

[ Pattern card: "High screen time nights correlated with higher next-day stress" ]

[ Action cards: 2–3 bullet suggestions ]

[ Caution note (if data thin): "Screen time data was unavailable for 1 day" ]

[ Regenerate button + timestamp: "Generated today at 9:41 AM" ]
```

---

## Data Architecture Notes

- A new app-owned service is needed: `StressInsightService` (under `WellPlate/Core/Services/`).
- That service builds a compact internal analysis model before any Foundation Models call:
  - `StressInsightContext` — aggregated 3-day summary struct passed to the model
  - `StressInsightReport` — public output type rendered by the view
- The service should be a `@MainActor final class` (matching `NutritionNarratorService`), with `@Published var isGenerating: Bool`.
- Prefer the `@Generable` + sentinel string pattern from `MealCoachService`. Do not use `String?` in `@Generable` structs.
- Do not feed raw `FoodLogEntry` arrays or unbounded `StressReading` history straight into the model.
- If daily factor attribution is needed later, add a persisted snapshot model rather than pushing more raw history into prompts.

---

## UI Integration Notes

- Add the AI trigger beside the calendar button in `HomeView`'s inline `homeHeader`.
- Use a push destination owned by `HomeView` (see Option A above).
- The AI view should feel editorial, not chat-like:
  - wrap-style cards with strong typographic hierarchy
  - animated entrance per card (stagger on appear)
  - strong headline + brief section copy
  - optional regenerate button with loading state
- Avoid placing the first version inside `StressView` — users are asking for a Home-level "what happened this week" summary, not a factor-debug screen.
- Consider caching the same-day result (store `generatedAt` date) so repeated taps on the same day feel instant and consistent. Regenerate clears the cache.

---

## Edge Cases

- [ ] Fewer than 2 days of usable `StressReading` data — show "not enough data" screen with guidance ("Log your stress for a few more days")
- [ ] HealthKit authorization missing or partially granted — analysis skips HealthKit-backed factors; `cautionNote` explains absence
- [ ] No screen time authorization or no threshold crossed yet — screen time omitted from analysis, not surfaced as an error
- [ ] Meals logged without enough nutritional diversity to infer patterns — diet factor confidence flagged low
- [ ] High stress with mixed signals, e.g. high activity but poor sleep — model should surface tension, not force a single cause
- [ ] Model unavailable because device, locale, or Apple Intelligence support is missing — template copy rendered using the same card layout; `isTemplateGenerated: true`
- [ ] Suggestions becoming repetitive across repeated same-day regenerations — consider seeding variation in the prompt or caching same-day result
- [ ] Generated copy sounding too clinical or too certain — system prompt must explicitly instruct "patterns and signals only, no causal claims, no medical language"
- [ ] User with only 1 full day + partial second day — round down to 1 day and block report generation
- [ ] User taps regenerate while a generation is in flight — disable button during `isGenerating == true`

---

## Open Questions

- [ ] Should V1 analyze exactly 3 days, or dynamically use 3 to 5 days when enough data exists?
- [ ] Should the AI entry be icon-only, or visually distinct from the calendar with a sparkles badge or pill label?
- [ ] Push navigation, modal sheet, or full-screen immersive report? (Recommendation above: push for V1)
- [ ] Is screen time required to be part of the insight score in V1, or optional when historical data is weak?
- [ ] Do you want actionable deep links in the report, such as "open meal log", "hydration detail", or "stress tab"?
- [ ] Should the report regenerate every tap, or cache a same-day result for consistency?
- [ ] Is it acceptable to frame outputs as "likely patterns" rather than "causes"?
- [ ] Should we show a "last generated" timestamp so the user knows when to expect fresh insights?
- [ ] If the user has mock mode on, should the AI insight surface use mock stress data to always show a populated report?

---

## Recommendation

Use a hybrid architecture where local code performs the actual recent-day analysis and Foundation Models only turns that analysis into a polished editorial report. This is the strongest fit for the current codebase because:

1. The app already has the raw ingredients (StressReading, WellnessDayLog, FoodLogEntry, HealthKit histories)
2. Two Foundation Models service patterns are already established and audited (`MealCoachService`, `NutritionNarratorService`) — this feature follows the same pattern
3. On-device inference means no cost, no network dependency, and no data leaving the device
4. The deterministic local analysis layer prevents the model from hallucinating stress causes
5. The template fallback path means the feature is never completely broken — devices without Apple Intelligence still get the insight cards

V1 should target a 3-day recap with deterministic ranking, structured generation via `@Generable`, and a template fallback. If the feature proves useful, Phase 2 should add persisted daily insight snapshots to unlock stronger weekly and monthly recaps, and potentially a widget teaser card.

---

## Planner Handoff

**Recommended implementation direction**: Home-owned AI insight entry point plus a new `StressInsightService` that builds a compact recent-days analysis object (`StressInsightContext`), then optionally passes it to Foundation Models for structured report generation using a private `@Generable` schema. The output (`StressInsightReport`) drives a new editorial view pushed from `HomeView`.

**Impacted files or areas**:
- `WellPlate/Features + UI/Home/Views/HomeView.swift` — add AI button to header
- `WellPlate/Features + UI/Home/Views/HomeAIInsightView.swift` — new editorial report view
- `WellPlate/Core/Services/StressInsightService.swift` — new service (analysis + generation)
- `WellPlate/Models/` or feature-local types — `StressInsightContext`, `StressInsightReport`
- Possible read-only helpers reused from `StressViewModel` for HealthKit history access

**Targets to verify later**:
- `WellPlate` build with and without `FoundationModels` import available
- Fallback behavior on unsupported devices (template report renders correctly)
- Whether `ScreenTimeMonitor` needs a daily persistence enhancement for historical accuracy
- Mock mode: if `AppConfig.shared.mockMode` is true, the insight view should pre-populate with mock data rather than showing "not enough data"
