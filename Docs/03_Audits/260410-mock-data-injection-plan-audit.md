# Plan Audit Report: Mock Data Injection System

**Audit Date**: 2026-04-10
**Plan Version**: `Docs/02_Planning/Specs/260410-mock-data-injection-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured and the core architecture (SwiftData injection + MockHealthKitService swap) is sound. The existing `HealthKitServiceProtocol` seam and `StressMockSnapshot` make this achievable with moderate effort. However, the audit found **1 critical issue** (missing service call site), **3 high issues** (SleepView unused, `#if DEBUG` factory design, StressInsightService omission), and several medium items that should be addressed before implementation.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: StressInsightService not covered in plan
- **Location**: Missing from "Affected Files" and "Implementation Steps"
- **Problem**: `StressInsightService` takes `HealthKitServiceProtocol` with default `HealthKitService()` (line 42 of `StressInsightService.swift`). It's instantiated in two places:
  - `HomeView.swift:61` — `@StateObject private var insightService = StressInsightService()`
  - `HomeAIInsightView.swift:630` — `let svc = StressInsightService()`
  These will create real `HealthKitService()` instances even when mock data is injected, causing the AI insight to fail or show real (empty) data instead of mock data.
- **Impact**: Home AI Insight card shows "Insufficient data" even when 30 days of mock data is injected.
- **Recommendation**: Add `StressInsightService` to the same auto-detect pattern — its init should check `AppConfig.shared.mockDataInjected` and use `MockHealthKitService` when active. Both creation sites (`HomeView`, `HomeAIInsightView`) will then automatically use mock data.

---

### HIGH (Should Fix Before Proceeding)

#### H1: `HealthKitServiceFactory` as `#if DEBUG` only is fragile
- **Location**: Step 1.2 — `HealthKitServiceFactory.swift`
- **Problem**: Making the entire factory `#if DEBUG` means every call site needs conditional compilation:
  ```swift
  #if DEBUG
  if AppConfig.shared.mockDataInjected { ... use factory ... }
  #endif
  // real code path
  ```
  This duplicates logic at every call site and creates maintenance burden. The plan's revised approach (Step 2.4 revised) puts the check inside VM inits, which is better, but the factory file itself being `#if DEBUG` means it can't be referenced from VM init code that also runs in Release.
- **Impact**: Compilation errors if any non-DEBUG code path accidentally references `HealthKitServiceFactory`.
- **Recommendation**: Either (a) make `HealthKitServiceFactory` available in all builds but have it always return `HealthKitService()` in Release (the `#if DEBUG` goes inside the method, not around the file), or (b) put the entire mock-detection logic inside each VM's init behind `#if DEBUG` without referencing a factory type at all. Option (b) is cleaner and matches the plan's revised Step 2.4 approach — in which case remove the factory file entirely and inline the pattern.

#### H2: SleepView is not navigated to in the actual app
- **Location**: Steps 2.5, 2.8 — modifications to `SleepView.swift` and `SleepViewModel.swift`
- **Problem**: `SleepView()` is only instantiated in `#Preview`. The actual app navigates to `SleepDetailView` from StressView (line 160 of `StressView.swift`). No navigation destination points to `SleepView`.
- **Impact**: Modifying `SleepView` is wasted effort. The sleep data that users actually see comes from `StressView` → `SleepDetailView`, which gets data from `StressViewModel` (already mock-aware).
- **Recommendation**: Remove SleepView/SleepViewModel from the plan. The sleep data path is already covered by StressViewModel's existing mock infrastructure. If SleepView is dead code, note it but don't spend effort wiring it.

#### H3: `#if DEBUG` around `mockDataInjected` property
- **Location**: Step 1.1 — `AppConfig.mockDataInjected`
- **Problem**: The plan puts `mockDataInjected` behind `#if DEBUG`. But the revised VM init pattern (Step 2.4) also needs to be behind `#if DEBUG`. If a VM's init references `AppConfig.shared.mockDataInjected` without `#if DEBUG`, it won't compile in Release. This is technically correct but means every VM init has `#if DEBUG` blocks, which is noisy.
- **Impact**: Verbose conditional compilation throughout VMs.
- **Recommendation**: Make `mockDataInjected` available in all builds (always returns `false` in Release, like existing `mockMode` pattern). This eliminates `#if DEBUG` in every VM init:
  ```swift
  var mockDataInjected: Bool {
      get {
          #if DEBUG
          return UserDefaults.standard.bool(forKey: Keys.mockDataInjected)
          #else
          return false
          #endif
      }
      set { ... }
  }
  ```
  This exactly mirrors how `mockMode` already works in `AppConfig`.

---

### MEDIUM (Fix During Implementation)

#### M1: WellnessDayLog collision handling is underspecified
- **Location**: Step 1.3 — MockDataInjector
- **Problem**: Plan says "skip injection for any day that already has a WellnessDayLog record." But `WellnessDayLog.day` has `@Attribute(.unique)` — inserting a duplicate will crash or silently fail depending on SwiftData's conflict resolution. The plan doesn't specify how to check for existing records before inserting.
- **Recommendation**: Before injecting WellnessDayLog records, fetch all existing WellnessDayLog records for the 30-day range and skip those dates. Use a `FetchDescriptor` with a date range predicate.

#### M2: Mock data quantity and realism
- **Location**: Step 1.3 — Data generation
- **Problem**: The plan specifies "2-4 entries per day" for FoodLogEntry but doesn't provide the actual meal data. The `StressMockSnapshot.default` already has 3 food entries for today only. The plan needs 30 days × 3 meals = ~90 entries with varied food names and realistic macros.
- **Recommendation**: Define a pool of ~20 meal templates (name, macros, serving size) and cycle through them to build 30 days of varied entries. Use the existing 3 entries in `StressMockSnapshot` as a starting pattern.

#### M3: FoodLogEntry `logSource` field may not filter uniquely
- **Location**: Step 1.3 — deletion strategy
- **Problem**: The plan uses `logSource == "mock"` to identify mock FoodLogEntry records. But `logSource` is also used for real entries ("barcode", "voice", "text"). If `logSource` is `nil` for some real entries, the predicate is safe. But if any future code path sets `logSource = "mock"` for non-mock entries, deletion would be destructive.
- **Recommendation**: This is acceptable for DEBUG-only code. Just ensure the `MockDataInjector` always sets `logSource = "mock"` on injected records. Add a code comment noting this convention.

#### M4: View refresh after inject/delete
- **Location**: Testing Strategy — "views need the HealthKit service to be swapped"
- **Problem**: After toggling `mockDataInjected`, VMs that are already instantiated still hold a reference to the old `HealthKitService()`. SwiftData `@Query` views will auto-refresh, but BurnViewModel/StressViewModel etc. won't automatically re-fetch with the new service.
- **Recommendation**: The plan mentions NotificationCenter as mitigation but doesn't include it as a step. Options:
  1. After inject/delete, post a notification that VMs observe to trigger re-fetch (complex, touches many VMs).
  2. **Simpler**: Accept that after inject/delete, the user must switch tabs or the VMs re-load on `onAppear`. Since `@StateObject` VMs persist in the SwiftUI view lifecycle, they'll call `requestPermissionAndLoad()` again on `onAppear`. This naturally works if the user navigates away and back. Document this as expected behavior.
  3. **Simplest**: Show an alert after inject/delete saying "Restart the app to see changes" and rely on the persisted flag. On next launch, VMs init with the correct service.

#### M5: `StressMockSnapshot` singleton is shared across VMs
- **Location**: Steps 1.4, 1.5 — snapshot extension
- **Problem**: `.default` is a static let computed once. Adding `waterHistory` and `exerciseMinutesHistory` properties changes the struct definition. All existing call sites (`MainTabView`, `StressView` previews) will need updating if you add required init parameters.
- **Recommendation**: Add the new arrays as properties with default values in the struct, or add them to `makeDefault()` factory. Since all usage goes through `.default`, just extend `makeDefault()` and add the properties. No call site changes needed if you use the struct's memberwise init (which is internal).

#### M6: Plan mentions `BurnView` as navigation destination from Home but not from Stress
- **Location**: Step 2.8
- **Problem**: `BurnView()` is created from `HomeView.swift:223` as a `navigationDestination`. The plan modifies `BurnView` but doesn't verify all navigation paths. Currently there's only one creation site (HomeView).
- **Recommendation**: Verified — `BurnView()` is only instantiated from `HomeView`. No additional wiring needed.

---

### LOW (Consider for Future)

#### L1: Widget extension doesn't share mock state
- **Location**: Non-Goals section acknowledges this
- **Problem**: `WellPlateWidget` reads HealthKit independently. Mock data won't appear in widgets.
- **Recommendation**: Out of scope. Acceptable for DEBUG-only feature. If needed later, use App Group UserDefaults.

#### L2: No undo/confirmation for inject/delete
- **Location**: Step 3.1 — MockDataDebugCard
- **Problem**: Tapping "Inject" or "Clear" takes immediate effect. No confirmation dialog.
- **Recommendation**: Add a `.confirmationDialog` for the "Clear" action (inject is safe since it only adds data). Low priority since this is a developer tool.

---

## Missing Elements

- [ ] `StressInsightService` — not listed as affected file, not wired for mock (**CRITICAL**)
- [ ] No implementation step for `HomeAIInsightView.swift:630` (`StressInsightService()` creation) 
- [ ] No step to handle "restart required" UX after inject/delete (M4)
- [ ] The plan's revised Step 2.4 approach (VM auto-detect in init) contradicts Step 1.2 (separate factory file) — need to decide which pattern to use and remove the other

## Unverified Assumptions

- [ ] `FoodLogEntry.logSource` is reliably `nil` for all user-created entries — **Risk: Low** (checked: voice/text/barcode are the only values set)
- [ ] `WellnessDayLog` unique constraint on `day` uses `Calendar.current.startOfDay()` consistently — **Risk: Low** (verified in init)
- [ ] `StressReading.source` field is reliably `"auto"` or `"manual"` for real entries, never `"mock"` — **Risk: Low** (verified in model)

## Questions for Clarification

1. Should the plan use a factory file (`HealthKitServiceFactory`) or inline the mock-detection in each VM init? The plan describes both patterns (Steps 1.2 and 2.4 revised) which are contradictory.
2. Should inject/delete require an app restart for HK-backed screens, or should we implement a notification-based refresh?
3. Is `SleepView` dead code that should be removed, or is it planned for future use?

## Recommendations

1. **Fix C1**: Add `StressInsightService` to the plan with the same auto-detect init pattern
2. **Fix H1+H3**: Drop the standalone `HealthKitServiceFactory.swift` file. Instead, use `AppConfig.mockDataInjected` (always-available, returns `false` in Release) and inline the mock detection in each VM init. This is cleaner and matches the revised Step 2.4 approach already in the plan.
3. **Fix H2**: Remove SleepView/SleepViewModel from the plan. Sleep data is covered via StressViewModel.
4. **Address M4**: Recommend "restart app" approach after inject/delete for simplicity. Show alert from ProfileView.
5. **Address M5**: Extend `StressMockSnapshot` struct with new properties and update `makeDefault()`. No call site changes needed since `.default` is the only usage.
