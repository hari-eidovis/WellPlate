# Checklist Audit Report: Home Screen Content Customisation

**Audit Date**: 2026-04-14
**Checklist Version**: `Docs/04_Checklist/260414-home-customisation-checklist.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The checklist is thorough and well-structured, covering all 13 plan steps with specific verify criteria and 13 manual test flows. Two medium issues found: a missing `resetToDefaults()` update that would leave stale layout data on reset, and a missing verify step for the `onAppear` migration ordering. One low issue about the init parameter placement. Overall ready for implementation after minor fixes.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

None.

### HIGH (Should Fix Before Proceeding)

None.

### MEDIUM (Fix During Implementation)

#### M1. `UserGoals.resetToDefaults()` Not Updated — Stale Layout Data on Reset

- **Location**: Step 1.2 (UserGoals modification)
- **Problem**: `UserGoals.resetToDefaults()` (line 146 of `UserGoals.swift`) manually resets every property to defaults:
  ```swift
  func resetToDefaults() {
      waterCupSizeML = 250
      waterDailyCups = 8
      // ... all other properties
      sleepGoalHours = 8.0
      // homeLayoutJSON is NOT reset!
  }
  ```
  The checklist doesn't include adding `homeLayoutJSON = "{}"` to this method. If a user triggers "Reset to Defaults" from the Goals screen, all their goals reset but their home layout customisation persists — which may be intended, but is more likely a gap.

  Note: The `HomeLayoutEditor` has its own "Reset to Default Layout" button that calls `layout.reset()`. So there are two reset paths, and they should be consistent.

- **Impact**: Minor inconsistency. User resets goals → expects clean slate → layout is still customised.

- **Recommendation**: Add a checklist item to Step 1.2:
  ```
  - [ ] Add `homeLayoutJSON = "{}"` to `resetToDefaults()` method (~line 167)
  ```

#### M2. Migration Ordering in `onAppear` Not Explicit

- **Location**: Step 3.8
- **Problem**: The checklist says "Call `migrateHideInsightCardIfNeeded()` in the `.onAppear` block (after existing calls)" but the existing `.onAppear` block has a specific order:
  ```swift
  .onAppear {
      foodJournalViewModel.bindContext(modelContext)
      insightEngine.bindContext(modelContext)
      Task { await insightEngine.generateInsights() }
      refreshTodayMoodState()
      refreshTodayHydrationState()
      refreshTodayCoffeeState()
      hasCoffeeStateLoaded = true
      refreshTodayJournalState()
      foodJournalViewModel.loadYesterdayStats()
  }
  ```
  The migration MUST run AFTER `foodJournalViewModel.bindContext(modelContext)` (since it uses `modelContext`) but BEFORE `insightEngine.generateInsights()` (since the insight engine might check card visibility). Placing it at the very end is safe but suboptimal — if the insight engine regenerates insights for a card the user had previously hidden, it wastes a cycle.

- **Impact**: Negligible functional impact, but the checklist should specify placement for implementer clarity.

- **Recommendation**: Update Step 3.8 to specify: "Add `migrateHideInsightCardIfNeeded()` call immediately after `insightEngine.bindContext(modelContext)` and before `Task { await insightEngine.generateInsights() }`"

---

### LOW (Consider for Future)

#### L1. Init Parameter Placement Could Be More Specific

- **Location**: Step 1.2
- **Problem**: The checklist says "Add `homeLayoutJSON: String = "{}"` as the last parameter of the `init(...)` method" — the current last parameter is `sleepGoalHours: Double = 8.0`. While "last parameter" is technically correct, specifying "after `sleepGoalHours: Double = 8.0`" would be more explicit for the implementer.

- **Impact**: Trivially clear from context, but more specificity never hurts.

- **Recommendation**: Clarify to "Add `homeLayoutJSON: String = "{}"` after the `sleepGoalHours` parameter in the `init(...)` method"

---

## Completeness Check

| Plan Phase | Checklist Coverage | Status |
|---|---|---|
| Phase 1: Data Model | Steps 1.1, 1.2 | Complete |
| Phase 2: Context Menu | Steps 2.1, 2.2, 2.3 | Complete |
| Phase 3: HomeView Refactor | Steps 3.1–3.9 | Complete |
| Phase 4: QuickStatsRow | Step 4.1 | Complete |
| Phase 5: Profile Editor | Steps 5.1, 5.2, 5.3 | Complete |
| Phase 6: Build & Polish | Post-Implementation | Complete |

All 13 RESOLVED plan steps have corresponding checklist items. All audit resolutions (C1, H1, H2, H3, M1–M4, L1, L2) are reflected.

## Unverified Assumptions

- [ ] `DailyInsightCard.onDismiss` fires correctly when wired to `hideCard(.dailyInsight)` — the current `onDismiss` calls `withAnimation { onDismiss() }` internally (verified at DailyInsightCard.swift line 89), so the `hideCard` animation may double-wrap. Risk: Low — nested `withAnimation` is harmless in SwiftUI.
- [ ] `.deleteDisabled(true)` suppresses the red minus circles in constant `.active` editMode — Risk: Low (standard SwiftUI behavior).

## Recommendations

1. **Add `homeLayoutJSON = "{}"` to `resetToDefaults()`** — one line, prevents inconsistent reset behavior
2. **Specify migration placement in `onAppear`** — after `bindContext`, before `generateInsights`
3. Otherwise, the checklist is **ready for implementation**
