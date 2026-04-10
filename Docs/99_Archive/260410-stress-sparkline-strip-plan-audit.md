# Plan Audit Report: Stress Sparkline Strip (Home Screen)

**Audit Date**: 2026-04-10
**Plan Version**: `Docs/02_Planning/Specs/260410-stress-sparkline-strip-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured with a clean data flow (SwiftData `@Query` → presentational
component), correct placement in the view hierarchy, and solid empty-state handling.
Three issues prevent the pseudocode from compiling as-is, and one single-reading edge
case would produce a blank chart. All are straightforward fixes.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: ForEach with tuple — won't compile

- **Location**: Phase 2, Step 3e (`realChart` computed property)
- **Problem**: The plan uses `readings.enumerated().map { (id:, timestamp:, score:) }`
  and then passes it to `ForEach(pts, id: \.id)`. Swift keypaths do not work on tuples,
  so `\.id` fails to compile.
- **Impact**: Build failure — the entire chart body won't compile.
- **Recommendation**: Define a private `Identifiable` struct, matching the pattern used in
  every other chart in this codebase (`ChartPoint` in `TrendAreaChart`, `SparkPoint` in
  `SparklineView`, etc.):
  ```swift
  private struct IntradayPoint: Identifiable {
      let id: Int
      let timestamp: Date
      let score: Double
  }

  private var chartPoints: [IntradayPoint] {
      readings.enumerated().map { IntradayPoint(id: $0.offset, timestamp: $0.element.timestamp, score: $0.element.score) }
  }
  ```
  Then use `ForEach(chartPoints)` (the `id:` parameter is implicit via `Identifiable`).

---

### HIGH (Should Fix Before Proceeding)

#### H1: Missing `import Charts`

- **Location**: Phase 2, Step 3 — new file `StressSparklineStrip.swift`
- **Problem**: The plan's pseudocode uses `Chart`, `LineMark`, `AreaMark`, `StrokeStyle`
  from the Charts framework, but doesn't list the required imports.
- **Impact**: Build failure in the new file.
- **Recommendation**: Imports should be:
  ```swift
  import SwiftUI
  import SwiftData
  import Charts
  ```

#### H2: Reference to undefined `emojiFor(_:)` helper

- **Location**: Phase 2, Step 3b — `emoji` computed property
- **Problem**: The fallback branch `latestLevel.map { emojiFor($0) }` references a function
  `emojiFor(_:)` that is never defined. `StressLevel` has no `emoji` property either — the
  emoji mapping only exists as `HomeView.stressEmojiFromLevel()`.
- **Impact**: Build failure — undefined function.
- **Recommendation**: Drop the fallback entirely. The `switch` on `stressLevel?.lowercased()`
  already covers all 5 cases plus a `default: "—"` branch. The `latestLevel` fallback path
  is unreachable when `stressLevel` is non-nil and redundant when it's nil.
  Simplified:
  ```swift
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

---

### MEDIUM (Fix During Implementation)

#### M1: Single reading produces blank chart

- **Location**: Phase 2, Step 3e — `realChart`
- **Problem**: `LineMark` requires ≥2 data points to render a visible line. With exactly
  1 `StressReading`, both `LineMark` and `AreaMark` render nothing — the chart area appears
  entirely blank (no dot, no line).
- **Impact**: User sees a card with a header saying "😌 32" but the chart area is empty.
  Confusing — not broken, but a poor UX.
- **Recommendation**: Add a `PointMark` when `readings.count == 1`, or treat `count < 2`
  as the empty state (show the dashed placeholder). The latter is simpler and more
  consistent.

#### M2: `emptyChartPlaceholder` framing is fragile

- **Location**: Phase 2, Step 3e
- **Problem**: The dashed line uses `.padding(.bottom, 26)` inside a 52 pt frame, which
  hardcodes the vertical centering. If the card's spacing or padding changes, the line
  drifts visually.
- **Recommendation**: Center the placeholder content properly:
  ```swift
  VStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 0.5)
          .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4]))
          .frame(height: 1)
      Text("No stress data yet")
          .font(.r(.caption2, .regular))
          .foregroundStyle(Color(.systemGray3))
  }
  .frame(maxWidth: .infinity)
  ```

---

### LOW (Consider for Future)

#### L1: `@Query` loads all historical readings

- **Location**: Phase 1, Step 1
- **Problem**: `@Query(sort: \StressReading.timestamp)` fetches every `StressReading` ever
  recorded. After a year of use (~3,600 rows), filtering on every body evaluation adds
  minor overhead.
- **Impact**: Negligible now; could matter if readings are logged more frequently in the
  future (e.g., automatic background refresh every hour).
- **Recommendation**: Acceptable for v1. If profiling shows overhead later, switch to a
  `FetchDescriptor` with a date predicate called from `onAppear`/`scenePhase`, or use
  `@Query` with a static date predicate.

#### L2: No animation on strip appearance

- **Location**: Phase 3, Step 4
- **Problem**: The strip appears statically. Other home screen cards (mood check-in,
  journal) use spring transitions. The strip could benefit from a subtle fade-in or the
  chart line drawing animation.
- **Recommendation**: Optional polish — add `.transition(.opacity)` on the strip, or
  animate the line trim similar to `WellnessRingsCard`'s ring animation.

---

## Missing Elements

- [x] Component signature and inputs — covered
- [x] Empty state — covered
- [x] Tap target and navigation — covered
- [x] Delta computation — covered
- [x] Build verification — covered
- [ ] **`import` declarations** for the new file (H1)
- [ ] **Private Identifiable struct** for chart data (C1)
- [ ] **Single-reading edge case** (M1)

## Unverified Assumptions

- [x] `StressReading.timestamp` and `.score` exist — **verified** (`Models/StressReading.swift`)
- [x] `StressLevel(score:).color` exists — **verified** (`Models/StressModels.swift`)
- [x] `HapticService.impact(.medium)` exists — **verified** (`Core/Services/HapticService.swift`)
- [x] `WellnessDayLog.stressLevel` is `String?` — **verified** (`Models/WellnessDayLog.swift:29`)
- [x] `.r()` font extension — **verified** (`Shared/Extensions/Font/Font.swift:8`)
- [x] `.appShadow(radius:y:)` — **verified** (`Shared/Color/AppColor.swift:41`)
- [x] `AppColors.error` / `.success` — **verified** (`Shared/Color/AppColor.swift:18-19`)
- [x] `Calendar.isDateInToday()` / `isDateInYesterday()` — standard Foundation API

## Questions for Clarification

None — all questions answered via source code verification.

## Recommendations

1. **Fix C1 first** (tuple → struct) — this is a compile blocker
2. **Fix H1 and H2** during implementation — trivial but also compile blockers
3. **Treat `readings.count < 2` as empty state** (M1) — simplest and most consistent
4. **Consider adding a line-drawing animation** (L2) — low-effort polish that makes the
   strip feel alive on first render
