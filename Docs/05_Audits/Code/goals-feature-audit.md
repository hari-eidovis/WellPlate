# Plan Audit Report: Goals Feature Implementation

**Audit Date**: 2026-03-08
**Plan Location**: `.cursor/plans/goals_feature_implementation_7f2621a0.plan.md`
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is well-structured with clear phasing and covers the main goal categories (nutrition, hydration, exercise, sleep). However, it has several technical feasibility gaps — most critically around how ViewModels that lack ModelContext access will receive UserGoals, missed hardcoded goal sites in HomeView, SwiftData array storage limitations, and an inconsistent ViewModel pattern choice (`@Observable` vs existing `ObservableObject`). These must be resolved before implementation.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **BurnViewModel and SleepViewModel have no ModelContext access**
   - Location: Phase 4b — "Wire UserGoals into BurnViewModel / SleepViewModel"
   - Problem: Both `BurnViewModel` and `SleepViewModel` are initialized with only a `HealthKitServiceProtocol` parameter. They have zero SwiftData dependency today. The plan says "Read `UserGoals.activeEnergyGoalKcal`" and "Read `UserGoals.sleepGoalHours`" but does not explain **how** — there is no ModelContext available in these VMs.
   - Impact: Cannot compile. The wiring approach is undefined for 2 of the 3 main ViewModel consumers.
   - Recommendation: Choose one of:
     - **(A)** Pass the goal value (Double/Int) into the VM's `init` from the View that creates it (BurnView, MainTabView). The View can use `@Query` to fetch `UserGoals`.
     - **(B)** Add a `ModelContext` parameter to these VMs (matches StressViewModel pattern).
     - **(C)** Use a lightweight `GoalsProvider` protocol / shared service instead of direct SwiftData access in every VM.
   - Option A is simplest and least invasive.

2. **SwiftData does not natively support `[CustomCodable]` arrays on iOS 17**
   - Location: Phase 1 — `var workoutGoals: [DayWorkoutGoal]`
   - Problem: SwiftData's `@Model` macro on iOS 17 does not support arrays of custom `Codable` structs as persistent properties. This will crash at runtime or fail to compile depending on the OS version.
   - Impact: App crash / build failure for the workout-per-day feature.
   - Recommendation: Store as `Data` (JSON-encoded) with a computed accessor:
     ```swift
     var workoutGoalsData: Data?

     var workoutGoals: [DayWorkoutGoal] {
         get { /* decode from workoutGoalsData */ }
         set { /* encode to workoutGoalsData */ }
     }
     ```
     Or use 7 individual `Int` properties (`workoutMon`, `workoutTue`, ...) which is simpler and avoids serialization entirely.

3. **HomeView `wellnessRings` hardcoded goals not listed in plan**
   - Location: Phase 4b — files to update table
   - Problem: `HomeView.wellnessRings` (lines 163-198) contains hardcoded `"/ 2000"`, `"/ 8 cups"`, `"/ 45 min"`. This is a primary, user-facing goal display and is completely missing from the plan's update list.
   - Impact: User changes goals in GoalsView but the Home dashboard rings still show old hardcoded values.
   - Recommendation: Add HomeView to the Phase 4b table. HomeView needs `@Query var userGoals: [UserGoals]` (or equivalent) to populate the wellness rings dynamically.

---

### HIGH (Should Fix Before Proceeding)

4. **`@Observable` vs `ObservableObject` pattern inconsistency**
   - Location: Phase 2 — GoalsViewModel
   - Problem: Plan says GoalsViewModel should be `@Observable`, but every existing ViewModel in the codebase (`HomeViewModel`, `BurnViewModel`, `SleepViewModel`, `StressViewModel`, `WellnessCalendarViewModel`) uses `ObservableObject` with `@Published`. Mixing observation patterns in the same codebase leads to confusion about when to use `@StateObject` vs `@State`.
   - Impact: Developer confusion, inconsistent binding patterns across views.
   - Recommendation: Use `ObservableObject` with `@Published` to match the existing codebase. If a migration to `@Observable` is desired, do it as a separate refactor across all VMs.

5. **Widget goals not refreshed when user changes goals**
   - Location: Phase 4c — Widget sync
   - Problem: The plan says "Goals update in widget only on next `syncWidgetData()` call — acceptable since goal changes are infrequent." But `syncWidgetData()` (called `refreshWidget(for:)` in code) only runs on food log events. If a user changes their calorie goal from 2000 to 1800, the widget shows the old goal until the next food is logged — which could be hours or the next day.
   - Impact: Stale/incorrect goal display on the widget after goal changes.
   - Recommendation: GoalsViewModel should call a widget refresh after any goal mutation. Extract the widget-sync logic into a shared helper callable from both HomeViewModel and GoalsViewModel.

6. **`DayWorkoutGoal` missing `id` property**
   - Location: Phase 1 — DayWorkoutGoal struct
   - Problem: The struct conforms to `Identifiable` but the code snippet shows no `id` property.
   - Impact: Compile error.
   - Recommendation: Add `var id: Int { dayOfWeek }` as a computed property, since day-of-week is unique within the 7-entry array.

7. **No input validation specified**
   - Location: Phase 2 — GoalsView
   - Problem: No minimum/maximum bounds defined for any goal field. User could set calories to 0 or negative, cup size to 0 mL, sleep goal to 24 hours, etc.
   - Impact: Division-by-zero in progress calculations (`caloriesProgress`, `fraction`, `sleepGoalProgress`), nonsensical UI, potential crashes.
   - Recommendation: Define validation ranges in the plan:
     - Calories: 500–10,000
     - Water cup size: 50–1000 mL
     - Water daily cups: 1–20
     - Macros (protein/carbs/fat): 0–1000g
     - Active energy: 50–5000 kcal
     - Workout duration: 0–480 min
     - Sleep: 3.0–14.0 hours
   - Enforce via clamped steppers / slider ranges in the UI, and a `clampedDefaults()` method on UserGoals.

---

### MEDIUM (Fix During Implementation)

8. **Missing: Steps daily goal**
   - Problem: The app tracks steps in `WellnessDayLog.steps` and `BurnViewModel.todaySteps`, but `UserGoals` has no `stepsGoal` property. Steps are a fundamental fitness metric.
   - Recommendation: Add `var dailyStepsGoal: Int` (default: 10,000) to `UserGoals` and include it in the Exercise section of GoalsView.

9. **`HydrationCard` call-site in HomeView hardcodes `totalGlasses: 8`**
   - Problem: HomeView line 66 passes `totalGlasses: 8`. Even if the UserGoals model stores `waterDailyCups`, this call-site won't use it unless updated.
   - Recommendation: Add to Phase 4b. HomeView must pass `userGoals.waterDailyCups` to `HydrationCard(totalGlasses:)`.

10. **HomeView `hydrationGlasses` is `@State` — not persisted**
    - Problem: `@State private var hydrationGlasses: Int = 5` in HomeView is not connected to `WellnessDayLog.waterGlasses`. This is a pre-existing bug, but the goals feature will make it more visible since we're adding a cup-size display.
    - Recommendation: Note as out-of-scope but flag for follow-up. The hydration state should read/write `WellnessDayLog` to persist across launches.

11. **`WidgetFoodData` default/empty constructors have hardcoded goals**
    - Location: `SharedFoodData.swift` — `empty` and `sampleData` static properties
    - Problem: These fallback values (e.g., `calorieGoal: 2000`) won't reflect user goals. When the widget can't read data, it falls back to these.
    - Recommendation: The fallback is acceptable for truly empty states, but document that `sampleData` is preview-only and `empty` is the "no data logged yet" state. The real widget data path must always use goals from AppGroup.

12. **ProfileView needs access to UserGoals for the summary subtitle**
    - Problem: The Goals card shows "2000 cal · 8 cups · 45 min" but the plan doesn't specify how ProfilePlaceholderView gets the UserGoals data.
    - Recommendation: Add `@Query var userGoals: [UserGoals]` in ProfilePlaceholderView, with a computed property like `var currentGoals: UserGoals { userGoals.first ?? UserGoals.defaults() }`.

---

### LOW (Consider for Future)

13. **No onboarding flow for first-time goal setup**
    - Problem: New users get silent defaults. They may never discover the Goals screen.
    - Recommendation: Consider a one-time prompt or badge on the Profile tab for users who haven't customized goals.

14. **No goal-change history or analytics**
    - Problem: When a user changes their calorie goal from 2000 to 1800, historical progress views still compare old data against the new goal.
    - Recommendation: Future consideration — store goal snapshots per time period for accurate historical comparisons.

15. **`DailyGoals` struct could be eliminated**
    - Problem: Once `UserGoals` exists, `DailyGoals` is a redundant intermediary. The plan adds an `init(from: UserGoals)` bridge, but long-term this is unnecessary indirection.
    - Recommendation: Acceptable for this phase to minimize blast radius. Flag for future cleanup.

---

## Missing Elements

- [ ] HomeView `wellnessRings` hardcoded goals (CRITICAL — not in plan)
- [ ] HomeView `HydrationCard(totalGlasses: 8)` call-site update
- [ ] Steps goal in UserGoals model
- [ ] Input validation ranges for all goal fields
- [ ] Widget refresh triggered from GoalsViewModel on goal change
- [ ] How ProfilePlaceholderView fetches UserGoals for the summary
- [ ] How BurnViewModel/SleepViewModel receive goal values (injection strategy)
- [ ] Test strategy (unit tests for UserGoals defaults, validation, singleton helper)

## Unverified Assumptions

- [ ] SwiftData supports `[Codable]` array persistence on the target iOS version — Risk: **High** (likely does NOT work on iOS 17)
- [ ] SwiftData singleton pattern won't create race-condition duplicates on concurrent access — Risk: **Medium**
- [ ] Adding a new `@Model` to an existing container requires no migration — Risk: **Low** (this is correct for additive changes)

## Performance Considerations

- [ ] `@Query` for `UserGoals` in every View that needs goals (HomeView, ProfileView, ProgressInsightsView, FoodJournalView) — acceptable since it's a single-row table, but consider a shared `@Query` at a higher level passed down via environment or init params
- [ ] The singleton fetch helper should cache the result in the ViewModel rather than re-fetching on every property access

## Recommendations

1. **Resolve the ModelContext injection strategy** for BurnViewModel and SleepViewModel before coding. Option A (pass goal values from View) is recommended.
2. **Use `Data` storage** for `workoutGoals` or flatten to 7 individual properties to avoid SwiftData `[Codable]` issues.
3. **Add HomeView** to the files-to-update list — it's the most prominent consumer of hardcoded goals.
4. **Use `ObservableObject`** for GoalsViewModel to match the existing codebase pattern.
5. **Define validation ranges** for every goal field and enforce them in the UI layer.
6. **Trigger widget refresh** from GoalsViewModel when any goal changes.
7. **Add a test strategy section** covering: singleton creation/fetch, defaults, validation clamping, DailyGoals bridge initializer.

---

## Sign-off Checklist

- [ ] All CRITICAL issues resolved (3 found)
- [ ] All HIGH issues resolved or accepted (4 found)
- [ ] Input validation defined
- [ ] Widget refresh on goal change planned
- [ ] ViewModel injection strategy decided
- [ ] SwiftData array storage approach confirmed
