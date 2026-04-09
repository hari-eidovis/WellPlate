# Plan Audit Report: Liquid Glass Hero Header + UI/UX Polish — ProgressInsightsView

**Audit Date**: 2026-02-19
**Plan File**: `/Users/hariom/.claude/plans/jolly-crunching-rabbit.md`
**Source File**: `WellPlate/Features + UI/Progress/Views/ProgressInsightsView.swift` (997 lines)
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan presents a coherent liquid glass aesthetic upgrade but contains four issues that will either crash the build or produce broken runtime behavior. The pull-to-dismiss gesture (Phase 4b) is fundamentally incompatible with the existing ScrollView architecture and will make the view unscrollable or untappable. The Phase 5 nav bar background replacement contains invalid Swift syntax that will not compile. The sticky selector placement in the overlay adds silent vertical height to the status-bar-only overlay zone, potentially clipping the selector. Additionally, the plan's instruction to remove the share button from the hero header introduces a regression when `scrollProgress` is 0 (the share button in the nav overlay is invisible until the user scrolls). These issues must be resolved before implementation begins.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **Phase 4b: Pull-to-dismiss `DragGesture` will fight the ScrollView and produce an unusable view**
   - Location: Phase 4b, `.gesture(DragGesture()...)` on the main `ZStack`
   - Problem: The plan attaches a bare `DragGesture()` (default `minimumDistance: 0`) to the outer `ZStack` that wraps the `ScrollView`. A plain `.gesture()` applied to a container that contains a `ScrollView` gives the scroll view exclusive claim on all vertical pan gestures — the outer gesture will never fire. Even if `.simultaneousGesture()` is used instead (as the Critical Implementation Note #4 hints at), there is a second fatal problem: the plan's gesture has no guard against `scrollOffset`. The `scrollOffset` `@State` variable is updated asynchronously via `onPreferenceChange` (which uses `withAnimation`), meaning there is no reliable synchronous check on scroll position when the drag begins. The result is either (a) the gesture is suppressed entirely by the scroll view, or (b) if attached with `simultaneousGesture`, dragging down while the list is scrolled mid-way fires the dismiss gesture and closes the view unexpectedly.
   - The Critical Implementation Note #4 in the plan says "only activate when `scrollOffset >= 0`" but provides no code for this guard — it is left completely unimplemented in the gesture snippet.
   - Impact: Either the dismiss gesture silently never fires, or the view unexpectedly dismisses while the user scrolls down through content. The `.offset(y: dragToDismissOffset * 0.35)` on the `ZStack` also conflicts with the `GeometryReader`-based scroll tracking coordinate space `"scrollArea"` — offsetting the ZStack will shift the origin of the coordinate space, producing wrong `scrollOffset` values and breaking the entire nav bar appearance animation.
   - Recommendation: (a) Replace with a `UIScrollViewDelegate`-based approach that checks `contentOffset.y <= 0` before activating dismiss, OR (b) attach the gesture exclusively to the `heroHeader` drag indicator pill (which is not inside the scroll view) and skip the rubber-band offset effect entirely to avoid the coordinate space problem.

2. **Phase 5: Code snippet contains invalid Swift syntax — will not compile**
   - Location: Phase 5, "Simplest correct approach" code block
   - Problem: The plan shows:
     ```swift
     .background(
         ZStack {
             Rectangle().fill(.regularMaterial)
             Rectangle().fill(Color(hex: "FF6B35").opacity(0.7))
         }
         .opacity(scrollProgress)
     )
     ```
     `Rectangle().fill(.regularMaterial)` is not valid Swift. `.regularMaterial` is a `Material` type, not a `ShapeStyle` that can be passed directly to `Shape.fill()` via a bare dot syntax without an explicit type. The correct invocation is `Rectangle().fill(Material.regular)` or `Rectangle().background(.regularMaterial)`. Using `.fill(.regularMaterial)` will produce a compiler error: "type 'Material' has no member 'regularMaterial'" or "cannot convert value of type 'Material' to expected argument type".
   - Additionally, the comment `// BEFORE (line ~210)` points to line 210, but the actual background is on lines 208–211 (a multi-line `.background(...)` block, not a single-line replacement). The implementer will need to replace a 4-line block, not a 1-line replacement.
   - Impact: Build failure if code is copied verbatim.
   - Recommendation: Replace with the correct syntax using `ZStack` with a `Rectangle().background(.regularMaterial)` layer, or use `.background(.regularMaterial).overlay(Color(hex: "FF6B35").opacity(scrollProgress * 0.7))` chained on the `HStack`.

---

### HIGH (Should Fix Before Proceeding)

3. **Share button accessibility regression: zero access when scrollProgress == 0**
   - Location: Phase 1c, "Remove the share button from the hero header entirely"
   - Problem: The plan removes the share button (`Image(systemName: "square.and.arrow.up")`) from the `heroHeader` ZStack (lines 261–270 of the current file). The share button is also present in the scrolled-in nav bar overlay (lines 187–195). However, the nav bar overlay has `.opacity(scrollProgress)` applied at line 213, which means the entire nav bar (including the share button) is completely invisible and non-interactive when `scrollProgress == 0` (i.e., when the user first opens the view and the hero header is fully visible). After removing the hero share button, there is NO accessible share button for the user until they scroll at least ~80pt into the content. This is a functional regression — on first open, the share action is silently inaccessible.
   - Impact: Users who immediately want to share upon opening the view cannot do so. UX regression.
   - Recommendation: Either (a) keep the share button in the hero header alongside the close button (do not remove it), only applying the glass styling upgrade, OR (b) set a minimum opacity of ~0.25 on the share button in the nav bar overlay independently of `scrollProgress` so it is always accessible, OR (c) move share to a toolbar item that is always visible.

4. **Sticky time range selector position is ambiguous within the overlay structure — visual conflict is plausible**
   - Location: Phase 2, insertion point "below the existing nav bar HStack"
   - Problem: The plan proposes inserting the sticky selector inside the existing `.overlay(alignment: .top)` block (lines 165–215), which currently contains only a `VStack` with the status-bar color fill and the nav bar row. The current `VStack(spacing: 0)` renders:
     - Row 1: `Color(hex: "FF6B35")` with height `safeTopInset` (the status bar area, ~59pt on iPhone 16 Pro)
     - Row 2: The `HStack` nav bar row with `.padding(.vertical, 10)` (~52pt total)
   - The entire `VStack` has `.opacity(scrollProgress)` applied at line 213. This means the sticky selector, if placed inside this `VStack`, will ALSO fade in via `scrollProgress` — but the plan also adds a separate `.opacity(min(1, (scrollProgress - 0.75) / 0.25))` on the selector itself. The effective opacity will be `scrollProgress * min(1, (scrollProgress - 0.75) / 0.25)` — a compounded fade that does not reach full opacity until `scrollProgress == 1.0`, which may never be fully reached depending on content length.
   - Additionally, the plan uses `.transition(.move(edge: .top).combined(with: .opacity))` wrapped in an `if scrollProgress > 0.75` condition, but SwiftUI `if`-based transitions inside overlays require the surrounding view to be inside an `animation()` or `withAnimation` scope — the overlay itself is not animated. The `.transition` modifier will be silently ignored.
   - Impact: The sticky selector may appear at incorrect opacity, and the slide-in transition animation will not fire.
   - Recommendation: Move the sticky selector to a SEPARATE second `.overlay(alignment: .top)` modifier applied after the nav bar overlay, so it has its own independent opacity control. Remove the `.transition()` modifier and use `.animation(.easeInOut, value: scrollProgress)` on the selector view directly.

5. **Phase 4a: `NavigationView` → `NavigationStack` migration requires deployment target verification**
   - Location: Phase 4a, line ~101
   - Problem: `NavigationStack` was introduced in iOS 16. The Xcode project's `IPHONEOS_DEPLOYMENT_TARGET` is set to `26.1` (which is an unusual/pre-release version number — likely a placeholder or typo in the project file for iOS 16+). If the actual deployment target is iOS 16+, this migration is safe. However, the plan makes no mention of verifying this.
   - More critically: the comment at line 164 in the source reads "Sits OUTSIDE NavigationView so it renders above the system white fill." This comment documents that the overlay pattern exists specifically to work around a `NavigationView` rendering issue (the system white fill on the navigation bar area). When switching to `NavigationStack`, the behavior of `.navigationBarHidden(true)` + the system bar rendering may change. `NavigationStack` handles `navigationBarHidden` differently and may not exhibit the same white-fill artifact that the overlay was designed to fix — meaning the overlay could become redundant or cause double-rendering.
   - Impact: Potential visual regression on the nav bar after migration, or unnecessary overlay complexity that should be cleaned up.
   - Recommendation: Verify deployment target is iOS 16+. After switching to `NavigationStack`, test whether `.navigationBarHidden(true)` still requires the external overlay or whether the system handles it correctly.

6. **Phase 1e: `calculateCurrentStreak()` called inside a `@ViewBuilder` context with `let streak = ...` — may cause compiler issues**
   - Location: Phase 1e, "Replace the `maxCalories` badge with streak days"
   - Problem: The plan shows:
     ```swift
     let streak = calculateCurrentStreak()
     HeroBadge(value: streak > 0 ? "\(streak)🔥" : "–", label: "day streak")
     ```
     This `let` binding is used inside `HStack(spacing: 8) { ... }` which is a `@ViewBuilder` closure. In SwiftUI, `let` bindings are allowed in `@ViewBuilder` closures (they are treated as local declarations), but `calculateCurrentStreak()` is a computed function that iterates over `dailyAggregates` — the same data already computed by `currentPeriodStats`. This is called on every render pass of `heroHeader`. While not a crash, it is a performance concern (O(n) re-sort on every frame).
   - More critically: `calculateCurrentStreak()` is already called at line 678 inside `trendsCard` (in the view body) AND would now be called again in `heroHeader`. The function is not memoized.
   - Impact: Minor performance regression; double computation of streak on every render. For a 90-day window (max query) this is ~90 iterations, which is acceptable but unnecessary.
   - Recommendation: Promote `calculateCurrentStreak()` result to a `private var currentStreak: Int` computed property alongside `currentPeriodStats`, so it is computed once and reused across both `heroHeader` and `trendsCard`.

---

### MEDIUM (Fix During Implementation)

7. **Phase 1a: `.ultraThinMaterial` blobs placed INSIDE the orange `LinearGradient` ZStack — material rendering is non-deterministic on iOS**
   - Problem: The plan states "When placed over the orange gradient, `.ultraThinMaterial` picks up the vibrancy and renders as a frosted white/translucent pane." This is partially correct but incomplete. On iOS, `Material` (including `.ultraThinMaterial`) uses a `UIBlurEffect` internally. When placed inside a `ZStack` over a gradient that is in the same rendering tree, the blur samples the content BEHIND the material — but in a `ZStack`, "behind" means the gradient that is defined earlier in the `ZStack`. The blur radius of `.ultraThinMaterial` is approximately 20–30pt. The orange gradient has very low contrast variation across that radius, so the material will render as nearly transparent frosted glass with a slight warm tint. This IS the intended effect. However, the `.blur(radius: 2)` on the existing `Circle()` in the current code (line 239) was providing a soft-glow look. The new blobs have no blur and will render as hard-edged frosted panes unless the `Ellipse`/`Circle` shapes have soft edges — which they do not by default.
   - Recommendation: Add `.blur(radius: 30)` to each blob's `Ellipse`/`Circle` frame to soften the edges and produce the organic "aurora" look the plan describes. Without blur, these will look like hard-edged frosted rectangles, not aurora blobs.

8. **Phase 1b: `HeroBadge` glass upgrade — text legibility on `.ultraThinMaterial` is unverified**
   - Problem: `HeroBadge` currently uses `.foregroundColor(.white)` for its text. After switching the background to `.ultraThinMaterial` (which renders as a semi-transparent frosted surface with an orange-warm tint from the hero gradient), white text on this background may have insufficient contrast — especially for the `label` text that is already at `.opacity(0.75)`. The badge will now blend into the orange gradient more than the previous solid-white fill.
   - Recommendation: After implementing, verify WCAG AA contrast ratio (4.5:1 minimum) for the label text against the material background. Consider bumping label opacity from `0.75` to `0.9` or switching to `.white` fully.

9. **Phase 1d: Hero bottom scrim uses `Color(hex:)` — extension must be present**
   - Problem: The scrim uses `Color(hex: colorScheme == .dark ? "0F0F1A" : "F5F5FF")`. The `Color(hex:)` extension is used throughout the file and is presumably available, but the plan does not reference where it is defined. If it lives in a separate extension file, there is no risk. However, if it is ever refactored or moved, this will break silently.
   - Recommendation: No blocking action required; confirm the `Color(hex:)` extension is in a shared location (e.g., `Extensions/Color+Hex.swift`) and not inline in another feature file.

10. **Phase 4c: Drag indicator pill placement uses `safeTopInset` which may be 0 during first render**
    - Problem: `safeTopInset` is populated via a `GeometryReader { outerGeo in Color.clear.onAppear { safeTopInset = outerGeo.safeAreaInsets.top } }` (lines 108–112). This fires on first appear, but the `heroHeader` view is rendered in a `ScrollView` content area with `.ignoresSafeArea(edges: .top)`. The `GeometryReader` that captures `safeTopInset` is OUTSIDE the scroll view (in the `ZStack`), so there is a one-render-pass delay. The drag indicator pill will be positioned at `.padding(.top, 0 + 8)` on the very first frame, then jump to the correct position when `safeTopInset` is populated. This produces a visible 1-frame jump.
    - Recommendation: Use `.padding(.top, safeTopInset + 8).animation(nil, value: safeTopInset)` to suppress the animation of the first-frame correction, or initialize `safeTopInset` with a reasonable default (e.g., `47`) matching the most common device.

11. **Phase 3: `GlassCardModifier` now takes `@Environment(\.colorScheme)` — impacts all 6+ call sites**
    - Problem: The current `GlassCardModifier` has no environment dependencies. Adding `@Environment(\.colorScheme)` to it is safe in isolation, but the modifier is used across 6+ call sites (`.glassCard(background: cardBackground, shadowColor: cardShadowColor)`). The `colorScheme` environment variable will propagate correctly through each call site. However, the `.ultraThinMaterial` overlay inside the modifier (for dark mode) adds a second material layer on top of `cardBackground` (which is `Color(hex: "1C1C2E")`). This will shift the card color to a lighter/different shade in dark mode and may visually conflict with the dark mode background color choice that was previously intentional. The previous dark mode card style used a very specific dark navy (`1C1C2E`) to create separation from the background (`0F0F1A`); the material overlay will tint this differently.
    - Recommendation: Preview the dark mode cards specifically before committing. If the material overlay washes out the intended dark navy color, reduce the material opacity from `0.35` to `0.15–0.20`.

---

### LOW (Consider for Future)

12. **`@State private var auroraPhase: CGFloat = 0` not declared in plan's state variable list**
    - Problem: The plan mentions adding this state in Phase 1a but does not provide a comprehensive "new `@State` variables" summary. The plan also requires `@State private var dragToDismissOffset: CGFloat = 0` (Phase 4b). Both need to be added to the `ProgressInsightsView` struct body alongside existing state variables. This is documentation clarity, not a blocking issue.
    - Recommendation: Add a "New State Variables Required" section to the plan listing both variables explicitly.

13. **`StatusBarStyleModifier` and drag-to-dismiss visual conflict**
    - Problem: `StatusBarStyleModifier` is a `UIViewControllerRepresentable` that forces `preferredStatusBarStyle` to `.lightContent`. When the drag-to-dismiss gesture applies `dragToDismissOffset * 0.35` as a vertical offset to the outer `ZStack`, the `StatusBarViewController` (being a UIKit-hosted `UIViewController`) does not participate in SwiftUI layout — it renders at a fixed position and will NOT move with the dragged content. The status bar icons will remain light (white) even as the view slides down and exposes the underlying `HomeView` content behind it during the drag. This creates an inconsistency where the status bar style does not match the visible content when the drag is in progress.
    - Impact: Low — cosmetic only, since the transition is brief. But on devices with light-colored `HomeView` backgrounds, white status bar icons on light content during drag may be hard to read.
    - Recommendation: Dismiss the `StatusBarViewController`'s effect by either removing `StatusBarStyleModifier` when `dragToDismissOffset > 20` (conditional rendering), or accepting the brief visual inconsistency.

14. **`timeRangeSelector` used as a `var` — potential SwiftUI identity issues when reused in sticky position**
    - Problem: `timeRangeSelector` is defined as `private var timeRangeSelector: some View`. SwiftUI uses structural identity for `var`-based views. Using the same `var` in two different layout positions (inline in the ScrollView VStack and in the overlay) means SwiftUI will treat them as two separate view instances. State changes (like `selectedTimeRange`) will animate independently in each instance. Since both read/write the same `@State` variable, the visual selection highlight will animate correctly on both, but the animation timing may differ (the overlay has an extra `.animation` or `.transition` modifier). This is not a blocking issue but worth noting.

15. **iOS deployment target shows `26.1` in project.pbxproj — likely a pre-release/placeholder value**
    - Problem: The Xcode project file lists `IPHONEOS_DEPLOYMENT_TARGET = 26.1`. This appears to be a pre-release SDK version number, likely meaning iOS 16 or beyond (possibly set for a beta SDK during development). All APIs used in this plan (`.ultraThinMaterial`, `Material`, `NavigationStack`, `@ViewBuilder` let bindings) require iOS 15+ minimum. `.regularMaterial` requires iOS 15+. If the actual target device is iOS 15+, all plan APIs are available. If the target is iOS 14 or lower, none of the Material APIs will work.
    - Recommendation: Confirm the actual minimum supported iOS version. If it is iOS 15+, add a comment to the plan confirming compatibility. The `26.1` value in the project file should be cleaned up.

---

## Missing Elements

- [ ] No guard on `scrollOffset` in pull-to-dismiss gesture — plan acknowledges this in Critical Note #4 but provides no code
- [ ] No `minimumDistance` specified in the plan's `DragGesture()` initializer (Note #4 says to use 15, but the code snippet uses the default)
- [ ] No rollback strategy defined for any of the 5 phases
- [ ] No test strategy (Xcode Previews are mentioned but no unit/UI tests)
- [ ] Missing comprehensive list of all new `@State` variables required
- [ ] `Color(hex:)` extension source location not verified
- [ ] No mention of how the hero scrim (`1d`) interacts in dark mode when `colorScheme == .dark` — the destination color `"0F0F1A"` must match exactly or a visible seam will appear between the scrim and the card area background
- [ ] Phase 5 "Before" comment says line `~210` but the actual background modifier is a 4-line block (lines 208–211) — the implementer will need clearer replacement instructions

---

## Unverified Assumptions

- [ ] `.ultraThinMaterial` renders as "frosted white/translucent pane" over orange gradient — correct in theory but depends on the rendering context; background blur may not apply within the same `ZStack` layer. Risk: **Medium**
- [ ] "Sticky selector and inline selector are visually non-overlapping" — the plan asserts the inline one "naturally scrolls off screen" before the sticky one appears. This depends on the inline selector's scroll position at `scrollProgress == 0.75`. If the screen is short or the font size is large (Dynamic Type), the selector may still be partially visible when the sticky one fades in. Risk: **Medium**
- [ ] The `VStack(spacing: 0)` overlay `opacity(scrollProgress)` applies to the entire VStack — confirmed by source code (line 213). The plan does not account for this compounding opacity on the sticky selector. Risk: **High** (flagged as CRITICAL issue #4 above)
- [ ] `NavigationStack` behaves identically to `NavigationView` with `navigationBarHidden(true)` — not guaranteed; the overlay pattern comment explicitly says it exists to work around NavigationView rendering. Risk: **Medium**
- [ ] `dragToDismissOffset` `.offset(y:)` on the outer ZStack does not corrupt the `"scrollArea"` coordinate space — this assumption is incorrect; offsetting a `ZStack` that contains a `ScrollView` using a named coordinate space WILL shift all preference key values. Risk: **High** (flagged as CRITICAL above)
- [ ] Share button in scrolled nav bar covers all share access needs — incorrect when `scrollProgress == 0`. Risk: **High** (flagged as HIGH issue above)

---

## Security Considerations

- None applicable. This is a pure UI rendering change with no network calls, data persistence, or authentication logic.

---

## Performance Considerations

- [ ] Aurora blobs with `.ultraThinMaterial` render using a `UIVisualEffectView` internally. Three simultaneous material views in a `ZStack` with `withAnimation(.easeInOut(duration: 6).repeatForever)` driven transforms (`rotationEffect`, `offset`) will cause continuous Core Animation transactions every 6 seconds. On older devices (iPhone XR/11 era), this may cause mild frame drops during the animation — especially combined with the existing `scrollOffset` preference key animation.
- [ ] `calculateCurrentStreak()` is O(n log n) due to `.sorted(by:)` on `dailyAggregates` (which can be up to 90 days = 90 elements). Called during every re-render of `heroHeader`. Should be promoted to a stored computed property.
- [ ] `GlassCardModifier` with `.ultraThinMaterial` overlay on dark mode will add one extra material rendering pass per card. With 6 cards on screen, this means 6 simultaneous `UIVisualEffectView` instances in addition to the 3 aurora blobs = 9 total material renders. This is within acceptable range for modern devices but should be monitored.

---

## Questions for Clarification

1. Does the plan intend `DragGesture` to be `.gesture()` or `.simultaneousGesture()`? The code snippet uses `.gesture()` but Critical Note #4 implies concurrent activation with scroll, which requires `.simultaneousGesture()`. The behavior is fundamentally different.
2. Should the `.opacity(scrollProgress)` on line 213 (which applies to the entire overlay VStack) be changed to allow the sticky selector to have independent opacity control? The plan adds to the existing VStack but does not address this compounding opacity issue.
3. The plan removes the share button from the hero header — is the intent that share is only accessible after scrolling, or should share always be accessible? If always accessible, the plan needs a revised approach.
4. Does the drag indicator pill (Phase 4c) use `safeTopInset + 8` because the pill is placed outside the `GeometryReader` block? If so, how does the `heroHeader` access `safeTopInset` — it is a `@State var` on the parent view, so it is accessible, but the initial-value flash issue (item 10 in MEDIUM) still needs to be addressed.
5. The plan says to add the aurora phase animation in `.onAppear` "which is already in the view." The `.onAppear` at line 154–161 runs `withAnimation` for `headerAppeared` and `DispatchQueue.asyncAfter` for `cardsAppeared`. Should `auroraPhase` animation be added inside the existing `withAnimation` block or as a separate `withAnimation` call?

---

## Recommendations

1. **Phase 4b (pull-to-dismiss) must be redesigned before implementation.** The current approach has two fatal flaws (gesture suppression by ScrollView + coordinate space corruption). The simplest safe alternative is: attach the `DragGesture` exclusively to the drag indicator pill in `heroHeader` (which is above the scroll view), remove the `ZStack`-level `.offset()`, and call `dismiss()` without rubber-banding. Or use `UIScrollViewDelegate` integration via a `UIViewRepresentable` wrapper on the ScrollView.

2. **Phase 5 syntax error must be corrected.** Use `Rectangle().background(.regularMaterial)` or `Rectangle().fill(Material.regular)` — not `Rectangle().fill(.regularMaterial)`.

3. **Add a second independent overlay for the sticky selector.** Chain a new `.overlay(alignment: .top)` modifier after the nav bar overlay, so the sticky selector has its own independent opacity (not compounded with the `scrollProgress` fade of the outer VStack). This also resolves the `.transition()` animation issue.

4. **Keep the share button in the hero header** until the nav bar overlay's share button is decoupled from the `scrollProgress` opacity fade. Or, set a minimum opacity on the nav bar share button so it is always interactive.

5. **Add `.blur(radius: 25–30)` to each aurora blob** to achieve the soft organic glow the plan describes. Without blur, the `Ellipse`/`Circle` shapes with `.ultraThinMaterial` fill will appear as hard-edged frosted panes, not aurora blobs.

6. **Promote `calculateCurrentStreak()` to a `private var`** so it computes once per render cycle and is reused by both `heroHeader` (new badge) and `trendsCard` (existing usage at line 678).

---

## Sign-off Checklist

- [ ] CRITICAL issue #1 resolved (pull-to-dismiss gesture redesigned for ScrollView compatibility + coordinate space safety)
- [ ] CRITICAL issue #2 resolved (Phase 5 Swift syntax corrected: `.fill(.regularMaterial)` → valid syntax)
- [ ] HIGH issue #3 resolved (share button accessibility at scrollProgress == 0 addressed)
- [ ] HIGH issue #4 resolved (sticky selector moved to independent overlay; compounded opacity addressed)
- [ ] HIGH issue #5 resolved (NavigationStack migration verified against deployment target and overlay behavior)
- [ ] HIGH issue #6 resolved (streak computation memoized as `private var`)
- [ ] Security review completed (N/A — UI-only change)
- [ ] Performance implications understood (material renders × 9 on-screen; aurora animation continuous; streak O(n) per frame)
- [ ] Rollback strategy defined (all changes are local to one file; git revert or stash is sufficient)
