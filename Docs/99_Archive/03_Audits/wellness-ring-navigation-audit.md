# Plan Audit Report: Wellness Ring Per-Ring Navigation

**Audit Date**: 2026-03-11
**Plan Version**: Informal plan (no versioned spec file)
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is directionally sound but contains two blocking architectural issues: `BurnView` and `StressView` each embed their own `NavigationStack`, making them incompatible with being pushed onto HomeView's existing `NavigationStack`. Additionally, the string-based ring ID dispatch (`onRingTap: (String) -> Void`) is a fragile design that should be replaced before any code is written. Several high-priority concerns around UX conflict, state synchronization, and tap gesture interaction also need resolution before implementation proceeds.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **BurnView and StressView each own a NavigationStack — they cannot be pushed**
   - Location: Plan step 2 (HomeView changes) — "add .navigationDestination for BurnView/StressView"
   - Problem: `BurnView.body` begins with `NavigationStack { ... }`. `StressView.body` also begins with `NavigationStack { ... }`. Pushing either of these via `.navigationDestination(isPresented:)` inside HomeView's `NavigationStack` creates a nested `NavigationStack`, which in SwiftUI produces undefined/broken navigation behavior (double nav bars, back button issues, toolbar conflicts).
   - Impact: The pushed view will render with its own navigation bar in addition to HomeView's, the back button may not function correctly, and the `.navigationBarHidden(true)` in `StressView` will fight with the parent stack's toolbar. This is a hard runtime UX defect.
   - Recommendation: Do NOT push these views directly. Instead, present them as `.fullScreenCover` or `.sheet`. Alternatively, switch the tab programmatically using a shared tab selection binding — this is the architecturally correct approach since both views are already tab-level destinations in `MainTabView` (tabs 1 and 2). A `@Binding var selectedTab: Int` passed down to HomeView (or a shared `@StateObject` tab coordinator) would allow the Exercise ring tap to switch to tab 1 and the Stress ring tap to switch to tab 2. This avoids duplicating ViewModels, HealthKit permission flows, and navigation stacks.

2. **String-based ring ID dispatch is untyped and fragile**
   - Location: Plan step 1 — `onRingTap: (String) -> Void`
   - Problem: The plan proposes dispatching ring identity using raw strings (presumably "Calories", "Water", "Exercise", "Stress"). These strings must match between `WellnessRingsCard` and `HomeView` with no compile-time enforcement. A label rename (e.g. internationalisation, copy change) silently breaks navigation. The `WellnessRingItem` struct already has an `id: UUID` which is useless for semantic dispatch.
   - Impact: Silent regression risk on any copy change; harder to reason about in code review.
   - Recommendation: Define a typed enum — `enum WellnessRingDestination: CaseIterable { case calories, water, exercise, stress }` — add it to `WellnessRingItem` or as a new callback type, and use `onRingTap: (WellnessRingDestination) -> Void`. This eliminates the string matching entirely.

---

### HIGH (Should Fix Before Proceeding)

3. **Card-level `.onTapGesture` will intercept ring taps before per-ring gestures fire**
   - Location: `WellnessRingsCard.swift` lines 59–62; Plan step 1
   - Problem: The current card has `.contentShape(RoundedRectangle(...))` combined with `.onTapGesture { onTap() }` applied to the entire card VStack. In SwiftUI, a parent `.onTapGesture` does NOT automatically yield to child gestures — the child gesture wins only when using `Button` or `.highPriorityGesture`. If per-ring taps are added as `.onTapGesture` on `WellnessRingView`, both gestures will fire simultaneously (child fires, then parent fires too), resulting in double navigation triggers.
   - Impact: Every ring tap would fire both the ring-specific navigation AND the old `showWellnessCalendar = true`, pushing two destinations simultaneously.
   - Recommendation: Remove the card-level `.onTapGesture` and `.contentShape` entirely when adding per-ring taps. Optionally retain a "tap empty area" gesture using `.simultaneousGesture` or restructure the rings to use `Button` (which properly isolates tap areas). Per-ring `Button` wrappers on `WellnessRingView` are the cleanest solution.

4. **WaterDetailView state sync: hydrationGlasses lives in HomeView with no proposed sharing mechanism**
   - Location: Plan step 3 — WaterDetailView; Plan step 2 — state wiring
   - Problem: `hydrationGlasses` is a `@State private var` in HomeView (line 19). `WaterDetailView` will be presented modally or as a pushed view. The plan mentions a "quick add button" in WaterDetailView. For mutations in WaterDetailView to be reflected in HomeView and persisted to SwiftData, the view needs either: (a) a `@Binding` to `hydrationGlasses` passed in, or (b) direct `@Environment(\.modelContext)` + `@Query` access to `WellnessDayLog`. The plan does not specify which approach is used.
   - Impact: Without a concrete sync mechanism, quick-add taps in WaterDetailView will either have no effect or cause double-write bugs if both HomeView and WaterDetailView independently write to SwiftData.
   - Recommendation: Pass `@Binding var hydrationGlasses: Int` into WaterDetailView and let HomeView's existing `onChange(of: hydrationGlasses)` handler persist to SwiftData — this is the minimal-change approach consistent with existing patterns. Alternatively, give WaterDetailView its own `@Environment(\.modelContext)` and `@Query` and bypass HomeView state entirely, but this requires removing the `@State` from HomeView to avoid divergence.

5. **StressView requires a `StressViewModel` init parameter — HomeView cannot create it correctly**
   - Location: Plan step 2 — `.navigationDestination` for StressView; `StressView.swift` line 34
   - Problem: `StressView` is initialized as `StressView(viewModel: StressViewModel(modelContext: modelContext))` in `MainTabView`. `StressViewModel` requires a `modelContext`. If HomeView were to create a second `StressView` instance via `.navigationDestination`, it would instantiate a second `StressViewModel`, triggering a second round of HealthKit permission requests and a second full 30-day data load on every navigation. This is expensive and architecturally incorrect.
   - Impact: Duplicate HealthKit queries, doubled memory usage for history arrays, potential race conditions writing to the same SwiftData store from two contexts.
   - Recommendation: This reinforces the recommendation in CRITICAL issue #1 — switch tabs programmatically instead of pushing a new StressView instance.

---

### MEDIUM (Fix During Implementation)

6. **`WellnessRingView` is `private struct` — plan must make it internal or restructure**
   - Location: `WellnessRingsCard.swift` line 73
   - Problem: `WellnessRingView` is declared `private struct`. The plan says to "make each WellnessRingView tappable." Adding a tap callback to a private struct requires either promoting it to internal, or keeping all tap logic inside `WellnessRingsCard`. The plan does not address this access level change.
   - Recommendation: Keep `WellnessRingView` private and add the per-ring tap as a parameter: `private struct WellnessRingView { let onTap: (() -> Void)? }`. The tap wiring stays internal to `WellnessRingsCard`. No access level change needed.

7. **Hint text "Tap to expand" becomes misleading but plan change may confuse new users**
   - Location: `WellnessRingsCard.swift` line 33 — "Tap to expand" capsule text
   - Problem: Plan says to change the hint to "Tap a ring to explore." However, if the WellnessCalendar navigation is removed (as implied), there is no longer a card-level tap action. If the calendar tap is retained alongside per-ring taps, the hint is accurate for rings but the card body between rings would also be tappable, which is inconsistent. The plan does not explicitly state whether WellnessCalendarView navigation is preserved.
   - Recommendation: Explicitly decide: (a) remove card-level tap entirely and show "Tap a ring to explore", or (b) keep card-level tap for calendar but make rings higher-priority. Document the decision in the spec.

8. **`FoodJournalView` navigation uses a shared `HomeViewModel` (`foodJournalViewModel`) — Calories ring tap would reuse it**
   - Location: HomeView line 113–115 — existing `.navigationDestination(isPresented: $showLogMeal)` pushes `FoodJournalView(viewModel: foodJournalViewModel)`
   - Problem: The plan routes the Calories ring to `FoodJournalView`. The existing food journal navigation (`showLogMeal`) already pushes `FoodJournalView` with the same `foodJournalViewModel`. If the plan adds a second `showFoodJournal` state boolean and a second `.navigationDestination`, there would be two separate booleans both showing the same view with the same VM. SwiftUI may activate both destinations under certain conditions.
   - Recommendation: Reuse the existing `showLogMeal` boolean for the Calories ring tap — `onRingTap(.calories) { showLogMeal = true }`. No new state variable needed for this case.

9. **Multiple `.navigationDestination(isPresented:)` modifiers in a single NavigationStack**
   - Location: HomeView lines 113–118; Plan step 2
   - Problem: SwiftUI's `NavigationStack` supports multiple `.navigationDestination(isPresented:)` modifiers, but Apple's documentation warns that only one should be active at a time. HomeView already has two (showLogMeal, showWellnessCalendar). Adding two more (showBurnView, showStressView) — even if BurnView/StressView were safe to push — increases the risk of state collisions (e.g., two booleans becoming true simultaneously) causing navigation stack corruption.
   - Recommendation: Consolidate navigation state into a single enum-based destination rather than four independent `@State` booleans. Example: `@State private var destination: HomeDestination?` with `enum HomeDestination { case foodJournal, wellnessCalendar, burnView, stressView, waterDetail }` and a single `.navigationDestination(item: $destination)`.

---

### LOW (Consider for Future)

10. **Animation re-trigger: navigating back to HomeView may re-run ring entrance animation**
    - Problem: `@State private var animate = false` in `WellnessRingsCard` is reset every time the card is re-created. Navigation push/pop in a `NavigationStack` re-renders the parent view, which may reset `animate` to `false` and replay the ring fill animation on every back-navigation.
    - Recommendation: Consider storing animation state outside the card (e.g., in a parent `@State` with `.onAppear` guard) or use `.task(id:)` with a stable identity to prevent replay.

11. **WaterDetailView glasss grid duplicates HydrationCard UI**
    - Problem: The plan proposes a glass grid in WaterDetailView. `HydrationCard` in HomeView already renders a tap-per-glass grid. Building a second glass grid in WaterDetailView risks UI divergence (different glass states, cap counts, visual style).
    - Recommendation: Extract the glass grid into a shared component, or consider whether WaterDetailView simply needs to be a deeper view of HydrationCard rather than a standalone view.

---

## Missing Elements

- [ ] No spec file exists for this feature (plan exists only as a conversational summary — no versioned document in `Docs/02_Planning/Specs/`)
- [ ] No rollback strategy defined (how to revert if per-ring taps cause navigation regressions)
- [ ] No test strategy mentioned (unit tests for ring dispatch, UI tests for navigation flows)
- [ ] No decision on whether WellnessCalendarView navigation is preserved or removed
- [ ] WaterDetailView data source not specified (does it read from `WellnessDayLog` via `@Query`, or via `@Binding` from HomeView?)
- [ ] No accessibility plan (each ring will need `.accessibilityLabel` and `.accessibilityHint` for VoiceOver)
- [ ] No haptic feedback plan for per-ring taps (existing card tap calls `HapticService.impact(.light)` — plan does not specify whether per-ring taps also trigger haptics)

---

## Unverified Assumptions

- [ ] Assumption: `WaterDetailView` can be a sheet or navigationDestination — **Risk: Medium** — depends on whether the chosen sync mechanism (Binding vs Query) works across presentation modes
- [ ] Assumption: Calories ring → FoodJournalView requires no new VM initialization — **Risk: Low** — confirmed, `foodJournalViewModel` is already available in HomeView
- [ ] Assumption: BurnView/StressView can be pushed as navigation destinations — **Risk: HIGH** — CONFIRMED FALSE by source code review; both embed their own `NavigationStack`
- [ ] Assumption: Per-ring taps will work without gesture conflicts with card-level tap — **Risk: HIGH** — CONFIRMED PROBLEMATIC; parent `.onTapGesture` fires simultaneously

---

## Security Considerations

- [ ] No security concerns specific to this feature (navigation only, no new data access)

---

## Performance Considerations

- [ ] Instantiating a second `StressViewModel` on ring tap would trigger 30-day HealthKit queries on every navigation (see HIGH issue #5)
- [ ] `WaterDetailView` hydration timeline may query or compute over all `WellnessDayLog` entries — ensure it uses a bounded fetch with date predicates, not a full table scan via `@Query`

---

## Questions for Clarification

1. Should the Burn and Stress ring taps switch tabs (tab 1 and tab 2) rather than push a new view? This appears to be the only architecturally safe option given both views embed `NavigationStack`.
2. Is the WellnessCalendar destination being removed entirely, or should tapping the card's non-ring areas still open it?
3. Should WaterDetailView be a sheet (like most detail views in the app) or a pushed navigation destination? The plan says both "sheet/navigationDestination" without committing.
4. Will WaterDetailView include a "remove glass" button (decrement), or only a "quick add" button? The HydrationCard supports both increment and decrement — parity is expected.
5. Is there a reason the Exercise ring navigates to BurnView (activity/energy) rather than a workout log? "Exercise ring" tracks minutes, but BurnView tracks active energy and steps — these are related but distinct metrics.

---

## Recommendations

1. **Replace BurnView/StressView push with tab switching.** Pass `@Binding var selectedTab: Int` from `MainTabView` into `HomeView`, and set `selectedTab = 1` (Burn) or `selectedTab = 2` (Stress) on ring tap. This is the correct pattern for tab-rooted views and avoids every issue related to nested NavigationStacks and duplicate ViewModels.
2. **Replace `onRingTap: (String) -> Void` with a typed enum** (`WellnessRingDestination`) before writing any code.
3. **Remove card-level `.onTapGesture`** or restructure rings as `Button` views to eliminate the dual-fire gesture conflict.
4. **Use `@Binding var hydrationGlasses: Int`** as the WaterDetailView state sync mechanism — it is consistent with how `HydrationCard` already receives its binding from HomeView.
5. **Write a spec file** to `Docs/02_Planning/Specs/` capturing the final decisions on tab switching vs push, WaterDetailView presentation mode, and WellnessCalendar fate before implementation begins.

---

## Sign-off Checklist

- [ ] All CRITICAL issues resolved
- [ ] All HIGH issues resolved or accepted
- [ ] Security review completed (N/A for this feature)
- [ ] Performance implications understood (duplicate VM / HealthKit query risk)
- [ ] Rollback strategy defined
