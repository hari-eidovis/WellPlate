# Implementation Checklist: Wellness Report Export

**Source Plan**: `Docs/02_Planning/Specs/260402-wellness-report-export-plan-RESOLVED.md`
**Date**: 2026-04-02

---

## Pre-Implementation

- [ ] Read the RESOLVED plan in full: `Docs/02_Planning/Specs/260402-wellness-report-export-plan-RESOLVED.md`
- [ ] Confirm `ProgressInsightsView.swift` exists at `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift`
  - Verify: File opens in editor; confirms `@State private var showShareSheet = false` at line 21 and share button at line 188
- [ ] Confirm `WellPlate/Features + UI/Progress/Services/` directory exists (new `WellnessReportGenerator.swift` will go here)
  - Verify: `ls "WellPlate/Features + UI/Progress/Services/"` lists at least one existing file
- [ ] Confirm no file named `WellnessReportView.swift`, `WellnessReportGenerator.swift`, or `WellnessReportShareSheet.swift` already exists under `WellPlate/`
  - Verify: `find WellPlate -name "WellnessReport*"` returns no results

---

## Phase 1: Data Model

### 1.1 — Create `WellnessReportData` struct

- [ ] Create new file `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`
- [ ] At the **top** of the file (before the generator struct), add the `WellnessReportData` plain struct exactly as specified in Step 1 of the RESOLVED plan:
  ```swift
  struct WellnessReportData {
      let dateRange: String
      let avgStressScore: Double?
      let avgCalories: Double
      let calorieGoal: Int
      let avgProtein: Double
      let avgCarbs: Double
      let avgFat: Double
      let avgSteps: Double
      let avgWaterGlasses: Double
      let waterGoal: Int
      let dominantMoodEmoji: String
      let loggedDays: Int
  }
  ```
  - Verify: File compiles in isolation — no `import` needed for this struct (pure Swift value types only)

### 1.2 — Add `@Query` properties to `ProgressInsightsView`

- [ ] Open `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift`
- [ ] After the existing `@Query private var userGoalsList: [UserGoals]` declaration (line 13), add two new lines:
  ```swift
  @Query private var allStressReadings: [StressReading]
  @Query private var allWellnessLogs: [WellnessDayLog]
  ```
  - Verify: The custom `init()` (lines 29–35) does NOT need to change — it only initializes `_allFoodLogs`. The new queries use default `@Query` initialization (fetch all, no predicate).

### 1.3 — Add `weekReportData` computed property to `ProgressInsightsView`

- [ ] In `ProgressInsightsView`, add the `weekReportData: WellnessReportData` private computed property. Place it after the `previousPeriodStats` computed property (around line 72), before `// MARK: - Colors`.
- [ ] The property body must:
  - Filter the last 7 days using `Calendar.current.date(byAdding: .day, value: -7, to: Date())`
  - Compute `dailyCalories`, `dailyProtein`, `dailyCarbs`, `dailyFat` by grouping `foodLogs` by `$0.day`
  - Compute `avgStress` as `Double?` — `nil` when `stressLogs` is empty
  - Compute `avgSteps` and `avgWater` from `wellnessLogs`
  - Compute `dominantEmoji` via `Dictionary(grouping:)` on `compactMap(\.moodRaw)`, then `MoodOption(rawValue:)?.emoji ?? "—"`
  - Use **`goals.calorieGoal`** (not `dailyCalorieGoal`) and **`goals.waterDailyCups`** (not `dailyCups`)
  - Verify: Build succeeds — any misspelled field names will produce a compile error here

---

## Phase 2: Report Card View

### 2.1 — Create `WellnessReportView.swift`

- [ ] Create new file `WellPlate/Features + UI/Progress/Views/WellnessReportView.swift`
- [ ] Add `import SwiftUI` at the top
- [ ] Implement `struct WellnessReportView: View` with:
  - `let data: WellnessReportData` stored property
  - `body`: `VStack(alignment: .leading, spacing: 0)` containing `headerSection`, `Divider()`, `statsGrid`, `footerSection`
  - `.frame(width: 390)` on the VStack — this fixed width is required for consistent `ImageRenderer` output
  - `.background(Color(.systemBackground))`
- [ ] Implement `headerSection` (brand name + "Weekly Wellness Report" + date range)
- [ ] Implement `statsGrid` as a `LazyVGrid` with `[GridItem(.flexible()), GridItem(.flexible())]` — 6 tiles:
  1. Stress: `brain.head.profile`, `"Avg Stress"`, `avgStressScore.map { "\(Int($0))/100" } ?? "—"`
  2. Calories: `flame.fill`, `"Avg Calories"`, `"\(Int(data.avgCalories)) / \(data.calorieGoal)"`
  3. Steps: `figure.walk`, `"Avg Steps"`, `Int(data.avgSteps).formatted()` or `"—"`
  4. Water: `drop.fill`, `"Avg Water"`, `"\(Int(data.avgWaterGlasses.rounded())) / \(data.waterGoal) cups"`
  5. Mood: `face.smiling`, `"Top Mood"`, `data.dominantMoodEmoji`
  6. Days Logged: `checkmark.circle.fill`, `"Days Logged"`, `"\(data.loggedDays) / 7"`
- [ ] Implement `statTile(icon:label:value:color:)` helper returning a `VStack` with the icon+label row and value text
- [ ] Implement `stressColor: Color` — green `< 40`, yellow `< 60`, orange `< 80`, red `≥ 80`; `AppColors.textSecondary` when nil
- [ ] Implement `footerSection` — `"Generated by WellPlate · Data stays on your iPhone"`, `.caption2`, centered, `Color(.secondarySystemBackground)` background
  - Verify: `WellnessReportView` is a pure layout view — no async work, no `@State`, no environment dependencies. Confirm `AppColors.textPrimary`, `AppColors.textSecondary`, `AppColors.brand` are used (not hardcoded colors) — except the two hex tile accent colors `Color(hex: "FF6B35")` and `Color(hex: "5E9FFF")` which are intentional

---

## Phase 3: Generator

### 3.1 — Add `WellnessReportGenerator` struct to `WellnessReportGenerator.swift`

- [ ] In `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` (the file created in 1.1), below the `WellnessReportData` struct, add:
  ```swift
  @MainActor
  struct WellnessReportGenerator { ... }
  ```
- [ ] Implement `static func renderImage(data: WellnessReportData) async -> UIImage?`:
  - Instantiate `WellnessReportView(data: data)`
  - Create `ImageRenderer(content: view)`
  - Set `renderer.scale = 2.0`
  - Guard on `renderer.uiImage`
  - Compress: `uiImage.jpegData(compressionQuality: 0.88)` → `UIImage(data: jpegData) ?? uiImage`
  - Return `UIImage?`
  - Verify: Function is `async` and in a `@MainActor` struct — `ImageRenderer` requires main actor
- [ ] Implement `static func generateCSV(foodLogs:stressReadings:wellnessLogs:) -> Data`:
  - Header row: `"date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood"`
  - Build `daySeq: [Date]` — last 7 days (oldest first) using `(0..<7).compactMap { ... }.reversed()`
  - Build `foodByDay`, `stressByDay`, `wellnessByDay` dictionaries keyed by `Date` (start-of-day)
  - For each day: aggregate calories/macros from food, average stress from stress readings, steps/water/mood from wellness
  - Format stress as `String(format: "%.1f", ...)` or `""` when absent
  - Join rows with `"\n"`, encode to `.utf8`
  - Verify: Output for a day with no logs produces a row like `"2026-03-26,,,0,0.0,0.0,0.0,0,0,"` — no crashes on empty arrays

---

## Phase 4: Share Sheet

### 4.1 — Create `WellnessReportShareSheet.swift`

- [ ] Create new file `WellPlate/Features + UI/Progress/Views/WellnessReportShareSheet.swift`
- [ ] Add `import SwiftUI` at the top
- [ ] Declare `struct WellnessReportShareSheet: View` with four let properties:
  ```swift
  let reportData: WellnessReportData
  let foodLogs: [FoodLogEntry]
  let stressReadings: [StressReading]
  let wellnessLogs: [WellnessDayLog]
  ```
- [ ] Add three `@State` properties:
  ```swift
  @State private var imageURL: URL? = nil
  @State private var csvURL: URL? = nil
  @State private var isRendering = true
  ```
  - Note: `URL?` not `UIImage?` or `Data` — this is the H1/H2 fix
- [ ] Add `@Environment(\.dismiss) private var dismiss`
- [ ] Implement `body`: `NavigationStack` containing a `VStack` with:
  - **Loading branch** (`isRendering == true`): `ProgressView("Generating report…")` with `.frame(maxWidth: .infinity, maxHeight: .infinity)`
  - **Content branch** (`isRendering == false`): `ScrollView` containing a `VStack(spacing: 20)` with:
    - Preview block (see 4.2 below)
    - Share buttons block (see 4.3 below)
- [ ] Add `.navigationTitle("Weekly Report")` and `.navigationBarTitleDisplayMode(.inline)`
- [ ] Add toolbar with `Button("Done") { dismiss() }` using `.topBarTrailing` placement, colored `AppColors.brand`
- [ ] Apply `.presentationDetents([.large])` on the `NavigationStack`

### 4.2 — Preview block inside `WellnessReportShareSheet`

- [ ] Inside the ScrollView's content VStack, add the preview using the scale-to-fit approach:
  ```swift
  let screenW = UIScreen.main.bounds.width - 40
  let scale = screenW / 390
  WellnessReportView(data: reportData)
      .scaleEffect(scale, anchor: .top)
      .frame(width: 390 * scale, height: 340 * scale)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .appShadow(radius: 16, y: 6)
      .padding(.horizontal, 20)
  ```
  - Verify: `.frame(width: 390 * scale, height: 340 * scale)` is present — this is the M1 fix that prevents layout overflow on iPhone SE (375pt screen). Without this, the layout system still sees a 390pt-wide view regardless of the scale transform.

### 4.3 — Share buttons inside `WellnessReportShareSheet`

- [ ] Add the "Share as Image" button — **guard on `imageURL`** (not `renderedImage: UIImage?`):
  ```swift
  if let url = imageURL {
      ShareLink(item: url, preview: SharePreview("WellPlate Weekly Report")) {
          Label("Share as Image", systemImage: "photo")
              .font(.r(.body, .semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(AppColors.brand)
              .foregroundColor(.white)
              .clipShape(RoundedRectangle(cornerRadius: 14))
      }
  }
  ```
  - Verify: `ShareLink(item: url)` where `url: URL` — `URL` conforms to `Transferable`. Do NOT use `ShareLink(item: Image(uiImage:))` — `SwiftUI.Image` does not conform to `Transferable`.
- [ ] Add the "Export as CSV" button — **guard on `csvURL`**:
  ```swift
  if let url = csvURL {
      ShareLink(item: url, preview: SharePreview("WellPlate Weekly Data.csv")) {
          Label("Export as CSV", systemImage: "tablecells")
              .font(.r(.body, .medium))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(Color(.secondarySystemBackground))
              .foregroundColor(AppColors.textPrimary)
              .clipShape(RoundedRectangle(cornerRadius: 14))
      }
  }
  ```
  - Verify: `ShareLink(item: csvURL)` where `csvURL: URL` pointing to a `.csv` file — the share target receives a file with correct MIME type. Do NOT use `ShareLink(item: csvData: Data)` — raw `Data` loses the filename.
- [ ] Wrap both share buttons in `VStack(spacing: 12).padding(.horizontal, 20)`

### 4.4 — `.task` block and temp file writing

- [ ] Add `.task { }` modifier on the `NavigationStack` body:
  - Render image: call `await WellnessReportGenerator.renderImage(data: reportData)` → get `UIImage?`
  - If image non-nil: call `.jpegData(compressionQuality: 0.88)` → `try? data.write(to: url)` where `url = FileManager.default.temporaryDirectory.appendingPathComponent("WellPlate_Weekly_Report.jpg")`
  - Set `imageURL = url`
  - Generate CSV: call `WellnessReportGenerator.generateCSV(foodLogs:stressReadings:wellnessLogs:)` → `Data`
  - Write CSV: `try? csvData.write(to: csvFileURL)` where `csvFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("WellPlate_Weekly_Data.csv")`
  - Set `csvURL = csvFileURL`
  - Set `isRendering = false`
  - Verify: Both assignments to `imageURL` and `csvURL` happen before `isRendering = false` — this prevents the share buttons appearing before their URLs are ready

### 4.5 — Temp file cleanup

- [ ] Add `.onDisappear { }` modifier on the `NavigationStack`:
  ```swift
  .onDisappear {
      if let url = imageURL { try? FileManager.default.removeItem(at: url) }
      if let url = csvURL   { try? FileManager.default.removeItem(at: url) }
  }
  ```
  - Verify: Block uses `try?` — failure to delete (e.g., file already gone) is silently ignored

---

## Phase 5: Wire Into ProgressInsightsView

### 5.1 — Attach `.sheet` to `showShareSheet`

- [ ] Open `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift`
- [ ] Locate `.background(StatusBarStyleModifier())` — this is the **last modifier** on the view body (around line 237)
- [ ] Add the `.sheet` modifier **after** `.background(StatusBarStyleModifier())`, making it the outermost modifier:
  ```swift
  .sheet(isPresented: $showShareSheet) {
      WellnessReportShareSheet(
          reportData: weekReportData,
          foodLogs: Array(allFoodLogs.filter {
              $0.day >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
          }),
          stressReadings: Array(allStressReadings.filter {
              $0.timestamp >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
          }),
          wellnessLogs: Array(allWellnessLogs.filter {
              $0.day >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
          })
      )
  }
  ```
  - Verify: The `showShareSheet` state variable is already declared at line 21 and the share button at line 188 already sets it to `true` — no changes needed to either of those lines

---

## Post-Implementation

### Build Verification

- [ ] Build main app target:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: `** BUILD SUCCEEDED **` — zero errors, zero new warnings
- [ ] Build ScreenTimeMonitor extension:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: `** BUILD SUCCEEDED **`
- [ ] Build ScreenTimeReport extension:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: `** BUILD SUCCEEDED **`
- [ ] Build Widget extension:
  ```
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: `** BUILD SUCCEEDED **`

### Manual Verification

- [ ] Navigate: App → Home tab → tap chart icon → `ProgressInsightsView` opens → tap share button (↑ circle, top-right)
  - Verify: `WellnessReportShareSheet` opens as a full-screen sheet with a spinner labeled "Generating report…"
- [ ] Wait for render to complete
  - Verify: Spinner disappears and is replaced by the report card preview + two buttons
- [ ] Inspect the preview card
  - Verify: Shows 6 tiles (Avg Stress, Avg Calories, Avg Steps, Avg Water, Top Mood, Days Logged) with non-placeholder values where data exists
- [ ] Tap "Share as Image"
  - Verify: iOS share sheet opens; the item is named `WellPlate_Weekly_Report.jpg`; saving to Photos produces a visible image
- [ ] Tap "Export as CSV"
  - Verify: iOS share sheet opens; the item is named `WellPlate_Weekly_Data.csv`; saving to Files app produces an openable CSV with a header row + 7 data rows
- [ ] Test empty-data edge case: tap share button when there are no `StressReading` records in the last 7 days
  - Verify: Sheet opens without crash; "Avg Stress" tile shows `"—"` (not `"0/100"`)
- [ ] Test on narrowest available simulator (iPhone SE, 375pt width)
  - Verify: Report preview card fits within the screen without horizontal clipping or overflow
- [ ] Tap "Done" button
  - Verify: Sheet dismisses cleanly

### Git

- [ ] Stage and commit:
  ```
  git add "WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift"
  git add "WellPlate/Features + UI/Progress/Views/WellnessReportView.swift"
  git add "WellPlate/Features + UI/Progress/Views/WellnessReportShareSheet.swift"
  git add "WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift"
  ```
  - Verify: `git status` shows exactly these 4 files staged (1 modified, 3 new)
