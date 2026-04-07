# Implementation Plan: F3. Circadian Stack (RESOLVED)

**Date**: 2026-04-07
**Source**: `Docs/02_Planning/Specs/260407-circadian-stack-strategy.md`
**Status**: Ready for Checklist
**Audit**: `Docs/03_Audits/260407-circadian-stack-plan-audit.md`

---

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|---|---|---|---|
| C1 | CRITICAL | `DailySleepSummary` memberwise init breaks 4 call sites | Fixed: declare `= nil` defaults; all existing call sites unchanged |
| H1 | HIGH | Missing `StressMockSnapshot.sleepToday` update | Resolved by C1: default values make this backward-compatible. Added explicit mock bedtime/wakeTime for `sleepToday` anyway. |
| H2 | HIGH | Missing `SleepStageBarView` #Preview update | Resolved by C1: default values make preview backward-compatible |
| H3 | HIGH | `CircadianResult` uses `Int` — codebase uses `Double` | Fixed: changed all score fields to `Double` |
| H4 | HIGH | `timeInDaylight` unit needs verification | Fixed: added verification note + testing step |
| M1 | MEDIUM | SRI should weight wake time more heavily | Fixed: changed to 60/40 wake:bed weighting |
| M2 | MEDIUM | No accessibility plan | Acknowledged: added note to match existing pattern |
| M3 | MEDIUM | HealthKit denial handling unclear | Fixed: added explicit clarification |
| M4 | MEDIUM | Sheet animation timing risk | Acknowledged: same pattern as existing factor cards |
| L1 | LOW | No circadian level labels | Fixed: added `CircadianLevel` enum |
| L2 | LOW | Chart colors unspecified | Acknowledged: deferred to implementation |
| L3 | LOW | 30-day over-fetch | No issue — by design |

---

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
| Model extension | `HealthModels.swift` | Add `bedtime: Date? = nil` and `wakeTime: Date? = nil` to `DailySleepSummary` |
| New HK fetch | `HealthKitService.swift` | Add `.timeInDaylight` to `readTypes`; add `fetchDaylight(for:)` method |
| Protocol update | `HealthKitServiceProtocol.swift` | Add `fetchDaylight(for:)` |
| Mock update | `MockHealthKitService.swift` | Implement `fetchDaylight(for:)` |
| Mock data | `StressMockSnapshot.swift` | Add `daylightHistory` array; update sleep summaries with bedtime/wakeTime |
| New service | `CircadianService.swift` (new) | Stateless enum: SRI computation, daylight scoring, composite score, tip selection |
| VM integration | `StressViewModel.swift` | Add circadian published properties; fetch daylight; call `CircadianService` |
| Card view | `CircadianCardView.swift` (new) | Score display card with sub-scores and tip |
| Detail view | `CircadianDetailView.swift` (new) | 7-day regularity chart + daylight bars + tips |
| Sheet wiring | `StressView.swift` | Add `.circadian` to `StressSheet`; add card to insights sheet; wire detail sheet |

### Complete call-site audit for `DailySleepSummary` init

<!-- RESOLVED: C1 — exhaustive list of all DailySleepSummary construction sites -->

| # | File | Line | Action needed |
|---|---|---|---|
| 1 | `HealthKitService.swift` | 168 | Pass explicit `bedtime:` / `wakeTime:` (Step 1.2) |
| 2 | `StressMockSnapshot.swift` | 63 | `sleepToday` — backward-compatible via `= nil` defaults; optionally pass mock values (Step 1.6) |
| 3 | `StressMockSnapshot.swift` | 157 | 30-day history loop — pass computed bedtime/wakeTime (Step 1.6) |
| 4 | `SleepStageBarView.swift` | 62 | #Preview — backward-compatible via `= nil` defaults; no change needed |

---

## Implementation Steps

### Phase 1: Data Layer (models + HealthKit)

#### Step 1.1 — Extend `DailySleepSummary` with bedtime/wakeTime

**File**: `WellPlate/Models/HealthModels.swift`

<!-- RESOLVED: C1 — declare with `= nil` defaults to preserve backward compatibility -->

**Action**: Add two optional properties with default values to `DailySleepSummary`:

```swift
struct DailySleepSummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalHours: Double
    let coreHours: Double
    let remHours: Double
    let deepHours: Double
    let bedtime: Date? = nil      // NEW: earliest sleep sample startDate in session
    let wakeTime: Date? = nil     // NEW: latest sleep sample endDate in session
    // existing computed properties unchanged
}
```

**Why**: SRI requires bedtime and wake time per night. Using `= nil` defaults ensures the Swift memberwise init retains backward compatibility — all 4 existing call sites compile without modification. Only `HealthKitService.fetchDailySleepSummaries` and `StressMockSnapshot.makeDefault` need to explicitly pass values.

**Affected call sites** (all backward-compatible, no forced changes):
- `HealthKitService.swift:168` — will pass explicit values (Step 1.2)
- `StressMockSnapshot.swift:63` (`sleepToday`) — will pass mock values (Step 1.6)
- `StressMockSnapshot.swift:157` (30-day loop) — will pass computed values (Step 1.6)
- `SleepStageBarView.swift:62` (#Preview) — no change needed, uses defaults

**Dependencies**: None
**Risk**: Low — additive change with defaults; zero breaking changes.

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

<!-- RESOLVED: H4 — added unit verification note -->

**Why**: `timeInDaylight` is a cumulative quantity (total minutes per day), so use `fetchDailySum` (not `fetchDailyAvg`). HealthKit stores time quantities internally and `doubleValue(for: .minute())` auto-converts to minutes regardless of internal storage unit.

**Unit verification**: After implementation, verify on a real Watch-paired device that returned values are in a reasonable range (5–120 minutes/day). If values are 60x too large, the data is in seconds and `.second()` should be used instead. Add a `#if DEBUG` log: `log("☀️ Daylight: \(samples.count) days, latest=\(samples.last?.value ?? 0) min")`.

<!-- RESOLVED: M3 — clarified zero-sample behavior -->

**Zero samples behavior**: Zero daylight samples can mean (a) no Apple Watch, (b) user denied HealthKit daylight authorization, or (c) genuinely zero daylight recorded. All three degrade identically to regularity-only mode. No distinction is made or shown to the user — this is intentional.

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

<!-- RESOLVED: H1 — explicitly covers sleepToday + 30-day history -->

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

**Action C**: Add bedtime hour array and update 30-day sleep history loop:

```swift
let bedtimeHours: [Double] = [
    23.0, 23.3, 22.8, 23.5, 22.5, 23.1, 23.2,
    22.9, 23.4, 23.0, 22.6, 23.3, 23.1, 23.5,
    22.7, 23.0, 23.4, 22.8, 23.2, 23.6,
    23.0, 22.9, 23.3, 22.4, 23.1, 23.0, 23.5,
    22.8, 23.2, 23.0
]
let sleepHist: [DailySleepSummary] = (0..<count).map { i in
    let total = sleepTotals[i]
    let deep  = total * deepRatios[i]
    let rem   = total * remRatios[i]
    let core  = max(0, total - deep - rem)
    // Compute mock bedtime/wakeTime
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

**Action D**: Update `sleepToday` to include bedtime/wakeTime:

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

**Action E**: Add `daylightHistory: daylightHist` to the `StressMockSnapshot(...)` constructor call.

**Dependencies**: Steps 1.1 (bedtime/wakeTime fields), 1.5 (mock service reads daylightHistory)
**Risk**: Medium — largest mock data change; must match the init parameter list exactly.

---

### Phase 2: Scoring Service

#### Step 2.1 — Create `CircadianService`

**File**: `WellPlate/Core/Services/CircadianService.swift` (NEW)

**Action**: Create a stateless enum mirroring `StressScoring`:

<!-- RESOLVED: H3 — all score fields use Double to match codebase convention -->
<!-- RESOLVED: L1 — added CircadianLevel enum for quality labels -->
<!-- RESOLVED: M1 — SRI uses 60/40 wake:bed weighting -->

```swift
import Foundation

enum CircadianService {

    // MARK: - Level Labels

    enum CircadianLevel: String {
        case aligned   = "Aligned"
        case adjusting = "Adjusting"
        case disrupted = "Disrupted"

        init(score: Double) {
            switch score {
            case 70...:  self = .aligned
            case 40..<70: self = .adjusting
            default:      self = .disrupted
            }
        }

        var color: String {  // semantic color name for views
            switch self {
            case .aligned:   return "green"
            case .adjusting: return "orange"
            case .disrupted: return "red"
            }
        }
    }

    // MARK: - Composite Result

    struct CircadianResult {
        let score: Double              // 0–100
        let regularityScore: Double    // 0–100 (SRI sub-score)
        let daylightScore: Double?     // 0–100 (nil if no Watch data)
        let level: CircadianLevel
        let tip: String
        let hasEnoughData: Bool        // false if < 5 nights
    }

    // MARK: - Compute

    static func compute(
        sleepSummaries: [DailySleepSummary],
        daylightSamples: [DailyMetricSample]
    ) -> CircadianResult {
        let (regScore, hasData) = sleepRegularityIndex(from: sleepSummaries)
        let dayScore = daylightScore(from: daylightSamples)

        let composite: Double
        if let ds = dayScore {
            composite = regScore * 0.5 + ds * 0.5
        } else {
            composite = regScore  // SRI alone, renormalized
        }

        let tip = selectTip(regularityScore: regScore, daylightScore: dayScore)
        let level = CircadianLevel(score: hasData ? composite : 0)

        return CircadianResult(
            score: hasData ? composite : 0,
            regularityScore: regScore,
            daylightScore: dayScore,
            level: level,
            tip: tip,
            hasEnoughData: hasData
        )
    }

    // MARK: - Sleep Regularity Index

    /// Compute SRI from last 7 days of sleep summaries.
    /// Requires ≥ 5 nights with valid bedtime data.
    /// Returns 0–100 where 100 = perfectly regular.
    static func sleepRegularityIndex(from summaries: [DailySleepSummary]) -> (score: Double, hasEnoughData: Bool) {
        let validNights = summaries.filter { $0.bedtime != nil && $0.wakeTime != nil }
        guard validNights.count >= 5 else { return (0, false) }

        let bedtimeMinutes = validNights.compactMap { $0.bedtime.map { minutesPast6PM($0) } }
        let wakeMinutes = validNights.compactMap { $0.wakeTime.map { minutesPast6PM($0) } }

        let bedSD = standardDeviation(bedtimeMinutes)
        let wakeSD = standardDeviation(wakeMinutes)

        // Wake time weighted 60%, bedtime 40% (wake consistency more important for entrainment)
        let combinedSD = wakeSD * 0.6 + bedSD * 0.4
        let score = max(0, 100.0 * (1.0 - combinedSD / 75.0))

        return (min(100, score), true)
    }

    // MARK: - Daylight Score

    /// Score from daily daylight exposure over last 7 days.
    /// Returns 0–100 where 100 = ≥30 min/day average. Nil if no samples.
    static func daylightScore(from samples: [DailyMetricSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let avg = samples.map(\.value).reduce(0, +) / Double(samples.count)
        return min(100, avg / 30.0 * 100.0)
    }

    // MARK: - Tip Selection

    /// Pick the most actionable tip based on lowest sub-score.
    static func selectTip(regularityScore: Double, daylightScore: Double?) -> String {
        if let ds = daylightScore {
            if regularityScore <= ds {
                return "Try going to bed within 30 min of your usual time"
            } else {
                return "10 min of outdoor light before noon helps set your clock"
            }
        }
        // No daylight data
        if regularityScore >= 70 {
            return "Great sleep rhythm — keep it up!"
        }
        return "Consistent bed and wake times help your body recover"
    }

    // MARK: - Helpers

    /// Convert a Date to minutes past 6 PM (handles midnight crossing).
    /// 6 PM = 0, 11 PM = 300, midnight = 360, 2 AM = 480.
    private static func minutesPast6PM(_ date: Date) -> Double {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let min = cal.component(.minute, from: date)
        let totalMin = Double(hour * 60 + min)
        let shifted = totalMin - (18 * 60)
        return shifted >= 0 ? shifted : shifted + (24 * 60)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
```

**Why**: Stateless enum with pure functions follows `StressScoring` pattern. Takes pre-fetched data, returns a result struct. Testable, no side effects. `CircadianLevel` enum provides human-readable labels matching the UX pattern of `StressLevel` and `SleepQuality`.

**Dependencies**: Step 1.1 (needs bedtime/wakeTime on `DailySleepSummary`)
**Risk**: Low — pure math, no framework dependencies.

---

### Phase 3: ViewModel Integration

#### Step 3.1 — Add circadian properties and fetch to `StressViewModel`

**File**: `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`

<!-- RESOLVED: H3 — CircadianResult fields are now Double -->

**Action A**: Add published properties (after the 30-day histories, ~line 53):

```swift
// MARK: - Circadian
@Published var circadianResult: CircadianService.CircadianResult = CircadianService.CircadianResult(
    score: 0, regularityScore: 0, daylightScore: nil, level: .disrupted, tip: "", hasEnoughData: false
)
@Published var daylightHistory: [DailyMetricSample] = []
```

**Action B**: Add safe fetch helper (after `fetchRRHistorySafely`, ~line 522):

```swift
private func fetchDaylightHistorySafely(range: DateInterval) async -> [DailyMetricSample] {
    (try? await healthService.fetchDaylight(for: range)) ?? []
}
```

**Action C**: In `loadData()`, after the 30-day history `async let` block (~line 268–276), add daylight to the parallel fetch:

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

#if DEBUG
log("🌅 Circadian → score=\(fmt2(circadianResult.score))  regularity=\(fmt2(circadianResult.regularityScore))  daylight=\(circadianResult.daylightScore.map { fmt2($0) } ?? "nil")  level=\(circadianResult.level.rawValue)  hasData=\(circadianResult.hasEnoughData)")
#endif
```

**Why**: Follows the established pattern — `async let` for parallel fetch, safe wrapper, compute after assignment. Using the 30-day range for fetching but filtering to 7 days for scoring (so detail view can show full history). Debug logging matches the existing factor logging format.

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
│  ☀️  CIRCADIAN HEALTH       chevron │
│                                     │
│  Score: 78 / 100    "Aligned"       │
│  ┌──────────┐  ┌──────────┐        │
│  │ Regularity│  │ Daylight │        │
│  │    82     │  │    74    │        │
│  └──────────┘  └──────────┘        │
│                                     │
│  "10 min of outdoor light..."       │
└─────────────────────────────────────┘
```

States:
- **Normal**: Shows score + level label + sub-scores + tip
- **No Watch**: Shows regularity score only + "Add Apple Watch for daylight data" note in place of daylight sub-card
- **Not enough data**: Shows "Need 5+ nights of sleep data" placeholder

**Design**: Use existing card styling pattern — `RoundedRectangle(cornerRadius: 24, style: .continuous)` + `.fill(Color(.systemBackground).opacity(0.85))` + shadow. Match `factorGridCard` styling from StressView (lines 640–688).

<!-- RESOLVED: M2 — follow existing accessibility pattern -->
**Accessibility**: Match VoiceOver labeling pattern of existing `StressFactorCardView` — add `.accessibilityElement(children: .combine)` and an `.accessibilityLabel` summarizing the score and level.

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
1. **Score Summary** — big score number + `CircadianLevel` label (Aligned/Adjusting/Disrupted) with semantic color
2. **Sleep Regularity Chart** — 7-day horizontal bar chart showing bedtime→wake time per night (like a Gantt chart). Each bar starts at bedtime, ends at wake time. Shows variance visually.
3. **Daylight Exposure Chart** — 7-day vertical bar chart of minutes/day. Target line at 30 min. (Hidden section if no Watch data)
4. **Tips** — 2-3 contextual tips based on scores

Use Swift Charts (`Chart` with `BarMark`) for both charts — same framework used in `SleepChartView`, `BurnChartView`.

<!-- RESOLVED: L2 — chart color guidance -->
**Chart colors**: Use sleep-adjacent tones for regularity (indigo/purple family matching `SleepStage.deep.color`) and warm amber/gold for daylight. Exact values to be determined during implementation; follow `AppColors` convention.

<!-- RESOLVED: M2 — accessibility note -->
**Accessibility**: Add `.accessibilityLabel` to chart marks and ensure VoiceOver can describe trends.

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

<!-- RESOLVED: M4 — acknowledged sheet animation pattern -->
**Sheet transition note**: `showInsights = false` + `activeSheet = .circadian` follows the same pattern as existing factor cards (e.g., `activeSheet = .exercise; showInsights = false`). If transition is janky during testing, wrap `activeSheet` assignment in `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)`.

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
**Risk**: Low — the `= nil` defaults (C1 fix) eliminate the most likely build failure mode.

#### Step 5.2 — Fix any build errors

If builds fail, fix errors iteratively. Most likely issues:
- Missing `StressSheet.circadian` case in any exhaustive switch
- `StressMockSnapshot` init parameter list mismatch
- Protocol conformance for `fetchDaylight`

<!-- RESOLVED: H4 — daylight unit verification step -->

#### Step 5.3 — Verify `timeInDaylight` unit on real device

**Action**: On a Watch-paired device, run the app in debug mode and check console for:
```
☀️ Daylight: X days, latest=Y min
```
Verify `Y` is in a reasonable range (5–120 min). If values are ~60x expected, change `.minute()` to `.second()` and divide by 60.

---

## Testing Strategy

### Build verification
- All 4 targets must compile cleanly

### Manual verification (mock mode)
1. Enable mock mode in AppConfig
2. Open Stress tab → tap Insights (chart icon)
3. Verify Circadian Health card appears between Stress Factors and 7-Day Trend
4. Verify card shows score, level label (Aligned/Adjusting/Disrupted), regularity sub-score, daylight sub-score, tip
5. Tap card → CircadianDetailView opens with charts
6. Verify dismiss closes detail sheet

### Manual verification (real device with HealthKit)
1. Disable mock mode
2. Verify Circadian card shows with real sleep data
3. If Apple Watch paired: verify daylight score appears and values are reasonable
4. If no Apple Watch: verify graceful degradation (regularity only + note)
5. With < 5 nights data: verify "Not enough data" state

### Edge cases to verify
- Mock mode: all values populated, card fully rendered
- No sleep data: card shows "Not enough data"
- 5 nights exactly: card shows valid score
- No daylight data: card shows regularity only, no crash
- `timeInDaylight` values sanity check on real device (Step 5.3)

---

## Risks & Mitigations

- **Risk**: `DailySleepSummary` init changes break existing call sites
  - Mitigation: Properties declared with `= nil` defaults — all 4 existing call sites are backward-compatible (C1 fix). Only `HealthKitService` and `StressMockSnapshot` pass explicit values.

- **Risk**: `timeInDaylight` authorization prompt surprises users
  - Mitigation: It's added to the existing `readTypes` set. HealthKit shows one combined permission dialog — adding a new type doesn't create a second prompt.

- **Risk**: `timeInDaylight` unit mismatch
  - Mitigation: Step 5.3 verification on real device + DEBUG logging.

- **Risk**: Charts in CircadianDetailView are complex
  - Mitigation: Keep MVP charts to simple `BarMark` visualizations. If chart implementation takes >1 day, ship card-only first and add detail view in follow-up.

- **Risk**: Sleep sample timestamps may be noisy (Watch removed mid-night)
  - Mitigation: The ≥ 3h total threshold for bedtime/wakeTime (Step 1.2) filters out noise from short naps. The ≥ 5-of-7-nights requirement (Step 2.1) ensures the SRI isn't skewed by sparse data.

---

## Success Criteria

- [ ] All 4 build targets compile without errors
- [ ] Circadian Health card visible in insights sheet (mock mode)
- [ ] Card shows composite score, level label, regularity sub-score, daylight sub-score, tip
- [ ] Tapping card opens CircadianDetailView with charts
- [ ] Graceful degradation when no daylight data (regularity-only score + note)
- [ ] "Not enough data" state when < 5 nights available
- [ ] No changes to composite stress score (totalScore unchanged)
- [ ] Mock mode fully functional with deterministic circadian data
- [ ] `timeInDaylight` values verified on real Watch-paired device (Step 5.3)
