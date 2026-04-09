# Implementation Checklist: Wellness Report Export — RESOLVED

**Source Plan**: `Docs/02_Planning/Specs/260402-wellness-report-export-plan-RESOLVED.md`
**Audit**: `Docs/03_Audits/260402-wellness-report-export-checklist-audit.md`
**Date**: 2026-04-02

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| H1 — `Services/` directory does not exist; no create instruction | HIGH | Fixed: Pre-Implementation item 3 replaced with `mkdir` action step |
| H2 — `imageURL`/`csvURL` set unconditionally after `try?` write | HIGH | Fixed: URL assignment conditioned on `(try? data.write(to:)) != nil` |
| M1 — `import SwiftUI` never added to `WellnessReportGenerator.swift` | MEDIUM | Fixed: Step 1.1 now includes `import SwiftUI` when creating the file |
| L1 — CSV verify example had extra comma (10 fields instead of 9) | LOW | Fixed: corrected to `"2026-03-26,,0,0.0,0.0,0.0,0,0,"` |
| L2 — Modifier order for `.task`/`.onDisappear`/`.presentationDetents` unspecified | LOW | Acknowledged: note added in Phase 4.4 |

---

## Pre-Implementation

- [ ] Read the RESOLVED plan in full: `Docs/02_Planning/Specs/260402-wellness-report-export-plan-RESOLVED.md`
- [ ] Confirm `ProgressInsightsView.swift` exists at `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift`
  - Verify: File opens in editor; confirms `@State private var showShareSheet = false` at line 21 and share button at line 188

<!-- RESOLVED: H1 — replaced "verify directory exists" with an action step to create it, since Services/ does not exist yet -->
- [ ] Create the `Services/` subdirectory under `WellPlate/Features + UI/Progress/`:
  ```
  mkdir -p "WellPlate/Features + UI/Progress/Services"
  ```
  - Verify: `ls "WellPlate/Features + UI/Progress/"` now shows both `Views/` and `Services/`. No pbxproj edit needed — `PBXFileSystemSynchronizedRootGroup` auto-includes all files placed under `WellPlate/`.

- [ ] Confirm no file named `WellnessReportView.swift`, `WellnessReportGenerator.swift`, or `WellnessReportShareSheet.swift` already exists under `WellPlate/`
  - Verify: `find WellPlate -name "WellnessReport*"` returns no results

---

## Phase 1: Data Model

### 1.1 — Create `WellnessReportData` struct

<!-- RESOLVED: M1 — file creation now includes `import SwiftUI` from the start, since WellnessReportGenerator (added in step 3.1) requires it -->
- [ ] Create new file `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` with the following initial content:
  ```swift
  import SwiftUI

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
  - Verify: File exists at the correct path and the struct definition is present. `import SwiftUI` is at line 1 — this import is required by `WellnessReportGenerator` (added in Phase 3) which lives in the same file.

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

- [ ] In `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` (the file created in 1.1), below the `WellnessReportData` struct, add the `@MainActor` generator struct:
  ```swift
  @MainActor
  struct WellnessReportGenerator { }
  ```
  - Note: `import SwiftUI` is already at line 1 from step 1.1 — do not add a second import.

- [ ] Implement `static func renderImage(data: WellnessReportData) async -> UIImage?` inside the struct:
  - Instantiate `WellnessReportView(data: data)`
  - Create `ImageRenderer(content: view)`
  - Set `renderer.scale = 2.0`
  - Guard on `renderer.uiImage`
  - Compress: `uiImage.jpegData(compressionQuality: 0.88)` → `UIImage(data: jpegData) ?? uiImage`
  - Return `UIImage?`
  - Verify: Function is `async` and in a `@MainActor` struct — `ImageRenderer` requires main actor

- [ ] Implement `static func generateCSV(foodLogs:stressReadings:wellnessLogs:) -> Data` inside the struct:
  - Header row: `"date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood"`
  - Build `daySeq: [Date]` — last 7 days (oldest first) using `(0..<7).compactMap { ... }.reversed()`
  - Build `foodByDay`, `stressByDay`, `wellnessByDay` dictionaries keyed by `Date` (start-of-day)
  - For each day: aggregate calories/macros from food, average stress from stress readings, steps/water/mood from wellness
  - Format stress as `String(format: "%.1f", ...)` or `""` when absent
  - Join rows with `"\n"`, encode to `.utf8`

<!-- RESOLVED: L1 — corrected verify example from 10-field to correct 9-field format -->
  - Verify: Output for a day with no logs produces a row like `"2026-03-26,,0,0.0,0.0,0.0,0,0,"` (9 columns: date, stress blank, calories 0, protein 0.0, carbs 0.0, fat 0.0, steps 0, water 0, mood blank) — no crashes on empty arrays

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
  - Note: `URL?` not `UIImage?` or `Data` — `URL` conforms to `Transferable`; `SwiftUI.Image` and raw `Data` do not produce correct share behaviour
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
  - Verify: `.frame(width: 390 * scale, height: 340 * scale)` is present immediately after `.scaleEffect()` — this constrains the layout size and prevents horizontal overflow on iPhone SE (375pt screen). Without this frame, the layout system still sees a 390pt-wide view regardless of the visual scale transform.

### 4.3 — Share buttons inside `WellnessReportShareSheet`

- [ ] Add the "Share as Image" button — **guard on `imageURL`**:
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
  - Verify: `ShareLink(item: csvURL)` where `csvURL: URL` pointing to a `.csv` file — the share target receives a named file with correct MIME type. Do NOT use `ShareLink(item: csvData: Data)` — raw `Data` loses the filename and type.

- [ ] Wrap both share buttons in `VStack(spacing: 12).padding(.horizontal, 20)`

### 4.4 — `.task` block and temp file writing

<!-- RESOLVED: H2 — URL assignments are now conditioned on successful try? write to prevent broken share buttons on write failure -->
<!-- RESOLVED: L2 — note added about modifier order -->
- [ ] Add `.task { }` modifier on the `NavigationStack` (place after `.presentationDetents([.large])` for readability — order relative to `.presentationDetents` and `.onDisappear` does not affect behaviour):

  ```swift
  .task {
      // Render image → write to temp JPEG file (only set imageURL if write succeeds)
      if let uiImage = await WellnessReportGenerator.renderImage(data: reportData),
         let jpegData = uiImage.jpegData(compressionQuality: 0.88) {
          let url = FileManager.default.temporaryDirectory
              .appendingPathComponent("WellPlate_Weekly_Report.jpg")
          if (try? jpegData.write(to: url)) != nil {
              imageURL = url
          }
      }

      // Generate CSV → write to temp .csv file (only set csvURL if write succeeds)
      let csvData = WellnessReportGenerator.generateCSV(
          foodLogs: foodLogs,
          stressReadings: stressReadings,
          wellnessLogs: wellnessLogs
      )
      let csvFileURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("WellPlate_Weekly_Data.csv")
      if (try? csvData.write(to: csvFileURL)) != nil {
          csvURL = csvFileURL
      }

      isRendering = false
  }
  ```
  - Verify: Both `imageURL` and `csvURL` assignments are inside `if (try? ...) != nil` guards — `isRendering = false` only executes after both operations complete (whether they succeed or fail). If a write fails, the corresponding button is hidden (URL stays nil) rather than appearing with a broken file.

### 4.5 — Temp file cleanup

- [ ] Add `.onDisappear { }` modifier on the `NavigationStack` (after `.task`):
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
- [ ] Add the `.sheet` modifier **after** `.background(StatusBarStyleModifier())`, making it the outermost modifier in the chain:
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
