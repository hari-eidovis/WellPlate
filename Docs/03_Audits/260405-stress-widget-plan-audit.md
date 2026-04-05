# Plan Audit Report: Stress Level Widget

**Audit Date**: 2026-04-05
**Plan Version**: `Docs/02_Planning/Specs/260405-stress-widget-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is architecturally sound and follows the established food-widget pattern correctly. However, it has two build-breaking omissions — `ProfileView.swift` contains an entire in-app food widget preview section with hard references to `WidgetFoodData` and `WidgetFoodItem` that are not mentioned anywhere in the plan, and `WidgetRefreshHelper.refresh(goals:context:)` (the method being deleted) is still called by two unrelated callers (`GoalsViewModel` and `HomeViewModel`). Both gaps will cause compile failures if the plan is executed as written. A third significant issue is the deep-link placement: the plan attaches `.onOpenURL` to `MainTabView` but the strategy document specifies `WellPlateApp.swift` — these are inconsistent. Addressing all three issues before implementation will prevent avoidable build failures.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. `ProfileView.swift` Directly References `WidgetFoodData` and `WidgetFoodItem` — Not Mentioned in Plan

- **Location**: Step 1.2 ("Delete `SharedFoodData.swift`") and Architecture Changes table
- **Problem**: `WellPlate/Features + UI/Tab/ProfileView.swift` (currently modified — appears in git status) contains an entire in-app widget preview section (structs `WidgetPreview`, `SmallPreview`, `MediumPreview`, `LargePreview`) that instantiates `WidgetFoodData` directly at lines 863–878 and takes it as a parameter at lines 911, 962, and 1012. There is also a `FoodWidgetSize` enum (lines 7–45) and a `WidgetSetupCard` component (line 709) with food-widget-specific copy ("Calorie ring + quick add", "Ring + macro bars", "Full log + recent foods"). None of these references are listed in the Architecture Changes table; the plan does not include `ProfileView.swift` as a file to modify.
- **Impact**: Deleting `SharedFoodData.swift` (Step 1.2) will immediately break the main app build with "use of undeclared type 'WidgetFoodData'" and "'WidgetFoodItem'" errors across 7+ lines. The widget target build (Step 5.2) will also fail until the main app compiles.
- **Recommendation**: Add `WellPlate/Features + UI/Tab/ProfileView.swift` to the Architecture Changes table with action "Modify". Either (a) update the widget preview section to show a stress widget preview instead of the food preview (preferred, since the food widget is being removed entirely), or (b) remove the food widget preview section from ProfileView altogether, replacing it with a stress widget preview card. Both the `FoodWidgetSize` enum and the `SmallPreview`/`MediumPreview`/`LargePreview` structs need replacement. This should be added as a new implementation step (e.g., **4.4**) before the build verification phase.

---

#### 2. `WidgetRefreshHelper.refresh(goals:context:)` Is Still Called by Two Non-Widget Callers — Plan Only Adds `refreshStress`, Does Not Preserve the Food Method

- **Location**: Step 4.1 ("Rewrite `WidgetRefreshHelper.swift`") — specifically the word "Rewrite" and "Replace food refresh with stress refresh"
- **Problem**: The existing `WidgetRefreshHelper.refresh(goals:context:)` method is currently called by:
  - `WellPlate/Features + UI/Goals/ViewModels/GoalsViewModel.swift:19` — `WidgetRefreshHelper.refresh(goals: goals, context: modelContext)`
  - `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift:294` — `WidgetRefreshHelper.refresh(goals: goals, context: modelContext)`
  These callers are for the food widget data pipeline (goals change → food widget refreshes). The plan says to rewrite the helper and replace the food method with the new stress method. If the old `refresh(goals:context:)` method is removed, both callers will fail to compile.
- **Impact**: Two compile errors in the main app target (build step 5.1). `GoalsViewModel` and `HomeViewModel` will fail with "type 'WidgetRefreshHelper' has no member 'refresh'".
- **Recommendation**: The plan must explicitly address these two callers. There are three valid resolutions: (a) keep both methods in `WidgetRefreshHelper` — add `refreshStress` alongside the existing `refresh(goals:context:)` instead of replacing it (the food widget is being removed from the *widget extension* but `GoalsViewModel` and `HomeViewModel` still try to save food data to AppGroup); (b) remove the `refresh(goals:context:)` calls from `GoalsViewModel` and `HomeViewModel` since the food widget no longer exists; (c) add explicit steps to update both callers. Option (b) is cleanest — the food widget kind is being deregistered, so saving food data is pointless. But the plan must state this explicitly, naming the two callers and the action to take. The current plan is silent on this entirely.

---

### HIGH (Should Fix Before Proceeding)

#### 3. Deep-Link Placement Contradiction Between Plan and Strategy

- **Location**: Step 4.3 vs. `Docs/02_Planning/Specs/260405-stress-widget-strategy.md` "Modify" list
- **Problem**: The strategy document lists `WellPlate/App/WellPlateApp.swift` as the file to modify for the deep-link handler. The implementation plan (Step 4.3) says to add `.onOpenURL` to `WellPlate/Features + UI/Tab/MainTabView.swift` instead. These are architecturally different: on `WellPlateApp.swift` via `WindowGroup`, it fires for all app entry points including cold-start from a deep-link; on `MainTabView`, it only fires once `MainTabView` is on-screen (it would miss cold launches where the app starts on the onboarding or splash screen before `MainTabView` appears).
- **Impact**: If the handler is placed on `MainTabView` and the user taps the widget while the app is cold (not running), the app boots through `RootView` → splash → onboarding/main flow. If `MainTabView` has not yet been rendered when the URL arrives, `.onOpenURL` may never fire, resulting in the tap opening the app to the default tab (Home) rather than the Stress tab.
- **Recommendation**: Reconcile the two documents. The strategy's choice of `WellPlateApp.swift` is architecturally safer for cold launches. Alternatively, place it on `RootView` which is always the first live view. The plan should be updated to remove the contradiction and pick one placement, explaining the cold-launch rationale. The `selectedTab = 2` mechanism also requires the `selectedTab` state to be passed up to or owned by a parent that survives to `MainTabView` — verify the state propagation path works correctly.

#### 4. `weekReadings` Is Not Loaded at `loadData()` End — Widget Will Receive Empty 7-Day Trend on First Call

- **Location**: Step 4.1 and 4.2 — `WidgetRefreshHelper.refreshStress(viewModel:)` reading `viewModel.weekReadings`
- **Problem**: In `StressViewModel.loadData()`, the `weekReadings` property is only populated by `loadReadings()`, which is called inside `logCurrentStress(source:)` at line 377. `logCurrentStress` has an early-return guard: `guard isAuthorized else { return }`. On the very first run after a fresh install (before HealthKit auth), `isAuthorized` is `false`, so `logCurrentStress` is skipped and `loadReadings()` is never called — meaning `weekReadings` is `[]` when the plan's new widget refresh call executes at the end of `loadData()`. Even in the authorized path, `loadReadings()` is called inside `logCurrentStress` but the widget refresh executes after `logCurrentStress`, so the order is actually correct in the authorized path. The real risk is the unauthorized path: `weekReadings` will be an empty array and the large widget will immediately show "Not enough data yet" even if the user has 7 days of readings from previous sessions.
- **Impact**: Medium — affects cold launches before HealthKit authorization. Users who previously had 7 days of data would see the "Not enough data yet" state in the widget until they open the app and re-authorize.
- **Recommendation**: Add an explicit `loadReadings()` call before the widget refresh call in `loadData()`, unconditionally, so `weekReadings` is always populated from SwiftData regardless of authorization state. SwiftData access does not require HealthKit authorization. This one-line addition to Step 4.2 removes the ambiguity.

#### 5. `WidgetStressFactor.contribution` Field Name Conflicts with `StressFactorResult.stressContribution` — Mapping Not Specified

- **Location**: Step 1.1 (data model definition) and Step 4.1 (`WidgetRefreshHelper.refreshStress`)
- **Problem**: `WidgetStressFactor` defines a field named `contribution: Double` (described as "stress contribution 0–25"). `StressFactorResult` computes this via the `stressContribution` computed property, which inverts the score depending on `higherIsBetter`. The mapping from `StressFactorResult.stressContribution` → `WidgetStressFactor.contribution` is straightforward, but Step 4.1 is vague: it says "Build `WidgetStressFactor` array from `viewModel.allFactors`" without specifying which fields map where. The `score` field on `WidgetStressFactor` is described as "0–25 (factor score, not stress contribution)" — meaning it maps to `StressFactorResult.score`. The `contribution` field maps to `StressFactorResult.stressContribution`. The `StressFactorBar` color formula in Step 2.1 uses `contribution / 25.0` as a stress ratio (high = red). But for `higherIsBetter = false` factors like Screen Time, `stressContribution == score` directly, which is correct. For `higherIsBetter = true` factors like Exercise, `stressContribution = 25 - score`. The plan's bar color formula works correctly in both cases only if `contribution` is always `stressContribution`, not `score`. This assumption is buried in the model description but never made explicit in the refresh helper step.
- **Impact**: If the implementer misreads the field mapping and writes `contribution = factor.score` instead of `contribution = factor.stressContribution`, Screen Time bars will be inverted (low screen time would show as high-stress red). This is a subtle but visually wrong bug.
- **Recommendation**: Step 4.1 should include an explicit field mapping table:
  - `WidgetStressFactor.title` ← `StressFactorResult.title`
  - `WidgetStressFactor.icon` ← `StressFactorResult.icon`
  - `WidgetStressFactor.score` ← `StressFactorResult.score`
  - `WidgetStressFactor.maxScore` ← `StressFactorResult.maxScore`
  - `WidgetStressFactor.contribution` ← `StressFactorResult.stressContribution`
  - `WidgetStressFactor.hasValidData` ← `StressFactorResult.hasValidData`

---

### MEDIUM (Fix During Implementation)

#### 6. Empty State Discrimination: `totalScore == 0` Is Ambiguous — "Excellent" vs. "No Data"

- **Location**: Step 3.1 (StressSmallView) — "Empty state: When `data.totalScore == 0 && data.factors.isEmpty`"
- **Problem**: The plan checks `totalScore == 0 && factors.isEmpty` to detect the empty state. However, `WidgetStressData.empty` has `totalScore: 0` and `factors: []`, so this correctly catches the empty struct. But the plan's `placeholder` has `score: 32` and sample factors. There is a subtler edge case: a real user with `Excellent` stress (`score < 21`) whose factors list has 4 entries (all with `hasValidData: false`) will have `totalScore = 0` but `factors` is not empty. The empty state condition correctly won't trigger (because `factors` is not empty), so this user would see "0 / 100" in the ring with an `Excellent` level — which is technically a valid state (all factors neutral = 0 stress). This is consistent, but it should be documented in the implementation note so the developer doesn't "fix" it by expanding the empty state check and inadvertently hiding valid data.
- **Recommendation**: Add a note in Step 3.1 clarifying that the empty-state guard only fires when `factors.isEmpty` — the all-neutral-factors case shows a valid (though low-confidence) score. Consider adding `var hasAnyValidData: Bool` to `WidgetStressData` that returns `true` when at least one factor has `hasValidData: true`, to make this intent explicit without relying on array count.

#### 7. `StressWidget` Missing `@Environment(\.widgetFamily)` `default` Case Coverage for Future Widget Families

- **Location**: Step 2.2 — `StressWidgetEntryView` body switching on `widgetFamily`
- **Problem**: The plan specifies `switch family` with cases for `.systemSmall`, `.systemMedium`, `.systemLarge` but does not mention a `default` case. The existing `FoodWidgetEntryView` uses a `default: FoodSmallView(data: entry.data)` fallback. Without a `default` case, the switch will produce an exhaustiveness warning or (if the compiler treats `widgetFamily` as non-exhaustive) a compile error in future SDK versions. The food widget correctly includes this fallback.
- **Recommendation**: Step 2.2 should explicitly call out adding `default: StressSmallView(data: entry.data)` as the fallback, mirroring the food widget pattern exactly.

#### 8. `WidgetDayScore` Struct Name Diverges From Brainstorm's `DayScore`

- **Location**: Step 1.1 defines `WidgetDayScore`; brainstorm (line 257) uses `DayScore`
- **Problem**: Minor naming inconsistency between documents. The plan introduces `WidgetDayScore` as a new Codable struct inside `SharedStressData.swift`. The brainstorm document shows `DayScore`. More importantly, `StressView.swift` (line 314) already uses a grouping pattern on `weekReadings` with a similar concept but does not define a `DayScore` type — it uses inline tuple grouping. If any future code tries to share a `DayScore` type between the main app and widget, the name divergence causes confusion. No build risk today, but worth noting for future maintenance.
- **Recommendation**: Confirm `WidgetDayScore` as the canonical name in `SharedStressData.swift` (since it's widget-only context and the `Widget` prefix is consistent with `WidgetStressData` and `WidgetStressFactor`). The plan's name choice is fine; just note that the brainstorm uses a different name and that it's intentionally different.

#### 9. Large Widget 7-Day Trend: Day-of-Week Labels Assume a Fixed Starting Day, But `weekReadings` Spans 6 Days Back

- **Location**: Step 3.3 (StressLargeView) — 7-day trend with day labels "M T W T F S S"
- **Problem**: `StressViewModel.loadReadings()` fetches readings from `startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday)`, which is today minus 6 days (7 days inclusive). The plan says to show day-of-week labels below the bars. These labels must be computed from the actual dates in `weeklyScores`, not hardcoded. The plan's ASCII diagram shows "M T W T F S S" which could be misread as a static string. If the implementer hardcodes these, users opening the widget on a Wednesday will see M-T-W-T-F-S-S labels but the data starts on last Thursday.
- **Recommendation**: Step 3.3 should explicitly state that day labels must be derived from `data.weeklyScores[i].date` using `Calendar.current.shortWeekdaySymbols` or a `DateFormatter` with `"EEE"` format — not hardcoded. Clarify that the ASCII diagram is illustrative only.

#### 10. `Score == -1` Sentinel Conflicts With `WidgetStressData.empty` Score of `0`

- **Location**: Step 1.1 — `WidgetDayScore.score` uses `-1` to mean "no data"; `WidgetStressData.empty` uses `totalScore: 0`
- **Problem**: The plan uses `score: -1` in `WidgetDayScore` to represent days with no readings. This is a numeric sentinel mixed into a `Double` domain. The large widget trend renderer must explicitly check `score == -1` before doing any math (normalizing bar height, deriving color). If the implementer forgets this check and passes `-1` into `StressLevel(score: -1)`, the `init(score:)` switch will match the `case ..<21` branch (since -1 < 21) and return `.excellent` — meaning a "no data" day would render with an excellent sage-green bar rather than a faded gray bar. The plan's implementation note for Step 3.3 says "score == -1 → show faded/gray bar at minimal height" but does not say where in the rendering code this guard must go.
- **Recommendation**: Consider using `Double?` (optional) instead of `-1` sentinel to leverage the type system — an optional `nil` is unmistakable, whereas `-1.0` is easy to forget to check. If keeping the sentinel, Step 3.3 should show pseudocode for the guard: `let isNoData = dayScore.score < 0`. Additionally, `WidgetRefreshHelper.refreshStress` step 4.1 should explicitly state that days with zero `StressReading` rows are encoded as `-1.0` (or nil) rather than `0.0`, because `0.0` is a valid stress score.

---

### LOW (Consider for Future)

#### 11. No VoiceOver / Accessibility Labels Specified for the Ring View

- **Location**: Step 2.1 (StressRingView)
- **Problem**: The plan describes the ring's visual structure in detail but does not mention `.accessibilityLabel` or `.accessibilityValue` modifiers. The existing `CalorieRingView` also lacks these, so there is no regression, but the new ring should have them given it's a primary informational element. WidgetKit renders widgets as snapshots; VoiceOver reads the accessibility tree of the view hierarchy.
- **Recommendation**: Add `.accessibilityLabel("Stress score: \(Int(data.totalScore)) out of 100, \(data.levelRaw)")` to `StressRingView`. Low priority but worth adding during the view implementation step.

#### 12. Widget Refresh Is Not Called from `refreshDietFactorAndLogIfNeeded()` or `refreshScreenTimeOnly()`

- **Location**: Step 4.2
- **Problem**: The plan adds the widget refresh call only to `loadData()`. But `StressViewModel` has two other public methods that update factor values and call `logCurrentStress`:
  - `refreshDietFactorAndLogIfNeeded()` — called when food is logged
  - `refreshScreenTimeOnly()` — called when screen time changes
  These methods can change `totalScore` meaningfully (e.g., logging a meal changes the diet factor score), but the widget will not update until the next 30-minute pull or the next full `loadData()` call.
- **Impact**: Low for the initial implementation — the plan's stated requirement is "Widget refresh triggered from `StressViewModel.loadData()`" which is met. However, users will notice the widget doesn't update when they log food, even though the app's stress score changes immediately.
- **Recommendation**: Document this as a known limitation in the plan's "Non-Goals" or "Risks & Mitigations" section so it's a conscious decision rather than an omission. A future iteration can add `WidgetRefreshHelper.refreshStress(viewModel: self)` to these methods.

#### 13. `getSnapshot` Returns `.placeholder` for Non-Preview Contexts — May Show Stale Ring

- **Location**: Step 2.2 — `getSnapshot` description
- **Problem**: The plan says `getSnapshot` should return `.placeholder` if `isPreview`, else `WidgetStressData.load()`. The food widget does exactly the same (`context.isPreview ? .placeholder : WidgetFoodData.load()`). This is correct behavior. However, `getSnapshot` is also called when the widget gallery shows a "Add Widget" preview of an already-added widget instance — in that context, `isPreview` is `true`. If a user's widget was last showing a score of 85 (Very High) and they see the gallery preview showing `score: 32` (Good/placeholder), it could be confusing. This is a cosmetic issue, not a bug, and matches the existing food widget's behavior exactly.
- **Recommendation**: No change needed for this implementation. Document in the testing checklist that the widget gallery preview always shows placeholder data.

---

## Missing Elements

- [ ] `ProfileView.swift` widget preview section update — an entire MARK block (`// MARK: - Widget Preview`) with 4 structs (`WidgetPreview`, `SmallPreview`, `MediumPreview`, `LargePreview`) and the `FoodWidgetSize` enum all need replacement or removal. The git status shows this file is already modified (`M "WellPlate/Features + UI/Tab/ProfileView.swift"`) — implementer must check current state before editing.
- [ ] Explicit action on `GoalsViewModel.save()` and `HomeViewModel.refreshWidget(for:)` — both call the food refresh method that is being deleted.
- [ ] Step for updating the widget preview descriptions in `ProfileView` from food-widget copy ("Calorie ring + quick add") to stress-widget copy, or removing the widget preview section entirely.
- [ ] `loadReadings()` call before widget refresh in Step 4.2 to guarantee `weekReadings` is current.
- [ ] Explicit `default:` case in `StressWidgetEntryView`'s family switch (Step 2.2).
- [ ] Day-of-week label derivation from actual `Date` objects (Step 3.3) — not hardcoded strings.

---

## Unverified Assumptions

- [ ] **App Group entitlement also exists in the main app target** — `WellPlate.entitlements` was not listed above but is confirmed present. No change needed. Risk: None.
- [ ] **`WidgetCenter.shared` is accessible from the main app target** — confirmed via existing `WidgetRefreshHelper.swift` which already imports `WidgetKit`. Risk: None.
- [ ] **`ProfileView.swift` widget preview is used/visible to real users** — the git status shows this file is currently modified (`M`), meaning changes already exist in the working tree that may affect the references found in the audit. The implementer should `git diff` this file first to understand the current state before editing. Risk: Medium.
- [ ] **`StressViewModel.weekReadings` is populated before widget refresh** — as noted in Issue 4, this depends on whether `logCurrentStress` is skipped. Risk: Medium (first-launch scenario).
- [ ] **`isPreview` flag correctly differentiates widget gallery vs. Home Screen** — assumed to work the same way as the food widget. Risk: Low.

---

## Questions for Clarification

1. Should `ProfileView.swift`'s widget preview section be replaced with a stress widget preview (showing a scaled-down version of the new stress views), or should the entire widget setup card be removed since there will be no more "Add Food Widget" flow?
2. Should `GoalsViewModel.save()` and `HomeViewModel.refreshWidget(for:)` retain food data writes to AppGroup even though the food widget is removed — in case a future pass re-adds a food widget — or should those calls be deleted entirely?
3. The strategy document specifies `WellPlateApp.swift` for the deep-link handler while the plan specifies `MainTabView.swift`. Which is the intended location? (The architectural difference matters for cold launches.)
4. Is the `score: -1` sentinel for "no data" days intentional, or would `Double?` be preferable for type safety in `WidgetDayScore`?

---

## Recommendations

1. **Before writing any code**, add `ProfileView.swift` to the Architecture Changes table with an explicit description of what to change. This is a build-blocking omission.
2. **Rename Step 4.1** from "Rewrite" to "Add `refreshStress` method to `WidgetRefreshHelper`" to make clear the old `refresh(goals:context:)` is being either preserved (if food data saves are still desired) or explicitly deleted with named callers updated.
3. **Add a Step 4.4** for the `ProfileView.swift` food widget preview replacement — with the current file state already modified in git, this step needs to check the working copy before editing.
4. **Add a Step 4.5** explicitly for updating or deleting the `WidgetRefreshHelper.refresh` call sites in `GoalsViewModel` and `HomeViewModel`.
5. **Reconcile the strategy and plan** on deep-link placement (WellPlateApp.swift vs. MainTabView.swift). A comment in Step 4.3 should explain the cold-launch risk and why the chosen placement handles it.
6. **Change `WidgetDayScore.score` to `Double?`** — the `nil` sentinel is type-safe and removes the need to remember the `-1` convention across three separate places (the helper that writes it, the large view that reads it, and any future code).
