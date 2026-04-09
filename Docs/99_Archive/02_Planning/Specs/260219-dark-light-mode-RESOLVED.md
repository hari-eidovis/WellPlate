# Dark & Light Mode Support — Resolved Implementation Checklist

**Status**: Ready to implement
**Audit**: `Docs/05_Audits/Code/dark-light-mode-audit.md`
**Changes from original plan**: LoadingScreenView added; ProgressInsightsView confirmed correct (already dark-mode aware); Burn module shadow fixes added; Phase ordering revised; appShadow y-offset flaw corrected; AppColors phase demoted to housekeeping.

---

## Final State of Each File

| File | Dark Mode State | Action |
|------|----------------|--------|
| `SplashScreenView.swift` | ✅ Already adaptive (uses `@Environment(\.colorScheme)`) | None |
| `ProgressInsightsView.swift` | ✅ Already adaptive (`cardBackground`, `bgGradient`, `cardShadowColor`, `glassCard`) | None |
| `BurnView.swift` backgrounds | ✅ Already adaptive (`Color(.systemGroupedBackground)`) | Shadow only |
| `BurnDetailView.swift` backgrounds | ✅ Already adaptive (`Color(.systemGroupedBackground)`) | Shadow only |
| `SleepPlaceholderView.swift` | ✅ Already adaptive | None |
| `ProfilePlaceholderView.swift` | ✅ Already adaptive | None |
| `MainTabView.swift` | ✅ Already adaptive | None |
| `GoalsExpandableView.swift` | ✅ Background adaptive | Shadow only |
| `HomeView.swift` | ❌ 3 hardcoded colors + 2 shadows | Phase 1 + Phase 2 |
| `CustomProgressView.swift` | ❌ Hardcoded white background | Phase 1 |
| `LoadingScreenView.swift` | ❌ Hardcoded gradient + dark text | Phase 1 |
| `BurnView.swift` shadow | ❌ `cardBackground` uses `.black.opacity` | Phase 2 |
| `BurnDetailView.swift` shadow | ❌ `cardBackground` uses `.black.opacity` | Phase 2 |
| `BurnMetricCardView.swift` shadow | ❌ Inline `.black.opacity` | Phase 2 |
| `AppColors.swift` / Asset Catalog | ⚠️ 10 named colors have no .colorset (unused, zero visual impact) | Phase 3 (housekeeping) |

---

## Phase 1 — Fix Hardcoded Colors
**Goal**: Replace hardcoded `Color.white`, `Color(.white)`, and hardcoded dark text with adaptive system colors.
**Files**: 3 files, 6 individual changes.

---

### File: `WellPlate/Features + UI/Home/Views/HomeView.swift`

- [ ] **1.1 — ZStack background** `(line ~96)`
  ```swift
  // BEFORE
  Color(.white)
      .ignoresSafeArea()
  // AFTER
  Color(.systemBackground)
      .ignoresSafeArea()
  ```

- [ ] **1.2 — textEditorView background** `(line ~250)`
  ```swift
  // BEFORE
  Color(.white)
  // AFTER
  Color(.systemBackground)
  ```

- [ ] **1.3 — Gear icon foreground** `(line ~212)`
  ```swift
  // BEFORE
  .foregroundColor(.black.opacity(0.9))
  // AFTER
  .foregroundColor(.primary)
  ```

---

### File: `WellPlate/Shared/Components/CustomProgressView.swift`

- [ ] **1.4 — Background fill** `(line ~9)`
  ```swift
  // BEFORE
  Color.white
      .ignoresSafeArea()
  // AFTER
  Color(.systemBackground)
      .ignoresSafeArea()
  ```

---

### File: `WellPlate/Shared/Components/LoadingScreenView.swift`

- [ ] **1.5 — Hardcoded gradient background** `(lines ~10–18)`
  ```swift
  // BEFORE
  LinearGradient(
      gradient: Gradient(colors: [
          Color.white,
          Color(red: 1.0, green: 0.95, blue: 0.9)
      ]),
      startPoint: .top,
      endPoint: .bottom
  )
  .ignoresSafeArea()
  // AFTER
  Color(.systemBackground)
      .ignoresSafeArea()
  ```

- [ ] **1.6 — Hardcoded dark text color** `(line ~25)`
  ```swift
  // BEFORE
  .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
  // AFTER
  .foregroundColor(.primary)
  ```

---

## Phase 2 — Fix Adaptive Shadows
**Goal**: Replace `.shadow(color: .black.opacity(...))` with an adaptive equivalent so shadows remain visible in dark mode.

**First, add the helper to `AppColor.swift`:**

- [ ] **2.0 — Add `appShadow` view modifier** `(WellPlate/Shared/Color/AppColor.swift)`

  > ⚠️ **Important**: The modifier takes an explicit `y` parameter with **no default**. Callers must pass the correct value including sign (negative = shadow projects upward, used for bottom-anchored sheets).

  ```swift
  extension View {
      /// Adaptive shadow — uses Color(.label) so it reads as dark in light mode
      /// and as a subtle white glow in dark mode.
      /// Always pass `y` explicitly; negative values project the shadow upward.
      func appShadow(radius: CGFloat, x: CGFloat = 0, y: CGFloat) -> some View {
          self.shadow(color: Color(.label).opacity(0.08), radius: radius, x: x, y: y)
      }
  }
  ```

---

### File: `WellPlate/Features + UI/Home/Components/GoalExpandableView.swift`

- [ ] **2.1 — Collapsed pill shadow** (upward shadow — keep `y: -5`)
  ```swift
  // BEFORE
  .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: -5)
  // AFTER
  .appShadow(radius: 20, y: -5)
  ```

- [ ] **2.2 — Expanded card shadow** (upward shadow — keep `y: -5`)
  ```swift
  // BEFORE
  .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: -5)
  // AFTER
  .appShadow(radius: 15, y: -5)
  ```

---

### File: `WellPlate/Features + UI/Home/Views/HomeView.swift`

- [ ] **2.3 — Top navigation bar shadow**
  ```swift
  // BEFORE
  .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
  // AFTER
  .appShadow(radius: 8, y: 2)
  ```
  *(Applied to the date pill and the right-side button group backgrounds)*

---

### File: `WellPlate/Features + UI/Burn/Views/BurnView.swift`

- [ ] **2.4 — `cardBackground` computed property**
  ```swift
  // BEFORE
  private var cardBackground: some View {
      RoundedRectangle(cornerRadius: 20)
          .fill(Color(.systemBackground))
          .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
  }
  // AFTER
  private var cardBackground: some View {
      RoundedRectangle(cornerRadius: 20)
          .fill(Color(.systemBackground))
          .appShadow(radius: 15, y: 5)
  }
  ```
  *(One change fixes all 3 cards: todayHeroCard, weeklyChartCard, metricsGrid)*

---

### File: `WellPlate/Features + UI/Burn/Views/BurnDetailView.swift`

- [ ] **2.5 — `cardBackground` computed property**
  ```swift
  // BEFORE
  private var cardBackground: some View {
      RoundedRectangle(cornerRadius: 20)
          .fill(Color(.systemBackground))
          .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
  }
  // AFTER
  private var cardBackground: some View {
      RoundedRectangle(cornerRadius: 20)
          .fill(Color(.systemBackground))
          .appShadow(radius: 15, y: 5)
  }
  ```
  *(One change fixes all 3 cards: kpiCard, chartCard, statsCard)*

---

### File: `WellPlate/Features + UI/Burn/Components/BurnMetricCardView.swift`

- [ ] **2.6 — Inline shadow on metric card**
  ```swift
  // BEFORE
  .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
  // AFTER
  .appShadow(radius: 10, y: 3)
  ```

---

## Phase 3 — AppColors Asset Catalog (Housekeeping)
**Goal**: Back the `AppColors` semantic token system with real `.colorset` files.
**Visual impact now**: Zero (no view references `AppColors.*` yet).
**Value**: Enables future views to use tokens instead of hardcoded hex values.

Each colorset is a folder at `WellPlate/Resources/Assets.xcassets/<Name>.colorset/Contents.json`.
Follow the exact JSON structure of `AccentColor.colorset/Contents.json` (3 entries: universal fallback, light, dark).

| # | Name | Light | Dark |
|---|------|-------|------|
| 3.1 | `Primary` | `#FF6A00` | `#FF7A20` |
| 3.2 | `PrimaryContainer` | `#FFF0E6` | `#3D2000` |
| 3.3 | `OnPrimary` | `#FFFFFF` | `#FFFFFF` |
| 3.4 | `Surface` | `#FFFFFF` | `#1C1C1E` |
| 3.5 | `BorderSubtle` | `#E5E5EA` | `#38383A` |
| 3.6 | `TextPrimary` | `#1C1C1E` | `#FFFFFF` |
| 3.7 | `TextSecondary` | `#8E8E93` | `#636366` |
| 3.8 | `Success` | `#34C759` | `#30D158` |
| 3.9 | `Warning` | `#FF9500` | `#FF9F0A` |
| 3.10 | `Error` | `#FF3B30` | `#FF453A` |

- [ ] **3.1** Create `Primary.colorset`
- [ ] **3.2** Create `PrimaryContainer.colorset`
- [ ] **3.3** Create `OnPrimary.colorset`
- [ ] **3.4** Create `Surface.colorset`
- [ ] **3.5** Create `BorderSubtle.colorset`
- [ ] **3.6** Create `TextPrimary.colorset`
- [ ] **3.7** Create `TextSecondary.colorset`
- [ ] **3.8** Create `Success.colorset`
- [ ] **3.9** Create `Warning.colorset`
- [ ] **3.10** Create `Error.colorset`

---

## Phase 4 — Add Dark Mode Previews
**Goal**: Each fixed view gets a dark mode Xcode preview so regressions are caught instantly.

- [ ] **4.1 — `HomeView`** — add `#Preview("Dark") { HomeView(...).preferredColorScheme(.dark) }`
- [ ] **4.2 — `CustomProgressView`** — add dark preview
- [ ] **4.3 — `LoadingScreenView`** — add dark preview
- [ ] **4.4 — `GoalsExpandableView`** — add dark preview (both collapsed + expanded)
- [ ] **4.5 — `BurnView`** — add dark preview
- [ ] **4.6 — `BurnDetailView`** — add dark preview

---

## Verification Checklist

Run through these after all changes are made:

### HomeView (Intake tab)
- [ ] Background is dark in dark mode (not white)
- [ ] Food log list rows are readable
- [ ] Gear icon visible in dark mode (not black-on-black)
- [ ] Top navigation bar (date pill, stats button) has visible depth/shadow in both modes
- [ ] Goals expandable pill shadows project upward correctly

### Burn tab
- [ ] All 3 card types (hero, chart, metrics grid) have visible depth in dark mode
- [ ] Detail sheet cards have visible depth in dark mode

### Loading / Splash
- [ ] `CustomProgressView` background is dark in dark mode
- [ ] `LoadingScreenView` background adapts and "Well" text is readable
- [ ] `SplashScreenView` already handles dark mode — verify no regression

### Progress & Insights
- [ ] Hero orange gradient looks correct in dark mode (intentional, stays orange)
- [ ] Cards below the hero use the dark card background (`#1C1C2E`)
- [ ] Shadows are still visible in dark mode

---

## Scope Summary

| Phase | Files | Changes |
|-------|-------|---------|
| 1 — Hardcoded colors | 3 files | 6 edits |
| 2 — Adaptive shadows | 5 files + `AppColor.swift` | 7 edits (1 new modifier) |
| 3 — AppColors assets | `Assets.xcassets/` | 10 new folders |
| 4 — Dark previews | 6 files | 6 preview blocks |
| **Total** | **9 source files** | **~30 targeted changes** |

**No architectural changes. No new screens. No model changes.**
