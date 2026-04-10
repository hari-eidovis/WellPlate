# Implementation Plan: Stress Sparkline Strip (Home Screen)

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
- Header row: "Stress today" label (left) · emoji + level label + score (right)
- Delta badge in the header: "↑ +8" (worse, red-tinted) / "↓ −12" (better, green-tinted) vs. yesterday's last reading
- Intraday line+area sparkline chart (~52 pt tall) spanning 6 AM → now
  - X-axis: hidden — clean sparkline look
  - Y-axis: hidden, implicit range 0–100
  - `catmullRom` interpolation for smooth curves
  - Line color: `StressLevel(score:).color` of the latest reading (or `.secondary` when empty)
  - Area fill: same color at 0.15–0.0 opacity gradient (top → bottom)
- Annotation row below the chart: auto-detected inflection label, e.g.
  "Morning workout helped ↓12 pts" / "Post-lunch spike ↑9 pts"
  — shows only when the largest delta between consecutive readings is ≥ 8 pts
- Empty / loading state when no readings exist today: flat dashed line placeholder + "No stress data yet" caption
- Tapping anywhere navigates to the Stress tab (`selectedTab = 1`) with a `.medium` haptic

---

## Architecture Changes

| What | File |
|------|------|
| **New component** — `StressSparklineStrip` | `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift` |
| **HomeView** — add `@Query`, two computed properties, and the strip insertion | `WellPlate/Features + UI/Home/Views/HomeView.swift` |

No new SwiftData models, no ViewModel changes, no pbxproj edits needed.

---

## Implementation Steps

### Phase 1 — Data Plumbing in HomeView

**Step 1 — Add `@Query` for StressReadings** (`HomeView.swift`, after existing `@Query` declarations)

```swift
@Query(sort: \StressReading.timestamp) private var allStressReadings: [StressReading]
```

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

/// Last StressReading from yesterday — used for the Δ badge.
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

Full file layout:

```
WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift
```

**3a. Struct signature & inputs**

```swift
struct StressSparklineStrip: View {
    let readings: [StressReading]    // today's readings, sorted ascending
    let stressLevel: String?         // from WellnessDayLog (e.g. "Good")
    let scoreDelta: Int?             // vs yesterday, nil if unknown
    var onTap: () -> Void
}
```

**3b. Private helpers (inside the struct)**

```swift
// The most recent score (or nil)
private var latestScore: Double? { readings.last?.score }

// StressLevel enum for color/emoji
private var latestLevel: StressLevel? {
    latestScore.map { StressLevel(score: $0) }
}

// Emoji from stressLevel String (fallback to latestLevel)
private var emoji: String {
    switch stressLevel?.lowercased() {
    case "excellent": return "😄"
    case "good":      return "😌"
    case "moderate":  return "😐"
    case "high":      return "😣"
    case "very high": return "😰"
    default:          return latestLevel.map { emojiFor($0) } ?? "—"
    }
}

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

**3c. Body**

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
}
```

**3d. headerRow subview**

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

**3e. chartArea subview**

```swift
private var chartArea: some View {
    Group {
        if readings.isEmpty {
            emptyChartPlaceholder
        } else {
            realChart
        }
    }
    .frame(height: 52)
}

private var emptyChartPlaceholder: some View {
    ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(height: 1)
            .padding(.bottom, 26)
        Text("No stress data yet")
            .font(.r(.caption2, .regular))
            .foregroundStyle(Color(.systemGray3))
    }
}

private var realChart: some View {
    // Build chart data points identified by index so Swift Charts is happy
    let pts = readings.enumerated().map { (id: $0.offset, timestamp: $0.element.timestamp, score: $0.element.score) }
    return Chart {
        ForEach(pts, id: \.id) { p in
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
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: 0...100)
}
```

**3f. Preview block**

```swift
#Preview("StressSparklineStrip") {
    let now = Date()
    let cal = Calendar.current
    let readings = [
        StressReading(timestamp: cal.date(byAdding: .hour, value: -6, to: now)!, score: 58, levelLabel: "Moderate"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -4, to: now)!, score: 72, levelLabel: "High"),
        StressReading(timestamp: cal.date(byAdding: .hour, value: -2, to: now)!, score: 48, levelLabel: "Moderate"),
        StressReading(timestamp: now, score: 34, levelLabel: "Good"),
    ]
    VStack(spacing: 16) {
        StressSparklineStrip(readings: readings, stressLevel: "Good", scoreDelta: -18, onTap: {})
        StressSparklineStrip(readings: [], stressLevel: nil, scoreDelta: nil, onTap: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
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
1. Open app with no stress data → strip shows "No stress data yet" empty state
2. Open Stress tab → `requestPermissionAndLoad()` fires → `logCurrentStress()` writes a
   reading → switch back to Home tab → strip now shows chart (reactive via `@Query`)
3. Tap the strip → confirm navigation to Stress tab (tab index 1)
4. With 2+ readings having |delta| ≥ 8 → confirm annotation appears below chart
5. With yesterday reading stored → confirm Δ badge visible with correct sign/color
6. Preview in Xcode Canvas — both filled and empty state

---

## Risks & Mitigations

- **Risk**: `StressReading` entries are written only when stress is computed (Stress tab opened).
  If user never visits the Stress tab the strip stays empty.
  - Mitigation: Empty state ("No stress data yet") is explicitly handled and looks intentional,
    not broken. No silent failure.

- **Risk**: `@Query(sort: \StressReading.timestamp)` loads all historical readings. Over many
  months this could be hundreds of rows.
  - Mitigation: Each `StressReading` is tiny (~40 bytes). Even 1,000 rows ≈ 40 KB in memory.
    Filtering in code (O(n)) is negligible. A date-bounded `@Query` can be added later if
    profiling shows it matters.

- **Risk**: If `StressLevel.color` (blue opacity gradient) renders poorly against the card
  background for the "Good" level (opacity 0.58), the line may be too faint.
  - Mitigation: Always render the line at full `accentColor` opacity; only the area fill uses
    the reduced opacity. This is hardcoded in the `LineMark` foreground style.

- **Risk**: `catmullRom` interpolation with only 1 reading produces a dot, not a line.
  - Mitigation: With a single reading the chart gracefully shows a single point; the
    `AreaMark` still renders a filled region at that score. Visually acceptable.

---

## Success Criteria

- [ ] Strip renders correctly between Wellness Rings and Mood Check-In
- [ ] Empty state shows when no `StressReading` rows exist for today
- [ ] Chart updates reactively when Stress tab is visited and a reading is written
- [ ] Correct emoji, level label, and score shown in header
- [ ] Delta badge appears with correct sign and color when yesterday data exists
- [ ] Annotation shows only when |inflection| ≥ 8 pts and at least 2 readings exist
- [ ] Tapping navigates to Stress tab with haptic feedback
- [ ] All 4 build targets compile clean
- [ ] Xcode Preview renders both filled and empty states
