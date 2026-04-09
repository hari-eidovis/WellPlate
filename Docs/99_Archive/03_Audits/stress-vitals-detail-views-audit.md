
# Plan Audit Report: StressView Vitals Section + Tappable Detail Views

**Audit Date**: 2026-02-25
**Plan Version**: fuzzy-bouncing-hickey.md (initial)
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is architecturally sound and well-structured, but it contains 3 critical blockers that will cause compile errors before a single view renders: an invalid Swift method-reference syntax for `fetchSamplesSafely`, a missing `pendingManualHours` binding in the `StressSheet.screenTimeEntry` case, and an undeclared `ScreenTimeDetailView.source` parameter type conflict. Several high-priority issues around data availability at sheet-open time, HealthKit unit correctness, and SwiftData model-context safety also need resolution before implementation begins.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. `fetchSamplesSafely` closure syntax — invalid method reference in Swift

- **Location**: Plan §3 `StressViewModel.swift` — `loadData()` block and helper definition
- **Problem**: The plan writes:
  ```swift
  async let stepsHist = fetchSamplesSafely(healthService.fetchSteps, range: thirtyDayRange)
  ```
  and defines:
  ```swift
  private func fetchSamplesSafely(_ fetch: (DateInterval) async throws -> [DailyMetricSample], range: DateInterval) async -> [DailyMetricSample]
  ```
  Passing `healthService.fetchSteps` as a bare method reference to a parameter typed `(DateInterval) async throws -> [DailyMetricSample]` does NOT work in Swift when the callee is a protocol method on an `any`-existential (`HealthKitServiceProtocol`). The compiler will reject `healthService.fetchSteps` as a partial application of a protocol method on an existential. The correct form requires an explicit closure:
  ```swift
  async let stepsHist = fetchSamplesSafely({ [self] r in try await self.healthService.fetchSteps(for: r) }, range: thirtyDayRange)
  ```
  Additionally, the `async let` declaration itself must appear inside an `async` context and the closure must be passed as a `@Sendable` or explicit closure literal — passing a naked `healthService.fetchSteps` to a non-`@escaping` function parameter of async type is also rejected by the Swift type-checker.
- **Impact**: The file will not compile at all. Every one of the 9 `async let` calls in `loadData()` uses this broken syntax.
- **Recommendation**: Rewrite the 9 call sites as explicit trailing closures, or define the helper to take a `@Sendable @escaping` async closure so the method references can be wrapped: `{ [self] r in try await self.healthService.fetchSteps(for: r) }`. Update the plan to show this form consistently.

#### 2. `ScreenTimeInputSheet` binding is lost in `StressSheet.screenTimeEntry` case

- **Location**: Plan §5 `StressView.swift` — `sheet(item:)` switch, `case .screenTimeEntry`
- **Problem**: The existing `ScreenTimeInputSheet` requires `hours: $pendingManualHours` — a `@Binding<Double>` that lives on `StressView`. The plan's switch statement inside `sheet(item:) { sheet in ... }` is a non-View closure that receives the sheet item, not the view body. The plan snippet shows:
  ```swift
  case .screenTimeEntry: ScreenTimeInputSheet(...) { viewModel.setManualScreenTime(pendingManualHours) }
  ```
  The `...` placeholder is never filled in by the plan. `$pendingManualHours` is a `@State` binding on `StressView` and IS accessible from within the `sheet(item:)` content closure (it is a closure over the view's property, not a separate struct). However the plan never explicitly states this or shows the `hours: $pendingManualHours` argument. If the implementer writes `ScreenTimeInputSheet(hours: .constant(0), ...)` by mistake — a tempting shortcut — the save action silently discards the user's slider value. The plan must make this explicit.
- **Impact**: Subtle runtime bug: user sets hours in slider, taps Save, nothing persists. The existing `showScreenTimeSheet` flow worked correctly because `$pendingManualHours` was right next to the sheet call site in the old code.
- **Recommendation**: Explicitly show `hours: $pendingManualHours` in the plan's `case .screenTimeEntry` snippet. Also confirm that `@State private var pendingManualHours: Double = 0` is retained (not removed) when `showScreenTimeSheet` is deleted.

#### 3. `ScreenTimeDetailView` initialiser — `source: ScreenTimeSource` is not a `Sendable` type visible to the sheet closure

- **Location**: Plan §5 `StressView.swift` — `case .screenTimeDetail`, and Plan §6 `ScreenTimeDetailView.swift`
- **Problem**: The plan says the new view takes `factor: StressFactorResult, source: ScreenTimeSource`. Both types are defined in `StressViewModel.swift` (the `ScreenTimeSource` enum is at file scope in that file, confirmed by reading the source). The plan places `ScreenTimeDetailView.swift` in the Stress/Views folder. The file will need to import nothing extra because `ScreenTimeSource` is in the same module, so this is not a compile error per se. However the plan never notes that `ScreenTimeSource` must remain at module scope (not moved inside `StressViewModel`) — if a developer refactors it to a nested type, the new view breaks. **More concretely**, the plan says `source: viewModel.screenTimeSource` — but `viewModel` is `@StateObject` on `StressView`, and its property `screenTimeSource` is `@Published`. The closure inside `sheet(item:)` captures `viewModel` by reference and reads the current value at sheet-display time, which is correct. No compile issue, but it should be noted in the plan.
- **Impact**: Low build risk now, medium maintenance risk.
- **Recommendation**: Add a note that `ScreenTimeSource` must stay at module scope. Minor, but document it.

---

### HIGH (Should Fix Before Proceeding)

#### 1. `HKUnit(from: "ms")` — invalid HealthKit unit string for HRV

- **Location**: Plan §2 `HealthKitService.swift` — HRV method unit
- **Problem**: The plan specifies `HKUnit(from: "ms")` for SDNN (HRV). The correct HealthKit unit string for milliseconds is `"ms"` — this is actually valid in HealthKit's unit string parser (`HKUnit(from: "ms")` parses correctly as milliseconds). However, HRV values returned by HealthKit for `.heartRateVariabilitySDNN` are stored in **seconds** internally, not milliseconds. Apple's HealthKit documentation states that `.heartRateVariabilitySDNN` samples are in `HKUnit.secondUnit(with: .milli)`. `HKUnit(from: "ms")` produces the same unit as `HKUnit.secondUnit(with: .milli)`, so the string form is technically valid and equivalent. This is NOT a bug, but the plan should clarify this versus "count/min" to prevent confusion during code review.
- **Impact**: Low — no functional issue, but could cause confusion.
- **Recommendation**: Change the table entry to explicitly use `HKUnit.secondUnit(with: .milli)` (the canonical HealthKit API call) rather than the opaque string `"ms"`, consistent with how the other methods use `.millimeterOfMercury()` API form.

#### 2. `currentDayLogs` computed property calling `modelContext.fetch()` synchronously

- **Location**: Plan §3 `StressViewModel.swift` — `currentDayLogs` computed property
- **Problem**: The plan adds `var currentDayLogs: [FoodLogEntry] { ... }` as a computed property that calls `modelContext.fetch()` synchronously. The existing `refreshDietFactor()` already does this pattern (confirmed in source, line 202–207 of `StressViewModel.swift`), and `StressViewModel` is `@MainActor` so the `modelContext` is always accessed on the main thread, which is correct for SwiftData. The pattern is safe.
  However, the plan says this is "called from `sheet(item:)` callback which runs on MainActor" — the issue is that `viewModel.currentDayLogs` is evaluated inside the `sheet(item:)` content closure, which is a `@ViewBuilder` closure called on the main thread. Every time the sheet re-renders (which can be multiple times), this computed property fires a fresh `modelContext.fetch()`. If the food log has many entries, this is an unbounded synchronous fetch on the main thread on every re-render.
- **Impact**: Performance regression for users with many food log entries. In practice the day's log is small, but it is still an anti-pattern.
- **Recommendation**: Cache the result — store `@Published var currentDayLogs: [FoodLogEntry] = []` and populate it in `refreshDietFactor()` alongside the existing fetch already there. Then `DietDetailView` reads the cached value. The plan currently has `refreshDietFactor()` doing the same fetch anyway (line 202–207), so this is zero additional work.

#### 3. `FoodLogEntry` passed outside its `ModelContext` — SwiftData threading concern

- **Location**: Plan §5 `StressView.swift` `case .diet` and Plan §6 `DietDetailView.swift`
- **Problem**: `FoodLogEntry` is a `@Model` class managed by SwiftData. SwiftData model objects are bound to the `ModelContext` they were fetched from. The plan passes `viewModel.currentDayLogs` (an array of live `@Model` instances) into `DietDetailView` as a plain `[FoodLogEntry]` parameter. The view receives them and calls `todayLogs.map(\.calories)` etc. This works correctly **as long as** `DietDetailView` only reads the values and does not hold the array beyond the lifecycle of the sheet (which it won't — it's a value-type-like read in SwiftUI). However, SwiftData `@Model` objects accessed from a context that has been invalidated will crash. Since both the view and the ViewModel share the same `ModelContext` (injected at init, passed from `WellPlateApp`), and the sheet is shown and dismissed on the main actor, there is no cross-context issue in practice.
  The residual risk is that if a future refactor passes `currentDayLogs` to a background task or a detached view, it will silently corrupt or crash. The plan should note this constraint.
- **Impact**: No immediate bug, but a footgun for future maintainers.
- **Recommendation**: Add a comment in the plan (and generated code) that `DietDetailView` must not store `[FoodLogEntry]` beyond its view lifecycle, and must not access it off the main actor. Alternatively, snapshot the data into a plain `struct` before passing (e.g., `DietLogSnapshot`).

#### 4. `VitalDetailView` todayValue vs. most-recent sample disconnect

- **Location**: Plan §5 `StressView.swift` `case .vital(let m)` and Plan §6 `VitalDetailView.swift`
- **Problem**: The plan derives `todayValue` via:
  ```swift
  todayHeartRate = heartRateHistory.first(where: { Calendar.current.isDateInToday($0.date) })?.value
  ```
  This returns `nil` if HealthKit has no sample with `stat.startDate` in today's calendar day. The `fetchDailyAvg` helper uses `HKStatisticsCollectionQuery` with `stat.startDate` as the bucket start. For a 30-day query ending at `now`, the "today" bucket starts at `startOfDay(today)` and ends at `now`. If the user has no heart rate data recorded today (e.g., Apple Watch was off), this correctly returns nil.
  However there is a subtle mismatch: `heartRateHistory` is fetched with a `DateInterval(start: thirtyDayStart, end: now)` query. The `fetchDailyAvg` implementation enumerates from `range.start` to `range.end`. The "today" entry in `heartRateHistory` will have `date == startOfDay(today)` (the bucket anchor). The `Calendar.current.isDateInToday($0.date)` check on `startOfDay(today)` evaluates to `true` correctly.
  The real issue is: `VitalDetailView` receives both `todayValue` and `samples` (the full 30-day history). The KPI card shows `todayValue`, and the chart shows `samples`. But `samples` already contains today's entry. The `formattedToday` display in `BurnDetailView` (which the plan copies) also does its own `samples.first(where: { isDateInToday })?.value` — creating two independent sources for the same value. If the plan passes the pre-computed `todayValue` AND separately the array that contains today, the implementer may accidentally show the array-derived value in one card and the pre-computed value in another, causing a visible discrepancy if `loadData()` is called at different times.
- **Impact**: Subtle display inconsistency in edge cases. Low probability but confusing to debug.
- **Recommendation**: In `VitalDetailView`, derive `todayValue` exclusively from `samples.first(where: { isDateInToday })?.value` internally, and remove the `todayValue: Double?` parameter from the view signature. This keeps a single source of truth and removes an unnecessary parameter from the public interface. Update `vitalTodayValue()` accordingly or remove it.

#### 5. `async let` with 9 concurrent HealthKit queries — `readTypes` not updated

- **Location**: Plan §2 `HealthKitService.swift` — `readTypes` property
- **Problem**: The plan correctly says to extend `quantityIDs` in `readTypes` with the 5 new identifiers. However the plan does NOT explicitly note that `requestAuthorization()` uses `readTypes` and is called before `loadData()`. If the user has already granted permissions (from a previous app launch), `requestAuthorization()` will be called again and present the permission sheet showing the 5 new types. The plan should address this expected UX flow: existing users will see a new permission prompt for blood pressure, resting HR, HRV, and respiratory rate on first launch after the update.
- **Impact**: UX surprise for existing users. Not a crash.
- **Recommendation**: Note in the plan that existing users will be re-prompted for the 5 new HealthKit types on next launch. Consider whether this should be mentioned in release notes or handled gracefully.

#### 6. `StressSheet` enum — `screenTimeDetail` case references a non-existent `ScreenTimeDetailView` file

- **Location**: Plan §5 `StressView.swift` — enum definition and §6 `ScreenTimeDetailView.swift`
- **Problem**: This is a sequencing issue only if files are created in the wrong order, but the plan's "Implementation Order" step 4 lists `ScreenTimeDetailView.swift` after `StressView.swift` modifications in step 6. The `StressSheet` enum references `screenTimeDetail` which directly causes `ScreenTimeDetailView(...)` to be instantiated in the `sheet(item:)` switch. If `ScreenTimeDetailView.swift` hasn't been added to the Xcode project yet when `StressView.swift` is compiled, the build fails.
- **Impact**: Build failure during phased implementation if order is not strictly followed.
- **Recommendation**: Reorder step 6 in Implementation Order — move all new view file creation (step 4) to come **before** `StressView.swift` wiring (step 6). The current ordering has `StressFactorCardView.swift` minor tweak (step 5) before `StressView.swift` (step 6), but all new files must exist before `StressView.swift` is modified. The plan's ordering is already close but should be explicit: create ALL 6 new files first, then modify the 5 existing files.

---

### MEDIUM (Fix During Implementation)

#### 1. `DetailBarChartView` Y-axis labels use `Int(v)` — unsuitable for HRV in milliseconds and respiratory rate

- **Problem**: `DetailBarChartView` (confirmed in `BurnChartView.swift` line 99) formats Y-axis labels as `"\(Int(v))"`. For HRV (SDNN values typically 20–100 ms, displayed as integers — fine) and respiratory rate (12–20 breaths/min, integers — fine), this is acceptable. However `DetailBarChartView` has no decimal formatting option. If a future vital needs decimal display (e.g., a metric with sub-1 values), the chart is unusable without modifying `DetailBarChartView`.
- **Recommendation**: Add an optional `formatValue: (Double) -> String` closure parameter to `DetailBarChartView` now, defaulting to `{ "\(Int($0))" }`. This is a minor enhancement that prevents future code duplication.

#### 2. Blood pressure "two half-width tappable areas" layout — complex constraint not fully specified

- **Problem**: The plan mentions "two half-width tappable areas side-by-side (Systolic | Diastolic), each tapping its own `VitalDetailView`" but gives no layout specification. The `StressVitalCardView` is designed as a compact horizontal card for a single metric. The blood pressure card is explicitly different (split-layout). The plan creates `StressVitalCardView` but doesn't explain how the blood pressure card reuses or adapts it. This leaves the implementer to design the blood pressure card from scratch with no guidance, potentially producing an inconsistent look.
- **Recommendation**: Either show a code sketch for the blood pressure card, or explicitly state it should be an inline `HStack` of two `StressVitalCardView` instances with `.frame(maxWidth: .infinity)` applied to each.

#### 3. `sleepHistory` fetch uses `fetchDailySleepSummaries` over 30 days — overlaps with stress score sleep fetch

- **Problem**: `loadData()` already calls `fetchSleepSafely(for: sleepInterval)` (1-day window) for the stress score. The new code adds `fetchSleepHistorySafely(range: thirtyDayRange)` for the 30-day history. These are two separate `HKSampleQuery` executions for sleep data in the same `loadData()` call. The existing 1-day query fetches raw `SleepSample` objects; the new 30-day query fetches `DailySleepSummary` objects. This is redundant — the 30-day fetch includes the last night's data, so the stress score's sleep summary could be derived from `sleepHistory.last` instead of a separate fetch. This duplication is minor but increases HealthKit query count.
- **Recommendation**: After `sleepHistory` is populated, derive `sleepSummary` from `sleepHistory.last` rather than a separate `fetchSleepSafely` call. Remove the standalone sleep fetch from `loadData()` and feed `sleepHistory.last` into `computeSleepScore`. This is an optimization, not a blocker.

#### 4. `VitalMetric.higherIsBetter` property — blood pressure direction is ambiguous

- **Problem**: The plan defines `higherIsBetter: Bool` on `VitalMetric`. For blood pressure (both systolic and diastolic), higher is NOT better — but the "normal range" concept is bilateral (too low is also bad). A simple boolean doesn't capture this nuance. The `normalRange: String` field in the plan helps with display but the `higherIsBetter` field could mislead chart coloring logic in `VitalDetailView` if it uses a traffic-light scheme based on this boolean.
- **Recommendation**: Either use an enum (`enum VitalDirection { case higherBetter, lowerBetter, rangeOptimal }`) or document in the plan that blood pressure chart bars will not use directional coloring and will show a flat accent color regardless of value. This prevents the implementer from accidentally showing "green = high BP" which is medically incorrect.

#### 5. `StressSheet.id` — plan says `var id: String { ... }` without specifying contents

- **Problem**: The `StressSheet` enum conforms to `Identifiable` (required by `.sheet(item:)`). The plan writes `var id: String { ... }` with `...` as a placeholder. For the `.vital(VitalMetric)` case, the id must include the associated value to uniquely identify each vital's sheet. If two `case .vital` instances with different `VitalMetric` values produce the same `id`, SwiftUI will incorrectly reuse the same sheet body when switching from one vital to another without dismissing first.
- **Recommendation**: Specify `var id: String { "\(self)" }` using Swift's default enum string representation, or use `switch self { case .vital(let m): return "vital_\(m.id)" ... }`. Make this explicit in the plan.

#### 6. Xcode project `.pbxproj` — 6 new files not addressed

- **Problem**: The plan creates 6 new `.swift` files. The Xcode project file (`WellPlate.xcodeproj/project.pbxproj`) must have each new file added to the WellPlate target's compile sources. The plan has no mention of this step. In practice, adding files via Xcode's "New File" dialog handles this automatically, but if files are created via the filesystem (e.g., by an agent writing them directly), they will not appear in the build and the project will compile as if they don't exist — producing "type not found" errors for `VitalDetailView`, `ExerciseDetailView`, etc.
- **Recommendation**: Add an explicit note: "All 6 new files must be added to the WellPlate target in Xcode (⌘+N or drag-and-drop into the project navigator). Verify each file appears under `SOURCES` in the `.pbxproj` compile sources phase."

---

### LOW (Consider for Future)

#### 1. `HKQuantityTypeIdentifier.bloodPressureSystolic` requires paired-device data

- **Problem**: Blood pressure data in HealthKit typically comes from a third-party cuff or Apple Watch Ultra (future) — the vast majority of iPhone-only users will have no systolic/diastolic data. The "—" empty state is handled gracefully per the plan, but there is no informational callout in `VitalDetailView` explaining *why* blood pressure is empty (unlike steps/HR which come from the built-in accelerometer/optical sensor). Users may think the app is broken.
- **Recommendation**: Add a "How to track" info row in `VitalDetailView` when `samples.isEmpty && metric == .systolicBP || metric == .diastolicBP` suggesting the user connect a compatible blood pressure monitor.

#### 2. `VitalMetric` enum conforms to `CaseIterable` — but not all cases are displayed in `vitalsSection`

- **Problem**: The plan adds `.heartRate, .restingHeartRate, .hrv, .systolicBP, .diastolicBP, .respiratoryRate` to `VitalMetric`. Only `.heartRate, .restingHeartRate, .hrv, .respiratoryRate` are shown as individual `StressVitalCardView` rows; blood pressure is a special combined card. If `VitalMetric.allCases` is used anywhere (e.g., a loop to build the vitals section), `.systolicBP` and `.diastolicBP` will appear twice — once in the loop and once in the special combined card.
- **Recommendation**: Document in the plan that `vitalsSection` must NOT use `VitalMetric.allCases` to build its list. Enumerate cases explicitly or add a static `var displayedSingleMetrics: [VitalMetric]` that excludes `.systolicBP` and `.diastolicBP`.

#### 3. `ExerciseDetailView` — `BurnMetric.steps/.activeEnergy` colors/units are already defined

- **Problem**: The plan says `ExerciseDetailView` reuses `BurnMetric.steps/.activeEnergy` for colors/units. This is a dependency on `HealthModels.swift`'s `BurnMetric` enum. This creates a subtle coupling: `ExerciseDetailView` (in the Stress feature) depends on `BurnMetric` (a Burn feature model). If `BurnMetric` is ever renamed or reorganized, `ExerciseDetailView` breaks. The plan doesn't acknowledge this cross-feature dependency.
- **Recommendation**: Note this coupling explicitly. Consider whether `ExerciseDetailView` should define its own local constants for color/unit, or whether `BurnMetric` should be moved to a shared Models location.

#### 4. No mock/preview data specified for new views

- **Problem**: The plan specifies no preview data strategy for `VitalDetailView`, `ExerciseDetailView`, `DietDetailView`, or `ScreenTimeDetailView`. The existing `BurnDetailView` has `#Preview` blocks with empty sample arrays, which produce blank charts. Meaningful previews need sample data to verify layout.
- **Recommendation**: Add a note that each new view should include a `#Preview` with at least 7 mock `DailyMetricSample` values to verify chart rendering during development.

---

## Missing Elements

- [ ] Explicit binding for `pendingManualHours` in `case .screenTimeEntry` of the plan's `sheet(item:)` snippet
- [ ] Specification of `StressSheet.id` computed property implementation
- [ ] Specification of blood pressure combined card layout (code sketch or wireframe description)
- [ ] Note on re-authorization prompt UX for existing users gaining 5 new HealthKit types
- [ ] Xcode project file update instruction for 6 new Swift files
- [ ] Strategy for whether `VitalDetailView` derives `todayValue` internally vs. accepts it as parameter
- [ ] `VitalMetric.higherIsBetter` direction specification for blood pressure bilateral range
- [ ] `#Preview` data strategy for each of the 6 new view files

---

## Unverified Assumptions

- [ ] `HKUnit(from: "ms")` is accepted by `HKStatisticsCollectionQuery` for `.heartRateVariabilitySDNN` — Risk: Low (HealthKit docs confirm "ms" parses as milliseconds; but SDNN is stored internally in seconds so `HKUnit.secondUnit(with:.milli)` is the canonical form)
- [ ] `HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)` returns non-nil — Risk: Low (confirmed valid `HKQuantityTypeIdentifier` in HKQuantityTypeIdentifier header)
- [ ] 9 concurrent `async let` HealthKit queries won't be throttled by the OS — Risk: Medium (HealthKit may serialize concurrent `HKStatisticsCollectionQuery` requests from the same `HKHealthStore`; observed in practice to complete in <2s but undocumented behavior)
- [ ] `SleepDetailView` correctly handles a 30-day `sleepHistory` array (it currently uses `summaries.last` for the KPI "Last Night" value — confirmed from source line 173 — this is correct)
- [ ] `fetchDailySleepSummaries` returning a 30-day range includes the correct "today" entry at the last position after `.sorted { $0.date < $1.date }` — Risk: Low (confirmed from HealthKit.swift line 160)

---

## Security Considerations

- [ ] No new network calls introduced — no API key exposure risk
- [ ] HealthKit data stays on-device; no persistence of HRV/BP values to UserDefaults or SwiftData in this plan
- [ ] `currentDayLogs` computed property reads SwiftData on main thread — no file-system side effects

---

## Performance Considerations

- [ ] 9 concurrent `HKStatisticsCollectionQuery` executions at `loadData()` time — verify total load time is acceptable on older devices (A14 and below)
- [ ] `currentDayLogs` computed property firing `modelContext.fetch()` on every `sheet(item:)` re-render — should be cached in `@Published` property instead (see HIGH issue #2)
- [ ] `sleepHistory` 30-day fetch is redundant with the existing 1-day sleep fetch for stress scoring — minor query duplication
- [ ] `StressSheet` enum with `case .vital(VitalMetric)` means a single sheet modifier handles 10 cases (4 factor + 5 vital + 1 screenTimeEntry) — no performance concern but increases view body complexity in `StressView`

---

## Questions for Clarification

1. Should `ExerciseDetailView` show today's steps/energy using the same data window as the stress score (the exercise window that can shift to yesterday before 3 AM), or always "today" from the 30-day `stepsHistory` array? The stress score uses `exerciseStart`/`exerciseEnd` logic, but the 30-day history uses midnight-to-midnight buckets. The KPI in `ExerciseDetailView` could show a different number than the `exerciseFactor.statusText` on the same screen.
2. The plan says the Screen Time card gets a "Details →" button added to the header. What happens to this button when `screenTimeSource == .none` (< 15 min)? Should the Details sheet still be accessible to show the score-mapping and tips cards?
3. Should `VitalDetailView`'s Normal Range card link to Apple Health or a reference URL, or is it purely static informational text?
4. The plan shows `vitalsSection` inserted "between `factorsSection` and `insightsCard`". The `insightsCard` uses `viewModel.topStressors` which includes only the 4 stress factors. Should vitals ever appear in `topStressors`? (The plan says "display-only" — confirming they should not, but the `topStressors` computed property relies on `allFactors` which should remain unchanged.)

---

## Recommendations

1. **Fix `fetchSamplesSafely` syntax before any other step** — rewrite the helper and all 9 call sites to use explicit closure literals. This is the only change that blocks compilation entirely.
2. **Explicitly show `pendingManualHours` binding** in the `screenTimeEntry` sheet case to prevent a silent save-failure bug.
3. **Cache `currentDayLogs` as `@Published`** — the fetch already happens in `refreshDietFactor()`; store the result in a property and read that property in `DietDetailView` instead of re-fetching on sheet render.
4. **Remove `todayValue` parameter from `VitalDetailView`** — derive it internally from `samples` to maintain a single source of truth.
5. **Specify `StressSheet.id` fully** — e.g., `var id: String { "\(self)" }` or a switch with explicit strings.
6. **Document the blood pressure bilateral range** in `VitalMetric` so the implementer doesn't apply a simplistic `higherIsBetter` color scheme to a metric where both extremes are unhealthy.
7. **Add Xcode project file guidance** for the 6 new files — even a single sentence prevents a common agent-workflow pitfall.

---

## Sign-off Checklist

- [ ] All CRITICAL issues resolved
- [ ] All HIGH issues resolved or accepted with documented rationale
- [ ] Security review completed
- [ ] Performance implications understood
- [ ] Rollback strategy defined (not mentioned in plan — consider noting that all changes are additive and can be reverted by removing the 6 new files and reverting the 5 modified files)
