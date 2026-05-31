# Implementation Checklist: Hydration Timing in Stress Engine

**Source Plan:** [`260527-hydration-timing-stress-plan-RESOLVED.md`](../02_Planning/Specs/260527-hydration-timing-stress-plan-RESOLVED.md)
**Audit:** [`260527-hydration-timing-stress-plan-audit.md`](../03_Audits/260527-hydration-timing-stress-plan-audit.md)
**Date:** 2026-05-27

---

## Pre-Implementation

- [ ] Read the RESOLVED plan in full.
  - Verify: confident on all four user decisions (C1 drop `now`, H1 gate bolus by `r ≥ 0.6`, H2 clamp `r ≥ 0.8`, M2 seed 2 bad days).
- [ ] Verify all referenced files exist:
  - `Cadence/Models/WellnessDayLog.swift`
  - `Cadence/Core/Services/StressScoring.swift`
  - `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift`
  - `Cadence/Features + UI/Home/Views/HomeView.swift`
  - `Cadence/Features + UI/Home/Views/WaterDetailView.swift`
  - `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift`
  - `Cadence/Core/Services/MockDataInjector.swift`
  - `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift`
  - Verify: `ls` each path returns success.
- [ ] Confirm clean working tree (no unstaged changes that conflict with these files).
  - Verify: `git status` shows the existing in-progress files but none of the eight above are modified.

---

## Phase 1 — Schema & Writers

### 1.1 — Add `waterLogTimestamps` to `WellnessDayLog`

- [ ] Open `Cadence/Models/WellnessDayLog.swift` and add the new stored property right after `var waterGlasses: Int` (line 17):
  ```swift
  /// Timestamps of each water-glass increment (count == waterGlasses). Empty
  /// for legacy rows — engine falls back to flat scoring.
  var waterLogTimestamps: [Date] = []
  ```
  - Verify: file compiles standalone (`xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build` — expect failure later but model file alone should not produce a parse error).
- [ ] Update the `init(...)` (lines 42–64) to accept and assign the new field:
  - Add parameter `waterLogTimestamps: [Date] = []` between `waterGlasses` and `exerciseMinutes`.
  - Add `self.waterLogTimestamps = waterLogTimestamps` in the body, between `self.waterGlasses` and `self.exerciseMinutes`.
  - Verify: parameter list is consistent with property declaration order; default value `[]` preserves call-site compatibility for legacy constructors.

### 1.2 — Update `WaterDetailView.updateGlasses`

- [ ] Open `Cadence/Features + UI/Home/Views/WaterDetailView.swift` and replace `updateGlasses(_:)` (lines 270–274) with:
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
  - Verify: every caller of `updateGlasses` (`addGlass`, `removeGlass`, `toggleGlass(at:)` at lines 246–268) still passes a single `Int` and compiles.

### 1.3 — Update `HomeView.updateHydrationForToday`

- [ ] Open `Cadence/Features + UI/Home/Views/HomeView.swift` and modify `updateHydrationForToday(_:)` (lines 1159–1170). Insert reconciliation between the existing `guard` and the assignment to `waterGlasses`:
  ```swift
  private func updateHydrationForToday(_ cups: Int) {
      let safeCups = max(cups, 0)
      let todayLog = fetchOrCreateTodayWellnessLog()
      guard todayLog.waterGlasses != safeCups else { return }

      let current = todayLog.waterLogTimestamps
      if safeCups > current.count {
          let additions = Array(repeating: Date(), count: safeCups - current.count)
          todayLog.waterLogTimestamps = current + additions
      } else if safeCups < current.count {
          todayLog.waterLogTimestamps = Array(current.prefix(safeCups))
      }
      todayLog.waterGlasses = safeCups
      do {
          try modelContext.save()
      } catch {
          WPLogger.home.error("Hydration save failed: \(error.localizedDescription)")
      }
  }
  ```
  - Verify: existing `guard` early-out still skips when `safeCups` already matches (no-op semantics preserved).

### 1.4 — Update `CoffeeDetailView.logOneWater`

- [ ] Open `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift` and replace `logOneWater()` (lines 329–333) with:
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
  - Verify: when `log.waterGlasses == waterGoal`, the guard prevents both `waterGlasses` and `waterLogTimestamps` from changing.

### 1.5 — Audit writer enumeration

- [ ] Run `grep -rn 'waterGlasses\s*=' Cadence --include='*.swift'` and confirm exactly four assignment sites are present in non-mock code:
  - `Cadence/Features + UI/Home/Views/HomeView.swift:1170-ish` (post-edit line will differ slightly)
  - `Cadence/Features + UI/Home/Views/WaterDetailView.swift` (inside `updateGlasses`)
  - `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift` (inside `logOneWater`)
  - Mock writers in `MockDataInjector.swift` and `StressMockSnapshot.swift` (handled in Phase 3)
  - Verify: no fifth non-mock writer exists. If one appears, halt and update the plan.

---

## Phase 2 — Stress Engine

### 2.1 — Extend `HydrationInput`

- [ ] Open `Cadence/Core/Services/StressScoring.swift` and edit `HydrationInput` (line 70-73):
  ```swift
  struct HydrationInput {
      let glasses: Int
      let hasWellnessRow: Bool
      let timestamps: [Date]   // empty → unknown, distribution checks skipped
  }
  ```
  - Verify: build will fail at call sites; this is expected and resolved in 2.4 + mock-mode site (StressViewModel.swift:1084-1087).

### 2.2a — Add `HydrationDistribution` constants

- [ ] In `Cadence/Core/Services/StressScoring.swift`, locate the `Weights` enum (around line 236). Immediately after the `Weights` declaration block, insert:
  ```swift
  /// Tunable constants for the hydration-distribution sub-penalties (bolus,
  /// late-bunch, backfill). Kept private and grouped here so threshold
  /// tuning is a single-file change.
  private enum HydrationDistribution {
      static let bolusWindow: TimeInterval = 3600
      static let bolusThresholds: [(burst: Int, points: Double)] = [(6, 3), (4, 2), (3, 1)]
      static let bolusRatioMin: Double = 0.6
      static let lateHourCutoff: Int = 21
      static let lateRatioMin: Double = 0.5
      static let lateGlassesMin: Int = 4
      static let latePoints: Double = 1
      static let backfillSpan: TimeInterval = 600
      static let backfillRatioMin: Double = 0.8
      static let backfillFloor: Double = 3
      static let minTimestamps: Int = 3
  }
  ```
  - Verify: file compiles up to this point (the enum is self-contained — referenced only by 2.2b).

### 2.2b — Rewrite `hydrationPoints` and add `maxGlassesInWindow`

- [ ] Replace the body of `hydrationPoints(input:goal:)` (lines 398–415) with the version below. **Do not change the function signature** — it must remain `(input: HydrationInput?, goal: Int)`.
  ```swift
  static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints {
      guard let input = input else { return .none }
      guard input.hasWellnessRow else { return .none }
      let goalSafe = max(goal, 1)
      let r = Double(input.glasses) / Double(goalSafe)

      var pts: Double
      switch r {
      case ..<0.3:    pts = 5
      case 0.3..<0.5: pts = 3
      case 0.5..<0.8: pts = 1
      default:        pts = 0
      }

      var hints: [String] = []
      let ts = input.timestamps

      // 1–2 glass days hit base = 5 already (r < 0.3). Skipping is safe:
      // any further addition would only be clipped by the Weights cap.
      if ts.count >= HydrationDistribution.minTimestamps {
          if r >= HydrationDistribution.bolusRatioMin {
              let burst = maxGlassesInWindow(ts, window: HydrationDistribution.bolusWindow)
              if let match = HydrationDistribution.bolusThresholds.first(where: { burst >= $0.burst }) {
                  pts += match.points
                  hints.append("logged in burst")
              }
          }

          let cal = Calendar.current
          let lateCount = ts.filter {
              cal.component(.hour, from: $0) >= HydrationDistribution.lateHourCutoff
          }.count
          if input.glasses >= HydrationDistribution.lateGlassesMin,
             Double(lateCount) / Double(input.glasses) >= HydrationDistribution.lateRatioMin {
              pts += HydrationDistribution.latePoints
              hints.append("mostly after 21:00")
          }

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
  ```
  - Verify: function signature is unchanged — `static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints`. No `now: Date` parameter.
- [ ] Immediately after `hydrationPoints`, add the sliding-window helper:
  ```swift
  /// Largest count of timestamps that lie within any `window`-sized range.
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
  - Verify: helper is `private static` so it doesn't leak into the public surface; lives next to `hydrationPoints` for locality.

### 2.3 — Verify `allFactors` call site unchanged

- [ ] Open `Cadence/Core/Services/StressScoring.swift:812` and confirm the line still reads:
  ```swift
  hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups),
  ```
  - Verify: **no change made** to this line. No `now:` argument. `allFactors(inputs:)` signature also unchanged (line 805).

### 2.4 — Wire `HydrationInput` in the VM + debug invariant

- [ ] Open `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift` and modify the real-mode `HydrationInput` construction (lines 942-945):
  ```swift
  let hydrationInput: StressScoring.HydrationInput? = todayWellness.map { log in
      #if DEBUG
      assert(
          log.waterLogTimestamps.isEmpty ||
          log.waterLogTimestamps.count == log.waterGlasses,
          "WellnessDayLog drift: waterGlasses=\(log.waterGlasses) but timestamps.count=\(log.waterLogTimestamps.count)"
      )
      #endif
      return StressScoring.HydrationInput(
          glasses: log.waterGlasses,
          hasWellnessRow: true,
          timestamps: log.waterLogTimestamps
      )
  }
  ```
  - Verify: `#if DEBUG` guards the assert so production builds don't carry it; assert lets legacy/empty arrays pass.
- [ ] Modify the mock-mode `HydrationInput` construction at `StressViewModel.swift:1084-1087`:
  ```swift
  let hydrationInput = StressScoring.HydrationInput(
      glasses: snap.waterGlasses,
      hasWellnessRow: hasWellnessProxy,
      timestamps: snap.waterLogTimestamps
  )
  ```
  - Verify: requires `StressMockSnapshot.waterLogTimestamps` to exist — Phase 3.2 adds it. Until 3.2 lands, this line will fail to compile. Order Phase 3.2 before the next build.

---

## Phase 3 — Mocks & Build Verification

### 3.1 — `MockDataInjector` seed timestamps + bad-distribution days

- [ ] Open `Cadence/Core/Services/MockDataInjector.swift`. Above the function that contains the `for offset in 0..<30` loop (line 211-ish), add three private helpers:
  ```swift
  private static func spreadTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
      let span: TimeInterval = 14 * 3600   // 08:00 → 22:00
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }

  /// Late-bunch scenario: timestamps clustered between 21:30 and 22:30.
  private static func lateBunchTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 21, minute: 30, second: 0, of: day) ?? day
      let span: TimeInterval = 3600
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }

  /// Bolus scenario: timestamps within a 45-min window at 14:00.
  private static func bolusTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
      let span: TimeInterval = 45 * 60
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }
  ```
  - Verify: helpers are `private static`, defined at the type level.
- [ ] Inside the `for offset in 0..<30` loop (lines 211–229), before the `WellnessDayLog(...)` constructor, compute `glasses` and `timestamps`:
  ```swift
  let glasses = 3 + (offset % 6)
  let timestamps: [Date]
  switch offset % 10 {
  case 0:  timestamps = lateBunchTimestamps(count: glasses, on: startOfDay, cal: cal)
  case 1:  timestamps = bolusTimestamps(count: glasses, on: startOfDay, cal: cal)
  default: timestamps = spreadTimestamps(count: glasses, on: startOfDay, cal: cal)
  }
  ```
- [ ] Update the `WellnessDayLog(...)` constructor (lines 216–226) to pass `waterLogTimestamps: timestamps` and use the local `glasses` variable:
  ```swift
  let log = WellnessDayLog(
      day: startOfDay,
      moodRaw: offset % 5,
      waterGlasses: glasses,
      waterLogTimestamps: timestamps,
      exerciseMinutes: exerciseValues[offset % 7],
      caloriesBurned: calorieValues[offset % 7],
      steps: stepValues[offset % 7],
      stressLevel: stressLevels[offset % 5],
      coffeeCups: offset % 4,
      coffeeType: coffeeTypes[offset % 4]
  )
  ```
  - Verify: `glasses` matches the prior expression `3 + (offset % 6)`; `timestamps.count == glasses` for every branch.

### 3.2 — `StressMockSnapshot` add `waterLogTimestamps` field + factory updates

- [ ] Open `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift`. In the struct (after `let waterGlasses: Int` at line 64), add:
  ```swift
  /// Timestamps for each glass in `waterGlasses` (count must match).
  /// Empty array → factor falls back to flat scoring (legacy semantics).
  let waterLogTimestamps: [Date]
  ```
  - Verify: property is `let` (immutable, like its neighbors).
- [ ] Update the six factory methods to pass `waterLogTimestamps:`. For each factory below, add the property near `waterGlasses:` in the struct literal:
  - [ ] `makeDefault()` (around line 328) — use `spreadTimestamps`-equivalent over today's hours, or `[]` if `waterGlasses == 0`.
  - [ ] `makeSparse()` (around line 95, waterGlasses at line 132) — `waterLogTimestamps: []` (matches `waterGlasses: 0`).
  - [ ] `makeFullyLoggedBalancedDay()` (line 138, waterGlasses at line 168) — supply 6 evenly-spaced timestamps across today.
  - [ ] `makeFullyLoggedBadDay()` (line 174, waterGlasses at line 226) — supply 1 timestamp at a plausible single time of day.
  - [ ] `makeDisengagedBadDay21h()` (line 232, waterGlasses at line 276) — `waterLogTimestamps: []` (matches `waterGlasses: 0`).
  - [ ] `makeDayOneNoData()` (line 282, waterGlasses at line 321) — `waterLogTimestamps: []`.
  - Verify after each: file builds incrementally (every `StressMockSnapshot(...)` constructor literal includes the new field).
- [ ] Add a new factory `makeLateBingeHydration()` and corresponding `static let lateBingeHydration` near the other static lets (line 90-ish). Construct it by starting from `makeFullyLoggedBalancedDay`'s base and overriding:
  - `waterGlasses: 8`
  - `waterLogTimestamps:` 8 timestamps clustered between 22:00 and 22:10 today (use a local helper `today.addingTimeInterval(22*3600 + Double($0)*60)` for `$0` in `0..<8`).
  - Verify: factory returns a snapshot whose hydration factor will compute to ≥4 (base 0 + bolus 3 + late 1 — backfill no-op since 3 ≤ 3).

### 3.3 — Build verification

- [ ] Run all four build targets:
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`
  - Verify: all four return `** BUILD SUCCEEDED **`. If any fail, use `/develop fix` to triage.

---

## Phase 4 — Manual Verification

Run the app in the simulator with mock mode ON.

### 4.1 Even-distribution case
- [ ] Use AppConfig debug → select `StressMockSnapshot.fullyLoggedBalancedDay`. Open StressView.
  - Verify: hydration factor reads **0**, detail string is exactly `"6 of 8 glasses"` (or current goal) — no `·` suffix.

### 4.2 Bolus case (afternoon, goal met)
- [ ] Use AppConfig debug → trigger a mock day with 8 glasses clustered 14:00–15:00 (e.g., via a one-off debug button or by editing a row in the simulator's persisted store). Alternatively, the seeded `offset % 10 == 1` day from `MockDataInjector` will satisfy this when picked as "today".
  - Verify: hydration factor reads **3**. Detail: `"8 of 8 glasses · logged in burst"`.

### 4.3 Backfill case (rapid taps)
- [ ] Open the Home tab. Tap +1 on the hydration tile eight times within ~10 seconds. Note the time-of-day at tap.
  - Verify against expected values:

    | Hour at tap | Expected hydration factor | Expected detail suffix |
    |---|---|---|
    | 14:00 | 3 | `· logged in burst` |
    | 19:00 | 3 | `· logged in burst` |
    | 22:00 | 4 | `· logged in burst, mostly after 21:00` |

- [ ] Open StressView and confirm the factor card displays the matching value + suffix.

### 4.4 Legacy case
- [ ] Construct a `WellnessDayLog` row in DEBUG with `waterGlasses: 5, waterLogTimestamps: []` (use a debug menu button or direct SwiftData write).
  - Verify: hydration factor returns base-only result for `r = 5/8 = 0.625` → **1**. Detail: exactly `"5 of 8 glasses"` (no suffix). DEBUG assert does NOT fire.

### 4.5 SwiftData migration verification
- [ ] Check out `main` (pre-change) and run on a clean simulator. Log a few glasses via the Home tile to persist `WellnessDayLog` rows with non-zero `waterGlasses` in `default.store`.
- [ ] Quit the simulator app. Switch back to this branch (which contains the schema change). Re-launch the app **without** deleting the simulator's app data.
  - Verify:
    - App launches without crash.
    - The Home tile displays the historical water count correctly.
    - StressView's hydration factor displays a base-only result (no distribution hints), because `waterLogTimestamps` decoded as `[]`.
    - DEBUG assert does NOT fire on the legacy row.
    - Tapping +1 on the Home tile increments `waterGlasses` to N+1 and appends one timestamp to `waterLogTimestamps`. The factor now treats the row as 1-timestamped (no distribution check fires below `minTimestamps`).
- [ ] If migration fails to mount the store, halt and document the failure mode in the resolve / fix iteration. **Do not delete `default.store`** unless explicitly approved.

---

## Post-Implementation

- [ ] Run all four build targets one more time (sanity check after manual verification):
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Run `grep -rn 'waterLogTimestamps' Cadence --include='*.swift' | wc -l` and confirm count matches expectations (schema + 4 writers + scoring + VM + mock injector + mock snapshot factories ≈ 15–20 hits).
- [ ] Stage changes and commit:
  ```bash
  git add Cadence/Models/WellnessDayLog.swift \
          Cadence/Core/Services/StressScoring.swift \
          Cadence/Core/Services/MockDataInjector.swift \
          "Cadence/Features + UI/Home/Views/HomeView.swift" \
          "Cadence/Features + UI/Home/Views/WaterDetailView.swift" \
          "Cadence/Features + UI/Home/Views/CoffeeDetailView.swift" \
          "Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift" \
          "Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift" \
          Docs/02_Planning/Specs/260527-hydration-timing-stress-plan.md \
          Docs/02_Planning/Specs/260527-hydration-timing-stress-plan-RESOLVED.md \
          Docs/03_Audits/260527-hydration-timing-stress-plan-audit.md \
          Docs/04_Checklist/260527-hydration-timing-stress-checklist.md
  git status
  ```
- [ ] Confirm with user before pushing. Suggested commit message:
  ```
  feat(stress): hydration timing — bolus/late/backfill penalties

  Adds per-glass timestamps on WellnessDayLog and three distribution
  sub-penalties (bolus r≥0.6, late-bunch ≥21:00, backfill clamp r≥0.8)
  capped at Weights.hydration. Legacy rows fall through to flat scoring.
  ```

---

## Notes for Implementer

- **Compile order matters**: Step 2.1 (extend `HydrationInput`) breaks the build until both call sites (2.4 real-mode and 2.4 mock-mode) are updated. Plan to land 2.1 + 2.4 + 3.2 in one local checkpoint before running a full build.
- **Don't add `now` to `hydrationPoints`**: the resolved plan explicitly drops the `now` parameter (C1 resolution). The signature stays `(input:goal:)`.
- **Bolus gate is `r ≥ 0.6`, NOT `r ≥ 0.5`** (H1 resolution).
- **Backfill gate is `r ≥ 0.8`, NOT `r ≥ 0.5`** (H2 resolution).
- **DEBUG assert allows empty timestamps** (M4 resolution) — do not tighten to `count == waterGlasses` without the `isEmpty ||` prefix.
