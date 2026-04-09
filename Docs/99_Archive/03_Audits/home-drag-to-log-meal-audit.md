# Plan Audit Report: Home "Drag Up to Log a Meal" Overlay

**Audit Date**: 2026-03-11
**Plan Version**: 260311-home-drag-to-log-meal.md
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The core architecture in the plan is sound and the "Sheet from HomeView + NavigationStack push on dismiss" approach is technically viable given the actual codebase. However, the plan contains several critical correctness bugs (incorrect `onDismiss` interaction with SwiftUI's sheet lifecycle, a broken haptic threshold comparison, and a reference to `AppColors.primary` instead of `AppColors.primary`), several high-priority UX problems (the "always land on FoodJournal" design is disorienting for cancel-without-save flows, the overlay will be visually obscured by the tab bar, and the breathing animation has no stop condition), and meaningful missing accessibility and gesture-conflict work. These must be addressed before implementation to avoid shipping broken behavior.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

---

**1. `onDismiss` fires on EVERY sheet dismissal — including user-initiated cancel without saving**

- **Location**: Plan §Phase 3 / Step 1.2; "Risks & Mitigations" section
- **Problem**: The plan itself acknowledges this in the risks section and calls it "intended — all dismissals should land on FoodJournalView." However, that is a bad UX decision that conflicts with standard iOS navigation expectations. If the user opens the meal log overlay, decides not to log anything, and swipes down (or taps the back chevron in `MealLogView`), they will be forcibly pushed to `FoodJournalView` even though they cancelled. The plan's test cases (Manual test 3) even confirm this: "Tap the back chevron without saving. Verify sheet closes and FoodJournalView opens." This is a confusing, unrecoverable navigation surprise.
- **Impact**: Users who accidentally trigger the drag gesture or change their mind will be yanked out of HomeView against their will. This is a jarring break of the principle of least surprise. It effectively makes the drag overlay a one-way trap — once you touch it, you leave HomeView no matter what.
- **Recommendation**: Differentiate between save-dismiss and cancel-dismiss. Add a `@State private var mealWasSaved = false` flag to HomeView (or pass a binding into `MealLogSheetContent`). Only set `showLogMeal = true` in `onDismiss` when `mealWasSaved == true`. Have `MealLogViewModel.shouldDismiss` trigger a callback that sets this flag before dismissing. Alternatively, use `@Binding var didSave: Bool` threaded through `MealLogSheetContent` → `MealLogView` and set it in the `onChange(of: viewModel.shouldDismiss)` handler before `dismiss()` is called.

---

**2. Haptic threshold comparison is broken (will never fire)**

- **Location**: Plan §Phase 2 / Step 2.1, `DragGesture.onChanged` closure, line: `if -translation >= dragThreshold / 2 && -offset < dragThreshold / 2 + 1`
- **Problem**: The condition checks `-offset < dragThreshold / 2 + 1` to act as a "fire only once" guard. But `offset` is updated via `withAnimation` *inside* the same `onChanged` call, not synchronously. In practice `offset` will already equal `translation` from the previous call because `withAnimation` in `onChanged` with `.interactiveSpring` animates the *presentation*, not the state itself — the `@Binding offset` is a `@State` in the parent, so it updates immediately. The result is that `-offset` will equal `-translation` on the very next gesture event, making the guard `-offset < dragThreshold / 2 + 1` almost always false after the first tick. The haptic will fire erratically or not at all. Additionally, using `withAnimation` inside `.onChanged` to mutate an `@Binding` is an anti-pattern; `.interactiveSpring` should be used on the presentation modifier, not the state mutation.
- **Impact**: The half-threshold haptic will be unreliable. The gesture may also behave inconsistently because the state and animation are fighting each other.
- **Recommendation**: Track a separate `@State private var hasTickedHalf = false` flag inside `DragToLogOverlay`. Reset it in `onEnded`. In `onChanged`, set the offset directly *without* `withAnimation` (let `.offset(y:)` drive a separate `@State` that is animated via a `spring` animation attached to the view). Only fire the haptic when `!hasTickedHalf && -translation >= dragThreshold / 2`, then set `hasTickedHalf = true`.

---

**3. The overlay sits inside `NavigationStack`, above `ScrollView` in ZStack, but below the tab bar safe area — it will be visually clipped/obscured**

- **Location**: Plan §Phase 1 / Step 1.3; §Phase 4 / Step 4.1
- **Problem**: The plan places the `DragToLogOverlay` as a `ZStack` child inside the `NavigationStack`. In this app's actual structure (confirmed by reading `HomeView.swift` lines 32–102 and `MainTabView.swift`), `HomeView` is embedded inside a `TabView`. The `TabView` renders the tab bar as a *separate system overlay* that sits above the `NavigationStack`'s coordinate space. The `DragToLogOverlay` placed at `.bottom` of a `ZStack` inside `NavigationStack` will be positioned at the bottom of the `NavigationStack`'s safe-area-inset frame — but on a device running iOS 26, the tab bar is still rendered *on top* of that and the pill will be hidden behind it. The plan mentions "sits above tab bar naturally via safe area" at `.padding(.bottom, 0)` but provides no justification for this assumption, and it is wrong. The tab bar does not inset the `NavigationStack`'s frame in a `TabView` on iOS 26 — it insets the `safeAreaInsets.bottom` of views *inside* the tab, but only if `.ignoresSafeArea` is not applied. The `ScrollView`'s `.background(Color(.systemGroupedBackground).ignoresSafeArea())` (line 92 of HomeView) will extend under the tab bar. The overlay, having no `ignoresSafeArea`, will be cropped or overlap the safe area inset incorrectly.
- **Impact**: The pill may be partially or fully hidden behind the tab bar, defeating the entire feature.
- **Recommendation**: Use a `GeometryReader` or `safeAreaInset(edge: .bottom)` to place the overlay correctly. The cleanest approach on iOS 26 is to use `.safeAreaInset(edge: .bottom)` as a modifier on the `ScrollView` itself (not a ZStack sibling), which causes the scroll view to inset its content and places the overlay *above* the tab bar's safe area automatically. This is also the correct pattern for FABs and overlays in the app — note how `FoodJournalView`'s plus button uses `VStack { Spacer(); HStack { Spacer(); Button... } }` inside a `ZStack` with `.padding(.bottom, 8)` and it works because `FoodJournalView` is a navigation-pushed view (no tab bar visible). HomeView has the tab bar active, making the ZStack-bottom approach fragile.

---

### HIGH (Should Fix Before Proceeding)

---

**1. `showLogMeal = true` in `onDismiss` will fire even when the user is already on FoodJournalView**

- **Location**: Plan §Phase 3 / Step 3.2; "Risks & Mitigations" — "already navigated" scenario
- **Problem**: The plan claims "SwiftUI's `@State` binding change detection handles this. No action needed." This is incorrect. SwiftUI does detect no-op state changes and avoids re-rendering, but `navigationDestination(isPresented:)` driven by a `@State Bool` can still trigger navigation side effects if the state was `false` and is set to `true` while the user is *on* FoodJournalView (which itself was the `showLogMeal = true` destination). Specifically: user opens FoodJournalView via the normal path → navigates back to HomeView (sets `showLogMeal = false`) → triggers drag overlay → saves meal → `onDismiss` sets `showLogMeal = true` again. This flow is fine. But consider: user opens FoodJournalView, does not navigate back, then somehow the drag overlay sheet fires (e.g., from a state restoration path). Setting `showLogMeal = true` while `FoodJournalView` is already shown via the NavigationStack will not double-push in iOS 26 (because `isPresented` is already true). This specific case is safe. However, the broader concern remains: the plan has no guard against `showLogMeal` being `true` already when `onDismiss` fires. Add an explicit guard: `if !showLogMeal { showLogMeal = true }` — or at minimum document this assumption.
- **Impact**: Low probability of double-push but the assumption is undocumented and brittle under future refactors.
- **Recommendation**: Wrap the `onDismiss` body in `if !showLogMeal { showLogMeal = true }` and add a code comment explaining the intent.

---

**2. Breathing animation (`repeatForever`) causes ongoing CPU/GPU work even when partially off-screen**

- **Location**: Plan §Phase 5 / Step 5.1
- **Problem**: The plan claims "SwiftUI pauses animations on views not in the hierarchy. The animation runs only while HomeView is the active tab." This is partially true — SwiftUI may reduce animation frequency when the view is off-screen, but it does *not* guarantee complete suspension for `repeatForever` animations. On iOS 26 with `SWIFT_APPROACHABLE_CONCURRENCY`, the Main Actor will continue processing animation ticks via the CADisplayLink underlying SwiftUI's animation engine even for background tabs. The breathing animation will run continuously as long as HomeView exists in the tab hierarchy (which is always — tabs are not destroyed when switched). This is a sustained, low-level GPU/CPU cost for a purely cosmetic hint.
- **Impact**: Unnecessary battery drain on a frequently visited screen. Multiplied by all users.
- **Recommendation**: Use `.task` with a loop and `try? await Task.sleep` to manually update opacity, which is cancellable. Alternatively, stop the animation after the user has seen HomeView a certain number of times (use `@AppStorage` for a view count). At minimum, only apply the animation modifier when the view has been visible for more than 2 seconds using `.onAppear` / `.onDisappear` state tracking, and stop it on `.onDisappear` by toggling a `@State private var animating = false` flag that guards the `withAnimation` call.

---

**3. `MealLogSheetContent` always logs to `Date()` (today), ignoring the selected date context**

- **Location**: Plan §Phase 1 / Step 1.2
- **Problem**: The plan specifies `MealLogSheetContent(homeViewModel: foodJournalViewModel, selectedDate: Date())`. This hardcodes logging to today. This is intentional for the HomeView context (reasonable assumption), but it is a departure from `FoodJournalView`'s behavior where the selected date can be any date. More importantly, it means that if a user happens to be on the Home tab late at night after midnight, the meal will be logged to the new day, which may be unexpected. This is a minor but undocumented assumption.
- **Impact**: Meals logged via the drag overlay will always go to today's date. Users cannot correct this.
- **Recommendation**: Document this explicitly in code comments and in the plan as a known limitation. Consider showing the date in the sheet header as `MealLogView` already does (it shows "Today" or the short date).

---

**4. Gesture conflict with FoodJournalView's horizontal swipe gesture is unaddressed for the overlay context**

- **Location**: Plan §Phase 2; "Risks & Mitigations"
- **Problem**: The plan correctly notes the overlay gesture is a ZStack sibling of the ScrollView, so it won't conflict with scroll. However, `FoodJournalView` uses a `.simultaneousGesture(DragGesture(...))` for horizontal swipe-to-change-date (lines 111–123 of `FoodJournalView.swift`). While this is in `FoodJournalView` not HomeView, the issue is subtler: the new `DragToLogOverlay` in HomeView uses a `DragGesture(minimumDistance: 8)`. On iOS 26, gesture recognizers in a `ZStack` compete. The `ScrollView`'s built-in pan gesture has a higher priority than custom `DragGesture` modifiers attached to ZStack children. If the user starts a drag on the pill but drifts slightly horizontally, the ScrollView gesture may take priority. More critically, the pill uses `minimumDistance: 8` but the ScrollView's pan gesture uses a system minimum distance that is also roughly 10pt. There is a race condition for diagonal drags that start on the pill.
- **Impact**: Diagonal drags on the overlay may trigger scrolling instead of the overlay gesture, leading to confusing partial lifts that snap back.
- **Recommendation**: Add `.highPriorityGesture()` instead of `.gesture()` on the overlay, or add `.simultaneousGesture()` with a competing gesture on the ScrollView that yields to the overlay for upward drags. The safest approach is `.highPriorityGesture(DragGesture(minimumDistance: 8).onChanged{...}.onEnded{...})` on the overlay pill, scoped to only claim the gesture when translation is predominantly vertical-upward (add an early-exit check: `guard abs(value.translation.width) < abs(value.translation.height) else { return }`).

---

**5. No accessibility support specified**

- **Location**: Plan as a whole — not mentioned anywhere
- **Problem**: The overlay has no VoiceOver label, hint, or action. A user relying on VoiceOver will find an unlabeled element at the bottom of HomeView. The `DragGesture` is inherently inaccessible — VoiceOver cannot perform a drag gesture on a SwiftUI view. There is no `accessibilityAction` that provides an equivalent tap-to-log interaction.
- **Impact**: The feature is completely unusable for VoiceOver users. In a health app, accessibility compliance is particularly important.
- **Recommendation**: Add the following to `DragToLogOverlay`:
  ```swift
  .accessibilityLabel("Log a meal")
  .accessibilityHint("Activates the meal logging form")
  .accessibilityAddTraits(.isButton)
  .onTapGesture { onThresholdReached() }
  ```
  The tap gesture gives VoiceOver users a way to activate the feature. The drag gesture remains for sighted users.

---

### MEDIUM (Fix During Implementation)

---

**1. `AppColors.primary` used in `DragToLogOverlay` — verify it resolves as expected at iOS 26 asset catalog level**

- **Problem**: `AppColors.primary` maps to `Color("AppPrimary")` (a named asset). The plan references this correctly, but the overlay also uses `Color(.tertiaryLabel)` and `.secondary` for system colors alongside the brand color. Confirm the visual combination works in both light and dark mode before shipping — the `appShadow` modifier uses `Color(.label).opacity(0.08)` which is adaptive. The `y: -4` shadow direction (upward) is correct for a bottom-anchored card but untested in dark mode where the shadow color is nearly invisible.
- **Recommendation**: Add explicit dark mode previews to the `#Preview` in `DragToLogOverlay.swift`.

---

**2. The plan modifies the `NavigationStack` body structure without accounting for the `.navigationBarHidden(true)` placement**

- **Location**: Plan §Phase 1 / Step 1.3 diff
- **Problem**: The plan shows `.navigationBarHidden(true)` moved to be a modifier on the `ZStack`, but in the current `HomeView.swift` (line 101) it is on the `ScrollView` chain. This is a subtle but potentially meaningful change: `.navigationBarHidden(true)` must be applied to a view that is a *direct child of `NavigationStack`* or it may not take effect consistently in iOS 26. Moving it to the `ZStack` should still work since `ZStack` is the direct child, but this is an untested change to existing behavior.
- **Recommendation**: Verify in a simulator build. Keep `.navigationBarHidden(true)` on the `ZStack` as proposed, but add a note to test that the nav bar remains hidden.

---

**3. `onDismiss` ordering relative to state updates is not guaranteed on iOS 26**

- **Problem**: On iOS 26 (using the new `SWIFT_APPROACHABLE_CONCURRENCY = YES` setting), the `onDismiss` closure runs on the `MainActor`. However, SwiftUI's sheet dismissal animation completes asynchronously. There is a documented edge case where `onDismiss` fires while the sheet dismiss animation is still in progress, and then `navigationDestination(isPresented:)` attempts to push a new view immediately. This can produce a "presenting while dismissing" state that causes a brief visual artifact (the new view may appear before the sheet has fully dismissed).
- **Recommendation**: Wrap the `onDismiss` body in a short `DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showLogMeal = true }` to allow the sheet dismissal animation to complete. 0.35s is slightly longer than the default sheet spring animation.

---

**4. The plan does not address what happens to `dragOverlayOffset` if the sheet is dismissed mid-drag**

- **Problem**: If the user drags quickly past the threshold, `onThresholdReached()` is called and `showMealLogFromDrag = true`. The `offset` is reset to 0 via `withAnimation` in `onEnded`. However, if somehow the sheet presentation races with an ongoing drag gesture (possible on slow devices), the overlay could be in a non-zero offset state while the sheet is presenting. When the sheet is dismissed, the overlay will snap back visually.
- **Recommendation**: In `onThresholdReached`, ensure `offset` is already 0 before presentation. The plan does reset offset to 0 before calling `onThresholdReached()` in `onEnded` — this is correct. Add a `.onAppear` in `MealLogSheetContent` that also resets the binding to 0 as a safety net.

---

**5. No empty-state / first-run discoverability beyond the breathing hint**

- **Problem**: The plan relies entirely on the "drag up to log a meal" text label and the breathing animation for discoverability. On first launch, a user may not understand that the pill is interactive at all. There is no onboarding callout, tooltip, or coach mark.
- **Recommendation**: For v1, add a one-time spotlight hint (using `@AppStorage` to track whether the user has seen it) that points at the overlay on first HomeView appearance. This is out of scope for this plan but should be a follow-up ticket.

---

### LOW (Consider for Future)

---

**1. The drag threshold of 60pt is arbitrary and not derived from HIG recommendations**

- **Problem**: 60pt is a reasonable guess but Apple's HIG recommends interactive gestures respond within 10–20pt. A 60pt threshold may feel sluggish on smaller devices (iPhone SE) where vertical space is precious.
- **Recommendation**: Consider a dynamic threshold: `max(44, UIScreen.main.bounds.height * 0.075)` — approximately 60pt on standard phones, slightly less on SE.

---

**2. `Components/` directory does not exist yet for Home feature**

- **Problem**: The plan creates `WellPlate/Features + UI/Home/Components/DragToLogOverlay.swift`. Checking the actual file tree, a `Components/` directory already exists (confirmed by `GoalExpandableView.swift`, `ExpandableFAB.swift`, etc. being found there). This is fine — just confirm the directory path matches exactly, including the space in `Features + UI`.
- **Recommendation**: No action needed, directory exists.

---

**3. `selectedDate: Date()` captures the date at sheet *creation* time, not presentation time**

- **Problem**: `MealLogSheetContent` is initialized with `selectedDate: Date()`. If HomeView is loaded at 11:58 PM and the sheet is shown at 12:01 AM, the date passed will still be from when the view was initialized/captured. Actually, `Date()` is evaluated at the `.sheet` modifier's content builder call time, which is at presentation time in SwiftUI — this is likely fine. But it is worth verifying.
- **Recommendation**: Low risk; verify in a late-night edge case test.

---

## Missing Elements

- [ ] Accessibility implementation (`accessibilityLabel`, `accessibilityHint`, `accessibilityAction`) — no VoiceOver path exists
- [ ] Differentiated cancel-vs-save `onDismiss` behavior — currently all dismissals navigate to FoodJournalView
- [ ] Dark mode screenshot/preview in the `DragToLogOverlay` component file
- [ ] `.highPriorityGesture` or gesture priority specification for the overlay vs ScrollView competition
- [ ] `ignoresSafeArea` / `safeAreaInset` analysis for correct placement above the tab bar
- [ ] Unit/snapshot tests — the testing strategy is entirely manual; no automated tests are specified
- [ ] Rollback strategy — no mention of a feature flag or easy removal path

---

## Unverified Assumptions

- [ ] "Overlay sits above tab bar naturally via safe area" — Risk: **HIGH** (see Critical issue 3; this is likely wrong)
- [ ] "SwiftUI pauses `repeatForever` animations when tab is not active" — Risk: **MEDIUM** (partially true but not guaranteed)
- [ ] "Setting `showLogMeal = true` again when already true is a no-op" — Risk: **Low** (SwiftUI handles this, but undocumented)
- [ ] "`onDismiss` fires synchronously before the dismiss animation completes" — Risk: **MEDIUM** (ordering not guaranteed on iOS 26)
- [ ] "The `DragGesture(minimumDistance: 8)` will not compete with the `ScrollView` pan" — Risk: **MEDIUM** (diagonal drags are not handled)
- [ ] "No tab exists for FoodJournal" — Risk: **Low** (VERIFIED: confirmed by reading `MainTabView.swift` — there are only 4 tabs: Home, Burn, Stress, Profile. FoodJournal is NavigationStack-pushed, as stated)

---

## Security Considerations

- [ ] No security concerns for this feature — it operates entirely on local data already accessible to HomeView

---

## Performance Considerations

- [ ] `repeatForever` breathing animation runs continuously on the Main Actor's CADisplayLink path while HomeView is in the tab hierarchy (tab is never destroyed) — sustained CPU/GPU cost
- [ ] `DragToLogOverlay` uses a `VStack` + `RoundedRectangle` + shadow — lightweight, no concerns
- [ ] The `.sheet(isPresented:)` adds one more sheet presentation path to an already sheet-heavy view; no concern at this scale
- [ ] `LazyVStack` in `HomeView` already handles list rendering efficiently; the overlay does not affect this

---

## Questions for Clarification

1. **Intent on cancel**: Should the user really land on `FoodJournalView` even when they open the overlay and cancel without saving? Or should cancel return them to HomeView? The plan says yes (all dismissals go to FoodJournal), but this appears to be a UX mistake rather than a deliberate design decision.

2. **Tab bar overlap**: Has the implementer tested a prototype of a bottom-anchored overlay inside a `NavigationStack` within a `TabView` on iOS 26? The safe area behavior must be confirmed before building.

3. **Discoverability**: The plan pins discoverability entirely on a breathing text hint. Has any user testing been done to validate that this pattern is understood without instruction?

4. **Regression risk for `showLogMeal`**: `showLogMeal` is already used to push `FoodJournalView` via the (commented-out) QuickLogSection. The `onDismiss` path now adds a second trigger point for `showLogMeal = true`. Is there any scenario where both triggers could fire in rapid succession?

5. **`MealLogViewModel` reuse**: `MealLogSheetContent` creates a new `MealLogViewModel` via `@StateObject` on each presentation. After saving, `shouldDismiss = true` is set but the VM is never reset. If the sheet is somehow re-presented without the `@StateObject` being recreated (e.g., SwiftUI identity not changing), the form would appear in a "dismissed" state. Has this lifecycle been tested?

---

## Recommendations

1. **Fix the cancel-vs-save navigation**: Thread a `@Binding var didSave: Bool` into `MealLogSheetContent` and only navigate to `FoodJournalView` when `didSave == true`. This is the single most important UX fix.

2. **Validate overlay placement on device before writing code**: Open a playground or test project, place a pill in a `ZStack` inside a `NavigationStack` inside a `TabView`, and confirm it appears above the tab bar. If it does not, switch to `.safeAreaInset(edge: .bottom)` on the `ScrollView` — this is the correct iOS 16+ pattern for bottom overlays in tabbed apps.

3. **Fix the haptic logic**: Use a `@State private var hasTickedHalf = false` guard and do not mix `withAnimation` with `@Binding` state mutations inside `onChanged`.

4. **Add VoiceOver support before shipping**: This is a health app and accessibility is non-negotiable. The tap-to-activate fallback takes ~3 lines of code.

5. **Consider simpler interaction model**: The drag gesture is novel but risky on discoverability. An alternative worth prototyping: a permanently visible, subtly pulsing pill that **taps** to open the meal log sheet directly (no drag needed). This eliminates gesture conflicts, accessibility concerns, and threshold tuning at the cost of some "delight." The drag can be a v2 enhancement once the simpler version is validated.

6. **Scope the `repeatForever` animation properly**: Add `.onDisappear { animating = false }` / `.onAppear { animating = true }` state management to avoid continuous animation rendering while the tab is inactive.

---

## Sign-off Checklist

- [ ] All CRITICAL issues resolved
- [ ] All HIGH issues resolved or accepted
- [ ] Security review completed (N/A — no security concerns)
- [ ] Performance implications understood (breathing animation CPU cost)
- [ ] Rollback strategy defined (currently missing — consider a feature flag)
