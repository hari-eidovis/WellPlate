# Implementation Checklist: Hydration Timing in Stress Engine — RESOLVED

**Source Checklist:** [`260527-hydration-timing-stress-checklist.md`](./260527-hydration-timing-stress-checklist.md)
**Audit Resolved:** [`260527-hydration-timing-stress-checklist-audit.md`](../03_Audits/260527-hydration-timing-stress-checklist-audit.md)
**Source Plan:** [`260527-hydration-timing-stress-plan-RESOLVED.md`](../02_Planning/Specs/260527-hydration-timing-stress-plan-RESOLVED.md)
**Date:** 2026-05-27
**Status:** Ready for `/develop implement`

---

## Audit Resolution Summary

| ID | Severity | Title | Resolution | Decision Source |
|---|---|---|---|---|
| C1 | CRITICAL | `let waterLogTimestamps: [Date]` (no default) breaks 6 init call sites | **Use `let waterLogTimestamps: [Date] = []` with default.** Allows incremental updates of the 6 factory call sites without breaking the build. | User |
| H1 | HIGH | Phase 4.2 (pure-bolus) has no reproducible fixture | **Add `makeAfternoonBolus()` factory** at 14:00–14:45 alongside `makeLateBingeHydration`. Phase 4.2 switches AppConfig to `StressMockSnapshot.afternoonBolus`. | User |
| M1 | MEDIUM | §1.1 verify "expect failure later" is misleading | **Resolved.** Verify reworded to "parse passes; workspace build still green at this checkpoint." | Author |
| M2 | MEDIUM | Pre-Impl clean-tree conflicts with current `git status` | **Resolved.** Pre-Impl now explicitly addresses the existing `HomeView.swift` diff. | Author |
| M3 | MEDIUM | §3.2 `makeDefault` timestamp count not specified | **Resolved.** "4 timestamps evenly spread across 08:00–22:00" called out explicitly. | Author |
| M4 | MEDIUM | §1.5 grep would catch mocks | **Resolved.** Grep tightened to `grep -v Mock` and explicitly moved to "run before Phase 2." | Author |
| M5 | MEDIUM | §4.3 doesn't address simulator-clock setup | **Resolved (Option a).** Added Simulator Date & Time setup steps. | User |
| L1 | LOW | Commit message lacks `Co-Authored-By` footer | **Resolved.** Footer added to sample. | Author |
| L2 | LOW | No rollback step for §4.5 migration failure | **Resolved.** "Stash, document, re-engage planner — do NOT delete store" added. | Author |
| L3 | LOW | Backfill hint never appears in rapid-tap path | **Resolved.** Note added under §4.3 table explaining why. | Author |
| L4 | LOW | `WellnessDayLog` synthesized init concern | **Acknowledged** — confirmed `WellnessDayLog` uses an explicit init that already follows the default-arg pattern; no change needed. | Author |

**Final verdict: ALL CRITICAL + HIGH RESOLVED. All MEDIUM + LOW addressed or acknowledged.**

---

## Pre-Implementation

- [ ] Read the resolved plan in full.
  - Verify: confident on all four plan-level user decisions (C1 drop `now`, H1 gate bolus by `r ≥ 0.6`, H2 clamp `r ≥ 0.8`, M2 seed 2 bad days) and the three checklist-level user decisions (default `[]`, `makeAfternoonBolus`, document simulator clock).
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
- [ ] **Address the pre-existing diff** on `HomeView.swift` (current branch has unstaged changes from the prior UX-polish commit cycle): <!-- RESOLVED: M2 -->
  - Run `git diff "Cadence/Features + UI/Home/Views/HomeView.swift"` and capture the existing diff.
  - Decide: commit/stash the existing edits *before* starting Step 1.3, **or** merge them into the new work explicitly.
  - Verify: the implementer can articulate which lines are pre-existing vs. new before touching the file.
- [ ] Confirm no `Cadence/Models/WellnessDayLog.swift`, `Cadence/Core/Services/StressScoring.swift`, or `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift` modifications are already staged.
  - Verify: `git status` shows these files clean.

---

## Phase 1 — Schema & Writers

### 1.1 — Add `waterLogTimestamps` to `WellnessDayLog`

- [ ] Open `Cadence/Models/WellnessDayLog.swift` and add the new stored property right after `var waterGlasses: Int` (line 17):
  ```swift
  /// Timestamps of each water-glass increment (count == waterGlasses). Empty
  /// for legacy rows — engine falls back to flat scoring.
  var waterLogTimestamps: [Date] = []
  ```
  - Verify: line passes Swift parse (no inline red bar in Xcode). At this checkpoint a full workspace build still passes — the type compiles fine in isolation because the default value preserves the existing initializer compatibility. <!-- RESOLVED: M1 -->
- [ ] Update the `init(...)` (lines 42–64) to accept and assign the new field:
  - Add parameter `waterLogTimestamps: [Date] = []` between `waterGlasses` and `exerciseMinutes`.
  - Add `self.waterLogTimestamps = waterLogTimestamps` in the body, between `self.waterGlasses` and `self.exerciseMinutes`.
  - Verify: parameter list is consistent with property declaration order; default value `[]` preserves call-site compatibility for legacy constructors. <!-- ACKNOWLEDGED: L4 — confirmed WellnessDayLog uses explicit init with all-defaults pattern. -->

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
  - Verify: existing `guard` early-out still skips when `safeCups` already matches (no-op semantics preserved). Pre-existing diff in `HomeView.swift` (from Pre-Impl) is preserved or explicitly reconciled.

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

### 1.5 — Audit writer enumeration <!-- RESOLVED: M4 -->

- [ ] **Run this check before starting Phase 2** (Phase 3 mock writes will add timestamp-array assignments that are unrelated to `waterGlasses`):
  ```bash
  grep -rn 'waterGlasses\s*=[^=]' Cadence --include='*.swift' | grep -v Mock
  ```
  - Verify: exactly four results — one per writer in `HomeView.swift`, `WaterDetailView.swift`, `CoffeeDetailView.swift` (`logOneWater` and the guard line don't both match — should be `logOneWater`'s `log.waterGlasses = next`), and one more in `HomeView.swift`'s tile mutation.
  - If a fifth non-mock writer surfaces, halt and update the plan.

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
  - Verify: build will fail at call sites (one real-mode in `StressViewModel.swift:944`, one mock-mode in `StressViewModel.swift:1084`); this is expected and resolved in 2.4. **Do not run a full workspace build between 2.1 and the end of 2.4 + 3.2** — it will fail until both `StressMockSnapshot.waterLogTimestamps` (3.2) and the VM updates (2.4) land.

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
  - Verify: enum is self-contained — no references to `HydrationInput` or other types; will not produce diagnostics on its own.

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
  - Verify: helper is `private static`; lives next to `hydrationPoints` for locality.

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
  - Verify: requires `StressMockSnapshot.waterLogTimestamps` (Phase 3.2). Land 3.2 before running a build.

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

- [ ] Open `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift`. In the struct (after `let waterGlasses: Int` at line 64), add the new property **with a default value**: <!-- RESOLVED: C1 -->
  ```swift
  /// Timestamps for each glass in `waterGlasses` (count must match).
  /// Empty array → factor falls back to flat scoring (legacy semantics).
  let waterLogTimestamps: [Date] = []
  ```
  - Verify: the default `= []` ensures the synthesized memberwise init makes `waterLogTimestamps:` optional. Existing 6 `StressMockSnapshot(...)` call sites still compile while we update them one at a time.
- [ ] Add a private helper at file scope (or as a nested static helper in the struct) for spread/cluster timestamp generation in factories. Since `StressMockSnapshot` has no shared helper file, add:
  ```swift
  private extension StressMockSnapshot {
      static func spread(_ count: Int, todayHourSpan: (Int, Int) = (8, 22)) -> [Date] {
          guard count > 0 else { return [] }
          let cal = Calendar.current
          let today = cal.startOfDay(for: Date())
          let start = cal.date(bySettingHour: todayHourSpan.0, minute: 0, second: 0, of: today) ?? today
          let end = cal.date(bySettingHour: todayHourSpan.1, minute: 0, second: 0, of: today) ?? today
          let span = end.timeIntervalSince(start)
          return (0..<count).map { i in
              start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
          }
      }

      static func cluster(_ count: Int, startHour: Int, durationMinutes: Int) -> [Date] {
          guard count > 0 else { return [] }
          let cal = Calendar.current
          let today = cal.startOfDay(for: Date())
          let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: today) ?? today
          let span: TimeInterval = Double(durationMinutes) * 60
          return (0..<count).map { i in
              start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
          }
      }
  }
  ```
  - Verify: extension is private to the file; `spread` and `cluster` are self-contained.
- [ ] Update the six factory methods to pass `waterLogTimestamps:`. Add the property near `waterGlasses:` in each struct literal:
  - [ ] `makeDefault()` (line 328, `waterGlasses: 4` at line 549) — `waterLogTimestamps: Self.spread(4)` (4 timestamps evenly across 08:00–22:00). <!-- RESOLVED: M3 -->
  - [ ] `makeSparse()` (line 95, `waterGlasses: 0` at line 132) — `waterLogTimestamps: []`.
  - [ ] `makeFullyLoggedBalancedDay()` (line 138, `waterGlasses: 6` at line 168) — `waterLogTimestamps: Self.spread(6)`.
  - [ ] `makeFullyLoggedBadDay()` (line 174, `waterGlasses: 1` at line 226) — `waterLogTimestamps: Self.cluster(1, startHour: 13, durationMinutes: 1)` (single mid-day timestamp).
  - [ ] `makeDisengagedBadDay21h()` (line 232, `waterGlasses: 0` at line 276) — `waterLogTimestamps: []`.
  - [ ] `makeDayOneNoData()` (line 282, `waterGlasses: 0` at line 321) — `waterLogTimestamps: []`.
  - Verify after each: file builds incrementally (every `StressMockSnapshot(...)` constructor literal includes the new field, but call sites that haven't been updated still compile thanks to the default `[]`).
- [ ] Add a new factory `makeLateBingeHydration()` and corresponding `static let lateBingeHydration: StressMockSnapshot = makeLateBingeHydration()` near the other static lets (line 90-ish). Body: start from `makeFullyLoggedBalancedDay`'s base and override:
  - `waterGlasses: 8`
  - `waterLogTimestamps: Self.cluster(8, startHour: 22, durationMinutes: 10)`
  - Verify: factory returns a snapshot whose hydration factor computes to **4** (base 0 + bolus +3 + late +1; backfill no-op since 4 ≥ 3). Expected detail: `"8 of 8 glasses · logged in burst, mostly after 21:00"`.
- [ ] Add a new factory `makeAfternoonBolus()` and corresponding `static let afternoonBolus: StressMockSnapshot = makeAfternoonBolus()` near the other static lets. Body: start from `makeFullyLoggedBalancedDay`'s base and override: <!-- RESOLVED: H1 -->
  - `waterGlasses: 8`
  - `waterLogTimestamps: Self.cluster(8, startHour: 14, durationMinutes: 45)`
  - Verify: factory returns a snapshot whose hydration factor computes to **3** (base 0 + bolus +3; no late-bunch because no timestamp is ≥ 21:00; no backfill no-op since pts=3=floor). Expected detail: `"8 of 8 glasses · logged in burst"`.

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

### 4.2 Pure-bolus case (afternoon, goal met) <!-- RESOLVED: H1 -->
- [ ] Use AppConfig debug → select `StressMockSnapshot.afternoonBolus`. Open StressView.
  - Verify: hydration factor reads **3**. Detail string: `"8 of 8 glasses · logged in burst"`. No late-bunch suffix. No backfill hint (bolus already pushes pts to floor).

### 4.3 Backfill case (rapid taps)

**Simulator clock setup** (required for the table below): <!-- RESOLVED: M5 -->
- [ ] On the simulator: open **Settings → General → Date & Time**, toggle off "Set Automatically," and set the time to **14:00** for the first row. After the first row verification, set to **19:00**, then **22:00** for subsequent rows. Each setting change takes effect immediately for `Calendar.current.component(.hour, from: Date())`.
- [ ] For each of the three time settings: open the Home tab and tap +1 on the hydration tile **eight times within ~10 seconds**. Then open StressView and check the hydration factor card.

  | Simulator hour | Expected hydration factor | Expected detail suffix |
  |---|---|---|
  | 14:00 | 3 | `· logged in burst` |
  | 19:00 | 3 | `· logged in burst` |
  | 22:00 | 4 | `· logged in burst, mostly after 21:00` |

- **Note:** `· logged all at once` (backfill hint) does NOT appear in any rapid-tap row because bolus already pushes `pts` above the backfill floor. The backfill hint surfaces only when `r ∈ [0.8, 1.0]` is reached with `timestamps.count < minTimestamps` — which is impossible (we need ≥3 timestamps to even check distribution), so in practice the backfill clamp suffix is essentially unreachable via the +1 tile. It exists as a defense-in-depth signal for the rare programmatic backfill path. <!-- RESOLVED: L3 -->
- [ ] After each row, reset the hydration count to 0 via the WaterDetail screen before changing the simulator clock for the next row.
- [ ] After all three rows: reset Date & Time → "Set Automatically" back to ON.

### 4.4 Legacy case
- [ ] Construct a `WellnessDayLog` row in DEBUG with `waterGlasses: 5, waterLogTimestamps: []` (use a debug menu button or a direct SwiftData write via a one-off debug action).
  - Verify: hydration factor returns base-only result for `r = 5/8 = 0.625` → **1**. Detail: exactly `"5 of 8 glasses"` (no suffix). DEBUG assert does NOT fire.

### 4.5 SwiftData migration verification
- [ ] Check out `main` (pre-change) and run on a clean simulator. Log a few glasses via the Home tile to persist `WellnessDayLog` rows with non-zero `waterGlasses` in `default.store`.
- [ ] Quit the simulator app. Switch back to this branch (which contains the schema change). Re-launch the app **without** deleting the simulator's app data.
  - Verify:
    - App launches without crash.
    - The Home tile displays the historical water count correctly.
    - StressView's hydration factor displays a base-only result (no distribution hints), because `waterLogTimestamps` decoded as `[]`.
    - DEBUG assert does NOT fire on the legacy row.
    - Tapping +1 on the Home tile increments `waterGlasses` to N+1 and appends one timestamp to `waterLogTimestamps`. The factor still treats the row as below `minTimestamps` (count=1).
- [ ] **If migration fails**: <!-- RESOLVED: L2 -->
  - `git stash` the schema-change branch.
  - Open a fix doc capturing the failure mode (which property failed to decode, what error SwiftData raised).
  - Re-engage `/develop plan` or `/develop fix` for a follow-up — do **not** delete `default.store` or otherwise touch persisted state without user approval.

---

## Post-Implementation

- [ ] Run all four build targets one more time (sanity check after manual verification):
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Run `grep -rn 'waterLogTimestamps' Cadence --include='*.swift' | wc -l` and confirm a plausible count (schema + 4 writers + scoring fn + VM real-mode + VM mock-mode + mock injector + 6 snapshot factories + 2 new factories ≈ 16–22 hits).
- [ ] Stage changes and commit (sample message): <!-- RESOLVED: L1 -->
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
          Docs/03_Audits/260527-hydration-timing-stress-checklist-audit.md \
          Docs/04_Checklist/260527-hydration-timing-stress-checklist.md \
          Docs/04_Checklist/260527-hydration-timing-stress-checklist-RESOLVED.md
  git status
  ```
- [ ] Confirm with user before pushing. Suggested commit message:
  ```
  feat(stress): hydration timing — bolus/late/backfill penalties

  Adds per-glass timestamps on WellnessDayLog and three distribution
  sub-penalties (bolus r≥0.6, late-bunch ≥21:00, backfill clamp r≥0.8)
  capped at Weights.hydration. Legacy rows fall through to flat scoring.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```

---

## Notes for Implementer

- **Compile order matters**: Step 2.1 (extend `HydrationInput`) breaks the build until both call sites in 2.4 AND the `StressMockSnapshot.waterLogTimestamps` field in 3.2 land. Order: 1.1 → 1.2 → 1.3 → 1.4 → 1.5 (grep) → 2.1 → 2.2a → 2.2b → 2.3 → 3.2 (struct field + factories) → 2.4 (now mock-mode line compiles) → 3.1 → 3.3 (build) → 4.x → Post-Impl. Critically: **do not attempt a full build between 2.1 and the end of 3.2.**
- **Don't add `now` to `hydrationPoints`**: the resolved plan explicitly drops the `now` parameter (C1 plan-resolution). The signature stays `(input:goal:)`.
- **Bolus gate is `r ≥ 0.6`, NOT `r ≥ 0.5`** (H1 plan-resolution).
- **Backfill gate is `r ≥ 0.8`, NOT `r ≥ 0.5`** (H2 plan-resolution).
- **DEBUG assert allows empty timestamps** (M4 plan-resolution) — do not tighten to `count == waterGlasses` without the `isEmpty ||` prefix.
- **The new `StressMockSnapshot.waterLogTimestamps` field MUST have a default value `= []`** (C1 checklist-resolution) — without it, all 6 existing call sites break simultaneously.
- **Phase 4.2 uses `afternoonBolus`, Phase 4.3 uses the live +1 tile** — the two scenarios isolate the bolus signal from the late-bunch signal (H1 checklist-resolution).
