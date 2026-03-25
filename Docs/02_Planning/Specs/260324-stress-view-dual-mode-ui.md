# Implementation Plan: StressView Dual-Mode UI

## Overview
Add a top-right toggle to `StressView` that switches between two presentation modes: an **Immersive animated view** (ambient glowing background, floating blobs, glassmorphic cards) and the existing **Info-rich plain view** (improved scrollable layout with cleaner hierarchy). All animations are slow and subtle (3–6 s ambient, spring for taps). No new SwiftData models, no new sheets, no ViewModel changes.

## Requirements
- Toggle button top-right persists mode in `@AppStorage("stressViewImmersive")`
- Immersive mode: dark ambient background tinted by stress level, 3 slowly-drifting blob orbs, pulsing glow halo on gauge, glassmorphic factor pills, score as full-screen hero
- Plain mode: current scrollable content polished — tighter section headers, card shadows using `appShadow`, better vitals grid, all existing data preserved
- Transition between modes: `.transition(.opacity)` with `.animation(.easeInOut(duration: 0.5))`
- Animations must be slow and subtle — no jarring motion; ambient blobs use `Animation.linear(duration: 6).repeatForever(autoreverses: true)`
- All existing sheet navigation (`.sheet(item: $activeSheet)`) untouched
- Builds cleanly — no new external dependencies

## Architecture Changes
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add `@AppStorage` toggle state, conditional branching between two layout functions, toggle button in overlay
- `WellPlate/Features + UI/Stress/Views/StressImmersiveView.swift` (**new**) — self-contained immersive layout view; receives ViewModel data as plain value props (no direct ViewModel reference to keep it testable)
- `WellPlate/Features + UI/Stress/Views/AmbientBlobView.swift` (**new**) — reusable animated blob orb component used by immersive background
- `WellPlate/Features + UI/Stress/Views/StressScoreGaugeView.swift` — add optional `immersive: Bool` parameter to show larger size + breathing halo variant

## Implementation Steps

### Phase 1: Ambient Background Infrastructure

1. **Create `AmbientBlobView`** (File: `WellPlate/Features + UI/Stress/Views/AmbientBlobView.swift`)
   - Action: A `View` that renders a single soft radial-gradient circle. Accepts `color: Color`, `size: CGFloat`, `offsetX/Y: CGFloat`, `animPhase: Bool`. On `onAppear` triggers a position + scale animation with `Animation.linear(duration: Double.random(in: 5...7)).repeatForever(autoreverses: true)`. Opacity fixed at 0.18–0.25.
   - Why: Isolated blob keeps StressImmersiveView clean and lets each orb have independent timing
   - Dependencies: None
   - Risk: Low

2. **Create `StressImmersiveBackground`** (inline private struct inside `StressImmersiveView`)
   - Action: `ZStack` of: (1) full-bleed `Color.black`, (2) three `AmbientBlobView` instances using `level.color`, `.purple`, and `.indigo` at different sizes (280, 220, 180 pt) and staggered positions. Each blob starts at different offsets and animates to mirrored offsets. (3) a thin `LinearGradient` overlay `[.black.opacity(0.3), .clear]` top-to-bottom for readability.
   - Why: Layering gives depth without GPU cost; three blobs cover the screen naturally
   - Dependencies: Step 1
   - Risk: Low

### Phase 2: Immersive Layout View

3. **Create `StressImmersiveView`** (File: `WellPlate/Features + UI/Stress/Views/StressImmersiveView.swift`)
   - Action: A standalone `View` with props: `score: Double`, `level: StressLevel`, `factors: [StressFactorResult]`, `vitalRows: [ImmersiveVitalRow]`, `onFactorTap: (StressSheet) -> Void`. Layout:
     - **Background**: `StressImmersiveBackground` fullscreen via `ZStack` + `.ignoresSafeArea()`
     - **Hero gauge**: `StressScoreGaugeView(score:, level:, immersive: true)` centered at ~42% from top, size 260. Add a `breathing halo` — a `Circle` with `level.color.opacity(pulseOpacity)` blurred 40 pt, animated between 0.12 and 0.22 on a 4 s linear repeat
     - **Comparison badge**: same capsule badge as plain view, positioned below gauge
     - **Factor pills strip**: horizontal `ScrollView(.horizontal)` of compact `ImmersiveFactorPill` subviews — each is a `HStack(icon, title, score)` inside a `RoundedRectangle` filled with `.ultraThinMaterial` + colored left border 3 pt. Tappable → calls `onFactorTap`.
     - **Vitals row**: horizontal `HStack` of 3 compact stat tiles (HR, Sleep, Activity) using `.ultraThinMaterial` background, icon + value label
   - Why: Keeps immersive layout self-contained; props-only interface avoids ViewModel coupling
   - Dependencies: Steps 1–2
   - Risk: Medium — glassmorphic `.ultraThinMaterial` requires iOS 15+; project targets iOS 26 so fine

4. **Define `ImmersiveVitalRow` helper struct** (top of `StressImmersiveView.swift`)
   - Action: `struct ImmersiveVitalRow { let icon: String; let iconColor: Color; let label: String; let value: String; let sheet: StressSheet }` — plain value type, no model dependency
   - Why: Decouples immersive view from ViewModel internals
   - Dependencies: Step 3
   - Risk: Low

### Phase 3: Gauge Enhancement

5. **Extend `StressScoreGaugeView`** (File: `WellPlate/Features + UI/Stress/Views/StressScoreGaugeView.swift`)
   - Action: Add `var immersive: Bool = false` parameter. When `immersive == true`: increase default size to 260, make the outer glow halo opacity higher (0.22 instead of 0.13), tint the center score text `level.color` instead of `.primary`. No change to arc logic.
   - Why: Reuses existing gauge rather than duplicating it; immersive mode just needs bigger + brighter presentation
   - Dependencies: None (can do in parallel with Phase 1)
   - Risk: Low

### Phase 4: Toggle & StressView Integration

6. **Add mode toggle state to `StressView`** (File: `WellPlate/Features + UI/Stress/Views/StressView.swift`)
   - Action: Add `@AppStorage("stressViewImmersive") private var isImmersive: Bool = false` at top of struct. This persists the user's choice across app launches.
   - Why: `@AppStorage` requires no extra infrastructure and survives app restarts
   - Dependencies: None
   - Risk: Low

7. **Add toggle button overlay** (File: `StressView.swift` — `body` ZStack)
   - Action: In the root `ZStack` of `body`, add a `.overlay(alignment: .topTrailing)` containing a `Button` that toggles `isImmersive`. Button label: `Image(systemName: isImmersive ? "list.bullet" : "sparkles")` inside a `Circle().fill(.ultraThinMaterial)` frame 36×36. Add `.padding(.top, 56).padding(.trailing, 20)` so it lands in the safe-area header zone. On tap: `HapticService.impact(.light)` + `withAnimation(.easeInOut(duration: 0.5)) { isImmersive.toggle() }`.
   - Why: Top-right overlay sits above both scroll views and never shifts with scroll position
   - Dependencies: Step 6
   - Risk: Low

8. **Wire conditional layout in `mainContent`** (File: `StressView.swift` — `mainContent` computed var)
   - Action: Replace current `ScrollView { VStack { ... } }` block with:
     ```swift
     Group {
         if isImmersive {
             StressImmersiveView(
                 score: viewModel.totalScore,
                 level: viewModel.stressLevel,
                 factors: sortedFactors.map(\.factor),
                 vitalRows: immersiveVitalRows,
                 onFactorTap: { activeSheet = $0 }
             )
             .transition(.opacity)
         } else {
             improvedPlainScrollView
                 .transition(.opacity)
         }
     }
     .animation(.easeInOut(duration: 0.5), value: isImmersive)
     ```
   - Why: Single `animation(value:)` drives the cross-fade cleanly; transitions on both branches ensures symmetry
   - Dependencies: Steps 3–7
   - Risk: Low

9. **Add `immersiveVitalRows` computed var** (File: `StressView.swift`)
   - Action: Private computed property that builds `[ImmersiveVitalRow]` from existing ViewModel properties (todayHeartRate, sleepFactor, exerciseFactor). Maps to `.exercise`, `.sleep` sheets where applicable.
   - Why: Keeps ViewModel-to-view mapping in StressView, not in the immersive subview
   - Dependencies: Step 4
   - Risk: Low

### Phase 5: Polish Plain View

10. **Refine `improvedPlainScrollView`** (File: `StressView.swift`)
    - Action: Extract current `mainContent` scroll body into a private `improvedPlainScrollView` var. Improvements:
      - Header: keep existing layout, add subtle `Divider()` below with `level.color.opacity(0.3)`
      - Vitals section: use a 3-column `LazyVGrid` with `GridItem(.flexible())` instead of stacked rows — shows more at a glance
      - Factor cards: reduce `VStack` spacing from 10 to 8; already use `appShadow` but ensure `cornerRadius: 20` matches design tokens
      - Section labels: bump tracking from 1.0 to 1.2 for polish
      - autoLoggingNote: move below the gauge, keep as-is
    - Why: Improves information density without changing data or navigation
    - Dependencies: None
    - Risk: Low

### Phase 6: Build Verification

11. **Build and verify** (Xcode / xcodebuild)
    - Action: Run `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
    - Verify: Zero errors, zero new warnings. Both branches compile. Toggle button visible in both state views (main content, not on permission/loading/unavailable states).
    - Dependencies: All previous steps
    - Risk: Low

## Animation Spec

| Element | Animation | Duration | Notes |
|---|---|---|---|
| Blob orb position | `linear.repeatForever(autoreverses: true)` | 5–7 s (staggered) | Each blob has randomized duration in range |
| Blob orb scale | same as position, linked | — | Scale 0.85→1.1 |
| Gauge halo pulse | `linear(4s).repeatForever(autoreverses: true)` | 4 s | Opacity 0.12→0.22 |
| Mode toggle cross-fade | `.easeInOut(duration: 0.5)` | 0.5 s | Driven by `animation(value: isImmersive)` |
| Factor card appear (immersive) | `.spring(response: 0.6, dampingFraction: 0.8).delay(index * 0.07)` | ~0.6 s | Staggered on appear |
| Score gauge fill (existing) | `.spring(response: 0.9, dampingFraction: 0.72)` | — | Already implemented, unchanged |

## File Summary

| Action | File |
|---|---|
| New | `Views/AmbientBlobView.swift` |
| New | `Views/StressImmersiveView.swift` |
| Modify | `Views/StressView.swift` |
| Modify | `Views/StressScoreGaugeView.swift` |

No changes to: ViewModels, Models, Services, other feature views, sheet enum, navigation.

## Risks & Mitigations

- **Risk**: `.ultraThinMaterial` readability over colored blobs
  Mitigation: Add a `Color.black.opacity(0.35)` scrim layer between blobs and cards; test on both light and dark system appearance
- **Risk**: Blob animations causing jank on older devices
  Mitigation: Use `drawingGroup()` on the blob ZStack to composite to Metal layer; limit to 3 blobs
- **Risk**: `@AppStorage` key collision
  Mitigation: Key is `"stressViewImmersive"` — unique enough; document in implementation

## Success Criteria
- [ ] Toggle button visible top-right on main content screen (not on loading/permission states)
- [ ] Tapping toggle cross-fades between immersive and plain views in ~0.5 s
- [ ] Immersive view shows: dark ambient background, 3 slow-moving blobs, breathing halo on gauge, factor pills in horizontal scroll, vitals as compact tiles
- [ ] Plain view retains all existing data: vitals rows, factor cards, timeline charts
- [ ] All existing sheet navigation works unchanged in both modes
- [ ] Blob/halo animations are visibly slow and non-distracting (5–7 s cycle)
- [ ] User's mode preference persists across app restarts
- [ ] Clean build with zero errors
