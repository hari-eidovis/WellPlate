# Plan Audit Report: Home Screen UX Update

**Audit Date**: 2026-04-09
**Plan Version**: `Docs/02_Planning/Specs/260409-home-screen-ux-update-plan.md`
**Strategy Source**: `Docs/02_Planning/Specs/260409-home-screen-ux-update-strategy.md`
**Auditor**: audit agent
**Verdict**: CONDITIONAL PASS

---

## Executive Summary

The plan is well-structured, thorough, and faithful to the strategy in all major respects. Source code cross-checking confirms that most model fields, service APIs, and component signatures are correctly referenced. However, three HIGH-severity issues were found: a wrong file path for `HomeViewModel.swift`, a broken coffee-increment logic in `QuickStatsRow` (the Step 1.2 code contradicts the W4 watchout fix), and a `@Published` tuple that will likely cause a Swift compiler warning or error depending on the Xcode version. Several MEDIUM-severity inaccuracies in line numbers and small logic gaps were also identified. None require a plan rewrite, but the implementer must resolve the HIGH issues before proceeding.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

None.

---

### HIGH (Should Fix Before Proceeding)

#### H1: Wrong file path for `HomeViewModel.swift` in Step 2.1

- **Location**: Plan Step 2.1 header
- **Problem**: The plan states the file is at `WellPlate/Features + UI/HomeViewModels/HomeViewModel.swift`. The actual path is `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` (note: `Home/ViewModels`, not `HomeViewModels`).
- **Impact**: An implementer following the path literally will not find the file and may create a duplicate in the wrong directory. Because the project uses `PBXFileSystemSynchronizedRootGroup`, a file placed at the wrong path would be auto-included, creating a duplicate symbol build error.
- **Actual code reference**: Verified by reading `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` directly. The Architecture table at the top of the plan correctly shows `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` — the discrepancy is only in Step 2.1's header.
- **Recommendation**: Correct Step 2.1 file path to `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`.

---

#### H2: Coffee increment logic in Step 1.2 (`QuickStatsRow`) contradicts W4 fix

- **Location**: Plan Step 1.2, `QuickStatsRow` layout spec for the coffee tile's `onIncrement` closure
- **Problem**: The `onIncrement` closure written in the Step 1.2 code block is:
  ```swift
  onIncrement: {
      SoundService.playConfirmation()
      if coffeeCups == 0 && coffeeType == nil {
          onCoffeeFirstCup()
      } else {
          coffeeCups += 1
      }
  }
  ```
  This fires `onCoffeeFirstCup()` *without* first incrementing `coffeeCups`. Watchout W4 explicitly identifies this as wrong: `HomeView.onChange(of: coffeeCups)` only fires when `newCups > oldCups`, so if `coffeeCups` is never incremented, the picker closes but the cup count is never persisted.

  W4 provides the correct fix — increment first, then call `onCoffeeFirstCup()` — but the Step 1.2 code block was never updated to match. The implementer will be given contradictory instructions: one block that is wrong and a watchout section that corrects it.

- **Impact**: On first coffee cup add, the cup count stays at 0 after the picker closes (or increments to -1 via the `onChange` defensive decrement path). Coffee logging breaks silently on first cup.
- **Recommendation**: Update the Step 1.2 coffee `onIncrement` closure to the W4-corrected version:
  ```swift
  onIncrement: {
      let wasFirst = coffeeCups == 0 && coffeeType == nil
      SoundService.playConfirmation()
      coffeeCups += 1
      if wasFirst { onCoffeeFirstCup() }
  }
  ```
  Remove the duplicate/conflicting code block. Keep W4 for explanation but mark the Step 1.2 code as the canonical implementation.

---

#### H3: `@Published` on a labeled tuple type is unreliable in Swift / Combine

- **Location**: Plan Step 2.1, `@Published var yesterdayStats: (water: Int, coffee: Int, steps: Int)`
- **Problem**: Swift's `@Published` property wrapper works on any type, but `Combine`'s `ObservableObject` synthesis emits a change notification when the property is *replaced*. Labeled tuples in Swift are not `Equatable` by synthesis — they require explicit `==` conformance, which is impossible on anonymous tuples. More critically, in Xcode 15+ with Swift 5.9+, `@Published` on a tuple with labels has been observed to produce compiler warnings or fail to synthesize the publisher correctly in some configurations.

  The plan acknowledges this in W1 and provides a struct fallback — but the primary code in Step 2.1 still uses the tuple form, which means the implementer must make a judgment call at implementation time rather than following the plan unambiguously.

- **Impact**: Possible `@Published` warning or error depending on Swift/Xcode version. If the `ObservableObject` `objectWillChange` publisher does not fire on tuple assignment, `HomeView` will never re-render after `loadYesterdayStats()` completes, making all delta badges permanently empty.
- **Recommendation**: Replace the primary Step 2.1 code with the struct form (already shown as fallback in W1). The tuple form should be the fallback comment, not the primary. Struct form:
  ```swift
  struct YesterdayStats: Equatable {
      var water: Int = 0
      var coffee: Int = 0
      var steps: Int = 0
  }
  @Published var yesterdayStats = YesterdayStats()
  ```
  Update all downstream references (`foodJournalViewModel.yesterdayStats.water`, `.coffee`, `.steps`) — they remain identical in dot-notation.

---

### MEDIUM (Fix During Implementation)

#### M1: Line number references in plan do not match actual file

- **Location**: Multiple steps throughout Phase 3–5
- **Problem**: Several specific line numbers cited in the plan are inaccurate when checked against the actual source files:
  - Step 3.1 states "Current signature (line 25–29)" for `WellnessRingsCard`. Actual struct declaration starts at line 25 but the closing `onRingTap` property is at line 29 — this is coincidentally correct, but the plan's "WellnessRingButton current struct declaration (line 78)" is verified correct (line 78 in actual file).
  - Step 3.1 states "lines 88–139" for the `WellnessRingButton` body — actual `VStack(spacing: 10)` starts at line 88 but the last `}` closing the button body is at line 142, not 139.
  - Step 3.1 states the delta badge should append "after the VStack(spacing: 2) block (lines 130–138)" — actual `VStack(spacing: 2)` starts at line 130 and closes at line 138, which matches.
  - Step 4.1 states "current `mealList` body (lines 46–77)" — actual `mealList` property declaration is at line 46 and the closing `}` is at line 77. This matches.
  - Step 5.2 states "Remove line 52: `@State private var dragLogProgress`" — actual line 51 in the file.
  - Step 5.2 states "Remove lines 164–169" for the blur/overlay — actual lines are 164–169 in the read file (`.blur` at 164, `.overlay` block through 169). This matches.
  - Step 5.3 states "Current header (lines 333–403)" — actual `homeHeader` computed property starts at line 333 and closes at line 403. This matches.
  - Step 5.4 states "Current `greeting` computed property (lines 547–554)" — actual lines 547–554 confirmed correct.
  - Step 2.1 states "Current end of file: line 285" — actual last line of `HomeViewModel.swift` is line 285 (closing `}`). This matches.
- **Impact**: Minor navigational friction for the implementer. No build risk if the implementer reads the actual file content rather than trusting line numbers blindly. `dragLogProgress` being on line 51 (not 52) is the only divergence with practical consequence.
- **Recommendation**: Update line numbers for `dragLogProgress` from "line 52" to "line 51". For all other line numbers, add a note that "line numbers are approximate — locate by content pattern."

---

#### M2: `WellnessRingDestination` is not `Hashable` — plan requires it as dictionary key

- **Location**: Plan Step 3.1 and Step 5.8
- **Problem**: The plan introduces `var deltaValues: [WellnessRingDestination: Int]?`. Using `WellnessRingDestination` as a `Dictionary` key requires it to conform to `Hashable`. Looking at the actual `WellnessRingsCard.swift`, `WellnessRingDestination` conforms to `Identifiable` (`var id: Self { self }`) but is NOT explicitly declared `Hashable`.

  In Swift, enums without associated values automatically get `Hashable` synthesis. `WellnessRingDestination` has no associated values (`case calories, water, exercise, stress`), so `Hashable` should be synthesized automatically. However, the plan does not call this out, and the `Identifiable` conformance via `var id: Self { self }` requires `Self` to be `Hashable` for the `Hashable`-based `Identifiable` default — so it should already work. The risk is low but unverified.

- **Impact**: If `Hashable` synthesis fails for any reason (e.g., a future associated value is added), the dictionary will not compile.
- **Recommendation**: Add `Hashable` to the `WellnessRingDestination` declaration as part of Step 3.1: `enum WellnessRingDestination: Identifiable, Hashable`. This is one word and eliminates ambiguity.

---

#### M3: `foodJournalViewModel` is named `HomeViewModel` — `prefillFromEntry` references `foodDescription` / `servingSize` fields that exist

- **Location**: Plan Step 2.1, `prefillFromEntry` method
- **Problem**: The plan states `prefillFromEntry` sets `foodDescription` and `servingSize`. These field names are verified in the actual `HomeViewModel.swift` (lines 8–9: `@Published var foodDescription`, `@Published var servingSize`). However, the plan calls the ViewModel `foodJournalViewModel` throughout (which matches the `@StateObject` declaration in `HomeView` — line 56). This is consistent and correct.

  The actual concern: when `onAddAgain` calls `prefillFromEntry(entry)` and then `showLogMeal = true`, `FoodJournalView` is presented as a `NavigationStack` destination. `FoodJournalView` reads from `foodJournalViewModel` via parameter injection (`FoodJournalView(viewModel: foodJournalViewModel)`). The pre-fill must happen *before* the destination is pushed — the plan correctly sets `prefillFromEntry` first, then `showLogMeal = true`. This ordering is correct.

  However, there is a subtle race: `showLogMeal = true` triggers a navigation push on the same run-loop iteration. `FoodJournalView` may read `foodDescription` before SwiftUI processes the state change from `prefillFromEntry`. In practice, since all state is `@MainActor` and `@Published`, SwiftUI batches both mutations in one render cycle, so this should work. But it is not called out in the watchouts.

- **Impact**: Low risk in practice due to SwiftUI's state batching. Worth verifying during manual testing.
- **Recommendation**: Add a note in W4 or a new W10 acknowledging the pre-fill + navigation ordering and confirming it has been tested.

---

#### M4: `QuickStatsRow` lacks the `onCoffeeFirstCup` call to also handle sound correctly

- **Location**: Plan Step 1.2 W4 corrected code block (plan page ~1270)
- **Problem**: In the W4-corrected version, `SoundService.playConfirmation()` is called before the first-cup path check. But for the first cup case, `HomeView.onChange(of: coffeeCups)` fires with `newCups == 1`, which executes `updateCoffeeForToday(cups: 1, type: nil)` and then sets `activeSheet = .coffeeTypePicker`. This means the picker fires and `showCoffeeWaterAlert` does NOT fire (matching the existing `CoffeeCard` behavior). The sound from `QuickStatsRow` fires before the picker appears. This is a minor UX inconsistency — sound plays but picker overwrites the interaction context immediately.

  The existing `CoffeeCard.addCup()` calls `SoundService.playConfirmation()` inside `addCup()` too, so the behavior is consistent with the current pattern. No functional bug.

- **Impact**: None — consistent with existing behavior. No fix required.
- **Recommendation**: No change needed. Noting for implementer awareness.

---

#### M5: `contextualBarState` in Step 5.1 uses `expectedCupsDeficit()` but the threshold condition is `behind > 1`, inconsistent with strategy's `behind > 1`

- **Location**: Plan Step 5.1, `contextualBarState` computed property; strategy "expectedCupsByNow()" section
- **Problem**: The strategy specifies: "If `behind > 1`, show `waterBehindPace` state." The plan correctly uses `if behind > 1`. However, the `expectedCupsDeficit()` helper returns `max(0, behind)`, so `behind == 1` (exactly one cup behind) will NOT trigger the bar state. This is intentional per the strategy, but it may surprise users who are exactly one cup behind and see no nudge. The strategy document is the authoritative source and the plan faithfully implements it.

  One minor discrepancy: the strategy document says `expectedCupsByNow()` returns `behind = expected > hydrationGlasses ? expected - hydrationGlasses : 0`, then "If `behind > 1`". The plan's `expectedCupsDeficit()` computes identically. No bug.

- **Impact**: None — this is a product decision documented in the strategy.
- **Recommendation**: No change needed.

---

#### M6: `WellnessDayLog.steps` is `Int` (non-optional), but plan uses `todayWellnessLog?.steps` as `Int?`

- **Location**: Plan Step 1.2 (`QuickStatsRow` props: `let steps: Int?`), Step 5.6 (`steps: todayWellnessLog?.steps`)
- **Problem**: `WellnessDayLog.steps` is declared as `var steps: Int` (non-optional, default `0`) in the actual model. When the plan passes `steps: todayWellnessLog?.steps`, the optional chaining on `todayWellnessLog?` produces `Int?` (the whole expression is optional because `todayWellnessLog` itself is `WellnessDayLog?`). So `todayWellnessLog?.steps` correctly produces `Int?` — nil when there is no log for today, and a non-nil `Int` when the log exists. This is correct Swift behavior.

  The only issue is the plan's description: "If no data (`steps == nil`), show `—`". When today's log exists but steps haven't been written by HealthKit yet, `steps` will be `0` (not `nil`). The tile will show "0" or display using the formatted number `"0"` rather than `"—"`. The `stepsText` computed var in Step 1.2 checks `guard let s = steps, s > 0 else { return "—" }` — so a `steps` value of 0 also shows `"—"`. This is correct behavior and is handled, but the explanation "If no data (`steps == nil`)" is slightly misleading: `"—"` shows for both nil (no log) and 0 (log exists, no steps yet).

- **Impact**: No build risk. Slight documentation inaccuracy.
- **Recommendation**: Update description to "If no data (`steps == nil` or `steps == 0`), show `—`".

---

#### M7: Plan says `FoodLogEntry.day` is used for `todayFoodLogs` filter but implementation uses `$0.day` — verify the field is `startOfDay`

- **Location**: Plan Step 5.1, `todayFoodLogs` computed property
- **Problem**: The plan computes:
  ```swift
  allFoodLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
  ```
  From the actual `FoodLogEntry.swift`, `day: Date` is stored as `startOfDay(date)` in `HomeViewModel.logFood`: `let day = Calendar.current.startOfDay(for: date)`. The `isDate(_:inSameDayAs:)` check is therefore correct and will match today's entries.

  But the strategy document's code snippet for `todayFoodLogs` uses `Calendar.current.isDate($0.day, inSameDayAs: Date())`, while the existing `HomeView.todayCalories` uses `$0.day == todayStart` (direct equality with `todayStart = Calendar.current.startOfDay(for: Date())`). Both approaches are correct but inconsistent.

- **Impact**: No functional issue. Minor inconsistency in approach.
- **Recommendation**: For consistency with existing `HomeView` patterns, use `allFoodLogs.filter { $0.day == todayStart }` (already defined as a `private var` in `HomeView`). This is a one-line simplification.

---

#### M8: `ContextualActionBar` does not handle `onAddCoffee` sound — but plan's Step 1.3 trailingActions calls `SoundService.playConfirmation()` internally

- **Location**: Plan Step 5.9, `onAddCoffee` interaction discussion; Step 1.3 `trailingActions` code block
- **Problem**: The plan correctly explains in Step 5.9 that the bar handles sound internally (Option A). Step 1.3 shows `trailingActions` calling `SoundService.playConfirmation()` for the coffee button before invoking `onAddCoffee()`. This is correct. However, Step 5.9's `onAddCoffee` closure in `HomeView` also checks `todayWellnessLog?.coffeeType == nil` for the first-cup path. The `ContextualActionBar` is not passed `coffeeType` or `coffeeCups` — it only receives callbacks.

  The `onAddCoffee` closure in Step 5.9 is:
  ```swift
  onAddCoffee: {
      if coffeeCups == 0 && todayWellnessLog?.coffeeType == nil {
          activeSheet = .coffeeTypePicker
      } else {
          coffeeCups += 1
      }
  }
  ```
  This does NOT increment `coffeeCups` before calling the picker (unlike the W4 fix for `QuickStatsRow`). The same W4 bug pattern applies here: if the picker is shown via `ContextualActionBar` without incrementing first, `HomeView.onChange(of: coffeeCups)` won't fire, and the first cup won't be persisted.

- **Impact**: HIGH-adjacent — same root cause as H2. First-cup coffee logging from `ContextualActionBar` will silently fail to persist.
- **Recommendation**: Apply the same W4 fix to the `onAddCoffee` closure in Step 5.9:
  ```swift
  onAddCoffee: {
      let wasFirst = coffeeCups == 0 && todayWellnessLog?.coffeeType == nil
      coffeeCups += 1
      if wasFirst { activeSheet = .coffeeTypePicker }
  }
  ```
  This mirrors the existing `HomeView.onChange(of: coffeeCups)` logic where `newCups == 1` triggers the picker path *after* the binding mutation.

  This is a separate bug from H2 (which is in `QuickStatsRow`) — both the bar's coffee button and the tile's coffee button have this issue.

---

#### M9: `ZStack` becomes unnecessary after removing `DragToLogOverlay` blur/overlay — plan does not clean it up

- **Location**: Plan Step 5.2, result after removal
- **Problem**: After removing the `.blur` and `.overlay` modifiers from the `ScrollView`, the `ZStack` wrapper around the `ScrollView` in `HomeView.body` serves no purpose. The post-Step-5.2 code shown in the plan keeps `ZStack { ScrollView { ... } }`. An empty `ZStack` with a single child adds a small but unnecessary view layer.
- **Impact**: No build error. Negligible performance impact.
- **Recommendation**: In Step 5.2, note that the `ZStack` can be removed, leaving `ScrollView` as the direct child of `NavigationStack`. This is optional but improves cleanliness. If the `ZStack` is kept for future extensibility, add a comment explaining why.

---

### LOW (Consider for Future)

#### L1: `greeting` hardcodes the user name "Alex"

- **Location**: Plan Step 5.4, new `greeting` computed property
- **Problem**: The existing `greeting` returns strings like "Good Morning, Alex". The plan extends this but keeps the hardcoded name. There is no user name stored in `UserGoals` or any model. This was already present before this update, so the plan is not introducing a regression, but it is an opportunity that could have been noted.
- **Recommendation**: Track as a future improvement. Out of scope for this update.

---

#### L2: `ContextualActionBar` visual container uses `.appShadow(radius: 16, y: -4)` but the helper signature requires explicit `y:` with no default

- **Location**: Plan Step 1.3, `barContent` background spec
- **Problem**: `AppColor.swift` defines `func appShadow(radius:x:y:)` with `x: CGFloat = 0` and `y: CGFloat` (no default). The plan correctly uses `.appShadow(radius: 16, y: -4)`. This is valid.
- **Impact**: None. Verified correct.
- **Recommendation**: No change needed. Verified clean.

---

#### L3: No migration of `WellnessCalendarView` trigger from header to Profile tab is planned in this update

- **Location**: Strategy "Non-Goals" section; Plan Step 5.3
- **Problem**: The plan removes the `calendar` header button but leaves `showWellnessCalendar` as dead state with no replacement trigger. The strategy explicitly defers the Profile tab relocation. The plan acknowledges this. Users who knew the calendar shortcut will lose access with no alternative until a future update.
- **Impact**: Feature regression for calendar access. Accepted as a known non-goal.
- **Recommendation**: Add a `// TODO: F-next — re-home WellnessCalendarView to Profile tab` comment in the code where `showWellnessCalendar` is kept as dead state.

---

#### L4: `ContextualActionBar` `.safeAreaInset` shadow direction uses `y: -4` (upward shadow) which may appear odd in dark mode

- **Location**: Plan Step 1.3, bar container visual spec
- **Problem**: `.appShadow(radius: 16, y: -4)` creates a shadow projecting upward (toward screen content). In dark mode, `Color(.label).opacity(0.08)` will be near-white, creating a white glow above the bar. This is the intended visual behavior (strategy confirms "shadow upward"), but may look unexpected depending on `systemBackground` vs `secondarySystemBackground` contrast. Not a correctness issue.
- **Recommendation**: Verify visually in both light and dark mode during testing. Consider adjusting opacity to 0.05 for dark mode if the glow is distracting.

---

## Missing Elements

- [ ] **W4 fix not applied to `ContextualActionBar.onAddCoffee`**: The plan correctly fixes the first-cup coffee bug in `QuickStatsRow` (W4) but misses the identical bug in the `ContextualActionBar`'s `onAddCoffee` closure (Step 5.9).
- [ ] **No mention of removing dead `insightService.bindContext`** after `ContextualActionBar` takes over the "See Summary → AI Insight" trigger: `insightService.bindContext(modelContext)` remains in `onAppear`. This is correct to keep; just not worth a watchout flag.
- [ ] **No explicit test case for the `goalsCelebration` bar state**: The manual verification section (Step 5, item 1) says "Log 8 water glasses (all rings complete) → goalsCelebration", but `wellnessCompletionPercent` depends on 4 rings (calories, water, exercise, stress), not just water. Reaching 100% requires all 4 rings at 100% — this is hard to simulate manually. A test path for this state is needed.
- [ ] **No test case for `ContextualActionBar` with no `modelContext` (cold launch before `onAppear`)**: `contextualBarState` reads `todayWellnessLog` which queries `allWellnessDayLogs`. On first install with no data, this is an empty array — the bar should show `defaultActions` or `logNextMeal`. This is not an issue per the logic, but no test step confirms it.

---

## Unverified Assumptions

- [ ] **`WellnessRingDestination` is `Hashable`** — Risk: Low. Auto-synthesized for plain enum, but not explicitly declared. Step 3.1 should add `Hashable` to the enum declaration.
- [ ] **`todayWellnessLog?.steps` accurately reflects today's HealthKit step count** — Risk: Medium. The HealthKit → `WellnessDayLog.steps` sync path is not visible in the audited files. If the write is not happening (or is delayed), the activity tile will always show `—`. Plan acknowledges this in W9 but does not suggest a fallback.
- [ ] **`allFoodLogs @Query(sort: \FoodLogEntry.createdAt)` is populated before `contextualBarState` first evaluates** — Risk: Low. SwiftData `@Query` results populate synchronously on first body evaluation after the context is available. The bar state on first appear may show `defaultActions` for one frame before switching to `logNextMeal`, which is acceptable.
- [ ] **`ContextualBarState.Equatable` auto-synthesis works for `.logNextMeal(mealLabel: String)` and `.waterBehindPace(glassesNeeded: Int)`** — Risk: Low. `String` and `Int` are `Equatable`, so auto-synthesis works. Verified in W5.

---

## Questions for Clarification

1. **H2/M8**: The coffee first-cup fix (W4) is applied in the `QuickStatsRow` watchout section but NOT updated in Step 1.2's code block, and the same bug exists in Step 5.9's `onAddCoffee`. Should the implementer apply the W4 fix everywhere, or is there a reason the Step 1.2 and Step 5.9 code differs?

2. **H3**: The struct fallback for `@Published var yesterdayStats` is shown in W1 but the primary Step 2.1 still uses the tuple. Which form should be implemented? (Recommendation: struct form as primary.)

3. **M9**: Should the `ZStack` around `ScrollView` be removed in Step 5.2, or is it intentionally kept for future use?

4. **L3**: Is there a timeline for re-homing `WellnessCalendarView` to Profile tab, or should a dead `// TODO` comment be placed?

---

## Recommendations

1. **Before implementing**: Fix Step 1.2 coffee `onIncrement` code to match W4 (increment before picker call), fix Step 5.9 `onAddCoffee` with same pattern, and switch Step 2.1 to use the struct form for `yesterdayStats`.

2. **Before implementing**: Correct the `HomeViewModel.swift` file path in Step 2.1 header.

3. **During Phase 3**: Add `Hashable` to `WellnessRingDestination` declaration when modifying `WellnessRingsCard.swift`.

4. **During Phase 5**: Use `$0.day == todayStart` instead of `Calendar.current.isDate($0.day, inSameDayAs: Date())` in `todayFoodLogs` for consistency with the existing `todayCalories` pattern.

5. **After Phase 5 complete**: Add a `goalsCelebration` test case to the manual verification flows that actually reaches 100% on all 4 rings (requires simulating HealthKit calories burned data or using mock mode).

6. **Post-implementation**: File a follow-up task for calendar button relocation and user name personalization.
