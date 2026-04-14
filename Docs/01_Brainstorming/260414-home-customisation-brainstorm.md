# Brainstorm: Home Screen Content Customisation

**Date**: 2026-04-14
**Status**: Ready for Planning
**Prior Art**: `260409-home-screen-ux-update-brainstorm.md` — focused on layout redesign and contextual UX. This brainstorm focuses specifically on **user-driven customisation**: hiding, showing, and reordering home screen components.

---

## Problem Statement

The home screen shows a fixed set of cards in a fixed order. Users have different wellness priorities — a user focused on fasting may not care about the calorie ring, while a hydration-focused user may want water front-and-centre. Currently there's no way to personalise which components appear or their order.

**Core Need**: Let users curate their home screen to show only the wellness data they care about, in the order they prefer.

**Stated Want**: Long-press a card to hide it, long-press again (or go to Profile) to bring it back.

## Core Requirements

- Users can **hide** any home screen card via long-press context menu
- Users can **show** hidden cards via long-press context menu or Profile section
- Users can **reorder** visible cards (move up/down via context menu)
- Cards with sub-elements (WellnessRingsCard, QuickStatsRow) support **element-level toggles** (e.g., hide Calorie ring but keep Water ring)
- Preferences **persist** across app launches (stored in UserGoals SwiftData model)
- Hidden cards animate out; restored cards animate in
- A sensible **default layout** ships for new users (all visible, developer-defined order)
- The customisation state never blocks core functionality (e.g., hiding all input methods shouldn't break logging)

## Constraints

- Must work within existing `LazyVStack` + `NavigationStack` architecture
- SwiftUI `.contextMenu` has limited customisation — may need custom long-press gesture + overlay
- `PBXFileSystemSynchronizedRootGroup` means new files auto-include (no pbxproj edits)
- Must not break the `ContextualActionBar` floating bar logic
- Must handle the conditional MoodCheckIn/JournalReflection cards (they're already visibility-gated)
- iOS 18+ target (can use modern SwiftUI APIs)

---

## Current Home Screen Components (Customisable Candidates)

| # | Component | Sub-elements | Can Hide? | Notes |
|---|-----------|-------------|-----------|-------|
| 1 | **HomeHeaderView** | Greeting, AI button, mood badge | No | Always visible — core navigation |
| 2 | **WellnessRingsCard** | Calorie ring, Water ring, Exercise ring, Stress ring | Card + per-ring | Most complex: 4 independent rings |
| 3 | **StressSparklineStrip** | — (atomic) | Card only | Single-purpose strip |
| 4 | **MoodCheckInCard** | — (atomic) | Card only | Already conditionally shown |
| 5 | **JournalReflectionCard** | — (atomic) | Card only | Already conditionally shown |
| 6 | **QuickStatsRow** | Water tile, Coffee tile | Card + per-tile | Two liquid gauge tiles |
| 7 | **DailyInsightCard** | — (atomic) | Card only | AI-generated insight |
| 8 | **ContextualActionBar** | — (floating) | No | Always visible — core actions |

**Non-customisable**: Header and ContextualActionBar are structural — they anchor the screen.

---

## Approach 1: Native Context Menu + Profile Re-Add

**Summary**: Use SwiftUI `.contextMenu` on each card for hide/reorder actions, with a "Home Layout" section in Profile to manage visibility and bring back hidden cards.

### Interaction Flow

**Hiding a card:**
1. User long-presses WellnessRingsCard
2. Native context menu appears:
   - "Hide Card" (with `eye.slash` icon)
   - "Customize Rings..." (only for cards with sub-elements)
   - "Move Up" / "Move Down" (greyed out at boundaries)
3. User taps "Hide Card"
4. Card animates out with `.transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale(scale: 0.8).combined(with: .opacity)))`
5. Brief toast: "Wellness Rings hidden. Undo?" (auto-dismiss 3s)

**Customising sub-elements:**
1. User taps "Customize Rings..." from context menu
2. A `.sheet` appears with toggle rows:
   - [x] Calorie Ring
   - [ ] Water Ring (toggled off)
   - [x] Exercise Ring
   - [x] Stress Ring
3. Changes apply immediately with animation

**Re-adding from context menu:**
1. User long-presses any visible card
2. Context menu includes "Add Hidden Cards..." option (shown only when cards are hidden)
3. Tapping opens a sheet listing hidden cards with "Show" buttons

**Re-adding from Profile:**
1. Profile > "Home Layout" section
2. Shows all cards with toggles (visible/hidden)
3. Drag handles for reorder
4. "Reset to Default" button at bottom

### Pros
- **Native iOS feel** — context menus are familiar, no custom gesture handling
- **Low implementation risk** — `.contextMenu` is well-supported in SwiftUI
- **Undo safety net** — toast with undo prevents accidental hides
- **Dual re-add paths** — context menu for power users, Profile for discoverability
- **Minimal UI overhead** — no new screens needed beyond the Profile section

### Cons
- `.contextMenu` can't show previews easily (iOS shows a preview of the view)
- Move Up/Down via menu is sequential (one position at a time) — no free drag
- Native context menu styling is opaque — can't theme it to match app design
- On iPad, context menus behave differently (popover vs. inline)

### Complexity: Medium
### Risk: Low

---

## Approach 2: Custom Long-Press Edit Mode (Apple Widget-Inspired)

**Summary**: Long-press anywhere on the home screen to enter a dedicated "Edit Mode" where all cards show handles, X buttons, and can be dragged to reorder — similar to iOS home screen widget editing.

### Interaction Flow

**Entering edit mode:**
1. User long-presses anywhere on the ScrollView
2. Haptic feedback fires
3. All cards start a subtle jiggle animation
4. Each card shows:
   - A minus (−) button in top-left corner to hide
   - A drag handle on the right edge
5. A floating toolbar appears: [Done] [Reset] [+ Add Card]
6. Background dims slightly

**Hiding:**
1. Tap the (−) button on any card
2. Card shrinks and fades out
3. A counter badge on [+ Add Card] shows number of hidden cards

**Reordering:**
1. Press and drag a card's handle
2. Other cards shift to make room (with spring animation)
3. Drop to confirm new position

**Sub-element customisation:**
1. Tap the card body (not the − or handle) while in edit mode
2. Opens the element toggle sheet (same as Approach 1)

**Exiting:**
1. Tap [Done] or tap outside the card area
2. Jiggle stops, controls fade out
3. New layout persists

### Pros
- **Premium feel** — matches Apple's own widget editing UX
- **Direct manipulation** — drag to reorder is intuitive
- **Batch editing** — hide multiple cards and reorder in one session
- **Visual clarity** — clear mode switch means no accidental hides

### Cons
- **Significantly more complex** — custom gesture handling, drag-and-drop in LazyVStack, jiggle animation
- **Gesture conflicts** — long-press on ScrollView may conflict with card-level interactions
- **LazyVStack + drag** — SwiftUI's built-in drag-and-drop with lazy stacks is notoriously finicky
- **Edit mode is a modal state** — user can't interact with cards normally while editing

### Complexity: High
### Risk: Medium-High (gesture conflicts, lazy stack drag issues)

---

## Approach 3: Hybrid — Context Menu for Quick Actions + Profile for Full Management

**Summary**: Context menus handle the quick hide/customize actions, while Profile provides a dedicated List-based editor with drag-to-reorder (`EditButton` + `.onMove`). Best of both worlds.

### Interaction Flow

**Quick hide (context menu):**
1. Long-press card → context menu: "Hide", "Customize..." (if applicable)
2. Card animates out with undo toast
3. No move up/down in context menu (keeps it simple)

**Full management (Profile):**
1. Profile > "Home Layout"
2. `List` with `ForEach` and `.onMove` modifier — native drag-to-reorder
3. Each row shows: drag handle | card icon + name | visibility toggle
4. Hidden cards appear greyed out at the bottom
5. "Reset to Default" button
6. Cards with sub-elements show a disclosure chevron → element toggles

**Re-add inline:**
1. When cards are hidden, a subtle "N cards hidden" pill appears at the bottom of the home screen
2. Tapping it opens the Profile Home Layout section directly

### Pros
- **Best UX balance** — quick actions are fast, full management is powerful
- **Native reorder** — `List` + `.onMove` is rock-solid in SwiftUI (no gesture conflicts)
- **Context menu stays simple** — just Hide + Customize, no move cluttering the menu
- **Discoverable** — "N cards hidden" pill teaches users where to go
- **Testable** — Profile section is a standard List, easy to test

### Cons
- **Two interaction surfaces** — users need to learn context menu AND Profile section
- **Reorder not available inline** — must go to Profile to change order
- **Profile screen gets busier** — another section to scroll past

### Complexity: Medium
### Risk: Low

---

## Data Model Design

All three approaches share the same persistence layer:

```swift
// MARK: - Home Layout Types

/// Identifies each customisable card on the home screen.
enum HomeCardID: String, Codable, CaseIterable, Identifiable {
    case wellnessRings
    case stressSparkline
    case moodCheckIn
    case journalReflection
    case quickStats
    case dailyInsight
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .wellnessRings:      return "Wellness Rings"
        case .stressSparkline:    return "Stress Sparkline"
        case .moodCheckIn:        return "Mood Check-In"
        case .journalReflection:  return "Journal Reflection"
        case .quickStats:         return "Water & Coffee"
        case .dailyInsight:       return "Daily Insight"
        }
    }
    
    var iconName: String {
        switch self {
        case .wellnessRings:      return "circle.circle"
        case .stressSparkline:    return "waveform.path.ecg"
        case .moodCheckIn:        return "face.smiling"
        case .journalReflection:  return "book"
        case .quickStats:         return "drop.fill"
        case .dailyInsight:       return "sparkles"
        }
    }
}

/// Identifies toggleable sub-elements within a card.
enum HomeElementID: String, Codable, CaseIterable {
    // WellnessRingsCard elements
    case calorieRing
    case waterRing
    case exerciseRing
    case stressRing
    // QuickStatsRow elements
    case waterTile
    case coffeeTile
}

/// Persisted layout configuration.
struct HomeLayoutConfig: Codable, Equatable {
    /// Ordered list of card IDs (visible and hidden).
    /// Cards appear in this order on the home screen.
    var cardOrder: [HomeCardID] = HomeCardID.allCases
    
    /// Cards the user has explicitly hidden.
    var hiddenCards: Set<HomeCardID> = []
    
    /// Per-card element visibility overrides.
    /// Key: card ID, Value: set of hidden element IDs.
    var hiddenElements: [HomeCardID: Set<HomeElementID>] = [:]
    
    /// Visible cards in display order.
    var visibleCards: [HomeCardID] {
        cardOrder.filter { !hiddenCards.contains($0) }
    }
    
    /// Check if a specific element is visible.
    func isElementVisible(_ element: HomeElementID, in card: HomeCardID) -> Bool {
        !(hiddenElements[card]?.contains(element) ?? false)
    }
    
    /// Default layout — all cards visible in standard order.
    static let `default` = HomeLayoutConfig()
}
```

### Storage in UserGoals

```swift
// Add to existing UserGoals @Model
var homeLayoutJSON: String = "{}"

var homeLayout: HomeLayoutConfig {
    get {
        guard let data = homeLayoutJSON.data(using: .utf8),
              let config = try? JSONDecoder().decode(HomeLayoutConfig.self, from: data)
        else { return .default }
        return config
    }
    set {
        if let data = try? JSONEncoder().encode(newValue),
           let json = String(data: data, encoding: .utf8) {
            homeLayoutJSON = json
        }
    }
}
```

**Migration**: Since `homeLayoutJSON` defaults to `"{}"`, existing users get `HomeLayoutConfig.default` (all visible, standard order) — zero migration needed.

---

## Edge Cases to Consider

- [ ] **All rings hidden**: If user hides all 4 rings inside WellnessRingsCard, should the card itself auto-hide? (Recommendation: yes, with a note in the customize sheet)
- [ ] **Mood/Journal conditional visibility**: These cards are already conditionally shown based on mood/journal state. User-hide should take precedence (if user hides MoodCheckIn, it stays hidden even if mood isn't logged)
- [ ] **ContextualActionBar references hidden cards**: The bar suggests "Add Water" — what if QuickStats is hidden? (Recommendation: bar actions still work; they trigger the underlying action, not card visibility)
- [ ] **New cards added in future updates**: When a new card type ships, it should appear at the end of the user's order and be visible by default. `HomeCardID.allCases` must diff against persisted `cardOrder` to catch new additions.
- [ ] **Empty home screen**: Prevent user from hiding ALL cards — enforce minimum 1 visible card, or show a friendly empty state with "Customise your home screen" CTA
- [ ] **Reset to default**: Must be available in Profile and should confirm with an alert
- [ ] **WellnessCompletionPercent**: If calorie ring is hidden, should it still count toward the 4-ring completion percentage? (Recommendation: yes — hiding is visual, not functional. Rings still track goals.)
- [ ] **VoiceOver**: Context menu items need proper accessibility labels. Edit mode in Approach 2 needs rotor support.
- [ ] **Undo toast timing**: If user rapidly hides multiple cards, toasts should queue or combine ("2 cards hidden. Undo all?")
- [ ] **Card-specific context menus**: Cards that already have tap interactions (rings → navigation, quick stats → detail views) — context menu must not interfere with primary tap

---

## Open Questions

- [ ] Should the "N cards hidden" indicator be a floating pill, a section at the bottom of the scroll, or just rely on Profile?
- [ ] Should hiding a card also disable its data fetching (performance optimisation) or just hide the view?
- [ ] Should there be a "Compact mode" preset that auto-hides certain cards for a minimal home screen?
- [ ] Do we want to support multiple saved layouts ("Morning", "Evening", "Minimal") in the future?
- [ ] Should the ContextualActionBar also be customisable, or is it always developer-controlled?

---

## Decisions Made

| # | Decision | Severity | Chosen Option | Rationale |
|---|----------|----------|---------------|-----------|
| 1 | Customisation granularity | Critical | Card + element level | User wants to toggle individual rings and tiles, not just whole cards. Provides fine-grained control without going to fully flat element-level complexity. |
| 2 | Primary interaction model | High | Long-press context menu | Native iOS feel, familiar pattern, lowest implementation risk. No custom gesture handling needed. |
| 3 | Persistence storage | High | UserGoals SwiftData model (JSON property) | Already queried in HomeView, travels with user data, zero migration for existing users (empty JSON = defaults). |
| 4 | Reordering support | Medium | Yes — show/hide + reorder | Full customisation. Reorder via context menu (Move Up/Down) for inline changes, and via Profile List `.onMove` for bulk reorder. |

---

## Recommendation

**Pursue Approach 3: Hybrid — Context Menu + Profile Management**

This combines the best of both worlds:

1. **Context menu** for quick, inline hide/customize actions (low friction, native feel)
2. **Profile "Home Layout" section** with `List` + `.onMove` for full reorder management (reliable SwiftUI drag, no gesture conflicts)
3. **"N cards hidden" pill** on the home screen for discoverability

This avoids the gesture-conflict risks of Approach 2's edit mode while offering more power than Approach 1's context-menu-only reorder (Move Up/Down one slot at a time is tedious for large reorders).

### Implementation Phases

**Phase 1 — Core visibility** (MVP)
- `HomeLayoutConfig` model + `UserGoals` integration
- Context menu on each card with "Hide" action
- Profile "Home Layout" section with toggles
- Undo toast on hide
- Animated show/hide transitions

**Phase 2 — Element-level customisation**
- "Customize..." context menu option for WellnessRingsCard and QuickStatsRow
- Element toggle sheet
- Auto-hide card when all elements hidden

**Phase 3 — Reordering**
- Context menu "Move Up" / "Move Down"
- Profile section with `.onMove` drag-to-reorder
- "Reset to Default" action

**Phase 4 — Polish**
- "N cards hidden" pill on home screen
- Haptic feedback on all interactions
- VoiceOver audit
- Edge case handling (new cards in updates, empty state)

---

## Research References

- Apple HIG: [Context Menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- Apple HIG: [Editing Lists](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- SwiftUI `.contextMenu` documentation — iOS 16+ supports preview customisation
- SwiftUI `List` + `.onMove` — reliable reorder in non-lazy contexts
- Prior art: `260409-home-screen-ux-update-brainstorm.md` — Approach 2 (Widget Grid) explored similar customisation but at a higher complexity level

---

## Next Step

→ Run `/develop strategize home-customisation` to select the implementation approach and define the concrete strategy.
