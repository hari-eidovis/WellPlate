# Plan Audit Report: StressView Dual-Mode UI

**Audit Date**: 2026-03-24
**Plan Version**: `Docs/02_Planning/Specs/260324-stress-view-dual-mode-ui.md`
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary
The plan is well-scoped and architecturally sound — no ViewModel changes, clean prop-passing interface, existing sheet pattern preserved. Two critical bugs (random animation duration in view body, unreliable Group transition) will cause visible runtime failures and must be fixed before implementation. Three high-priority gaps (screen-time factor sheet mapping, factor→sheet resolution in immersive view, safe area hardcoding) need concrete resolution steps added to the plan.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **`Double.random()` called inside view body — breaks looping animation**
   - Location: Phase 1, Step 1 — `AmbientBlobView`
   - Problem: The plan says "triggers a position + scale animation with `Animation.linear(duration: Double.random(in: 5...7))`". SwiftUI recreates view bodies frequently (on any state change, parent re-render, etc.). `Double.random()` in the body means each re-render picks a *new* random duration, resetting and jittering the animation — it will never loop smoothly.
   - Impact: Blobs will stutter and restart on every re-render instead of drifting continuously.
   - Recommendation: Store the random duration in `@State private var animDuration: Double = Double.random(in: 5...7)` initialised once per view instance. Then use `animDuration` in the `withAnimation` call inside `.onAppear`. Same fix for offset values if they are randomised.

2. **`.transition(.opacity)` on views inside `Group` is unreliable**
   - Location: Phase 4, Step 8 — `mainContent` conditional swap
   - Problem: SwiftUI's `Group` is layout-transparent and does not create an identity boundary. Attaching `.transition(.opacity)` to views inside a `Group` combined with `.animation(value:)` on the Group itself does not reliably cross-fade in all SwiftUI versions — the transition may be skipped or applied to the wrong layer. The recommended pattern for view-identity-based transitions is `ZStack` with explicit `.id()` or `if/else` inside a container with stable identity.
   - Impact: The toggle cross-fade may show a hard cut or incorrectly animate both branches simultaneously.
   - Recommendation: Replace the `Group { if isImmersive { … } else { … } }` pattern with:
     ```swift
     ZStack {
         if isImmersive {
             StressImmersiveView(…)
                 .transition(.opacity)
                 .zIndex(1)
         } else {
             improvedPlainScrollView
                 .transition(.opacity)
                 .zIndex(0)
         }
     }
     .animation(.easeInOut(duration: 0.5), value: isImmersive)
     ```
     This gives each branch a stable layout container and lets SwiftUI correctly insert/remove with the opacity transition.

---

### HIGH (Should Fix Before Proceeding)

3. **Screen Time factor sheet mapping gap in immersive view**
   - Location: Phase 2, Step 3 — `StressImmersiveView` factor pills, and Phase 4, Step 9 — `immersiveVitalRows`
   - Problem: In the plain view, `screenTimeFactor` is mapped to `sheet: nil` in `sortedFactors` because it needs *two* separate sheets (`.screenTimeDetail` and `.screenTimeEntry`). The plan doesn't define how the immersive factor pill for Screen Time handles this — `onFactorTap` only takes one `StressSheet`. If the pill calls `onFactorTap(.screenTimeDetail)`, the entry sheet is inaccessible in immersive mode.
   - Impact: Screen time entry flow is broken or silently dropped in immersive mode.
   - Recommendation: Add an explicit note in the plan: the Screen Time pill in immersive mode opens `.screenTimeDetail` only (matching behaviour of detail-sheet-capable factors). The entry sheet remains accessible through the detail view itself, which already has an entry path. Confirm this is the intended UX. If not, define a long-press or secondary button on the pill.

4. **No defined mechanism to map `StressFactorResult` → `StressSheet` in immersive view**
   - Location: Phase 2, Step 3 — `ImmersiveFactorPill` / `onFactorTap`
   - Problem: `StressImmersiveView` receives `factors: [StressFactorResult]` and `onFactorTap: (StressSheet) -> Void`. But `StressFactorResult` has no `StressSheet` field — the mapping lives in `StressView.sortedFactors` (the private `FactorItem` struct). The immersive view has no way to know which sheet to invoke for each factor without duplicating the mapping logic or receiving it as data.
   - Impact: Compiler error or incorrect sheet routing unless resolved before implementation.
   - Recommendation: Two options — (A) Pass `[(factor: StressFactorResult, sheet: StressSheet?)]` tuples instead of `[StressFactorResult]` from `StressView`, reusing the existing `sortedFactors` mapping. (B) Add a `sheet: StressSheet?` property to `StressFactorResult`. Option A is simpler and requires no model change. Add this to the plan explicitly.

5. **Hardcoded `.padding(.top, 56)` for safe area on toggle button**
   - Location: Phase 4, Step 7 — toggle button overlay
   - Problem: The plan specifies `.padding(.top, 56).padding(.trailing, 20)` to position the toggle in the "safe-area header zone". On iOS 26 with Dynamic Island, notch variants, or iPad multitasking, the top safe area inset varies (44 pt to 59 pt). A hardcoded 56 will misalign on some devices.
   - Impact: Toggle button clips into the Dynamic Island or sits too far below it on some devices.
   - Recommendation: Replace with `.safeAreaInset(edge: .top) { … }` or read `\.safeAreaInsets.top` from a `GeometryReader`. Alternatively, place the toggle button *inside* a `NavigationStack` toolbar (`.toolbar { ToolbarItem(placement: .topBarTrailing) { … } }`) — but note the current view hides the nav bar. Simplest fix: use `safeAreaInset(edge: .top, spacing: 0)` with a transparent spacer or pin using `ignoresSafeArea(.all, edges: .top)` and manual padding from safe area.

---

### MEDIUM (Fix During Implementation)

6. **`animPhase: Bool` parameter on `AmbientBlobView` is undefined and unused**
   - Problem: Step 1 lists `animPhase: Bool` as a parameter but no description of how it's set or what it controls. There's no step that passes a phased value, and no `@State` driver is described for it in the parent. It appears vestigial.
   - Recommendation: Remove `animPhase` from the interface or define it clearly (e.g. it could be a `@State private var phase = false` inside the blob view itself driven by `.onAppear`, which is simpler and self-contained).

7. **`drawingGroup()` mitigation mentioned in Risks but absent from implementation steps**
   - Problem: The Risks section says "Use `drawingGroup()` on the blob ZStack to composite to Metal layer" to prevent jank. However no implementation step calls this out. Implementers following the steps sequentially will miss it.
   - Recommendation: Add `.drawingGroup()` explicitly to Step 2 in the `StressImmersiveBackground` ZStack construction.

8. **Immersive view always forces dark appearance — light mode UX not addressed**
   - Problem: Background is `Color.black` + colored blobs. In light system appearance, abruptly switching to a fully black screen will feel jarring and inconsistent with the rest of the app which uses `systemGroupedBackground`.
   - Recommendation: Either (A) force dark color scheme on the immersive view via `.preferredColorScheme(.dark)`, which makes the intent explicit and ensures text/material contrast is correct, or (B) use a very dark tinted color instead of pure black for the base layer (e.g. `Color(hue: levelColor.hue, saturation: 0.4, brightness: 0.08)`). Add this decision to the plan.

9. **`StressScoreGaugeView` `immersive` flag changes size implicitly — existing callers unaffected but confusing**
   - Problem: The plan says "increase default size to 260 when immersive == true". The existing default `size: CGFloat = 230` is a stored property, not derived from `immersive`. If the implementer adds `immersive` without also adjusting the `size` parameter default conditionally, the gauge won't actually grow. The plan needs to clarify that the `immersive` flag acts as a computed override: `effective size = immersive ? 260 : size`.
   - Recommendation: Clarify step 5: when `immersive == true`, the view ignores the `size` parameter and uses 260 internally (or simply always pass `size: 260` at the call site in `StressImmersiveView`).

10. **Plain view vitals 3-column `LazyVGrid` — vitals have unequal content lengths**
    - Problem: The existing `vitalsQuickSection` shows Heart Rate (with resting HR subtitle), Sleep Quality (multi-line), and Activity — each has 3 lines of text. A 3-column `LazyVGrid` with `GridItem(.flexible())` will produce very narrow cells on standard 390pt screens (~110 pt per cell). Multi-line subtitles will truncate or overflow.
    - Recommendation: Use a 2-column grid instead, or use a horizontally scrolling row for the vitals tiles (matching the immersive view's compact tile row). Alternatively, keep the existing stacked rows in the plain view and only use a grid for the immersive mode compact tiles.

---

### LOW (Consider for Future)

11. **Background animations run when tab is inactive**
    - Problem: No `.onDisappear` / `.task` cancellation is planned for blob animations. On iOS, SwiftUI does pause CAAnimations for non-visible views, but SwiftUI's own `withAnimation` repeat loops may continue consuming state updates.
    - Recommendation: Add `@State private var isVisible = false` in `StressImmersiveView`, toggle it via `.onAppear` / `.onDisappear`, and condition the animation start on `isVisible`. Low urgency — iOS handles most of this, but explicit control is cleaner.

12. **`ImmersiveFactorPill` is never defined in a dedicated step**
    - Problem: Step 3 references `ImmersiveFactorPill` as a subview but it has no own implementation step. Implementers need to infer its structure from the description in step 3.
    - Recommendation: Either add a sub-bullet defining the pill's exact interface and layout, or note it's a private `@ViewBuilder` func inside `StressImmersiveView`.

---

## Missing Elements
- [ ] How Screen Time double-sheet UX works in immersive mode (detail vs. entry)
- [ ] Explicit `drawingGroup()` call in implementation steps
- [ ] Decision on light-mode appearance for immersive background
- [ ] `ImmersiveFactorPill` interface spec
- [ ] Factor→Sheet mapping strategy passed into `StressImmersiveView`

## Unverified Assumptions
- [ ] `StressFactorResult.id` is stable across factor re-sorts — used in `ForEach(sortedFactors, id: \.factor.id)`. Risk: Low (confirmed as `title` string in model)
- [ ] `HapticService.impact(.light)` is accessible from `StressImmersiveView` — Risk: Low (it's a static utility, not injected)
- [ ] iOS 26 simulator renders `.ultraThinMaterial` correctly over dark backgrounds — Risk: Low

## Performance Considerations
- [ ] Three simultaneously animating blobs + gauge halo = 4 concurrent repeat animations. On devices with `UIAccessibility.isReduceMotionEnabled`, these should all be suppressed. The plan has no `@Environment(\.accessibilityReduceMotion)` guard.
- [ ] `drawingGroup()` is mentioned as a mitigation in Risks but omitted from steps — must be included to avoid compositing overhead on older Metal GPUs.

## Questions for Clarification
1. Should the immersive view show the timeline charts (day/week) at all, or is it intentionally gauge+factors only? The plan omits them from immersive mode — confirm this is intentional.
2. Should `refreshable { }` pull-to-refresh work in immersive mode? Currently `StressImmersiveView` is not a `ScrollView` so it won't support it.
3. Is the debug screen time section expected to be visible in immersive mode? The plan doesn't mention it.

## Recommendations
1. Fix critical issues 1 and 2 in the plan before implementation begins — both are SwiftUI fundamentals that will cause immediately visible bugs.
2. Resolve the factor→sheet mapping strategy (issue 4) by passing tuples instead of bare `StressFactorResult` — this is a one-line change to the `StressImmersiveView` interface and eliminates ambiguity.
3. Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to `AmbientBlobView` and `StressImmersiveView` — gate all `repeatForever` animations behind `if !reduceMotion`.
4. Keep the `LazyVGrid` vitals layout as a 2-column grid or horizontal scroll row, not 3-column — content width is too constrained at 3 columns on 390pt phones.

## Sign-off Checklist
- [ ] Critical issue 1 resolved (random duration in @State)
- [ ] Critical issue 2 resolved (ZStack transition pattern)
- [ ] High issue 3 resolved (screen time sheet strategy defined)
- [ ] High issue 4 resolved (factor→sheet tuple interface)
- [ ] High issue 5 resolved (safe area handling)
- [ ] `drawingGroup()` added to implementation steps
- [ ] Reduce motion guard added
- [ ] Light-mode immersive background decision documented
