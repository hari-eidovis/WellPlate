# Implementation Plan: Stress Sparkline Strip (Home Screen)

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|----|----------|-------|------------|
| C1 | CRITICAL | ForEach with tuple won't compile | Replaced with private `IntradayPoint: Identifiable` struct |
| H1 | HIGH | Missing `import Charts` | Added `import SwiftUI`, `import SwiftData`, `import Charts` |
| H2 | HIGH | Undefined `emojiFor()` helper | Removed fallback; simplified to switch-only |
| M1 | MEDIUM | Single reading = blank chart | Treat `readings.count < 2` as empty state |
| M2 | MEDIUM | Fragile placeholder framing | Replaced with centered VStack layout |
| L1 | LOW | @Query loads all history | Acceptable for v1; noted for future optimization |
| L2 | LOW | No animation on appear | Added trim-based line-drawing animation |

---

## Overview

Add a compact, tappable `StressSparklineStrip` card between the Wellness Rings card and
the Mood Check-In section in `HomeView`. The card shows today's intraday stress trajectory
as a Swift Charts line+area chart, a current score badge, a delta vs. yesterday, and an
auto-detected annotation for the day's most significant inflection point.

Data flows entirely through SwiftData: `StressViewModel` already persists `StressReading`
rows via `logCurrentStress()`, so `HomeView` only needs a new `@Query` to read them reactively.

---

## Requirements

- Compact card: standard card chrome (cornerRadius 24, systemBackground, appShadow), ~110 pt tall total
- Header row: "Stress today" label (left) + emoji + level label + score (right)
- Delta badge in the header: "↑ +8" (worse, red-tinted) / "↓ -12" (better, green-tinted) vs. yesterday's last reading
- Intraday line+area sparkline chart (~52 pt tall) spanning 6 AM to now
  - X-axis: hidden — clean sparkline look
  - Y-axis: hidden, implicit range 0-100
  - `catmullRom` interpolation for smooth curves
  - Line color: `StressLevel(score:).color` of the latest reading (or `.secondary` when empty)
  - Area fill: same color at 0.20-0.0 opacity gradient (top to bottom)
  - Line-drawing trim animation on appear (spring response 1.0, dampingFraction 0.75)
- Annotation row below the chart: auto-detected inflection label, e.g.
  "Morning workout helped ↓12 pts" / "Post-lunch spike ↑9 pts"
  — shows only when the largest delta between consecutive readings is >= 8 pts
- Empty / loading state when fewer than 2 readings exist today: centered dashed line + "No stress data yet" caption
<!-- RESOLVED: M1 — treat readings.count < 2 as empty state per user decision -->
- Tapping anywhere navigates to the Stress tab (`selectedTab = 1`) with a `.medium` haptic

---

## Architecture Changes

| What | File |
|------|------|
| **New component** — `StressSparklineStrip` | `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift` |
| **HomeView** — add `@Query`, computed properties, and the strip insertion | `WellPlate/Features + UI/Home/Views/HomeView.swift` |

No new SwiftData models, no ViewModel changes, no pbxproj edits needed.

---

## Implementation Steps

### Phase 1 — Data Plumbing in HomeView

**Step 1 — Add `@Query` for StressReadings** (`HomeView.swift`, after existing `@Query` declarations)

```swift
@Query(sort: \StressReading.timestamp) private var allStressReadings: [StressReading]
```

<!-- RESOLVED: L1 — acceptable for v1; StressReading rows are tiny (~40 bytes each), even 1000 rows = 40 KB. Future optimization: date-bounded FetchDescriptor if profiling shows overhead. -->

- Action: insert after line 30 (`@Query private var allJournalEntries: [JournalEntry]`)
- Why: Follows the existing pattern — `allWellnessDayLogs` is also queried without a
  predicate and filtered in code. `StressReading` accumulates at most a handful of entries
  per day so a full-table scan is negligible.
- Dependencies: none
- Risk: Low — read-only query, no mutations

**Step 2 — Add three computed helpers** (`HomeView.swift`, private section after `todayWellnessLog`)

```swift
/// StressReadings recorded today, in chronological order.
private var todayStressReadings: [StressReading] {
    allStressReadings.filter { Calendar.current.isDateInToday($0.timestamp) }
}

/// Last StressReading from yesterday — used for the delta badge.
private var yesterdayLastStressReading: StressReading? {
    allStressReadings.last { Calendar.current.isDateInYesterday($0.timestamp) }
}

/// Score delta vs. yesterday's last reading. Nil when insufficient data.
private var stressScoreDelta: Int? {
    guard let today = todayStressReadings.last,
          let yesterday = yesterdayLastStressReading else { return nil }
    let delta = Int(today.score.rounded()) - Int(yesterday.score.rounded())
    return delta == 0 ? nil : delta
}
```

- Action: add below `todayWellnessLog` computed property (~line 424)
- Why: Separates query result filtering from the component — keeps `StressSparklineStrip`
  purely presentational (no SwiftData dependency)
- Risk: Low

---

### Phase 2 — StressSparklineStrip Component

**Step 3 — Create `StressSparklineStrip.swift`**

```
WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift
```

<!-- RESOLVED: H1 — explicit import declarations -->
**3a. Imports**

```swift
import SwiftUI
import SwiftData
import Charts
```

**3b. Struct signature & inputs**

```swift
struct StressSparklineStrip: View {
    let readings: [StressReading]    // today's readings, sorted ascending
    let stressLevel: String?         // from WellnessDayLog (e.g. "Good")
    let scoreDelta: Int?             // vs yesterday, nil if unknown
    var onTap: () -> Void
}
```

<!-- RESOLVED: C1 — private Identifiable struct replacing raw tuple -->
**3c. Private chart data struct**

```swift
private struct IntradayPoint: Identifiable {
    let id: Int
    let timestamp: Date
    let score: Double
}

private var chartPoints: [IntradayPoint] {
    readings.enumerated().map {
        IntradayPoint(id: $0.offset, timestamp: $0.element.timestamp, score: $0.element.score)
    }
}
```

**3d. Private helpers (inside the struct)**

```swift
// The most recent score (or nil)
private var latestScore: Double? { readings.last?.score }

// StressLevel enum for color
private var latestLevel: StressLevel? {
    latestScore.map { StressLevel(score: $0) }
}
```

<!-- RESOLVED: H2 — removed emojiFor() reference; simplified to switch-only -->
```swift
// Emoji from stressLevel string
private var emoji: String {
    switch stressLevel?.lowercased() {
    case "excellent": return "😄"
    case "good":      return "😌"
    case "moderate":  return "😐"
    case "high":      return "😣"
    case "very high": return "😰"
    default:          return "—"
    }
}
```

```swift
// Line/area color
private var accentColor: Color {
    latestLevel?.color ?? Color(.systemGray3)
}

// Auto-annotation: finds the pair of consecutive readings with the largest
// absolute delta, returns a caption only when |delta| >= 8.
private var inflectionAnnotation: String? {
    guard readings.count >= 2 else { return nil }
    var maxDelta: Double = 0
    var maxIdx = 1
    for i in 1..<readings.count {
        let delta = readings[i].score - readings[i - 1].score
        if abs(delta) > abs(maxDelta) {
            maxDelta = delta
            maxIdx = i
        }
    }
    guard abs(maxDelta) >= 8 else { return nil }
    let pts = Int(abs(maxDelta).rounded())
    let hour = Calendar.current.component(.hour, from: readings[maxIdx].timestamp)
    let period: String
    switch hour {
    case 5..<12:  period = "Morning"
    case 12..<17: period = "Afternoon"
    default:      period = "Evening"
    }
    if maxDelta < 0 {
        return "\(period) activity helped ↓\(pts) pts"
    } else {
        return "\(period) spike ↑\(pts) pts"
    }
}
```

<!-- RESOLVED: L2 — added trim animation state per user decision -->
**3e. Animation state**

```swift
@State private var lineDrawn = false
```

**3f. Body**

```swift
var body: some View {
    Button(action: { HapticService.impact(.medium); onTap() }) {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            chartArea
            if let note = inflectionAnnotation {
                Text(note)
                    .font(.r(.caption2, .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
    .buttonStyle(.plain)
    .onAppear {
        withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) {
            lineDrawn = true
        }
    }
}
```

**3g. headerRow subview**

```swift
private var headerRow: some View {
    HStack(alignment: .center) {
        Text("Stress today")
            .font(.r(.subheadline, .semibold))
            .foregroundStyle(.primary)

        Spacer()

        // Delta badge
        if let delta = scoreDelta {
            let worse = delta > 0
            Text("\(worse ? "↑" : "↓") \(abs(delta))")
                .font(.r(.caption2, .semibold))
                .foregroundStyle(worse ? AppColors.error : AppColors.success)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill((worse ? AppColors.error : AppColors.success).opacity(0.12))
                )
        }

        // Emoji + level + score
        if let score = latestScore {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 15))
                Text("\(Int(score.rounded()))")
                    .font(.r(.subheadline, .bold))
                    .foregroundStyle(.primary)
                if let lvl = stressLevel {
                    Text(lvl)
                        .font(.r(.caption, .regular))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("—")
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
```

<!-- RESOLVED: M1 — readings.count < 2 treated as empty state -->
<!-- RESOLVED: M2 — placeholder uses centered VStack layout -->
**3h. chartArea subview**

```swift
private var chartArea: some View {
    Group {
        if readings.count < 2 {
            emptyChartPlaceholder
        } else {
            realChart
        }
    }
    .frame(height: 52)
}

private var emptyChartPlaceholder: some View {
    VStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 0.5)
            .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(height: 1)
        Text("No stress data yet")
            .font(.r(.caption2, .regular))
            .foregroundStyle(Color(.systemGray3))
    }
    .frame(maxWidth: .infinity)
}

private var realChart: some View {
    Chart(chartPoints) { p in
        AreaMark(
            x: .value("Time", p.timestamp),
            y: .value("Stress", p.score)
        )
        .foregroundStyle(
            .linearGradient(
                colors: [accentColor.opacity(0.20), accentColor.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .interpolationMethod(.catmullRom)

        LineMark(
            x: .value("Time", p.timestamp),
            y: .value("Stress", p.score)
        )
        .foregroundStyle(accentColor)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .interpolationMethod(.catmullRom)
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: 0...100)
    .mask {
        Rectangle()
            .scaleEffect(x: lineDrawn ? 1 : 0, anchor: .leading)
    }
}
```

**3i. Preview block**

```swift
#Preview("StressSparklineStrip — Filled") {
    let now = Date()
    let cal = Calendar.current
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StressReading.self, configurations: config)
    let readings = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -6, to: now)!, score: 58, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -4, to: now)!, score: 72, levelLabel: "High"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -2, to: now)!, score: 48, levelLabel: "Moderate"),
        StressReading(timestamp: now, score: 34, levelLabel: "Good"),
    ]
    return StressSparklineStrip(readings: readings, stressLevel: "Good", scoreDelta: -18, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .modelContainer(container)
}

#Preview("StressSparklineStrip — Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StressReading.self, configurations: config)
    return StressSparklineStrip(readings: [], stressLevel: nil, scoreDelta: nil, onTap: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .modelContainer(container)
}
```

---

### Phase 3 — Wire into HomeView

**Step 4 — Insert strip between WellnessRingsCard and Mood Check-In** (`HomeView.swift`)

Location: After the `WellnessRingsCard(...)` block and before the `if !hasLoggedMoodToday` block.

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

- Action: insert at ~line 102 (between `.padding(.horizontal, 16)` of WellnessRingsCard and
  `// 3. Mood Check-In / Journal Reflection`)
- Why: Directly below the rings gives the user deeper context after seeing the stress ring
  and before the mood prompt
- Dependencies: Steps 1, 2, 3
- Risk: Low — pure view addition, no state mutation

---

## Testing Strategy

**Build verification:**
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate \
  -destination 'generic/platform=iOS Simulator' build
```
Run after every phase; all 4 targets should still pass.

**Manual verification flows:**
1. Open app with no stress data -> strip shows dashed-line empty state
2. Open Stress tab -> `requestPermissionAndLoad()` fires -> `logCurrentStress()` writes a
   reading -> switch back to Home tab -> still shows empty state (only 1 reading, need >= 2)
3. Trigger a second stress reading (e.g., log food, re-open Stress tab) -> strip now shows
   chart with line-drawing animation
4. Tap the strip -> confirm navigation to Stress tab (tab index 1)
5. With 2+ readings having |delta| >= 8 -> confirm annotation appears below chart
6. With yesterday reading stored -> confirm delta badge visible with correct sign/color
7. Preview in Xcode Canvas — both filled and empty state render correctly

---

## Risks & Mitigations

- **Risk**: `StressReading` entries are written only when stress is computed (Stress tab opened).
  If user never visits the Stress tab the strip stays empty.
  - Mitigation: Empty state ("No stress data yet") is explicitly handled and looks intentional,
    not broken. No silent failure.

- **Risk**: `@Query(sort: \StressReading.timestamp)` loads all historical readings. Over many
  months this could be hundreds of rows.
  - Mitigation: Each `StressReading` is tiny (~40 bytes). Even 1,000 rows ~ 40 KB in memory.
    Filtering in code (O(n)) is negligible. A date-bounded `@Query` can be added later if
    profiling shows it matters.

- **Risk**: `catmullRom` interpolation with only 1 reading produces blank chart.
  - Mitigation: `readings.count < 2` is treated as empty state, showing the dashed placeholder.

- **Risk**: Trim mask animation may clip AreaMark gradient at the leading edge during
  animation, producing a hard vertical edge instead of a smooth gradient.
  - Mitigation: Acceptable visual trade-off — the animation completes in ~1s and the final
    state is pixel-perfect. If it looks jarring in practice, fall back to a simple opacity
    fade-in.

---

## Success Criteria

- [ ] Strip renders correctly between Wellness Rings and Mood Check-In
- [ ] Empty state shows when fewer than 2 `StressReading` rows exist for today
- [ ] Chart updates reactively when Stress tab is visited and readings are written
- [ ] Line-drawing animation plays on appear
- [ ] Correct emoji, level label, and score shown in header
- [ ] Delta badge appears with correct sign and color when yesterday data exists
- [ ] Annotation shows only when |inflection| >= 8 pts and at least 2 readings exist
- [ ] Tapping navigates to Stress tab with haptic feedback
- [ ] All 4 build targets compile clean
- [ ] Xcode Preview renders both filled and empty states
