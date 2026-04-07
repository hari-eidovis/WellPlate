# Implementation Plan: Journal / Gratitude Prompts Tied to Mood

**Date**: 2026-04-07
**Source**: `Docs/02_Planning/Specs/260407-journal-gratitude-strategy.md`
**Status**: Ready for Audit

## Overview

Add a daily journal/reflection feature to the Home screen that activates after the user logs their mood. An inline `JournalReflectionCard` replaces the dismissed `MoodCheckInCard` in the same slot, showing an AI-generated prompt with a quick text field. A "Write more" button opens a full `JournalEntryView` sheet. A header icon provides access to `JournalHistoryView` at any time. Foundation Models generates context-aware prompts on iOS 26+; a curated 50-prompt template library covers all other devices.

## Requirements

- R1: After mood check-in, show an inline journal card with an AI-generated prompt
- R2: Quick 1–2 line text entry directly in the inline card
- R3: "Write more" action opens a full journal entry sheet
- R4: Journal history accessible from header icon at all times
- R5: One `JournalEntry` per calendar day (SwiftData, `@Attribute(.unique)` on day)
- R6: Foundation Models prompt generation on iOS 26+ with template fallback
- R7: All journal data stays on-device (no cloud, no analytics)
- R8: Follow existing UI conventions (`.r()` fonts, `.appShadow()`, card styling, haptics)

## Architecture Changes

| Type | File | Change |
|------|------|--------|
| **New** | `WellPlate/Models/JournalEntry.swift` | SwiftData `@Model` for journal entries |
| **New** | `WellPlate/Core/Services/JournalPromptService.swift` | Foundation Models prompt gen + template fallback |
| **New** | `WellPlate/Features + UI/Home/Views/JournalReflectionCard.swift` | Inline card shown after mood check-in |
| **New** | `WellPlate/Features + UI/Home/Views/JournalEntryView.swift` | Full journal sheet with rich text area |
| **New** | `WellPlate/Features + UI/Home/Views/JournalHistoryView.swift` | Past entries list with mood badges |
| **Modify** | `WellPlate/App/WellPlateApp.swift` | Add `JournalEntry.self` to model container |
| **Modify** | `WellPlate/Features + UI/Home/Views/HomeView.swift` | Card swap logic, state, navigation, header icon |

## Implementation Steps

### Phase 1: Data Layer

#### Step 1. Create `JournalEntry` SwiftData Model
**File**: `WellPlate/Models/JournalEntry.swift` (new)

Create the `@Model` class following the `StressReading` / `InterventionSession` pattern:

```swift
import Foundation
import SwiftData

@Model
final class JournalEntry {
    @Attribute(.unique) var day: Date       // Calendar.startOfDay — one per day
    var text: String                         // User's journal text
    var moodRaw: Int?                        // Snapshot of MoodOption.rawValue at write time
    var promptUsed: String?                  // The prompt shown (nil if free-form)
    var stressScore: Double?                 // Snapshot of today's stress score
    var createdAt: Date
    var updatedAt: Date

    init(
        day: Date,
        text: String = "",
        moodRaw: Int? = nil,
        promptUsed: String? = nil,
        stressScore: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.day = Calendar.current.startOfDay(for: day)
        self.text = text
        self.moodRaw = moodRaw
        self.promptUsed = promptUsed
        self.stressScore = stressScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var mood: MoodOption? {
        guard let raw = moodRaw else { return nil }
        return MoodOption(rawValue: raw)
    }
}
```

- **Why**: Separate model from `WellnessDayLog` — journal entries are richer and may evolve independently. Linked by `day` (same `startOfDay` convention).
- **Dependencies**: None
- **Risk**: Low

#### Step 2. Register `JournalEntry` in ModelContainer
**File**: `WellPlate/App/WellPlateApp.swift` (line 34)

Add `JournalEntry.self` to the `.modelContainer(for:)` array:

```swift
.modelContainer(for: [
    FoodCache.self, FoodLogEntry.self, WellnessDayLog.self,
    UserGoals.self, StressReading.self, StressExperiment.self,
    InterventionSession.self, FastingSchedule.self, FastingSession.self,
    JournalEntry.self   // ← add
])
```

- **Why**: SwiftData requires all models registered at container creation
- **Dependencies**: Step 1
- **Risk**: Low — additive schema change, no migration needed

---

### Phase 2: Service Layer

#### Step 3. Create `JournalPromptService`
**File**: `WellPlate/Core/Services/JournalPromptService.swift` (new)

Follow the `StressInsightService` pattern exactly:

**Class structure:**
```swift
@MainActor
final class JournalPromptService: ObservableObject {
    @Published var currentPrompt: String?
    @Published var promptCategory: String?
    @Published var isGenerating: Bool = false

    func generatePrompt(mood: MoodOption?, stressLevel: String?) async { ... }
}
```

**Foundation Models integration (iOS 26+):**
- `#if canImport(FoundationModels)` guard
- `@available(iOS 26, *)` on the generation method
- Check `SystemLanguageModel.default.availability` — return nil if not `.available`
- Create `LanguageModelSession()`, call `session.respond(to:generating:)`
- On failure, fall back to template

**@Generable schema:**
```swift
#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _JournalPromptSchema {
    @Guide(description: "A warm, specific 1–2 sentence journal prompt. No medical language. Encourage reflection, not fixing.")
    var prompt: String

    @Guide(description: "Single-word category: gratitude, reflection, awareness, or intention")
    var category: String
}
#endif
```

**Prompt construction:**
Build a natural-language prompt from context signals:
- Current mood (emoji + label)
- Today's stress level (if available from `WellnessDayLog`)
- Time of day (morning/afternoon/evening)
- Instruction: "Generate a warm, non-clinical journal prompt for someone feeling [mood]. It's [time of day]. Their stress level is [level]. The prompt should encourage gentle self-reflection, not problem-solving."

**Template fallback library:**
Organize ~50 prompts indexed by:
- Mood tier: `awful/bad` (tier 1), `okay` (tier 2), `good/great` (tier 3)
- Time of day: morning, afternoon, evening
- Category: gratitude, reflection, awareness, intention

Structure as a static dictionary:
```swift
private static let templates: [MoodTier: [TimeOfDay: [String]]] = [
    .low: [
        .morning: [
            "What's one small thing you can look forward to today?",
            "If you could give yourself permission for one thing today, what would it be?",
            ...
        ],
        .afternoon: [...],
        .evening: [...]
    ],
    .neutral: [...],
    .high: [...]
]
```

Select randomly from the matching bucket. Use `stressLevel` as a secondary signal to prefer certain categories (high stress → awareness/intention prompts; low stress → gratitude prompts).

- **Why**: Follows proven Foundation Models pattern from `StressInsightService`; template fallback ensures feature works on all devices
- **Dependencies**: None (uses `MoodOption` which already exists)
- **Risk**: Low — no network, no external dependencies

---

### Phase 3: UI — Inline Card

#### Step 4. Create `JournalReflectionCard`
**File**: `WellPlate/Features + UI/Home/Views/JournalReflectionCard.swift` (new)

A compact card (~120pt tall) that appears in the mood check-in slot after mood is logged. Follows `MoodCheckInCard` styling conventions.

**Layout:**
```
┌─────────────────────────────────────┐
│ 📖  Daily Reflection                │
│                                     │
│ "What's one thing you're grateful   │
│  for right now?"                    │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Write something...              │ │
│ └─────────────────────────────────┘ │
│                                     │
│ [Save]              [Write more →]  │
└─────────────────────────────────────┘
```

**Props / bindings:**
```swift
struct JournalReflectionCard: View {
    let prompt: String?
    let promptCategory: String?
    @Binding var entryText: String
    var onSave: () -> Void
    var onWriteMore: () -> Void
    var isGeneratingPrompt: Bool
}
```

**Styling:**
- Background: `RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground))` with a subtle gradient overlay (warm tones matching mood card)
- Shadow: `.shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)` — matching `MoodCheckInCard`
- Font: `.system(size:weight:design: .rounded)` — matching existing Home cards
- Text field: 2-line `TextField` with `.axis(.vertical)` and `lineLimit(2...4)` for inline, rounded border
- Prompt text: italic, secondary color, 14pt
- Category badge: small capsule with category name (gratitude/reflection/etc.)
- Save button: filled capsule with `AppColors.brand`
- "Write more →" link: trailing, subtle brand color

**Animations:**
- Card entrance: `.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))`
- Save confirmation: brief checkmark animation, then card compacts to a "Journal logged" pill

**States:**
1. **Prompt loading**: Shimmer placeholder while `isGeneratingPrompt` is true
2. **Ready**: Prompt shown, text field empty
3. **Typing**: Text field active, Save button enabled
4. **Saved**: Compact "Journaled today ✓" pill (similar pattern to mood badge)

- **Why**: Progressive disclosure — catches users at peak reflection; doesn't require navigation
- **Dependencies**: Step 3 (prompt service)
- **Risk**: Low

---

### Phase 4: UI — Full Journal Sheet

#### Step 5. Create `JournalEntryView`
**File**: `WellPlate/Features + UI/Home/Views/JournalEntryView.swift` (new)

Full sheet for deeper reflection. Presented via `.sheet(isPresented:)`.

**Layout:**
```
┌─────────────────────────────────────┐
│ ✕  Daily Journal          [Save]    │
│─────────────────────────────────────│
│                                     │
│ 😊 Good  ·  Stress: Moderate       │
│ Tuesday, April 7                    │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ "What's one thing you're        │ │
│ │  grateful for right now?"       │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │                                 │ │
│ │ [Large text editor area]        │ │
│ │                                 │ │
│ │                                 │ │
│ └─────────────────────────────────┘ │
│                                     │
│ [🔄 New prompt]                     │
│                                     │
│ 127 characters                      │
└─────────────────────────────────────┘
```

**Props:**
```swift
struct JournalEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let mood: MoodOption?
    let stressLevel: String?
    @Binding var entryText: String
    let prompt: String?
    @ObservedObject var promptService: JournalPromptService
    var onSave: () -> Void
}
```

**Features:**
- Context header: mood emoji + label, stress level pill, date
- Prompt card: shown at top, tappable "New prompt" to regenerate
- Text editor: `TextEditor` with placeholder text, grows to fill available space
- Character count: subtle footer
- Save button: in navigation bar trailing position, disabled when text is empty
- Dismiss: X button or swipe-to-dismiss
- Keyboard handling: `.scrollDismissesKeyboard(.interactively)`

**Presentation detents:** `.presentationDetents([.large])` — full sheet for focus

- **Why**: Gives depth when users want it; progressive disclosure from inline card
- **Dependencies**: Steps 3, 4
- **Risk**: Low

---

### Phase 5: UI — Journal History

#### Step 6. Create `JournalHistoryView`
**File**: `WellPlate/Features + UI/Home/Views/JournalHistoryView.swift` (new)

Chronological list of past journal entries, accessible from header icon. Presented as a `navigationDestination`.

**Layout:**
```
┌─────────────────────────────────────┐
│ ←  Journal History                  │
│─────────────────────────────────────│
│                                     │
│ Today                               │
│ ┌─────────────────────────────────┐ │
│ │ 😊 Good                        │ │
│ │ "I'm grateful for the quiet     │ │
│ │  morning coffee before..."      │ │
│ │                        10:32 AM │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Yesterday                           │
│ ┌─────────────────────────────────┐ │
│ │ 😐 Okay                        │ │
│ │ "Work was stressful but I       │ │
│ │  managed to take a walk..."     │ │
│ │                         8:15 PM │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ...more entries...                  │
└─────────────────────────────────────┘
```

**Data source:**
```swift
@Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
```

**Features:**
- Entries grouped by relative date (Today, Yesterday, then date strings)
- Each entry card: mood emoji + label, truncated text (3 lines), timestamp
- Tap to expand: shows full text inline (no navigation)
- Empty state: illustration + "Start your first journal entry" message
- Swipe to delete: `.onDelete` with confirmation

**Styling:**
- Cards: `RoundedRectangle(cornerRadius: 16)`, lighter shadow than main cards
- Mood badge: small colored pill with emoji (reuse `MoodOption.accentColor`)
- Text: `.r(.body, .regular)`, secondary color for timestamps

- **Why**: Users need to review past reflections; simple chronological list for MVP
- **Dependencies**: Step 1
- **Risk**: Low

---

### Phase 6: Integration — HomeView Wiring

#### Step 7. Add Journal State & Services to HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Add state variables** (after existing `@State` declarations, around line 35):
```swift
@State private var journalText: String = ""
@State private var hasJournaledToday = false
@State private var showJournalSheet = false
@State private var showJournalHistory = false
@StateObject private var journalPromptService = JournalPromptService()
```

**Add journal entry query** (after existing `@Query` declarations, around line 13):
```swift
@Query private var allJournalEntries: [JournalEntry]
```

**Add computed property** for today's journal entry:
```swift
private var todayJournalEntry: JournalEntry? {
    allJournalEntries.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
}
```

- **Dependencies**: Steps 1–6
- **Risk**: Low

#### Step 8. Wire Card Swap Logic in HomeView Body
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift` (lines 86–90)

Replace the current mood section:

**Current** (lines 86–90):
```swift
// 4. Mood Check-In
if !hasLoggedMoodToday {
    MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
        .padding(.horizontal, 16)
}
```

**New:**
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
        onWriteMore: { showJournalSheet = true },
        isGeneratingPrompt: journalPromptService.isGenerating
    )
    .padding(.horizontal, 16)
    .transition(.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .opacity
    ))
}
```

The three states for the slot:
1. `!hasLoggedMoodToday` → `MoodCheckInCard`
2. `hasLoggedMoodToday && !hasJournaledToday` → `JournalReflectionCard`
3. `hasLoggedMoodToday && hasJournaledToday` → nothing (slot empty; mood badge in header is sufficient)

- **Dependencies**: Steps 4, 7
- **Risk**: Low — conditional rendering in existing slot

#### Step 9. Add Header Journal Icon
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift` (in `homeHeader`, around line 326)

Add a journal history button between the Calendar button and the Mood badge:

```swift
// Journal history button
Button {
    HapticService.impact(.light)
    showJournalHistory = true
} label: {
    ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.brand.opacity(0.65),
                        AppColors.brand.opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
            .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)

        Image(systemName: "book.fill")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}
.buttonStyle(.plain)
```

- **Dependencies**: Step 7
- **Risk**: Low — follows exact pattern of AI Insights and Calendar buttons

#### Step 10. Add Navigation Destinations & Sheet
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift` (after existing `.navigationDestination` modifiers, around line 175)

```swift
.navigationDestination(isPresented: $showJournalHistory) {
    JournalHistoryView()
}
.sheet(isPresented: $showJournalSheet) {
    JournalEntryView(
        mood: selectedMood,
        stressLevel: todayWellnessLog?.stressLevel,
        entryText: $journalText,
        prompt: journalPromptService.currentPrompt,
        promptService: journalPromptService,
        onSave: saveJournalEntry
    )
}
```

- **Dependencies**: Steps 5, 6, 7
- **Risk**: Low

#### Step 11. Add Journal Lifecycle Methods to HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Add to `.onAppear` block** (after line 184):
```swift
refreshTodayJournalState()
```

**Add trigger for prompt generation** — in the `.onChange(of: hasLoggedMoodToday)` block (or a new one):
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

**Add helper methods:**
```swift
private func refreshTodayJournalState() {
    if let entry = todayJournalEntry {
        hasJournaledToday = true
        journalText = entry.text
    } else {
        hasJournaledToday = false
        journalText = ""
    }
    // If mood is already logged and no journal yet, generate a prompt
    if hasLoggedMoodToday && !hasJournaledToday {
        Task {
            await journalPromptService.generatePrompt(
                mood: selectedMood,
                stressLevel: todayWellnessLog?.stressLevel
            )
        }
    }
}

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
            stressScore: nil // Could fetch from StressReading if available
        )
        modelContext.insert(entry)
    }

    do {
        try modelContext.save()
        HapticService.notify(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            hasJournaledToday = true
        }
        WPLogger.home.info("Journal entry saved for today")
    } catch {
        WPLogger.home.error("Journal save failed: \(error.localizedDescription)")
    }
}
```

**Handle sheet dismiss — reload state** (add after the journal sheet modifier):
```swift
.onChange(of: showJournalSheet) { _, showing in
    if !showing { refreshTodayJournalState() }
}
```

- **Dependencies**: Steps 7–10
- **Risk**: Low–Medium — most complex step but follows established patterns

---

### Phase 7: Build Verification

#### Step 12. Build All Targets
Run all 4 build commands from CLAUDE.md:

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

Fix any compilation errors before marking complete.

- **Dependencies**: All previous steps
- **Risk**: Low — all changes follow existing patterns

## Testing Strategy

### Build Verification
- All 4 targets compile cleanly (main app + 3 extensions)

### Manual Verification Flows
1. **Fresh launch (no mood logged)**: Home shows `MoodCheckInCard` — no journal card visible
2. **Log mood**: Card swap animation — `MoodCheckInCard` fades, `JournalReflectionCard` slides in with a prompt
3. **Quick save**: Type 1 line in inline card, tap Save → card disappears with animation, mood badge in header
4. **Write more**: Tap "Write more →" → full sheet opens with prompt, mood context, text editor
5. **Save from sheet**: Write text, tap Save → sheet dismisses, inline card disappears
6. **Re-open app (mood + journal already logged)**: No mood card, no journal card — slot is empty
7. **Re-open app (mood logged, no journal)**: Journal card appears with a prompt
8. **Journal history**: Tap book icon in header → history view with past entries
9. **Empty history**: First launch with no entries → empty state message
10. **Edit existing entry**: Return to app same day, journal card shows saved text for editing
11. **Foundation Models unavailable**: Template prompt appears immediately (no loading delay)

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Home scroll depth increases | Low | Card **replaces** mood card slot rather than stacking below it |
| Foundation Models not available on dev device | Medium | Template fallback is first-class; test with `#if canImport(FoundationModels)` compile-time guard |
| Card swap animation jank | Low | Use `.animation(.spring(...), value:)` on the conditional group, test on device |
| SwiftData lightweight migration | Low | New model with no relationships — no migration needed |
| Template prompt fatigue over weeks | Low | ~50 prompts across 3 mood tiers × 3 times of day; Foundation Models generates unique prompts on supported devices |
| Keyboard overlaps inline text field | Low | `.scrollDismissesKeyboard(.interactively)` already set on Home scroll view |

## Success Criteria

- [ ] After mood check-in, journal card appears with a contextual prompt
- [ ] User can save a quick 1–2 line entry from the inline card
- [ ] "Write more" opens a full sheet with text editor and mood/stress context
- [ ] Journal history shows all past entries with mood badges
- [ ] Foundation Models generates prompts on iOS 26+ devices
- [ ] Template fallback prompts appear on unsupported devices
- [ ] All 4 build targets compile cleanly
- [ ] Card swap animation is smooth (no layout jumps)
- [ ] One entry per day enforced (editing updates existing entry)
- [ ] App state is correct after backgrounding and returning
