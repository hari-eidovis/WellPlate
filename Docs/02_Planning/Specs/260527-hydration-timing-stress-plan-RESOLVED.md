# Implementation Plan: Hydration Timing in Stress Engine — RESOLVED

**Date:** 2026-05-27
**Source Plan:** [`260527-hydration-timing-stress-plan.md`](./260527-hydration-timing-stress-plan.md)
**Audit Resolved:** [`260527-hydration-timing-stress-plan-audit.md`](../../03_Audits/260527-hydration-timing-stress-plan-audit.md)
**Status:** Ready for Checklist

---

## Audit Resolution Summary

| ID | Severity | Title | Resolution | Decision Source |
|---|---|---|---|---|
| C1 | CRITICAL | `now` not in scope at `hydrationPoints` call site | **Dropped `now` parameter from `hydrationPoints`.** Function uses `Calendar.current.component(.hour, from: timestamp)` per-timestamp; no `now` needed. Zero changes to `allFactors` and its three callers. | User |
| H1 | HIGH | Bolus penalty punishes legitimate pre-workout hydration | **Gated bolus by `r ≥ 0.6`.** Below 0.6, base ratio penalty already reflects insufficient hydration; bolus only fires once user is past the catch-up zone. | User |
| H2 | HIGH | Backfill clamp `r ≥ 0.5` silently inflates mid-band | **Tightened to `r ≥ 0.8`.** Clamp now only suppresses unearned goal-met rewards; mid-band keeps existing base penalty of 1. Matches the prose intent. | User |
| M1 | MEDIUM | `detail` string offers no UX explanation | **Resolved.** `detail` now appends `" · logged in burst"` and/or `" · mostly after 21:00"` when those penalties fire. | Plan author |
| M2 | MEDIUM | `MockDataInjector` never exercises distribution paths | **Resolved.** Added 2 bad-distribution days (offset % 10 == 0 → late-bunch; == 1 → bolus) so new factor visibly surfaces in default mock previews. | User |
| M3 | MEDIUM | Magic numbers should be named constants | **Resolved.** All thresholds extracted into a `private enum HydrationDistribution` next to `Weights`. | Plan author |
| M4 | MEDIUM | `assert` would mis-fire on legacy rows | **Resolved.** Assert is now `assert(log.waterLogTimestamps.isEmpty || log.waterLogTimestamps.count == log.waterGlasses)` — legacy/empty arrays pass, post-write drift still caught. | Plan author |
| M5 | MEDIUM | SwiftData migration asserted but not verified | **Resolved.** Added explicit Phase 4 case "5. Migration verification" with simulator-with-prior-store reproduction steps. | Plan author |
| L1 | LOW | `>=3` gate skips 1-2 glass days | **Acknowledged** — safe by analysis. Added inline code comment in the implementation. |
| L2 | LOW | Bolus penalty ignores glass size | **Deferred** — depends on future cup-size feature. Noted in Out of Scope. |
| L3 | LOW | No enumeration of read paths | **Resolved.** Added a "Read paths intentionally untouched" section. |
| L4 | LOW | Phase 4 case-3 expected value imprecise | **Resolved.** Phase 4 now has a concrete expected-value table per time-of-day. |
| L5 | LOW | Pure-function purity not improved | **Acknowledged** — acceptable as-is; pre-existing `Calendar.current` impurity. |

**Final verdict on resolution: ALL CRITICAL + HIGH RESOLVED. All MEDIUM resolved or actively addressed. All LOW acknowledged or resolved.**

---

## Overview

Today the stress engine treats `WellnessDayLog.waterGlasses` as a goal-ratio penalty only — it cannot distinguish "8 glasses spaced through the day" from "8 glasses dumped at 22:00". The latter is physiologically *less* favorable (nocturia, possible bolus discomfort) and is also our strongest signal that the log is backfilled / gamed.

This plan adds per-glass timestamps as an additive schema field on `WellnessDayLog`, threads them through `StressScoring.HydrationInput`, and extends `hydrationPoints` with two new sub-penalties — **bolus** (gated by `r ≥ 0.6`) and **late-bunching** — alongside a **backfill clamp** (gated by `r ≥ 0.8`) that prevents the goal-ratio reward from firing when all timestamps are clustered within minutes of each other. All changes are backward-compatible: rows with an empty timestamps array (legacy, mocked-without-history, or freshly migrated) fall through to today's exact behavior.

The hydration factor's max contribution stays capped at `Weights.hydration = 5` so the overall score envelope and confidence-weight math are unchanged.

<!-- RESOLVED: C1 — `now` parameter dropped from hydrationPoints; no allFactors signature changes. -->
<!-- RESOLVED: H1 — bolus penalty gated by r ≥ 0.6. -->
<!-- RESOLVED: H2 — backfill clamp gated by r ≥ 0.8. -->

---

## Requirements

- Persist per-glass timestamps on `WellnessDayLog` without forcing a destructive migration (SwiftData default value handles legacy rows).
- Detect three timing pathologies:
  1. **Bolus** — many glasses in a short window, **and `r ≥ 0.6`** (>3, >4, >6 in any 60-min sliding window → +1, +2, +3).
  2. **Late bunching** — ≥50% of glasses logged after 21:00 when total ≥4.
  3. **Backfill** — all timestamps within a 10-min span, **claiming `r ≥ 0.8`**; clamp reward to the r<0.5 tier (floor 3).
- Keep `hydrationPoints` total ≤ `Weights.hydration` (currently 5). No widening of the stress envelope.
- Preserve today's `engagementPenalty` `no_water` ramp (`StressScoring.swift:637-640`, `:684-688`) unchanged — bolus detection lives in the *factor*, not the engagement nudge.
- Mocks (`MockDataInjector`, `StressMockSnapshot`) must populate plausible timestamp arrays so dev/preview builds keep producing realistic stress numbers, and must include at least one bolus + one late-bunch scenario in default mock previews.
- Writers that touch `waterGlasses` must keep `waterGlasses` and `waterLogTimestamps` consistent — increments append `.now`, decrements pop the most recent entry, absolute sets reconcile the array length.
- A `HydrationInput` with empty `timestamps` must yield exactly the old behavior. Verified by inspection — no separate flag needed.
- `hydrationPoints` requires no `now` parameter — `allFactors(inputs:)` signature is unchanged.

---

## Architecture Changes

| Component | Path | Change |
|---|---|---|
| Data model | `Cadence/Models/WellnessDayLog.swift` | Add `var waterLogTimestamps: [Date] = []`. Default ensures SwiftData migration is automatic for existing rows. |
| Scoring input | `Cadence/Core/Services/StressScoring.swift` (struct at line 70) | Add `timestamps: [Date]` to `HydrationInput`. |
| Scoring fn | `Cadence/Core/Services/StressScoring.swift:401-415` (`hydrationPoints`) | Layer bolus (gated `r ≥ 0.6`) + late-bunching + backfill clamp (gated `r ≥ 0.8`) on top of existing goal-ratio penalty; new private helper `maxGlassesInWindow(_:window:)`; new `private enum HydrationDistribution` for tunable constants. **`now` parameter not added.** |
| Scoring call site | `Cadence/Core/Services/StressScoring.swift:812` | **Unchanged** — still `hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups)`. |
| Hydration writer (Home tile) | `Cadence/Features + UI/Home/Views/HomeView.swift:1159-1170` | Reconcile `waterLogTimestamps` to match `safeCups` on absolute set. |
| Hydration writer (detail) | `Cadence/Features + UI/Home/Views/WaterDetailView.swift:246-274` | `addGlass()` appends now; `removeGlass()` pops last; `toggleGlass(at:)` truncates/appends. `updateGlasses(_:)` reconciles array length. |
| Hydration writer (coffee cross-log) | `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift:329-333` | `logOneWater` appends `.now`. |
| Stress VM | `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift:943-945` | Pass `log.waterLogTimestamps` into `HydrationInput`. |
| Mock seed | `Cadence/Core/Services/MockDataInjector.swift:216-226` | Generate `waterLogTimestamps` evenly across waking hours by default, **with 2 bad-distribution days per 30** (one bolus, one late-bunch). |
| Mock snapshots | `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift` (`waterGlasses` call-sites at lines 132, 168, 226, 276, 321, 549) | Add matching `waterLogTimestamps` per scenario; add a new `lateBingeHydration` scenario. |

No new files, no new SwiftData entities, no new `Weights` constants. <!-- RESOLVED: C1, M3 — no signature change to allFactors; new constants live in private enum next to Weights. -->

### Read paths intentionally untouched <!-- RESOLVED: L3 -->

The following call sites read `waterGlasses` only and require no changes for this plan:

- `Cadence/Core/Services/InsightEngine.swift:279, 389, 456, 519, 685`
- `Cadence/Core/Services/ReportDataBuilder.swift:162, 292, 445`
- `Cadence/Core/Services/ReportNarrativeGenerator.swift:292`
- `Cadence/Core/Services/SymptomCorrelationEngine.swift:74`
- `Cadence/Features + UI/Home/Views/AI15DayReportView.swift:130`
- `Cadence/Features + UI/Home/Views/WellnessCalendarView.swift:166, 449, 453, 478`
- `Cadence/Features + UI/Home/Views/ReportSections/HydrationCaffeineSection.swift:20`
- `Cadence/Features + UI/Home/Views/ReportSections/ReportHeaderSection.swift:28`
- `Cadence/Features + UI/Progress/Views/ProgressInsightsView.swift:113`
- `Cadence/Features + UI/Progress/Services/WellnessReportGenerator.swift:70`

These all operate on day-aggregate counts; per-timestamp distribution is a stress-engine concern only.

---

## Implementation Steps

### Phase 1 — Schema & Writers (≈1 hr)

#### 1.1 Add `waterLogTimestamps` to `WellnessDayLog`
- **File:** `Cadence/Models/WellnessDayLog.swift`
- **Action:**
  - Add `var waterLogTimestamps: [Date] = []` right after `var waterGlasses: Int` (line 17).
  - Add matching parameter `waterLogTimestamps: [Date] = []` to the initializer (lines 42-64). Assign in init body.
  - Add a short doc comment: `/// Timestamps of each water-glass increment (count == waterGlasses). Empty for legacy rows — engine falls back to flat scoring.`
- **Why:** Single source of truth on the day row. Default value `[]` makes the SwiftData schema migration automatic — existing rows decode with empty array.
- **Dependencies:** None.
- **Risk:** Low.

#### 1.2 Update `WaterDetailView` writers
- **File:** `Cadence/Features + UI/Home/Views/WaterDetailView.swift`
- **Action:** Replace `updateGlasses(_:)` (lines 270-274) with a body that reconciles both fields:
  ```swift
  private func updateGlasses(_ count: Int) {
      let log = fetchOrCreateTodayLog()
      let safe = max(0, count)
      let current = log.waterLogTimestamps
      if safe > current.count {
          let additions = Array(repeating: Date(), count: safe - current.count)
          log.waterLogTimestamps = current + additions
      } else if safe < current.count {
          log.waterLogTimestamps = Array(current.prefix(safe))
      }
      log.waterGlasses = safe
      try? modelContext.save()
  }
  ```
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 1.3 Update `HomeView.updateHydrationForToday`
- **File:** `Cadence/Features + UI/Home/Views/HomeView.swift:1159-1170`
- **Action:** Apply the same reconciliation logic before the existing `todayLog.waterGlasses = safeCups` line. Keep the `guard todayLog.waterGlasses != safeCups else { return }` early-out.
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 1.4 Update `CoffeeDetailView.logOneWater`
- **File:** `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift:329-333`
- **Action:**
  ```swift
  private func logOneWater() {
      let log = fetchOrCreateTodayLog()
      let next = min(log.waterGlasses + 1, waterGoal)
      guard next > log.waterGlasses else { return }
      log.waterLogTimestamps.append(Date())
      log.waterGlasses = next
      try? modelContext.save()
  }
  ```
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 1.5 Audit for stragglers
- **Action:** Run `grep -rn 'waterGlasses\s*=' Cadence` and verify the four writers above are the only ones. Mocks handled in Phase 3.
- **Dependencies:** 1.2, 1.3, 1.4.
- **Risk:** Medium — mitigated by debug assert (see 2.4).

---

### Phase 2 — Stress Engine (≈1.5 hr)

#### 2.1 Extend `HydrationInput`
- **File:** `Cadence/Core/Services/StressScoring.swift:70-73`
- **Action:**
  ```swift
  struct HydrationInput {
      let glasses: Int
      let hasWellnessRow: Bool
      let timestamps: [Date]   // empty → unknown, distribution checks skipped
  }
  ```
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 2.2 Add `HydrationDistribution` constants & `hydrationPoints` rewrite
- **File:** `Cadence/Core/Services/StressScoring.swift` — place the new `enum` near the existing `Weights` enum (around line 236), then update `hydrationPoints` at lines 398-415.

<!-- RESOLVED: M3 — named constants in a private enum. -->
<!-- RESOLVED: C1 — no `now` parameter. -->
<!-- RESOLVED: H1 — bolus gated by r ≥ bolusRatioMin. -->
<!-- RESOLVED: H2 — backfill clamp gated by r ≥ backfillRatioMin (0.8). -->
<!-- RESOLVED: M1 — detail string appended with hints when distribution penalties fire. -->
<!-- RESOLVED: L1 — comment on the `>=3` gate explaining why it's safe. -->

```swift
private enum HydrationDistribution {
    /// Sliding window for bolus detection.
    static let bolusWindow: TimeInterval = 3600
    /// (burst-count, points) ladder — first matching row applies.
    static let bolusThresholds: [(burst: Int, points: Double)] = [(6, 3), (4, 2), (3, 1)]
    /// Minimum r before bolus penalty engages — below this, base penalty
    /// already reflects insufficient intake and we don't want to punish
    /// legitimate catch-up clusters (e.g. pre-workout).
    static let bolusRatioMin: Double = 0.6
    /// Hour-of-day threshold for "late" timestamps.
    static let lateHourCutoff: Int = 21
    static let lateRatioMin: Double = 0.5
    static let lateGlassesMin: Int = 4
    static let latePoints: Double = 1
    /// Max span across all timestamps to qualify as backfill.
    static let backfillSpan: TimeInterval = 600
    /// Minimum r before backfill clamp engages — only suppress unearned
    /// goal-met rewards. Mid-band keeps its base penalty unchanged.
    static let backfillRatioMin: Double = 0.8
    static let backfillFloor: Double = 3
    /// Distribution checks need at least this many timestamps to be meaningful.
    static let minTimestamps: Int = 3
}

static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints {
    guard let input = input else { return .none }
    guard input.hasWellnessRow else { return .none }
    let goalSafe = max(goal, 1)
    let r = Double(input.glasses) / Double(goalSafe)

    // Base ratio penalty (unchanged thresholds).
    var pts: Double
    switch r {
    case ..<0.3:    pts = 5
    case 0.3..<0.5: pts = 3
    case 0.5..<0.8: pts = 1
    default:        pts = 0
    }

    var hints: [String] = []
    let ts = input.timestamps

    // Distribution adjustments — skip on 1–2 glass days. Base penalty is
    // already at maximum in those cases (r<0.3 → 5), so further additions
    // would only be clipped by the Weights.hydration cap anyway.
    if ts.count >= HydrationDistribution.minTimestamps {
        // (a) Bolus — only when user is past the catch-up zone (r ≥ 0.6).
        if r >= HydrationDistribution.bolusRatioMin {
            let burst = maxGlassesInWindow(ts, window: HydrationDistribution.bolusWindow)
            if let match = HydrationDistribution.bolusThresholds.first(where: { burst >= $0.burst }) {
                pts += match.points
                hints.append("logged in burst")
            }
        }

        // (b) Late bunching — independent of r; the body-clock cost stands
        // even for under-goal days.
        let cal = Calendar.current
        let lateCount = ts.filter { cal.component(.hour, from: $0) >= HydrationDistribution.lateHourCutoff }.count
        if input.glasses >= HydrationDistribution.lateGlassesMin,
           Double(lateCount) / Double(input.glasses) >= HydrationDistribution.lateRatioMin {
            pts += HydrationDistribution.latePoints
            hints.append("mostly after 21:00")
        }

        // (c) Backfill clamp — only when user is claiming goal-met (r ≥ 0.8)
        // but all timestamps are clustered within ~10 min. Mid-band keeps
        // its base penalty unchanged.
        if r >= HydrationDistribution.backfillRatioMin,
           let lo = ts.min(), let hi = ts.max(),
           hi.timeIntervalSince(lo) < HydrationDistribution.backfillSpan {
            if pts < HydrationDistribution.backfillFloor {
                pts = HydrationDistribution.backfillFloor
                hints.append("logged all at once")
            }
        }
    }

    pts = min(pts, Weights.hydration)
    var detail = "\(input.glasses) of \(goalSafe) glasses"
    if !hints.isEmpty {
        detail += " · " + hints.joined(separator: ", ")
    }
    return FactorPoints(points: pts, maxPoints: Weights.hydration, hasData: true, detail: detail)
}

/// Largest count of timestamps that lie within any `window` (seconds)-wide sliding range.
private static func maxGlassesInWindow(_ timestamps: [Date], window: TimeInterval) -> Int {
    guard !timestamps.isEmpty else { return 0 }
    let sorted = timestamps.sorted()
    var maxCount = 1
    var left = 0
    for right in 0..<sorted.count {
        while sorted[right].timeIntervalSince(sorted[left]) > window {
            left += 1
        }
        maxCount = max(maxCount, right - left + 1)
    }
    return maxCount
}
```

- **Dependencies:** 2.1.
- **Risk:** Medium — all thresholds tunable via the private enum.

#### 2.3 Call site unchanged
- **File:** `Cadence/Core/Services/StressScoring.swift:812`
- **Action:** **No change.** The line stays `hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups)`. <!-- RESOLVED: C1 -->
- **Dependencies:** 2.2.
- **Risk:** None.

#### 2.4 Build `HydrationInput` in the VM + debug invariant
- **File:** `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift:942-945` and the surrounding `loadData()`-style method.
- **Action:**
  ```swift
  let hydrationInput: StressScoring.HydrationInput? = todayWellness.map { log in
      // RESOLVED: M4 — assert allows legacy empty arrays; only catches drift.
      assert(
          log.waterLogTimestamps.isEmpty ||
          log.waterLogTimestamps.count == log.waterGlasses,
          "WellnessDayLog drift: waterGlasses=\(log.waterGlasses) but timestamps.count=\(log.waterLogTimestamps.count)"
      )
      return StressScoring.HydrationInput(
          glasses: log.waterGlasses,
          hasWellnessRow: true,
          timestamps: log.waterLogTimestamps
      )
  }
  ```
- **Why:** Surfaces schema-invariant drift in DEBUG builds without false-positiving on legacy rows that haven't yet been touched by a writer. <!-- RESOLVED: M4 -->
- **Dependencies:** 1.1, 2.1.
- **Risk:** Low.

---

### Phase 3 — Mocks & Build Verification (≈45 min)

#### 3.1 `MockDataInjector` — seed plausible + bad-distribution timestamps
- **File:** `Cadence/Core/Services/MockDataInjector.swift:216-226`
- **Action:** Add three helpers and dispatch per-day on `offset % 10`:
  ```swift
  private static func spreadTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
      let span: TimeInterval = 14 * 3600   // 08:00 → 22:00
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }

  /// Late-bunch scenario: all timestamps between 21:30 and 22:30.
  private static func lateBunchTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 21, minute: 30, second: 0, of: day) ?? day
      let span: TimeInterval = 3600
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }

  /// Bolus scenario: all timestamps within a 45-min window mid-day.
  private static func bolusTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
      let span: TimeInterval = 45 * 60
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }
  ```
  And inside the loop:
  ```swift
  let glasses = 3 + (offset % 6)
  let timestamps: [Date]
  switch offset % 10 {
  case 0:  timestamps = lateBunchTimestamps(count: glasses, on: startOfDay, cal: cal)   // RESOLVED: M2
  case 1:  timestamps = bolusTimestamps(count: glasses, on: startOfDay, cal: cal)        // RESOLVED: M2
  default: timestamps = spreadTimestamps(count: glasses, on: startOfDay, cal: cal)
  }

  let log = WellnessDayLog(
      day: startOfDay,
      moodRaw: offset % 5,
      waterGlasses: glasses,
      waterLogTimestamps: timestamps,
      exerciseMinutes: exerciseValues[offset % 7],
      // ...
  )
  ```
- **Why:** Gives default mock previews at least two days where the distribution penalty visibly contributes to the stress factor breakdown. <!-- RESOLVED: M2 -->
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 3.2 `StressMockSnapshot` — six existing scenarios + new bolus scenario
- **File:** `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift`
- **Action:** For each `waterGlasses:` site (lines 132, 168, 226, 276, 321, 549), set a matching `waterLogTimestamps:` field. Use `spreadTimestamps` for healthy scenarios; clustered late timestamps for the high-stress mock at line 549. Add a new `lateBingeHydration` scenario near the existing high-stress scenarios with `waterGlasses: 8, waterLogTimestamps: 8 timestamps clustered between 22:00–22:10`.
- **Why:** Preview-driven verification of every code path. <!-- RESOLVED: M2 -->
- **Dependencies:** 1.1.
- **Risk:** Medium — multiple construction sites; verify each compiles.

#### 3.3 Build verification — workspace, all four schemes
- **Action:** Run each of the four commands from CLAUDE.md:
  ```bash
  xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build
  xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build
  ```
- **Dependencies:** Phases 1 and 2 complete.
- **Risk:** Low.

---

### Phase 4 — Manual Verification (≈25 min, no code)

Smoke-test in the simulator with mock mode ON.

#### 4.1 Even-distribution case
- Setup: log 8 glasses one at a time, simulator clock advanced so timestamps span >1h.
- Expected: hydration factor reads **0**, detail `"8 of 8 glasses"` (no hints).

#### 4.2 Bolus case (afternoon, goal met)
- Setup: AppConfig debug — inject a row with `waterGlasses=8` and 8 timestamps within a 60-min window at 14:00–15:00.
- Expected: r=1.0, base 0, bolus burst=8 → +3, no late-bunch, no backfill (>10 min span).
- **Total: 3.** Detail: `"8 of 8 glasses · logged in burst"`.

#### 4.3 Backfill case (rapid taps right now)
- Setup: tap +1 eight times within 10 seconds. Time-of-day determines bolus and late add-ons.
- Expected values by time-of-day: <!-- RESOLVED: L4 -->

| Hour at tap | Base (r=1.0) | Bolus (burst=8, r≥0.6) | Late (hour≥21, ≥50%) | Backfill (r≥0.8, span<10min) | Cap | **Total** |
|---|---|---|---|---|---|---|
| 14:00 | 0 | +3 | — | floor 3 (no-op, 3 ≥ 3) | 5 | **3** |
| 19:00 | 0 | +3 | — | floor 3 (no-op) | 5 | **3** |
| 22:00 | 0 | +3 | +1 | floor 3 (no-op, 4 ≥ 3) | 5 | **4** |

Detail string includes `"logged in burst"` always; appends `"mostly after 21:00"` for the 22:00 case.

#### 4.4 Legacy case
- Setup: a wellness log with `waterGlasses > 0` and `waterLogTimestamps == []` (pre-migration row, or simulate by clearing via debug).
- Expected: function returns the *exact* base-only result (5 / 3 / 1 / 0 per r-band). No hints in detail string. No DEBUG assert fires.

#### 4.5 SwiftData migration verification <!-- RESOLVED: M5 -->
- Setup: install a build *without* this change on a clean simulator. Log a few glasses in the Home tab — confirm a `WellnessDayLog` row is persisted with `waterGlasses > 0`. Quit. Replace the app binary with the build *containing* this change (without deleting `default.store`). Re-launch.
- Expected:
  - App launches without crash.
  - The pre-existing row's `waterLogTimestamps` decodes as `[]`.
  - The Home tile shows the historical count correctly.
  - Tapping +1 from the Home tile appends a single timestamp (count becomes 1 even though glasses moves from N to N+1; the writer's reconciliation logic at 1.2 handles this).
- If migration fails to mount the store, document the DEBUG-only fallback before merging: delete `default.store` and reseed via MockDataInjector. **Do not ship this fallback to production.**

Document any threshold-tuning needed.

---

## Testing Strategy

- **Build verification (required):** 4 schemes per CLAUDE.md command list.
- **Automated tests:** Per CLAUDE.md, test files aren't wired into shared schemes. Recommend a local `StressScoringHydrationTests.swift` covering:
  - empty `timestamps` array → exact old behavior across all r-bands
  - `maxGlassesInWindow` correctness on edge cases (0, 1, exactly window-sized gap, ties)
  - bolus gating: r=0.59 with burst=8 → no bolus; r=0.6 with burst=3 → +1
  - bolus thresholds (3, 4, 6 glasses in 60 min)
  - late-bunching trigger / non-trigger boundary (3 vs 4 glasses; 49% vs 50%)
  - backfill clamp lifting r=1.0 score from 0 to 3 (and **not** lifting r=0.7 case)
  - distribution hints appended to detail string
- **Manual smoke (required):** Phase 4 cases 4.1–4.5 above.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Honest backfillers (real intake, late log) get penalized | Phase 5 follow-up: per-glass "Consumed at" time picker in `WaterDetailView`. Out of scope; documented. |
| Threshold tuning is judgment-based | All thresholds live in `HydrationDistribution` enum — tunable in one place. Phase 4 manual verification surfaces miscalibration. <!-- RESOLVED: M3 --> |
| Schema drift if a future writer forgets timestamps | DEBUG `assert(log.waterLogTimestamps.isEmpty || count == waterGlasses)` in `StressViewModel` — passes legacy rows, catches post-write drift. <!-- RESOLVED: M4 --> |
| `Calendar.current` impurity | Acceptable — pre-existing pattern. No new impurity introduced. <!-- ACKNOWLEDGED: L5 --> |
| Bolus penalty double-counts with engagement nudge | Engagement nudge fires only when `glasses == 0`; bolus fires only when `glasses ≥ 3` AND `r ≥ 0.6`. Mutually exclusive. |
| SwiftData migration unverified on real prior store | Phase 4 case 4.5 explicit verification step. <!-- RESOLVED: M5 --> |
| Bolus penalty ignores glass size | Depends on future cup-size feature surface. Out of scope. <!-- ACKNOWLEDGED: L2 --> |

---

## Out of Scope (Explicit Non-Goals)

- Adding a "Consumed at" time picker to `WaterDetailView` — flagged as a Phase 5 follow-up.
- Changing `Weights.hydration` or any other weight constant.
- Modifying the engagement `no_water` ramp.
- Migration of historical data — legacy rows already have correct fallback behavior.
- Adding hydration-related symptoms or correlation hooks.
- Bolus penalty calibration by cup size (depends on a future cup-size user setting). <!-- ACKNOWLEDGED: L2 -->

---

## Success Criteria

- [ ] `WellnessDayLog.waterLogTimestamps` exists with default `[]`; existing rows decode cleanly.
- [ ] All four hydration writers keep `waterGlasses == waterLogTimestamps.count` after any mutation.
- [ ] `hydrationPoints(input:goal:)` retains the same `(input:goal:)` signature — no `now`, no `allFactors` cascade.
- [ ] `hydrationPoints` returns identical results to the pre-change implementation when `timestamps` is empty.
- [ ] Bolus penalty does not fire when `r < 0.6` (e.g., 3 glasses in 30 min at goal=8 still scores base 3, not 4).
- [ ] Backfill clamp only fires when `r ≥ 0.8` (e.g., 5/8 glasses logged in one burst scores base 1, not 3).
- [ ] "8 glasses chugged after 21:00 within 10 minutes" → hydration factor = **4** (was 0).
- [ ] "8 glasses evenly across 08:00–22:00" → hydration factor 0 (unchanged).
- [ ] `Weights.hydration` cap (5 points) still respected in every code path.
- [ ] `detail` string includes hint suffixes when distribution penalties fire.
- [ ] `MockDataInjector` produces at least one bolus day and one late-bunch day per 10 seeded rows.
- [ ] DEBUG `assert` does not fire on a freshly seeded mock or a legacy row.
- [ ] Phase 4 SwiftData migration test passes on a prior-store install.
- [ ] All 4 build targets pass.
