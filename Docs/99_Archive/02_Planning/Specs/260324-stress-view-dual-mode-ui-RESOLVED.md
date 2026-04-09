# Implementation Plan: StressView Dual-Mode UI (RESOLVED)

> Resolved from audit `Docs/05_Audits/Code/260324-stress-view-dual-mode-ui-audit.md`
> All CRITICAL and HIGH issues addressed. Selected MEDIUM fixes included.

## Overview
Add a top-right toggle to `StressView` that switches between two presentation modes: an **Immersive animated view** (ambient glowing background, floating blobs, glassmorphic cards) and the existing **Info-rich plain view** (improved scrollable layout with cleaner hierarchy). All animations are slow and subtle (3–6 s ambient, spring for taps). No new SwiftData models, no new sheets, no ViewModel changes.

## Audit Resolutions Summary

| Issue | Severity | Resolution |
|---|---|---|
| `Double.random()` in view body resets animation on re-render | CRITICAL | Store duration in `@State private var animDuration` — initialised once on struct creation |
| `.transition` on views inside `Group` is unreliable | CRITICAL | Replace `Group { if/else }` with `ZStack { if/else + .zIndex() }` |
| Screen Time factor has no defined sheet in immersive mode | HIGH | Immersive pill opens `.screenTimeDetail` only; entry remains accessible from detail view |
| `StressImmersiveView` can't map `StressFactorResult → StressSheet` | HIGH | Pass `[(factor: StressFactorResult, sheet: StressSheet?)]` tuples instead of bare factors |
| Toggle button `.padding(.top, 56)` hardcoded | HIGH | Use `safeAreaInset` via `GeometryReader` reading `\.safeAreaInsets.top` |
| `animPhase: Bool` parameter undefined/unused | MEDIUM | Removed; blob is fully self-contained — phase driven by internal `@State` |
| `drawingGroup()` only in Risks section, not in steps | MEDIUM | Added explicitly to Step 2 |
| Dark-only background jarring in light mode | MEDIUM | Apply `.preferredColorScheme(.dark)` to `StressImmersiveView` |
| Gauge `immersive` flag size behaviour ambiguous | MEDIUM | Clarified: `StressImmersiveView` always passes `size: 260` explicitly |
| 3-column vitals grid too narrow on 390 pt phones | MEDIUM | Changed to 2-column `LazyVGrid` |
| No `accessibilityReduceMotion` guard | MEDIUM | Guard added to `AmbientBlobView` and gauge halo pulse |

---

## Requirements
- Toggle button top-right persists mode in `@AppStorage("stressViewImmersive")`
- Immersive mode: dark ambient background (`.preferredColorScheme(.dark)` forced), 3 slowly-drifting blob orbs, pulsing glow halo on gauge, glassmorphic factor pills, score as full-screen hero
- Plain mode: current scrollable content polished — tighter section headers, 2-column vitals grid, all existing data preserved
- Transition between modes: `ZStack`-based opacity cross-fade, `.easeInOut(duration: 0.5)`
- All repeat animations guarded by `@Environment(\.accessibilityReduceMotion)`
- All existing sheet navigation (`.sheet(item: $activeSheet)`) untouched
- Builds cleanly — no new external dependencies

---

## Architecture Changes
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add `@AppStorage` toggle state, `ZStack`-based conditional layout, overlay toggle button using safe-area-aware padding
- `WellPlate/Features + UI/Stress/Views/StressImmersiveView.swift` (**new**) — receives `[(factor: StressFactorResult, sheet: StressSheet?)]` tuples + `[ImmersiveVitalRow]`; fully self-contained with forced dark scheme
- `WellPlate/Features + UI/Stress/Views/AmbientBlobView.swift` (**new**) — self-contained blob with `@State`-stored duration; no `animPhase` param
- `WellPlate/Features + UI/Stress/Views/StressScoreGaugeView.swift` — add `immersive: Bool = false`; callers that want immersive size pass `size: 260` explicitly

---

## Implementation Steps

### Phase 1: Ambient Background Infrastructure

1. **Create `AmbientBlobView`** (File: `WellPlate/Features + UI/Stress/Views/AmbientBlobView.swift`)
   - Action: A `View` accepting `color: Color`, `size: CGFloat`, `targetOffset: CGSize`. Internally holds:
     ```swift
     @State private var animDuration: Double = Double.random(in: 5...7)  // set once at init
     @State private var isAnimating = false
     @Environment(\.accessibilityReduceMotion) private var reduceMotion
     ```
     Body: a radial-gradient `Circle` (center `color.opacity(0.9)` → `color.opacity(0)`) of the given size, opacity 0.20, offset by `isAnimating ? targetOffset : .zero`, scaleEffect `isAnimating ? 1.1 : 0.85`.
     `.onAppear`: guard `!reduceMotion`, then `withAnimation(.linear(duration: animDuration).repeatForever(autoreverses: true)) { isAnimating = true }`.
   - Why: `animDuration` stored in `@State` is initialised **once** when the struct is first created and survives re-renders — fixes critical bug #1. No external phase parameter needed.
   - Dependencies: None
   - Risk: Low

2. **Create `StressImmersiveBackground`** (private struct inside `StressImmersiveView.swift`)
   - Action: A `View` accepting `level: StressLevel`. Body:
     ```swift
     ZStack {
         Color.black
         AmbientBlobView(color: level.color,  size: 280, targetOffset: CGSize(width: 80,  height: -60))
         AmbientBlobView(color: .purple,       size: 220, targetOffset: CGSize(width: -70, height: 90))
         AmbientBlobView(color: .indigo,       size: 180, targetOffset: CGSize(width: 50,  height: 120))
         LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
     }
     .drawingGroup()   // composites all blobs to a single Metal layer — prevents jank
     .ignoresSafeArea()
     ```
   - Why: `drawingGroup()` moved from Risks section into an explicit step. Each `AmbientBlobView` animates with its own internally-randomised duration for natural stagger.
   - Dependencies: Step 1
   - Risk: Low

### Phase 2: Immersive Layout View

3. **Define `ImmersiveFactorItem` and `ImmersiveVitalRow`** (top of `StressImmersiveView.swift`)
   - Action:
     ```swift
     struct ImmersiveFactorItem {
         let factor: StressFactorResult
         let sheet: StressSheet?          // nil for Screen Time (entry via detail)
     }

     struct ImmersiveVitalRow {
         let icon: String
         let iconColor: Color
         let label: String
         let value: String
         let sheet: StressSheet
     }
     ```
   - Why: `ImmersiveFactorItem` carries the `sheet` alongside the factor, solving the critical mapping gap. `StressImmersiveView` never needs to know the `StressSheet` enum's cases.
   - Dependencies: None
   - Risk: Low

4. **Create `StressImmersiveView`** (File: `WellPlate/Features + UI/Stress/Views/StressImmersiveView.swift`)
   - Action: Standalone `View` with interface:
     ```swift
     struct StressImmersiveView: View {
         let score: Double
         let level: StressLevel
         let factorItems: [ImmersiveFactorItem]
         let vitalRows: [ImmersiveVitalRow]
         let onFactorTap: (StressSheet) -> Void
         let onVitalTap: (StressSheet) -> Void

         @State private var haloPulse = false
         @Environment(\.accessibilityReduceMotion) private var reduceMotion
     }
     ```
     Layout (ZStack):
     - **Layer 0 – Background**: `StressImmersiveBackground(level: level)`
     - **Layer 1 – Content**: `VStack(spacing: 0)` (safe-area aware, not ignoring edges):
       - Spacer (adaptive via GeometryReader, ~10% of height)
       - **Hero gauge**: `StressScoreGaugeView(score: score, level: level, immersive: true, size: 260)` overlaid with breathing halo: `Circle().fill(level.color.opacity(haloPulse ? 0.22 : 0.10)).frame(width: 310).blur(radius: 44)`. Halo animation: `.onAppear { if !reduceMotion { withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) { haloPulse = true } } }`
       - Comparison badge (same capsule as plain view, white text for dark background)
       - `Spacer(minLength: 24)`
       - **Factor pills**: `ScrollView(.horizontal, showsIndicators: false)` containing `HStack(spacing: 10)` of `ImmersiveFactorPill` for each item. Screen Time pill (sheet == nil) still renders and taps to `.screenTimeDetail`.
       - `Spacer(minLength: 16)`
       - **Vitals tiles**: `HStack(spacing: 10)` of 3 `ImmersiveVitalTile` subviews, each `.frame(maxWidth: .infinity)`.
       - `Spacer(minLength: 32)`

     **`ImmersiveFactorPill`** (private `@ViewBuilder` func or nested struct):
     - `HStack(spacing: 8) { icon badge | VStack(title, score/25) }` in a `RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)` with a 3 pt leading colored border via `.overlay(alignment: .leading) { Capsule().fill(factor.accentColor).frame(width: 3) }`.
     - Tappable if `item.sheet != nil`, calls `onFactorTap(item.sheet!)`. Screen Time item (`sheet == nil`) maps to `.screenTimeDetail` explicitly: `onFactorTap(.screenTimeDetail)`.
     - Appear animation: `.offset(y: appeared ? 0 : 20).opacity(appeared ? 1 : 0)` with `.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.07)`.

     **`ImmersiveVitalTile`** (private `@ViewBuilder` func or nested struct):
     - `VStack(spacing: 4) { icon | value | label }` in `RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)`.
     - Tappable → `onVitalTap(row.sheet)`.

   - Apply `.preferredColorScheme(.dark)` to the root ZStack — ensures `.ultraThinMaterial` and `.secondary` text colour adapt correctly regardless of system appearance.
   - Why: Dark scheme explicitly set — fixes medium issue #8 (light-mode jarring). Screen Time pill always calls `.screenTimeDetail` — fixes high issue #3.
   - Dependencies: Steps 1–3
   - Risk: Low (all dependencies resolved)

### Phase 3: Gauge Enhancement

5. **Extend `StressScoreGaugeView`** (File: `WellPlate/Features + UI/Stress/Views/StressScoreGaugeView.swift`)
   - Action: Add `var immersive: Bool = false`. When `immersive == true`:
     - Outer glow halo opacity: 0.22 (was 0.13)
     - Center score text colour: `level.color` (was `.primary`)
     - No change to `size` default or arc logic — size is always passed explicitly by callers
   - Note: `StressImmersiveView` always calls `StressScoreGaugeView(score:, level:, immersive: true, size: 260)`. The existing plain-view call `StressScoreGaugeView(score:, level:)` remains unchanged and unaffected.
   - Why: Immersive gauge is bigger + brighter without changing existing call sites.
   - Dependencies: None
   - Risk: Low

### Phase 4: Toggle & StressView Integration

6. **Add mode toggle state** (File: `StressView.swift`)
   - Action: Add at top of struct:
     ```swift
     @AppStorage("stressViewImmersive") private var isImmersive: Bool = false
     ```
   - Dependencies: None
   - Risk: Low

7. **Add safe-area-aware toggle button overlay** (File: `StressView.swift` — `body` ZStack)
   - Action: Add `.overlay(alignment: .topTrailing)` on the root `ZStack`. Content:
     ```swift
     GeometryReader { geo in
         Button {
             HapticService.impact(.light)
             withAnimation(.easeInOut(duration: 0.5)) { isImmersive.toggle() }
         } label: {
             Image(systemName: isImmersive ? "list.bullet" : "sparkles")
                 .font(.system(size: 15, weight: .semibold))
                 .foregroundStyle(isImmersive ? Color.white : Color.primary)
                 .frame(width: 36, height: 36)
                 .background(Circle().fill(.ultraThinMaterial))
         }
         .padding(.top, geo.safeAreaInsets.top + 10)
         .padding(.trailing, 20)
         .frame(maxWidth: .infinity, alignment: .trailing)
     }
     .ignoresSafeArea()
     ```
   - Why: `geo.safeAreaInsets.top` reads the actual safe area for the current device (Dynamic Island, notch, iPad), removing the hardcoded 56 pt — fixes high issue #5.
   - Dependencies: Step 6
   - Risk: Low

8. **Wire `ZStack`-based conditional layout in `mainContent`** (File: `StressView.swift`)
   - Action: Replace current `ScrollView { VStack { ... } }` with:
     ```swift
     ZStack {
         if isImmersive {
             StressImmersiveView(
                 score: viewModel.totalScore,
                 level: viewModel.stressLevel,
                 factorItems: immersiveFactorItems,
                 vitalRows: immersiveVitalRows,
                 onFactorTap: { activeSheet = $0 },
                 onVitalTap:  { activeSheet = $0 }
             )
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
   - Why: `ZStack` + explicit `.zIndex()` gives SwiftUI stable view identity on both branches, ensuring the `.opacity` transition fires correctly on both enter and exit — fixes critical bug #2. `Group` removed entirely.
   - Dependencies: Steps 3–7
   - Risk: Low

9. **Add `immersiveFactorItems` and `immersiveVitalRows` computed vars** (File: `StressView.swift`)
   - Action:
     ```swift
     private var immersiveFactorItems: [ImmersiveFactorItem] {
         sortedFactors.map { item in
             ImmersiveFactorItem(factor: item.factor, sheet: item.sheet)
         }
     }

     private var immersiveVitalRows: [ImmersiveVitalRow] {
         [
             ImmersiveVitalRow(
                 icon: "heart.fill", iconColor: .pink, label: "HEART RATE",
                 value: viewModel.todayHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                 sheet: .vital(.heartRate)
             ),
             ImmersiveVitalRow(
                 icon: "moon.zzz.fill",
                 iconColor: Color(hue: 0.68, saturation: 0.55, brightness: 0.75),
                 label: "SLEEP",
                 value: sleepDisplayValue,
                 sheet: .sleep
             ),
             ImmersiveVitalRow(
                 icon: "figure.walk",
                 iconColor: Color(hue: 0.55, saturation: 0.55, brightness: 0.60),
                 label: "ACTIVITY",
                 value: viewModel.exerciseFactor.statusText,
                 sheet: .exercise
             ),
         ]
     }
     ```
   - Why: Reuses `sortedFactors` (which already has `sheet`) for `immersiveFactorItems` — single source of truth for the mapping. Vital rows are the same 3 as the existing quick-vital section.
   - Dependencies: Steps 3, 4
   - Risk: Low

### Phase 5: Polish Plain View

10. **Refine `improvedPlainScrollView`** (File: `StressView.swift`)
    - Action: Extract current `mainContent` scroll body into a private `improvedPlainScrollView` var. Improvements:
      - Header: keep existing layout; add a 1 pt `Divider()` tinted `level.color.opacity(0.25)` below
      - Vitals section: change from stacked rows to a **2-column** `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10)` — 2 columns fit comfortably at 390 pt width with full label/subtitle visible
      - Factor cards: spacing reduced 10 → 8; confirm `cornerRadius: 20` and `.appShadow(radius: 15, y: 5)` on all cards
      - Section labels: tracking bumped 1.0 → 1.2
      - `autoLoggingNote` and `comparisonBadge` positions unchanged
    - Why: 2-column grid (not 3) prevents truncation on standard iPhone screens — fixes medium issue #10.
    - Dependencies: None
    - Risk: Low

### Phase 6: Build Verification

11. **Build and verify**
    - Action: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
    - Verify:
      - Zero errors, zero warnings
      - Toggle button renders at correct position (safe-area-aware)
      - Cross-fade fires in both directions (plain→immersive and immersive→plain)
      - Blob animations loop smoothly (no restart flicker)
      - All 4 factor pills tappable in immersive mode; Screen Time opens detail sheet
      - Plain view vitals display in 2-column grid without truncation
      - `#if DEBUG` screen time section visible only in plain view (immersive omits it by design)
    - Dependencies: All previous steps
    - Risk: Low

---

## Animation Spec

| Element | Animation | Duration | Notes |
|---|---|---|---|
| Blob orb position + scale | `linear(animDuration).repeatForever(autoreverses: true)` | 5–7 s each (independent `@State`) | Guarded by `reduceMotion` |
| Gauge halo pulse | `linear(4s).repeatForever(autoreverses: true)` | 4 s | Guarded by `reduceMotion` |
| Mode toggle cross-fade | `.easeInOut(duration: 0.5)` | 0.5 s | `ZStack` + `zIndex` for reliable opacity transition |
| Factor pill stagger (immersive appear) | `.spring(response: 0.6, dampingFraction: 0.8).delay(i * 0.07)` | ~0.6 s | `offset+opacity` from 20 pt below |
| Score gauge fill (existing, unchanged) | `.spring(response: 0.9, dampingFraction: 0.72)` | — | No change |

---

## File Summary

| Action | File |
|---|---|
| New | `Views/AmbientBlobView.swift` |
| New | `Views/StressImmersiveView.swift` |
| Modify | `Views/StressView.swift` |
| Modify | `Views/StressScoreGaugeView.swift` |

No changes to: ViewModels, Models, Services, other feature views, `StressSheet` enum, navigation.

---

## Risks & Mitigations

- **`.ultraThinMaterial` over blobs**: `.preferredColorScheme(.dark)` + `Color.black.opacity(0.35)` scrim ensure sufficient contrast in all system appearances
- **Blob animation jank**: `drawingGroup()` on blob ZStack composites to Metal layer; 3 blobs is the maximum
- **Reduce motion**: all `repeatForever` animations guarded by `@Environment(\.accessibilityReduceMotion)`
- **`@AppStorage` key collision**: key `"stressViewImmersive"` is unique in the app's UserDefaults namespace

---

## Success Criteria
- [ ] Toggle button visible top-right, safe-area-aligned on all device sizes including Dynamic Island
- [ ] Tapping toggle cross-fades smoothly (opacity) in both directions in ~0.5 s — no hard cut
- [ ] Blob animations loop continuously without stuttering or restarting on re-renders
- [ ] Immersive view: dark background, 3 slow blobs, breathing halo, factor pills scroll, vitals tiles
- [ ] Screen Time pill in immersive mode opens `.screenTimeDetail` sheet
- [ ] Plain view: 2-column vitals grid, factor cards with `cornerRadius: 20`, all data preserved
- [ ] Timeline charts (day/week) visible in plain view; intentionally absent from immersive view
- [ ] All animations suppressed when Reduce Motion is enabled
- [ ] Clean build with zero errors
