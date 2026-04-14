# Strategy: Home Screen Content Customisation

**Date**: 2026-04-14
**Source**: `Docs/01_Brainstorming/260414-home-customisation-brainstorm.md`
**Status**: Ready for Planning

## Chosen Approach

**Approach 3: Hybrid — Context Menu for Quick Actions + Profile for Full Management**

Users long-press any home screen card to get a native `.contextMenu` with "Hide" and "Customize..." options. For full reorder and bulk management, a dedicated "Home Layout" section in ProfileView provides a `List` with `.onMove` drag-to-reorder and visibility toggles. A subtle "N cards hidden" pill at the bottom of the home scroll links to the Profile editor.

## Rationale

- **Approach 1 (Context Menu only)** was rejected because Move Up/Move Down one slot at a time is tedious for reordering 6 cards. The user explicitly wants reordering, and context-menu-only reorder is a poor UX for more than 2-3 swaps.
- **Approach 2 (Edit Mode / Jiggle)** was rejected due to high risk: `LazyVStack` + custom drag gesture is unreliable in SwiftUI, long-press on ScrollView conflicts with card-level gestures, and the implementation cost is 2-3x higher.
- **Approach 3 (Hybrid)** wins because:
  - Context menu for quick hide is native, zero-risk, and instant
  - Profile `List` + `.onMove` for reorder is SwiftUI's most reliable drag mechanism (no LazyVStack conflicts)
  - Two interaction surfaces serve different intents: quick edits (inline) vs. full layout management (Profile)
  - Medium complexity, low risk

## Affected Files & Components

### New Files (auto-included via PBXFileSystemSynchronizedRootGroup)

| File | Purpose |
|------|---------|
| `WellPlate/Models/HomeLayoutConfig.swift` | `HomeCardID` enum, `HomeElementID` enum, `HomeLayoutConfig` struct (Codable) |
| `WellPlate/Features + UI/Home/Components/HomeCardContextMenu.swift` | ViewModifier wrapping `.contextMenu` with hide/customize/move actions |
| `WellPlate/Features + UI/Home/Components/CardCustomizeSheet.swift` | Sheet for toggling sub-elements within a card (rings, tiles) |
| `WellPlate/Features + UI/Home/Components/HiddenCardsPill.swift` | "N cards hidden" pill shown at bottom of home scroll |
| `WellPlate/Features + UI/Tab/HomeLayoutEditor.swift` | Profile sub-view: `List` + `.onMove` reorder + visibility toggles |

### Modified Files

| File | Changes |
|------|---------|
| `WellPlate/Models/UserGoals.swift` | Add `homeLayoutJSON: String` stored property + computed `homeLayout: HomeLayoutConfig` get/set |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | Replace hardcoded card stack with `ForEach(layout.visibleCards)` dispatch; add context menus; add hidden-cards pill; read layout from `currentGoals` |
| `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` | Accept optional `visibleRings` filter (or filter `rings` array at call site in HomeView) |
| `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` | Accept optional `showWater`/`showCoffee` booleans to conditionally render tiles |
| `WellPlate/Features + UI/Tab/ProfileView.swift` | Add "Home Layout" section card that navigates to `HomeLayoutEditor` |

### Untouched (verified no changes needed)

- `StressSparklineStrip.swift` — atomic card, no sub-elements; hiding is handled by HomeView not rendering it
- `DailyInsightCard.swift` — same: atomic, hide handled externally
- `MoodCheckInCard.swift` / `JournalReflectionCard.swift` — already conditionally rendered; user-hide overrides the existing condition
- `ContextualActionBar.swift` — always visible, actions work regardless of card visibility
- `WellPlateApp.swift` — no ModelContainer changes (no new @Model)

## Architectural Direction

### Data Flow

```
UserGoals.homeLayoutJSON (SwiftData, persisted)
    ↓ decoded
HomeLayoutConfig (value type, Codable, Equatable)
    ↓ read by
HomeView (drives card rendering order + visibility)
    ↓ mutated by
Context menu actions  OR  HomeLayoutEditor (Profile)
    ↓ encoded back to
UserGoals.homeLayoutJSON → SwiftData save
```

### HomeView Card Rendering

The current `LazyVStack` has hardcoded card calls. The strategy replaces this with a data-driven dispatch:

```swift
// Current (hardcoded):
WellnessRingsCard(...)
StressSparklineStrip(...)
MoodCheckInCard(...)
QuickStatsRow(...)
DailyInsightCard(...)

// New (data-driven):
ForEach(layout.visibleCards, id: \.self) { card in
    switch card {
    case .wellnessRings:     wellnessRingsSection
    case .stressSparkline:   stressSparklineSection
    case .moodCheckIn:       moodCheckInSection   // still respects hasLoggedMoodToday
    case .journalReflection: journalSection        // still respects hasJournaledToday
    case .quickStats:        quickStatsSection
    case .dailyInsight:      dailyInsightSection
    }
}
```

The header and ContextualActionBar remain outside the `ForEach` — they are structural anchors.

### Context Menu ViewModifier Pattern

A reusable `.homeCardMenu(card:layout:onCustomize:)` modifier wraps each card:

```swift
wellnessRingsSection
    .homeCardMenu(card: .wellnessRings, layout: $layout) {
        activeSheet = .customizeCard(.wellnessRings)
    }
```

This keeps card views unmodified — the menu is an overlay concern, not a card concern.

### Element-Level Filtering

- **WellnessRingsCard**: HomeView filters the `rings` array before passing it: `rings.filter { layout.isElementVisible(ringToElement($0.destination)) }`. The card renders whatever rings it receives — no internal knowledge of layout config.
- **QuickStatsRow**: Accepts `showWater: Bool` and `showCoffee: Bool` parameters. When one is hidden, the remaining tile expands to full width. When both are hidden, the card auto-hides (HomeView skips rendering it).

### Profile HomeLayoutEditor

A dedicated `NavigationLink` destination in ProfileView:

```swift
// In ProfileView's VStack
homeLayoutCard  // → NavigationLink to HomeLayoutEditor
```

`HomeLayoutEditor` is a `List` with:
- `Section("Visible Cards")` — cards in current order, with `.onMove` and `.onDelete` (hide, not delete)
- `Section("Hidden Cards")` — greyed out, with "Show" button to restore
- Cards with sub-elements show a disclosure `NavigationLink` → element toggles
- "Reset to Default" button at bottom

### Undo Toast

A lightweight overlay toast (not an `Alert`) appears for 3 seconds after hiding a card. Uses `@State` + `withAnimation` + `Task.sleep` for auto-dismiss. Single toast at a time — rapid hides replace the previous toast.

## Design Constraints

1. **HomeView ForEach must use `id: \.self`** — `HomeCardID` is `Hashable` via `RawRepresentable`
2. **No new SwiftData @Model** — `homeLayoutJSON` is a flat `String` property on the existing `UserGoals` model, avoiding ModelContainer changes
3. **Card views remain layout-unaware** — they don't import or reference `HomeLayoutConfig`. All filtering and ordering happens in HomeView
4. **Mood/Journal conditional logic stacks with user-hide** — if the user has hidden `.moodCheckIn`, it stays hidden even if `!hasLoggedMoodToday`. The visibility check is: `layout.isCardVisible(card) && existingCondition`
5. **Context menu must not conflict with existing tap gestures** — `.contextMenu` is triggered by long-press, which is distinct from tap. No gesture conflict expected
6. **Animations use existing project patterns** — `.spring(response: 0.4, dampingFraction: 0.7)` for show/hide, `.transition(.asymmetric(...))` matching the JournalReflectionCard pattern
7. **New cards in future updates** — `HomeLayoutConfig` must handle unknown card IDs gracefully: when decoded, compare against `HomeCardID.allCases` and append any missing cases to `cardOrder` as visible

## Non-Goals

- **Multiple saved layouts** (e.g., "Morning", "Evening") — out of scope, can be added later atop the same data model
- **Layout presets** (e.g., "Minimal", "Fitness Focus") — nice-to-have, not in initial implementation
- **ContextualActionBar customisation** — remains developer-controlled
- **Disabling data fetching for hidden cards** — hidden cards are just not rendered; HealthKit/SwiftData fetches remain unchanged (complexity not justified at this stage)
- **iPad-specific layout** — context menus work on iPad but no grid/multi-column adaptation
- **Widget-style drag on the home screen itself** — explicitly rejected (Approach 2 risks)

## Open Risks

- **SwiftData lightweight migration** — Adding `homeLayoutJSON: String` with a default value to an existing `@Model` should work as a lightweight migration. SwiftData handles new properties with defaults automatically. **Risk: Low** — same pattern used for `coffeeDailyCups` which was added post-launch.
- **ForEach + LazyVStack animation** — Changing the `ForEach` data source (hiding/showing cards) inside a `LazyVStack` can occasionally cause animation glitches in SwiftUI. **Mitigation**: Use `.animation(.spring(...), value: layout.visibleCards)` on the `LazyVStack` and ensure `HomeCardID` conforms to `Identifiable`.
- **Context menu + ScrollView interaction** — On some iOS versions, `.contextMenu` inside a `ScrollView` can cause scroll-to-top on dismiss. **Mitigation**: Test on iOS 18.x; if problematic, use `.contextMenu(menuItems:preview:)` variant with explicit preview to anchor the menu.
- **Profile screen growing too large** — ProfileView already has 6+ sections. Adding "Home Layout" increases scroll depth. **Mitigation**: Place it strategically (after Goals, before Widget Setup) and keep the card compact — just an icon, title, and chevron.

## Next Step

→ Run `/develop plan home-customisation` to create the detailed implementation plan.
