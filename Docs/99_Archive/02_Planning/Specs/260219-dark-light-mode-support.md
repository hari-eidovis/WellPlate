# Implementation Plan: Dark & Light Mode Support

## Overview
The app currently has a mix of adaptive and hardcoded colors. `SplashScreenView` and most `ProgressInsightsView`/`GoalsExpandableView` components already use adaptive system colors correctly. The main gaps are: (1) hardcoded `Color.white` backgrounds in `HomeView` and `CustomProgressView`, (2) a `.black.opacity(0.9)` foreground that will be invisible in dark mode, (3) a complete `AppColors` semantic token system defined in code but with **no corresponding `.colorset` assets** in the catalog — meaning those tokens render transparent everywhere they're used, and (4) shadows hardcoded as black (invisible in dark mode).

---

## Requirements
- All screens render correctly in both light and dark mode
- No hardcoded white/black colors remain for backgrounds and foregrounds
- The `AppColors` semantic token system actually works (backed by real asset catalog entries)
- Shadows are visible in both modes
- No user-facing settings needed — follow system preference automatically

---

## Current State Audit

### ✅ Already Adaptive (no changes needed)
| File | Color Usage |
|------|------------|
| `SplashScreenView.swift` | Uses `@Environment(\.colorScheme)` + computed adaptive colors |
| `ProgressInsightsView.swift` | `Color(.systemGroupedBackground)`, `Color(.systemBackground)` |
| `GoalsExpandableView.swift` | `Color(.systemBackground)` |
| `MainTabView.swift` | `.tint(.orange)` — accent only |
| Most foreground text | `.primary`, `.secondary` — adaptive |

### ❌ Hardcoded Colors That Break Dark Mode

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `HomeView.swift` | 96 | `Color(.white)` — ZStack background | `Color(.systemBackground)` |
| `HomeView.swift` | 250 | `Color(.white)` — textEditorView background | `Color(.systemBackground)` |
| `HomeView.swift` | 212 | `.foregroundColor(.black.opacity(0.9))` — gear icon | `.foregroundColor(.primary)` |
| `CustomProgressView.swift` | 9 | `Color.white` — loading screen background | `Color(.systemBackground)` |

### ⚠️ Missing Asset Catalog Color Sets (Silent Bug)
`AppColors.swift` defines 10 named colors (`Primary`, `PrimaryContainer`, `OnPrimary`, `Surface`, `BorderSubtle`, `TextPrimary`, `TextSecondary`, `Success`, `Warning`, `Error`) but **none have a `.colorset` file** in `Assets.xcassets`. These all render as transparent/clear throughout the app.

### ⚠️ Adaptive Shadow Concern
Shadows throughout the app use `.black.opacity(0.05–0.1)`. In dark mode these disappear entirely. Should be replaced with an adaptive approach.

---

## Architecture Changes
- `WellPlate/Resources/Assets.xcassets/` — Add 10 new `.colorset` folders with light + dark variants
- `WellPlate/Shared/Color/AppColor.swift` — Add adaptive shadow extension
- `WellPlate/Features + UI/Home/Views/HomeView.swift` — Fix 3 hardcoded color usages
- `WellPlate/Shared/Components/CustomProgressView.swift` — Fix 1 hardcoded color usage

---

## Implementation Steps

### Phase 1: Create Missing Asset Catalog Color Sets
**Goal**: Make the `AppColors` semantic token system actually work by creating the missing `.colorset` files with proper light/dark variants.

1. **Create `Primary.colorset`** (File: `Assets.xcassets/Primary.colorset/Contents.json`)
   - Light: `#FF6A00` (orange — matches existing accent `Color(red: 1.0, green: 0.45, blue: 0.25)`)
   - Dark: `#FF7A20` (slightly lighter for dark background readability)
   - Risk: Low

2. **Create `PrimaryContainer.colorset`** (File: `Assets.xcassets/PrimaryContainer.colorset/Contents.json`)
   - Light: `#FFF0E6` (soft orange tint)
   - Dark: `#3D2000` (deep warm dark)
   - Risk: Low

3. **Create `OnPrimary.colorset`** (File: `Assets.xcassets/OnPrimary.colorset/Contents.json`)
   - Light: `#FFFFFF`
   - Dark: `#FFFFFF`
   - Risk: Low

4. **Create `Surface.colorset`** (File: `Assets.xcassets/Surface.colorset/Contents.json`)
   - Light: `#FFFFFF`
   - Dark: `#1C1C1E` (iOS dark surface)
   - Risk: Low

5. **Create `BorderSubtle.colorset`** (File: `Assets.xcassets/BorderSubtle.colorset/Contents.json`)
   - Light: `#E5E5EA` (light gray)
   - Dark: `#38383A` (dark gray)
   - Risk: Low

6. **Create `TextPrimary.colorset`** (File: `Assets.xcassets/TextPrimary.colorset/Contents.json`)
   - Light: `#1C1C1E`
   - Dark: `#FFFFFF`
   - Risk: Low

7. **Create `TextSecondary.colorset`** (File: `Assets.xcassets/TextSecondary.colorset/Contents.json`)
   - Light: `#8E8E93`
   - Dark: `#8E8E93` (same — system secondary gray is already calibrated)
   - Risk: Low

8. **Create `Success.colorset`** (File: `Assets.xcassets/Success.colorset/Contents.json`)
   - Light: `#34C759` (iOS green)
   - Dark: `#30D158` (iOS dark green)
   - Risk: Low

9. **Create `Warning.colorset`** (File: `Assets.xcassets/Warning.colorset/Contents.json`)
   - Light: `#FF9500` (iOS orange-yellow)
   - Dark: `#FF9F0A` (iOS dark warning)
   - Risk: Low

10. **Create `Error.colorset`** (File: `Assets.xcassets/Error.colorset/Contents.json`)
    - Light: `#FF3B30` (iOS red)
    - Dark: `#FF453A` (iOS dark red)
    - Risk: Low

> **Format for each `Contents.json`** — follow the same structure as `AccentColor.colorset/Contents.json` with three entries: universal (fallback), light appearance, and dark appearance.

---

### Phase 2: Fix Hardcoded Colors in Views
**Goal**: Replace the 4 hardcoded `Color.white` / `.black.opacity(0.9)` usages that visibly break dark mode.

1. **Fix HomeView ZStack background** (File: `HomeView.swift:96`)
   - Action: Change `Color(.white)` → `Color(.systemBackground)`
   - Why: White background stays white in dark mode, creating a blinding screen
   - Risk: Low

2. **Fix HomeView textEditorView background** (File: `HomeView.swift:250`)
   - Action: Change `Color(.white)` → `Color(.systemBackground)`
   - Why: Same issue — the food log list area will be white-on-dark
   - Risk: Low

3. **Fix HomeView gear icon foreground** (File: `HomeView.swift:212`)
   - Action: Change `.foregroundColor(.black.opacity(0.9))` → `.foregroundColor(.primary)`
   - Why: Black text is invisible on dark backgrounds
   - Risk: Low

4. **Fix CustomProgressView background** (File: `CustomProgressView.swift:9`)
   - Action: Change `Color.white` → `Color(.systemBackground)`
   - Why: Loading screen renders white in dark mode
   - Risk: Low

---

### Phase 3: Add Adaptive Shadow Helper
**Goal**: Prevent shadows from completely disappearing in dark mode.

1. **Add `appShadow` modifier to `AppColor.swift`** (File: `AppColor.swift`)
   - Action: Add an extension on `View` with a `.appShadow(radius:y:)` modifier that uses `Color(.label).opacity(0.08)` instead of `Color.black.opacity(0.05)`
   - Why: `Color(.label)` is white in dark mode, black in light mode — an adaptive shadow
   - Note: In dark mode, subtle white glow/shadow gives depth. `0.08` opacity keeps it subtle.
   - Risk: Low — purely additive

   ```swift
   extension View {
       func appShadow(radius: CGFloat = 10, y: CGFloat = 4) -> some View {
           self.shadow(color: Color(.label).opacity(0.08), radius: radius, x: 0, y: y)
       }
   }
   ```

2. **Apply `appShadow` to GoalsExpandableView** (File: `GoalsExpandableView.swift`)
   - Replace `.shadow(color: .black.opacity(0.1), ...)` with `.appShadow(...)`
   - Risk: Low

3. **Apply `appShadow` to HomeView navigation bar** (File: `HomeView.swift`)
   - Replace `.shadow(color: .black.opacity(0.05), ...)` with `.appShadow(...)`
   - Risk: Low

4. **Apply `appShadow` to ProgressInsightsView cards** (File: `ProgressInsightsView.swift`)
   - Replace `.shadow(color: .black.opacity(0.05), ...)` with `.appShadow(...)`
   - Risk: Low

---

## Testing Strategy

### Preview Testing (Xcode)
- Add `.preferredColorScheme(.dark)` preview to `HomeView`, `CustomProgressView`, `GoalsExpandableView`, and `ProgressInsightsView` (following the pattern already in `SplashScreenView_Previews`)
- Visually verify each screen in both modes

### Manual Device Testing
- Toggle system appearance in Settings → Display & Brightness
- Check: HomeView background, navigation bar, food log list
- Check: GoalsExpandableView collapsed pill and expanded card
- Check: ProgressInsightsView chart cards and metric grid
- Check: CustomProgressView (loading state)
- Check: SplashScreenView (already tested but verify)

### Checklist
- [ ] HomeView background adapts (white light / dark surface dark)
- [ ] Gear icon visible in dark mode
- [ ] Food log list readable in dark mode
- [ ] Loading screen adapts
- [ ] Named colors (`AppColors.primary`, `AppColors.surface`, etc.) no longer transparent
- [ ] Shadows visible (subtle) in both modes

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `.colorset` hex values don't match design intent | Start with standard iOS system color equivalents; easy to adjust in Xcode color picker |
| Adaptive shadows (white glow) look unexpected in dark | Keep opacity very low (0.06–0.08); test on device |
| Missing other hardcoded colors in future views | After this, add a lint rule or PR checklist item: "no `Color.white` or `Color.black` in SwiftUI views" |
| `AppColors` tokens newly working may change appearance | Since they were transparent before, any views using `AppColors.surface` etc. will now show color — review each |

---

## Success Criteria
- [ ] App runs without white/black artifacts in dark mode on any screen
- [ ] All 10 named color assets exist in the catalog with light + dark variants
- [ ] Zero instances of `Color.white` or `Color.black` used for backgrounds/foregrounds (use semantic or system colors)
- [ ] Shadows visible in both light and dark mode
- [ ] All Xcode previews include a dark mode variant

---

## File Summary

| File | Changes |
|------|---------|
| `Assets.xcassets/` | +10 new `.colorset` folders |
| `AppColor.swift` | +`appShadow` view modifier |
| `HomeView.swift` | 3 color fixes (2× background, 1× foreground) |
| `CustomProgressView.swift` | 1 background fix |
| `GoalsExpandableView.swift` | Shadow fix |
| `ProgressInsightsView.swift` | Shadow fixes |

**Total scope: Small — ~20 targeted edits across 6 files + 10 new asset files.**
