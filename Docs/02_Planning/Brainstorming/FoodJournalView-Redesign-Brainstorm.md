# FoodJournalView Redesign — Brainstorm
**Date**: 2026-03-13  
**Session Type**: UI/UX Design Exploration (Stitch)

---

## Context

The `FoodJournalView` is the primary food tracking screen in the WellPlate app, accessible when the user taps **"Log Meal"** from the home screen's Quick Log section. It wraps two main sub-components:

- **`CalorieHeroCard`** — shows aggregated nutrition for the selected day
- **`MealLogCard`** — lists individual food log entries for the selected day

### Current State (Before Redesign)

- The calorie progress bar in `CalorieHeroCard` is **commented out** — no calorie summary is shown to the user
- Macros (Protein, Carbs, Fat) are displayed as three equal columns with tiny 4px progress bars
- The `MealLogCard` uses a time + vertical accent bar layout with colorful macro pills
- Floating `+` button (bottom right) opens `MealLogSheetContent`
- Date navigation via horizontal swipe gesture
- Toolbar: "Today" date selector (center), streak flame + count (trailing), insights chart (trailing)

### Key Data Model (`FoodLogEntry`)

Each food log entry tracks: `foodName`, `calories`, `protein`, `carbs`, `fat`, `fiber`, `mealType`, `hungerLevel`, `presenceLevel`, `reflection`, `quantity`, `quantityUnit`, `createdAt`

---

## Design Principles Established This Session

1. **Minimal** — No visual clutter; every element earns its place
2. **Subtle** — Low-saturation colors, near-invisible shadows, restrained use of color
3. **UX-Friendly** — Clear hierarchy, easy scanning, generous whitespace
4. **Wellness journal tone** — Calm and encouraging, not a flashy fitness dashboard (think: Apple Health, Bear Notes, Things 3)

---

## Brand Color Reference

| Token | Hex | Usage |
|---|---|---|
| `AppColors.brand` (AppPrimary) | `#53B87B` | Calorie ring, FAB, badges, accent elements |
| `AppColors.primaryContainer` | `#E8F7E0` (light) | Soft green backgrounds |
| Protein | `#D94040` | Macro bar / pill |
| Carbs | `#4A90D9` | Macro bar / pill |
| Fat | `#E8943A` | Macro bar / pill |

---

## Design Exploration (3 Iterations via Stitch)

### V1 — Initial Generation

**Stitch Screen ID**: `8dcc0ed4731c4785a1e1841aaf97cd07`

Key ideas introduced:
- Circular calorie progress ring (1,450 / 2,100 kcal) replacing the missing progress bar
- Macro tracking as horizontal full-width bars
- Meal list grouped by meal type (Breakfast, Lunch, Snack) with colored icons and macro capsules
- Floating green `+` FAB

Issues noted:
- Brand green was too vivid (`#11d411` — neon, not earthy)
- Macro pill colors were too loud and distracting
- Overall felt more like a dashboard than a journal

---

### V2 — Brand & Polish Pass

**Stitch Screen ID**: `6f9e3ddc3e6a4a0ea3df5e34ece94f4c`

Changes applied:
- Corrected brand color to muted earthy green (`#53B87B`)
- Warm off-white/cream background (`#F5F5F0`)
- Added "Calories" label above the calorie ring
- "650 kcal remaining" as a soft green pill badge below ring
- Macro bars thicker (6px), clearer `78 / 120g` format
- Added 4th meal: **Dinner** → Salmon with Quinoa, 430 kcal
- Removed bottom tab bar (handled by SwiftUI `TabView` separately)
- "Today" nav title with dropdown chevron

---

### V3 — Minimal & Subtle Final Pass ✅

**Stitch Screen ID**: `aa77cf63d72845ec8cc9ff5ef217004f`

Changes applied:
- Thinner calorie ring stroke — more elegant, less chunky
- "CALORIES" → "Calories" (sentence case — less aggressive)
- Macro pill backgrounds reduced to ~8% opacity with desaturated text
- Meal row icons replaced with muted gray SF Symbol-style icons (not colorful circles)
- Font weights reduced to Regular/Medium throughout
- Calorie values on meal rows: secondary color, regular weight
- Card shadows near-invisible — hint of elevation only
- More vertical padding between meal rows

---

## Proposed SwiftUI Implementation Changes

When implementing this design, the following files will need updates:

### `CalorieHeroCard.swift`
- [ ] Add circular progress ring using `Circle().trim(...)` with the brand green
- [ ] Show large calorie number inside the ring
- [ ] Add "X kcal remaining" pill badge below ring
- [ ] Keep macro bars but make them full-width with clearer value+goal labels
- [ ] Reduce visual weight (lighter fonts, subtle separator)

### `MealLogCard.swift`
- [ ] Replace colorful meal-type icon circles with a small muted vertical accent bar (current approach is already close — keep and refine)
- [ ] Tone down macro pills: reduce opacity of colored capsule backgrounds, desaturate text
- [ ] Increase row padding for breathing room
- [ ] Calorie value on each row: use `.secondary` color, regular weight

### `FoodJournalView.swift`
- [ ] No structural changes needed — the view composition is solid
- [ ] Consider adding a gentle background gradient or slight warm tint instead of pure `systemGroupedBackground`

---

## Open Questions / Future Considerations

- **Calorie ring animation** — Should it animate on appear (fill from 0 to current) for delight?
- **Empty state for CalorieHeroCard** — What shows when no food is logged for the day? Currently falls back to zero values.
- **Color in meal rows** — Is the time-based color accent bar (orange/blue/purple/indigo by time of day) worth keeping for visual interest, or should it be removed for maximum minimalism?
- **Meal type grouping** — Currently `MealLogCard` sorts chronologically. Should items be grouped by `mealType` (Breakfast / Lunch / Snack / Dinner) in the new design?
- **Dark mode** — The redesign was specified in light mode. A dark mode variant should be validated before implementation.

---

## Stitch Project Reference

- **Project ID**: `6291214212332208590`
- **Project Title**: WellPlate FoodJournalView Redesign
- **Screens**:
  - V1: `8dcc0ed4731c4785a1e1841aaf97cd07`
  - V2: `6f9e3ddc3e6a4a0ea3df5e34ece94f4c`
  - V3 (final): `aa77cf63d72845ec8cc9ff5ef217004f`
