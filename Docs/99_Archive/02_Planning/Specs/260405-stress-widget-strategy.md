# Strategy: Stress Level Widget

**Date**: 2026-04-05
**Source**: `Docs/01_Brainstorming/260405-stress-widget-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Hybrid "Score + Top Factor"** — a circular stress ring (score as hero) plus the top contributing factor as an actionable callout, scaling in depth across the three widget sizes. Small answers "how stressed am I?", medium adds "what's causing it?", large adds "how am I trending?".

---

## Rationale

- **Score ring is immediately legible** — the circular ring pattern from `CalorieRingView` already exists; adapting it avoids introducing a novel visual primitive and keeps the widget family visually coherent
- **Factor callout drives behavior change** without adding visual complexity — showing the single worst factor is more actionable than showing all four
- **Vitals in medium/large (Resting HR + HRV)** add biological credibility; these are the two most correlated HealthKit signals to stress and are already fetched by `StressViewModel`
- **7-day trend in large** turns a snapshot into a story — the brainstorm noted this is the key differentiator for power users
- **Rejected Approach 3 (Mood-Ring/Aura)**: Full-bleed color is too sparse on information and `.primary.opacity()` used for excellent/good levels is nearly invisible against default widget backgrounds — would require maintaining a separate widget-specific color palette anyway
- **Rejected Approach 2 (4 Pillars)**: 2×2 grid in the small widget is too dense; factor rings in medium need precise sizing that is fragile across device sizes
- **Key trade-off accepted**: Medium widget carries more information than the food equivalent — this is intentional; stress data is inherently multi-dimensional and users benefit from the extra context

---

## Affected Files & Components

### Delete (food widget — fully replaced)
- `WellPlateWidget/FoodWidget.swift` — replaced by `StressWidget.swift`
- `WellPlateWidget/Views/FoodSmallView.swift` — replaced by `StressSmallView.swift`
- `WellPlateWidget/Views/FoodMediumView.swift` — replaced by `StressMediumView.swift`
- `WellPlateWidget/Views/FoodLargeView.swift` — replaced by `StressLargeView.swift`
- `WellPlate/Widgets/SharedFoodData.swift` — replaced by `SharedStressData.swift`

### Modify
- `WellPlateWidget/WellPlateWidgetBundle.swift` — swap `FoodWidget()` for `StressWidget()`
- `WellPlateWidget/Views/SharedWidgetViews.swift` — replace `CalorieRingView` + `MacroBarRow` with `StressRingView` + `StressFactorBar`; keep `wellPlateWidgetBackground` modifier unchanged
- `WellPlate/Core/Services/WidgetRefreshHelper.swift` — replace `refresh(goals:context:)` with `refreshStress(viewModel:)` that serializes `WidgetStressData` and calls `WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.stressWidget")`
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — call `WidgetRefreshHelper.refreshStress(viewModel: self)` at the end of `loadData()` after all factors and vitals are populated
- `WellPlate/App/WellPlateApp.swift` — add `wellplate://stress` deep-link handler that switches the active tab to Stress (tab index 2)

### Create
- `WellPlate/Widgets/SharedStressData.swift` — shared data model (Codable, AppGroup UserDefaults, `.empty` + `.placeholder` presets)
- `WellPlateWidget/StressWidget.swift` — `StressEntry`, `StressWidgetProvider`, `StressWidgetEntryView`, `StressWidget` declaration
- `WellPlateWidget/Views/StressSmallView.swift`
- `WellPlateWidget/Views/StressMediumView.swift`
- `WellPlateWidget/Views/StressLargeView.swift`

---

## Architectural Direction

The solution follows the **exact same data-flow pattern** as the existing food widget:

```
StressViewModel.loadData()
  └─ (async, after all factors + vitals resolved)
       └─ WidgetRefreshHelper.refreshStress(viewModel:)
            └─ serialize WidgetStressData → AppGroup UserDefaults
                 └─ WidgetCenter.reloadTimelines("stressWidget")
                      └─ StressWidgetProvider.getTimeline()
                           └─ WidgetStressData.load() → StressEntry
                                └─ StressSmallView / StressMediumView / StressLargeView
```

**Shared data model** lives in `WellPlate/Widgets/SharedStressData.swift` (main app target) — the widget extension reads it via the same App Group (`group.com.hariom.wellplate`).

**StressLevel colors** — the existing `StressLevel.color` uses `.primary.opacity()` for excellent/good, which is invisible on widget backgrounds. `SharedStressData.swift` will define a `widgetColor` computed property on `StressLevel` with explicit hex colors that work on both light and dark widget backgrounds:
- excellent → `Color(hue: 0.33, saturation: 0.60, brightness: 0.72)` (sage green)
- good → `Color(hue: 0.27, saturation: 0.55, brightness: 0.70)` (yellow-green)
- moderate → reuse existing amber
- high → reuse existing terracotta
- veryHigh → reuse existing rust

**7-day trend** — `StressViewModel.weekReadings: [StressReading]` contains intraday samples. The refresh helper aggregates these into one `DayScore` per day (average score) before serializing. Days with zero readings are encoded as `score: -1` to allow the large view to render them as a faded bar.

---

## Design Constraints

1. **Ring reuse**: `StressRingView` must mirror `CalorieRingView`'s structure (ZStack of track Circle + trimmed fill Circle + center labels) — use `StressLevel.widgetColor` for the fill gradient endpoints
2. **No WidgetKit interactivity** beyond `Link` deep-links — no buttons, toggles, or app intents in this pass
3. **Graceful no-data**: All views must render correctly when `WidgetStressData.load()` returns `.empty` — show a "Open app to start" placeholder state
4. **Background tint**: Use `wellPlateWidgetBackground` with a subtle `LinearGradient` of `stressLevel.widgetColor.opacity(0.07)` — matches food widget's warm-tint pattern, never a full-bleed color
5. **Deep-link URL scheme**: `wellplate://stress` — verify the app already handles `wellplate://` and add the `stress` path alongside `logFood`
6. **Widget kind**: `"com.hariom.wellplate.stressWidget"` — distinct from the food kind so any existing home-screen placements of the food widget don't break silently

---

## Non-Goals

- Lock Screen widgets (`.accessoryCircular`, `.accessoryRectangular`) — future pass
- "Breathe / meditate" interactive intent button — requires `AppIntent`, future pass
- Keeping the food widget as a second option in the bundle — fully replaced
- Intraday stress chart in any widget size — too much data for WidgetKit's static rendering
- Push-driven widget refresh (background delivery) — existing 30-min pull model is sufficient

---

## Open Risks

- **StressReading availability on first launch**: `weekReadings` may be empty for new users. Mitigation: render the trend section in the large widget as "Not enough data yet" when `weeklyScores` has < 2 entries
- **WidgetRefreshHelper call site**: `StressViewModel.loadData()` is async/MainActor — the refresh call must be on the main actor after `await` completes. Ensure `WidgetRefreshHelper.refreshStress` is also `@MainActor` or actor-isolated safely
- **StressLevel.color opacity issue**: Widget-specific colors must be tested against both light and dark widget appearances; `.primary.opacity(0.45)` becomes near-white on dark backgrounds and is illegible
- **App Group entitlement on widget target**: Already set for food widget (`WellPlateWidget.entitlements`) — no change needed, but verify the new `stressWidget` kind is reloaded correctly and old `foodWidget` kind is no longer registered
