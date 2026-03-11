# Implementation Plan: Accent Color Change — Orange to Brand Green
# Revision 2

**Date**: 2026-03-11
**Status**: Ready to Implement
**Approach**: Asset Catalog + `AppColors.brand` Swift constant (asset-catalog-backed, dark-mode adaptive)

---

## Changelog — What Changed from Revision 1

| Issue | Change Made |
|---|---|
| CRITICAL: sRGB math error | Corrected R/B channels. See "Color Reference Values" section for full derivation. New correct light-mode values: R:0.324, G:0.720, B:0.482. |
| CRITICAL: `AppColors.brand` not dark-mode adaptive | Changed from hardcoded `Color(hue:...)` constant to `Color("AppPrimary")`. `AppPrimary.colorset` already has light and dark variants — `brand` now reads from it automatically. No `UIColor(dynamicProvider:)` wrapper needed. |
| HIGH: Summary table inconsistency for StreakDetailView line 190 | Summary table now correctly shows line 190 in a separate "Special changes" column. It becomes `.yellow`, not orange, not brand. |
| HIGH: Exercise ring hue collision | HomeView.swift line 277 Exercise ring uses `Color(hue: 0.40, ...)` — same hue as new brand green. Plan now addresses this: shift Exercise ring to teal (hue ~0.50). See new Step 3.3b. |
| HIGH: Dark-mode opacity cascade | Fixed automatically by the `AppColors.brand = Color("AppPrimary")` change above. All `AppColors.brand.opacity(x)` calls will now use the correct dark-mode base color. |
| MEDIUM: DragToLogOverlay not in test checklist | Added to visual regression checklist (changes via asset, no Swift edit needed). |
| MEDIUM: ExpandableFAB sub-action note | Added note that lines 18–21 sub-action colors are already non-orange. |
| MEDIUM: GoalsView flame icon rationale | Added explicit justification. |
| LOW: AppPrimary dark-mode description | Corrected to `#FF7A20`. |
| LOW: PrimaryContainer current state hex | Corrected to `#FFF0E6` (warm peach/cream). |
| LOW: Rollback strategy | Added to plan. |

---

## Overview

Replace the app's orange brand color (`#FF6A00`) with a muted earthy green. The correct sRGB representation of `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` is **R:0.324, G:0.720, B:0.482** (see derivation below). Three asset catalog colorsets require JSON edits; `AppColors.brand` becomes `Color("AppPrimary")` (asset-backed, adaptive); and ~19 Swift files have brand `.orange` references that must be redirected to `AppColors.brand`. Semantic orange uses (carbs macro, fat macro, fair quality, breakfast time slot, warning scales, BP accent, fire/burn gradients) are preserved untouched. The Exercise ring in `HomeView.swift` must also shift from hue 0.40 (identical to brand) to hue 0.50 (teal) to maintain visual ring distinctness.

---

## Color Reference Values

### sRGB Derivation — Light Mode Brand Green

**Input**: `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`
**HSV parameters**: H = 0.40 (= 144°), S = 0.55, V = 0.72

Standard HSV-to-RGB algorithm:
1. H × 6 = 0.40 × 6 = **2.40** → sector i = **2** (green-to-cyan sector)
2. Fractional part f = 2.40 − 2 = **0.40**
3. p = V × (1 − S) = 0.72 × 0.45 = **0.324**
4. q = V × (1 − S × f) = 0.72 × (1 − 0.55 × 0.40) = 0.72 × 0.78 = **0.5616** (not used in final triple for sector 2)
5. t = V × (1 − S × (1 − f)) = 0.72 × (1 − 0.55 × 0.60) = 0.72 × 0.67 = **0.4824**

For sector i = 2: **(R, G, B) = (p, V, t) = (0.324, 0.720, 0.482)**

**Revision 1 error**: R and B were reported as 0.414 and 0.324 respectively — these are values from two inconsistent intermediate computations that were mixed together. The correct values are R:0.324, B:0.482 as derived above.

**Dark mode brand green** (raised brightness, full opacity for legibility on dark backgrounds):
H = 0.40, S = 0.50, V = 0.82 → **R:0.410, G:0.820, B:0.574**

Derivation:
- sector i = 2, f = 0.40
- p = 0.82 × 0.50 = **0.410**
- t = 0.82 × (1 − 0.50 × 0.60) = 0.82 × 0.70 = **0.574**
- (R, G, B) = (p, V, t) = **(0.410, 0.820, 0.574)**

| Use | Light Mode (sRGB) | Dark Mode (sRGB) |
|---|---|---|
| AccentColor / AppPrimary / brand | R:0.324, G:0.720, B:0.482, A:1.0 | R:0.410, G:0.820, B:0.574, A:1.0 |
| PrimaryContainer | R:0.910, G:0.969, B:0.878, A:1.0 | R:0.102, G:0.231, B:0.082, A:1.0 |

**Swift constant** (Revision 2): `static let brand = Color("AppPrimary")`

This is the simplest dark-mode-adaptive solution. `AppPrimary.colorset` already carries separate light and dark entries (updated in Phase 1). Every call site that uses `AppColors.brand.opacity(x)` automatically operates on the correct dark-mode base color without any `UIColor(dynamicProvider:)` wrapper.

---

## Phase 1: Asset Catalog Updates (3 JSON files)

### Step 1.1 — `AccentColor.colorset`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`

**Current state**: All three entries (universal, light, dark) use `red: 0xFF, green: 0x6A, blue: 0x00`. The dark entry uses `alpha: 0.500` — a half-opacity hack that made the dark-mode accent look washed out.

**Change**: Replace all three color component blocks with the corrected green sRGB values using decimal notation. Remove the half-opacity dark-mode hack — use full opacity with an adjusted brightness value.

**New JSON**:
```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.482",
          "green" : "0.720",
          "red" : "0.324"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "light"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.482",
          "green" : "0.720",
          "red" : "0.324"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.574",
          "green" : "0.820",
          "red" : "0.410"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "localizable" : true
  }
}
```

**Impact**: System-level SwiftUI components (Toggle, Link, Slider, ProgressView, focused TextFields) will immediately adopt the new green because they reference `AccentColor`.

---

### Step 1.2 — `AppPrimary.colorset`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Resources/Assets.xcassets/AppPrimary.colorset/Contents.json`

**Current state**: Universal entry uses decimal (`red: 1.000, green: 0.416, blue: 0.000`); light and dark entries use hex notation. Dark entry is a warmer/shifted orange (`0xFF, 0x7A, 0x20` = `#FF7A20`). Mixed notation — normalize to decimal throughout.

**New JSON**:
```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.482",
          "green" : "0.720",
          "red" : "0.324"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "light"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.482",
          "green" : "0.720",
          "red" : "0.324"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.574",
          "green" : "0.820",
          "red" : "0.410"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Impact**: `AppColors.primary` (used in `MealLogView` text, `DragToLogOverlay` border, and anywhere `AppColors.primary` is referenced) becomes green. Since `AppColors.brand` will now point to `Color("AppPrimary")`, both constants render identically — no split-brand risk.

---

### Step 1.3 — `PrimaryContainer.colorset`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Resources/Assets.xcassets/PrimaryContainer.colorset/Contents.json`

**Current state**: Light/universal = `#FFF0E6` (warm peach/cream); dark = `#3D2000` (deep orange-brown).

**New values**: Light = very pale green `#E8F7E0` (R:0.910, G:0.969, B:0.878); Dark = deep forest green `#1A3B15` (R:0.102, G:0.231, B:0.082).

**New JSON**:
```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.878",
          "green" : "0.969",
          "red" : "0.910"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "light"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.878",
          "green" : "0.969",
          "red" : "0.910"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.082",
          "green" : "0.231",
          "red" : "0.102"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Impact**: Selection backgrounds, soft container tints used in `MealLogView` and `DragToLogOverlay` become green-tinted instead of orange-tinted. `DragToLogOverlay` will change appearance automatically via this asset edit — no Swift changes needed in that file.

---

## Phase 2: Swift Constant — `AppColor.swift`

### Step 2.1 — Add `brand` constant and update comments

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Shared/Color/AppColor.swift`

**Change**: Add `static let brand` inside the `AppColors` enum as an asset-catalog alias for `AppPrimary`, and update the comment on `primaryContainer` to remove the "softer orange" wording.

**Exact edit** — replace the `// MARK: - Brand / Primary` block (lines 4–7) with:

```swift
    // MARK: - Brand / Primary
    static let brand             = Color("AppPrimary")           // adaptive: reads light/dark from AppPrimary.colorset
    static let primary           = Color("AppPrimary")
    static let primaryContainer  = Color("PrimaryContainer")     // soft green background
    static let onPrimary         = Color("OnPrimary")            // text/icons on primary
```

**Why `Color("AppPrimary")` not `Color(hue:...)`**: The asset-backed approach is the simplest way to achieve dark-mode adaptivity. Both `brand` and `primary` now point to the same asset, which carries correct light (R:0.324, G:0.720, B:0.482) and dark (R:0.410, G:0.820, B:0.574) variants. Any call site using `AppColors.brand.opacity(x)` will operate on the correct base color for the active color scheme. No `UIColor(dynamicProvider:)` wrapper needed.

**Note**: `brand` and `primary` are functionally identical — both resolve to `Color("AppPrimary")`. Keeping both allows call sites to express intent: `AppColors.brand` for brand-identity uses (FAB, header buttons) and `AppColors.primary` for more generic "primary color" uses where it already exists in the codebase.

---

## Phase 3: Swift File Updates — Brand Orange to `.brand`

Work through these files in order. Each section lists every `.orange` / `Color.orange` occurrence in that file, whether to change it, and the exact replacement.

---

### 3.1 — `MainTabView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Tab/MainTabView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 45 | `.tint(.orange)` | `.tint(AppColors.brand)` | Tab bar tint — primary brand signal |

This is the highest-visibility change in the entire app.

---

### 3.2 — `ExpandableFAB.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/ExpandableFAB.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 69 | `colors: [.orange, .orange.opacity(0.8)]` | `colors: [AppColors.brand, AppColors.brand.opacity(0.8)]` | FAB fill gradient — primary CTA brand color |
| 75 | `.shadow(color: .orange.opacity(0.35), ...)` | `.shadow(color: AppColors.brand.opacity(0.35), ...)` | FAB colored shadow — matches fill |

**Note**: Lines 18–21 (sub-action item colors: `.pink`, `.blue`, `.green`) are already non-orange; leave untouched.

---

### 3.3 — `HomeView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/HomeView.swift`

**Part A — Brand orange replacements**:

| Line | Current | Change to | Reason |
|---|---|---|---|
| 204 | `Color.orange.opacity(0.85)` | `AppColors.brand.opacity(0.85)` | Calendar button gradient — brand CTA |
| 205 | `Color.orange` | `AppColors.brand` | Calendar button gradient — brand CTA |
| 212 | `.shadow(color: .orange.opacity(0.3), ...)` | `.shadow(color: AppColors.brand.opacity(0.3), ...)` | Calendar button shadow |
| 259 | `color: .orange` | `color: AppColors.brand` | Calories `WellnessRingItem` color — primary wellness indicator |

**Part B — Exercise ring hue collision (Step 3.3b)**:

After changing line 259, the Calories ring becomes brand green (hue 0.40). The Exercise ring at line 277 is currently `Color(hue: 0.40, saturation: 0.62, brightness: 0.70)` — **identical hue** to the new brand green. The `WellnessRingsCard` depends on all four rings being visually distinct. With both Calories and Exercise at hue 0.40, the rings become indistinguishable to the user at a glance.

**Resolution**: Shift the Exercise ring to teal/cyan (hue ~0.50), which sits visually midway between the brand green (0.40) and the existing blue Water ring (hue 0.58). This preserves all four rings as distinct and keeps the "active/movement" semantic that a cool green-teal conveys.

| Line | Current | Change to | Reason |
|---|---|---|---|
| 277 | `Color(hue: 0.40, saturation: 0.62, brightness: 0.70)` | `Color(hue: 0.50, saturation: 0.62, brightness: 0.70)` | Exercise ring — shifted to teal to avoid hue collision with brand green Calories ring |

**Resulting ring palette after this plan**:
- Calories: hue 0.40 (brand green) — primary food-tracking metric
- Water: hue 0.58 (blue) — unchanged
- Exercise: hue 0.50 (teal) — shifted from 0.40
- Stress: hue 0.76 (purple) — unchanged

All four rings remain visually distinct.

---

### 3.4 — `NarratorButton.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Shared/Components/NarratorButton.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 23 | `.stroke(Color.orange.opacity(0.25), ...)` | `.stroke(AppColors.brand.opacity(0.25), ...)` | Speaking state pulse ring — app brand, not semantic |
| 37 | `[Color.orange, Color.orange.opacity(0.75)]` | `[AppColors.brand, AppColors.brand.opacity(0.75)]` | Speaking state gradient fill |
| 45 | `.orange.opacity(0.35)` (shadow) | `AppColors.brand.opacity(0.35)` | Speaking state glow shadow |

**Note**: The NarratorButton's active-speaking orange marks the app's active state, not a data tier — it is brand and should change.

---

### 3.5 — `MealLogView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/MealLogView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 383 | `colors: [Color.orange, Color.orange.opacity(0.8)]` | `colors: [AppColors.brand, AppColors.brand.opacity(0.8)]` | Save/confirm button gradient — brand CTA |

---

### 3.6 — `FoodJournalView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/FoodJournalView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 142 | `colors: [.orange, .orange.opacity(0.8)]` | `colors: [AppColors.brand, AppColors.brand.opacity(0.8)]` | Floating "+" button fill gradient |
| 148 | `.shadow(color: .orange.opacity(0.35), ...)` | `.shadow(color: AppColors.brand.opacity(0.35), ...)` | Floating "+" button shadow |
| 214 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Streak flame icon in toolbar |
| 226 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Chart icon in toolbar |
| 311 | `.tint(.orange)` | `.tint(AppColors.brand)` | Date picker graphical tint |
| 323 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | "Today" toolbar button |

---

### 3.7 — `StreakDetailView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/StreakDetailView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 176 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Hero flame icon — streak celebration, brand identity |
| 190 | `Color.orange` (in `isActiveToday ? .green : Color.orange`) | `Color.yellow` | **Special case** — "not yet logged today" indicator. This is a pending/urgency status signal, not brand identity. `.yellow` is more appropriate than brand green (which would ironically mean "not done yet") and more appropriate than orange (which in this context fights the brand change). Final ternary: `isActiveToday ? Color.green : Color.yellow` |
| 306 | `Color.orange` (circle stroke for today) | `AppColors.brand` | "Today" ring outline — celebratory/identity marker |
| 311 | `Color.orange` (circle fill for logged days) | `AppColors.brand` | Logged day filled circle — celebrating a completed day |
| 349 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Past streak flame icon in list |

---

### 3.8 — `GoalExpandableView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/GoalExpandableView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 159 | `colors: [Color.orange, Color.orange.opacity(0.8)]` | `colors: [AppColors.brand, AppColors.brand.opacity(0.8)]` | Goal progress fill gradient — brand |

---

### 3.9 — `GoalsView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Goals/Views/GoalsView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 82 | `iconColor: .orange` (nutrition card) | `iconColor: AppColors.brand` | Nutrition GoalCard header icon. **Decision rationale**: This `flame.fill` icon is the header icon for the "Nutrition" goals card — it represents the section identity within the Goals screen, not a calorie-burn data visualization. The flame in `BurnView`'s fire gradients (kept orange) is embedded in a full fire/heat aesthetic for the permission screen. These are different contexts. Goals card header icons are brand-identity markers, so this changes. |
| 333 | `.foregroundStyle(... : .orange)` (stepper minus) | `.foregroundStyle(... : AppColors.brand)` | Stepper active state — brand UI control |
| 350 | `.foregroundStyle(... : .orange)` (stepper plus) | `.foregroundStyle(... : AppColors.brand)` | Stepper active state — brand UI control |
| 402 | `.foregroundStyle(... : .orange)` (rest day toggle) | `.foregroundStyle(... : AppColors.brand)` | Toggle active state — brand |
| 413 | `.foregroundStyle(... : .orange)` (minutes stepper) | `.foregroundStyle(... : AppColors.brand)` | Stepper active state — brand |

---

### 3.10 — `BurnView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Burn/Views/BurnView.swift`

This file has 7 orange occurrences. They split into two categories:

**Brand uses — CHANGE**:

| Line | Current | Change to | Reason |
|---|---|---|---|
| 88 | `.foregroundColor(.orange)` (hero kcal number) | `.foregroundColor(AppColors.brand)` | Primary data number color — brand |
| 102 | `color: .orange` (ProgressRingView) | `color: AppColors.brand` | Calorie ring — brand |
| 119 | `color: .orange` (7D Avg stat chip) | `color: AppColors.brand` | Active energy average — brand primary metric |
| 260 | `.tint(.orange)` (loadingView ProgressView) | `.tint(AppColors.brand)` | Loading spinner tint — brand |

**Fire/burn gradient uses — LEAVE AS ORANGE** (semantic: combustion/heat motif):

| Line | Current | Decision | Reason |
|---|---|---|---|
| 204 | `colors: [.orange.opacity(0.15), .red.opacity(0.08)]` | **KEEP** | Permission screen background glow — fire/heat motif |
| 214 | `colors: [.orange, .red]` | **KEEP** | Permission screen heart icon gradient — fire motif |
| 243 | `colors: [.orange, .red]` | **KEEP** | Permission screen CTA button — fire motif, consistent with screen's visual language |

**Rationale for keeping fire gradients**: The entire `permissionView` in BurnView uses an orange+red fire aesthetic ("heart on fire" = burning calories / active energy). Changing these to green+red creates a traffic-light semantic that contradicts the intended combustion theme. These three occurrences are self-contained to the permission/empty state screen and do not appear once data loads.

---

### 3.11 — `BurnDetailView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Burn/Views/BurnDetailView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 55 | `.foregroundColor(.orange)` ("Done" button text) | `.foregroundColor(AppColors.brand)` | Navigation action button — brand |

---

### 3.12 — `ProfileView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Tab/ProfileView.swift`

This file has the most occurrences (~20). They span five logical groups:

**Group A — Profile header and Goals card (brand uses — CHANGE)**:

| Line | Current | Change to | Reason |
|---|---|---|---|
| 71 | `.foregroundStyle(.orange.opacity(0.85))` | `.foregroundStyle(AppColors.brand.opacity(0.85))` | Profile avatar icon |
| 140 | `.foregroundStyle(.orange)` | `.foregroundStyle(AppColors.brand)` | Widget section header icon |
| 655 | `.fill(Color.orange.opacity(0.12))` | `.fill(AppColors.brand.opacity(0.12))` | Goals card icon background |
| 659 | `.foregroundStyle(.orange)` | `.foregroundStyle(AppColors.brand)` | Goals card "target" icon |

**Group B — Widget preview miniatures (CHANGE to brand)**:

These are in `SmallPreview`, `MediumPreview`, and `LargePreview` structs showing a calorie-tracking widget mockup. The preview must match the new brand color.

| Line | Current | Change to | Reason |
|---|---|---|---|
| 201 | `colors: [.orange.opacity(0.85)]` | `colors: [AppColors.brand.opacity(0.85)]` | SmallPreview mini ring progress arc |
| 256 | `.fill(Color.orange)` (SizePill selected bg) | `.fill(AppColors.brand)` | Selected size pill background |
| 339 | `Color.orange.opacity(0.07)` (SmallPreview bg tint) | `AppColors.brand.opacity(0.07)` | Widget preview card background gradient tint |
| 346 | `.foregroundStyle(.orange)` (fork.knife icon) | `.foregroundStyle(AppColors.brand)` | Widget preview header icon |
| 351 | `Color.orange.opacity(0.18)` (ring track) | `AppColors.brand.opacity(0.18)` | Ring track (empty ring background) |
| 354 | `colors: [.orange, .pink]` (ring gradient) | `colors: [AppColors.brand, .pink]` | Ring fill gradient — keep `.pink` as accent |
| 371 | `.foregroundStyle(.orange)` (plus.circle.fill) | `.foregroundStyle(AppColors.brand)` | "Add Food" button icon |
| 375 | `Color.orange.opacity(0.12)` (capsule bg) | `AppColors.brand.opacity(0.12)` | "Add Food" button background |
| 389 | `Color.orange.opacity(0.06)` (MediumPreview bg tint) | `AppColors.brand.opacity(0.06)` | MediumPreview background gradient |
| 395 | `Color.orange.opacity(0.18)` (ring track) | `AppColors.brand.opacity(0.18)` | MediumPreview ring track |
| 398 | `colors: [.orange, .pink]` (ring gradient) | `colors: [AppColors.brand, .pink]` | MediumPreview ring fill gradient |
| 411 | `.foregroundStyle(.orange)` (plus icon) | `.foregroundStyle(AppColors.brand)` | MediumPreview "Add" button icon |
| 412 | `.foregroundStyle(.orange)` ("Add" text) | `.foregroundStyle(AppColors.brand)` | MediumPreview "Add" text |
| 439 | `Color.orange.opacity(0.06)` (LargePreview bg tint) | `AppColors.brand.opacity(0.06)` | LargePreview background gradient |
| 444 | `.foregroundStyle(.orange)` (fork.knife.circle.fill) | `.foregroundStyle(AppColors.brand)` | LargePreview header icon |
| 455 | `.foregroundStyle(.orange)` (calorie number) | `.foregroundStyle(AppColors.brand)` | LargePreview primary calorie count |
| 464 | `Color.orange.opacity(0.15)` (progress bar track) | `AppColors.brand.opacity(0.15)` | LargePreview calorie progress bar track |
| 466 | `colors: [.orange, .pink]` (progress bar fill) | `colors: [AppColors.brand, .pink]` | LargePreview calorie progress bar fill |
| 488 | `Color.orange.opacity(0.35)` (bullet dot) | `AppColors.brand.opacity(0.35)` | Recent foods bullet dot |
| 506 | `colors: [.orange, .pink.opacity(0.85)]` (CTA capsule) | `colors: [AppColors.brand, .pink.opacity(0.85)]` | LargePreview "Add Food" CTA button |

**Group C — Widget instructions step color and header icon (CHANGE)**:

| Line | Current | Change to | Reason |
|---|---|---|---|
| 550 | `("magnifyingglass", .orange, "Search for WellPlate...")` | `("magnifyingglass", AppColors.brand, ...)` | "Search for WellPlate" step icon — brand identity |
| 564 | `.foregroundStyle(.orange)` (rectangle.3.group.fill) | `.foregroundStyle(AppColors.brand)` | Widget instructions sheet header icon |

**Group D — Status badge `isInstalled ? .green : .orange` — LEAVE AS ORANGE (semantic)**:

| Line | Current | Decision | Reason |
|---|---|---|---|
| 229 | `Color.orange` (not-installed dot) | **KEEP** | Binary status indicator — orange = problem, green = good. Changing to brand green would make "not installed" look successful. |
| 234 | `.orange` (not-installed text) | **KEEP** | Same reason |
| 240 | `Color.orange.opacity(0.1)` (not-installed capsule) | **KEEP** | Same reason |

**Group E — MiniMacroBar fat macro color — LEAVE AS ORANGE (nutritional convention)**:

| Line | Current | Decision | Reason |
|---|---|---|---|
| 423 | `color: .orange` (Fat MiniMacroBar in MediumPreview) | **KEEP** | Fat macro convention — orange=fat is consistent throughout nutritional UI |
| 478 | `color: .orange` (Fat MiniMacroBar in LargePreview) | **KEEP** | Same |

**Note on line 311**: The original brainstorm listed line 311 as having an orange reference. This line is no longer present in the current file. No action needed — confirmed absent from current source.

---

### 3.13 — `WellnessCalendarView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/WellnessCalendarView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 398 | `color: .orange` (macroChip "Cal") | `color: AppColors.brand` | Calorie chip — brand primary metric |
| 422 | `.foregroundStyle(.orange)` (calorie value text) | `.foregroundStyle(AppColors.brand)` | Calorie text emphasis |

**Note**: The fat macro chip in this file is already `.yellow` (pre-existing convention in this view — different from `MealLogCard` and `ProfileView` which use `.orange` for fat). This inconsistency is pre-existing; do not "fix" the fat chip to orange while making this change.

---

### 3.14 — `DisambiguationChipsView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Views/DisambiguationChipsView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 27 | `.fill(Color.orange.opacity(0.15))` | `.fill(AppColors.brand.opacity(0.15))` | Question icon background |
| 31 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Question mark icon |
| 57 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Calorie badge text |
| 62 | `.fill(Color.orange.opacity(0.12))` | `.fill(AppColors.brand.opacity(0.12))` | Calorie badge background |

---

### 3.15 — `HomeHeaderView.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/HomeHeaderView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 40 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Streak flame icon |
| 53 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Chart icon |

---

### 3.16 — `CalorieHeroCard.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/CalorieHeroCard.swift`

**Active code** (non-commented):

| Line | Current | Change to | Reason |
|---|---|---|---|
| 100 | `color: .orange` | **KEEP as `.orange`** | Fat macro color in `macroRow` — nutritional data convention |
| 166 | `.foregroundColor(.orange)` | `.foregroundColor(AppColors.brand)` | Flame icon on calorie card |
| 183 | `colors: [Color.orange, Color.orange.opacity(0.8)]` | `colors: [AppColors.brand, AppColors.brand.opacity(0.8)]` | Calorie progress gradient |

**Commented-out code** (lines 35, 39, 53, 54 — prefixed with `//`):
Leave commented code as-is. No runtime impact.

---

### 3.17 — `MealLogCard.swift`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/MealLogCard.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 23 | `Capsule().fill(Color.orange)` ("Today" badge fill) | `Capsule().fill(AppColors.brand)` | "Today" badge — brand identity marker |
| 116 | `macroPill("\(Int(entry.fat))g F", color: .orange)` | **KEEP as `.orange`** | Fat macro pill — nutritional convention |
| 160 | `case 5..<11: return .orange` | **KEEP as `.orange`** | Breakfast time slot color — morning/sunrise semantic |

---

### 3.18 — `WellnessRingsCard.swift` (Preview only)

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 154 | `color: .orange` (Calories ring in `#Preview`) | `color: AppColors.brand` | Preview should reflect real data — Calories ring color is set in HomeView.swift line 259 |

---

### 3.19 — `HealthModels.swift` — `accentColor` for `activeEnergy`

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Models/HealthModels.swift`

| Line | Current | Decision | Reason |
|---|---|---|---|
| 74 | `case .fair: return .orange` | **KEEP** | Quality scale (poor=red, fair=orange, good=green, excellent=mint) — data semantics |
| 136 | `case .activeEnergy: return .orange` | **CHANGE to `AppColors.brand`** | `BurnMetric.accentColor` — feeds `BurnChartView` for weekly active energy chart. Changing here keeps the chart consistent with the hero card, progress ring, and stat chip (all being changed in step 3.10). |

---

## Phase 4: Files to Skip Entirely

These files have `.orange` occurrences that are all semantic — do not touch them:

| File | Line(s) | Why |
|---|---|---|
| `VitalMetric.swift` | 45 | `case .systolicBP: return .orange` — chart color differentiation per vital, not brand |
| `StressModels.swift` | (dynamic score color) | Stress score gradient green→yellow→orange→red — data semantics |
| `Stress/Views/DietDetailView.swift` | 103 | Carbs macro color `color: .orange` — nutritional convention |
| `Stress/Views/ScreenTimeDetailView.swift` | 121, 147, 189 | Warning scale (mint→yellow→orange→red) — severity tiers |
| `Home/Components/QuickAddCard.swift` | 13, 20, 46, 52 | All commented-out dead code — no runtime impact |

---

### `MiniLineChartView.swift` Preview Update (optional but recommended)

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Burn/Components/MiniLineChartView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 53 | `color: .orange` (in `#Preview`) | `color: AppColors.brand` | Preview accuracy — real usage reads from `BurnMetric.accentColor` (being changed in step 3.19) |

---

### `ProgressRingView.swift` Preview Update (optional but recommended)

**File**: `/Users/hariom/Desktop/WellPlate/WellPlate/Features + UI/Burn/Components/ProgressRingView.swift`

| Line | Current | Change to | Reason |
|---|---|---|---|
| 55 | `color: .orange` (in `#Preview`) | `color: AppColors.brand` | Preview accuracy |

---

## Complete Change Summary

### Files that change (production code)

| File | Lines changed | Special changes | Lines kept orange |
|---|---|---|---|
| `Assets.xcassets/AccentColor.colorset/Contents.json` | All 3 color blocks | — | — |
| `Assets.xcassets/AppPrimary.colorset/Contents.json` | All 3 color blocks | — | — |
| `Assets.xcassets/PrimaryContainer.colorset/Contents.json` | All 3 color blocks | — | — |
| `Shared/Color/AppColor.swift` | Add `brand` constant | — | — |
| `Tab/MainTabView.swift` | Line 45 | — | — |
| `Home/Components/ExpandableFAB.swift` | Lines 69, 75 | — | — |
| `Home/Views/HomeView.swift` | Lines 204, 205, 212, 259; Exercise ring line 277 shifted to hue 0.50 | — | — |
| `Shared/Components/NarratorButton.swift` | Lines 23, 37, 45 | — | — |
| `Home/Views/MealLogView.swift` | Line 383 | — | — |
| `Home/Views/FoodJournalView.swift` | Lines 142, 148, 214, 226, 311, 323 | — | — |
| `Home/Views/StreakDetailView.swift` | Lines 176, 306, 311, 349 | Line 190 → `.yellow` (not brand, not orange) | — |
| `Home/Components/GoalExpandableView.swift` | Line 159 | — | — |
| `Goals/Views/GoalsView.swift` | Lines 82, 333, 350, 402, 413 | — | — |
| `Burn/Views/BurnView.swift` | Lines 88, 102, 119, 260 | — | Lines 204, 214, 243 (fire gradients) |
| `Burn/Views/BurnDetailView.swift` | Line 55 | — | — |
| `Tab/ProfileView.swift` | Lines 71, 140, 201, 256, 339, 346, 351, 354, 371, 375, 389, 395, 398, 411, 412, 439, 444, 455, 464, 466, 488, 506, 550, 564, 655, 659 | — | Lines 229, 234, 240 (status badge); Lines 423, 478 (fat macro) |
| `Home/Views/WellnessCalendarView.swift` | Lines 398, 422 | — | — |
| `Home/Views/DisambiguationChipsView.swift` | Lines 27, 31, 57, 62 | — | — |
| `Home/Components/HomeHeaderView.swift` | Lines 40, 53 | — | — |
| `Home/Components/CalorieHeroCard.swift` | Lines 166, 183 | — | Line 100 (fat macro) |
| `Home/Components/MealLogCard.swift` | Line 23 | — | Lines 116 (fat), 160 (breakfast) |
| `Models/HealthModels.swift` | Line 136 (activeEnergy accentColor) | — | Line 74 (fair quality) |

### Files that change (previews only — low priority)

| File | Line | Change |
|---|---|---|
| `Home/Components/WellnessRingsCard.swift` | 154 | `.orange` → `AppColors.brand` in `#Preview` |
| `Burn/Components/MiniLineChartView.swift` | 53 | `.orange` → `AppColors.brand` in `#Preview` |
| `Burn/Components/ProgressRingView.swift` | 55 | `.orange` → `AppColors.brand` in `#Preview` |

### Files that are untouched (all semantic)

- `VitalMetric.swift` (systolicBP chart color)
- `StressModels.swift` (stress score gradient)
- `Stress/Views/DietDetailView.swift` (carbs macro)
- `Stress/Views/ScreenTimeDetailView.swift` (warning scale)
- `Home/Components/QuickAddCard.swift` (all commented out)

---

## Implementation Order

1. **Phase 1 first** (asset catalog) — gives immediate visual feedback in Simulator even before touching Swift. Build and run after Phase 1 to confirm `AccentColor` propagation.
2. **Phase 2 next** (`AppColor.swift`) — the `brand` constant must exist before Phase 3 so the compiler accepts `AppColors.brand` references.
3. **Step 3.3b early** — change the Exercise ring hue in `HomeView.swift` line 277 at the same time as the Calories ring change (step 3.3 part A). Do not leave this until the end; the hue collision is immediately visible.
4. **Phase 3 file by file** — work top-to-bottom through the list. Build after every 3–4 files to catch typos early. Suggested order matches the summary table (most visible changes first).
5. **Preview updates last** — `#Preview` blocks don't affect app behavior; do these after confirming the main app looks correct.

---

## Testing Strategy

### Visual Regression Checklist (manual, on device)

Run the app on a physical device or Simulator in both Light and Dark Mode after each phase.

**Phase 1 Checkpoint** (after colorset edits):
- [ ] Tab bar selected icon is green
- [ ] System Toggle is green when ON
- [ ] `AccentColor` propagation visible in any SwiftUI Picker

**Phase 3 Checkpoints** (after each major file):
- [ ] Home tab: Calorie ring = green; Exercise ring = teal (distinct from green); FAB button = green; calendar button = green
- [ ] Food Journal tab: floating "+" button = green; streak icon = green; date picker tint = green
- [ ] Streak Detail: flame icon = green; calendar logged days = green; "not yet logged today" dot = **yellow** (not green, not orange)
- [ ] Burn tab: hero kcal number = green; progress ring = green; loading spinner = green; fire gradients (permission screen) = orange+red (unchanged)
- [ ] Profile tab: avatar icon = green; widget card header icon = green; widget preview ring = green gradient; "Not added" status badge = orange (unchanged); fat macro bars = orange (unchanged)
- [ ] Goals tab: nutrition card icon = green; stepper +/- buttons = green
- [ ] NarratorButton (trigger speech): active glow = green
- [ ] DragToLogOverlay: border/tint = green (changed via asset update in Phase 1 — no Swift edit needed; verify appearance here)

**Dark Mode Checks**:
- [ ] Brand green (light mode) and dark-mode variant are both legible and visually consistent — asset-backed `AppColors.brand` should look correct in both modes
- [ ] `AppColors.brand` (via `Color("AppPrimary")`) renders identically in light and dark mode to `Color("AccentColor")`; view a side-by-side swatch of both in a test view if there is any doubt
- [ ] `PrimaryContainer` dark variant provides visible but non-glaring green tint in selection backgrounds
- [ ] `AppColors.brand.opacity(x)` calls (FAB shadow, calendar button shadow, etc.) use the correct dark-mode base color — verify the FAB shadow is not muddy in dark mode

**Ring Distinctness Check**:
- [ ] View `WellnessRingsCard` in Simulator. Confirm all four rings are visually distinct: green (Calories), blue (Water), teal (Exercise), purple (Stress). If green and teal appear too similar at ring size, consider shifting Exercise hue to 0.52–0.54.

### Semantic Color Preservation Checks

- [ ] `DietDetailView`: Carbs row = orange, Protein = green, Fat = yellow (unchanged)
- [ ] `ScreenTimeDetailView`: warning badge = orange, tip icon = orange (unchanged)
- [ ] `HealthModels` quality scale: fair = orange (unchanged)
- [ ] `VitalMetric`: systolic BP accent = orange in stress vitals (unchanged)
- [ ] `MealLogCard`: breakfast time slot (5–11 h) = orange (unchanged); fat pill = orange (unchanged)
- [ ] `ProfileView` StatusBadge: "Not added" = orange, "Active" = green (unchanged)
- [ ] `BurnView` permission screen: heart icon gradient = orange→red, CTA button = orange→red (unchanged)
- [ ] `WellnessCalendarView` fat chip = yellow (pre-existing convention, not to be "corrected" to orange)

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Accidentally changing a semantic orange | Medium | Each file's change list above explicitly calls out which lines to skip and why. Read before editing. |
| `AppColors.brand` not accessible from a file | Low | `AppColors` is in `AppColor.swift` inside the main target — available everywhere. |
| sRGB values in colorset not matching SwiftUI HSB constant | Low | Revision 2 uses `AppColors.brand = Color("AppPrimary")` — the asset and the Swift constant are the same asset; they cannot diverge. |
| Dark-mode green too bright or neon | Low-Medium | Dark variant H:0.40, S:0.50, V:0.82 = R:0.410, G:0.820, B:0.574. Test on device; if too vivid reduce V to 0.78 and adjust B accordingly. |
| `AccentColor` asset not picked up (Xcode caching) | Low | Clean build folder (`Cmd+Shift+K`) after JSON edits if colors don't refresh in Simulator. |
| ProfileView fat `MiniMacroBar` accidentally changed | Medium | Lines 423 and 478 are explicitly KEEP. Double-check after editing ProfileView. |
| StreakDetailView line 190 changed to brand instead of yellow | Medium | Summary table now correctly shows this as a "special change" to `.yellow`. Verify ternary reads `isActiveToday ? Color.green : Color.yellow` after the edit. |
| Exercise and Calories rings appear too similar at ring size | Medium | Hue gap is 0.10 (teal vs green), which should be visually sufficient. Verify in Simulator; shift Exercise hue to 0.52–0.54 if needed. |
| Widget extension target with its own orange references | Low-Medium | Git status shows no widget target files. Confirm no `WellPlateWidgetExtension` folder exists before closing the plan. If one exists, run the same orange grep against its source directory. |

---

## Rollback Strategy

This change touches only color values — no logic changes, no data migrations, no API changes. Rollback is trivially: `git stash` or `git checkout` on the affected files. If work spans multiple sessions, use feature branch + `git revert` to cleanly undo.

---

## Success Criteria

- [ ] All three `.colorset` JSON files contain the corrected green sRGB values (R:0.324, G:0.720, B:0.482 light; R:0.410, G:0.820, B:0.574 dark)
- [ ] `AppColors.brand = Color("AppPrimary")` exists in `AppColor.swift` and compiles without warnings
- [ ] `AppColors.brand` and `AppColors.primary` render identically (both are `Color("AppPrimary")`)
- [ ] Tab bar selected icon is green in both Light and Dark Mode
- [ ] Calorie ring on HomeView is green; Exercise ring is teal (visually distinct from green)
- [ ] FAB button is green; shadow is correctly tinted in dark mode
- [ ] Burn tab hero number and ring are green; fire gradients remain orange+red
- [ ] Profile tab widget preview ring shows green gradient (not orange)
- [ ] Fat macro bars (DietDetailView, ProfileView, MealLogCard, CalorieHeroCard) remain orange
- [ ] Breakfast time slot in MealLogCard remains orange
- [ ] "Not added" StatusBadge in ProfileView remains orange
- [ ] Fair quality color in HealthModels remains orange
- [ ] ScreenTimeDetailView warning colors remain orange
- [ ] "Not yet logged today" dot in StreakDetailView is **yellow** (not orange, not green)
- [ ] DragToLogOverlay border/tint is green (via asset update)
- [ ] No new compiler warnings or errors introduced
- [ ] App runs without crashes on both Light and Dark Mode
