# Plan Audit Report: Coffee Tracking

**Audit Date:** 2026-03-22
**Plan:** `Docs/02_Planning/Specs/260322-coffee-tracking.md`
**Auditor:** plan-auditor agent
**Verdict:** NEEDS REVISION

---

## Executive Summary

The plan is structurally sound and well-aligned with existing app patterns. However two critical issues require resolution before implementation: a SwiftUI race condition that will silently drop the water alert after sheet dismissal, and an unaddressed persistence gap for individual cup-icon decrements in CoffeeCard. Several high/medium issues also need design decisions locked in before coding begins.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

---

#### 1. Water Alert Silently Dropped After Sheet Dismissal

- **Location:** Step 7d/7g — `CoffeeTypePickerSheet` closure + `commitCoffeeAdd`
- **Problem:** The plan sets `showCoffeeTypePicker = false` and immediately sets `showCoffeeWaterAlert = true` within the same closure call:
  ```swift
  CoffeeTypePickerSheet { type in
      showCoffeeTypePicker = false   // triggers sheet dismiss animation
      pendingCoffeeType = type
      commitCoffeeAdd(type: type)    // immediately sets showCoffeeWaterAlert = true
  }
  ```
  On iOS, you cannot reliably present an alert while a sheet is still animating out. SwiftUI will silently suppress the alert if the presenting sheet hasn't finished dismissing. This is a well-known iOS UIKit/SwiftUI interaction bug.
- **Impact:** Users who select a coffee type never see the water nudge alert — the entire dehydration-reminder feature is broken on the most important path (first cup of the day).
- **Recommendation:** Trigger the water alert from `onChange(of: showCoffeeTypePicker)` after the sheet has fully closed, not inside the sheet closure:
  ```swift
  .onChange(of: showCoffeeTypePicker) { _, isShowing in
      if !isShowing, let type = pendingCoffeeType {
          commitCoffeeAdd(type: type)
          // commitCoffeeAdd sets showCoffeeWaterAlert = true — now safe because sheet is gone
      }
  }
  ```
  `pendingCoffeeType` (currently dead state in the plan) becomes useful here as the handoff variable between sheet dismissal and alert presentation.

---

#### 2. Individual Cup Icon Decrements Will Not Persist

- **Location:** Step 4 (CoffeeCard), Step 7 (HomeView) — persistence architecture gap
- **Problem:** For water, `HydrationCard` mutates `glassesConsumed` binding directly for ALL interactions (+ button and individual glass icon toggles). `HomeView` listens with `onChange(of: hydrationGlasses)` and persists every change. The plan breaks this symmetry for coffee:
  - The `+` button calls `onAdd()` callback → `commitCoffeeAdd()` → saves explicitly
  - Individual cup icon taps are specified to follow the same HydrationCard pattern (direct binding mutation)
  - But the plan does **not** add `onChange(of: coffeeCups)` for persistence
  - Result: tapping a filled cup icon to decrement will update the UI but never write to SwiftData
- **Impact:** Coffee counts silently diverge from the stored log. After backgrounding the app, the count resets to the stale SwiftData value on `refreshTodayCoffeeState()`.
- **Recommendation (choose one):**
  - **Option A (simpler, consistent with water):** Have CoffeeCard also mutate `cupsConsumed` binding directly for the `+` button (no `onAdd` callback). HomeView intercepts via `onChange(of: coffeeCups)`. For first-cup detection in `onChange`: check `cups == 1 && todayWellnessLog?.coffeeType == nil` and show the type picker there. This matches the water pattern exactly.
  - **Option B (keep callbacks):** Add `onRemove: (() -> Void)?` callback parallel to `onAdd`. All cup icon taps route through callbacks, never directly mutate the binding. HomeView persists in each callback. Remove the direct binding mutation pattern entirely from CoffeeCard.

  Option A is recommended for consistency with the existing codebase.

---

### HIGH (Should Fix Before Proceeding)

---

#### 3. First-Cup Type Picker Bypassed via Card Body Tap

- **Location:** Step 6 — CoffeeDetailView spec; Step 7b — `onTap: { showCoffeeDetail = true }`
- **Problem:** A user who taps the card body (not the `+` button) is navigated to `CoffeeDetailView`. The detail view has no type picker. If they log their first cup from the detail view, `coffeeType` stays `nil` all day. This also means the subtitle in the card will show "80 mg caffeine" (fallback) rather than their actual coffee's caffeine content.
- **Impact:** Type picker is only accessible from one of the two entry points. The feature delivers a degraded experience for a likely user path.
- **Recommendation:** Either (a) show the type picker sheet from within `CoffeeDetailView` when `coffeeCups == 0 && coffeeType == nil` and the user taps `+`, or (b) show the type picker *before* navigating to the detail view when `coffeeCups == 0` (same way WaterDetailView is shown directly without a pre-check).

---

#### 4. `logOneWater()` Hardcodes Cap at 8

- **Location:** Step 8 — `CoffeeDetailView` water alert
- **Problem:** The plan states "`logOneWater()` ... increments `waterGlasses` by 1 (capped at 8)". `CoffeeDetailView` takes no `UserGoals` reference, so it can't know the actual goal.
- **Impact:** Users who've set a custom water goal (e.g., 10 cups) will have their water log capped at 8 cups from this path, silently ignoring their goal.
- **Recommendation:** `CoffeeDetailView` should accept a `waterGoal: Int` parameter (defaulting to 8), or fetch `UserGoals` via `@Query` (same pattern HomeView uses). The simpler fix is to add `@Query private var userGoalsList: [UserGoals]` to `CoffeeDetailView` and use `.first?.waterDailyCups ?? 8`.

---

### MEDIUM (Fix During Implementation)

---

#### 5. `pendingCoffeeType` Is Dead State (Without Fix #1 Applied)

- **Location:** Step 7a — state vars
- **Problem:** `pendingCoffeeType` is declared, set in the sheet closure, but never read anywhere in the plan. It serves no purpose in the current design.
- **Recommendation:** This becomes useful only if the fix for Issue #1 is applied (using `onChange(of: showCoffeeTypePicker)` as the handoff mechanism). If the sheet-dismiss race is fixed as recommended, `pendingCoffeeType` becomes the correct bridge. Document this intent explicitly so the implementer doesn't remove it as dead code.

---

#### 6. CoffeeDetailView Missing Toolbar +/- Buttons in Spec

- **Location:** Step 6 — comparison table between `WaterDetailView` and `CoffeeDetailView`
- **Problem:** `WaterDetailView` has `+` and `-` toolbar buttons in the top-right for quick adjustment. The comparison table in the plan omits this row entirely. An implementer cloning the view structure may or may not include them.
- **Recommendation:** Add a toolbar row to the comparison table specifying ToolbarItem with `+` (calls `addCup()`) and `-` (calls `removeCup()`) buttons. This is also where the water alert should fire for the toolbar `+` path.

---

#### 7. CoffeeCard Removes Only Type on Today's Log — Not Downgrading Type on Decrement

- **Location:** Step 7h — `updateCoffeeForToday(cups:type:)`
- **Problem:** If user decrements to 0 cups, `coffeeType` in `WellnessDayLog` is not cleared. On next `+` tap, `coffeeCups == 0` but `coffeeType != nil`, so the type picker won't show (condition: `coffeeCups == 0 && todayWellnessLog?.coffeeType == nil`). User is stuck with yesterday's type if they undo and redo the first cup.
  - Wait: each day has a fresh `WellnessDayLog`, so this only applies within the same day. If a user taps `+` (adds first cup, picks Latte), then decrements back to 0 cups, then taps `+` again — the picker won't show because `coffeeType` is still "Latte" from earlier. This is actually reasonable product behaviour (remember the type once chosen per day). **But it should be explicitly documented as a product decision**, not left implicit.
- **Recommendation:** Add a note to the spec: "Once a coffee type is selected for the day, it is retained even if all cups are removed. The picker does not re-appear unless tomorrow's log is fresh."

---

#### 8. One Coffee Type Per Day Is a Silent Product Limitation

- **Location:** Architecture — `WellnessDayLog.coffeeType: String?` (single value per day)
- **Problem:** The data model stores one `coffeeType` for the entire day. A user who drinks a Latte in the morning and an Espresso in the evening can only track one type. Caffeine calculations will be incorrect for the second drink.
- **Impact:** While acceptable for an MVP, this should be a documented, conscious decision — not an oversight. If the product requirement is to track mixed drink types accurately in the future, the model needs to change to a separate `CoffeeLogEntry` model instead of a field on `WellnessDayLog`.
- **Recommendation:** Add a note to the plan stating this is a known V1 limitation and that a `CoffeeLogEntry` model would be the path to multi-type-per-day tracking.

---

### LOW (Consider for Future)

---

#### 9. Coffee Tip Copy Conflicts With Caffeine Data

- **Location:** Step 6 — coffee tips array
- **Problem:** The tip "Espresso has less caffeine than drip coffee" is technically accurate (63 mg vs 95 mg per serving). However, the `caffeineMg` values in `CoffeeType` show `flatWhite = 130 mg` and `coldBrew = 200 mg`. A user who just logged a Cold Brew sees the tip claiming drip coffee has more caffeine, which contradicts their own data display.
- **Recommendation:** Replace with a non-comparative tip: e.g., "A single espresso shot has about 63 mg of caffeine."

---

#### 10. No Decrement Smoke Test

- **Location:** Testing Strategy
- **Problem:** The manual smoke test list covers the addition path thoroughly but has no test for decrement: tapping a filled cup icon to remove it, or the toolbar `-` button in detail view.
- **Recommendation:** Add: `[ ] Tapping a filled cup icon decrements count and persists after backgrounding app`

---

#### 11. `.medium` Sheet Detent May Be Tight on Small Screens

- **Location:** Step 5 — `CoffeeTypePickerSheet`
- **Problem:** 8 items in a 3-column grid = 3 rows of cells. At `.medium` detent (~50% screen height on iPhone SE 3rd gen = ~330 pt), with the navigation title, two text labels, and 3 grid rows at ~90 pt each, the content may clip or require scrolling without a `ScrollView` wrapper in the sheet.
- **Recommendation:** Wrap the `LazyVGrid` in a `ScrollView` inside the sheet, or test on a 4.7" screen.

---

## Missing Elements

- [ ] Explicit decision on whether individual cup icon taps in CoffeeCard use binding mutation or callbacks (currently unspecified — see Issue #2)
- [ ] `CoffeeDetailView` toolbar +/- buttons (see Issue #6)
- [ ] `waterDailyCups` passed to or fetched in `CoffeeDetailView` for `logOneWater()` cap (see Issue #4)
- [ ] Product decision documented: one coffee type per day (see Issue #8)
- [ ] Type picker trigger from within `CoffeeDetailView` on first cup (see Issue #3)

---

## Unverified Assumptions

- [ ] SwiftData lightweight migration handles new columns on `WellnessDayLog` and `UserGoals` without data loss on existing installs — **Risk: Medium.** The claim is correct per Apple docs, but SwiftData's migration behavior on iOS 17/18 has had known bugs. The plan should add: "Verify with Simulator that has existing WellnessDayLog data before shipping."
- [ ] `cup.and.saucer` (unfilled variant) exists as an SF Symbol — **Risk: Low.** `cup.and.saucer.fill` is available from iOS 14. The un-filled variant `cup.and.saucer` should also exist, but the plan doesn't verify this for the empty cup icon state.
- [ ] `takeoutbag.and.cup.and.straw.fill` available on iOS 26.1 — **Risk: Low.** Available since iOS 16; app targets iOS 26.1, so this is safe.

---

## Performance Considerations

- [ ] `@Query private var allWellnessDayLogs` is already fetching all logs in HomeView. Adding `coffeeCups` to the model does not add an extra fetch. No performance concern.
- [ ] `CoffeeDetailView` fetching `UserGoals` via `@Query` (if added per Issue #4 fix) adds a trivial second query. Acceptable.

---

## Questions for Clarification

1. **Product decision:** Should the type picker appear every time the user logs their first cup of a new day, or only the very first time they ever use coffee tracking? (Current plan: every new day — this is the correct interpretation, just confirming.)
2. **Decrement + water alert:** If a user decrements a cup (removes it), should a water alert fire? (Current plan implies no — alert only fires on additions. Confirm this is intended.)
3. **CoffeeCard individual icon behavior:** Should tapping a filled coffee cup icon decrement (like HydrationCard), or should taps on individual icons be disabled in CoffeeCard to simplify the first-cup flow?
4. **Coffee in Wellness Rings:** Should a coffee ring be added to `WellnessRingsCard`, or is the coffee card standalone and not represented in the rings? The plan adds no ring, which is correct for MVP — but confirm.

---

## Recommendations

1. **Fix Issue #1 first** — the alert-after-sheet race is invisible in unit tests and easy to miss in development (simulators are faster; real devices show the bug). It should be designed out, not worked around.
2. **Decide on binding vs callbacks for CoffeeCard** before writing any code — this is an architectural fork that touches both the card component and HomeView, and changing it mid-implementation is disruptive.
3. **Consider making the type picker flow optional at the CoffeeDetailView level** (Issue #3) — the simplest fix is to trigger the type picker from the detail view's `addCup()` when `coffeeType == nil`, which handles both entry paths uniformly.
4. **Add `onChange(of: coffeeCups)` following the water pattern** (Option A for Issue #2) — it is the most consistent approach with the existing codebase and removes the need for `onAdd` callback complexity.

---

## Sign-off Checklist

- [ ] Issue #1 (alert-after-sheet race) resolved
- [ ] Issue #2 (decrement persistence gap) resolved with explicit architectural decision
- [ ] Issue #3 (type picker bypass via card tap) addressed
- [ ] Issue #4 (`logOneWater` hardcoded cap) fixed
- [ ] Issue #6 (toolbar buttons) added to spec
- [ ] One-type-per-day product limitation documented
- [ ] Security review: N/A (local SwiftData only, no network, no PII beyond cup count)
- [ ] Performance implications: acceptable (no new queries, no unbounded operations)
- [ ] Rollback: SwiftData schema changes are additive; rollback would require a manual migration or app delete — acceptable for local wellness data
