# Plan Audit Report: MealLogView Implementation

**Audit Date**: 2026-03-09
**Plan Version**: v1 (initial)
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is well-structured and covers most UI sections faithfully. However, the save flow architecture has a critical coupling flaw: `MealLogViewModel` calls `HomeViewModel.logFood()` then retroactively patches the entry, which is fragile and ignores the disambiguation branch. The voice recording feature introduces an undeclared microphone permission. Several medium-priority gaps around error handling, file cleanup, and data modeling should also be addressed before implementation.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

1. **Save flow race condition / two-ViewModel coupling**
   - Location: Section 3 (MealLogViewModel) -- `saveMeal()` method
   - Problem: The plan says `MealLogViewModel` calls `HomeViewModel.logFood()` then "patches the newly created `FoodLogEntry` with context fields." This is a two-step operation with no reliable way to find the entry that was just created. `HomeViewModel.logFood()` calls `modelContext.insert()` internally, but the inserted entry is not returned or exposed. Finding "the most recent entry" is unreliable when entries can be created from multiple sources.
   - Impact: Context fields (triggers, hunger level, etc.) could be attached to the wrong entry, or lost entirely if the save flow enters disambiguation or errors out mid-way.
   - Recommendation: Pass all context fields directly into `HomeViewModel.logFood()` (and its `insertLog()` helpers) so the `FoodLogEntry` is created atomically with all data. Add a new parameter bundle (e.g., a `MealContext` struct) to `logFood(on:context:)` rather than coupling two ViewModels.

2. **Disambiguation flow unhandled in MealLogView**
   - Location: Section 3 (MealLogViewModel) and Section 4 (MealLogView)
   - Problem: `HomeViewModel.logFood()` can set `disambiguationState` when confidence is low, suspending the save and requiring user interaction (chip selection). The plan does not describe how `MealLogView` observes or reacts to this state. Since `disambiguationState` lives on `HomeViewModel`, the sheet-based MealLogView would need to either: (a) observe it and display chips inline, or (b) dismiss and let FoodJournalView handle it -- neither is addressed.
   - Impact: When the user types something ambiguous (e.g., "pasta"), the save silently fails with no feedback in MealLogView. The disambiguation chips appear behind the sheet on FoodJournalView.
   - Recommendation: Either (a) pass `disambiguationState` binding into MealLogView and render `DisambiguationChipsView` inline, or (b) have `MealLogViewModel` run `MealCoachService` directly and handle disambiguation within its own view hierarchy. Option (b) is cleaner since MealLogView is a self-contained experience.

### HIGH (Should Fix Before Proceeding)

3. **Missing microphone permission declaration**
   - Location: Section 4 (Voice Note Section)
   - Problem: The plan includes `AVAudioRecorder` for 30-second voice recording but does not mention adding `NSMicrophoneUsageDescription` to the app's Info.plist. The main target has no Info.plist file (it uses Xcode-managed settings) -- only the widget and ScreenTimeReport extensions have Info.plist files.
   - Impact: The app will crash at runtime when requesting microphone access without the usage description string.
   - Recommendation: Add `NSMicrophoneUsageDescription` to the main target's Info.plist (or Xcode project settings). Include a user-friendly string like "WellPlate uses the microphone to record optional voice reflections with your meals." Alternatively, defer voice recording to a later phase and make it UI-only for now.

4. **Comma-separated string for eatingTriggers is fragile**
   - Location: Section 2 (Extend FoodLogEntry) -- `var eatingTriggers: String?`
   - Problem: Storing multi-select values as a comma-separated string is error-prone (no type safety, parsing overhead, edge cases with values containing commas). SwiftData supports `Codable` properties natively when the type conforms to `Codable`.
   - Impact: Querying or filtering by trigger becomes difficult. Parsing bugs if format changes.
   - Recommendation: Store as `[String]?` (array of raw values). Since `[String]` is `Codable`, SwiftData will handle it automatically via JSON encoding. No `@Attribute(.transformable)` needed. Example: `var eatingTriggers: [String]?`

5. **ExpandableFAB behavior change not clearly scoped**
   - Location: Section 5 (Navigation Integration)
   - Problem: The plan says "change the ExpandableFAB's main plus button behavior" to open MealLogView, effectively killing the expand-to-reveal-actions pattern. However, the MealLogView screenshot already includes "Add photo", "Scan barcode", and "Voice note" inline. This is a migration of FAB actions INTO MealLogView, which should be stated explicitly.
   - Impact: Ambiguity about whether to keep `ExpandableFAB` as-is, replace it with a simple button, or remove it entirely.
   - Recommendation: Replace the `ExpandableFAB` component with a simple plus `Button` that opens the MealLogView sheet. State explicitly that the mic/camera/notepad actions have been absorbed into MealLogView's Quick Action Row. The `ExpandableFAB.swift` file can remain for potential reuse elsewhere.

### MEDIUM (Fix During Implementation)

6. **No loading or error states in MealLogView**
   - Problem: The nutrition analysis API call is async and can take seconds. The plan describes the "Save & Reflect" button but no loading indicator, disabled state during save, or error alert if the API fails.
   - Recommendation: Add `isLoading` state to `MealLogViewModel`. Disable the save button and show a `ProgressView` overlay during save. Show an error alert on failure, mirroring the existing pattern in `FoodJournalView`.

7. **Voice note file cleanup on entry deletion**
   - Problem: Voice notes are stored as files on disk (`voiceNoteURL`). When a `FoodLogEntry` is deleted (via `MealLogCard` swipe-to-delete or `deleteFoodEntry()`), the audio file remains orphaned.
   - Recommendation: In `FoodJournalView.deleteFoodEntry()`, check if the entry has a `voiceNoteURL` and delete the file from disk before deleting the model.

8. **Widget refresh not mentioned**
   - Problem: The current `logFood()` flow calls `refreshWidget(for:)` after saving. The plan does not mention widget refresh. If the save flow is restructured, widget refresh must be preserved.
   - Recommendation: Ensure `refreshWidget(for:)` is called after the atomic save, same as current flow.

9. **No keyboard handling for multi-field form**
   - Problem: MealLogView has at least two text inputs (food description, reflection text). The plan does not address keyboard avoidance, scroll-to-focused-field, or dismiss-keyboard-on-scroll.
   - Recommendation: Use `.scrollDismissesKeyboard(.interactively)` on the ScrollView (matching existing FoodJournalView pattern). Consider `@FocusState` management for the multiple text fields.

10. **MealType auto-selection logic duplicated**
    - Problem: The plan says `MealType` should auto-select based on current hour "same logic as `MealLogCard.mealTimeColor`." This creates duplicated time-range logic in two places.
    - Recommendation: Move the time-to-meal-type mapping into `MealType` as a static method (e.g., `MealType.current(for date: Date) -> MealType`), then have `MealLogCard.mealTimeColor` derive from `MealType` as well.

### LOW (Consider for Future)

11. **No test strategy**
    - Problem: No unit tests are planned for `MealLogViewModel` (form validation, auto meal type selection, save flow). No snapshot or integration tests.
    - Recommendation: At minimum, add unit tests for `MealType.current(for:)`, `MealLogViewModel.isValid`, and the save flow with mock dependencies.

12. **No accessibility planning**
    - Problem: The trigger grid (8 emoji cards), custom sliders (hunger/presence), and voice note section all need VoiceOver labels, traits, and hints. Emoji-only labels are not screen-reader friendly.
    - Recommendation: Add `accessibilityLabel` to each trigger card (e.g., "Hungry, eating trigger, selected"). Add `accessibilityValue` to sliders. Mark decorative emojis with `accessibilityHidden(true)` when text labels are present.

13. **No dark mode consideration for custom slider styling**
    - Problem: The screenshot only shows light mode. The existing design system handles dark mode via asset catalog colors, but any custom slider track/thumb styling needs to be adaptive.
    - Recommendation: Use `AppColors` tokens for slider track colors rather than hardcoded values. Test in both appearances.

## Missing Elements

- [ ] `MealContext` struct to bundle all context fields for atomic save
- [ ] Loading/error state handling in MealLogView
- [ ] `NSMicrophoneUsageDescription` in Info.plist for voice recording
- [ ] Voice note file cleanup in deletion flow
- [ ] Keyboard avoidance and focus management
- [ ] Widget refresh after save
- [ ] Disambiguation handling within MealLogView

## Unverified Assumptions

- [ ] SwiftData lightweight migration handles 6 new optional properties without issues - Risk: Medium (typically safe, but untested with this many additions at once; recommend testing on a device with existing data)
- [ ] `[String]?` is natively persisted by SwiftData without `@Attribute(.transformable)` - Risk: Low (documented behavior for Codable types)
- [ ] Sheet presentation does not interfere with existing `DisambiguationChipsView` overlay - Risk: High (Z-index and sheet layering conflicts)

## Security Considerations

- [ ] Voice note files stored in app documents -- ensure they are not backed up to iCloud if privacy is a concern (use `.isExcludedFromBackup` or store in tmp/caches)
- [ ] Reflection text is user-provided free text -- no injection risk in SwiftData, but ensure it's not rendered as HTML anywhere

## Performance Considerations

- [ ] Voice recording should use a compressed format (AAC/m4a) not WAV to minimize storage
- [ ] The 8-card trigger grid with animations should use `LazyVGrid` (already planned) to avoid unnecessary view allocations
- [ ] Slider value changes should be debounced if they trigger any side effects

## Questions for Clarification

1. Should the voice recording feature be fully implemented now, or is UI-only (with TODO) acceptable for the first pass?
2. When the "Save & Reflect" button is tapped, should it navigate to a reflection/summary screen, or just save and dismiss?
3. Should the eating triggers and context sliders be required, or can a user save with just a food description?

## Recommendations

1. **Restructure save flow**: Create a `MealContext` struct and pass it through `HomeViewModel.logFood(on:context:)` for atomic entry creation. Do not use a two-step create-then-patch approach.
2. **Handle disambiguation inline**: Run `MealCoachService` from `MealLogViewModel` directly so disambiguation can be handled within the MealLogView sheet, rather than punting to `HomeViewModel`.
3. **Phase voice recording**: Implement the voice note UI with a "Coming soon" state for v1, and add actual AVAudioRecorder in a follow-up. This avoids the microphone permission and file management complexity.
4. **Use `[String]?` for triggers**: Replace comma-separated string with a proper Codable array.
5. **Consolidate time-to-meal logic**: Single source of truth in `MealType.current(for:)`.

## Sign-off Checklist

- [ ] All CRITICAL issues resolved
- [ ] All HIGH issues resolved or accepted
- [ ] Security review completed
- [ ] Performance implications understood
- [ ] Rollback strategy defined
