# Implementation Checklist: Stress Level Widget

**Source Plan**: `Docs/02_Planning/Specs/260405-stress-widget-plan-RESOLVED.md`
**Date**: 2026-04-06

---

## Pre-Implementation

- [ ] Read the RESOLVED plan fully
- [ ] Verify all affected files exist:
  - [ ] `WellPlate/Widgets/SharedFoodData.swift` (to delete)
  - [ ] `WellPlateWidget/FoodWidget.swift` (to delete)
  - [ ] `WellPlateWidget/Views/FoodSmallView.swift` (to delete)
  - [ ] `WellPlateWidget/Views/FoodMediumView.swift` (to delete)
  - [ ] `WellPlateWidget/Views/FoodLargeView.swift` (to delete)
  - [ ] `WellPlateWidget/Views/SharedWidgetViews.swift` (to rewrite)
  - [ ] `WellPlateWidget/WellPlateWidgetBundle.swift` (to modify)
  - [ ] `WellPlate/Core/Services/WidgetRefreshHelper.swift` (to rewrite)
  - [ ] `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` (to modify)
  - [ ] `WellPlate/App/RootView.swift` (to modify)
  - [ ] `WellPlate/Features + UI/Tab/MainTabView.swift` (to modify)
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift` (to modify)
  - [ ] `WellPlate/Features + UI/Goals/ViewModels/GoalsViewModel.swift` (to modify)
  - [ ] `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` (to modify)
- [ ] Check `git diff "WellPlate/Features + UI/Tab/ProfileView.swift"` — file is already modified in working tree; understand current state before editing

---

## Phase 1: Shared Data Model

### 1.1 — Create SharedStressData

- [ ] Create `WellPlate/Widgets/SharedStressData.swift` with:
  - [ ] `WidgetStressData` struct (Codable): `totalScore`, `levelRaw`, `encouragement`, `factors`, `restingHR?`, `hrv?`, `respiratoryRate?`, `weeklyScores`, `yesterdayScore?`, `lastUpdated`
    - Verify: struct has `var hasAnyValidData: Bool { factors.contains { $0.hasValidData } }` computed property
  - [ ] `WidgetStressFactor` struct (Codable): `title`, `icon`, `score` (0–25), `maxScore` (25), `contribution` (stress contribution 0–25), `hasValidData`
  - [ ] `WidgetDayScore` struct (Codable): `date`, `score: Double?` (nil = no data)
    - Verify: `score` is `Double?` (optional), NOT `Double` with `-1` sentinel
  - [ ] `static let appGroupID = "group.com.hariom.wellplate"`
  - [ ] `static let defaultsKey = "widgetStressData"`
  - [ ] `static func load() -> WidgetStressData` with `isDateInToday` guard returning `.empty` for stale data
  - [ ] `func save()` writing to AppGroup UserDefaults
  - [ ] `static var empty` preset (score 0, empty factors array, no vitals)
  - [ ] `static var placeholder` preset (score 32, "Good", 4 sample factors, sample vitals, 7-day sample scores)
  - Verify: File has only `import Foundation` — no SwiftData, HealthKit, or SwiftUI imports

### 1.2 — Delete SharedFoodData

- [ ] Delete `WellPlate/Widgets/SharedFoodData.swift`
  - Verify: File no longer exists — `ls WellPlate/Widgets/SharedFoodData.swift` returns "No such file"

---

## Phase 2: Widget Extension — Core Infrastructure

### 2.1 — Rewrite SharedWidgetViews

- [ ] Open `WellPlateWidget/Views/SharedWidgetViews.swift`
- [ ] Keep `wellPlateWidgetBackground` view modifier unchanged
- [ ] Remove `CalorieRingView` struct entirely
- [ ] Remove `MacroBarRow` struct entirely
- [ ] Add `static func widgetColor(for levelRaw: String) -> Color` helper with color mapping:
  - "Excellent" → `Color(hue: 0.33, saturation: 0.60, brightness: 0.72)`
  - "Good" → `Color(hue: 0.27, saturation: 0.55, brightness: 0.70)`
  - "Moderate" → `Color(hue: 0.12, saturation: 0.55, brightness: 0.72)`
  - "High" → `Color(hue: 0.06, saturation: 0.60, brightness: 0.70)`
  - "Very High" → `Color(hue: 0.01, saturation: 0.65, brightness: 0.65)`
  - default → `Color.gray`
  - Verify: Helper returns explicit HSB colors, NOT `.primary.opacity()`
- [ ] Add `StressRingView` struct:
  - Takes `data: WidgetStressData` and `ringWidth: CGFloat = 10`
  - ZStack: track Circle (level color at 0.18 opacity) + trimmed fill Circle + center labels
  - Fill uses `AngularGradient` with `widgetColor(for: data.levelRaw)`
  - Center: score number (18pt bold rounded) + "/100" (10pt secondary)
  - Fraction = `min(data.totalScore / 100.0, 1.0)`
  - `.accessibilityLabel("Stress score: \(Int(data.totalScore)) out of 100, \(data.levelRaw)")`
  - Verify: Ring renders with explicit colors in both light and dark mode
- [ ] Add `StressFactorBar` struct:
  - Takes `factor: WidgetStressFactor`
  - Label row: Image(systemName: factor.icon) + Text(factor.title) + Text("\(Int(factor.contribution))/25")
  - Progress bar: width = `factor.contribution / 25.0`, color = `Color(hue: 0.33 * (1.0 - factor.contribution/25.0), saturation: 0.65, brightness: 0.75)`
  - If `!factor.hasValidData` → gray out entire row
  - Verify: Bar shows green for low contribution, red for high contribution

### 2.2 — Create StressWidget

- [ ] Create `WellPlateWidget/StressWidget.swift` with:
  - [ ] `StressEntry: TimelineEntry` — `let date: Date`, `let data: WidgetStressData`
  - [ ] `StressWidgetProvider: TimelineProvider`:
    - `placeholder(in:)` → `StressEntry(date: .now, data: .placeholder)`
    - `getSnapshot(in:completion:)` → `.placeholder` if `isPreview`, else `WidgetStressData.load()`
    - `getTimeline(in:completion:)` → load data, next refresh at now + 30 minutes
  - [ ] `StressWidgetEntryView: View`:
    - Switch on `@Environment(\.widgetFamily)`:
      - `.systemSmall` → `StressSmallView(data: entry.data)`
      - `.systemMedium` → `StressMediumView(data: entry.data)`
      - `.systemLarge` → `StressLargeView(data: entry.data)`
      - `default` → `StressSmallView(data: entry.data)`
    - Verify: `default` case is present (not just the 3 explicit cases)
  - [ ] `StressWidget: Widget`:
    - `let kind = "com.hariom.wellplate.stressWidget"`
    - `.configurationDisplayName("Stress Level")`
    - `.description("Monitor your stress score and top factors.")`
    - `.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])`
  - [ ] `#if DEBUG` preview provider with all 3 families using `.placeholder`

### 2.3 — Delete FoodWidget

- [ ] Delete `WellPlateWidget/FoodWidget.swift`
  - Verify: File no longer exists

### 2.4 — Update WidgetBundle

- [ ] In `WellPlateWidget/WellPlateWidgetBundle.swift`: replace `FoodWidget()` with `StressWidget()`
  - Verify: File contains `StressWidget()` and no reference to `FoodWidget`

---

## Phase 3: Widget Views

### 3.1 — Create StressSmallView

- [ ] Create `WellPlateWidget/Views/StressSmallView.swift`
- [ ] Wrap body in `Link(destination: URL(string: "wellplate://stress")!)`
- [ ] Header: "Stress" label + SF Symbol for level (use `systemImage` mapping based on `data.levelRaw`)
- [ ] Center: `StressRingView(data: data, ringWidth: 9)` at 82×82pt
- [ ] Footer: level label text
- [ ] Bottom: if top factor has high contribution, show factor icon + name; else show encouragement text
- [ ] Empty state: when `data.factors.isEmpty` → show "Open WellPlate to get started" with app icon
- [ ] Apply `wellPlateWidgetBackground` with gradient tint using `widgetColor(for: data.levelRaw).opacity(0.06)`
  - Verify: Widget renders correctly with placeholder data in Xcode preview

### 3.2 — Create StressMediumView

- [ ] Create `WellPlateWidget/Views/StressMediumView.swift`
- [ ] Wrap body in `Link(destination: URL(string: "wellplate://stress")!)`
- [ ] Left column (114pt width):
  - [ ] "Stress" label
  - [ ] `StressRingView(data: data, ringWidth: 10)` at 94×94pt
  - [ ] Level label below ring
- [ ] Vertical divider (0.5pt separator with 12pt vertical padding, 14pt horizontal padding)
- [ ] Right column:
  - [ ] Top factor: find factor with highest `contribution` where `hasValidData == true`, show icon + name + `StressFactorBar`
  - [ ] Vitals row (only if at least one non-nil): "❤️ Xbpm | 💚 Xms" using `data.restingHR` and `data.hrv`
  - [ ] Change indicator (only if `data.yesterdayScore != nil`): compute diff, show "↓ X from yesterday" (green if score decreased = less stress) or "↑ X from yesterday" (terracotta if score increased)
- [ ] Empty state: same as small
- [ ] Apply `wellPlateWidgetBackground`
  - Verify: Widget renders correctly; right column does not overflow

### 3.3 — Create StressLargeView

- [ ] Create `WellPlateWidget/Views/StressLargeView.swift`
- [ ] Wrap body in `Link(destination: URL(string: "wellplate://stress")!)`
- [ ] Header: `brain.head.profile.fill` icon + "Stress Level" title + `Date()` style date
- [ ] Score section: HStack — `StressRingView` (80×80) + VStack(level label + encouragement)
- [ ] Divider
- [ ] 4 factor rows: `ForEach` over `data.factors` using `StressFactorBar`
  - [ ] Highlight factor with highest `contribution` using subtle background tint
  - Verify: factor with highest contribution is visually distinct
- [ ] Divider
- [ ] 7-day trend section:
  - [ ] Check `data.weeklyScores.compactMap(\.score).count >= 2` — if not, show "Not enough data yet" text
  - [ ] If enough data: HStack of 7 mini bars (RoundedRectangle)
    - Bar height: proportional to `score` (0–100 → 0–40pt); nil score → 2pt gray bar
    - Bar color: `widgetColor(for: StressLevel(score: score).rawValue)` for non-nil; `Color.gray.opacity(0.3)` for nil
  - [ ] Day-of-week labels derived from `dayScore.date`: use `Calendar.current.component(.weekday, from: date)` to index `Calendar.current.shortWeekdaySymbols` — NOT hardcoded strings
    - Verify: Labels match actual day of week (e.g., if today is Sunday, rightmost label is "Sun")
- [ ] Vitals row (only if at least one non-nil): Resting HR, HRV, Respiratory Rate as caption2 monospaced text
  - If all nil → hide row entirely
- [ ] Empty state: same as small
- [ ] Apply `wellPlateWidgetBackground`
  - Verify: All sections fit within ~345pt height without clipping

### 3.4 — Delete Food Widget Views

- [ ] Delete `WellPlateWidget/Views/FoodSmallView.swift`
- [ ] Delete `WellPlateWidget/Views/FoodMediumView.swift`
- [ ] Delete `WellPlateWidget/Views/FoodLargeView.swift`
  - Verify: `ls WellPlateWidget/Views/Food*` returns no matches

---

## Phase 4: App-Side Integration

### 4.1 — Replace WidgetRefreshHelper

- [ ] Open `WellPlate/Core/Services/WidgetRefreshHelper.swift`
- [ ] Remove the entire `refresh(goals:context:)` method
- [ ] Remove `import SwiftData` (no longer needed)
- [ ] Add `import WidgetKit` (keep existing)
- [ ] Add `@MainActor static func refreshStress(viewModel: StressViewModel)`:
  - [ ] Map `viewModel.allFactors` to `[WidgetStressFactor]` using explicit mapping:
    - `.title` ← `.title`
    - `.icon` ← `.icon`
    - `.score` ← `.score`
    - `.maxScore` ← `.maxScore`
    - `.contribution` ← **`.stressContribution`** (NOT `.score`)
    - `.hasValidData` ← `.hasValidData`
    - Verify: `contribution` field uses `stressContribution` property, NOT `score`
  - [ ] Build `weeklyScores` by grouping `viewModel.weekReadings` by calendar day, averaging `.score` per day. Fill all 7 days in the window; days with no readings → `WidgetDayScore(date:, score: nil)`
  - [ ] Compute `yesterdayScore` from grouped readings (nil if no readings yesterday)
  - [ ] Populate `WidgetStressData` with all fields from viewModel
  - [ ] Call `.save()` then `WidgetCenter.shared.reloadTimelines(ofKind: "com.hariom.wellplate.stressWidget")`
  - Verify: File compiles with no `WidgetFoodData` references

### 4.2 — Add Widget Refresh to StressViewModel

- [ ] Open `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
- [ ] Add `import WidgetKit` at the top (if not already present)
- [ ] At the very end of `loadData()` (after the vitals extraction block ending at ~line 294), add:
  ```swift
  // Ensure weekReadings is populated (SwiftData doesn't need HK auth)
  loadReadings()
  // Push latest data to widget
  WidgetRefreshHelper.refreshStress(viewModel: self)
  ```
  - Verify: The two new lines are the LAST lines in `loadData()`, after all vitals are assigned
  - Verify: `loadReadings()` is called unconditionally (not inside any guard)

### 4.3 — Add Deep-Link Handler

- [ ] Open `WellPlate/App/RootView.swift`
- [ ] Add `@State private var pendingDeepLink: URL? = nil` property
- [ ] Add `.onOpenURL { url in pendingDeepLink = url }` modifier on the outer ZStack
- [ ] Update `MainTabView()` call to `MainTabView(pendingDeepLink: $pendingDeepLink)`
  - Verify: `RootView` compiles with the new state and binding
- [ ] Open `WellPlate/Features + UI/Tab/MainTabView.swift`
- [ ] Add `@Binding var pendingDeepLink: URL?` property
- [ ] Add `.onChange(of: pendingDeepLink)` modifier on the TabView:
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
- [ ] Update `#Preview` at bottom of file to pass `.constant(nil)`:
  ```swift
  MainTabView(pendingDeepLink: .constant(nil))
  ```
  - Verify: Both `RootView` and `MainTabView` compile; no other callers of `MainTabView()` exist that need updating (check with grep)

### 4.4 — Replace Food Widget Preview in ProfileView

- [ ] Open `WellPlate/Features + UI/Tab/ProfileView.swift`
- [ ] Rename `FoodWidgetSize` enum to `StressWidgetSize` (all occurrences in file)
- [ ] Update `previewDescription` property values:
  - `.small` → "Score ring + level"
  - `.medium` → "Ring + top factor + vitals"
  - `.large` → "Full breakdown + 7-day trend"
- [ ] Update `@State private var selectedSize: FoodWidgetSize` → `StressWidgetSize` in `ProfilePlaceholderView`
- [ ] Update `WidgetSetupCard`: `@Binding var selectedSize: FoodWidgetSize` → `StressWidgetSize`; update any food-specific copy/icons to stress equivalents
- [ ] Update `SizePill`: `let size: FoodWidgetSize` → `StressWidgetSize`
- [ ] Update `WidgetInstructionsSheet`: `let size: FoodWidgetSize` → `StressWidgetSize`
- [ ] Rewrite `WidgetPreview`:
  - Replace `WidgetFoodData(...)` mock with `WidgetStressData.placeholder`
  - Update size parameter type to `StressWidgetSize`
- [ ] Rewrite `SmallPreview`, `MediumPreview`, `LargePreview` structs:
  - Change parameter from `WidgetFoodData` to `WidgetStressData`
  - Replace food UI (calorie rings, macro bars, food lists) with stress UI (stress ring approximation, level label, factor bars)
  - These are in-app previews — they don't need to exactly match the widget views, just approximate the layout
  - Verify: No references to `WidgetFoodData`, `WidgetFoodItem`, or `FoodWidgetSize` remain in the file
- [ ] Grep the file for any remaining food-widget references:
  ```
  grep -n "FoodWidget\|WidgetFoodData\|WidgetFoodItem\|CalorieRing\|MacroBar\|logFood" "WellPlate/Features + UI/Tab/ProfileView.swift"
  ```
  - Verify: Grep returns no matches

### 4.5 — Remove Food Widget Refresh Callers

- [ ] Open `WellPlate/Features + UI/Goals/ViewModels/GoalsViewModel.swift`
- [ ] Delete line 19: `WidgetRefreshHelper.refresh(goals: goals, context: modelContext)`
  - Verify: `save()` method still contains `try? modelContext.save()` but no widget refresh call
- [ ] Open `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`
- [ ] Delete the `refreshWidget(for:)` method (lines ~291–295)
- [ ] Delete the 3 call sites of `refreshWidget(for: day)` at lines ~97, ~122, ~243
  - Verify: `grep -n "refreshWidget" "WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift"` returns no matches
- [ ] Verify no other files reference the deleted method:
  ```
  grep -rn "refreshWidget" WellPlate/ --include="*.swift"
  ```
  - Verify: No matches (or only matches in docs/comments)

---

## Phase 5: Build Verification

### 5.1 — Build All Targets

- [ ] Build main app:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED with no errors
- [ ] Build widget extension:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED with no errors
- [ ] Build ScreenTimeMonitor:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED (this target should be unaffected)
- [ ] Build ScreenTimeReport:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED (this target should be unaffected)

### 5.2 — Final Verification

- [ ] Grep entire project for orphaned food widget references:
  ```bash
  grep -rn "FoodWidget\|WidgetFoodData\|WidgetFoodItem\|foodWidget" WellPlate/ WellPlateWidget/ --include="*.swift"
  ```
  - Verify: No matches in `.swift` files (docs/markdown are okay)
- [ ] Verify widget bundle only contains stress widget:
  ```bash
  grep -n "Widget()" WellPlateWidget/WellPlateWidgetBundle.swift
  ```
  - Verify: Only `StressWidget()` appears

---

## Post-Implementation

- [ ] All 4 build targets pass (Phase 5.1)
- [ ] No orphaned food widget references (Phase 5.2)
- [ ] Git commit with descriptive message
