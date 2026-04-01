# Implementation Plan: Wellness Report Export (PDF + CSV)

**Date**: 2026-04-02
**Strategy**: `Docs/02_Planning/Specs/260402-wellness-report-export-strategy.md`
**Status**: Ready for Audit

---

## Overview

Add a weekly wellness report export to the existing `ProgressInsightsView`. The share button (line 188) already exists as a dead stub — `showShareSheet` is declared but no sheet is attached. This plan wires it up: a new `WellnessReportShareSheet` previews a rendered `WellnessReportView` card and offers two `ShareLink` buttons — one for a PNG image, one for a CSV file. A lightweight `WellnessReportGenerator` handles rendering and CSV generation. Three new files, one edit to `ProgressInsightsView`.

---

## Requirements

- Tapping the existing share button (↑) in `ProgressInsightsView` opens a share sheet
- Sheet shows a live preview of the 7-day wellness report card
- Two share options: PNG image and CSV data file
- Report card covers: date range, stress avg, nutrition avg vs goals, steps avg, mood summary, water avg
- CSV has one row per day: `date, stress_score, calories, protein_g, carbs_g, fat_g, steps, water_glasses, mood`
- Fixed-width 390pt layout for consistent rendering on all devices
- No new SwiftData models, no new navigation routes, no new app entry points

---

## Architecture Changes

- `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift` — add two `@Query` properties (`StressReading`, `WellnessDayLog`), compute `WellnessReportData`, attach `.sheet(isPresented: $showShareSheet)`
- `WellPlate/Features + UI/Progress/Views/WellnessReportView.swift` *(new)* — fixed-width SwiftUI card for rendering and preview
- `WellPlate/Features + UI/Progress/Services/WellnessReportGenerator.swift` *(new)* — renders PNG + generates CSV
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
  1. Add two new `@Query` properties inside `ProgressInsightsView`:
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

      let goals = currentGoals

      return WellnessReportData(
          dateRange: dateRange,
          avgStressScore: avgStress,
          avgCalories: avgCal,
          calorieGoal: goals.dailyCalorieGoal,
          avgProtein: avgProtein,
          avgCarbs: avgCarbs,
          avgFat: avgFat,
          avgSteps: avgSteps,
          avgWaterGlasses: avgWater,
          waterGoal: goals.dailyCups,
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

          let foodByDay   = Dictionary(grouping: foodLogs.filter { $0.day >= cutoff }) { $0.day }
          let stressByDay = Dictionary(grouping: stressReadings.filter { $0.timestamp >= cutoff }) { $0.day }
          let wellnessByDay = Dictionary(grouping: wellnessLogs.filter { $0.day >= cutoff }) { $0.day }

          let dateFmt = DateFormatter()
          dateFmt.dateFormat = "yyyy-MM-dd"

          for day in daySeq {
              let food    = foodByDay[day] ?? []
              let stress  = stressByDay[day]
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
- **Why**: `@MainActor` struct because `ImageRenderer` must run on the main actor. Static methods keep it stateless — easy to call from any view.
- **Dependencies**: Steps 1 + 3
- **Risk**: Low — `ImageRenderer` is well-established on iOS 16+

---

### Phase 4: Share Sheet

**Step 5 — Create `WellnessReportShareSheet.swift`** *(new file)*
- **Action**: Create `WellPlate/Features + UI/Progress/Views/WellnessReportShareSheet.swift`:

  ```swift
  import SwiftUI

  struct WellnessReportShareSheet: View {
      let reportData: WellnessReportData
      let foodLogs: [FoodLogEntry]
      let stressReadings: [StressReading]
      let wellnessLogs: [WellnessDayLog]

      @State private var renderedImage: UIImage? = nil
      @State private var csvData: Data = Data()
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
                              // Live preview
                              WellnessReportView(data: reportData)
                                  .clipShape(RoundedRectangle(cornerRadius: 16))
                                  .appShadow(radius: 16, y: 6)
                                  .padding(.horizontal, 20)
                                  .scaleEffect(UIScreen.main.bounds.width / 390)
                                  .frame(height: previewHeight)

                              // Share buttons
                              VStack(spacing: 12) {
                                  if let image = renderedImage {
                                      ShareLink(
                                          item: Image(uiImage: image),
                                          preview: SharePreview(
                                              "WellPlate Weekly Report",
                                              image: Image(uiImage: image)
                                          )
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

                                  ShareLink(
                                      item: csvData,
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
              async let image = WellnessReportGenerator.renderImage(data: reportData)
              let csv = WellnessReportGenerator.generateCSV(
                  foodLogs: foodLogs,
                  stressReadings: stressReadings,
                  wellnessLogs: wellnessLogs
              )
              renderedImage = await image
              csvData = csv
              isRendering = false
          }
      }

      // Scale WellnessReportView (390pt wide) to fit current screen minus padding
      private var previewHeight: CGFloat {
          let screenW = UIScreen.main.bounds.width - 40
          let scale = screenW / 390
          return 340 * scale   // approximate card height × scale
      }
  }
  ```
- **Why**: `.task` fires on appear and runs both render operations concurrently. `ProgressView` hides the slight delay.
- **Dependencies**: Steps 1, 3, 4
- **Risk**: Low — `async let` for concurrent image render + csv generation

---

### Phase 5: Wire Into ProgressInsightsView

**Step 6 — Attach sheet to existing `showShareSheet` stub** (`ProgressInsightsView.swift`)
- **Action**: In `ProgressInsightsView.body`, after the existing `.preferredColorScheme(colorScheme)` modifier (around line 235), add:
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
2. Tap "Share as Image" → iOS share sheet opens with PNG image
3. Tap "Export as CSV" → iOS share sheet opens with `.csv` file
4. Verify report card shows all 6 stat tiles with correct values
5. Verify "Days Logged" reflects actual logged days (not always 7)
6. With no StressReadings in window → "Avg Stress" shows "—" (not crash)
7. With no WellnessDayLog entries → steps/water show "0 / goal", mood shows "—"

---

## Risks & Mitigations

- **Risk**: `ImageRenderer` returns `nil` on simulator edge case
  - **Mitigation**: `renderImage` returns `UIImage?`. Share sheet hides "Share as Image" button when `renderedImage == nil`. CSV always available.

- **Risk**: `ShareLink(item: Image(uiImage:))` requires `Transferable` conformance — `Image` from `UIImage` may not directly conform in all SDK versions
  - **Mitigation**: If `Image` doesn't transfer directly, use `ShareLink(item: url)` where url is a temp file written with `UIImage.jpegData`. Plan resolves this if needed during implementation.

- **Risk**: `WellnessDayLog` steps field may not reflect HealthKit steps (depends on app sync)
  - **Mitigation**: Use `WellnessDayLog.steps` as-is — it's what the app persists. If 0, it shows 0. No new HealthKit calls in this feature.

- **Risk**: `@Query` additions to `ProgressInsightsView` increase query count
  - **Mitigation**: Two simple `@Query` with no predicate (fetch all, filter in memory) — negligible performance impact for wellness and stress tables which have at most hundreds of rows.

---

## Success Criteria

- [ ] All 4 build targets compile cleanly
- [ ] Tapping share (↑) in `ProgressInsightsView` opens the sheet (not a no-op as before)
- [ ] Report card renders with correct date range
- [ ] "Share as Image" opens native iOS share sheet with PNG
- [ ] "Export as CSV" opens native iOS share sheet with `.csv` file
- [ ] CSV has header row + 7 data rows, correctly formatted
- [ ] Zero crashes when stress/wellness data is absent
- [ ] `isRendering` spinner visible then replaced by report card (no blank flash)
