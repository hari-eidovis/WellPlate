# Implementation Plan: F3. Circadian Stack

**Date**: 2026-04-07
**Source**: `Docs/02_Planning/Specs/260407-circadian-stack-strategy.md`
**Status**: Ready for Audit

## Overview

Add a Circadian Score (0–100) to the StressView insights sheet. The score blends sleep timing regularity (SRI — standard deviation of bedtime/wake time over 7 nights) with daylight exposure (`timeInDaylight` from Apple Watch). Gracefully degrades to SRI-only when Watch data is absent. Three new files, six modified files. Circadian is informational — does not affect the 100-point composite stress score.

## Requirements

- Compute Circadian Score from sleep regularity (SRI) + daylight exposure
- Show as a tappable card in the insights sheet
- Detail sheet with 7-day bed/wake time chart + daylight bars + actionable tips
- Degrade gracefully when Apple Watch is not present (no `timeInDaylight` data)
- Require ≥ 5 nights in last 7 days for a valid SRI; show "Not enough data" otherwise
- Mock mode support for all new data paths
- No change to composite stress score (informational axis only)

## Architecture Changes

| Change | File | Description |
|---|---|---|
| Model extension | `HealthModels.swift` | Add `bedtime: Date?` and `wakeTime: Date?` to `DailySleepSummary` |
| New HK fetch | `HealthKitService.swift` | Add `.timeInDaylight` to `readTypes`; add `fetchDaylight(for:)` method |
| Protocol update | `HealthKitServiceProtocol.swift` | Add `fetchDaylight(for:)` |
| Mock update | `MockHealthKitService.swift` | Implement `fetchDaylight(for:)` |
| Mock data | `StressMockSnapshot.swift` | Add `daylightHistory` array; update sleep summaries with bedtime/wakeTime |
| New service | `CircadianService.swift` (new) | Stateless enum: SRI computation, daylight scoring, composite score, tip selection |
| VM integration | `StressViewModel.swift` | Add circadian published properties; fetch daylight; call `CircadianService` |
| Card view | `CircadianCardView.swift` (new) | Score display card with sub-scores and tip |
| Detail view | `CircadianDetailView.swift` (new) | 7-day regularity chart + daylight bars + tips |
| Sheet wiring | `StressView.swift` | Add `.circadian` to `StressSheet`; add card to insights sheet; wire detail sheet |

---

## Implementation Steps

### Phase 1: Data Layer (models + HealthKit)

#### Step 1.1 — Extend `DailySleepSummary` with bedtime/wakeTime

**File**: `WellPlate/Models/HealthModels.swift`

**Action**: Add two optional properties to `DailySleepSummary`:

```swift
struct DailySleepSummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalHours: Double
    let coreHours: Double
    let remHours: Double
    let deepHours: Double
    let bedtime: Date?      // NEW: earliest sleep sample startDate in session
    let wakeTime: Date?     // NEW: latest sleep sample endDate in session
    // existing computed properties unchanged
}
```

**Why**: SRI requires bedtime and wake time per night. Optional fields are additive — all existing call sites that construct `DailySleepSummary` will need to pass these new values, but existing views that read the struct only access `totalHours`, stages, etc. and won't break.

**Dependencies**: None
**Risk**: Low — additive struct change. All call sites constructing `DailySleepSummary` need updating (Steps 1.2, 1.5, 1.6).

---

#### Step 1.2 — Update `fetchDailySleepSummaries` to track bedtime/wakeTime

**File**: `WellPlate/Core/Services/HealthKitService.swift` (lines 149–177)

**Action**: In the `fetchDailySleepSummaries` method, after grouping samples by wake-up date, compute bedtime and wakeTime per night:

```swift
return grouped.map { day, daySamples in
    let core = daySamples.filter { $0.stage == .core }.map(\.value).reduce(0, +)
    let rem  = daySamples.filter { $0.stage == .rem  }.map(\.value).reduce(0, +)
    let deep = daySamples.filter { $0.stage == .deep }.map(\.value).reduce(0, +)
    let unspec = daySamples.filter { $0.stage == .unspecified }.map(\.value).reduce(0, +)
    let total = core + rem + deep + unspec
    
    // Bedtime = earliest sample start; WakeTime = latest sample end
    let bedtime = daySamples.map(\.date).min()
    let wakeTime = daySamples.map { $0.date.addingTimeInterval($0.value * 3600) }.max()
    
    return DailySleepSummary(
        date: day,
        totalHours: total,
        coreHours: core,
        remHours: rem,
        deepHours: deep,
        bedtime: total >= 3.0 ? bedtime : nil,    // ignore naps < 3h
        wakeTime: total >= 3.0 ? wakeTime : nil
    )
}
```

**Why**: Only long sleep sessions (≥ 3h total) should count for circadian regularity — short naps shouldn't skew bedtime calculations.

**Dependencies**: Step 1.1
**Risk**: Low — existing data flow unchanged; just populating new optional fields.

---

#### Step 1.3 — Add `fetchDaylight` to `HealthKitServiceProtocol`

**File**: `WellPlate/Core/Services/HealthKitServiceProtocol.swift`

**Action**: Add after `fetchRespiratoryRate`:

```swift
/// Daily time in daylight (minutes) sums over the given interval.
/// Returns empty array if Apple Watch is not paired or data unavailable.
func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample]
```

**Dependencies**: None
**Risk**: Low

---

#### Step 1.4 — Implement `fetchDaylight` in `HealthKitService` + add to `readTypes`

**File**: `WellPlate/Core/Services/HealthKitService.swift`

**Action A**: Add `.timeInDaylight` to `readTypes` (line 38–41, add to `quantityIDs` array):

```swift
let quantityIDs: [HKQuantityTypeIdentifier] = [
    .stepCount, .activeEnergyBurned, .appleExerciseTime, .heartRate, .dietaryWater,
    .restingHeartRate, .heartRateVariabilitySDNN,
    .bloodPressureSystolic, .bloodPressureDiastolic, .respiratoryRate,
    .timeInDaylight    // NEW
]
```

**Action B**: Add fetch method after `fetchRespiratoryRate` (line ~211), following the `fetchDailySum` pattern since daylight is cumulative:

```swift
func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample] {
    guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else {
        throw HealthKitError.typeNotAvailable
    }
    return try await fetchDailySum(type: type, unit: .minute(), range: range)
}
```

**Why**: `timeInDaylight` is a cumulative quantity (total minutes per day), so use `fetchDailySum` (not `fetchDailyAvg`).

**Dependencies**: Step 1.3
**Risk**: Low — follows established pattern exactly.

---

#### Step 1.5 — Implement `fetchDaylight` in `MockHealthKitService`

**File**: `WellPlate/Core/Services/MockHealthKitService.swift`

**Action**: Add after `fetchRespiratoryRate`:

```swift
func fetchDaylight(for range: DateInterval) async throws -> [DailyMetricSample] {
    snapshot.daylightHistory.filter { range.contains($0.date) }
}
```

**Dependencies**: Steps 1.3, 1.6 (needs `daylightHistory` in snapshot)
**Risk**: Low

---

#### Step 1.6 — Update `StressMockSnapshot` with daylight + bedtime/wakeTime data

**File**: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`

**Action A**: Add `daylightHistory: [DailyMetricSample]` property to the struct.

**Action B**: In `makeDefault()`, generate 30 days of daylight mock data (realistic range: 10–45 min/day):

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

**Action C**: Update sleep summary construction to include bedtime and wakeTime. Generate bedtimes centered around 23:00 with some variance:

```swift
let bedtimeHours: [Double] = [
    23.0, 23.3, 22.8, 23.5, 22.5, 23.1, 23.2,
    22.9, 23.4, 23.0, 22.6, 23.3, 23.1, 23.5,
    22.7, 23.0, 23.4, 22.8, 23.2, 23.6,
    23.0, 22.9, 23.3, 22.4, 23.1, 23.0, 23.5,
    22.8, 23.2, 23.0
]
// In the map closure, compute bedtime/wakeTime:
let bedtimeDecimal = bedtimeHours[i]
let bedtimeDate = cal.date(bySettingHour: Int(bedtimeDecimal),
                           minute: Int((bedtimeDecimal.truncatingRemainder(dividingBy: 1)) * 60),
                           second: 0, of: cal.date(byAdding: .day, value: -1, to: daysAgo(count - 1 - i))!)
let wakeTimeDate = bedtimeDate?.addingTimeInterval(total * 3600)
```

**Action D**: Add `daylightHistory: daylightHist` to the `StressMockSnapshot(...)` constructor call.

**Dependencies**: Steps 1.1 (bedtime/wakeTime fields), 1.5 (mock service reads daylightHistory)
**Risk**: Medium — largest mock data change; must match the init parameter list exactly.

---

### Phase 2: Scoring Service

#### Step 2.1 — Create `CircadianService`

**File**: `WellPlate/Core/Services/CircadianService.swift` (NEW)

**Action**: Create a stateless enum mirroring `StressScoring`:

```swift
import Foundation

enum CircadianService {

    // MARK: - Composite Score

    struct CircadianResult {
        let score: Int              // 0–100
        let regularityScore: Int    // 0–100 (SRI sub-score)
        let daylightScore: Int?     // 0–100 (nil if no Watch data)
        let tip: String
        let hasEnoughData: Bool     // false if < 5 nights
    }

    static func compute(
        sleepSummaries: [DailySleepSummary],
        daylightSamples: [DailyMetricSample]
    ) -> CircadianResult {
        // ... implementation
    }

    // MARK: - Sleep Regularity Index

    /// Compute SRI from last 7 days of sleep summaries.
    /// Requires ≥ 5 nights with valid bedtime data.
    /// Returns 0–100 where 100 = perfectly regular.
    static func sleepRegularityIndex(from summaries: [DailySleepSummary]) -> (score: Int, hasEnoughData: Bool) {
        // Filter to last 7 days with non-nil bedtime
        // Convert bedtime to minutes-past-6pm (handles midnight crossing)
        // Compute stdDev of bedtime minutes + stdDev of wake minutes
        // Average the two SDs → combined SD
        // Score: max(0, 100 * (1 - combinedSD / 75.0))
        // hasEnoughData = validNights >= 5
    }

    // MARK: - Daylight Score

    /// Score from daily daylight exposure over last 7 days.
    /// Returns 0–100 where 100 = ≥30 min/day average. Nil if no samples.
    static func daylightScore(from samples: [DailyMetricSample]) -> Int? {
        // Filter to last 7 days
        // Average minutes/day
        // Score: min(100, Int(avgMinutes / 30.0 * 100))
        // Return nil if samples is empty
    }

    // MARK: - Tip Selection

    /// Pick the most actionable tip based on lowest sub-score.
    static func selectTip(regularityScore: Int, daylightScore: Int?) -> String {
        // If regularity is weakest: "Try going to bed within 30 min of your usual time"
        // If daylight is weakest: "10 min of outdoor light before noon helps set your clock"
        // If no daylight data: "Consistent bed and wake times help your body recover"
        // If both good: "Great circadian rhythm — keep it up!"
    }
}
```

**Why**: Stateless enum with pure functions follows `StressScoring` pattern. Takes pre-fetched data, returns a result struct. Testable, no side effects.

**Key implementation detail — midnight crossing for bedtime**:
```swift
// Convert bedtime to minutes past 6pm anchor (avoids midnight discontinuity)
// 6pm = 0, 11pm = 300, midnight = 360, 2am = 480
func minutesPast6PM(_ date: Date) -> Double {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: date)
    let min = cal.component(.minute, from: date)
    let totalMin = Double(hour * 60 + min)
    // Shift: 18:00 = 0
    let shifted = totalMin - (18 * 60)
    return shifted >= 0 ? shifted : shifted + (24 * 60)
}
```

**Dependencies**: Step 1.1 (needs bedtime/wakeTime on `DailySleepSummary`)
**Risk**: Low — pure math, no framework dependencies.

---

### Phase 3: ViewModel Integration

#### Step 3.1 — Add circadian properties and fetch to `StressViewModel`

**File**: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`

**Action A**: Add published properties (after the 30-day histories, ~line 53):

```swift
// MARK: - Circadian
@Published var circadianResult: CircadianService.CircadianResult = CircadianService.CircadianResult(
    score: 0, regularityScore: 0, daylightScore: nil, tip: "", hasEnoughData: false
)
@Published var daylightHistory: [DailyMetricSample] = []
```

**Action B**: Add safe fetch helper (after `fetchRRHistorySafely`, ~line 522):

```swift
private func fetchDaylightHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
    (try? await healthService.fetchDaylight(for: range)) ?? []
}
```

**Action C**: In `loadData()`, after the 30-day history `async let` block (~line 268–276), add:

```swift
async let daylightHist = fetchDaylightHistorySafely(range: thirtyDayRange)
```

**Action D**: After the history assignments (~line 286), add:

```swift
daylightHistory = await daylightHist
```

**Action E**: After the today's vitals extraction (~line 294), compute circadian:

```swift
// Compute Circadian Score from last 7 days of sleep + daylight
let sevenDayStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
let recentSleep = sleepHistory.filter { $0.date >= sevenDayStart }
let recentDaylight = daylightHistory.filter { $0.date >= sevenDayStart }
circadianResult = CircadianService.compute(sleepSummaries: recentSleep, daylightSamples: recentDaylight)
```

**Why**: Follows the established pattern — `async let` for parallel fetch, safe wrapper, compute after assignment. Using the 30-day range for fetching but filtering to 7 days for scoring (so detail view can show full history).

**Dependencies**: Steps 1.3–1.5 (fetchDaylight), Step 2.1 (CircadianService)
**Risk**: Low — additive code in existing method.

---

### Phase 4: UI

#### Step 4.1 — Create `CircadianCardView`

**File**: `WellPlate/Features + UI/Stress/Views/CircadianCardView.swift` (NEW)

**Action**: Self-contained SwiftUI view. Takes `CircadianService.CircadianResult` and an `onTap` closure.

Layout:
```
┌─────────────────────────────────────┐
│  🌅  CIRCADIAN HEALTH       chevron │
│                                     │
│  Score: 78 / 100                    │
│  ┌──────────┐  ┌──────────┐        │
│  │ Regularity│  │ Daylight │        │
│  │    82     │  │    74    │        │
│  └──────────┘  └──────────┘        │
│                                     │
│  💡 "10 min of outdoor light..."   │
└─────────────────────────────────────┘
```

States:
- **Normal**: Shows score + sub-scores + tip
- **No Watch**: Shows regularity score only + "Add Apple Watch for daylight data" note in place of daylight sub-card
- **Not enough data**: Shows "Need 5+ nights of sleep data" placeholder

**Design**: Use existing card styling pattern — `RoundedRectangle(cornerRadius: 24, style: .continuous)` + `.fill(Color(.systemBackground).opacity(0.85))` + shadow. Match `factorGridCard` styling from StressView (lines 640–688).

**Dependencies**: Step 2.1 (CircadianResult)
**Risk**: Low — self-contained view.

---

#### Step 4.2 — Create `CircadianDetailView`

**File**: `WellPlate/Features + UI/Stress/Views/CircadianDetailView.swift` (NEW)

**Action**: Detail sheet following the pattern of `ExerciseDetailView` / `SleepDetailView`. Receives data arrays and result.

Parameters:
```swift
struct CircadianDetailView: View {
    let result: CircadianService.CircadianResult
    let sleepSummaries: [DailySleepSummary]   // 30-day for charts
    let daylightSamples: [DailyMetricSample]  // 30-day for charts
}
```

Sections:
1. **Score Summary** — big score number + level label (Good/Fair/Poor)
2. **Sleep Regularity Chart** — 7-day horizontal bar chart showing bedtime→wake time per night (like a Gantt chart). Each bar starts at bedtime, ends at wake time. Shows variance visually.
3. **Daylight Exposure Chart** — 7-day vertical bar chart of minutes/day. Target line at 30 min. (Hidden section if no Watch data)
4. **Tips** — 2-3 contextual tips based on scores

Use Swift Charts (`Chart` with `BarMark`) for both charts — same framework used in `SleepChartView`, `BurnChartView`.

**Dependencies**: Steps 2.1, 4.1
**Risk**: Medium — chart design requires iteration. Keep charts simple for MVP (bar marks only, no custom layouts).

---

#### Step 4.3 — Wire into `StressView`

**File**: `WellPlate/Features + UI/Stress/Views/StressView.swift`

**Action A**: Add `.circadian` case to `StressSheet` enum (line 12–33):

```swift
enum StressSheet: Identifiable {
    // ... existing cases ...
    case circadian   // NEW

    var id: String {
        switch self {
        // ... existing cases ...
        case .circadian: return "circadian"
        }
    }
}
```

**Action B**: Add `CircadianDetailView` to the `.sheet(item:)` switch (line 150–184):

```swift
case .circadian:
    CircadianDetailView(
        result: viewModel.circadianResult,
        sleepSummaries: viewModel.sleepHistory,
        daylightSamples: viewModel.daylightHistory
    )
```

**Action C**: Add `CircadianCardView` to `insightsSheet` (line 548–591). Place it between the Stress Factors section and the 7-Day Trend section:

```swift
// Vitals Grid
vitalsGridSection
    .padding(.horizontal, 16)
    .padding(.top, 20)

// Stress Factors
factorsSection
    .padding(.horizontal, 16)
    .padding(.top, 28)

// Circadian Health — NEW
VStack(alignment: .leading, spacing: 12) {
    sectionLabel("CIRCADIAN HEALTH")
    CircadianCardView(result: viewModel.circadianResult) {
        activeSheet = .circadian
        showInsights = false
    }
}
.padding(.horizontal, 16)
.padding(.top, 28)

// 7-Day Trend
// ... existing code ...
```

**Why**: Placing after factors and before trend charts positions Circadian as a peer to the stress factor cards — visible but not displacing existing content. `showInsights = false` dismisses the insights sheet before presenting the detail sheet (same pattern as factor cards).

**Dependencies**: Steps 3.1, 4.1, 4.2
**Risk**: Low — follows existing sheet wiring pattern exactly.

---

### Phase 5: Build Verification

#### Step 5.1 — Build all targets

**Action**: Run all 4 build commands:

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Dependencies**: All previous steps
**Risk**: Low–Medium — most likely issues: init parameter mismatches on `DailySleepSummary` call sites, or missing protocol conformance.

#### Step 5.2 — Fix any build errors

If builds fail, fix errors iteratively. Most likely issues:
- `DailySleepSummary` init call sites missing `bedtime`/`wakeTime` parameters
- `StressImmersiveView` if it references `StressSheet` cases
- Mock data mismatches

---

## Testing Strategy

### Build verification
- All 4 targets must compile cleanly

### Manual verification (mock mode)
1. Enable mock mode in AppConfig
2. Open Stress tab → tap Insights (chart icon)
3. Verify Circadian Health card appears between Stress Factors and 7-Day Trend
4. Verify card shows score, regularity sub-score, daylight sub-score, tip
5. Tap card → CircadianDetailView opens with charts
6. Verify dismiss closes detail sheet

### Manual verification (real device with HealthKit)
1. Disable mock mode
2. Verify Circadian card shows with real sleep data
3. If Apple Watch paired: verify daylight score appears
4. If no Apple Watch: verify graceful degradation (regularity only + note)
5. With < 5 nights data: verify "Not enough data" state

### Edge cases to verify
- Mock mode: all values populated, card fully rendered
- No sleep data: card shows "Not enough data"
- 5 nights exactly: card shows valid score
- No daylight data: card shows regularity only, no crash

---

## Risks & Mitigations

- **Risk**: `DailySleepSummary` init changes break existing call sites
  - Mitigation: Use default parameter values (`bedtime: Date? = nil, wakeTime: Date? = nil`). But since Swift structs have memberwise inits, we need to audit every construction site. Known sites: `HealthKitService.fetchDailySleepSummaries`, `StressMockSnapshot.makeDefault`. Both are modified in this plan.

- **Risk**: `timeInDaylight` authorization prompt surprises users
  - Mitigation: It's added to the existing `readTypes` set. HealthKit shows one combined permission dialog — adding a new type doesn't create a second prompt. Existing users who already granted permission may see a subtle "Updated" indicator in Health settings, but no modal.

- **Risk**: Charts in CircadianDetailView are complex
  - Mitigation: Keep MVP charts to simple `BarMark` visualizations. If chart implementation takes >1 day, ship card-only first and add detail view in follow-up.

- **Risk**: Sleep sample timestamps may be noisy (Watch removed mid-night)
  - Mitigation: The ≥ 3h total threshold for bedtime/wakeTime (Step 1.2) filters out noise from short naps. The ≥ 5-of-7-nights requirement (Step 2.1) ensures the SRI isn't skewed by sparse data.

---

## Success Criteria

- [ ] All 4 build targets compile without errors
- [ ] Circadian Health card visible in insights sheet (mock mode)
- [ ] Card shows composite score, regularity sub-score, daylight sub-score, tip
- [ ] Tapping card opens CircadianDetailView with charts
- [ ] Graceful degradation when no daylight data (regularity-only score + note)
- [ ] "Not enough data" state when < 5 nights available
- [ ] No changes to composite stress score (totalScore unchanged)
- [ ] Mock mode fully functional with deterministic circadian data
