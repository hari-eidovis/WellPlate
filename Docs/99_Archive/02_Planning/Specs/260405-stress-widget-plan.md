# Implementation Plan: Stress Level Widget

## Overview

Replace the existing Food Log widget with a Stress Level widget across all three WidgetKit families (small, medium, large). The widget surfaces the app's 0–100 stress score, top contributing factor, key vitals, and a 7-day trend — using the same App Group + UserDefaults data-sharing pattern already established by the food widget.

## Requirements

- Remove all food widget code from the widget extension
- New `WidgetStressData` shared data model with App Group persistence
- Stress ring view (adapted from `CalorieRingView`) with level-aware colors
- Three widget sizes with progressive information depth
- Widget refresh triggered from `StressViewModel.loadData()`
- Deep-link `wellplate://stress` to switch to Stress tab
- Graceful empty/partial data states

## Architecture Changes

| File | Action | Description |
|---|---|---|
| `WellPlate/Widgets/SharedFoodData.swift` | Delete | Replaced by SharedStressData |
| `WellPlateWidget/FoodWidget.swift` | Delete | Replaced by StressWidget |
| `WellPlateWidget/Views/FoodSmallView.swift` | Delete | Replaced by StressSmallView |
| `WellPlateWidget/Views/FoodMediumView.swift` | Delete | Replaced by StressMediumView |
| `WellPlateWidget/Views/FoodLargeView.swift` | Delete | Replaced by StressLargeView |
| `WellPlate/Widgets/SharedStressData.swift` | Create | Shared Codable data model |
| `WellPlateWidget/StressWidget.swift` | Create | Timeline provider + widget declaration |
| `WellPlateWidget/Views/StressSmallView.swift` | Create | Small widget view |
| `WellPlateWidget/Views/StressMediumView.swift` | Create | Medium widget view |
| `WellPlateWidget/Views/StressLargeView.swift` | Create | Large widget view |
| `WellPlateWidget/Views/SharedWidgetViews.swift` | Rewrite | Replace CalorieRingView/MacroBarRow with StressRingView/StressFactorBar |
| `WellPlateWidget/WellPlateWidgetBundle.swift` | Modify | Swap `FoodWidget()` → `StressWidget()` |
| `WellPlate/Core/Services/WidgetRefreshHelper.swift` | Rewrite | Replace food refresh with stress refresh |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Modify | Add widget refresh call at end of `loadData()` |
| `WellPlate/Features + UI/Tab/MainTabView.swift` | Modify | Add `.onOpenURL` handler for `wellplate://stress` |

---

## Implementation Steps

### Phase 1: Shared Data Model

**1.1 Create `SharedStressData.swift`** (File: `WellPlate/Widgets/SharedStressData.swift`)
- Action: Create new file with `WidgetStressData`, `WidgetStressFactor`, and `WidgetDayScore` structs
- All structs must be `Codable` — no SwiftData or HealthKit imports
- Use same App Group pattern: `group.com.hariom.wellplate`, key `"widgetStressData"`
- Include `load()` and `save()` static/instance methods matching `WidgetFoodData`'s pattern
- Add `isDateInToday` guard in `load()` to return `.empty` for stale data
- Include widget-specific color computation (cannot use SwiftUI `Color` in Codable — store raw hue/saturation/brightness or use a `String` level and compute color in the view)
- Data shape:
  ```swift
  struct WidgetStressData: Codable {
      var totalScore: Double          // 0–100
      var levelRaw: String            // StressLevel raw value ("Excellent", "Good", etc.)
      var encouragement: String
      var factors: [WidgetStressFactor]  // always 4
      var restingHR: Double?
      var hrv: Double?
      var respiratoryRate: Double?
      var weeklyScores: [WidgetDayScore] // last 7 days
      var yesterdayScore: Double?
      var lastUpdated: Date
  }

  struct WidgetStressFactor: Codable {
      let title: String
      let icon: String
      let score: Double           // 0–25 (factor score, not stress contribution)
      let maxScore: Double        // 25
      let contribution: Double    // stress contribution 0–25
      let hasValidData: Bool
  }

  struct WidgetDayScore: Codable {
      let date: Date
      let score: Double           // -1 = no data
  }
  ```
- Add `static var empty` (score 0, empty factors, no vitals) and `static var placeholder` (score 32 "Good", sample factors, sample vitals, 7-day sample scores)
- Dependencies: None
- Risk: Low

**1.2 Delete `SharedFoodData.swift`** (File: `WellPlate/Widgets/SharedFoodData.swift`)
- Action: Delete the file entirely
- Verify no other code references `WidgetFoodData` or `WidgetFoodItem` outside the widget extension (the widget extension files that reference it are also being deleted)
- Dependencies: Step 1.1 (replacement exists)
- Risk: Low

---

### Phase 2: Widget Extension — Core Infrastructure

**2.1 Rewrite `SharedWidgetViews.swift`** (File: `WellPlateWidget/Views/SharedWidgetViews.swift`)
- Action: Replace `CalorieRingView` and `MacroBarRow` with new shared components
- Keep `wellPlateWidgetBackground` modifier unchanged
- New components:

  **`StressRingView`** — circular ring showing stress score:
  - ZStack: track Circle (level color at 0.18 opacity) + trimmed fill Circle + center labels
  - Fill: `AngularGradient` using widget-specific stress colors (not `.primary.opacity()`)
  - Center: score number (bold, rounded, 18pt) + "/ 100" (10pt, secondary)
  - Fraction: `totalScore / 100.0` (clamped 0–1)
  - Color logic based on `levelRaw` string:
    - "Excellent" → `Color(hue: 0.33, saturation: 0.60, brightness: 0.72)` (sage green)
    - "Good" → `Color(hue: 0.27, saturation: 0.55, brightness: 0.70)` (yellow-green)
    - "Moderate" → `Color(hue: 0.12, saturation: 0.55, brightness: 0.72)` (amber)
    - "High" → `Color(hue: 0.06, saturation: 0.60, brightness: 0.70)` (terracotta)
    - "Very High" → `Color(hue: 0.01, saturation: 0.65, brightness: 0.65)` (rust)
  - Extract this into a helper: `static func widgetColor(for levelRaw: String) -> Color`

  **`StressFactorBar`** — horizontal bar for a single factor:
  - Same layout as `MacroBarRow` but adapted:
  - Label row: icon (SF Symbol) + title + contribution score (e.g., "8/25")
  - Progress bar: filled width = `contribution / 25.0`
  - Bar color: green→red based on contribution (high contribution = more stress = redder)
    - `Color(hue: 0.33 * (1.0 - contribution/25.0), saturation: 0.65, brightness: 0.75)`
  - Gray out if `!hasValidData`

- Dependencies: Step 1.1 (uses `WidgetStressData`)
- Risk: Low

**2.2 Create `StressWidget.swift`** (File: `WellPlateWidget/StressWidget.swift`)
- Action: Create timeline provider and widget declaration, mirroring `FoodWidget.swift` structure
- `StressEntry: TimelineEntry` with `date: Date` and `data: WidgetStressData`
- `StressWidgetProvider: TimelineProvider`:
  - `placeholder`: return `.placeholder`
  - `getSnapshot`: return `.placeholder` if `isPreview`, else `WidgetStressData.load()`
  - `getTimeline`: load data, schedule next refresh at now + 30 minutes
- `StressWidgetEntryView`: switch on `widgetFamily` → Small/Medium/Large
- `StressWidget: Widget`:
  - kind: `"com.hariom.wellplate.stressWidget"`
  - displayName: `"Stress Level"`
  - description: `"Monitor your stress score and top factors."`
  - supportedFamilies: `[.systemSmall, .systemMedium, .systemLarge]`
- Dependencies: Step 1.1, Step 2.1
- Risk: Low

**2.3 Delete `FoodWidget.swift`** (File: `WellPlateWidget/FoodWidget.swift`)
- Action: Delete the file
- Dependencies: Step 2.2 (replacement exists)
- Risk: Low

**2.4 Update `WellPlateWidgetBundle.swift`** (File: `WellPlateWidget/WellPlateWidgetBundle.swift`)
- Action: Replace `FoodWidget()` with `StressWidget()`
- Dependencies: Step 2.2
- Risk: Low

---

### Phase 3: Widget Views

**3.1 Create `StressSmallView.swift`** (File: `WellPlateWidget/Views/StressSmallView.swift`)
- Action: Create small widget (~155×155pt) — answers "How stressed am I?"
- Layout:
  ```
  ┌──────────────────────┐
  │ Stress    [face.icon] │  ← header: "Stress" label + SF Symbol colored by level
  │                       │
  │      ┌──────┐        │
  │      │  32  │        │  ← StressRingView (82×82pt)
  │      │ /100 │        │
  │      └──────┘        │
  │                       │
  │       Good            │  ← level label
  │                       │
  │  📱 Screen Time       │  ← top factor (only if score >= moderate, else encouragement)
  └──────────────────────┘
  ```
- Wrap in `Link(destination: URL(string: "wellplate://stress")!)`
- Background: `wellPlateWidgetBackground` with subtle gradient tint using level color at 0.06 opacity
- Empty state: When `data.totalScore == 0 && data.factors.isEmpty` → show "Open WellPlate to get started" with app icon
- Dependencies: Step 2.1 (StressRingView), Step 1.1
- Risk: Low

**3.2 Create `StressMediumView.swift`** (File: `WellPlateWidget/Views/StressMediumView.swift`)
- Action: Create medium widget (~329×155pt) — answers "What's causing it?"
- Layout:
  ```
  ┌─────────────┬─────────────────────────────┐
  │   Stress    │  Top Factor                  │
  │             │  📱 Screen Time  ████░ 20/25 │
  │  ┌──────┐   │                              │
  │  │  32  │   │  ❤️ 62 bpm  |  💚 42ms HRV  │  ← vitals row (if available)
  │  │ /100 │   │                              │
  │  └──────┘   │  ↓ 5 from yesterday          │  ← change indicator (green if lower, red if higher)
  │   Good      │                              │
  └─────────────┴─────────────────────────────┘
  ```
- Left column (114pt width): "Stress" label + StressRingView (94×94) + level label
- Vertical divider (same pattern as FoodMediumView)
- Right column:
  - Top contributing factor: find factor with highest `contribution` — show icon + name + StressFactorBar
  - Vitals row: Show Resting HR + HRV if available (caption2 text, monospaced digits)
  - Change indicator: Compare `totalScore` vs `yesterdayScore` — show "↓ X from yesterday" in green or "↑ X from yesterday" in red/terracotta. Hide if `yesterdayScore` is nil
- Empty state: "Open WellPlate" message (same as small)
- Dependencies: Step 2.1, Step 1.1
- Risk: Medium (layout density — needs careful spacing)

**3.3 Create `StressLargeView.swift`** (File: `WellPlateWidget/Views/StressLargeView.swift`)
- Action: Create large widget (~329×345pt) — answers "How am I trending?"
- Layout:
  ```
  ┌─────────────────────────────────────────────┐
  │ 🧠 Stress Level                  Apr 5      │  ← header
  │                                              │
  │       ┌──────┐                               │
  │       │  32  │   Good                        │  ← ring + level + encouragement
  │       │ /100 │   Keep up the good work!      │
  │       └──────┘                               │
  │ ──────────────────────────────────────────── │
  │ 🏃 Exercise    ████████░░░  5/25             │  ← 4 factor bars
  │ 🌙 Sleep       ██████░░░░  8/25              │
  │ 🥗 Diet        ████░░░░░░  12/25             │
  │ 📱 Screen Time ██████████  20/25             │  ← highest = highlighted
  │ ──────────────────────────────────────────── │
  │ 7-Day Trend                                  │
  │ ▁▂▃▂▄▃▂                                     │  ← mini bar chart
  │ M T W T F S S                                │
  │                                              │
  │ ❤️ 62 bpm   💚 42ms   🫁 16 br/min          │  ← vitals row
  └─────────────────────────────────────────────┘
  ```
- Header: brain icon + "Stress Level" + date
- Score section: HStack with StressRingView (80×80) on left, VStack with level label + encouragement on right
- Divider
- 4 factor rows: `ForEach(data.factors)` → `StressFactorBar` for each. Highlight the highest contributor with a subtle background tint
- Divider
- 7-day trend: HStack of mini bars using `data.weeklyScores`
  - Each bar: `RoundedRectangle` with height proportional to score (0–100 → 0–40pt)
  - Color: widget color for that day's level
  - Day-of-week labels below (M, T, W, etc.)
  - If < 2 entries → show "Not enough data yet" text instead
  - Days with score == -1 → show faded/gray bar at minimal height
- Vitals row: Resting HR, HRV, Respiratory Rate — show only values that are non-nil
- Dependencies: Step 2.1, Step 1.1
- Risk: Medium (most complex layout — needs careful vertical space budgeting)

**3.4 Delete food widget views**
- Delete `WellPlateWidget/Views/FoodSmallView.swift`
- Delete `WellPlateWidget/Views/FoodMediumView.swift`
- Delete `WellPlateWidget/Views/FoodLargeView.swift`
- Dependencies: Steps 3.1–3.3 (replacements exist)
- Risk: Low

---

### Phase 4: App-Side Integration

**4.1 Rewrite `WidgetRefreshHelper.swift`** (File: `WellPlate/Core/Services/WidgetRefreshHelper.swift`)
- Action: Replace the food-specific `refresh(goals:context:)` with `refreshStress(viewModel:)`
- New signature: `static func refreshStress(viewModel: StressViewModel)`
- Method body:
  1. Build `WidgetStressFactor` array from `viewModel.allFactors`
  2. Build `weeklyScores` by grouping `viewModel.weekReadings` by day, averaging scores per day
  3. Compute `yesterdayScore` from `weeklyScores` for yesterday's date
  4. Populate `WidgetStressData` with totalScore, level, encouragement, factors, vitals, weeklyScores
  5. Call `.save()` on the data
  6. Call `WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.stressWidget")`
- Must be `@MainActor` (accesses viewModel properties which are `@Published` on MainActor)
- Dependencies: Step 1.1
- Risk: Low

**4.2 Add widget refresh call to `StressViewModel.loadData()`** (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)
- Action: Add `WidgetRefreshHelper.refreshStress(viewModel: self)` at the very end of `loadData()`, after line 294 (after all vitals are extracted)
- This ensures the widget gets the complete picture — all 4 factors + 30-day vitals are populated before the refresh
- Also add the call after `logCurrentStress(source:)` in `loadData()` — actually, just place it as the last line of `loadData()` since that runs after everything else
- Dependencies: Step 4.1
- Risk: Low

**4.3 Add deep-link handler** (File: `WellPlate/Features + UI/Tab/MainTabView.swift`)
- Action: Add `.onOpenURL` modifier to the `TabView` to handle `wellplate://stress`
- Implementation:
  ```swift
  .onOpenURL { url in
      guard url.scheme == "wellplate" else { return }
      switch url.host {
      case "stress": selectedTab = 2
      case "logFood": selectedTab = 0  // preserve existing food deep-link if needed
      default: break
      }
  }
  ```
- Note: Currently the app has NO `.onOpenURL` handler anywhere — the food widget's `wellplate://logFood` deep-link was never actually handled. This step adds the handler for both old and new routes
- Dependencies: None
- Risk: Low

---

### Phase 5: Build Verification

**5.1 Build main app target**
- Command: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- Verify: No compile errors from deleted `WidgetFoodData` references, new `WidgetStressData` compiles, `WidgetRefreshHelper` changes compile
- Dependencies: All Phase 1–4 steps

**5.2 Build widget target**
- Command: `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
- Verify: Widget extension compiles with all new views, no references to deleted food types
- Dependencies: All Phase 1–4 steps

---

## Testing Strategy

- **Build verification**: Both main app and widget targets compile (Phase 5)
- **Manual verification**:
  - [ ] Add stress widget (all 3 sizes) to simulator Home Screen
  - [ ] Verify placeholder appearance in widget gallery
  - [ ] Open app → navigate to Stress tab → widget should update within 30s
  - [ ] Verify small widget shows score ring + level label
  - [ ] Verify medium widget shows ring + top factor + vitals
  - [ ] Verify large widget shows ring + all 4 factors + 7-day trend + vitals
  - [ ] Tap any widget → app opens to Stress tab
  - [ ] Verify dark mode appearance (colors visible on dark background)
  - [ ] Verify empty state when no stress data exists

---

## Risks & Mitigations

- **Risk**: `StressLevel` widget colors look different from main app colors
  - Mitigation: Widget colors are intentionally explicit hex values (not `.primary.opacity()`) — this is by design for visibility. Document the difference
  
- **Risk**: `weekReadings` empty for new users → large widget trend section looks broken
  - Mitigation: Show "Not enough data yet" text when `weeklyScores` has < 2 valid entries

- **Risk**: Vitals (Resting HR, HRV, RR) all nil → medium/large widget has empty space
  - Mitigation: Only render vitals row when at least one value is non-nil; fill remaining space with encouragement text or expand factor section

- **Risk**: Existing food widget on user's Home Screen will disappear after update
  - Mitigation: Unavoidable — the food widget kind is being removed. Users will need to add the new stress widget manually. This is acceptable per the user's intent to fully replace it

- **Risk**: No `.onOpenURL` existed before — adding it might conflict with other URL handling
  - Mitigation: Checked — no `.onOpenURL` exists anywhere in the codebase. The handler is additive with no conflicts

---

## Success Criteria

- [ ] Food widget code fully removed (no `FoodWidget`, `WidgetFoodData`, or food view files remain)
- [ ] Stress widget appears in widget gallery with correct name, description, and preview
- [ ] Small widget shows stress ring with score, level label, and level icon
- [ ] Medium widget shows ring + top contributing factor + available vitals + yesterday comparison
- [ ] Large widget shows ring + 4-factor breakdown + 7-day trend + vitals
- [ ] Tapping any widget deep-links to Stress tab in app
- [ ] Widget updates when stress data refreshes in app
- [ ] Both main app and widget extension targets build successfully
- [ ] Empty/partial data states render gracefully (not blank or crashed)
