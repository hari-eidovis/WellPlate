# Strategy: Journal / Gratitude Prompts Tied to Mood

**Date**: 2026-04-07
**Source**: `Docs/01_Brainstorming/260407-journal-gratitude-brainstorm.md`
**Status**: Ready for Planning

## Chosen Approach

**Hybrid — Inline Prompt + Journal Sheet (Approach 3 from brainstorm)**

After the user logs their mood on the Home screen, a compact "Daily Reflection" card appears in place of the dismissed `MoodCheckInCard`. This card shows an AI-generated prompt and a 1–2 line text field for a quick entry. A "Write more" action opens a full journal sheet for deeper reflection. A toolbar icon on Home provides access to journal history and themes at any time, even if mood hasn't been logged.

## Rationale

- **Catches users at peak reflection mindset**: Mood check-in is the natural trigger — the card swap (mood card → journal card) creates a seamless flow with zero navigation friction
- **Progressive disclosure**: Most days users write 1 sentence; when they want depth, the full sheet is one tap away. This matches Daylio's "micro-diary" pattern that drives retention
- **No tab restructure**: Avoids touching `MainTabView` — Profile placeholder stays available for future needs. Journal is a Home-anchored feature accessed via card + toolbar, not a tab
- **Proven Foundation Models pattern**: `StressInsightService` already demonstrates `LanguageModelSession` → `@Generable` schema → template fallback. `JournalPromptService` follows the identical architecture
- **Reuses existing sheet/navigation patterns**: Home already uses `@State` booleans for `.navigationDestination` and `.sheet`. Journal history fits naturally as a new `.navigationDestination`

### Trade-offs accepted
- Two UI surfaces (inline card + sheet) instead of one dedicated view — acceptable because the inline card is a thin wrapper, not a full editor
- One entry per day in MVP — limits expressiveness but dramatically simplifies the model, queries, and themes analysis

## Affected Files & Components

### New Files (~5)
| File | Purpose |
|---|---|
| `WellPlate/Models/JournalEntry.swift` | SwiftData `@Model` — date, text, moodRaw, promptUsed, stressScore |
| `WellPlate/Core/Services/JournalPromptService.swift` | Foundation Models prompt generation + template fallback (~50 prompts) |
| `WellPlate/Features + UI/Home/Views/JournalReflectionCard.swift` | Inline card that replaces `MoodCheckInCard` after mood is logged |
| `WellPlate/Features + UI/Home/Views/JournalEntryView.swift` | Full journal sheet — rich text area, prompt, mood/stress context |
| `WellPlate/Features + UI/Home/Views/JournalHistoryView.swift` | Past entries + themes summary, accessible from toolbar |

### Modified Files (~3)
| File | Change |
|---|---|
| `WellPlate/App/WellPlateApp.swift` (line 34) | Add `JournalEntry.self` to `.modelContainer(for:)` array |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` (lines 86–90) | Replace mood card section: show `MoodCheckInCard` when no mood logged, show `JournalReflectionCard` after mood is logged. Add `@State` for journal sheet/navigation. Add toolbar icon for journal history |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` (lines 150–176) | Add `.navigationDestination` for journal history + `.sheet` for full entry |

### Untouched (explicitly)
- `MoodCheckInCard.swift` — no changes; the swap logic lives in `HomeView`
- `WellnessDayLog.swift` — no schema changes; `JournalEntry` is a separate model linked by date
- `StressInsightService.swift` — referenced as a pattern but not modified
- `MainTabView.swift` — no tab changes

## Architectural Direction

### Data Model
```
JournalEntry (@Model)
├── day: Date          // @Attribute(.unique) — start of day, one per calendar day (MVP)
├── text: String       // User's journal text
├── moodRaw: Int?      // Snapshot of mood at time of writing (from WellnessDayLog)
├── promptUsed: String? // The prompt that was shown (nil if free-form)
├── stressScore: Double? // Snapshot of today's stress score (if available)
├── createdAt: Date
└── updatedAt: Date
```

Separate model from `WellnessDayLog` — journal entries are richer, may evolve independently (multi-entry per day in future), and shouldn't bloat the compact daily log model. Linked by `day` date (same `startOfDay` convention).

### Service Layer
`JournalPromptService` follows `StressInsightService` pattern:
- `@MainActor final class`, `ObservableObject`
- `generatePrompt(mood:stressScore:recentPatterns:) async -> String`
- iOS 26+: `LanguageModelSession` with `@Generable` schema for structured prompt output
- Fallback: curated template library indexed by mood level + context signals
- No network calls — fully on-device

### UI Flow
```
HomeView scroll
├── [1] Header
├── [2] Wellness Rings
├── [3] IF mood not logged → MoodCheckInCard
│       IF mood logged AND no journal today → JournalReflectionCard (inline)
│       IF mood logged AND journal exists → Compact "Journal logged" pill
├── [4] Hydration
├── [5] Coffee
└── ...

Toolbar: 📖 icon → JournalHistoryView (navigationDestination)
JournalReflectionCard "Write more →" → JournalEntryView (sheet)
```

### Foundation Models Schema
```swift
@Generable
struct _JournalPromptSchema {
    @Guide(description: "A warm, specific journal prompt based on the user's mood and stress data. 1-2 sentences. No medical language.")
    var prompt: String
    
    @Guide(description: "A single-word category: gratitude, reflection, awareness, or intention")
    var category: String
}
```

## Design Constraints

1. **One entry per day (MVP)**: `@Attribute(.unique)` on `day` field. User can edit throughout the day but not create multiple entries
2. **Card swap, not card stack**: `MoodCheckInCard` and `JournalReflectionCard` are mutually exclusive in the same slot — controlled by `hasLoggedMoodToday` and `hasJournaledToday` state
3. **Font/shadow/card conventions**: `.r()` fonts, `.appShadow()`, `RoundedRectangle(cornerRadius: 20/24)`, `Color(.systemBackground)` — match existing Home screen cards
4. **Foundation Models gated on iOS 26**: `#if canImport(FoundationModels)` + `@available(iOS 26, *)` — identical pattern to `StressInsightService`
5. **Template fallback must feel natural**: Prompts should not feel obviously canned. Vary by mood level (5 tiers), time of day (morning/afternoon/evening), and optional stress context (high/low) = ~50+ combinations
6. **Journal text stays on-device**: SwiftData only. No cloud sync, no analytics, no server
7. **Haptics**: `HapticService.impact(.light)` on card interactions, `.notify(.success)` on save

## Non-Goals

- **Multi-entry per day**: MVP is one entry. Future enhancement
- **Rich text / markdown**: Plain text only in MVP
- **Photo/audio attachments**: Out of scope
- **Sentiment analysis on journal text**: Not computing or storing sentiment scores in MVP
- **Journal as stress score input**: Journal data does not feed into stress score calculation
- **Search**: Not in MVP. History view is chronological scroll
- **Export integration**: Not in MVP — can be added when journal data is mature (Phase 2 follow-up)
- **Streak mechanic for journaling**: Not in MVP — avoid gamifying reflection
- **Themes-over-time AI summary**: Deferred to a fast-follow. MVP themes view is a simple list of past entries with mood badges

## Open Risks

- **Foundation Models availability**: Template fallback must be high quality. Risk is low since `StressInsightService` already proves the pattern works
- **Home scroll depth**: Adding another card increases vertical scroll. Mitigation: journal card is compact (~100pt) and replaces the mood card slot rather than stacking below it
- **Prompt fatigue**: ~50 templates may feel repetitive over weeks. Mitigation: Foundation Models generates unique prompts when available; templates are a safety net, not the primary experience on supported devices
- **SwiftData lightweight migration**: Adding `JournalEntry` model to existing container. Risk is low — it's a new model with no relationships to existing models, so no migration needed
