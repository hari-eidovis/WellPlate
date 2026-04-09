# Checklist Audit Report: Journal / Gratitude Prompts Tied to Mood

**Audit Date**: 2026-04-08
**Checklist Version**: `Docs/04_Checklist/260407-journal-gratitude-checklist.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The checklist is comprehensive, well-ordered, and covers all 12 plan steps with verify steps. Source code verification confirms the `HomeSheet` enum pattern is proven (used by `StressSheet`, `FastingSheet`), the coffee picker migration is safe, and SwiftData imports are already present. Two issues need fixing: a double-dismiss race condition in JournalEntryView and a missing animation context for the card swap transition.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

*None found.*

### HIGH (Should Fix Before Proceeding)

#### H1. Double-Dismiss Race in JournalEntryView Save Flow
- **Location**: Step 4.1 (line 144) says "Save button action: calls `onSave()` then `dismiss()`". Step 6.8 `saveJournalEntry()` sets `activeSheet = nil`.
- **Problem**: When the user taps Save in the full sheet, `onSave()` fires which calls `saveJournalEntry()` which sets `activeSheet = nil` (dismissing the sheet). Then `dismiss()` is called on an already-dismissed view. This is a double-dismiss race condition that can cause SwiftUI warnings or visual glitches.
- **Impact**: Potential console warnings, animation artifacts, or crash on some iOS versions
- **Recommendation**: Remove `dismiss()` from `JournalEntryView`'s Save button. Use ONLY `onSave()` — the parent's `saveJournalEntry()` handles dismissal by setting `activeSheet = nil`. The X button can still use `dismiss()` for cancel (since it doesn't trigger `onSave`). Update Step 4.1:
  ```
  Save button action: calls `onSave()` only — parent handles dismissal via `activeSheet = nil`
  X button action: calls `dismiss()` for cancel
  ```

### MEDIUM (Fix During Implementation)

#### M1. Card Swap Transition Needs Animation Context
- **Location**: Step 6.4 — applies `.transition()` to `JournalReflectionCard` but doesn't ensure the state change triggering insertion happens inside `withAnimation()`
- **Problem**: SwiftUI `.transition()` modifiers only animate when the view insertion/removal occurs inside an animation context. The existing mood badge works because `logMoodForTodayIfNeeded()` wraps `hasLoggedMoodToday = true` in `withAnimation(.spring(...))` at line 532. But `refreshTodayJournalState()` in Step 6.8 does NOT wrap `hasJournaledToday = true` in `withAnimation()`.
- **Impact**: Journal card save → disappear may be instant (no fade), and journal card appearance after mood log may also be instant
- **Recommendation**: The `hasLoggedMoodToday = true` change is already inside `withAnimation` (line 532), so the journal card insertion after mood log WILL animate. But `hasJournaledToday = true` in `saveJournalEntry()` IS wrapped in `withAnimation` (Step 6.8 code shows this). And `refreshTodayJournalState()` sets `hasJournaledToday` without animation — this is correct for onAppear/scenePhase (no animation needed for state restore). So this is actually fine for the save path. However, add a note to Step 6.8 clarifying that `refreshTodayJournalState()` intentionally does NOT animate (state restore), while `saveJournalEntry()` DOES animate via `withAnimation`.

#### M2. Missing Enumeration of All `showCoffeeTypePicker` References
- **Location**: Step 6.3 says "Find all occurrences" but doesn't list them
- **Problem**: Source code verification found 6 references to `showCoffeeTypePicker` across HomeView.swift:
  - Line 28: `@State` declaration → **remove** (replaced by `activeSheet`)
  - Line 206: `showCoffeeTypePicker = true` inside `onChange(of: coffeeCups)` → **replace** with `activeSheet = .coffeeTypePicker`
  - Line 207: comment referencing `showCoffeeTypePicker` → **update** comment
  - Line 219: `.onChange(of: showCoffeeTypePicker)` → **replace** with `.onChange(of: activeSheet)`
  - Line 238: `.sheet(isPresented: $showCoffeeTypePicker)` → **replace** with `.sheet(item: $activeSheet)`
  - Line 241: `showCoffeeTypePicker = false` inside sheet closure → **replace** with `activeSheet = nil`
- **Impact**: Missing a reference would leave a compile error (state variable no longer exists)
- **Recommendation**: Add explicit line-number list to Step 6.3 so implementer doesn't miss any reference

### LOW (Consider for Future)

#### L1. `showCoffeeWaterAlert` Timing After Sheet Enum Migration
- **Location**: Step 6.3 — the old pattern had a race-safe comment about `showCoffeeWaterAlert` firing only after sheet animation completes
- **Problem**: The old `.onChange(of: showCoffeeTypePicker)` fired after the sheet fully dismissed. The new `.onChange(of: activeSheet)` fires when the enum changes to nil, which is the same timing for `.sheet(item:)` — SwiftUI calls onChange when the binding changes, and the sheet animates out. This should be equivalent, but worth testing.
- **Impact**: Low — if timing differs, the water alert could appear while the coffee picker sheet is still animating out
- **Recommendation**: Test this specific flow during functional verification. No checklist change needed.

## Missing Elements

- [ ] Explicit line numbers for all `showCoffeeTypePicker` references in Step 6.3
- [ ] Clarification in Step 4.1 that Save button should NOT call `dismiss()` — only `onSave()`
- [ ] Note in Step 6.8 explaining animation context: `saveJournalEntry()` uses `withAnimation`, `refreshTodayJournalState()` intentionally does not

## Unverified Assumptions

- [ ] `HomeSheet` auto-synthesizes `Equatable` — Risk: None (confirmed: enums without associated values always do)
- [ ] `.onChange(of: activeSheet)` fires with correct `old`/`new` values for `.sheet(item:)` dismiss — Risk: Low (proven by StressSheet pattern)

## Questions for Clarification

None — all questions resolved via source code verification.

## Recommendations

1. **Fix H1** — simplest fix: remove `dismiss()` from JournalEntryView's Save action, keep it only on the X cancel button
2. **Add M2 line numbers** to Step 6.3 — prevents missed references during implementation
3. **Add M1 clarifying note** to Step 6.8 — prevents implementer from adding unnecessary `withAnimation` wrappers
4. Overall: checklist is solid and implementation-ready after these fixes
