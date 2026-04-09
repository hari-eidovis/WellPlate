# Implementation Plan: Wellness Report Export (PDF + CSV) — RESOLVED

**Date**: 2026-04-02
**Strategy**: `Docs/02_Planning/Specs/260402-wellness-report-export-strategy.md`
**Audit**: `Docs/03_Audits/260402-wellness-report-export-plan-audit.md`
**Status**: Audit-Resolved — Ready for Checklist

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| C1 — `goals.dailyCups` / `goals.dailyCalorieGoal` don't exist | CRITICAL | Fixed: changed to `goals.waterDailyCups` / `goals.calorieGoal` |
| H1 — `ShareLink(item: Image(uiImage:))` not Transferable | HIGH | Fixed: write JPEG to temp URL, share URL via `ShareLink(item: url)` |
| H2 — `ShareLink(item: csvData: Data)` loses filename/type | HIGH | Fixed: write CSV bytes to named temp `.csv` URL, share URL |
| M1 — `.scaleEffect()` without layout-size fix, overflow on narrow devices | MEDIUM | Fixed: add explicit `.frame(width: 390*scale, height: 340*scale)` after scaleEffect |
| M2 — `.sheet` placement should be after last modifier | MEDIUM | Fixed: instruction updated to place after `.background(StatusBarStyleModifier())` |
| L1 — `weekReportData` recomputed on every render | LOW | Acknowledged — acceptable for MVP data volumes |
| L2 — No temp URL cleanup on dismiss | LOW | Acknowledged — iOS manages temp dir; add `.onDisappear` cleanup |

---

## Overview

Add a weekly wellness report export to the existing `ProgressInsightsView`. The share button (line 188) already exists as a dead stub — `showShareSheet` is declared but no sheet is attached. This plan wires it up: a new `WellnessReportShareSheet` previews a rendered `WellnessReportView` card and offers two `ShareLink` buttons — one for a JPEG image, one for a CSV file. A lightweight `WellnessReportGenerator` handles rendering and CSV generation. Three new files, one edit to `ProgressInsightsView`.

---

## Requirements

- Tapping the existing share button (↑) in `ProgressInsightsView` opens a share sheet
- Sheet shows a live preview of the 7-day wellness report card
- Two share options: JPEG image and CSV data file
- Report card covers: date range, stress avg, nutrition avg vs goals, steps avg, mood summary, water avg
- CSV has one row per day: `date, stress_score, calories, protein_g, carbs_g, fat_g, steps, water_glasses, mood`
- Fixed-width 390pt layout for consistent rendering on all devices
- No new SwiftData models, no new navigation routes, no new app entry points

---

## Architecture Changes

- `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift` — add two `@Query` properties (`StressReading`, `WellnessDayLog`), compute `WellnessReportData`, attach `.sheet(isPresented: $showShareSheet)`
- `WellPlate/Features + UI/Progress/Views/WellnessReportView.swift` *(new)* — fixed-width SwiftUI card for rendering and preview
- `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` *(new)* — renders PNG/JPEG + generates CSV
- `WellPlate/Features + UI/Progress/Views/WellnessReportShareSheet.swift` *(new)* — sheet with preview + share buttons

---

## Implementation Steps

### Phase 1: Data Model

**Step 1 — Create `WellnessReportData` struct** (`WellnessReportGenerator.swift`)
- **Action**: Define `WellnessReportData` as a plain `struct` (not SwiftData) at the top of `WellnessReportGenerator.swift`:
  ```swift
  struct WellnessReportData {
      let dateRange: String          // e.g. "Mar 26 – Apr 1, 2026"
      let avgStressScore: Double?    // nil if no StressReadings in window
      let avgCalories: Double
      let calorieGoal: Int
      let avgProtein: Double
      let avgCarbs: Double
      let avgFat: Double
      let avgSteps: Double
      let avgWaterGlasses: Double
      let waterGoal: Int
      let dominantMoodEmoji: String  // most frequent mood emoji, or "—" if none
      let loggedDays: Int            // number of days with at least one food log
  }
  ```
- **Why**: A plain struct decouples rendering from SwiftData. Easy to construct from `ProgressInsightsView`'s existing computed data.
- **Dependencies**: None
- **Risk**: Low

---

**Step 2 — Add `buildReportData()` helper to `ProgressInsightsView`** (`ProgressInsightsView.swift`)
- **Action**:
  1. Add two new `@Query` properties inside `ProgressInsightsView` (after the existing `@Query private var userGoalsList` declaration):
     ```swift
     @Query private var allStressReadings: [StressReading]
     @Query private var allWellnessLogs: [WellnessDayLog]
     ```
  2. Add a private computed property `weekReportData: WellnessReportData` that:
     - Filters `allFoodLogs`, `allStressReadings`, `allWellnessLogs` to the last 7 days
     - Computes averages for each field
     - Picks `dominantMoodEmoji` as the mode of `moodRaw` values across all `WellnessDayLog` entries in the window
     - Formats `dateRange` string as `"MMM d – MMM d, yyyy"`
     - Counts `loggedDays` as days with at least one `FoodLogEntry`

  ```swift
  private var weekReportData: WellnessReportData {
      let cal = Calendar.current
      let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()

      let foodLogs = allFoodLogs.filter { $0.day >= cutoff }
      let stressLogs = allStressReadings.filter { $0.timestamp >= cutoff }
      let wellnessLogs = allWellnessLogs.filter { $0.day >= cutoff }

      // Date range string
      let fmt = DateFormatter()
      fmt.dateFormat = "MMM d"
      let endFmt = DateFormatter()
      endFmt.dateFormat = "MMM d, yyyy"
      let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
      let dateRange = "\(fmt.string(from: start)) – \(endFmt.string(from: Date()))"

      // Nutrition (group by day, then average across days)
      let dayGroups = Dictionary(grouping: foodLogs) { $0.day }
      let loggedDays = dayGroups.count
      let dailyCalories = dayGroups.values.map { logs in logs.reduce(0) { $0 + $1.calories } }
      let dailyProtein  = dayGroups.values.map { logs in logs.reduce(0.0) { $0 + $1.protein } }
      let dailyCarbs    = dayGroups.values.map { logs in logs.reduce(0.0) { $0 + $1.carbs } }
      let dailyFat      = dayGroups.values.map { logs in logs.reduce(0.0) { $0 + $1.fat } }

      let avgCal     = dailyCalories.isEmpty ? 0 : Double(dailyCalories.reduce(0, +)) / Double(dailyCalories.count)
      let avgProtein = dailyProtein.isEmpty  ? 0 : dailyProtein.reduce(0, +) / Double(dailyProtein.count)
      let avgCarbs   = dailyCarbs.isEmpty    ? 0 : dailyCarbs.reduce(0, +) / Double(dailyCarbs.count)
      let avgFat     = dailyFat.isEmpty      ? 0 : dailyFat.reduce(0, +) / Double(dailyFat.count)

      // Stress
      let avgStress: Double? = stressLogs.isEmpty ? nil :
          stressLogs.map(\.score).reduce(0, +) / Double(stressLogs.count)

      // Steps + water (from WellnessDayLog)
      let avgSteps = wellnessLogs.isEmpty ? 0.0 :
          Double(wellnessLogs.map(\.steps).reduce(0, +)) / Double(wellnessLogs.count)
      let avgWater = wellnessLogs.isEmpty ? 0.0 :
          Double(wellnessLogs.map(\.waterGlasses).reduce(0, +)) / Double(wellnessLogs.count)

      // Dominant mood
      let moodCounts = Dictionary(grouping: wellnessLogs.compactMap(\.moodRaw)) { $0 }
      let dominantRaw = moodCounts.max(by: { $0.value.count < $1.value.count })?.key
      let dominantEmoji = dominantRaw.flatMap { MoodOption(rawValue: $0) }?.emoji ?? "—"

      // RESOLVED: C1 — corrected field names: waterDailyCups (not dailyCups),
      // calorieGoal (not dailyCalorieGoal)
      let goals = currentGoals

      return WellnessReportData(
          dateRange: dateRange,
          avgStressScore: avgStress,
          avgCalories: avgCal,
          calorieGoal: goals.calorieGoal,
          avgProtein: avgProtein,
          avgCarbs: avgCarbs,
          avgFat: avgFat,
          avgSteps: avgSteps,
          avgWaterGlasses: avgWater,
          waterGoal: goals.waterDailyCups,
          dominantMoodEmoji: dominantEmoji,
          loggedDays: loggedDays
      )
  }
  ```
- **Why**: Keeps data preparation in the view that already has all the `@Query` context.
- **Dependencies**: Step 1
- **Risk**: Low — filtering 7 days from in-memory SwiftData is fast

---

### Phase 2: Report Card View

**Step 3 — Create `WellnessReportView.swift`** *(new file)*
- **Action**: Create `WellPlate/Features + UI/Progress/Views/WellnessReportView.swift` with a fixed 390pt width card layout:

  ```swift
  import SwiftUI

  struct WellnessReportView: View {
      let data: WellnessReportData

      var body: some View {
          VStack(alignment: .leading, spacing: 0) {
              // Header
              headerSection
              Divider()
              // Stats grid
              statsGrid
              // Footer
              footerSection
          }
          .frame(width: 390)
          .background(Color(.systemBackground))
      }

      // Header: brand bar + date range
      private var headerSection: some View {
          HStack {
              VStack(alignment: .leading, spacing: 2) {
                  Text("WellPlate")
                      .font(.r(.headline, .semibold))
                      .foregroundColor(AppColors.brand)
                  Text("Weekly Wellness Report")
                      .font(.r(.caption, .regular))
                      .foregroundColor(AppColors.textSecondary)
              }
              Spacer()
              Text(data.dateRange)
                  .font(.r(.caption2, .regular))
                  .foregroundColor(AppColors.textSecondary)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
          .background(AppColors.brand.opacity(0.06))
      }

      // 2×3 stat tiles
      private var statsGrid: some View {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
              statTile(icon: "brain.head.profile",
                       label: "Avg Stress",
                       value: data.avgStressScore.map { "\(Int($0))/100" } ?? "—",
                       color: stressColor)
              statTile(icon: "flame.fill",
                       label: "Avg Calories",
                       value: "\(Int(data.avgCalories)) / \(data.calorieGoal)",
                       color: Color(hex: "FF6B35"))
              statTile(icon: "figure.walk",
                       label: "Avg Steps",
                       value: data.avgSteps > 0 ? "\(Int(data.avgSteps).formatted())" : "—",
                       color: .blue)
              statTile(icon: "drop.fill",
                       label: "Avg Water",
                       value: "\(Int(data.avgWaterGlasses.rounded())) / \(data.waterGoal) cups",
                       color: Color(hex: "5E9FFF"))
              statTile(icon: "face.smiling",
                       label: "Top Mood",
                       value: data.dominantMoodEmoji,
                       color: .yellow)
              statTile(icon: "checkmark.circle.fill",
                       label: "Days Logged",
                       value: "\(data.loggedDays) / 7",
                       color: .green)
          }
          .background(Color(.separator).opacity(0.2))
      }

      private func statTile(icon: String, label: String, value: String, color: Color) -> some View {
          VStack(alignment: .leading, spacing: 6) {
              HStack(spacing: 5) {
                  Image(systemName: icon)
                      .font(.system(size: 11, weight: .semibold))
                      .foregroundColor(color)
                  Text(label)
                      .font(.r(.caption2, .medium))
                      .foregroundColor(AppColors.textSecondary)
                      .textCase(.uppercase)
                      .kerning(0.3)
              }
              Text(value)
                  .font(.r(.subheadline, .semibold))
                  .foregroundColor(AppColors.textPrimary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.8)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.systemBackground))
      }

      private var stressColor: Color {
          guard let score = data.avgStressScore else { return AppColors.textSecondary }
          switch score {
          case ..<40:  return .green
          case ..<60:  return .yellow
          case ..<80:  return .orange
          default:     return .red
          }
      }

      private var footerSection: some View {
          Text("Generated by WellPlate · Data stays on your iPhone")
              .font(.r(.caption2, .regular))
              .foregroundColor(AppColors.textSecondary.opacity(0.6))
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 10)
              .background(Color(.secondarySystemBackground))
      }
  }
  ```
- **Why**: Fixed 390pt width ensures consistent `ImageRenderer` output across all device sizes.
- **Dependencies**: Step 1 (`WellnessReportData`)
- **Risk**: Low — pure layout view, no async work

---

### Phase 3: Generator

**Step 4 — Create `WellnessReportGenerator.swift`** *(new file)*
- **Action**: Create `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift`:

  ```swift
  import SwiftUI

  @MainActor
  struct WellnessReportGenerator {

      /// Renders WellnessReportView to a JPEG-compressed UIImage.
      static func renderImage(data: WellnessReportData) async -> UIImage? {
          let view = WellnessReportView(data: data)
          let renderer = ImageRenderer(content: view)
          renderer.scale = 2.0   // @2x for crisp output
          guard let uiImage = renderer.uiImage else { return nil }
          // Compress to JPEG for reasonable file size (~200–400KB)
          guard let jpegData = uiImage.jpegData(compressionQuality: 0.88) else { return uiImage }
          return UIImage(data: jpegData) ?? uiImage
      }

      /// Generates a UTF-8 CSV Data blob from the raw log entries.
      static func generateCSV(
          foodLogs: [FoodLogEntry],
          stressReadings: [StressReading],
          wellnessLogs: [WellnessDayLog]
      ) -> Data {
          var rows: [String] = ["date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood"]

          let cal = Calendar.current
          let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()

          // Build per-day map for the last 7 days
          let daySeq: [Date] = (0..<7).compactMap {
              cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date()))
          }.reversed()

          let foodByDay    = Dictionary(grouping: foodLogs.filter { $0.day >= cutoff }) { $0.day }
          let stressByDay  = Dictionary(grouping: stressReadings.filter { $0.timestamp >= cutoff }) { $0.day }
          let wellnessByDay = Dictionary(grouping: wellnessLogs.filter { $0.day >= cutoff }) { $0.day }

          let dateFmt = DateFormatter()
          dateFmt.dateFormat = "yyyy-MM-dd"

          for day in daySeq {
              let food     = foodByDay[day] ?? []
              let stress   = stressByDay[day]
              let wellness = wellnessByDay[day]?.first

              let calories  = food.reduce(0) { $0 + $1.calories }
              let protein   = food.reduce(0.0) { $0 + $1.protein }
              let carbs     = food.reduce(0.0) { $0 + $1.carbs }
              let fat       = food.reduce(0.0) { $0 + $1.fat }
              let stressAvg = stress.map { r in r.map(\.score).reduce(0,+) / Double(r.count) }
              let steps     = wellness?.steps ?? 0
              let water     = wellness?.waterGlasses ?? 0
              let mood      = wellness?.mood?.label ?? ""

              let stressStr = stressAvg.map { String(format: "%.1f", $0) } ?? ""
              let row = "\(dateFmt.string(from: day)),\(stressStr),\(calories),\(String(format:"%.1f",protein)),\(String(format:"%.1f",carbs)),\(String(format:"%.1f",fat)),\(steps),\(water),\(mood)"
              rows.append(row)
          }

          return rows.joined(separator: "\n").data(using: .utf8) ?? Data()
      }
  }
  ```
- **Why**: `@MainActor` struct because `ImageRenderer` must run on the main actor. Static methods keep it stateless.
- **Dependencies**: Steps 1 + 3
- **Risk**: Low

---

### Phase 4: Share Sheet

<!-- RESOLVED: H1 & H2 — Replaced ShareLink(item: Image) and ShareLink(item: Data) with temp-URL-based sharing. @State now holds URL? for both image and CSV. Both URLs are written to FileManager.default.temporaryDirectory in .task. OnDisappear cleans up temp files (addresses L2). -->

**Step 5 — Create `WellnessReportShareSheet.swift`** *(new file)*
- **Action**: Create `WellPlate/Features + UI/Progress/Views/WellnessReportShareSheet.swift`:

  ```swift
  import SwiftUI

  struct WellnessReportShareSheet: View {
      let reportData: WellnessReportData
      let foodLogs: [FoodLogEntry]
      let stressReadings: [StressReading]
      let wellnessLogs: [WellnessDayLog]

      // RESOLVED: H1, H2 — store temp file URLs instead of UIImage/Data
      @State private var imageURL: URL? = nil
      @State private var csvURL: URL? = nil
      @State private var isRendering = true
      @Environment(\.dismiss) private var dismiss

      var body: some View {
          NavigationStack {
              VStack(spacing: 24) {
                  if isRendering {
                      ProgressView("Generating report…")
                          .frame(maxWidth: .infinity, maxHeight: .infinity)
                  } else {
                      ScrollView {
                          VStack(spacing: 20) {
                              // RESOLVED: M1 — use scaleEffect with explicit frame to fix layout on narrow devices
                              let screenW = UIScreen.main.bounds.width - 40
                              let scale = screenW / 390
                              WellnessReportView(data: reportData)
                                  .scaleEffect(scale, anchor: .top)
                                  .frame(width: 390 * scale, height: 340 * scale)
                                  .clipShape(RoundedRectangle(cornerRadius: 16))
                                  .appShadow(radius: 16, y: 6)
                                  .padding(.horizontal, 20)

                              // Share buttons
                              VStack(spacing: 12) {
                                  // RESOLVED: H1 — ShareLink shares a temp JPEG URL (URL conforms to Transferable)
                                  if let url = imageURL {
                                      ShareLink(
                                          item: url,
                                          preview: SharePreview("WellPlate Weekly Report")
                                      ) {
                                          Label("Share as Image", systemImage: "photo")
                                              .font(.r(.body, .semibold))
                                              .frame(maxWidth: .infinity)
                                              .padding(.vertical, 14)
                                              .background(AppColors.brand)
                                              .foregroundColor(.white)
                                              .clipShape(RoundedRectangle(cornerRadius: 14))
                                      }
                                  }

                                  // RESOLVED: H2 — ShareLink shares a temp .csv URL (preserves filename + MIME type)
                                  if let url = csvURL {
                                      ShareLink(
                                          item: url,
                                          preview: SharePreview("WellPlate Weekly Data.csv")
                                      ) {
                                          Label("Export as CSV", systemImage: "tablecells")
                                              .font(.r(.body, .medium))
                                              .frame(maxWidth: .infinity)
                                              .padding(.vertical, 14)
                                              .background(Color(.secondarySystemBackground))
                                              .foregroundColor(AppColors.textPrimary)
                                              .clipShape(RoundedRectangle(cornerRadius: 14))
                                      }
                                  }
                              }
                              .padding(.horizontal, 20)
                          }
                          .padding(.bottom, 32)
                      }
                  }
              }
              .navigationTitle("Weekly Report")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                  ToolbarItem(placement: .topBarTrailing) {
                      Button("Done") { dismiss() }
                          .font(.r(.body, .semibold))
                          .foregroundColor(AppColors.brand)
                  }
              }
          }
          .presentationDetents([.large])
          .task {
              // Render image → write to temp JPEG file
              if let uiImage = await WellnessReportGenerator.renderImage(data: reportData),
                 let jpegData = uiImage.jpegData(compressionQuality: 0.88) {
                  let url = FileManager.default.temporaryDirectory
                      .appendingPathComponent("WellPlate_Weekly_Report.jpg")
                  try? jpegData.write(to: url)
                  imageURL = url
              }

              // Generate CSV → write to temp .csv file
              let csvData = WellnessReportGenerator.generateCSV(
                  foodLogs: foodLogs,
                  stressReadings: stressReadings,
                  wellnessLogs: wellnessLogs
              )
              let csvFileURL = FileManager.default.temporaryDirectory
                  .appendingPathComponent("WellPlate_Weekly_Data.csv")
              try? csvData.write(to: csvFileURL)
              csvURL = csvFileURL

              isRendering = false
          }
          // RESOLVED: L2 — clean up temp files when sheet dismisses
          .onDisappear {
              if let url = imageURL { try? FileManager.default.removeItem(at: url) }
              if let url = csvURL   { try? FileManager.default.removeItem(at: url) }
          }
      }
  }
  ```
- **Why**: Writing to temp URLs makes both image and CSV natively shareable — `URL` conforms to `Transferable`, the OS infers MIME type from the file extension, and the filename appears correctly in the share sheet.
- **Dependencies**: Steps 1, 3, 4
- **Risk**: Low

---

### Phase 5: Wire Into ProgressInsightsView

<!-- RESOLVED: M2 — sheet placement instruction updated to place AFTER .background(StatusBarStyleModifier()), the last modifier, so .sheet is the outermost modifier in the chain. -->

**Step 6 — Attach sheet to existing `showShareSheet` stub** (`ProgressInsightsView.swift`)
- **Action**: In `ProgressInsightsView.body`, after the existing `.background(StatusBarStyleModifier())` modifier (the last modifier, around line 237) — making `.sheet` the outermost modifier — add:
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
- **Why**: The button already sets `showShareSheet = true` — this is purely wiring. The filter is repeated here (not via `weekReportData`) because `WellnessReportGenerator.generateCSV` needs the raw per-day entries, not averages.
- **Dependencies**: Steps 1–5
- **Risk**: Low

---

## Testing Strategy

**Build verification** (all 4 targets):
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Manual verification flows**:
1. Open `FoodJournalView` → tap chart icon → `ProgressInsightsView` opens → tap share (↑) button → `WellnessReportShareSheet` appears with loading indicator, then report preview
2. Tap "Share as Image" → iOS share sheet opens with JPEG image named `WellPlate_Weekly_Report.jpg`
3. Tap "Export as CSV" → iOS share sheet opens with `WellPlate_Weekly_Data.csv` file
4. Verify report card shows all 6 stat tiles with correct values
5. Verify "Days Logged" reflects actual logged days (not always 7)
6. With no StressReadings in window → "Avg Stress" shows "—" (not crash)
7. With no WellnessDayLog entries → steps/water show "0 / goal", mood shows "—"
8. Verify on iPhone SE / 375pt screen — preview card fits without horizontal overflow

---

## Risks & Mitigations

- **Risk**: `ImageRenderer` returns `nil` on simulator edge case
  - **Mitigation**: `renderImage` returns `UIImage?`. Share sheet hides "Share as Image" button when `imageURL == nil`. CSV always available.

- **Risk**: Temp file write fails (e.g., disk full)
  - **Mitigation**: Both `try? jpegData.write(to: url)` and `try? csvData.write(to: csvFileURL)` use optional-try — failures silently leave `imageURL`/`csvURL` as `nil`, hiding the corresponding button. No crash.

- **Risk**: `WellnessDayLog` steps field may not reflect HealthKit steps
  - **Mitigation**: Use `WellnessDayLog.steps` as-is. If 0, shows 0. No new HealthKit calls.

- **Risk**: `@Query` additions to `ProgressInsightsView` increase query count
  - **Mitigation**: Two simple `@Query` with no predicate — negligible for tables with at most hundreds of rows.

---

## Success Criteria

- [ ] All 4 build targets compile cleanly
- [ ] Tapping share (↑) in `ProgressInsightsView` opens the sheet (not a no-op)
- [ ] Report card renders with correct date range
- [ ] "Share as Image" opens native iOS share sheet with `WellPlate_Weekly_Report.jpg`
- [ ] "Export as CSV" opens native iOS share sheet with `WellPlate_Weekly_Data.csv`
- [ ] CSV has header row + 7 data rows, correctly formatted
- [ ] Zero crashes when stress/wellness data is absent
- [ ] `isRendering` spinner visible then replaced by report card
- [ ] Preview card fits without overflow on iPhone SE (375pt screen)
