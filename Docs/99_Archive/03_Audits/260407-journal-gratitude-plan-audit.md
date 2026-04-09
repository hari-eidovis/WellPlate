# Plan Audit Report: Journal / Gratitude Prompts Tied to Mood

**Audit Date**: 2026-04-07
**Plan Version**: `Docs/02_Planning/Specs/260407-journal-gratitude-plan.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

## Executive Summary

The plan is well-structured, follows existing codebase patterns closely, and correctly identifies all affected files. However, source code verification reveals 2 HIGH issues (preview crash, missing scenePhase refresh), 1 MEDIUM issue (sheet pattern violates CLAUDE.md convention), and several LOW items. All are fixable without architectural changes.

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

*None found.*

### HIGH (Should Fix Before Proceeding)

#### H1. HomeView Preview Will Crash After Adding `@Query` for JournalEntry
- **Location**: Plan Step 7 (Add Journal State) — adds `@Query private var allJournalEntries: [JournalEntry]`
- **Problem**: HomeView's preview at line 597–605 creates its own `ModelContainer` with only `FoodLogEntry.self`, `WellnessDayLog.self`, `UserGoals.self`. Adding a `@Query` for `JournalEntry` without adding the model to the preview container will crash with `SwiftData error: Model 'JournalEntry' was not included when creating the ModelContainer`.
- **Impact**: Preview becomes unusable; Xcode canvas crashes for HomeView
- **Recommendation**: Plan Step 7 must include updating the HomeView preview's `ModelContainer` to include `JournalEntry.self`:
  ```swift
  let container = try! ModelContainer(
      for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, JournalEntry.self,
      configurations: config
  )
  ```

#### H2. Missing scenePhase Refresh for Journal State
- **Location**: Plan Step 11 (Lifecycle Methods) — defines `refreshTodayJournalState()` but only calls it from `.onAppear`
- **Problem**: HomeView already has a `.onChange(of: scenePhase)` block at line 231 that refreshes mood, hydration, and coffee state when the app returns to foreground. The plan does not mention adding `refreshTodayJournalState()` here. If the user journals via a different path (e.g., Shortcuts, or edits data in another view) and returns, the journal card state will be stale.
- **Impact**: Journal card could show "write" prompt even though entry already exists, or vice versa
- **Recommendation**: Add `refreshTodayJournalState()` to the existing `.onChange(of: scenePhase)` block:
  ```swift
  .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      refreshTodayMoodState()
      refreshTodayHydrationState()
      refreshTodayCoffeeState()
      refreshTodayJournalState()  // ← add
  }
  ```

### MEDIUM (Fix During Implementation)

#### M1. Adding a Second `.sheet()` Modifier Violates CLAUDE.md Convention
- **Location**: Plan Step 10 — adds `.sheet(isPresented: $showJournalSheet)` to HomeView
- **Problem**: CLAUDE.md states: "Feature sheets use a single enum driving one `.sheet(item:)` — do not add multiple `.sheet()` calls." HomeView currently has one `.sheet(isPresented: $showCoffeeTypePicker)` at line 238. Adding a second boolean-driven `.sheet()` violates this convention and can cause SwiftUI sheet presentation conflicts (only one sheet can present at a time from the same view hierarchy).
- **Impact**: Potential sheet presentation bugs if coffee type picker and journal sheet are somehow triggered in sequence; violates documented architecture rule
- **Recommendation**: Introduce a `HomeSheet` enum (like `StressSheet` in StressView) to consolidate all sheet presentations:
  ```swift
  enum HomeSheet: Identifiable {
      case coffeeTypePicker
      case journalEntry
      var id: String { ... }
  }
  @State private var activeSheet: HomeSheet?
  ```
  Then use a single `.sheet(item: $activeSheet)` with a switch. Alternatively, since the coffee type picker and journal sheet will never conflict in practice (one requires no mood logged, the other requires mood logged), a pragmatic approach is to convert just the journal presentation to `.fullScreenCover` or keep the second `.sheet` with awareness of the limitation.

#### M2. `JournalPromptService` Does Not Need `bindContext` — But Plan Implies It
- **Location**: Plan Step 3 (Service Layer) and Step 11 (Lifecycle)
- **Problem**: The plan follows `StressInsightService` pattern which uses `bindContext()` because it reads from SwiftData (StressReading, WellnessDayLog, FoodLogEntry). However, `JournalPromptService` as designed only needs `mood: MoodOption?` and `stressLevel: String?` as inputs — it does not query SwiftData directly. The plan's Step 3 class structure does not show a `modelContext` property or `bindContext()` method, yet Step 11 doesn't explicitly state this isn't needed either.
- **Impact**: Implementer may add unnecessary `bindContext()` plumbing, or may be confused about whether the service needs ModelContext
- **Recommendation**: Explicitly state in Step 3 that `JournalPromptService` does NOT need `bindContext()` or `ModelContext` — all data is passed in via `generatePrompt(mood:stressLevel:)` parameters. This is simpler than `StressInsightService` and that's fine.

#### M3. Font Convention Inconsistency
- **Location**: Plan Steps 4, 5, 6 — reference both `.r(.headline, .semibold)` (from CLAUDE.md) and `.system(size:weight:design:.rounded)` patterns
- **Problem**: CLAUDE.md documents `.r()` as the font convention, but HomeView and its existing cards (`MoodCheckInCard`, header, etc.) actually use `.system(size:weight:design:.rounded)` directly. The plan's Step 4 styling section says to use `card styling` conventions but doesn't specify which font approach.
- **Impact**: New journal cards could be inconsistent with surrounding Home screen cards
- **Recommendation**: Use `.system(size:weight:design:.rounded)` to match HomeView's actual convention. The `.r()` extension is used in other parts of the app (Stress, Burn views) but Home screen cards use system fonts directly.

### LOW (Consider for Future)

#### L1. No Mention of Accessibility
- **Location**: Entire plan
- **Problem**: No VoiceOver labels, Dynamic Type considerations, or accessibility identifiers mentioned for any of the new views.
- **Impact**: Accessibility users may have difficulty using journal features
- **Recommendation**: Add `.accessibilityLabel()` to key elements (prompt text, save button, mood badges) during implementation. Not blocking.

#### L2. No Character Limit on Journal Text
- **Location**: Plan Step 1 (JournalEntry model) — `text: String` with no length constraint
- **Problem**: Users could paste extremely long text, impacting SwiftData storage and future Foundation Models theme analysis (context window limits).
- **Impact**: Low — unlikely in practice for a reflection prompt, but unbounded strings can cause issues at scale
- **Recommendation**: Consider a soft limit (e.g., 2000 characters) with a visual indicator in `JournalEntryView`. Not blocking for MVP.

#### L3. Template Prompt Randomness Could Repeat
- **Location**: Plan Step 3 — "Select randomly from the matching bucket"
- **Problem**: Pure random selection from ~50 prompts can show the same prompt on consecutive days.
- **Impact**: Minor UX annoyance
- **Recommendation**: Track last-used prompt (in UserDefaults or on the `JournalEntry.promptUsed` field) and exclude it from the next selection. Simple dedup.

#### L4. `JournalEntryView` Save Duplicates `saveJournalEntry()` Logic
- **Location**: Plan Steps 5 and 11
- **Problem**: The full sheet's `onSave` callback calls the same `saveJournalEntry()` method defined in HomeView. But `JournalEntryView` also has its own `@Environment(\.modelContext)` — if the sheet tries to save directly, there could be duplicate save paths.
- **Impact**: Potential confusion about where save logic lives
- **Recommendation**: Keep save logic exclusively in HomeView via the `onSave` callback. `JournalEntryView` should NOT save directly — it only manages the text editor and calls the closure. Remove `@Environment(\.modelContext)` from `JournalEntryView` if it's not needed for anything else.

## Missing Elements

- [ ] HomeView preview update with `JournalEntry.self` in ModelContainer
- [ ] `refreshTodayJournalState()` call in `.onChange(of: scenePhase)` block
- [ ] Explicit statement that `JournalPromptService` does NOT need `bindContext()`
- [ ] Font convention decision (`.system()` vs `.r()`) for new Home screen cards
- [ ] Sheet consolidation strategy (enum vs multiple `.sheet()` modifiers)

## Unverified Assumptions

- [ ] SwiftData handles `@Attribute(.unique)` on `Date` fields without issues when using `Calendar.startOfDay` — Risk: Low (same pattern used by `WellnessDayLog.day`)
- [ ] Foundation Models `@Generable` works with a simple 2-field struct (prompt + category) — Risk: Low (simpler than existing `_StressInsightSchema`)
- [ ] Adding a 4th header icon (book) doesn't overflow on smaller devices (iPhone SE) — Risk: Low–Medium (4 circles × 44pt + spacing = ~220pt; SE screen is 375pt wide, minus greeting text)

## Questions for Clarification

1. Should the journal sheet use `.sheet()` or `.fullScreenCover()` for the full entry view? Full-screen cover prevents accidental dismiss but adds more friction.
2. Is the header getting crowded with 4 icons (AI, Calendar, Journal, Mood badge)? Consider moving journal access elsewhere if so.

## Recommendations

1. **Fix H1 and H2 before implementation** — both are straightforward additions to existing code
2. **Decide on M1 (sheet pattern)** early — if converting to enum-based sheets, it affects HomeView structure
3. **Clarify M2** in the plan — explicitly state `JournalPromptService` is a stateless prompt generator, not a data-fetching service
4. **Match M3 font convention** to actual HomeView code (`.system()`, not `.r()`)
5. Overall: plan is solid and well-researched. Issues are all addressable without rethinking architecture.
