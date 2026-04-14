# Plan Audit Report: Home Screen Content Customisation

**Audit Date**: 2026-04-14
**Plan Version**: `Docs/02_Planning/Specs/260414-home-customisation-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured with clear phases, correct architectural direction, and good edge case coverage. However, there are **1 critical issue** (silent data loss from `currentGoals` fallback) and **3 high-priority issues** (working tree drift, duplicate hide mechanism, and edit mode side-effects) that must be addressed before implementation. The data model and core architecture are sound.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. `currentGoals` Fallback Creates Transient Object — Writes Silently Lost

- **Location**: Step 7a (`layoutBinding`), Step 7e (`hideCard`, `undoHide`), Step 11d (ProfileView binding)
- **Problem**: `currentGoals` is defined as:
  ```swift
  private var currentGoals: UserGoals {
      userGoalsList.first ?? UserGoals.defaults()
  }
  ```
  `UserGoals.defaults()` creates a NEW instance **not inserted into the ModelContext**. When `userGoalsList` is empty (fresh install before onboarding completes, or SwiftData fetch failure), any write to `currentGoals.homeLayout = newValue` followed by `try? modelContext.save()` will silently succeed but **persist nothing** — the object isn't tracked by SwiftData.

  The existing codebase only **reads** from `currentGoals` (calorie goal, water cups, etc.) — the plan introduces **writes**, which is a new pattern that exposes this bug.

  The same issue exists in Step 11d's ProfileView binding:
  ```swift
  let goals = userGoalsList.first ?? UserGoals.defaults()
  goals.homeLayout = newValue  // lost if defaults()
  ```

- **Impact**: On fresh installs or edge cases where UserGoals hasn't been created yet, layout customisation silently fails. User hides a card, restarts app, card is back. No error shown.

- **Recommendation**: Replace all write paths with `UserGoals.current(in: modelContext)` (which fetches OR creates+inserts — see `UserGoals.swift` line 128-139). In HomeView, add a helper:
  ```swift
  private var writableGoals: UserGoals {
      UserGoals.current(in: modelContext)
  }
  ```
  Use `writableGoals` in `layoutBinding.set`, `hideCard()`, and `undoHide()`. Keep `currentGoals` for reads (it's fine for reads since `.defaults()` returns sensible values).

  In ProfileView's binding, also use `UserGoals.current(in: modelContext)` instead of `userGoalsList.first ?? UserGoals.defaults()`.

---

### HIGH (Should Fix Before Proceeding)

#### H1. Working Tree Has `@AppStorage("hideInsightCard")` — Duplicate Hide Mechanism

- **Location**: Step 7c (`cardView(for: .dailyInsight)`)
- **Problem**: The current working tree (uncommitted changes) has:
  - Line 59: `@AppStorage("hideInsightCard") private var hideInsightCard = false`
  - Line 90: `if !hideInsightCard { DailyInsightCard(..., onDismiss: { hideInsightCard = true }) }`

  The plan introduces `HomeLayoutConfig.hiddenCards` as the new hide mechanism but never mentions removing or migrating `@AppStorage("hideInsightCard")`. If both mechanisms coexist:
  - User can hide DailyInsightCard via `onDismiss` button (sets AppStorage) AND via context menu (sets HomeLayoutConfig)
  - To show it again, user goes to Profile HomeLayoutEditor — but the card is ALSO hidden by AppStorage, so it stays hidden even after un-hiding in the layout editor

- **Impact**: Contradictory state — two independent sources of truth for the same card's visibility.

- **Recommendation**: Remove `@AppStorage("hideInsightCard")` and the `onDismiss` parameter from DailyInsightCard in the HomeView call site. Replace with the unified HomeLayoutConfig mechanism. The `DailyInsightCard.onDismiss` property can remain on the view (it's optional), but HomeView should use the context menu "Hide Card" action instead of a dedicated dismiss button. If a per-card inline dismiss button is desired, wire `onDismiss` to call `hideCard(.dailyInsight)`.

#### H2. Plan Based on Committed Version — Working Tree Card Order Differs

- **Location**: Step 7b, Step 7c (`cardView(for:)` dispatch)
- **Problem**: The plan's card ordering is based on the **committed** HomeView. The **working tree** (git status shows HomeView.swift modified) has a different order:
  
  | Position | Plan assumes | Working tree actual |
  |----------|-------------|-------------------|
  | After header | WellnessRingsCard | DailyInsightCard (1b) |
  | Then | StressSparklineStrip | WellnessRingsCard |
  | Then | MoodCheckIn/Journal | StressSparklineStrip |
  | Then | QuickStatsRow | MoodCheckIn/Journal |
  | Then | DailyInsightCard | QuickStatsRow |

  The `HomeCardID.allCases` default order must match the working tree's actual card order, otherwise the "default layout" will differ from what users see today.

- **Impact**: If implemented as-is, the default card order won't match the current layout. Existing users would see a reordered home screen after the update.

- **Recommendation**: Update `HomeCardID.allCases` order to match the working tree:
  ```swift
  enum HomeCardID: String, Codable, CaseIterable, ... {
      case dailyInsight       // 1b — after header
      case wellnessRings      // 2
      case stressSparkline    // 2b
      case moodCheckIn        // 3a
      case journalReflection  // 3b
      case quickStats         // 4
  }
  ```
  This requires changing the enum case declaration order (since `CaseIterable` uses declaration order).

#### H3. HomeLayoutEditor `.editMode(.active)` Shows Delete Buttons

- **Location**: Step 10 (HomeLayoutEditor)
- **Problem**: `.environment(\.editMode, .constant(.active))` enables both drag handles AND delete buttons (red minus circles) on every row. The plan uses `.onMove` but does NOT have `.onDelete`. In SwiftUI, when `editMode` is `.active` and `onMove` is present, iOS shows drag handles — but if `.onDelete` is NOT present, no delete buttons appear. However, the Hidden Cards section does NOT have `.onMove`, so the constant `.active` editMode may show unexpected UI there.
  
  Additionally, constant `.active` editMode prevents the user from tapping the eye toggle button easily — in edit mode, row tap targets shift to accommodate the reorder handle, which can make the eye button hard to tap.

- **Impact**: UI glitch — either unwanted delete buttons or awkward tap targets in the hidden cards section.

- **Recommendation**: Instead of global `.environment(\.editMode, .constant(.active))`, use `EditButton()` in the toolbar and let the user toggle edit mode for reordering. Or scope the `.editMode` to only the visible cards section. Alternatively, just add `.deleteDisabled(true)` to both sections if using constant active mode.

---

### MEDIUM (Fix During Implementation)

#### M1. Conditional Cards (Mood/Journal) in ForEach May Cause Issues

- **Location**: Step 7c (`cardView(for: .moodCheckIn)` and `cardView(for: .journalReflection)`)
- **Problem**: The `moodCheckIn` and `journalReflection` cases use `@ViewBuilder` conditional logic:
  ```swift
  case .moodCheckIn:
      if !hasLoggedMoodToday {
          MoodCheckInCard(...)
      }
  ```
  When the condition is false, `@ViewBuilder` produces no content. The `ForEach` still includes this card ID in its identity list, but the rendered view is empty. The `.homeCardMenu()` modifier and `.transition()` are applied to this empty result.

  **Concern 1**: The context menu wraps an empty view — user can't trigger it, but it's semantically odd.
  **Concern 2**: The `.transition` on the ForEach item won't animate because the conditional content change doesn't match the ForEach identity change.

- **Impact**: Minor — no crash, but transitions may not animate smoothly for mood/journal cards.

- **Recommendation**: Consider moving the conditional logic OUTSIDE the ForEach by filtering these cards from `visibleCards` at the computed property level:
  ```swift
  var effectiveVisibleCards: [HomeCardID] {
      layout.visibleCards.filter { card in
          switch card {
          case .moodCheckIn: return !hasLoggedMoodToday
          case .journalReflection: return hasLoggedMoodToday && !hasJournaledToday
          default: return true
          }
      }
  }
  ```
  This way, `ForEach` identity matches actual rendering, and transitions work correctly.

#### M2. UndoToast Task.sleep Race Condition

- **Location**: Step 4 (UndoToast), Step 7e/7f (undo state management)
- **Problem**: `UndoToast.onAppear` starts a `Task.sleep(for: .seconds(3))` and then calls `onDismiss()`. If the user hides two cards rapidly:
  1. Card A hidden → toast appears → timer starts (3s)
  2. 1 second later, card B hidden → `undoState` replaced → new toast appears → new timer starts (3s)
  3. 2 seconds later, timer from step 1 fires → calls `onDismiss()` → sets `undoState = nil`
  4. Toast for card B vanishes after only 2 seconds

  The old Task is NOT cancelled when the view is replaced.

- **Impact**: Undo toast disappears prematurely when hiding cards in quick succession.

- **Recommendation**: Store the Task in a `@State` variable and cancel it when new undo state is set. Or use an ID-based approach: pass a unique ID to UndoToast, and in `onDismiss`, only dismiss if the current ID matches.

#### M3. `toggleElement` Has Dead Code Branch

- **Location**: Step 1 (`HomeLayoutConfig.toggleElement()`, lines 207-212 of plan)
- **Problem**: The auto-show branch is entirely commented out with a rationale comment:
  ```swift
  if hiddenCards.contains(card) && !visibleElements(for: card).isEmpty {
      // Only auto-show if the card was hidden implicitly...
      // We can't distinguish implicit vs. explicit hide here, so don't auto-show.
  }
  ```
  This dead code adds confusion. If the decision is "don't auto-show", just remove the branch entirely.

- **Impact**: Code clarity only — no runtime effect.

- **Recommendation**: Remove the dead branch. Add a comment on `hideCard()` noting that auto-hidden cards (all elements toggled off) must be manually re-shown.

#### M4. QuickStatsRow `onCoffeeLog` Closure Mismatch

- **Location**: Step 7c (`cardView(for: .quickStats)`)
- **Problem**: The plan's `onCoffeeLog` closure uses the `wasFirst` pattern from the committed version:
  ```swift
  onCoffeeLog: {
      let wasFirst = coffeeCups == 0 && todayWellnessLog?.coffeeType == nil
      coffeeCups += 1
      if wasFirst { activeSheet = .coffeeTypePicker }
      else { showCoffeeWaterAlert = true }
  }
  ```
  But the working tree's QuickStatsRow call at line 174 has a simplified closure:
  ```swift
  onCoffeeLog: { activeSheet = .coffeeTypePicker }
  ```
  The plan must use the **working tree** version to avoid introducing a regression.

- **Impact**: If the committed version's closure is used, it changes the coffee logging behavior from what the user currently sees.

- **Recommendation**: Use the working tree's simplified closure in the `cardView(for: .quickStats)` dispatch.

---

### LOW (Consider for Future)

#### L1. No Element-Level Customisation Disclosure in HomeLayoutEditor

- **Location**: Step 10 (HomeLayoutEditor)
- **Problem**: The plan mentions "Cards with sub-elements show a disclosure chevron → element toggles" in the brainstorm's Profile editor description, but Step 10's implementation doesn't include a `NavigationLink` for element-level customisation. The subtitle shows "2/4 elements visible" but there's no way to open the customize sheet from the editor.

- **Impact**: Users can only customize elements via the home screen context menu, not from the Profile editor. Minor discoverability gap.

- **Recommendation**: Add a `NavigationLink` on rows where `card.hasSubElements` is true, pushing to a `CardCustomizeSheet`-like view (or presenting it as a sheet).

#### L2. No Accessibility Labels for Context Menu Items

- **Location**: Step 3 (HomeCardContextMenu)
- **Problem**: The context menu buttons use `Label("Hide Card", systemImage: "eye.slash")` which is decent for VoiceOver, but the "Customize..." button doesn't include the card name. VoiceOver would read "Customize..." without context.

- **Impact**: Minor accessibility issue — VoiceOver users may not know which card is being customized.

- **Recommendation**: Use `Label("Customize \(card.displayName)", systemImage: "slider.horizontal.3")`.

---

## Missing Elements

- [ ] Migration of existing `@AppStorage("hideInsightCard")` state to HomeLayoutConfig on first launch
- [ ] Element-level customisation accessible from Profile HomeLayoutEditor (not just context menu)
- [ ] Cancellation of UndoToast auto-dismiss timer when new undo state is set
- [ ] Verification that the `DailyInsightCard.onDismiss` button behavior is migrated to the new system

## Unverified Assumptions

- [ ] SwiftData lightweight migration handles new `String` property with default on `UserGoals` — Risk: Low (same pattern as `coffeeDailyCups: Int = 4` added at line 11)
- [ ] `.contextMenu` inside `LazyVStack` within `ScrollView` works without scroll-to-top bugs on iOS 18+ — Risk: Low (tested in `MealLogCard.swift` line 56 which uses `.contextMenu` in the same ScrollView)
- [ ] `HomeCardID` enum case declaration order matches `CaseIterable` synthesis order — Risk: None (Swift guarantees declaration-order iteration for `CaseIterable`)
- [ ] `List` + `.onMove` works correctly when `.environment(\.editMode, .constant(.active))` is set — Risk: Low (standard pattern)

## Questions for Clarification

1. Should the existing `@AppStorage("hideInsightCard")` be migrated (check if true → pre-populate `hiddenCards` with `.dailyInsight`) or simply removed?
2. Should the `DailyInsightCard.onDismiss` inline button be kept (wired to `hideCard(.dailyInsight)`) or removed in favor of context-menu-only hiding?

## Recommendations

1. **Fix C1 immediately** — use `UserGoals.current(in: modelContext)` for all write paths
2. **Address H1 + H2 before checklist** — audit the working tree state and reconcile plan with actual current code
3. **Consider M1 strongly** — the `effectiveVisibleCards` approach produces cleaner ForEach identity and better animations
4. **Address M2 during implementation** — the timer race is easy to fix with a cancellable Task
5. **Remove M3 dead code** — don't ship commented-out branches
