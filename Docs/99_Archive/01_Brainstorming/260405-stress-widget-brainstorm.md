# Brainstorm: Stress Widget — Replace Food Log Widget

**Date**: 2026-04-05
**Status**: Ready for Planning

---

## Problem Statement

WellPlate currently ships a **Food Log widget** (small/medium/large) showing calorie rings, macro bars, and recent foods. We want to **replace it entirely** with a **Stress Level widget** that surfaces the app's stress scoring system (0–100, 4 factors, 5 levels) on the Home Screen — giving users a glanceable window into their stress state throughout the day.

---

## Core Requirements

- Show stress level (0–100 score) in all 3 widget sizes
- Visual language must match the existing StressLevel color/icon system
- Data shared via the same App Group (`group.com.hariom.wellplate`) + UserDefaults pattern
- Deep-link to the Stress tab in the main app
- Must feel useful even when some factors have no data yet

## Constraints

- WidgetKit: static snapshots, no interactivity beyond taps/deep-links
- Small widget: ~155×155pt — extremely limited real estate
- No live animations (WidgetKit renders static images)
- Data refresh limited by WidgetKit budget (~15-40 refreshes/day + app-triggered)
- StressLevel uses adaptive colors (`.primary.opacity()` for excellent/good) which may need special handling for widget backgrounds

---

## Approach 1: Score-Centric — "The Gauge"

**Summary**: Center the design around a prominent stress score number with a colored arc/gauge, making the score the hero element across all sizes.

### Small (~155×155pt)
- **Header**: "Stress" label + stress-level SF Symbol (e.g., `face.smiling`)
- **Hero**: Large score number (e.g., **32**) centered
- **Gauge**: Semi-circular arc behind the number, colored by stress level (green → red)
- **Footer**: Level label ("Good") + subtle encouragement text or time since last update
- **Tap**: Deep-link to `wellplate://stress`

### Medium (~329×155pt)
- **Left column**: Gauge + score (same as small but slightly larger)
- **Right column**: 4-factor mini breakdown
  - Each factor: icon + name + mini progress bar (colored green→red)
  - e.g., 🏃 Exercise ████░░ 18/25
  - e.g., 📱 Screen ██████ 20/25 (red-tinted)
- **Divider**: Vertical separator between columns
- **Tap**: Deep-link to `wellplate://stress`

### Large (~329×345pt)
- **Header**: "Stress Level" title + date + score badge
- **Hero**: Large gauge arc with score + level label
- **Factor cards**: 4 horizontal rows, each with icon, name, score bar, status text
- **Trend line**: Sparkline or dot chart showing last 7 days of total stress scores
- **Encouragement**: Level-appropriate message from `encouragementText`
- **CTA**: "View Details" pill button
- **Tap**: Deep-link to `wellplate://stress`

**Pros**:
- Score is instantly readable — the #1 thing users want at a glance
- Gauge is a universally understood metaphor for "level"
- Factor breakdown in medium/large adds actionable context
- Maps cleanly to existing StressLevel properties

**Cons**:
- Gauge rendering in WidgetKit requires custom `Path` drawing (no SFSymbol for it)
- Semi-circular gauge may feel clinical/medical
- Score alone (small widget) may feel thin without context

**Complexity**: Medium
**Risk**: Low

---

## Approach 2: Factor-Forward — "The 4 Pillars"

**Summary**: Lead with the 4 stress factors as the primary visual element, showing which areas are contributing most to stress. The total score is secondary.

### Small (~155×155pt)
- **Header**: "Stress" + level icon
- **Hero**: 2×2 grid of factor icons, each with a colored background circle
  - Green circle = healthy factor, Red circle = stressed factor
  - Icons: 🏃 Exercise, 🛌 Sleep, 🥗 Diet, 📱 Screen
- **Footer**: Level label + total score in small text
- **Tap**: Deep-link to `wellplate://stress`

### Medium (~329×155pt)
- **4 factor columns** side by side (evenly spaced)
  - Each: Icon → circular progress ring → score label
  - Ring color: green→red based on that factor's contribution
- **Total score badge**: Right edge or top-right corner
- **Level label**: Below the badge
- **Tap**: Deep-link to `wellplate://stress`

### Large (~329×345pt)
- **Header**: Score + level label + encouragement text
- **4 factor rows**: Full-width cards with icon, title, progress bar, status text, detail text
- **Worst factor highlight**: The highest-contributing factor gets a subtle colored border or "⚠️ Focus area" tag
- **7-day factor trend**: Small area chart or stacked bar showing how each factor contributed over the week
- **Tap**: Deep-link to `wellplate://stress`

**Pros**:
- Immediately actionable — user sees *which factor* needs attention
- 2×2 grid in small widget is visually distinctive and information-dense
- "Focus area" highlight drives behavior change
- Differentiates from competitors who just show a single score

**Cons**:
- Small widget may feel cluttered with 4 elements
- Users may not immediately understand what the 4 icons mean (learning curve)
- Less dramatic "at a glance" impact than a single big number
- Factor progress rings in medium widget need careful sizing to fit

**Complexity**: Medium-High
**Risk**: Medium (visual density trade-off)

---

## Approach 3: Mood-Ring Ambient — "The Aura"

**Summary**: A visually striking, ambient approach where the entire widget background is colored/gradient-shifted based on stress level. Minimal text, maximum vibes.

### Small (~155×155pt)
- **Full-bleed gradient** background matching stress level color
- **Center**: Large SF Symbol icon (face.smiling / exclamationmark.triangle)
- **Below icon**: Level label ("Good") in contrasting text
- **Corner**: Small score number
- **Tap**: Deep-link to `wellplate://stress`

### Medium (~329×155pt)
- **Left**: Gradient background with large icon + level label
- **Right**: White/system-background panel with:
  - Score number
  - Change indicator: "↓ 8 from yesterday" or "↑ 12 from yesterday"
  - Top contributing factor with icon
- **Tap**: Deep-link to `wellplate://stress`

### Large (~329×345pt)
- **Top section**: Full-width gradient banner with score, icon, level, encouragement
- **Middle**: 4 factors as icon chips with colored backgrounds
- **Bottom**: 7-day trend sparkline with colored dots per day
- **Tap**: Deep-link to `wellplate://stress`

**Pros**:
- Extremely glanceable — color tells the story before you read anything
- Visually distinctive on the Home Screen (stands out from other widgets)
- Emotional/ambient feel aligns with wellness app positioning
- Minimal text = works at any glance speed

**Cons**:
- Full-bleed color may clash with user's wallpaper or other widgets
- Less informational density — some users want numbers
- "Excellent" and "Good" levels use `.primary.opacity()` which is subtle — may need widget-specific colors
- Accessibility concern: color-only encoding fails for color-blind users (mitigated by icon + label)

**Complexity**: Low-Medium
**Risk**: Medium (aesthetic risk — polarizing design)

---

## Approach 4: Hybrid — "Score + Top Factor" (Recommended)

**Summary**: Combine the best of Approaches 1 and 2. Lead with score/gauge but always surface the #1 contributing factor as an actionable callout.

### Small (~155×155pt)
- **Header row**: "Stress" label + level SF Symbol icon (colored)
- **Hero**: Circular progress ring (like the existing CalorieRingView pattern) filled by stress score
  - Ring color: StressLevel.color
  - Center: Score number (bold, large) + "/100" small
- **Footer**: Level label ("Good") — or if score is high, show top factor: "📱 Screen Time"
- **Background**: Subtle gradient tint matching stress level color
- **Tap**: `wellplate://stress`

### Medium (~329×155pt)
- **Left column** (~40% width):
  - Stress ring (same pattern as small) — 94×94pt
  - Level label below
- **Right column** (~60% width):
  - **Top factor callout**: "Biggest contributor" → icon + factor name + score bar
  - **Quick stats row**: 2 key vitals — Resting HR + HRV (the most meaningful stress indicators)
    - e.g., "❤️ 62 bpm  |  💚 42ms HRV"
  - **Change indicator**: "↓ 5 from yesterday" in green/red
- **Tap**: `wellplate://stress`

### Large (~329×345pt)
- **Header**: "Stress Level" + date
- **Score section**: Large ring + score + level label + encouragement text
- **4-factor breakdown**: Horizontal rows with icon, name, progress bar, contribution score
  - Highest contributor gets accent highlight
- **Trend section**: 7-day bar chart or sparkline with colored bars per day
  - Each bar colored by that day's StressLevel.color
- **Key vitals row**: Resting HR, HRV, Respiratory Rate (latest values)
- **Tap**: `wellplate://stress`

**Pros**:
- Score is the hero (fast glance), factor is the actionable insight (deeper glance)
- Reuses `CalorieRingView` pattern — consistent with existing food widget visual language
- HealthKit vitals in medium/large add credibility and "real data" feeling
- 7-day trend in large satisfies users who want to track progress
- Change indicator drives daily engagement ("am I better than yesterday?")
- Background tint gives the ambient color effect without full-bleed risk

**Cons**:
- Medium widget packs a lot of information — needs very careful layout
- Vitals data may not always be available (need graceful fallback)
- Slightly more complex data model for widget (score + factors + vitals + history)

**Complexity**: Medium
**Risk**: Low

---

## Widget Data Model (Shared via App Group)

Regardless of approach, we'll need a shared data structure:

```swift
struct WidgetStressData: Codable {
    // Core
    var totalScore: Double          // 0–100
    var level: String               // StressLevel.rawValue
    var encouragement: String       // StressLevel.encouragementText
    
    // Factors (4)
    var factors: [WidgetStressFactor]
    
    // Optional vitals
    var restingHR: Double?          // bpm
    var hrv: Double?                // ms
    var respiratoryRate: Double?    // breaths/min
    
    // Trend (last 7 days)
    var weeklyScores: [DayScore]    // [{date, score}]
    
    // Comparison
    var yesterdayScore: Double?
    
    // Meta
    var lastUpdated: Date
}

struct WidgetStressFactor: Codable, Identifiable {
    var id: String { title }
    let title: String           // "Exercise", "Sleep", etc.
    let icon: String            // SF Symbol name
    let score: Double           // 0–25
    let maxScore: Double        // 25
    let contribution: Double    // stress contribution (0–25)
    let hasValidData: Bool
}

struct DayScore: Codable {
    let date: Date
    let score: Double
}
```

---

## Edge Cases to Consider

- [ ] **No data yet**: First-time user with no stress readings — show "Open app to get started" placeholder
- [ ] **Partial factors**: Some factors have data, others don't — show available ones, gray out missing
- [ ] **Stale data**: Last update was >24h ago — show staleness indicator or "last updated" timestamp
- [ ] **Score = 0**: Technically "Excellent" but could also mean no data — need to distinguish
- [ ] **Dark mode**: StressLevel colors (especially .primary.opacity for excellent/good) need to look good on both dark and light widget backgrounds
- [ ] **Widget background**: iOS 17+ containerBackground vs. older fallback
- [ ] **Accessibility**: VoiceOver labels for gauge/rings, Dynamic Type for text
- [ ] **7-day trend with gaps**: Days with no readings should show as gaps or faded dots, not zero
- [ ] **Deep-link routing**: Current deep-link is `wellplate://logFood` — need new `wellplate://stress` route

---

## Open Questions

- [ ] Should we keep the food widget as a second widget option, or fully replace it?
- [ ] Should the small widget show the numeric score or just the level label + icon?
- [ ] Is 7-day trend worth the data complexity in the large widget, or is "vs. yesterday" sufficient?
- [ ] Should we include a "Breathe" quick-action button (like Apple's Mindfulness widget)?
- [ ] Do we want Lock Screen widgets (`.accessoryCircular`, `.accessoryRectangular`) in addition to Home Screen?

---

## Recommendation

**Approach 4: Hybrid "Score + Top Factor"** — it combines the best elements:

1. **Small**: Stress ring + score is instantly glanceable (like Apple's Activity ring)
2. **Medium**: Score ring + top factor + vitals gives actionable info without clutter
3. **Large**: Full breakdown + trend satisfies power users who want the complete picture

This approach reuses the `CalorieRingView` pattern (consistency), surfaces actionable insights (which factor to work on), and scales naturally across widget sizes. The 7-day trend in the large widget drives daily engagement and makes the widget feel alive over time.

**Key design principle**: Each size should answer a progressively deeper question:
- **Small** → "How stressed am I right now?" (score + color)
- **Medium** → "What's causing my stress?" (top factor + vitals)
- **Large** → "How am I trending?" (full breakdown + 7-day history)

---

## Research References

- Existing stress model: `WellPlate/Models/StressModels.swift` (StressLevel enum, StressFactorResult)
- Current food widget pattern: `WellPlateWidget/` (FoodWidget.swift, Views/)
- Shared data pattern: `WellPlate/Widgets/SharedFoodData.swift` (WidgetFoodData)
- Creative stress features brainstorm: `Docs/01_Brainstorming/260403-creative-stress-features-brainstorm.md`
- Apple WidgetKit docs: HIG widget design guidelines
