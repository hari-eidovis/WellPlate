# AI Features Integration — WellPlate
**Date:** 2026-03-01  
**Session scope:** Foundation Models · AVFoundation TTS · Haptics

---

## Overview

Three new features were planned, audited, and implemented across this session:

| #   | Feature                                           | Tech                                           |
| --- | ------------------------------------------------- | ---------------------------------------------- |
| 1   | **AI Daily Nutrition Narrative + TTS Read-Aloud** | FoundationModels + AVSpeechSynthesizer         |
| 2   | **Conversational Meal Coach**                     | FoundationModels (input canonicalization)      |
| 3   | **Smart Food Disambiguation Chips**               | FoundationModels (option generation) + Haptics |

All three features degrade gracefully on iOS < 26 or unsupported devices — no crashes, no empty states.

---

## Pre-Flight Changes

### `Package.swift`
- Bumped platform target from `.iOS(.v16)` → **`.iOS(.v18_1)`**
- Required minimum for `FoundationModels` framework availability

### `Core/Services/HapticService.swift`
Added two new named compound haptic patterns:

```swift
static func narratorStart()
// Two light impacts 100ms apart — fires when TTS narration begins

static func goalAchieved()
// success notification + 3× rigid pulses at 150ms intervals — fires on goal completion
```

---

## Feature 1 · AI Daily Nutrition Narrative + TTS

### New: `Core/Services/NutritionNarratorService.swift`

`@MainActor final class` (owns `AVSpeechSynthesizer` — main thread required).

**Key design decisions:**
- `@Generable struct NutritionNarrative` (iOS 26+) structures model output to a single `summary: String`
- Tiered voice selection: `.premium` → `.enhanced` → `.default` (system fallback)
- `showVoiceNudge: Bool` published if only `.default` quality voice is available, nudging user to `Settings → Accessibility → Live Speech`
- Deterministic template narrative fallback for iOS < 26 (calorie diff, protein %, fiber check)
- `AVSpeechSynthesizerDelegate` methods are `nonisolated`, bridged back to `@MainActor` via `Task { @MainActor in ... }`
- Second tap while speaking → `stop()` (toggle behaviour)

**Availability guard pattern used throughout:**
```swift
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26, *)
private func generateWithFoundationModels(...) async throws -> String { ... }
```

**Published state:**
```swift
@Published var isSpeaking: Bool
@Published var isGenerating: Bool
@Published var showVoiceNudge: Bool
```

---

### New: `Shared/Components/NarratorButton.swift`

Stateless SwiftUI button driven entirely by external props:

| State      | Visual                                                                      |
| ---------- | --------------------------------------------------------------------------- |
| Idle       | `waveform` icon on secondary background                                     |
| Generating | `ProgressView` spinner                                                      |
| Speaking   | `waveform` with `.variableColor.iterative` symbolEffect + pulsing glow ring |

The glow ring is a `Circle` stroke with `scaleEffect` + `opacity` animation that repeats `forever`.

---

### Modified: `Features + UI/Home/Views/HomeView.swift` (Feature 1 additions)

- `@StateObject private var narrator = NutritionNarratorService()` added at class level
- `NarratorButton` rendered **above `GoalsExpandableView`** — only when `aggregatedNutrition != nil`
- Voice nudge banner rendered above `NarratorButton` — only when `narrator.showVoiceNudge == true` and food is logged

---

## Feature 2 · Conversational Meal Coach

### New: `Core/Services/MealCoachService.swift`

Plain `final class` (no `@MainActor` — only calls async FoundationModels APIs, no UI or AVFoundation).

**Internal `@Generable` schema (private to file):**
```swift
@available(iOS 26, *)
@Generable
private struct _FoodExtractionSchema {
    @Guide(description: "Canonical food name") var foodName: String
    @Guide(description: "Serving size, or 'unknown'") var portion: String
    @Guide(description: "Confidence 0.0 to 1.0") var confidence: Double
    @Guide(description: "Clarifying question, or empty string") var clarifyingQuestion: String
}
```

> **Audit fix #3 applied:** `String?` Optionals replaced with sentinel strings (`"unknown"`, `""`) — `@Generable` doesn't support Optional properties reliably.

**Public APIs:**
```swift
func extractFoodEntry(from rawInput: String) async -> FoodExtraction
func generateOptions(for ambiguousInput: String) async -> [FoodOption]
```

Both fall back silently on unsupported devices (`FoodExtraction.passthrough(rawInput)` / `[]`).

---

### New domain model: `FoodExtraction` (defined in `MealCoachService.swift`)

```swift
struct FoodExtraction {
    let foodName: String        // canonical name
    let portion: String         // "unknown" if not specified
    let confidence: Double      // 0–1
    let clarifyingQuestion: String  // empty if confident
    var needsDisambiguation: Bool   // confidence < 0.6 && question non-empty
}
```

### New domain model: `DisambiguationState` (defined in `MealCoachService.swift`)

```swift
struct DisambiguationState {
    let question: String
    let options: [FoodOption]
    let rawInput: String
}
```

---

### Modified: `Features + UI/Home/ViewModels/HomeViewModel.swift`

**New published property:**
```swift
@Published var disambiguationState: DisambiguationState?
```

**Updated `init`:**
```swift
init(
    modelContext: ModelContext,
    nutritionService: NutritionServiceProtocol = NutritionService(),
    mealCoach: MealCoachService = MealCoachService()   // ← new
)
```

**Updated `logFood(on:coachOverride:)` flow:**

```
Raw input
  ↓
MealCoachService.extractFoodEntry()   [async, falls back on iOS < 26]
  ↓
confidence < 0.6 + question non-empty?
  ├─ YES → generateOptions() → publish disambiguationState → return early
  └─ NO  → use extraction.foodName as canonical name
             ↓
           normalizeFoodKey(canonicalName)   ← audit fix #7: key from coach name, not typed input
             ↓
           cache lookup → API call → persist
```

**Modified: `HomeView.swift` (Feature 2)**
- `sparkles` submit button now has `.symbolEffect(.breathe, isActive: viewModel.isLoading)` — pulses while coach is running

---

## Feature 3 · Smart Food Disambiguation Chips

### New: `Features + UI/Home/FoodOption.swift`

```swift
struct FoodOption: Identifiable {
    let id: UUID
    let label: String           // "Thin-crust pizza slice"
    let calorieEstimate: Int    // 220
}
```

> **Audit fix #9 applied:** Plain struct, no `@Generable`. Lives in the Feature layer, not `Models/`, to avoid polluting the domain model layer with a FoundationModels compile-time dependency. The `@Generable`-annotated counterpart (`_FoodOptionSchema`) is private inside `MealCoachService`.

---

### New: `Features + UI/Home/Views/DisambiguationChipsView.swift`

Bottom-sheet overlay with spring animation (`response: 0.45, dampingFraction: 0.78`).

**Props:**
```swift
let question: String
let options: [FoodOption]
let rawInput: String
let onSelect: (FoodOption) -> Void
let onAddAsTyped: () -> Void      // ← audit fix #8: escape hatch
```

**UX details:**
- Semi-transparent `.black.opacity(0.18)` scrim on background
- Each chip: `label` left-aligned + `~calorieEstimate kcal` Capsule badge
- Chip tap → `HapticService.selectionChanged()` → `onSelect`
- "Add as typed" button → `HapticService.impact(.light)` → `onAddAsTyped`
- Sheet springs up from `y: 300` offset on appear

---

### Modified: `Features + UI/Home/Views/HomeView.swift` (Feature 3)

`DisambiguationChipsView` wired as a `ZStack` overlay at `zIndex: 10`:

```swift
if let state = viewModel.disambiguationState {
    DisambiguationChipsView(
        question: state.question,
        options: state.options,
        rawInput: state.rawInput,
        onSelect: { option in
            viewModel.disambiguationState = nil
            Task { await viewModel.logFood(on: selectedDate, coachOverride: option.label) ... }
        },
        onAddAsTyped: {
            viewModel.disambiguationState = nil
            Task { await viewModel.logFood(on: selectedDate, coachOverride: state.rawInput) ... }
        }
    )
    .transition(.opacity)
    .zIndex(10)
}
```

---

## Audit Issues Resolved

| #   | Issue                                     | Resolution                                                             |
| --- | ----------------------------------------- | ---------------------------------------------------------------------- |
| 1   | Platform target iOS 16                    | Bumped `Package.swift` to `.v18_1`                                     |
| 2   | FoundationModels is Xcode 26 beta API     | `#if canImport(FoundationModels)` + `@available(iOS 26, *)` throughout |
| 3   | `String?` in `@Generable` structs         | Replaced with sentinel strings (`"unknown"`, `""`)                     |
| 4   | `actor` + AVFoundation crash              | Services are `@MainActor final class` or plain `final class`           |
| 5   | `.enhanced` voice not pre-installed       | Tiered fallback + `showVoiceNudge` banner                              |
| 6   | Vague `HomeViewModel` injection           | `mealCoach` added as defaulted init param                              |
| 7   | Cache key breaks for conversational input | `normalizeFoodKey` called on `extraction.foodName` not raw input       |
| 8   | No escape hatch on chips                  | "Add as typed" button in `DisambiguationChipsView`                     |
| 9   | `@Generable` type in `Models/` layer      | `FoodOption` is a plain struct in the Feature layer                    |

---

## File Map

```
WellPlate/
├── Package.swift                                          [MODIFIED]
├── Core/
│   └── Services/
│       ├── HapticService.swift                            [MODIFIED]  +narratorStart, +goalAchieved
│       ├── NutritionNarratorService.swift                 [NEW]
│       └── MealCoachService.swift                         [NEW]
├── Shared/
│   └── Components/
│       └── NarratorButton.swift                           [NEW]
└── Features + UI/
    └── Home/
        ├── FoodOption.swift                               [NEW]
        ├── ViewModels/
        │   └── HomeViewModel.swift                        [MODIFIED]
        └── Views/
            ├── HomeView.swift                             [MODIFIED]
            └── DisambiguationChipsView.swift              [NEW]
```
