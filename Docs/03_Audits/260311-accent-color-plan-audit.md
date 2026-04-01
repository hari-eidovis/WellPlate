# Plan Audit Report: Accent Color Change — Orange to Brand Green

**Audit Date**: 2026-03-11
**Plan Version**: 260311-accent-color-change-plan.md
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is thorough and well-researched. The brand-vs-semantic classification of every `.orange` occurrence is largely correct, the asset catalog JSON is accurate, and the implementation order is sound. However, there are several confirmed line-number errors (plan references wrong line numbers in the summary table vs. the file-by-file tables), one sRGB math error that propagates into the colorset JSON, one missed brand-orange case not in any section, and a structural gap around the `GoalsView` flame icon decision that deserves explicit acknowledgment. None of these are blockers on their own, but together they create a meaningful risk of silent mistakes during implementation.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. sRGB Color Math Error in Colorset JSON and Swift Constant

- **Location**: Phase 1 Step 1.1/1.2 JSON, and Phase 2 Swift constant. Also in brainstorm line 266.
- **Problem**: The plan consistently states the new green sRGB values as R:0.414, G:0.720, B:0.324. This is internally inconsistent. For `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`:
  - Hue 0.40 lies in the green sector (hue range 1/3 to 2/3). The maximum channel at full brightness is green (G = B = 0.72).
  - Standard HSB→RGB for H=0.40 (which is 0.40 * 6 = 2.4, sector 2 — green to cyan):
    - f = 2.4 - 2 = 0.4 (fractional part of H*6 - sector_start)
    - X = B*(1-S*(1-f)) = 0.72*(1-0.55*0.6) = 0.72*0.67 = 0.4824
    - p = B*(1-S) = 0.72*0.45 = 0.324
    - In this sector: R=p=0.324, G=B=0.72, B=X≈0.482
  - The correct sRGB triple is approximately **R≈0.324, G≈0.720, B≈0.482** — the blue channel should be ~0.482, not 0.324 as stated everywhere in the plan and brainstorm. The red and blue channels are swapped in the plan's stated values.
  - The brainstorm compounds this at line 266 by reversing R and B in a note ("R ≈ 0.414, G ≈ 0.720, B ≈ 0.324") then listing still-different values in the recommendation (R:0.414, G:0.720, B:0.324).
  - The most reliable authoritative value: what does `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` actually render in SwiftUI? The implementer should verify by creating a Color swatch and reading its sRGB components in the Xcode color picker before writing any colorset JSON. **Do not copy the plan's sRGB literals blindly.**
- **Impact**: If the wrong sRGB values are written into the colorset JSONs, the asset-catalog-sourced colors (`AppColors.primary`, `AccentColor`) will differ visibly from the Swift-constant `AppColors.brand`. The tab bar (asset) would be a different shade of green from the FAB button (Swift constant). This is a split-brand failure.
- **Recommendation**: Before Phase 1, open Xcode's color picker, enter HSB (hue: 144°, sat: 55%, bri: 72%), and read the exact sRGB values from the picker. Use those values in all three colorset files. Then verify `AppColors.brand` renders identically to `Color("AppPrimary")` on a test swatch before shipping.

---

### HIGH (Should Fix Before Proceeding)

#### 2. Plan Summary Table Line Numbers Do Not Match File-by-File Tables

- **Location**: "Complete Change Summary" table at the bottom of Phase 3 vs. the individual file sections.
- **Problem**: The summary table for `StreakDetailView.swift` says "Lines 176, 306, 311, 349 changed; Line 190 → `.yellow`". The actual file-by-file section (3.7) lists line 190 in the changes table with instruction to change to `.yellow`. This is internally consistent but the summary table's column header says "Lines changed" and lists 190 separately under "Lines kept orange" — which is wrong: line 190 is not kept orange, it becomes yellow. This creates implementation confusion: the executor might think line 190 stays orange.
- **Impact**: Line 190 (`streakData.isActiveToday ? Color.green : Color.orange`) stays as-is if implementer trusts the summary table's "Lines kept orange" column. The `Color.orange` survives when it should become `Color.yellow`.
- **Recommendation**: Correct the summary table. In the `StreakDetailView` row, move line 190 out of "Lines kept orange" into a third column or add a note: "Line 190 → `.yellow` (not kept as orange, not changed to brand)".

#### 3. `GoalsView` Line 82 — Icon Semantics Decision Not Justified

- **Location**: Section 3.9, line 82.
- **Problem**: The plan changes `GoalCard(icon: "flame.fill", iconColor: .orange, title: "Nutrition")` to `iconColor: AppColors.brand`. The icon is `flame.fill` inside a card titled "Nutrition". A flame icon in a nutrition context can reasonably be interpreted as a calorie symbol (semantic — "energy = heat = flame") rather than a brand signal. The brainstorm identifies flame icons elsewhere as brand, but the Nutrition card's flame is specifically tied to food energy. The plan gives no reasoning for this decision; it simply lists it as a "brand use."
- **Impact**: Low visual risk, but the decision could be challenged during review. More importantly: this is the same flame icon used in `BurnView`'s fire gradient (which is explicitly kept orange). The inconsistency — flame is brand in GoalsView but semantic in BurnView — is not addressed.
- **Recommendation**: Add an explicit justification in the plan: "This flame represents the Goals section header, not a calorie-burn data visualization; it is therefore brand." Or keep it orange as a data-convention icon. Either is defensible, but the decision must be stated.

#### 4. `ProfileView` Line 311 — Listed in Brainstorm but Missing from Plan's File Section

- **Location**: Brainstorm inventory lists `ProfileView.swift:71,140,201,256,311,339,...` — note line 311 is in the brainstorm's list. The plan's section 3.12 does not include line 311 anywhere (neither in the CHANGE nor the KEEP tables).
- **Problem**: Verified in the actual source: line 311 in ProfileView.swift is inside the `case .medium:` branch and sets up the MediumPreview frame — there is no `.orange` on line 311 of the current file. The brainstorm line number was likely stale from an earlier file state, and the plan correctly omitted it. However the brainstorm list creates a false expectation. This is a documentation gap, not a code gap.
- **Impact**: Low code risk (the plan's table is correct for the current file), but an implementer who cross-references the brainstorm will search for an orange reference at line 311 and find none, then wonder if they missed something.
- **Recommendation**: Add a note in section 3.12: "Brainstorm listed line 311 — this is no longer present in the current file; confirmed resolved."

#### 5. `AppColor.swift` — `brand` Constant Not Dark-Mode Adaptive

- **Location**: Phase 2, Step 2.1.
- **Problem**: The plan adds `static let brand = Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` as a plain HSB constant. This is a single value with no light/dark mode variant. All the asset catalog colors (`AccentColor`, `AppPrimary`) are being given proper light/dark variants (light at H:0.40, S:0.55, B:0.72 and dark at R:0.50, G:0.82, B:0.40). But any call site that uses `AppColors.brand` (instead of `.accentColor` or `AppColors.primary`) will always render the same green regardless of color scheme, while the asset-backed colors adapt.

  The call sites being changed include shadows, gradients, foreground colors — all using `AppColors.brand`. In dark mode, this mid-brightness green (B=0.72) may appear muddy against dark backgrounds, while the asset-backed colors will correctly use the brighter dark-mode variant (B=0.82).
- **Impact**: Visual inconsistency in dark mode: FAB button shadow (uses `AppColors.brand.opacity(0.35)`) will be dimmer/different from the tab bar tint (uses `AccentColor` from asset). Calendar button gradient (uses `AppColors.brand`) will differ from `AppColors.primary`.
- **Recommendation**: Use Approach 4 style for the `brand` constant — make it adaptive via `UIColor(dynamicProvider:)`:
  ```swift
  static let brand = Color(UIColor { trait in
      trait.userInterfaceStyle == .dark
          ? UIColor(red: 0.500, green: 0.820, blue: 0.400, alpha: 1) // dark variant
          : UIColor(red: 0.324, green: 0.720, blue: 0.482, alpha: 1) // light variant (corrected)
  })
  ```
  Alternatively, add a new named color asset `Brand.colorset` that mirrors `AccentColor`, and reference it as `Color("Brand")`. This keeps everything in the asset catalog system.

---

### MEDIUM (Fix During Implementation)

#### 6. `WellnessCalendarView` Line 401 — Fat Macro Color Changed from Orange to Yellow (Unmarked)

- **Location**: Not in the plan at all.
- **Problem**: In the actual `WellnessCalendarView.swift`, the macro chip row at line 401 has `color: .yellow` for fat (not `.orange`). This is already yellow in the source — so this was apparently changed at some prior point. More importantly, line 398 shows `color: .orange` for "Cal" (the plan correctly flags this for change to `AppColors.brand`). But the plan's table for section 3.13 describes only lines 398 and 422 — which matches the actual file. No issue with the plan's table, but worth noting the fat macro is `.yellow` here (different convention from `MealLogCard` and `ProfileView` which use `.orange` for fat). This inconsistency in the codebase itself is pre-existing and out of scope, but the implementer should be aware.
- **Recommendation**: Note this for the implementer: fat in `WellnessCalendarView` is already `.yellow`; do not "fix" it to orange while making the color change.

#### 7. `ExpandableFAB` — Plan Line Numbers Verified Correct, but Rationale Gap

- **Location**: Section 3.2.
- **Problem**: The ExpandableFAB's orange uses are at lines 69 and 75, confirmed in the actual file. However, the sub-action items in the FAB (mic=pink, camera=blue, note=green at lines 18-21) already use non-orange colors. The FAB's main button being orange was intentional and the plan correctly changes it. No code issue, but the plan does not note that sub-action items are already correctly colored — an implementer might scan the file and worry they need to change those colors too.
- **Recommendation**: Add a note: "Lines 18–21 (sub-action item colors: .pink, .blue, .green) are already non-orange; leave untouched."

#### 8. `HomeView` — Exercise Ring Hardcoded Green Color Could Conflict

- **Location**: Not in the plan — not strictly an orange change issue, but a side-effect risk.
- **Problem**: In `HomeView.swift`, the Exercise ring at line 277 uses `Color(hue: 0.40, saturation: 0.62, brightness: 0.70)`. After this change, the Calories ring will also become green (`AppColors.brand` ≈ `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)`). Two rings will be similar shades of green — Calories ring (HSB 0.40/0.55/0.72) and Exercise ring (HSB 0.40/0.62/0.70). This is a visual legibility concern: the `WellnessRingsCard` depends on ring colors being distinct for the user to differentiate at a glance.
- **Impact**: The four rings would show green (calories), blue (water), green-ish (exercise), purple (stress). The two green rings will be hard to distinguish.
- **Recommendation**: After Phase 3, step back and view the `WellnessRingsCard` in the Simulator. Consider changing the Exercise ring color to a teal (`Color(hue: 0.50, saturation: 0.65, brightness: 0.72)`) or blue-green to differentiate it from the brand-green Calories ring. This is not strictly part of the orange-to-green plan but will become necessary once the change is visible.

#### 9. Asset Catalog — `AppPrimary.colorset` State Description Inaccuracy in Plan

- **Location**: Phase 1, Step 1.2.
- **Problem**: The plan describes `AppPrimary.colorset` current state as: "Universal entry uses decimal (red: 1.000, green: 0.416, blue: 0.000); light and dark use hex notation." This is confirmed correct by the actual JSON. However, the plan says "Dark has a slightly adjusted orange" — the actual dark value is `0xFF, 0x7A, 0x20` = a more saturated/warm orange-yellow (not just "slightly adjusted"). This is a minor description inaccuracy that does not affect the JSON replacement but could mislead an implementer checking the file manually.
- **Recommendation**: Minor. Correct to: "Dark entry uses a warmer/shifted orange (0xFF 0x7A 0x20 ≈ `#FF7A20`)."

#### 10. `PrimaryContainer.colorset` — Plan Describes Wrong Current Light-Mode Color

- **Location**: Phase 1, Step 1.3.
- **Problem**: The plan states: "Current state: Light/universal = `#FFE6F0` (pinkish-orange wash)." The actual file has `0xFF, 0xF0, 0xE6` which decodes to `#FFF0E6` — a very light peach/cream, not pinkish. The brainstorm line 212 says "currently `#FFE6E6`" which is also wrong. The real value `#FFF0E6` is a warm cream/peach — still orange-tinted, so the semantic intent ("it needs to change to green") is correct, but the described hex is wrong.
- **Impact**: An implementer who manually verifies the current state before editing will see `0xFF, 0xF0, 0xE6` (not `#FFE6F0`) and may doubt whether they have the right file. Low risk if they just overwrite the whole JSON.
- **Recommendation**: Correct to "`#FFF0E6` (warm peach/cream wash)".

---

### LOW (Consider for Future)

#### 11. No Widget Target Coverage

- **Location**: Phase 3 overview, ProfileView section.
- **Problem**: The plan acknowledges that `ProfileView` shows widget previews and correctly changes those preview colors. However, it does not address whether there is a separate Widget extension target that also hard-codes orange. The git status shows no widget target files, but if a WellPlateWidget target exists, it would have its own Swift files with their own `.orange` references that the plan would miss entirely.
- **Recommendation**: Confirm there is no separate widget target (`WellPlateWidgetExtension` or similar). If one exists, run the same orange grep against its source directory before closing this plan.

#### 12. No Rollback Strategy

- **Location**: Plan has no rollback section.
- **Problem**: For a purely cosmetic change touching 25 files plus 3 JSON files, the natural rollback is git. But the plan does not mention this. If the implementer works across multiple sessions, partial rollback becomes complex.
- **Recommendation**: Add: "Rollback strategy: `git stash` or `git checkout` — this change touches only color values; no logic changes require migration."

#### 13. `AccentColor.colorset` Has a `localizable` Property — Plan Preserves It

- **Location**: Phase 1, Step 1.1 — the new JSON.
- **Problem**: The plan's proposed JSON for `AccentColor.colorset` includes `"properties": { "localizable": true }` — this is correct and matches the current file. The `AppPrimary.colorset` and `PrimaryContainer.colorset` do not have this property (also matching current state). The plan correctly differentiates them. This is informational — no issue.
- **Recommendation**: No action required.

#### 14. `DragToLogOverlay.swift` — Implicit Coverage Gap

- **Location**: Not mentioned in the plan.
- **Problem**: The plan notes in Steps 1.2 and 1.3 that `AppColors.primary` (and `AppColors.primaryContainer`) are used in `DragToLogOverlay`. Since those asset colors are being changed in Phase 1, the overlay will automatically become green via the asset change — no Swift edits needed. This is architecturally correct. But the plan never explicitly lists `DragToLogOverlay.swift` as a file that will change its appearance, which could confuse a reviewer doing a visual regression test who notices the overlay turned green and can't find it in the plan.
- **Recommendation**: Add `DragToLogOverlay.swift` to the testing checklist: "DragToLogOverlay border/tint = green (indirectly via AppColors.primary asset change)".

---

## Missing Elements

- [ ] Verification step to confirm `AppColors.brand` (Swift constant) renders identically to `Color("AppPrimary")` (asset) in both light and dark mode
- [ ] Widget extension target audit (confirm no separate target with its own orange hardcodes)
- [ ] Visual regression note for `WellnessRingsCard` ring distinctness after Calories ring becomes green
- [ ] `DragToLogOverlay` listed in the visual testing checklist (changes via asset, not Swift edits)
- [ ] Rollback strategy (even just "use git")

## Unverified Assumptions

- [ ] `AppColors.brand` (single HSB value) renders as the same green as `Color("AccentColor")` in dark mode — Risk: **High** (it does not — the asset has a different dark variant, the Swift constant does not adapt)
- [ ] sRGB R:0.414, G:0.720, B:0.324 matches `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` — Risk: **High** (math indicates B channel should be ~0.482, not 0.324)
- [ ] No widget extension target exists with its own orange references — Risk: **Medium** (not verified by plan)
- [ ] Exercise ring HSB `(0.40, 0.62, 0.70)` will be visually distinct from brand green `(0.40, 0.55, 0.72)` at ring size — Risk: **Medium** (same hue, very similar brightness/saturation)
- [ ] `ProfileView` line 311 was in the brainstorm but is absent from current file — Risk: **Low** (confirmed absent from current source)

## Security Considerations

- None applicable — purely cosmetic color change.

## Performance Considerations

- None applicable — no logic changes, no new computations. Asset catalog color lookups are cached by the system.

## Questions for Clarification

1. **Color math**: What sRGB values does `Color(hue: 0.40, saturation: 0.55, brightness: 0.72)` actually produce in Xcode's color picker? The plan's stated values (R:0.414, G:0.720, B:0.324) appear to have the R and B channels from two different calculations mixed together. Verify before writing JSON.
2. **Dark mode adaptive brand**: Should `AppColors.brand` be a single value or adaptive? If adaptive, is `UIColor(dynamicProvider:)` preferred or should a new `Brand.colorset` asset be created?
3. **Exercise ring color**: After the change, the Calories ring (brand green) and Exercise ring (HSB 0.40/0.62/0.70) will be similar shades. Is this intentional, or should Exercise ring shift hue to differentiate?
4. **Widget target**: Is there a separate WellPlateWidget extension target with its own source files? If so, it is not covered by this plan.
5. **GoalsView flame icon**: Explicitly confirm that `flame.fill` in the Nutrition GoalCard header is intended as brand (not calorie-semantic), since the same flame is used in BurnView's fire gradient which is explicitly kept orange.

## Recommendations

1. **Fix sRGB values first**: Derive the correct sRGB triple from the Xcode color picker before writing any JSON. Do not use the values stated in the plan without verification.
2. **Make `AppColors.brand` adaptive**: Use `UIColor(dynamicProvider:)` to give it the same light/dark behavior as the asset-backed colors. This is the single most impactful architectural improvement to the plan.
3. **Fix the summary table**: Line 190 in `StreakDetailView` is listed under "Lines kept orange" but should be "changed to `.yellow`". This will cause a missed edit if the implementer uses the summary table as their checklist.
4. **Add `DragToLogOverlay` to visual test checklist**: It changes appearance via the asset update even though no Swift edit is required.
5. **Check ring visual distinctness**: After Phase 3, view `WellnessRingsCard` in Simulator before declaring done. The Calories and Exercise rings may need hue differentiation.

## Sign-off Checklist

- [ ] sRGB values verified against Xcode color picker (not plan text)
- [ ] `AppColors.brand` made dark-mode adaptive
- [ ] Summary table corrected for `StreakDetailView` line 190
- [ ] All CRITICAL issues resolved
- [ ] All HIGH issues resolved or accepted
- [ ] Security review completed (N/A)
- [ ] Performance implications understood (N/A)
- [ ] Rollback strategy defined (git)
- [ ] Widget extension target confirmed absent or separately audited
- [ ] Visual regression: ring distinctness confirmed after implementation
