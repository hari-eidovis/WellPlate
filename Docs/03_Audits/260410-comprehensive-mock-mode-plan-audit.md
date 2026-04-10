# Plan Audit Report: Comprehensive Mock Mode Toggle

**Audit Date**: 2026-04-10
**Plan Version**: `Docs/02_Planning/Specs/260410-comprehensive-mock-mode-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured with good code samples and clear before/after diffs for all 16 steps. The architecture (HealthKitServiceFactory mirroring APIClientFactory) is sound and the scope is well-bounded. However, there are 1 critical bug, 2 high-priority gaps, and 3 medium issues that need resolution before implementation.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. MockDataInjector.inject() guard will always fail after flag merge
- **Location**: Step 11, action 1 — changing guard from `mockDataInjected` to `mockMode`
- **Problem**: The plan's Step 13 (ProfileView onToggle) sets `AppConfig.shared.mockMode = true` BEFORE calling `MockDataInjector.inject(into:)`. Step 11 changes the guard to `guard !AppConfig.shared.mockMode else { return }`. This means the guard immediately fires and injection is skipped — no data is ever injected.
- **Impact**: Mock mode toggle does nothing. SwiftData remains empty. All screens show empty state except HealthKit-backed ones (which get MockHealthKitService data but no SwiftData records).
- **Recommendation**: Two options:
  - **Option A (preferred)**: Remove the guard from `inject()` entirely. Instead, check for existing mock data: `guard (try? context.fetchCount(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.logSource == "mock" }))) == 0 else { return }`. This prevents double-injection without depending on the flag.
  - **Option B**: Set `AppConfig.shared.mockMode = true` AFTER injection succeeds (move the flag set inside `inject()` after `context.save()`). But this means the flag and the data are briefly out of sync.

---

### HIGH (Should Fix Before Proceeding)

#### H1. SleepView.swift has unguarded `HealthKitService.isAvailable` check — plan misses it
- **Location**: Plan Step 15 says StressView needs no changes, but **SleepView** is not mentioned at all
- **Problem**: `SleepView.swift:29` has `if !HealthKitService.isAvailable { unavailableView }`. On Simulator (where `isAvailable` is false), this shows the unavailable view even when mock mode is on. The plan updates SleepViewModel (Step 3) but never touches SleepView itself.
- **Impact**: Sleep tab shows "unavailable" on Simulator in mock mode despite SleepViewModel having mock data ready.
- **Recommendation**: Add a step to update `SleepView.swift:29`:
  ```swift
  // Before:
  if !HealthKitService.isAvailable {
  // After:
  if !HealthKitServiceFactory.isDataAvailable {
  ```
  This mirrors the BurnView fix in Step 10.

#### H2. WellnessDayLog deletion breaks after removing `mockInjectedWellnessLogDates`
- **Location**: Step 2 removes `AppConfig.mockInjectedWellnessLogDates`. Step 11's `deleteAll` section doesn't provide concrete replacement for WellnessDayLog cleanup.
- **Problem**: The current `deleteAll()` uses `mockInjectedWellnessLogDates` (ISO8601 date strings tracked in UserDefaults) to identify and delete WellnessDayLog records. The plan removes this property in Step 2 but Step 11 only provides hand-wavy notes about "date-range-based cleanup" without concrete code.
- **Impact**: WellnessDayLog records are orphaned after toggle-off — they remain in SwiftData forever. On next toggle-on, `injectWellnessLogs` skips those days (it checks for existing logs), so the calendar may show stale mock data.
- **Recommendation**: Either:
  - **Keep `mockInjectedWellnessLogDates`** (rename to `mockInjectedDates` for generality) — it works and is proven.
  - **Or** add a 30-day window deletion that's safe for WellnessDayLog since the injection method already skips days with existing real data:
    ```swift
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
    let wellnessDescriptor = FetchDescriptor<WellnessDayLog>(
        predicate: #Predicate { $0.day >= thirtyDaysAgo }
    )
    // This deletes ALL recent WellnessDayLogs including real ones.
    // Use tracked dates instead if real data safety is needed.
    ```
    The first option is safer.

---

### MEDIUM (Fix During Implementation)

#### M1. Step 11 deletion strategy is inconsistent — some models tracked by UUID, some by date range, some not at all
- **Location**: Step 11, action 4
- **Problem**: The plan proposes three different deletion strategies:
  1. `FoodLogEntry` + `StressReading` — by `logSource`/`source` == "mock" tag (existing, works)
  2. `SymptomEntry` + `AdherenceLog` — by tracked UUIDs in `mockInjectedRecordIDs` (new)
  3. `FastingSession` + `JournalEntry` — by date range (no ID, no tag)
  
  This is complex and the date-range approach (option 3) risks deleting real data.
- **Recommendation**: Add a `source` or `notes` tag to mock-injected `SymptomEntry`, `FastingSession`, `AdherenceLog`, and `JournalEntry` records where possible:
  - `SymptomEntry` has a `notes` field → set to `"[mock]"` during injection, delete where `notes == "[mock]"`
  - `FastingSession` has a `scheduleType` field but that's semantic. Add to notes if available, or keep UUID tracking.
  - `AdherenceLog` has no notes field → UUID tracking is correct
  - `JournalEntry` has a `promptUsed` field → set to `"[mock]"` during injection, delete where `promptUsed == "[mock]"`
  
  This reduces the number of deletion strategies from 3 to 2 (tag-based + UUID-based).

#### M2. InsightEngine `buildWellnessContext()` has a `healthService.isAuthorized` check at line 244 that adds a "missing HealthKit data" quality note
- **Location**: Step 6 / InsightEngine.swift:244
- **Problem**: `if !healthService.isAuthorized { missingCategories.append("HealthKit data") }` — while `MockHealthKitService.isAuthorized` is `true`, the plan doesn't mention this line. If a future refactor changes the mock default, this would silently degrade insights quality in mock mode.
- **Impact**: Low — currently works. But the plan should note it as a verified assumption.
- **Recommendation**: Add a brief note in Step 6 confirming that `MockHealthKitService.isAuthorized` is `true` by default and this line is safe.

#### M3. `MockModeDebugCard` has both `@Binding` and `onChange` for the same property — potential double-trigger
- **Location**: Step 12 code sample
- **Problem**: The `Toggle` is bound to `$isMockMode` (a `@Binding`), and there's an `onChange(of: isMockMode)` that calls `onToggle`. When the toggle changes, SwiftUI fires the binding update AND the onChange. If ProfileView's `@State mockModeEnabled` has any side effects from other `.onChange` handlers, this could double-fire.
- **Impact**: Low risk — the plan removes the old ProfileView `.onChange(of: mockModeEnabled)` handler. But the pattern is fragile.
- **Recommendation**: Consider removing the internal `onChange` from `MockModeDebugCard` and instead pass a simpler callback triggered directly by the Toggle action. Or just document that ProfileView must NOT have a separate `onChange(of: mockModeEnabled)` handler.

---

### LOW (Consider for Future)

#### L1. No comprehensive `mockDataInjected` grep/cleanup verification step
- **Location**: Steps 15-16
- **Problem**: Steps 15-16 are vague "check and verify" steps without concrete actions. The plan should include a final grep to ensure zero `mockDataInjected` references remain.
- **Recommendation**: Add a verification step: `grep -r "mockDataInjected" WellPlate/ --include="*.swift"` must return zero results.

#### L2. No mock mode visual indicator during app runtime
- **Location**: Not in plan
- **Problem**: After restarting with mock mode on, there's no persistent visual cue that the app is running with mock data. A developer might forget and be confused by data.
- **Recommendation**: Consider adding a small "MOCK" badge overlay (like the DEBUG ribbon pattern) — but this can be a V2 polish item.

#### L3. `HealthKitServiceFactory._shared` is a `let` — no way to reset for testing
- **Location**: Step 1 code sample
- **Problem**: `APIClientFactory` has `#if DEBUG` test instance support (`setTestInstance`, `testable`). The plan's `HealthKitServiceFactory` doesn't include this.
- **Recommendation**: Add the same `_testInstance` / `setTestInstance` / `testable` pattern for consistency. Not blocking — can add during implementation if needed.

---

## Missing Elements

- [ ] **SleepView.swift update** — needs `HealthKitServiceFactory.isDataAvailable` guard (see H1)
- [ ] **Concrete WellnessDayLog deletion code** after `mockInjectedWellnessLogDates` removal (see H2)
- [ ] **Concrete `deleteAll` code** for all 4 new model types (Step 11 action 4 is notes, not code)

## Unverified Assumptions

- [ ] `MockHealthKitService.isAuthorized` is `true` by default — **Verified: correct** (line 16 of MockHealthKitService.swift)
- [ ] `MockHealthKitService.requestAuthorization()` is a no-op — **Verified: correct** (empty body, lines 22-24)
- [ ] InsightEngine's `domainsWith2Days >= 2` gate will pass with mock data — **Verified: highly likely** (30 days of food + wellness + stress + HK sleep + HK steps = 5 domains)
- [ ] StressMockSnapshot.default has sleep data — **Unverified**: plan assumes `sleepHistory` is populated. Should confirm `StressMockSnapshot.default.sleepHistory` is non-empty.

## Questions for Clarification

1. Should `MockDataInjector.inject()` set the `mockMode` flag itself (after success), or should ProfileView set it before/after calling inject? The current plan has ProfileView setting it before, which causes C1.
2. Is it acceptable for the 30-day date-range deletion approach to delete real `FastingSession`/`JournalEntry` records? Or must all deletion be tag-safe?

## Recommendations

1. **Fix C1 first** — the injection guard bug is a show-stopper. Simplest fix: have `inject()` check for existing mock records instead of the flag.
2. **Add SleepView step** — one-line change, same pattern as BurnView Step 10.
3. **Keep `mockInjectedWellnessLogDates`** (possibly rename to `mockInjectedDates`) rather than removing it — it's the safest deletion mechanism for WellnessDayLog.
4. **Consolidate deletion strategy** — prefer tag-based deletion (using `notes`/`promptUsed` fields) over UUID tracking or date-range where possible.
5. **Add the final grep verification step** to ensure no `mockDataInjected` references survive.
