# Implementation Checklist: Journal / Gratitude Prompts Tied to Mood

**Source Plan**: `Docs/02_Planning/Specs/260407-journal-gratitude-plan-RESOLVED.md`
**Date**: 2026-04-07
**Status**: RESOLVED — Ready for Implementation

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| H1 — Double-dismiss race in JournalEntryView | HIGH | **FIXED** — Step 4.1 Save button now calls `onSave()` only; X button uses `dismiss()` for cancel |
| M1 — Card swap animation context | MEDIUM | **FIXED** — Step 6.8 now has clarifying note: `saveJournalEntry()` animates, `refreshTodayJournalState()` intentionally does not |
| M2 — Missing `showCoffeeTypePicker` line references | MEDIUM | **FIXED** — Step 6.3 now lists all 6 references with exact line numbers |
| L1 — `showCoffeeWaterAlert` timing | LOW | **ACKNOWLEDGED** — Added to functional verification checklist |

---

## Pre-Implementation

- [ ] Read the resolved plan: `Docs/02_Planning/Specs/260407-journal-gratitude-plan-RESOLVED.md`
- [ ] Verify affected files exist:
  - [ ] `WellPlate/App/WellPlateApp.swift` — contains `.modelContainer(for:)` on line 34
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift` — contains `MoodCheckInCard` on line 88
  - [ ] `WellPlate/Shared/Components/MoodCheckInCard.swift` — exists (no changes, reference only)
  - [ ] `WellPlate/Core/Services/StressInsightService.swift` — exists (reference for Foundation Models pattern)
  - [ ] `WellPlate/Models/StressReading.swift` — exists (reference for @Model pattern)
- [ ] Verify no naming conflicts: search for `JournalEntry.swift`, `JournalPromptService.swift`, `JournalReflectionCard.swift`, `JournalEntryView.swift`, `JournalHistoryView.swift` — none should exist
  - Verify: `find WellPlate/ -name "Journal*.swift"` returns empty

---

## Phase 1: Data Layer

### 1.1 — Create JournalEntry SwiftData Model

- [ ] Create file `WellPlate/Models/JournalEntry.swift`
- [ ] Define `@Model final class JournalEntry` with:
  - `@Attribute(.unique) var day: Date` — start of day
  - `var text: String`
  - `var moodRaw: Int?`
  - `var promptUsed: String?`
  - `var stressScore: Double?`
  - `var createdAt: Date`
  - `var updatedAt: Date`
- [ ] Add `init(day:text:moodRaw:promptUsed:stressScore:createdAt:updatedAt:)` with defaults — `day` must use `Calendar.current.startOfDay(for:)`
- [ ] Add computed property `var mood: MoodOption?` resolving from `moodRaw`
- [ ] Verify: File compiles — run `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

### 1.2 — Register JournalEntry in ModelContainer

- [ ] Edit `WellPlate/App/WellPlateApp.swift` line 34 — add `JournalEntry.self` to the `.modelContainer(for:)` array after `FastingSession.self`
  - Verify: The array now contains 10 models ending with `JournalEntry.self`
- [ ] Build to confirm: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 2: Service Layer

### 2.1 — Create JournalPromptService

- [ ] Create file `WellPlate/Core/Services/JournalPromptService.swift`
- [ ] Add imports: `Foundation`, `SwiftUI`, and conditional `#if canImport(FoundationModels)` / `import FoundationModels`
- [ ] Define `@MainActor final class JournalPromptService: ObservableObject` with:
  - `@Published var currentPrompt: String?`
  - `@Published var promptCategory: String?`
  - `@Published var isGenerating: Bool = false`
- [ ] **No `bindContext()` or `ModelContext`** — this service is stateless; all data passed via parameters
- [ ] Implement `func generatePrompt(mood: MoodOption?, stressLevel: String?) async`:
  - Set `isGenerating = true`
  - On iOS 26+: attempt Foundation Models generation, fall back to template on failure
  - On older iOS: use template directly
  - Set `currentPrompt` and `promptCategory` from result
  - Set `isGenerating = false`
  - Verify: Method signature matches `func generatePrompt(mood: MoodOption?, stressLevel: String?) async`

### 2.2 — Foundation Models Integration

- [ ] Add `@available(iOS 26, *)` private method for Foundation Models generation
- [ ] Check `SystemLanguageModel.default.availability` — return nil if not `.available`
- [ ] Create `LanguageModelSession()`, build prompt string from mood + stress + time of day
- [ ] Call `session.respond(to: prompt, generating: _JournalPromptSchema.self)`
- [ ] Add `@Generable private struct _JournalPromptSchema` inside `#if canImport(FoundationModels)` block with:
  - `@Guide(description: "A warm, specific 1–2 sentence journal prompt...")` `var prompt: String`
  - `@Guide(description: "Single-word category: gratitude, reflection, awareness, or intention")` `var category: String`
- [ ] On error: log via `WPLogger.home.warning(...)` and return nil to trigger fallback
  - Verify: No compiler errors with `#if canImport(FoundationModels)` guards

### 2.3 — Template Fallback Library

- [ ] Define `private enum MoodTier: CaseIterable { case low, neutral, high }` with helper to map from `MoodOption`
- [ ] Define `private enum TimeOfDay: CaseIterable { case morning, afternoon, evening }` with helper from current hour
- [ ] Create `private static let templates: [MoodTier: [TimeOfDay: [(prompt: String, category: String)]]]` with ~50 prompts across all combinations (~5-6 per bucket)
- [ ] Implement template selection: pick from matching bucket, exclude last-used index via `UserDefaults("journalLastPromptIndex")`
- [ ] Use `stressLevel` as secondary signal: high stress → prefer awareness/intention categories; low stress → prefer gratitude
  - Verify: Template method returns a non-nil prompt for every mood × time combination

### 2.4 — Build Check

- [ ] Build to confirm service compiles: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 3: UI — Inline Card

### 3.1 — Create JournalReflectionCard

- [ ] Create file `WellPlate/Features + UI/Home/Views/JournalReflectionCard.swift`
- [ ] Define `struct JournalReflectionCard: View` with props:
  - `let prompt: String?`
  - `let promptCategory: String?`
  - `@Binding var entryText: String`
  - `var onSave: () -> Void`
  - `var onWriteMore: () -> Void`
  - `var isGeneratingPrompt: Bool`
- [ ] Build card layout:
  - Header: "Daily Reflection" with book icon
  - Prompt text: italic, secondary color, `.system(size: 14, weight: .regular, design: .rounded)`
  - Category badge: small capsule with category name
  - Text field: `TextField("Write something...", text:, axis: .vertical)` with `lineLimit(2...4)`
  - Save button: filled capsule, `AppColors.brand`, disabled when text empty
  - "Write more →" button: trailing, brand color
- [ ] Style card background: `RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground))` + gradient overlay + shadow matching `MoodCheckInCard`
- [ ] Add shimmer/placeholder state when `isGeneratingPrompt` is true
- [ ] Add haptics: `HapticService.impact(.light)` on Save and Write More taps
- [ ] Add `.accessibilityLabel()` to prompt text, Save button, and Write More link
- [ ] Add `#Preview` block with mock data
  - Verify: Preview renders in Xcode canvas without crash

---

## Phase 4: UI — Full Journal Sheet

### 4.1 — Create JournalEntryView

- [ ] Create file `WellPlate/Features + UI/Home/Views/JournalEntryView.swift`
- [ ] Define `struct JournalEntryView: View` with props:
  - `@Environment(\.dismiss) private var dismiss`
  - `let mood: MoodOption?`
  - `let stressLevel: String?`
  - `@Binding var entryText: String`
  - `let prompt: String?`
  - `@ObservedObject var promptService: JournalPromptService`
  - `var onSave: () -> Void`
  - **No `@Environment(\.modelContext)`** — save via `onSave` callback only
- [ ] Build layout in `NavigationStack`:
  - Toolbar: X dismiss button (leading), Save button (trailing, disabled when empty)
  - Context header: mood emoji + label pill, stress level pill, date
  - Prompt card: shown at top with "New prompt" refresh button
  - `TextEditor` for main text input, fills available space
  - Character count footer: `"\(entryText.count) / 2000"`, warning color when >1800
- [ ] Add `.scrollDismissesKeyboard(.interactively)`
- [ ] Add `.presentationDetents([.large])`
- [ ] "New prompt" button: calls `Task { await promptService.generatePrompt(...) }`
<!-- RESOLVED: H1 — Save calls onSave() only; parent handles dismiss via activeSheet = nil. X button uses dismiss() for cancel. -->
- [ ] **Save button action**: calls `onSave()` **only** — do NOT call `dismiss()`. Parent's `saveJournalEntry()` handles sheet dismissal by setting `activeSheet = nil`
- [ ] **X (cancel) button action**: calls `dismiss()` — this is the only place `dismiss()` is used
- [ ] Add `.accessibilityLabel()` to context header, prompt, save button
- [ ] Add `#Preview` block
  - Verify: Preview renders without crash

---

## Phase 5: UI — Journal History

### 5.1 — Create JournalHistoryView

- [ ] Create file `WellPlate/Features + UI/Home/Views/JournalHistoryView.swift`
- [ ] Define `struct JournalHistoryView: View` with:
  - `@Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]`
- [ ] Build layout:
  - Navigation title: "Journal History"
  - Group entries by relative date (Today, Yesterday, then formatted date strings)
  - Each entry card: mood emoji + label colored pill, truncated text (3 lines via `.lineLimit(3)`), timestamp
  - Tap to expand: `@State` toggle per entry to show full text
  - Empty state: centered text "Start your first journal entry" with book icon
- [ ] Add swipe-to-delete with `modelContext.delete()` + `try modelContext.save()`
- [ ] Style cards: `RoundedRectangle(cornerRadius: 16)`, lighter shadow
- [ ] Font: `.system(size:weight:design:.rounded)` throughout
- [ ] Add `.accessibilityLabel()` combining mood and text snippet for each entry card
- [ ] Add `#Preview` with in-memory ModelContainer including `JournalEntry.self`
  - Verify: Preview renders without crash

### 5.2 — Build Check

- [ ] Build to confirm all new views compile: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`

---

## Phase 6: Integration — HomeView Wiring

### 6.1 — Add HomeSheet Enum

- [ ] Add `HomeSheet` enum above or inside `HomeView` in `WellPlate/Features + UI/Home/Views/HomeView.swift`:
  ```swift
  enum HomeSheet: Identifiable {
      case coffeeTypePicker
      case journalEntry
      var id: String {
          switch self {
          case .coffeeTypePicker: return "coffeeTypePicker"
          case .journalEntry: return "journalEntry"
          }
  }
  ```
  - Verify: Enum compiles, conforms to `Identifiable` (also auto-synthesizes `Equatable` — no explicit conformance needed)

### 6.2 — Add State Variables & Query

- [ ] Add `@Query private var allJournalEntries: [JournalEntry]` after existing `@Query` declarations (~line 13)
- [ ] Replace `@State private var showCoffeeTypePicker = false` with `@State private var activeSheet: HomeSheet?`
- [ ] Add new state variables after existing `@State` declarations (~line 35):
  - `@State private var journalText: String = ""`
  - `@State private var hasJournaledToday = false`
  - `@State private var showJournalHistory = false`
- [ ] Add `@StateObject private var journalPromptService = JournalPromptService()` after existing `@StateObject` declarations (~line 37)
- [ ] Add computed property:
  ```swift
  private var todayJournalEntry: JournalEntry? {
      allJournalEntries.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
  }
  ```
  - Verify: No compiler errors on declarations

### 6.3 — Migrate Coffee Picker to HomeSheet Enum

<!-- RESOLVED: M2 — All 6 showCoffeeTypePicker references now listed with exact line numbers -->
- [ ] **Line 28**: Remove `@State private var showCoffeeTypePicker = false` (replaced by `activeSheet` in Step 6.2)
- [ ] **Line 206**: Replace `showCoffeeTypePicker = true` with `activeSheet = .coffeeTypePicker` (inside `onChange(of: coffeeCups)`, first-cup path)
- [ ] **Line 207**: Update comment `// Water alert fires in onChange(of: showCoffeeTypePicker)` → `// Water alert fires in onChange(of: activeSheet)`
- [ ] **Line 219**: Replace `.onChange(of: showCoffeeTypePicker) { _, isShowing in` with `.onChange(of: activeSheet) { old, new in`
- [ ] **Line 238**: Replace `.sheet(isPresented: $showCoffeeTypePicker) { ... }` with the consolidated `.sheet(item: $activeSheet)`:
  ```swift
  .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .coffeeTypePicker:
          CoffeeTypePickerSheet { type in
              pendingCoffeeType = type
              activeSheet = nil
          }
      case .journalEntry:
          JournalEntryView(
              mood: selectedMood,
              stressLevel: todayWellnessLog?.stressLevel,
              entryText: $journalText,
              prompt: journalPromptService.currentPrompt,
              promptService: journalPromptService,
              onSave: saveJournalEntry
          )
      }
  }
  ```
- [ ] **Line 241**: The `showCoffeeTypePicker = false` inside the old sheet closure is now `activeSheet = nil` inside the new switch case (already handled above)
- [ ] Replace the old `.onChange(of: showCoffeeTypePicker)` body (~lines 219–230) with:
  ```swift
  .onChange(of: activeSheet) { old, new in
      // Coffee picker just dismissed
      if old == .coffeeTypePicker && new == nil {
          if let type = pendingCoffeeType {
              pendingCoffeeType = nil
              updateCoffeeForToday(cups: coffeeCups, type: type)
              showCoffeeWaterAlert = true
          } else {
              coffeeCups = max(0, coffeeCups - 1)
          }
      }
      // Journal sheet just dismissed
      if old == .journalEntry && new == nil {
          refreshTodayJournalState()
      }
  }
  ```
  - Verify: Build compiles with no references to `showCoffeeTypePicker` remaining. Run: `grep -n "showCoffeeTypePicker" "WellPlate/Features + UI/Home/Views/HomeView.swift"` — should return empty

### 6.4 — Wire Card Swap Logic

- [ ] Replace lines 86–90 (mood check-in section) with three-state conditional:
  ```swift
  // 4. Mood Check-In / Journal Reflection
  if !hasLoggedMoodToday {
      MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
          .padding(.horizontal, 16)
  } else if !hasJournaledToday {
      JournalReflectionCard(
          prompt: journalPromptService.currentPrompt,
          promptCategory: journalPromptService.promptCategory,
          entryText: $journalText,
          onSave: saveJournalEntry,
          onWriteMore: { activeSheet = .journalEntry },
          isGeneratingPrompt: journalPromptService.isGenerating
      )
      .padding(.horizontal, 16)
      .transition(.asymmetric(
          insertion: .move(edge: .bottom).combined(with: .opacity),
          removal: .opacity
      ))
  }
  ```
  - Verify: Three states work — `!hasLoggedMoodToday` → mood card, `logged && !journaled` → journal card, `logged && journaled` → empty slot
  - Note: Transitions animate because `hasLoggedMoodToday = true` is already inside `withAnimation` in `logMoodForTodayIfNeeded()` (line 532), and `hasJournaledToday = true` is inside `withAnimation` in `saveJournalEntry()` (Step 6.8)

### 6.5 — Add Header Journal Icon

- [ ] In `homeHeader` computed property (~line 326), add journal history button between the Calendar button and the Mood badge:
  ```swift
  // Journal history button
  Button {
      HapticService.impact(.light)
      showJournalHistory = true
  } label: {
      ZStack {
          Circle()
              .fill(LinearGradient(
                  colors: [AppColors.brand.opacity(0.65), AppColors.brand.opacity(0.65)],
                  startPoint: .topLeading, endPoint: .bottomTrailing
              ))
              .frame(width: 44, height: 44)
              .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)
          Image(systemName: "book.fill")
              .font(.system(size: 17, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
      }
  }
  .buttonStyle(.plain)
  ```
  - Verify: Header shows 4 icons — AI, Calendar, Journal, Mood badge (when logged)

### 6.6 — Add Navigation Destination

- [ ] Add after existing `.navigationDestination` modifiers (~line 175):
  ```swift
  .navigationDestination(isPresented: $showJournalHistory) {
      JournalHistoryView()
  }
  ```
  - Verify: Tapping book icon navigates to JournalHistoryView

### 6.7 — Add Lifecycle Methods

- [ ] Add `refreshTodayJournalState()` call in `.onAppear` block (after line 184, alongside existing refresh calls)
- [ ] Add new `.onChange(of: hasLoggedMoodToday)` modifier:
  ```swift
  .onChange(of: hasLoggedMoodToday) { _, logged in
      if logged {
          Task {
              await journalPromptService.generatePrompt(
                  mood: selectedMood,
                  stressLevel: todayWellnessLog?.stressLevel
              )
          }
      }
  }
  ```
- [ ] Add `refreshTodayJournalState()` to existing `.onChange(of: scenePhase)` block (~line 231):
  ```swift
  .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      refreshTodayMoodState()
      refreshTodayHydrationState()
      refreshTodayCoffeeState()
      refreshTodayJournalState()  // ← add this line
  }
  ```
  - Verify: No duplicate `.onChange` modifiers for the same property

### 6.8 — Add Helper Methods

<!-- RESOLVED: M1 — Animation context clarification added -->
- [ ] Add `refreshTodayJournalState()` method — **Note: this method intentionally does NOT use `withAnimation()` because it restores state on appear/scenePhase, not user-triggered transitions:**
  ```swift
  private func refreshTodayJournalState() {
      if let entry = todayJournalEntry {
          hasJournaledToday = true
          journalText = entry.text
      } else {
          hasJournaledToday = false
          journalText = ""
      }
      if hasLoggedMoodToday && !hasJournaledToday {
          Task {
              await journalPromptService.generatePrompt(
                  mood: selectedMood,
                  stressLevel: todayWellnessLog?.stressLevel
              )
          }
      }
  }
  ```
- [ ] Add `saveJournalEntry()` method — **Note: this method DOES use `withAnimation()` for the `hasJournaledToday` state change to animate the card removal transition:**
  ```swift
  private func saveJournalEntry() {
      let trimmed = journalText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      if let existing = todayJournalEntry {
          existing.text = trimmed
          existing.updatedAt = .now
      } else {
          let entry = JournalEntry(
              day: Date(),
              text: trimmed,
              moodRaw: selectedMood?.rawValue,
              promptUsed: journalPromptService.currentPrompt,
              stressScore: nil
          )
          modelContext.insert(entry)
      }
      do {
          try modelContext.save()
          HapticService.notify(.success)
          withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
              hasJournaledToday = true
          }
          activeSheet = nil  // Dismisses journal sheet if open
          WPLogger.home.info("Journal entry saved for today")
      } catch {
          WPLogger.home.error("Journal save failed: \(error.localizedDescription)")
      }
  }
  ```
  - Verify: Both methods compile without errors

### 6.9 — Update HomeView Preview

- [ ] Update the `#Preview("Home Dashboard")` block (~line 597) to include `JournalEntry.self`:
  ```swift
  let container = try! ModelContainer(
      for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, JournalEntry.self,
      configurations: config
  )
  ```
  - Verify: HomeView preview renders without crash in Xcode canvas

---

## Post-Implementation

### Build All 4 Targets

- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build`

### Functional Verification

- [ ] Fresh launch (no mood): only `MoodCheckInCard` visible — no journal card
- [ ] Log mood: card swap animation — mood card fades, journal card slides in with prompt
- [ ] Quick save from inline card: type text, tap Save → card disappears with animation, success haptic
- [ ] Write more: tap "Write more →" → full journal sheet opens with prompt + context
- [ ] Save from sheet: write text, tap Save → sheet dismisses (via `activeSheet = nil`), inline card gone
- [ ] X cancel from sheet: tap X → sheet dismisses (via `dismiss()`), journal card still visible
- [ ] Re-open (mood + journal logged): no mood card, no journal card — slot empty
- [ ] Re-open (mood logged, no journal): journal card reappears with prompt
- [ ] Journal history: tap book icon → history view with entries
- [ ] Empty history: shows empty state message
- [ ] Background/foreground: journal state refreshes correctly (no animation on restore)
- [ ] Coffee picker: still works after HomeSheet enum migration — type selection saves, water alert fires
<!-- RESOLVED: L1 — Coffee water alert timing explicitly tested -->
- [ ] Coffee water alert timing: alert appears only after coffee picker sheet fully dismissed (no overlap)
- [ ] Template fallback: prompts appear on non-Foundation-Models devices

### Git Commit

- [ ] Stage all new and modified files
- [ ] Commit with message describing the journal/gratitude feature
