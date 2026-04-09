# Brainstorm: Change Primary/Accent Color from Orange to Green

**Date**: 2026-03-11
**Status**: Ready for Planning

---

## Problem Statement

The app's brand/primary color is currently orange (`#FF6A00` / `Color.orange`). The goal is to replace it with a specific muted green: `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`, which computes to approximately `RGB(0.414, 0.720, 0.324)` — a medium, earthy green.

The challenge is that "orange" is used in two distinct ways throughout the codebase:
1. **Brand uses** — places where orange means "this app's primary color" (e.g., tab bar tint, FAB button, calories ring, meal log button, streak icons, NarratorButton active state).
2. **Semantic/data uses** — places where orange means something specific in a data-classification context that has nothing to do with brand (e.g., "fair" sleep quality, carbs macro color, breakfast meal time, systolic BP accent, screen time warning level, fat macro bar).

Conflating these two categories is the single biggest risk in this change.

---

## Color Inventory: Where Orange Lives

### Source of Truth Files (must change)
| File | What it controls |
|---|---|
| `Assets.xcassets/AccentColor.colorset` | System-level accent (SwiftUI `.accentColor`, UIKit tint fallback) — currently `#FF6A00` |
| `Assets.xcassets/AppPrimary.colorset` | `AppColors.primary` — used for text, tint, borders in MealLogView and DragToLogOverlay |
| `Assets.xcassets/PrimaryContainer.colorset` | `AppColors.primaryContainer` — soft background tint for selections (currently a near-white orange-tinted color) |

### High-Impact Hard-coded Brand Orange (should change to green)
| File | Lines | Context |
|---|---|---|
| `MainTabView.swift:45` | `.tint(.orange)` | Tab bar icon tint — the most visible use |
| `ExpandableFAB.swift:69,75` | Gradient + shadow | FAB button fill — primary CTA |
| `HomeView.swift:204,205,212` | Gradient + shadow | Log meal button in header |
| `NarratorButton.swift:23,37,45` | Stroke, gradient, shadow | Active speaking state |
| `MealLogView.swift:383` | Button gradient | Save/confirm button |
| `FoodJournalView.swift:142,148,311,323` | Circle gradient, date picker tint, toolbar | Food journal primary actions |
| `StreakDetailView.swift:306,311` | Calendar ring stroke + fill | Today / logged day indicator |
| `GoalExpandableView.swift:159` | Progress bar gradient | Goal progress fill |
| `BurnView.swift:88,102,119,204,214,243,260` | Hero number, ring, stat chip, gradients, loading tint | Entire Burn tab primary color |
| `BurnDetailView.swift:55` | "Done" button text | Navigation action |
| `GoalsView.swift:82,333,350,402,413` | Nutrition card icon, stepper +/- buttons | Goals editing UI |
| `ProfileView.swift:71,140,201,256,311,339,346,354,375,389,411,444,455,464,466,488,506,564,655,659` | Extensive use — avatar, widget preview rings, progress bars, gradients, indicators | Profile tab — very heavily orange |
| `DisambiguationChipsView.swift:27,31,57,62` | Question icon bg + calorie badge | Disambiguation UI |
| `CalorieHeroCard.swift:100,166,183` | Fat macro color, flame icon, progress gradient | Home calorie card |
| `HomeHeaderView.swift:40,53` | Streak flame icon, chart icon | Home header stats |
| `WellnessCalendarView.swift:398,422` | Calorie chip, calorie value text | Wellness calendar |
| `MealLogCard.swift:23,116,160` | "Today" badge, fat macro pill, breakfast time color | Meal log list items |

### Semantic Orange (should NOT change to brand green — these are data classifications)
| File | Line | Context | Why it stays orange |
|---|---|---|---|
| `HealthModels.swift:74` | `case .fair: return .orange` | Sleep/activity quality scale: poor=red, fair=orange, good=green, excellent=mint | Data semantics — orange means "mediocre" in a red→green scale |
| `VitalMetric.swift:45` | `case .systolicBP: return .orange` | Each vital has a distinct color for chart differentiation | Data identity, not brand |
| `StressModels.swift` | Dynamic stress score color | Gradient from green to red based on stress level | Data semantics |
| `DietDetailView.swift:103` | `macroRow(...color: .orange)` for Carbs | Carbs is always orange in nutrition science convention | Nutritional convention |
| `ScreenTimeDetailView.swift:121,147,189` | Warning badge, score row at 8h, tip icon | Warning level in a scale (mint→yellow→orange→red) | Warning/severity scale |
| `MealLogCard.swift:160` | `case 5..<11: return .orange` (breakfast) | Breakfast time slot color (breakfast=orange is intuitive — sunrise) | Time-of-day semantic |
| `MealLogCard.swift:116` | Fat macro pill | Fat macro convention | Nutritional convention |
| `CalorieHeroCard.swift:100` | Fat macro color | Same | Nutritional convention |
| `ProfileView.swift:229,234,240` | `isInstalled ? .green : .orange` | "Not added" state for widget — orange=warning | Status indicator semantic |
| `StreakDetailView.swift:190` | `isActiveToday ? .green : .orange` | "Not yet logged today" — orange=pending | Status/urgency semantic |

---

## Core Requirements
- The brand/accent color throughout the app changes from orange to `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`
- The `AccentColor` asset must change (affects system-level tints, toggles, links, etc.)
- `AppColors.primary` (the `AppPrimary` color asset) must change
- `AppColors.primaryContainer` must be rederived as a light tint of the new green
- Hard-coded `.orange` brand uses must be changed to the new green
- Semantic `.orange` uses (data classifications, warning scales, macros) must be left alone
- `PrimaryContainer` (soft background used for selections) needs a new green-tinted variant

---

## Constraints
- iOS 26 / SwiftUI — no UIKit color overrides needed
- The new green is specified in HSB; it must be correctly converted to the sRGB values needed by `.colorset` JSON files
- No font or shadow changes required
- The `BurnView` has an orange+red fire gradient (`[.orange, .red]`) that represents "active energy burning" — this is partially semantic (fire = heat = energy) and partially brand. Needs a decision.
- `ProfileView` uses an `orange+pink` gradient for mini rings/bars — this is brand but also has a food/nutrition association

---

## Color Math: New Green in sRGB

`Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`:
- H=0.40 (144° — a muted, medium green)
- S=0.55, B=0.72
- sRGB: R = B*(1-S) = 0.72*0.45 = 0.324, G = 0.720, B = 0.324 (approximately)
- More precisely via HSB→RGB: the hue 0.40 is in the green-to-cyan sextant (0.333..=green, 0.5=cyan)
  - Sector: hue=0.40, in [0.333, 0.5] range → green dominant
  - R ≈ 0.414, G ≈ 0.720, B ≈ 0.324 (computed)
- Hex approximation: `#69B853` or similar (sage/forest green)

For `PrimaryContainer` (light version, used for selection backgrounds):
- Light mode: very light green tint, similar to current `#FFE6F0`→ use something like `#E6F5E0`
- Dark mode: deep dark green tint, like `#1A3D20`

---

## Approach 1: Asset Catalog + Single Static Extension (Recommended)

**Summary**: Change the 3 color assets (`AccentColor`, `AppPrimary`, `PrimaryContainer`) to the new green values, then add a Swift `Color` extension constant `AppColors.brand` that exposes the same green as a Swift value (so hard-coded `.orange` call sites can be updated to `.brand` instead of duplicating the HSB literal everywhere).

**Steps**:
1. Update `AccentColor.colorset` — change all 3 entries (universal, light, dark) to the green sRGB values
2. Update `AppPrimary.colorset` — same green values (light mode = full opacity, dark mode = slightly lighter/adjusted)
3. Update `PrimaryContainer.colorset` — light-mode: very light green `~#E8F5E0`, dark-mode: deep dark green `~#1A3A14`
4. Add to `AppColor.swift`: `static let brand = Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` as a convenience alias
5. Update all brand `.orange` call sites in Swift files to use `AppColors.brand` (or `.brand` if imported) — approximately 25 files

**Pros**:
- Asset catalog change gives you proper light/dark mode support on `AccentColor` and `AppPrimary`
- Single source of truth: all future brand color uses flow from one constant
- Clean separation: `AppColors.brand` vs. semantic `.orange` is clearly named
- `AccentColor` change propagates to all SwiftUI components that respect it (Toggle, Link, etc.) automatically

**Cons**:
- Requires touching ~25 files for the `.orange` → `.brand` substitution
- `BurnView`'s fire gradient `[.orange, .red]` requires a judgment call (change to `[.brand, .red]`? Looks odd if green+red = traffic light)
- `ProfileView` has ~20 orange references, heavily intertwined with the nutrition/food widget preview concept

**Complexity**: Medium
**Risk**: Low (purely cosmetic change, no logic)

---

## Approach 2: Asset Catalog Only + Global `.tint` Override

**Summary**: Change only the 3 color assets (same as Approach 1), and add `.tint(AppColors.primary)` at the root `WindowGroup` or `RootView` level, relying on SwiftUI's tint propagation to override the hard-coded `.orange` call sites that use `.accentColor`-sensitive components. Leave non-tint hard-coded `.orange` in place.

**Steps**:
1. Change color assets (same as Approach 1)
2. Add `.tint(AppColors.primary)` at the top of `RootView` or inside `WellPlateApp`
3. Remove the existing `.tint(.orange)` from `MainTabView`
4. Do NOT touch individual `.orange` literals in non-tint contexts

**Pros**:
- Minimal file changes
- Fast to implement

**Cons**:
- Does NOT change hard-coded `Color.orange` usages — most of the visible orange in `BurnView`, `ProfileView`, `ExpandableFAB`, `StreakDetailView`, etc. stays orange
- The result would be a split personality: tab bar = green, but calorie ring = orange, FAB button = orange
- Incomplete and likely visually jarring

**Complexity**: Low
**Risk**: Medium (incomplete result creates inconsistency)

---

## Approach 3: Full Find-and-Replace with No New Abstraction

**Summary**: Use a text search-replace to swap every `\.orange` and `Color\.orange` with `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` globally, then manually revert the semantic uses.

**Pros**:
- Catches everything mechanically

**Cons**:
- Creates a bloated, unreadable constant repeated 50+ times in code
- High risk of accidentally replacing semantic oranges (carbs, fair quality, etc.)
- No abstraction — future brand color changes require the same mass find-and-replace again
- The literal `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` inline is not self-documenting

**Complexity**: Low effort, High maintenance debt
**Risk**: High (semantic orange collateral damage)

---

## Approach 4: Introduce a `Color` Extension Computed Property with Adaptive Dark/Light

**Summary**: Like Approach 1, but instead of relying on the asset catalog for `AppColors.brand`, define the color entirely in Swift with an adaptive light/dark variant using `UIColor(dynamicProvider:)`. Remove the asset catalog color sets for `AppPrimary` (or keep them for `AccentColor` only).

```swift
static let brand = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(hue: 0.40, saturation: 0.45, brightness: 0.85, alpha: 1) // lighter in dark mode
        : UIColor(hue: 0.40, saturation: 0.55, brightness: 0.72, alpha: 1)
})
```

**Pros**:
- Everything in one Swift file, no JSON editing
- Easy to tweak dark-mode variant

**Cons**:
- `AccentColor` in asset catalog still needs updating separately (system components use it)
- More complex than needed — the app already has a working asset catalog color system
- Mixing two systems for the same concept

**Complexity**: Medium
**Risk**: Low-Medium

---

## The `BurnView` Gradient Decision

The fire/burn motif uses `[.orange, .red]` gradients. This is ambiguous:
- **Option A**: Change to `[AppColors.brand, .red]` — makes it green→red, which looks like a traffic light "danger approaching" gradient. Odd for a calorie burn screen but not broken.
- **Option B**: Change to `[AppColors.brand, .orange]` — keeps the warm end, transitions from brand green → orange. Soft and avoids the harsh green+red contrast.
- **Option C**: Leave as-is — the fire/burn concept has its own semantic identity separate from brand color. Orange+red is "fire", not "brand color". This is the most defensible interpretation.

**Recommendation**: Option C — leave `BurnView` fire gradients as orange+red. They represent heat/fire, not brand identity.

---

## Edge Cases to Consider

- [ ] `AccentColor` in asset catalog has 3 entries: universal (fallback), light, dark. All three need updating. The dark-mode variant currently has `alpha: 0.500` — consider whether the new dark-mode green also needs reduced opacity or should be full opacity with adjusted brightness.
- [ ] `PrimaryContainer` light-mode is currently `#FFE6E6` (pinkish-orange wash). The new equivalent for green should feel analogous: a very light, low-saturation green. `#E8F5E0` or `Color(hue: 0.40, saturation: 0.12, brightness: 0.97)` would work.
- [ ] `OnPrimary` is pure white — this remains correct for both orange and the new green (white text on a mid-brightness green is readable).
- [ ] `StreakDetailView` uses orange for "today is logged" (filled circle) — this is brand-like (celebration color) and should change. But it also uses orange for "not yet logged today" — this is semantic (warning/urgency) and arguably should stay orange or go to `.yellow`.
- [ ] The `orange+pink` gradient in `ProfileView` mini rings represents calorie progress — this is strongly food/nutrition branded. Changing to `green+mint` would be coherent with the wellness/health theme.
- [ ] `MealLogCard` breakfast time slot color (`case 5..<11: return .orange`) — breakfast-orange is a universal convention (morning, sunrise). Recommend leaving as orange.
- [ ] Commented-out code in `QuickAddCard.swift` and `CalorieHeroCard.swift` contains `.orange` references. These are already commented out and should be cleaned up or left as-is — no runtime impact.
- [ ] Dark-mode behavior: the new green at full opacity on dark backgrounds needs testing. `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` is mid-brightness; it may need to be lightened slightly (higher brightness, lower saturation) for dark mode legibility.

---

## Open Questions

- [ ] Should the `BurnView` fire gradients (`[.orange, .red]`) change? See analysis above.
- [ ] What is the dark-mode variant for `AccentColor`? Currently it uses the same hex at 50% opacity. Should the new green use the same pattern or a different HSB value with full opacity?
- [ ] Does the `orange+pink` gradient in ProfileView mini-ring widgets change? These are widget previews — a user will see the widget on their home screen and it will look different from the app.
- [ ] Is `NarratorButton`'s orange glow (TTS speaking state indicator) considered brand or functional?
- [ ] Should `StreakDetailView` logged-day indicator remain orange (celebratory warmth) or shift to green (success/health)?

---

## Recommendation

Use **Approach 1** (Asset Catalog + `AppColors.brand` Swift constant).

**Exact execution plan**:

### Step 1 — Update color assets (3 JSON files)
- `AccentColor.colorset`: Set universal + light to `(R: 0.414, G: 0.720, B: 0.324, A: 1.0)`, dark to `(R: 0.50, G: 0.82, B: 0.40, A: 1.0)` (brighter for dark mode legibility)
- `AppPrimary.colorset`: Same as AccentColor entries
- `PrimaryContainer.colorset`: Light = `(R: 0.91, G: 0.97, B: 0.88, A: 1.0)`, Dark = `(R: 0.10, G: 0.23, B: 0.08, A: 1.0)`

### Step 2 — Add `brand` alias to `AppColor.swift`
```swift
static let brand = Color(hue: 0.40, saturation: 0.55, brightness: 0.72)
```
This gives a named constant any `.orange` hard-code can be replaced with, avoiding repetition of the HSB literal.

### Step 3 — Update brand `.orange` uses (~25 files)
Replace the hard-coded `.orange` / `Color.orange` references that are **brand uses** with `AppColors.brand` (or `.brand` where `AppColors` is in scope).

### Step 4 — Do NOT change semantic orange uses
Leave untouched: fair-quality color, carbs macro, fat macro, breakfast time slot, screen time warning scale, systolic BP accent, stress score scale, widget install status indicator.

### Step 5 — `BurnView` fire gradients
Leave `[.orange, .red]` fire gradients as orange+red. These represent combustion/heat, not brand.

### Step 6 — `MainTabView` `.tint(.orange)`
Change to `.tint(AppColors.brand)` — this is the most visible single change.

---

## Research References
- Apple HIG — Color: https://developer.apple.com/design/human-interface-guidelines/color
- SwiftUI `.tint` modifier propagation: applies to Tab bars, buttons, toggles, sliders, links, progress views when color is not explicitly overridden
- HSB to sRGB conversion: For H=0.40, S=0.55, B=0.72 → the sector is green-to-cyan (H between 1/3 and 1/2). Using standard HSB→RGB: R≈0.324, G≈0.720, B≈0.414 (note: G is max at B=0.72, R and B are B*(1-S) and B*(1-S*(1-f)) where f is fractional part of H*6-2)
