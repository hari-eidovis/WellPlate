# Implementation Checklist: F3. Circadian Stack

**Source Plan**: `Docs/02_Planning/Specs/260407-circadian-stack-plan-RESOLVED.md`
**Date**: 2026-04-07

---

## Pre-Implementation

- [ ] Read and understand the resolved plan
- [ ] Verify all referenced files exist:
  - [ ] `WellPlate/Models/HealthModels.swift`
  - [ ] `WellPlate/Core/Services/HealthKitService.swift`
  - [ ] `WellPlate/Core/Services/HealthKitServiceProtocol.swift`
  - [ ] `WellPlate/Core/Services/MockHealthKitService.swift`
  - [ ] `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - [ ] `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - [ ] `WellPlate/Features + UI/Stress/Views/StressView.swift`

---

## Phase 1: Data Layer

### 1.1 — Extend `DailySleepSummary` with bedtime/wakeTime

- [ ] In `WellPlate/Models/HealthModels.swift`, add two properties to `DailySleepSummary` (after `deepHours`):
  ```swift
  let bedtime: Date? = nil
  let wakeTime: Date? = nil
  ```
  - Verify: `DailySleepSummary` struct has 8 stored properties (id, date, totalHours, coreHours, remHours, deepHours, bedtime, wakeTime). Existing computed properties (`quality`, `stageBreakdown`) are unchanged.

### 1.2 — Update `fetchDailySleepSummaries` in HealthKitService

- [ ] In `WellPlate/Core/Services/HealthKitService.swift`, inside the `fetchDailySleepSummaries(for:)` method's `grouped.map` closure (~line 162–176):
  - Add before the `return DailySleepSummary(...)` line:
    ```swift
    let bedtime = daySamples.map(\.date).min()
    let wakeTime = daySamples.map { $0.date.addingTimeInterval($0.value * 3600) }.max()
    ```
  - Update the `DailySleepSummary(...)` init to pass:
    ```swift
    bedtime: total >= 3.0 ? bedtime : nil,
    wakeTime: total >= 3.0 ? wakeTime : nil
    ```
  - Verify: The `DailySleepSummary` init now passes `bedtime:` and `wakeTime:` arguments. Sessions with `total < 3.0` get nil for both.

### 1.3 — Add `fetchDaylight` to protocol

- [ ] In `WellPlate/Core/Services/HealthKitServiceProtocol.swift`, add after `fetchRespiratoryRate` (before the State of Mind section):
  ```swift
  /// Daily time in daylight (minutes) sums over the given interval.
  /// Returns empty array if Apple Watch is not paired or data unavailable.
  func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample]
  ```
  - Verify: Protocol now has the `fetchDaylight` method. Build will fail until concrete types conform (expected — fixed in 1.4 and 1.5).

### 1.4 — Implement `fetchDaylight` in HealthKitService + add to readTypes

- [ ] In `WellPlate/Core/Services/HealthKitService.swift`, add `.timeInDaylight` to the `quantityIDs` array inside `readTypes` (~line 38–41):
  ```swift
  .bloodPressureSystolic, .bloodPressureDiastolic, .respiratoryRate,
  .timeInDaylight
  ```
  - Verify: `quantityIDs` array has 11 items (was 10).

- [ ] In the same file, add `fetchDaylight` method after `fetchRespiratoryRate` (~after line 211):
  ```swift
  func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample] {
      guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else {
          throw HealthKitError.typeNotAvailable
      }
      return try await fetchDailySum(type: type, unit: .minute(), range: range)
  }
  ```
  - Verify: Method exists, uses `fetchDailySum` (not `fetchDailyAvg`), unit is `.minute()`.

### 1.5 — Implement `fetchDaylight` in MockHealthKitService

- [ ] In `WellPlate/Core/Services/MockHealthKitService.swift`, add after `fetchRespiratoryRate`:
  ```swift
  func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample] {
      snapshot.daylightHistory.filter { range.contains($0.date) }
  }
  ```
  - Verify: MockHealthKitService now conforms to the updated protocol (no compiler error for missing method once 1.6 adds `daylightHistory` to snapshot).

### 1.6 — Update StressMockSnapshot with daylight + bedtime/wakeTime

- [ ] In `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`, add `daylightHistory: [DailyMetricSample]` as a stored property (after `respiratoryRateHistory`).
  - Verify: Struct has the new property.

- [ ] In `makeDefault()`, add a `daylightBase` array (30 values, range 10–45):
  ```swift
  let daylightBase: [Double] = [
      25, 30, 15, 35, 10, 28, 32,
      20, 33, 40, 12, 27, 35, 22,
      38, 18, 25, 42, 30, 28,
      22, 35, 31, 14, 26, 38, 24,
      30, 34, 28
  ]
  let daylightHist = (0..<count).map { DailyMetricSample(date: daysAgo(count - 1 - $0), value: daylightBase[$0]) }
  ```
  - Verify: `daylightHist` has 30 elements.

- [ ] Add a `bedtimeHours` array (30 values, centered around 23.0):
  ```swift
  let bedtimeHours: [Double] = [
      23.0, 23.3, 22.8, 23.5, 22.5, 23.1, 23.2,
      22.9, 23.4, 23.0, 22.6, 23.3, 23.1, 23.5,
      22.7, 23.0, 23.4, 22.8, 23.2, 23.6,
      23.0, 22.9, 23.3, 22.4, 23.1, 23.0, 23.5,
      22.8, 23.2, 23.0
  ]
  ```

- [ ] Update the `sleepHist` map closure to compute and pass bedtime/wakeTime:
  ```swift
  let sleepHist: [DailySleepSummary] = (0..<count).map { i in
      let total = sleepTotals[i]
      let deep  = total * deepRatios[i]
      let rem   = total * remRatios[i]
      let core  = max(0, total - deep - rem)
      let dayDate = daysAgo(count - 1 - i)
      let prevDay = cal.date(byAdding: .day, value: -1, to: dayDate)!
      let btDecimal = bedtimeHours[i]
      let btDate = cal.date(bySettingHour: Int(btDecimal),
                            minute: Int((btDecimal.truncatingRemainder(dividingBy: 1)) * 60),
                            second: 0, of: prevDay)
      let wtDate = btDate?.addingTimeInterval(total * 3600)
      return DailySleepSummary(date: dayDate, totalHours: total,
                               coreHours: core, remHours: rem, deepHours: deep,
                               bedtime: btDate, wakeTime: wtDate)
  }
  ```
  - Verify: Each `DailySleepSummary` in the history now has non-nil `bedtime` and `wakeTime`.

- [ ] Update `sleepToday` to include bedtime/wakeTime:
  ```swift
  let sleepTodayBedtime = cal.date(bySettingHour: 23, minute: 0, second: 0,
                                    of: cal.date(byAdding: .day, value: -1, to: today)!)
  let sleepToday = DailySleepSummary(
      date: today,
      totalHours: 7.2,
      coreHours: 3.1,
      remHours: 1.8,
      deepHours: 2.3,
      bedtime: sleepTodayBedtime,
      wakeTime: sleepTodayBedtime?.addingTimeInterval(7.2 * 3600)
  )
  ```
  - Verify: `sleepToday` has bedtime at 23:00 yesterday, wakeTime ~06:12 today.

- [ ] Add `daylightHistory: daylightHist` to the `StressMockSnapshot(...)` return constructor.
  - Verify: All init parameters match the struct's stored properties in order.

---

## Phase 2: Scoring Service

### 2.1 — Create CircadianService

- [ ] Create new file `WellPlate/Core/Services/CircadianService.swift`.

- [ ] Add `CircadianLevel` enum with cases `.aligned`, `.adjusting`, `.disrupted`:
  - `score >= 70` → `.aligned`
  - `score >= 40` → `.adjusting`
  - else → `.disrupted`
  - Include `rawValue: String` ("Aligned", "Adjusting", "Disrupted")
  - Verify: Enum has 3 cases, an `init(score: Double)`, and a `color` property returning semantic color name strings.

- [ ] Add `CircadianResult` struct with fields:
  - `score: Double` (0–100)
  - `regularityScore: Double` (0–100)
  - `daylightScore: Double?` (nil if no Watch data)
  - `level: CircadianLevel`
  - `tip: String`
  - `hasEnoughData: Bool`
  - Verify: All fields are `Double` (not `Int`) to match codebase conventions.

- [ ] Implement `static func compute(sleepSummaries:daylightSamples:) -> CircadianResult`:
  - Call `sleepRegularityIndex(from:)` for regularity score
  - Call `daylightScore(from:)` for daylight score
  - Composite: if daylight exists, 50/50 blend; else regularity alone
  - Derive level and tip from scores
  - If `!hasEnoughData`, return score=0
  - Verify: Method compiles and returns a valid `CircadianResult`.

- [ ] Implement `static func sleepRegularityIndex(from:) -> (score: Double, hasEnoughData: Bool)`:
  - Filter summaries to those with non-nil `bedtime` and `wakeTime`
  - Return `(0, false)` if < 5 valid nights
  - Convert bedtime/wakeTime to minutes-past-6PM (handle midnight crossing)
  - Compute stdDev of bedtime minutes (40% weight) and wake minutes (60% weight)
  - Score: `max(0, 100 * (1 - combinedSD / 75))`
  - Verify: Returns `(score: Double, hasEnoughData: Bool)` tuple.

- [ ] Implement `static func daylightScore(from:) -> Double?`:
  - Return `nil` if samples is empty
  - Average daily minutes → score: `min(100, avg / 30 * 100)`
  - Verify: Returns `nil` for empty input, `100.0` for 30+ min average.

- [ ] Implement `static func selectTip(regularityScore:daylightScore:) -> String`:
  - If daylight exists and regularity ≤ daylight → bed consistency tip
  - If daylight exists and daylight < regularity → outdoor light tip
  - If no daylight and regularity ≥ 70 → "keep it up" tip
  - Else → "consistent bed and wake times" tip
  - Verify: Returns a non-empty String for all input combinations.

- [ ] Implement private helpers:
  - `minutesPast6PM(_ date: Date) -> Double` — shift to 6PM anchor
  - `standardDeviation(_ values: [Double]) -> Double` — population std dev
  - Verify: `minutesPast6PM` for 11PM returns 300, midnight returns 360, 2AM returns 480.

---

## Phase 3: ViewModel Integration

### 3.1 — Add circadian to StressViewModel

- [ ] In `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`, add published properties (after the 30-day history block, ~line 53):
  ```swift
  // MARK: - Circadian
  @Published var circadianResult: CircadianService.CircadianResult = CircadianService.CircadianResult(
      score: 0, regularityScore: 0, daylightScore: nil, level: .disrupted, tip: "", hasEnoughData: false
  )
  @Published var daylightHistory: [DailyMetricSample] = []
  ```
  - Verify: Two new `@Published` properties exist.

- [ ] Add safe fetch helper (after `fetchRRHistorySafely`, ~line 522):
  ```swift
  private func fetchDaylightHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
      (try? await healthService.fetchDaylight(for: range)) ?? []
  }
  ```
  - Verify: Method exists, returns `[]` on failure.

- [ ] In `loadData()`, add to the 30-day `async let` parallel fetch block (~line 268–276):
  ```swift
  async let daylightHist = fetchDaylightHistorySafely(range: thirtyDayRange)
  ```
  - Verify: Line is within the same `async let` block as the other history fetches.

- [ ] After the history assignments (~line 286), add:
  ```swift
  daylightHistory = await daylightHist
  ```
  - Verify: `daylightHistory` is assigned from the `async let`.

- [ ] After today's vitals extraction (~line 294), compute circadian score:
  ```swift
  let sevenDayStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
  let recentSleep = sleepHistory.filter { $0.date >= sevenDayStart }
  let recentDaylight = daylightHistory.filter { $0.date >= sevenDayStart }
  circadianResult = CircadianService.compute(sleepSummaries: recentSleep, daylightSamples: recentDaylight)
  ```
  - Verify: `circadianResult` is computed from 7-day filtered data.

- [ ] Add `#if DEBUG` logging after circadian computation:
  ```swift
  #if DEBUG
  log("🌅 Circadian → score=\(fmt2(circadianResult.score))  regularity=\(fmt2(circadianResult.regularityScore))  daylight=\(circadianResult.daylightScore.map { fmt2($0) } ?? "nil")  level=\(circadianResult.level.rawValue)  hasData=\(circadianResult.hasEnoughData)")
  #endif
  ```
  - Verify: Log line appears in console when running in mock mode debug.

---

## Phase 4: UI

### 4.1 — Create CircadianCardView

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/CircadianCardView.swift`.

- [ ] Implement `CircadianCardView` as a SwiftUI `View`:
  - Parameters: `result: CircadianService.CircadianResult`, `onTap: () -> Void`
  - Use `Button` wrapping the card content with `onTap` action
  - Card styling: `RoundedRectangle(cornerRadius: 24, style: .continuous)` + `.fill(Color(.systemBackground).opacity(0.85))` + `.shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)`
  - Show sun icon (`sun.max.fill`), section label, chevron
  - Show composite score + `result.level.rawValue` label
  - Show regularity sub-score + daylight sub-score in side-by-side mini cards
  - Show `result.tip` text
  - Verify: Card renders with all sub-components in Xcode preview.

- [ ] Handle 3 states:
  - **Normal** (`hasEnoughData && daylightScore != nil`): Full card with both sub-scores
  - **No Watch** (`hasEnoughData && daylightScore == nil`): Regularity score only + "Add Apple Watch for daylight data" note
  - **Not enough data** (`!hasEnoughData`): "Need 5+ nights of sleep data" placeholder
  - Verify: Each state renders without crash in preview.

- [ ] Add accessibility: `.accessibilityElement(children: .combine)` and `.accessibilityLabel` summarizing score and level.
  - Verify: VoiceOver reads a coherent summary.

### 4.2 — Create CircadianDetailView

- [ ] Create new file `WellPlate/Features + UI/Stress/Views/CircadianDetailView.swift`.

- [ ] Implement `CircadianDetailView` as a SwiftUI `View`:
  - Parameters: `result: CircadianService.CircadianResult`, `sleepSummaries: [DailySleepSummary]`, `daylightSamples: [DailyMetricSample]`
  - Wrap in `NavigationStack` with title "Circadian Health"
  - Verify: View compiles with all 3 parameters.

- [ ] Add Score Summary section:
  - Big score number + `result.level.rawValue` label with semantic color
  - Use `CircadianLevel` color (green/orange/red)
  - Verify: Score and label render.

- [ ] Add Sleep Regularity Chart section (7-day):
  - Filter `sleepSummaries` to last 7 days with non-nil `bedtime`/`wakeTime`
  - Use Swift Charts `Chart` with `BarMark` showing bedtime→wakeTime range per night
  - Use indigo/purple tones (sleep family colors)
  - Verify: Chart renders with mock data in preview.

- [ ] Add Daylight Exposure Chart section (7-day):
  - Filter `daylightSamples` to last 7 days
  - Use Swift Charts `Chart` with `BarMark` for minutes/day
  - Add `RuleMark` at y=30 (target line)
  - Use warm amber/gold color
  - **Hide entire section** if `result.daylightScore == nil`
  - Verify: Chart renders with mock data; section hidden when `daylightScore` is nil.

- [ ] Add Tips section:
  - Show `result.tip` prominently
  - Add 1-2 supplementary static tips based on scores
  - Verify: Tips section renders.

### 4.3 — Wire into StressView

- [ ] In `WellPlate/Features + UI/Stress/Views/StressView.swift`, add `.circadian` case to `StressSheet` enum:
  ```swift
  case circadian
  ```
  - Verify: Enum has the new case.

- [ ] Add `case .circadian: return "circadian"` to the `id` computed property switch.
  - Verify: `StressSheet` `id` switch is exhaustive.

- [ ] Add `CircadianDetailView` to the `.sheet(item: $activeSheet)` switch (after `.fasting`):
  ```swift
  case .circadian:
      CircadianDetailView(
          result: viewModel.circadianResult,
          sleepSummaries: viewModel.sleepHistory,
          daylightSamples: viewModel.daylightHistory
      )
  ```
  - Verify: Sheet switch is exhaustive with the new case.

- [ ] Add Circadian Health card to `insightsSheet` (between `factorsSection` and "7-DAY TREND"):
  ```swift
  VStack(alignment: .leading, spacing: 12) {
      sectionLabel("CIRCADIAN HEALTH")
      CircadianCardView(result: viewModel.circadianResult) {
          activeSheet = .circadian
          showInsights = false
      }
  }
  .padding(.horizontal, 16)
  .padding(.top, 28)
  ```
  - Verify: In the insights sheet scroll, the Circadian section appears between Stress Factors and 7-Day Trend.

---

## Phase 5: Build & Verify

### 5.1 — Build all targets

- [ ] Build main app:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED

- [ ] Build ScreenTimeMonitor:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED

- [ ] Build ScreenTimeReport:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED

- [ ] Build WellPlateWidget:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: BUILD SUCCEEDED

### 5.2 — Fix build errors (if any)

- [ ] If any target fails, read error output and fix:
  - Most likely: missing `StressSheet.circadian` in an exhaustive switch (check `StressImmersiveView`)
  - Most likely: `StressMockSnapshot` init parameter order mismatch
  - Most likely: protocol conformance for `fetchDaylight` missing in a service
  - Verify: All 4 targets build after fixes.

### 5.3 — Mock mode smoke test

- [ ] Run the app in Simulator with mock mode enabled (AppConfig)
- [ ] Navigate to Stress tab
- [ ] Tap Insights (chart icon in top bar)
- [ ] Verify: Circadian Health section visible with score, level label, sub-scores, and tip
- [ ] Tap the Circadian card
- [ ] Verify: CircadianDetailView opens with score summary, sleep regularity chart, daylight chart, and tips
- [ ] Dismiss detail sheet
- [ ] Verify: Returns to insights sheet cleanly

---

## Post-Implementation

- [ ] All 4 build targets compile cleanly (Phase 5.1)
- [ ] Mock mode smoke test passes (Phase 5.3)
- [ ] Confirm `totalScore` is unchanged (Circadian does NOT affect stress composite)
- [ ] Git commit with descriptive message
