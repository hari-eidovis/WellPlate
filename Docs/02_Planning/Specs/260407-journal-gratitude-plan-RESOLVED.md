# Implementation Plan: Journal / Gratitude Prompts Tied to Mood

**Date**: 2026-04-07
**Source**: `Docs/02_Planning/Specs/260407-journal-gratitude-strategy.md`
**Status**: RESOLVED — Ready for Checklist

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| H1 — HomeView preview crash (missing JournalEntry in ModelContainer) | HIGH | **FIXED** — Step 7 now includes explicit preview ModelContainer update |
| H2 — Missing scenePhase refresh for journal state | HIGH | **FIXED** — Step 11 now includes `.onChange(of: scenePhase)` addition |
| M1 — Second `.sheet()` violates CLAUDE.md convention | MEDIUM | **FIXED** — Step 7+10 now introduce `HomeSheet` enum consolidating all sheets |
| M2 — JournalPromptService doesn't need bindContext | MEDIUM | **FIXED** — Step 3 now explicitly states no ModelContext/bindContext needed |
| M3 — Font convention inconsistency | MEDIUM | **FIXED** — R8 + Steps 4/5/6 now specify `.system(size:weight:design:.rounded)` to match HomeView |
| L1 — No accessibility mentions | LOW | **ACKNOWLEDGED** — Added accessibility note to Steps 4, 5, 6 |
| L2 — No character limit on journal text | LOW | **ACKNOWLEDGED** — Added soft limit note to Step 5 |
| L3 — Template prompt randomness could repeat | LOW | **FIXED** — Step 3 now uses last-prompt exclusion via UserDefaults |
| L4 — JournalEntryView save duplication risk | LOW | **FIXED** — Step 5 now removes `@Environment(\.modelContext)`, save exclusively via onSave callback |

---

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
- R8: Follow existing UI conventions — `.system(size:weight:design:.rounded)` fonts (matching HomeView actual convention), `.appShadow()`, card styling, haptics
<!-- RESOLVED: M3 — R8 now specifies .system() font convention to match HomeView's actual code, not .r() from CLAUDE.md -->

## Architecture Changes

| Type | File | Change |
|------|------|--------|
| **New** | `WellPlate/Models/JournalEntry.swift` | SwiftData `@Model` for journal entries |
| **New** | `WellPlate/Core/Services/JournalPromptService.swift` | Foundation Models prompt gen + template fallback |
| **New** | `WellPlate/Features + UI/Home/Views/JournalReflectionCard.swift` | Inline card shown after mood check-in |
| **New** | `WellPlate/Features + UI/Home/Views/JournalEntryView.swift` | Full journal sheet with rich text area |
| **New** | `WellPlate/Features + UI/Home/Views/JournalHistoryView.swift` | Past entries list with mood badges |
| **Modify** | `WellPlate/App/WellPlateApp.swift` | Add `JournalEntry.self` to model container |
| **Modify** | `WellPlate/Features + UI/Home/Views/HomeView.swift` | Card swap logic, state, `HomeSheet` enum, navigation, header icon, scenePhase refresh |

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

<!-- RESOLVED: M2 — Explicitly states this service does NOT need ModelContext or bindContext -->

**Important**: Unlike `StressInsightService`, this service does **NOT** need `ModelContext` or a `bindContext()` method. All context (mood, stress level) is passed in via `generatePrompt()` parameters. This is a stateless prompt generator, not a data-fetching service.

**Class structure:**
```swift
@MainActor
final class JournalPromptService: ObservableObject {
    @Published var currentPrompt: String?
    @Published var promptCategory: String?
    @Published var isGenerating: Bool = false

    /// No bindContext() needed — all data passed via parameters.
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

<!-- RESOLVED: L3 — Template selection now excludes last-used prompt to prevent consecutive repeats -->
**Template selection with dedup:** Store the last-used prompt key in `UserDefaults` (`"journalLastPromptIndex"`). When selecting from the matching bucket, exclude the last-used index. If only one prompt in bucket, allow repeat.

Select from the matching bucket excluding last-used. Use `stressLevel` as a secondary signal to prefer certain categories (high stress → awareness/intention prompts; low stress → gratitude prompts).

- **Why**: Follows proven Foundation Models pattern from `StressInsightService`; template fallback ensures feature works on all devices. No ModelContext needed — simpler than StressInsightService.
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

<!-- RESOLVED: M3 — Font convention explicitly set to .system() matching HomeView -->
**Styling:**
- Background: `RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground))` with a subtle gradient overlay (warm tones matching mood card)
- Shadow: `.shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)` — matching `MoodCheckInCard`
- Font: `.system(size:weight:design:.rounded)` — matching HomeView's actual convention (not `.r()`)
- Text field: 2-line `TextField` with `.axis(.vertical)` and `lineLimit(2...4)` for inline, rounded border
- Prompt text: italic, secondary color, `.system(size: 14, weight: .regular, design: .rounded)`
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
4. **Saved**: Compact "Journaled today" pill (similar pattern to mood badge)

<!-- RESOLVED: L1 — Accessibility note added -->
**Accessibility:** Add `.accessibilityLabel()` to the prompt text, Save button, and "Write more" link. Ensure the text field has a clear accessibility hint.

- **Why**: Progressive disclosure — catches users at peak reflection; doesn't require navigation
- **Dependencies**: Step 3 (prompt service)
- **Risk**: Low

---

### Phase 4: UI — Full Journal Sheet

#### Step 5. Create `JournalEntryView`
**File**: `WellPlate/Features + UI/Home/Views/JournalEntryView.swift` (new)

Full sheet for deeper reflection. Presented via `HomeSheet.journalEntry`.

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
│ 127 / 2000 characters              │
└─────────────────────────────────────┘
```

<!-- RESOLVED: L4 — Removed @Environment(\.modelContext). Save exclusively via onSave callback from HomeView -->
**Props:**
```swift
struct JournalEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let mood: MoodOption?
    let stressLevel: String?
    @Binding var entryText: String
    let prompt: String?
    @ObservedObject var promptService: JournalPromptService
    var onSave: () -> Void
}
```

**Note**: No `@Environment(\.modelContext)` — this view does NOT save directly. All persistence is handled by HomeView via the `onSave` callback. This prevents duplicate save paths and keeps save logic centralized.

**Features:**
- Context header: mood emoji + label, stress level pill, date
- Prompt card: shown at top, tappable "New prompt" to regenerate
- Text editor: `TextEditor` with placeholder text, grows to fill available space
- Character count: subtle footer showing current / 2000 limit
- Save button: in navigation bar trailing position, disabled when text is empty
- Dismiss: X button or swipe-to-dismiss
- Keyboard handling: `.scrollDismissesKeyboard(.interactively)`
- Font: `.system(size:weight:design:.rounded)` matching HomeView convention

<!-- RESOLVED: L2 — Soft character limit added -->
**Character limit:** Soft limit of 2000 characters. Show count in footer as `"127 / 2000"`. When approaching limit (>1800), change count color to `.warning`. Do not hard-block input — just visual indicator.

**Presentation detents:** `.presentationDetents([.large])` — full sheet for focus

<!-- RESOLVED: L1 — Accessibility note added -->
**Accessibility:** Add `.accessibilityLabel()` to mood context header, prompt text, and save button. Ensure text editor is properly labeled for VoiceOver.

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
- Font: `.system(size:weight:design:.rounded)` matching HomeView convention
- Timestamps: secondary color

<!-- RESOLVED: L1 — Accessibility note added -->
**Accessibility:** Entry cards should have meaningful `.accessibilityLabel()` combining mood and text snippet. Delete action should have `.accessibilityHint()`.

- **Why**: Users need to review past reflections; simple chronological list for MVP
- **Dependencies**: Step 1
- **Risk**: Low

---

### Phase 6: Integration — HomeView Wiring

#### Step 7. Add Journal State, HomeSheet Enum & Services to HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

<!-- RESOLVED: M1 — Introduced HomeSheet enum to consolidate all sheet presentations into a single .sheet(item:) -->
**Add `HomeSheet` enum** (above `HomeView` struct, or as a nested type):
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
}
```

**Replace** the existing `@State private var showCoffeeTypePicker = false` and `@State private var showJournalSheet = false` **with**:
```swift
@State private var activeSheet: HomeSheet?
```

**Add remaining state variables** (after existing `@State` declarations, around line 35):
```swift
@State private var journalText: String = ""
@State private var hasJournaledToday = false
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

<!-- RESOLVED: H1 — HomeView preview now includes JournalEntry.self in ModelContainer -->
**Update HomeView preview** (lines 597–605) to include `JournalEntry.self`:
```swift
#Preview("Home Dashboard") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, JournalEntry.self,
        configurations: config
    )
    return HomeView(selectedTab: .constant(0))
        .modelContainer(container)
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

#### Step 10. Consolidate Sheets & Add Navigation Destinations
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

<!-- RESOLVED: M1 — Single .sheet(item:) replaces all boolean-driven .sheet() modifiers -->

**Replace** the existing `.sheet(isPresented: $showCoffeeTypePicker)` modifier (line 238) **with** a single enum-driven sheet:

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

**Update coffee type picker trigger** — everywhere `showCoffeeTypePicker = true` appears, replace with `activeSheet = .coffeeTypePicker`. And everywhere `showCoffeeTypePicker = false` appears (in dismiss), replace with `activeSheet = nil`.

**Add journal history navigation destination** (after existing `.navigationDestination` modifiers, around line 175):
```swift
.navigationDestination(isPresented: $showJournalHistory) {
    JournalHistoryView()
}
```

**Update `.onChange(of: showCoffeeTypePicker)`** — this onChange watches the old boolean. Replace with `.onChange(of: activeSheet)` checking for nil after coffee picker was active:
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

- **Dependencies**: Steps 5, 6, 7
- **Risk**: Medium — refactors existing coffee picker sheet, needs careful testing of coffee flow

#### Step 11. Add Journal Lifecycle Methods to HomeView
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Add to `.onAppear` block** (after line 184):
```swift
refreshTodayJournalState()
```

**Add trigger for prompt generation** — new `.onChange`:
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

<!-- RESOLVED: H2 — scenePhase refresh now includes journal state -->
**Update existing `.onChange(of: scenePhase)` block** (line 231) to include journal refresh:
```swift
.onChange(of: scenePhase) { _, phase in
    guard phase == .active else { return }
    refreshTodayMoodState()
    refreshTodayHydrationState()
    refreshTodayCoffeeState()
    refreshTodayJournalState()  // ← add
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
        // Dismiss journal sheet if open
        activeSheet = nil
        WPLogger.home.info("Journal entry saved for today")
    } catch {
        WPLogger.home.error("Journal save failed: \(error.localizedDescription)")
    }
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
12. **Background/foreground cycle**: Journal state refreshes correctly when returning from background
13. **Coffee picker still works**: Verify coffee type picker sheet presents and dismisses correctly after `HomeSheet` enum migration

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Home scroll depth increases | Low | Card **replaces** mood card slot rather than stacking below it |
| Foundation Models not available on dev device | Medium | Template fallback is first-class; test with `#if canImport(FoundationModels)` compile-time guard |
| Card swap animation jank | Low | Use `.animation(.spring(...), value:)` on the conditional group, test on device |
| SwiftData lightweight migration | Low | New model with no relationships — no migration needed |
| Template prompt fatigue over weeks | Low | ~50 prompts with last-used exclusion; Foundation Models generates unique prompts on supported devices |
| Keyboard overlaps inline text field | Low | `.scrollDismissesKeyboard(.interactively)` already set on Home scroll view |
| HomeSheet enum migration breaks coffee flow | Medium | Test coffee picker flow thoroughly after migration (manual test #13) |
| Header overflow on small screens | Low | 4 icons × 44pt + spacing ≈ 220pt; iPhone SE (375pt) should fit with compressed greeting text. Test on SE simulator |

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
- [ ] Coffee type picker sheet still works after HomeSheet enum migration
- [ ] HomeView preview renders without crash
