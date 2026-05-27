# Implementation Plan: Hydration Timing in Stress Engine

**Date:** 2026-05-27
**Brainstorm / Strategy:** _(none — direct plan from chat dialogue dated 2026-05-27)_
**Touches:** `Cadence/Models/WellnessDayLog.swift`, `Cadence/Core/Services/StressScoring.swift`, `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift`, hydration writer call-sites, mocks
**Status:** Ready for Audit

---

## Overview

Today the stress engine treats `WellnessDayLog.waterGlasses` as a goal-ratio penalty only — it cannot distinguish "8 glasses spaced through the day" from "8 glasses dumped at 22:00". The latter is physiologically *less* favorable (nocturia, possible bolus discomfort) and is also our strongest signal that the log is backfilled / gamed.

This plan adds per-glass timestamps as an additive schema field on `WellnessDayLog`, threads them through `StressScoring.HydrationInput`, and extends `hydrationPoints` with two new sub-penalties — **bolus** and **late-bunching** — alongside a **backfill clamp** that prevents the goal-ratio reward from firing when all timestamps are clustered within minutes of each other. All changes are backward-compatible: rows that have an empty timestamps array (legacy, mocked-without-history, or just freshly migrated) fall through to today's exact behavior.

The hydration factor's max contribution stays capped at `Weights.hydration = 5` so the overall score envelope and confidence-weight math are unchanged.

---

## Requirements

- Persist per-glass timestamps on `WellnessDayLog` without forcing a destructive migration (SwiftData default value handles legacy rows).
- Detect three timing pathologies:
  1. **Bolus** — many glasses in a short window (>3, >4, >6 in any 60-min sliding window).
  2. **Late bunching** — ≥50% of glasses logged after 21:00 when total ≥4.
  3. **Backfill** — all timestamps within a 10-min span, claiming r ≥ 0.5; clamp reward to the r<0.5 tier.
- Keep `hydrationPoints` total ≤ `Weights.hydration` (currently 5). No widening of the stress envelope.
- Preserve today's `engagementPenalty` `no_water` ramp (`StressScoring.swift:637-640`, `:684-688`) unchanged — bolus detection lives in the *factor*, not the engagement nudge.
- Mocks (`MockDataInjector`, `StressMockSnapshot`) must populate plausible timestamp arrays so dev/preview builds keep producing realistic stress numbers.
- Writers that touch `waterGlasses` must keep `waterGlasses` and `waterLogTimestamps` consistent — increments append `.now`, decrements pop the most recent entry, absolute sets reconcile the array length.
- A `HydrationInput` with timestamps == empty must yield exactly the old behavior. Verified by inspection — no separate flag needed.

---

## Architecture Changes

| Component | Path | Change |
|---|---|---|
| Data model | `Cadence/Models/WellnessDayLog.swift` | Add `var waterLogTimestamps: [Date] = []`. Default ensures SwiftData migration is automatic for existing rows. |
| Scoring input | `Cadence/Core/Services/StressScoring.swift` (struct at line 70) | Add `timestamps: [Date]` to `HydrationInput`. |
| Scoring fn | `Cadence/Core/Services/StressScoring.swift:401-415` (`hydrationPoints`) | Accept `now: Date`; layer bolus + late-bunching + backfill clamp on top of existing goal-ratio penalty; new private helper `maxGlassesInWindow(_:window:)`. |
| Scoring call site | `Cadence/Core/Services/StressScoring.swift:812` | Pass `now` to `hydrationPoints`. |
| Hydration writer (Home tile) | `Cadence/Features + UI/Home/Views/HomeView.swift:1159-1170` | Reconcile `waterLogTimestamps` to match `safeCups` on absolute set. |
| Hydration writer (detail) | `Cadence/Features + UI/Home/Views/WaterDetailView.swift:246-274` | `addGlass()` appends now; `removeGlass()` pops last; `toggleGlass(at:)` truncates/appends. `updateGlasses(_:)` reconciles array length. |
| Hydration writer (coffee cross-log) | `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift:329-333` | `logOneWater` appends `.now`. |
| Stress VM | `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift:943-945` | Pass `log.waterLogTimestamps` into `HydrationInput`. |
| Mock seed | `Cadence/Core/Services/MockDataInjector.swift:216-226` | Generate `waterLogTimestamps` evenly across waking hours for seeded rows. |
| Mock snapshots | `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift` (`waterGlasses` call-sites at lines 132, 168, 226, 276, 321, 549) | Add matching `waterLogTimestamps` per scenario (distributed for "healthy" mocks, clustered late for the "bunching" scenario). |
| Tests / fixtures | `Cadence/Resources/MockData/` (any hydration-related JSON, if present) | Audit-only; extend if any fixture references `waterGlasses`. |

No new files, no new SwiftData entities, no new `Weights` constants.

---

## Implementation Steps

### Phase 1 — Schema & Writers (≈1 hr)

#### 1.1 Add `waterLogTimestamps` to `WellnessDayLog`
- **File:** `Cadence/Models/WellnessDayLog.swift`
- **Action:**
  - Add `var waterLogTimestamps: [Date] = []` right after `var waterGlasses: Int` (line 17).
  - Add matching parameter `waterLogTimestamps: [Date] = []` to the initializer (lines 42-64). Assign in init body.
  - Add a short doc comment: `/// Timestamps of each water-glass increment (count == waterGlasses). Empty for legacy rows — engine falls back to flat scoring.`
- **Why:** Single source of truth on the day row. Default value `[]` makes the SwiftData schema migration automatic — existing rows decode with empty array. (Per CLAUDE.md "PBXFileSystemSynchronizedRootGroup" the file is auto-included; no pbxproj edits.)
- **Dependencies:** None.
- **Risk:** Low. SwiftData property addition with default is non-breaking — same pattern used by `coffeeCups: Int = 0` and `coffeeType: String? = nil` in this same model (lines 32-36).

#### 1.2 Update `WaterDetailView` writers
- **File:** `Cadence/Features + UI/Home/Views/WaterDetailView.swift`
- **Action:** Replace `updateGlasses(_:)` (lines 270-274) with a body that reconciles both fields:
  ```swift
  private func updateGlasses(_ count: Int) {
      let log = fetchOrCreateTodayLog()
      let safe = max(0, count)
      let current = log.waterLogTimestamps
      if safe > current.count {
          // Append now-timestamps for the added glasses
          let additions = Array(repeating: Date(), count: safe - current.count)
          log.waterLogTimestamps = current + additions
      } else if safe < current.count {
          // Drop the most recent entries
          log.waterLogTimestamps = Array(current.prefix(safe))
      }
      log.waterGlasses = safe
      try? modelContext.save()
  }
  ```
- **Why:** Single chokepoint — both `addGlass`, `removeGlass`, and `toggleGlass(at:)` already route through here, so we don't need to touch them. Repeat-append vs. iterative append doesn't matter for the bolus check (all timestamps are within the same UI tick anyway).
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 1.3 Update `HomeView.updateHydrationForToday`
- **File:** `Cadence/Features + UI/Home/Views/HomeView.swift:1159-1170`
- **Action:** Apply the same reconciliation logic before the existing `todayLog.waterGlasses = safeCups` line. Keep the existing `guard todayLog.waterGlasses != safeCups else { return }` early-out — the timestamp array stays in sync because we mutate only when count changes.
- **Why:** This is the Home-screen tile path (separate from WaterDetailView). It also uses absolute count writes.
- **Dependencies:** 1.1.
- **Risk:** Low. Identical pattern to 1.2.

#### 1.4 Update `CoffeeDetailView.logOneWater`
- **File:** `Cadence/Features + UI/Home/Views/CoffeeDetailView.swift:329-333`
- **Action:** Before assigning `log.waterGlasses = min(log.waterGlasses + 1, waterGoal)`, capture the would-be new count; if it differs from the current count (i.e., the clamp didn't no-op), append `.now` to `log.waterLogTimestamps`.
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
- **Why:** This is a cross-feature shortcut. Failing to update timestamps here would produce silent drift between `waterGlasses` and `waterLogTimestamps.count`.
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 1.5 Audit for stragglers
- **Action:** Run `grep -rn 'waterGlasses\s*=' Cadence` and verify the four writers above are the only ones. The grep run during planning found exactly these four (HomeView, WaterDetailView, CoffeeDetailView, plus a `+=` increment site that resolves to the same coffee path). Mocks are handled in Phase 3.
- **Why:** Schema invariant — `waterLogTimestamps.count == waterGlasses` for any non-empty array must hold.
- **Dependencies:** 1.2, 1.3, 1.4.
- **Risk:** Medium — if a future writer is added without updating timestamps, the engine still works (falls back when array is empty), but the silent drift would erode signal quality. Mitigation: a `WellnessDayLog` computed helper (`var hasConsistentWaterTimestamps: Bool`) used in a debug `assert` in `StressViewModel` during development.

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
- **Why:** Empty-array fallback keeps the function pure & testable without a separate "unknown" flag.
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 2.2 Rewrite `hydrationPoints`
- **File:** `Cadence/Core/Services/StressScoring.swift:398-415`
- **Action:** Replace the function with the version below. Also add a `now: Date` parameter and a private helper `maxGlassesInWindow(_:window:)`.

  ```swift
  static func hydrationPoints(input: HydrationInput?, goal: Int, now: Date) -> FactorPoints {
      guard let input = input else { return .none }
      guard input.hasWellnessRow else { return .none }
      let goalSafe = max(goal, 1)
      let r = Double(input.glasses) / Double(goalSafe)

      // Base ratio penalty (unchanged thresholds)
      var pts: Double
      switch r {
      case ..<0.3:    pts = 5
      case 0.3..<0.5: pts = 3
      case 0.5..<0.8: pts = 1
      default:        pts = 0
      }

      // Distribution adjustments — only when we have enough timestamps to be meaningful.
      let ts = input.timestamps
      if ts.count >= 3 {
          // (a) Bolus penalty
          let burst = maxGlassesInWindow(ts, window: 3600)
          if burst >= 6      { pts += 3 }
          else if burst >= 4 { pts += 2 }
          else if burst >= 3 { pts += 1 }

          // (b) Late-bunching penalty
          let cal = Calendar.current
          let lateCount = ts.filter { cal.component(.hour, from: $0) >= 21 }.count
          if input.glasses >= 4,
             Double(lateCount) / Double(input.glasses) >= 0.5 {
              pts += 1
          }

          // (c) Backfill clamp — all glasses in a <10 min span but claiming r ≥ 0.5
          if let lo = ts.min(), let hi = ts.max(), hi.timeIntervalSince(lo) < 600, r >= 0.5 {
              pts = max(pts, 3)
          }
      }

      pts = min(pts, Weights.hydration)
      let detail = "\(input.glasses) of \(goalSafe) glasses"
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
- **Why:** Keeps `Weights.hydration = 5` as the hard cap so total stress envelope is unchanged. Three layered signals catch the three distinct failure modes (binge, late-bunch, backfill). All three skip silently when `ts.count < 3` so the function stays well-behaved for legacy rows and minimal-data days.
- **Dependencies:** 2.1.
- **Risk:** Medium. The thresholds (3/4/6 in 60min, 50% after 21:00, 10-min backfill span, r≥0.5 clamp floor) are judgment calls. Mitigation: write them in one place; auditable; tunable without touching writers.

#### 2.3 Pass `now` from the call site
- **File:** `Cadence/Core/Services/StressScoring.swift:812`
- **Action:** Update the invocation from `hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups)` to `hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups, now: now)`. The surrounding `allFactors(inputs:now:)` (or equivalent — confirm at line 800-815) already has `now` in scope.
- **Why:** The function needs `now` only via the `Calendar.current` calls; the parameter exists for purity even though those `Calendar.current` calls don't strictly require it. Passing `now` matches the convention used by `engagementPenalty(inputs:now:)`.
- **Dependencies:** 2.2.
- **Risk:** Low.

#### 2.4 Build `HydrationInput` in the VM
- **File:** `Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift:942-945`
- **Action:**
  ```swift
  let hydrationInput: StressScoring.HydrationInput? = todayWellness.map { log in
      StressScoring.HydrationInput(
          glasses: log.waterGlasses,
          hasWellnessRow: true,
          timestamps: log.waterLogTimestamps
      )
  }
  ```
- **Why:** Wire the new field. No other VM behavior changes.
- **Dependencies:** 1.1, 2.1.
- **Risk:** Low.

---

### Phase 3 — Mocks & Build Verification (≈45 min)

#### 3.1 `MockDataInjector` — seed plausible timestamps
- **File:** `Cadence/Core/Services/MockDataInjector.swift:216-226`
- **Action:** For each of the 30 seeded `WellnessDayLog` rows, generate `waterLogTimestamps` evenly spaced across the user's waking window (08:00–22:00). Helper:
  ```swift
  private static func spreadTimestamps(count: Int, on day: Date, cal: Calendar) -> [Date] {
      guard count > 0 else { return [] }
      let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
      let span: TimeInterval = 14 * 3600   // 08:00 → 22:00
      return (0..<count).map { i in
          start.addingTimeInterval(span * Double(i) / Double(max(count, 1)))
      }
  }
  ```
  Call: `waterLogTimestamps: spreadTimestamps(count: 3 + (offset % 6), on: startOfDay, cal: cal)`.
- **Why:** Without this, every mocked day has `timestamps.count == 0`, so the distribution penalty never fires in dev — defeats the purpose of mocks.
- **Dependencies:** 1.1.
- **Risk:** Low.

#### 3.2 `StressMockSnapshot` — six existing scenarios
- **File:** `Cadence/Features + UI/Stress/Support/StressMockSnapshot.swift`
- **Action:** For each `waterGlasses:` site (lines 132, 168, 226, 276, 321, 549), set a matching `waterLogTimestamps` array. Use spreadTimestamps for "healthy" scenarios; for the high-stress mock scenarios where waterGlasses is 0 or 1, the array is `[]` or `[oneLateTimestamp]`. Consider adding a *new* scenario `lateBingeHydration` with `waterGlasses: 8, waterLogTimestamps: 8 timestamps clustered between 22:00–22:10` so previews can verify the bolus penalty fires.
  - This requires the snapshot struct to either extend its `WellnessDayLog` construction or — if currently passing only an Int — to attach the timestamps in the `recentWellnessLogs` builder at line 58.
- **Why:** Without this, previews and tests can't exercise the new path.
- **Dependencies:** 1.1.
- **Risk:** Medium — the snapshot file constructs `WellnessDayLog` in multiple places; need to verify each one supplies a timestamps array (or use the default `[]`).

#### 3.3 Build verification — workspace, all four schemes
- **Action:** Run each of the four commands from CLAUDE.md:
  ```bash
  xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build
  xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build
  ```
- **Why:** Per CLAUDE.md, all four must pass. The widget only needs `xcodeproj`; everything else needs `xcworkspace` because of Lottie via CocoaPods.
- **Dependencies:** Phases 1 and 2 complete.
- **Risk:** Low — additive schema change, additive input field. Most likely break is a missing initializer argument in mocks (caught at compile-time).

---

### Phase 4 — Manual Verification (≈20 min, no code)

Smoke-test in the simulator with mock mode ON:

1. **Even-distribution case:** Log 8 glasses one at a time spaced ~30s apart with the simulator clock advanced between taps so timestamps span >1h. Confirm hydration factor reads 0 in StressView.
2. **Bolus case:** Use AppConfig debug to inject a day-row with `waterGlasses=8` and timestamps within a 60-min window. Hydration factor should read +3.
3. **Backfill case:** Tap +1 eight times within 10 seconds. Hydration factor should clamp to ≥3 (not 0). Confirm the user-visible stress score reflects this.
4. **Legacy case:** Manually clear `waterLogTimestamps` on a wellness log via debug menu (if available) or use a pre-migration row. Hydration factor should behave as before (today's flat goal-ratio).

Document any threshold-tuning needed.

---

## Testing Strategy

- **Build verification (required):** 4 schemes per CLAUDE.md command list.
- **Automated tests:** Per CLAUDE.md, test files aren't wired into shared schemes — report any new logic-test files as "unverified automated coverage." Strongly recommend at least a local unit-test file `StressScoringHydrationTests.swift` covering:
  - empty `timestamps` array → exact old behavior
  - `maxGlassesInWindow` correctness on edge cases (0, 1, exactly window-sized gap)
  - bolus thresholds (3, 4, 6 glasses in 60 min)
  - late-bunching trigger / non-trigger boundary
  - backfill clamp lifting r=1.0 score from 0 to 3
- **Manual smoke (required):** Phase 4 above.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Honest backfillers (real intake, late log) get penalized | Phase 5 follow-up: add a per-glass "Consumed at" time picker in `WaterDetailView` so users can timestamp retroactively. Out of scope for this plan but documented as the next iteration. |
| Threshold tuning is judgment-based | All thresholds live in `hydrationPoints` — tunable in one place. Phase 4 manual verification surfaces miscalibration before merging. |
| Schema drift if a future writer forgets timestamps | Debug-only `assert(log.waterGlasses == log.waterLogTimestamps.count)` in `StressViewModel.loadData`, behind `#if DEBUG`. |
| `Calendar.current` in pure function reduces testability | Acceptable — same pattern already used by `engagementPenalty`. If purity becomes a goal, factor calendar into a parameter in a future refactor. |
| Bolus penalty double-counts with engagement nudge | The engagement nudge fires only when `glasses == 0`. The bolus penalty fires when `glasses ≥ 3` in a window. Mutually exclusive by construction. |

---

## Out of Scope (Explicit Non-Goals)

- Adding a "Consumed at" time picker to `WaterDetailView` — flagged as a Phase 5 follow-up.
- Changing `Weights.hydration` or any other weight constant.
- Modifying the engagement `no_water` ramp.
- Migration of historical data — legacy rows already have correct fallback behavior.
- Adding hydration-related symptoms or correlation hooks.

---

## Success Criteria

- [ ] `WellnessDayLog.waterLogTimestamps` exists with default `[]`; existing rows decode cleanly.
- [ ] All four hydration writers keep `waterGlasses == waterLogTimestamps.count` after any mutation.
- [ ] `hydrationPoints` returns identical results to the pre-change implementation when `timestamps` is empty.
- [ ] "8 glasses chugged after 21:00 within 10 minutes" → hydration factor ≥ 3 (was 0).
- [ ] "8 glasses evenly across 08:00–22:00" → hydration factor 0 (unchanged).
- [ ] `Weights.hydration` cap (5 points) still respected in every code path.
- [ ] All 4 build targets pass.
- [ ] Mocks produce non-zero distribution penalties in at least one preview scenario, demonstrating the new path is reachable in dev.
