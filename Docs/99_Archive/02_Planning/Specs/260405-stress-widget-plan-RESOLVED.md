# Implementation Plan: Stress Level Widget (RESOLVED)

## Audit Resolution Summary

| Issue | Severity | Resolution |
|---|---|---|
| #1 `ProfileView.swift` references `WidgetFoodData` — not in plan | CRITICAL | Added to Architecture Changes table + new Step 4.4 to replace food widget preview with stress widget preview |
| #2 `GoalsViewModel` and `HomeViewModel` call deleted `refresh(goals:context:)` | CRITICAL | Added Step 4.5 to remove both call sites since food widget no longer exists |
| #3 Deep-link placement contradiction (strategy: WellPlateApp, plan: MainTabView) | HIGH | Moved handler to `RootView.swift` with `pendingDeepLink` state that propagates to `MainTabView.selectedTab`. Handles cold launches correctly |
| #4 `weekReadings` empty on unauthorized path | HIGH | Step 4.2 now adds unconditional `loadReadings()` call before widget refresh |
| #5 Field mapping ambiguity (`contribution` vs `stressContribution`) | HIGH | Added explicit field mapping table to Step 4.1 |
| #6 Empty state: `totalScore == 0` ambiguity | MEDIUM | Added `hasAnyValidData` computed property to `WidgetStressData`; empty state uses it |
| #7 Missing `default:` case in widget family switch | MEDIUM | Added `default: StressSmallView` to Step 2.2 |
| #8 `WidgetDayScore` name diverges from brainstorm's `DayScore` | MEDIUM | Confirmed `WidgetDayScore` as canonical — noted as intentional |
| #9 Day-of-week labels must be dynamic, not hardcoded | MEDIUM | Step 3.3 now specifies deriving labels from `date` using `Calendar.shortWeekdaySymbols` |
| #10 `score == -1` sentinel is fragile | MEDIUM | Changed `WidgetDayScore.score` to `Double?` — nil = no data |
| #11 No VoiceOver labels on ring view | LOW | Added `.accessibilityLabel` note to Step 2.1 |
| #12 Widget not refreshed from `refreshDietFactor` / `refreshScreenTimeOnly` | LOW | Documented as known limitation in Risks & Mitigations |
| #13 `getSnapshot` returns placeholder for preview contexts | LOW | No change needed — matches food widget behavior |

---

## Overview

Replace the existing Food Log widget with a Stress Level widget across all three WidgetKit families (small, medium, large). The widget surfaces the app's 0–100 stress score, top contributing factor, key vitals, and a 7-day trend — using the same App Group + UserDefaults data-sharing pattern already established by the food widget.

## Requirements

- Remove all food widget code from the widget extension and main app
- New `WidgetStressData` shared data model with App Group persistence
- Stress ring view (adapted from `CalorieRingView`) with level-aware colors
- Three widget sizes with progressive information depth
- Widget refresh triggered from `StressViewModel.loadData()`
- Deep-link `wellplate://stress` to switch to Stress tab (including cold launches)
- Graceful empty/partial data states

## Architecture Changes

<!-- RESOLVED: #1 — Added ProfileView.swift, GoalsViewModel.swift, HomeViewModel.swift, RootView.swift -->

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
| `WellPlate/Core/Services/WidgetRefreshHelper.swift` | Rewrite | Remove food refresh, add stress refresh |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Modify | Add `loadReadings()` + widget refresh call at end of `loadData()` |
| `WellPlate/App/RootView.swift` | Modify | Add `.onOpenURL` handler with `pendingDeepLink` state |
| `WellPlate/Features + UI/Tab/MainTabView.swift` | Modify | Accept optional `pendingDeepLink` binding from RootView |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Modify | Replace food widget preview section (`FoodWidgetSize` enum, `WidgetPreview`, `SmallPreview`, `MediumPreview`, `LargePreview`, `WidgetSetupCard`, `SizePill`, `WidgetInstructionsSheet`) with stress widget equivalents |
| `WellPlate/Features + UI/Goals/ViewModels/GoalsViewModel.swift` | Modify | Remove `WidgetRefreshHelper.refresh(goals:context:)` call at line 19 |
| `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` | Modify | Remove `refreshWidget(for:)` method (lines 291–295) that calls deleted food refresh |

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
      
      // RESOLVED #6: explicit validity check for empty-state discrimination
      var hasAnyValidData: Bool {
          factors.contains { $0.hasValidData }
      }
  }

  struct WidgetStressFactor: Codable {
      let title: String
      let icon: String
      let score: Double           // 0–25 (factor score, not stress contribution)
      let maxScore: Double        // 25
      let contribution: Double    // stress contribution 0–25 (= stressContribution from StressFactorResult)
      let hasValidData: Bool
  }

  // RESOLVED #10: changed from Double with -1 sentinel to Double? for type safety
  struct WidgetDayScore: Codable {
      let date: Date
      let score: Double?          // nil = no data for this day
  }
  ```
- Add `static var empty` (score 0, empty factors, no vitals) and `static var placeholder` (score 32 "Good", sample factors, sample vitals, 7-day sample scores)
- Note: `WidgetDayScore` is the canonical name (not `DayScore` from the brainstorm) — the `Widget` prefix is consistent with `WidgetStressData` and `WidgetStressFactor` <!-- RESOLVED: #8 — naming confirmed as intentional -->
- Dependencies: None
- Risk: Low

**1.2 Delete `SharedFoodData.swift`** (File: `WellPlate/Widgets/SharedFoodData.swift`)
- Action: Delete the file entirely
- Note: Other files that reference `WidgetFoodData` / `WidgetFoodItem` (`ProfileView.swift`, `GoalsViewModel.swift`, `HomeViewModel.swift`) are updated in Phase 4 steps 4.4 and 4.5. The widget extension files that reference it are deleted in Phase 2/3.
- Dependencies: Step 1.1 (replacement exists), Steps 4.4 and 4.5 must run before build verification
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
  <!-- RESOLVED: #11 — added VoiceOver accessibility label -->
  - Add `.accessibilityLabel("Stress score: \(Int(data.totalScore)) out of 100, \(data.levelRaw)")` to the ZStack

  **`StressFactorBar`** — horizontal bar for a single factor:
  - Same layout as `MacroBarRow` but adapted:
  - Label row: icon (SF Symbol) + title + contribution score (e.g., "8/25")
  - Progress bar: filled width = `contribution / 25.0`
  - Bar color: green→red based on contribution (high contribution = more stress = redder)
    - `Color(hue: 0.33 * (1.0 - contribution/25.0), saturation: 0.65, brightness: 0.75)`
  - Gray out if `!hasValidData`

- Dependencies: Step 1.1 (uses `WidgetStressData`)
- Risk: Low

<!-- RESOLVED: #7 — added explicit default case -->
**2.2 Create `StressWidget.swift`** (File: `WellPlateWidget/StressWidget.swift`)
- Action: Create timeline provider and widget declaration, mirroring `FoodWidget.swift` structure
- `StressEntry: TimelineEntry` with `date: Date` and `data: WidgetStressData`
- `StressWidgetProvider: TimelineProvider`:
  - `placeholder`: return `.placeholder`
  - `getSnapshot`: return `.placeholder` if `isPreview`, else `WidgetStressData.load()`
  - `getTimeline`: load data, schedule next refresh at now + 30 minutes
- `StressWidgetEntryView`: switch on `widgetFamily` → Small/Medium/Large + **`default: StressSmallView(data: entry.data)`** fallback (mirrors existing food widget pattern for future WidgetFamily cases)
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

<!-- RESOLVED: #6 — empty state uses hasAnyValidData instead of factors.isEmpty -->
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
- Empty state: When `!data.hasAnyValidData && data.factors.isEmpty` → show "Open WellPlate to get started" with app icon. Note: if `factors` has 4 entries but all have `hasValidData: false`, this is a valid all-neutral state showing score 0 — this is NOT the empty state
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
  - Top contributing factor: find factor with highest `contribution` where `hasValidData == true` — show icon + name + StressFactorBar
  - Vitals row: Show Resting HR + HRV if available (caption2 text, monospaced digits). Only render this row when at least one vital is non-nil
  - Change indicator: Compare `totalScore` vs `yesterdayScore` — show "↓ X from yesterday" in green or "↑ X from yesterday" in red/terracotta. Hide if `yesterdayScore` is nil
- Empty state: "Open WellPlate" message (same as small)
- Dependencies: Step 2.1, Step 1.1
- Risk: Medium (layout density — needs careful spacing)

<!-- RESOLVED: #9 — day-of-week labels derived from dates, not hardcoded -->
<!-- RESOLVED: #10 — bars check score != nil instead of score != -1 -->
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
  │ ▁▂▃▂▄▃▂                                     │  ← mini bar chart (illustrative)
  │ S M T W T F S                                │  ← dynamic day labels
  │                                              │
  │ ❤️ 62 bpm   💚 42ms   🫁 16 br/min          │  ← vitals row
  └─────────────────────────────────────────────┘
  ```
- Header: brain icon + "Stress Level" + date
- Score section: HStack with StressRingView (80×80) on left, VStack with level label + encouragement on right
- Divider
- 4 factor rows: `ForEach(data.factors)` → `StressFactorBar` for each. Highlight the highest contributor (by `contribution` value) with a subtle background tint
- Divider
- 7-day trend: HStack of mini bars using `data.weeklyScores`
  - Each bar: `RoundedRectangle` with height proportional to score (0–100 → 0–40pt)
  - Color: widget color for that day's level (use `widgetColor(for:)` with `StressLevel(score:).rawValue`)
  - **Day-of-week labels must be derived from `dayScore.date`** using `Calendar.current.shortWeekdaySymbols` indexed by `Calendar.current.component(.weekday, from: date)` — NOT hardcoded. The ASCII diagram above is illustrative only
  - If `weeklyScores` has fewer than 2 entries with non-nil scores → show "Not enough data yet" text instead of bars
  - Days with `score == nil` → show faded gray bar at 2pt height (minimal) to indicate the day existed but had no readings
- Vitals row: Resting HR, HRV, Respiratory Rate — show only values that are non-nil. If all nil, hide the row entirely and let factor section expand
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

<!-- RESOLVED: #2 — renamed from "Rewrite" to clarify both food removal and stress addition -->
<!-- RESOLVED: #5 — added explicit field mapping table -->
**4.1 Replace `WidgetRefreshHelper.swift`** (File: `WellPlate/Core/Services/WidgetRefreshHelper.swift`)
- Action: Remove the food-specific `refresh(goals:context:)` method entirely (callers are cleaned up in Step 4.5). Add new `refreshStress(viewModel:)` method.
- New signature: `@MainActor static func refreshStress(viewModel: StressViewModel)`
- **Explicit field mapping** (`StressFactorResult` → `WidgetStressFactor`):

  | `WidgetStressFactor` field | Source from `StressFactorResult` |
  |---|---|
  | `.title` | `.title` |
  | `.icon` | `.icon` |
  | `.score` | `.score` (0–25, the factor's raw score) |
  | `.maxScore` | `.maxScore` (always 25) |
  | `.contribution` | **`.stressContribution`** (NOT `.score` — this is the stress-direction value) |
  | `.hasValidData` | `.hasValidData` |

- Method body:
  1. Build `[WidgetStressFactor]` from `viewModel.allFactors` using mapping table above
  2. Build `weeklyScores` by grouping `viewModel.weekReadings` by calendar day, averaging `.score` per day. Days within the 7-day window that have zero readings → `WidgetDayScore(date: dayDate, score: nil)`
  3. Compute `yesterdayScore` from grouped readings for yesterday's date (nil if no readings)
  4. Populate `WidgetStressData` with:
     - `totalScore`: `viewModel.totalScore`
     - `levelRaw`: `viewModel.stressLevel.rawValue`
     - `encouragement`: `viewModel.stressLevel.encouragementText`
     - `factors`: mapped array from step 1
     - `restingHR`: `viewModel.todayRestingHR`
     - `hrv`: `viewModel.todayHRV`
     - `respiratoryRate`: `viewModel.todayRespiratoryRate`
     - `weeklyScores`: from step 2
     - `yesterdayScore`: from step 3
     - `lastUpdated`: `.now`
  5. Call `.save()` on the data
  6. Call `WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.stressWidget")`
- Dependencies: Step 1.1
- Risk: Low

<!-- RESOLVED: #4 — added unconditional loadReadings() before widget refresh -->
**4.2 Add widget refresh call to `StressViewModel.loadData()`** (File: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`)
- Action: At the very end of `loadData()` (after line 294 — after all vitals are extracted), add two lines:
  ```swift
  // Ensure weekReadings is populated (SwiftData doesn't need HK auth)
  loadReadings()
  // Push latest data to widget
  WidgetRefreshHelper.refreshStress(viewModel: self)
  ```
- The unconditional `loadReadings()` call ensures `weekReadings` is always current from SwiftData, even if `logCurrentStress` was skipped due to HealthKit auth not yet granted. SwiftData access does not require HealthKit authorization.
- This ensures the widget gets the complete picture — all 4 factors + vitals + 7-day readings are populated before the refresh
- Dependencies: Step 4.1
- Risk: Low

<!-- RESOLVED: #3 — moved deep-link to RootView for cold-launch support -->
**4.3 Add deep-link handler** (File: `WellPlate/App/RootView.swift` + `WellPlate/Features + UI/Tab/MainTabView.swift`)
- Action: Handle `wellplate://stress` deep-link at the `RootView` level so it works even on cold launches (when splash/onboarding screens are showing). The URL is stored and forwarded to `MainTabView` once it appears.
- **RootView changes**:
  - Add `@State private var pendingDeepLink: URL? = nil`
  - Add `.onOpenURL { url in pendingDeepLink = url }` on the outer ZStack
  - Pass `pendingDeepLink` binding to `MainTabView`: `MainTabView(pendingDeepLink: $pendingDeepLink)`
- **MainTabView changes**:
  - Add `@Binding var pendingDeepLink: URL?` parameter
  - Add `.onChange(of: pendingDeepLink)` modifier:
    ```swift
    .onChange(of: pendingDeepLink) { _, url in
        guard let url, url.scheme == "wellplate" else { return }
        switch url.host {
        case "stress": selectedTab = 2
        default: break
        }
        pendingDeepLink = nil
    }
    ```
  - Update `MainTabView()` call in the `#Preview` to pass `.constant(nil)` for the binding
- **Why RootView**: If the user taps the widget during a cold launch, the app starts through `RootView` → splash → onboarding → `MainTabView`. If `.onOpenURL` is on `MainTabView`, it would miss URLs arriving while splash/onboarding is showing. Placing it on `RootView` catches all URLs, and the `pendingDeepLink` binding ensures `MainTabView` receives it once rendered.
- Dependencies: None
- Risk: Low

<!-- RESOLVED: #1 — new step for ProfileView food widget preview replacement -->
**4.4 Replace food widget preview in `ProfileView.swift`** (File: `WellPlate/Features + UI/Tab/ProfileView.swift`)
- Action: The ProfileView contains an entire food widget preview system that references `WidgetFoodData` and `WidgetFoodItem`. All of these must be replaced with stress widget equivalents:
  - **`FoodWidgetSize` enum** (lines 7–45): Rename to `StressWidgetSize`. Update the `previewDescription` property from food-specific copy to stress-specific:
    - Small: "Score ring + level" (was "Calorie ring + quick add")
    - Medium: "Ring + top factor + vitals" (was "Ring + macro bars")
    - Large: "Full breakdown + 7-day trend" (was "Full log + recent foods")
  - **`WidgetSetupCard`** (line 709): Update `@Binding var selectedSize: FoodWidgetSize` → `StressWidgetSize`. Update any food-widget copy/icons to stress-widget equivalents
  - **`SizePill`** (line 828): Update `let size: FoodWidgetSize` → `StressWidgetSize`
  - **`WidgetPreview`** (line 860): Replace `WidgetFoodData` mock with `WidgetStressData.placeholder`. Replace `SmallPreview`/`MediumPreview`/`LargePreview` invocations with stress versions
  - **`SmallPreview`** (line 910), **`MediumPreview`** (line 961), **`LargePreview`** (line 1011): Rewrite to show simplified stress widget previews using `WidgetStressData` instead of `WidgetFoodData`. These are in-app previews (not actual WidgetKit views) so they should approximate the widget appearance with SwiftUI
  - **`WidgetInstructionsSheet`** (line 1117): Update `let size: FoodWidgetSize` → `StressWidgetSize`
  - **`@State private var selectedSize: FoodWidgetSize`** in `ProfilePlaceholderView` (line 52): Change to `StressWidgetSize`
- Note: This file appears in git status as already modified (`M`). Check current working state before editing
- Dependencies: Step 1.1 (uses `WidgetStressData`)
- Risk: Medium (large file with many interconnected preview structs)

<!-- RESOLVED: #2 — new step to remove food widget refresh callers -->
**4.5 Remove food widget refresh call sites** (File: `GoalsViewModel.swift` + `HomeViewModel.swift`)
- Action: Since the food widget no longer exists, remove the orphaned `WidgetRefreshHelper.refresh(goals:context:)` calls:
  - **`WellPlate/Features + UI/Goals/ViewModels/GoalsViewModel.swift` line 19**: Delete the `WidgetRefreshHelper.refresh(goals: goals, context: modelContext)` call inside `save()`. The `try? modelContext.save()` line above it stays
  - **`WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` lines 291–295**: Delete the entire `refreshWidget(for:)` method. It was only used for the food widget pipeline
  - Also check if `refreshWidget(for:)` is called from anywhere in `HomeViewModel` or `HomeView` — if so, remove those call sites too
- Dependencies: Step 4.1 (new helper replaces old one)
- Risk: Low

---

### Phase 5: Build Verification

**5.1 Build main app target**
- Command: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- Verify: No compile errors from deleted `WidgetFoodData`/`WidgetFoodItem` references, new `WidgetStressData` compiles, `WidgetRefreshHelper` changes compile, `ProfileView` references updated, `GoalsViewModel`/`HomeViewModel` callers removed
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
  - [ ] Verify placeholder appearance in widget gallery (always shows placeholder data)
  - [ ] Open app → navigate to Stress tab → widget should update within 30s
  - [ ] Verify small widget shows score ring + level label
  - [ ] Verify medium widget shows ring + top factor + vitals
  - [ ] Verify large widget shows ring + all 4 factors + 7-day trend + vitals
  - [ ] Tap any widget → app opens to Stress tab (warm launch)
  - [ ] Force-quit app → tap widget → app cold-launches to Stress tab
  - [ ] Verify dark mode appearance (colors visible on dark background)
  - [ ] Verify empty state when no stress data exists
  - [ ] Verify ProfileView stress widget preview renders correctly

---

## Risks & Mitigations

- **Risk**: `StressLevel` widget colors look different from main app colors
  - Mitigation: Widget colors are intentionally explicit hex values (not `.primary.opacity()`) — this is by design for visibility. Document the difference

- **Risk**: `weekReadings` empty for new users → large widget trend section looks broken
  - Mitigation: Show "Not enough data yet" text when `weeklyScores` has < 2 entries with non-nil scores

- **Risk**: Vitals (Resting HR, HRV, RR) all nil → medium/large widget has empty space
  - Mitigation: Only render vitals row when at least one value is non-nil; let other sections expand

- **Risk**: Existing food widget on user's Home Screen will disappear after update
  - Mitigation: Unavoidable — the food widget kind is being removed. Users will need to add the new stress widget manually. This is acceptable per the user's intent to fully replace it

- **Risk**: No `.onOpenURL` existed before — adding it might conflict with other URL handling
  - Mitigation: Checked — no `.onOpenURL` exists anywhere in the codebase. The handler is additive with no conflicts

<!-- RESOLVED: #12 — documented as known limitation -->
- **Risk**: Widget not updated when food is logged or screen time changes (only updates on full `loadData()`)
  - Mitigation: Known limitation. `refreshDietFactorAndLogIfNeeded()` and `refreshScreenTimeOnly()` do not trigger widget refresh. The 30-minute WidgetKit pull cycle and the next `loadData()` call (when user opens Stress tab) will catch up. A future pass can add `WidgetRefreshHelper.refreshStress(viewModel: self)` to those methods

---

## Success Criteria

- [ ] Food widget code fully removed (no `FoodWidget`, `WidgetFoodData`, `WidgetFoodItem`, or food view files remain)
- [ ] `ProfileView.swift` compiles with stress widget preview (no `FoodWidgetSize` references)
- [ ] `GoalsViewModel` and `HomeViewModel` compile without food refresh calls
- [ ] Stress widget appears in widget gallery with correct name, description, and preview
- [ ] Small widget shows stress ring with score, level label, and level icon
- [ ] Medium widget shows ring + top contributing factor + available vitals + yesterday comparison
- [ ] Large widget shows ring + 4-factor breakdown + 7-day trend (dynamic day labels) + vitals
- [ ] Tapping any widget deep-links to Stress tab in app (cold and warm launches)
- [ ] Widget updates when stress data refreshes in app
- [ ] Both main app and widget extension targets build successfully
- [ ] Empty/partial data states render gracefully (not blank or crashed)
