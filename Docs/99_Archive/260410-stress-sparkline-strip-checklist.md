# Implementation Checklist: Stress Sparkline Strip (Home Screen)

**Source Plan**: `Docs/02_Planning/Specs/260410-stress-sparkline-strip-plan-RESOLVED.md`
**Date**: 2026-04-10

---

## Pre-Implementation

- [ ] Verify `WellPlate/Features + UI/Home/Views/HomeView.swift` exists
  - Verify: file opens and contains `struct HomeView: View`
- [ ] Verify `WellPlate/Models/StressReading.swift` exists with `timestamp` and `score` properties
  - Verify: grep for `var timestamp: Date` and `var score: Double`
- [ ] Verify `WellPlate/Models/StressModels.swift` has `StressLevel(score:)` init and `.color` property
  - Verify: grep for `init(score: Double)` and `var color: Color`
- [ ] Verify target directory exists: `WellPlate/Features + UI/Home/Components/`
  - Verify: directory listing shows existing component files (DailyInsightCard.swift, WellnessRingsCard.swift, etc.)

---

## Phase 1: Data Plumbing in HomeView

### 1.1 — Add @Query for StressReadings

- [ ] In `WellPlate/Features + UI/Home/Views/HomeView.swift`, add after the existing `@Query private var allJournalEntries` line (~line 30):
  ```swift
  @Query(sort: \StressReading.timestamp) private var allStressReadings: [StressReading]
  ```
  - Verify: build succeeds — `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

### 1.2 — Add computed helpers for today/yesterday readings

- [ ] In `WellPlate/Features + UI/Home/Views/HomeView.swift`, add after the `todayWellnessLog` computed property (~line 424), before `todayCalories`:
  ```swift
  private var todayStressReadings: [StressReading] {
      allStressReadings.filter { Calendar.current.isDateInToday($0.timestamp) }
  }

  private var yesterdayLastStressReading: StressReading? {
      allStressReadings.last { Calendar.current.isDateInYesterday($0.timestamp) }
  }

  private var stressScoreDelta: Int? {
      guard let today = todayStressReadings.last,
            let yesterday = yesterdayLastStressReading else { return nil }
      let delta = Int(today.score.rounded()) - Int(yesterday.score.rounded())
      return delta == 0 ? nil : delta
  }
  ```
  - Verify: build succeeds — no compile errors referencing the new properties

---

## Phase 2: StressSparklineStrip Component

### 2.1 — Create the component file

- [ ] Create new file: `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift`
- [ ] Add imports at the top:
  ```swift
  import SwiftUI
  import SwiftData
  import Charts
  ```
  - Verify: file exists at the correct path

### 2.2 — Define struct, chart data model, and private helpers

- [ ] Add `struct StressSparklineStrip: View` with parameters:
  - `let readings: [StressReading]`
  - `let stressLevel: String?`
  - `let scoreDelta: Int?`
  - `var onTap: () -> Void`
  - Verify: struct compiles with empty body `var body: some View { EmptyView() }`

- [ ] Add private `IntradayPoint: Identifiable` struct inside the view:
  ```swift
  private struct IntradayPoint: Identifiable {
      let id: Int
      let timestamp: Date
      let score: Double
  }
  ```
  - Verify: struct is defined and used by `chartPoints` computed property

- [ ] Add `chartPoints` computed property mapping `readings` to `[IntradayPoint]`
  - Verify: property compiles

- [ ] Add private computed properties:
  - `latestScore: Double?` — `readings.last?.score`
  - `latestLevel: StressLevel?` — maps latestScore via `StressLevel(score:)`
  - `emoji: String` — switch on `stressLevel?.lowercased()` returning emoji per level, default `"—"`
  - `accentColor: Color` — `latestLevel?.color ?? Color(.systemGray3)`
  - `inflectionAnnotation: String?` — finds max |delta| between consecutive readings, returns caption if >= 8
  - Verify: all properties compile with no undefined references

- [ ] Add animation state:
  ```swift
  @State private var lineDrawn = false
  ```
  - Verify: state property compiles

### 2.3 — Implement body and subviews

- [ ] Implement `body` as a `Button` wrapping a `VStack` with:
  - `headerRow`
  - `chartArea`
  - Optional `inflectionAnnotation` text
  - Standard card background: `RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)`
  - `.buttonStyle(.plain)`
  - `.onAppear` triggering `lineDrawn = true` with spring animation (response: 1.0, dampingFraction: 0.75)
  - Button action: `HapticService.impact(.medium); onTap()`
  - Verify: body compiles

- [ ] Implement `headerRow` as a private computed property (`HStack`):
  - Left: `Text("Stress today")` with `.font(.r(.subheadline, .semibold))`
  - Center: `Spacer()`
  - Delta badge (conditional): capsule pill with arrow + value, colored `AppColors.error` (worse) or `AppColors.success` (better), background at 0.12 opacity
  - Right: emoji text + score number + optional level label (conditional on `latestScore`)
  - Fallback: `Text("—")` when no score
  - Verify: header renders in preview

- [ ] Implement `chartArea` as a private computed property:
  - `Group` switching on `readings.count < 2`:
    - `< 2`: `emptyChartPlaceholder`
    - `>= 2`: `realChart`
  - `.frame(height: 52)`
  - Verify: both branches compile

- [ ] Implement `emptyChartPlaceholder`:
  - `VStack(spacing: 6)` with dashed `RoundedRectangle` stroke (1pt height) + "No stress data yet" caption
  - `.frame(maxWidth: .infinity)`
  - Verify: placeholder renders in empty preview

- [ ] Implement `realChart`:
  - `Chart(chartPoints)` with `AreaMark` (gradient fill 0.20 → 0.0 opacity) + `LineMark` (2pt stroke)
  - Both using `.interpolationMethod(.catmullRom)` and `accentColor`
  - `.chartXAxis(.hidden)`, `.chartYAxis(.hidden)`, `.chartYScale(domain: 0...100)`
  - `.mask { Rectangle().scaleEffect(x: lineDrawn ? 1 : 0, anchor: .leading) }` for trim animation
  - Verify: chart renders in filled preview

### 2.4 — Add previews

- [ ] Add `#Preview("StressSparklineStrip — Filled")` with:
  - In-memory `ModelContainer` for `StressReading`
  - 4 sample readings spanning -6h to now, scores: 58 → 72 → 48 → 34
  - `stressLevel: "Good"`, `scoreDelta: -18`
  - Verify: preview renders in Xcode Canvas showing chart line, header, delta badge, annotation

- [ ] Add `#Preview("StressSparklineStrip — Empty")` with:
  - In-memory `ModelContainer` for `StressReading`
  - Empty readings array, nil stressLevel, nil scoreDelta
  - Verify: preview renders showing dashed placeholder and "No stress data yet"

---

## Phase 3: Wire into HomeView

### 3.1 — Insert strip in the scroll view

- [ ] In `WellPlate/Features + UI/Home/Views/HomeView.swift`, insert after the `WellnessRingsCard(...)` block (after `.padding(.horizontal, 16)` ~line 102) and before `// 3. Mood Check-In / Journal Reflection`:
  ```swift
  // 2b. Stress Sparkline Strip
  StressSparklineStrip(
      readings: todayStressReadings,
      stressLevel: todayWellnessLog?.stressLevel,
      scoreDelta: stressScoreDelta,
      onTap: { selectedTab = 1 }
  )
  .padding(.horizontal, 16)
  ```
  - Verify: build succeeds, strip appears between wellness rings and mood check-in

---

## Post-Implementation

- [ ] Build all 4 targets:
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Verify no new warnings introduced in the main scheme build
- [ ] Git commit with descriptive message
