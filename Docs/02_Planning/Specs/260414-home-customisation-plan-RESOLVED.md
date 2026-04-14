# Implementation Plan: Home Screen Content Customisation (RESOLVED)

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|----|----------|-------|------------|
| C1 | CRITICAL | `currentGoals` fallback creates transient object — writes silently lost | Added `writableGoals` helper using `UserGoals.current(in: modelContext)` for all write paths |
| H1 | HIGH | `@AppStorage("hideInsightCard")` conflicts with HomeLayoutConfig | Remove AppStorage, migrate on first launch, wire `onDismiss` to `hideCard(.dailyInsight)` |
| H2 | HIGH | Plan card order doesn't match working tree | Updated `HomeCardID` enum order: dailyInsight first (matching working tree position 1b) |
| H3 | HIGH | `.editMode(.constant(.active))` shows delete buttons | Added `.deleteDisabled(true)` to both sections |
| M1 | MEDIUM | Conditional cards in ForEach produce empty views | Added `effectiveVisibleCards` computed property to filter at identity level |
| M2 | MEDIUM | UndoToast Task.sleep race condition | Added cancellable timer pattern with `@State` Task reference |
| M3 | MEDIUM | Dead code branch in `toggleElement` | Removed dead branch, added clarifying comment |
| M4 | MEDIUM | `onCoffeeLog` closure mismatch with working tree | Updated to match working tree's simplified closure |
| L1 | LOW | No element customisation from ProfileEditor | Acknowledged — deferred to future enhancement |
| L2 | LOW | Context menu accessibility labels | Fixed — "Customize..." now includes card name |

---

## Overview

Allow users to customise their home screen by hiding/showing cards, toggling sub-elements within compound cards (rings, tiles), and reordering cards. The implementation uses a hybrid approach: native `.contextMenu` on each card for quick inline actions, and a dedicated "Home Layout" editor in Profile for full reorder via `List` + `.onMove`. Preferences persist in the existing `UserGoals` SwiftData model as a JSON-encoded `HomeLayoutConfig`.

## Requirements

- Users can hide any home screen card via long-press context menu
- Users can show hidden cards from Profile "Home Layout" section or via a "hidden cards" pill on the home screen
- Users can reorder visible cards via Profile editor (drag-to-reorder)
- WellnessRingsCard supports per-ring toggles; QuickStatsRow supports per-tile toggles
- Preferences persist across app launches (stored on UserGoals)
- Animated show/hide transitions with undo toast
- Default layout: all cards visible in standard order

## Architecture Changes

- `WellPlate/Models/HomeLayoutConfig.swift` — **NEW**: `HomeCardID`, `HomeElementID` enums + `HomeLayoutConfig` Codable struct
- `WellPlate/Models/UserGoals.swift` — **MODIFY**: Add `homeLayoutJSON: String` property + computed `homeLayout` accessor
- `WellPlate/Features + UI/Home/Views/HomeView.swift` — **MODIFY**: Replace hardcoded card stack with data-driven `ForEach`; add context menus; add undo toast overlay; add hidden-cards pill; remove `@AppStorage("hideInsightCard")`; add `writableGoals` for safe writes
- `WellPlate/Features + UI/Home/Components/HomeCardContextMenu.swift` — **NEW**: ViewModifier for `.contextMenu` on home cards
- `WellPlate/Features + UI/Home/Components/CardCustomizeSheet.swift` — **NEW**: Sheet view for toggling sub-elements within a card
- `WellPlate/Features + UI/Home/Components/HiddenCardsPill.swift` — **NEW**: Pill overlay showing count of hidden cards
- `WellPlate/Features + UI/Home/Components/UndoToast.swift` — **NEW**: Auto-dismiss toast overlay for undo after hiding
- `WellPlate/Features + UI/Tab/HomeLayoutEditor.swift` — **NEW**: Profile sub-view with `List` + `.onMove` + visibility toggles
- `WellPlate/Features + UI/Tab/ProfileView.swift` — **MODIFY**: Add "Home Layout" section card with `NavigationLink`
- `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` — **NO CHANGES**: filtering happens at the call site in HomeView
- `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` — **MODIFY**: Add `showWater`/`showCoffee` parameters for conditional tile rendering

## Implementation Steps

### Phase 1: Data Model & Persistence

#### Step 1: Create HomeLayoutConfig model
**File**: `WellPlate/Models/HomeLayoutConfig.swift` (NEW)
**Action**: Create the core data model with three types.

<!-- RESOLVED: H2 — Enum case order updated to match working tree: dailyInsight first (position 1b after header) -->

```swift
import Foundation

// MARK: - Home Card Identification

/// Identifies each customisable card on the home screen.
/// Case order matches the default display order (used by CaseIterable).
/// Raw values are used for JSON persistence — do not rename without migration.
enum HomeCardID: String, Codable, CaseIterable, Identifiable, Hashable {
    case dailyInsight       // Position 1b — after header
    case wellnessRings      // Position 2
    case stressSparkline    // Position 2b
    case moodCheckIn        // Position 3a (conditional)
    case journalReflection  // Position 3b (conditional)
    case quickStats         // Position 4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dailyInsight:       return "Daily Insight"
        case .wellnessRings:      return "Wellness Rings"
        case .stressSparkline:    return "Stress Sparkline"
        case .moodCheckIn:        return "Mood Check-In"
        case .journalReflection:  return "Journal Reflection"
        case .quickStats:         return "Water & Coffee"
        }
    }

    var iconName: String {
        switch self {
        case .dailyInsight:       return "sparkles"
        case .wellnessRings:      return "circle.circle"
        case .stressSparkline:    return "waveform.path.ecg"
        case .moodCheckIn:        return "face.smiling"
        case .journalReflection:  return "book"
        case .quickStats:         return "drop.fill"
        }
    }

    /// Cards that support element-level customisation.
    var hasSubElements: Bool {
        switch self {
        case .wellnessRings, .quickStats: return true
        default: return false
        }
    }

    /// Element IDs belonging to this card.
    var subElements: [HomeElementID] {
        switch self {
        case .wellnessRings: return [.calorieRing, .waterRing, .exerciseRing, .stressRing]
        case .quickStats:    return [.waterTile, .coffeeTile]
        default:             return []
        }
    }
}

// MARK: - Home Element Identification

/// Identifies toggleable sub-elements within compound cards.
enum HomeElementID: String, Codable, CaseIterable, Identifiable, Hashable {
    case calorieRing
    case waterRing
    case exerciseRing
    case stressRing
    case waterTile
    case coffeeTile

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calorieRing:  return "Calorie Ring"
        case .waterRing:    return "Water Ring"
        case .exerciseRing: return "Exercise Ring"
        case .stressRing:   return "Stress Ring"
        case .waterTile:    return "Water"
        case .coffeeTile:   return "Coffee"
        }
    }

    var iconName: String {
        switch self {
        case .calorieRing:  return "flame.fill"
        case .waterRing:    return "drop.fill"
        case .exerciseRing: return "figure.run"
        case .stressRing:   return "brain.head.profile"
        case .waterTile:    return "drop.fill"
        case .coffeeTile:   return "cup.and.saucer.fill"
        }
    }
}

// MARK: - Home Layout Configuration

/// Persisted layout configuration. Codable for JSON storage in UserGoals.
struct HomeLayoutConfig: Codable, Equatable {

    /// Ordered list of ALL card IDs. Cards appear in this order on the home screen.
    var cardOrder: [HomeCardID]

    /// Cards the user has explicitly hidden.
    var hiddenCards: Set<HomeCardID>

    /// Per-card element visibility overrides.
    /// Key = parent card ID, Value = set of HIDDEN element IDs within that card.
    var hiddenElements: [HomeCardID: Set<HomeElementID>]

    // MARK: - Defaults

    init(
        cardOrder: [HomeCardID] = HomeCardID.allCases,
        hiddenCards: Set<HomeCardID> = [],
        hiddenElements: [HomeCardID: Set<HomeElementID>] = [:]
    ) {
        self.cardOrder = cardOrder
        self.hiddenCards = hiddenCards
        self.hiddenElements = hiddenElements
    }

    static let `default` = HomeLayoutConfig()

    // MARK: - Queries

    /// Visible cards in display order.
    var visibleCards: [HomeCardID] {
        cardOrder.filter { !hiddenCards.contains($0) }
    }

    /// Number of hidden cards.
    var hiddenCount: Int { hiddenCards.count }

    /// Check if a specific element is visible within a card.
    func isElementVisible(_ element: HomeElementID, in card: HomeCardID) -> Bool {
        !(hiddenElements[card]?.contains(element) ?? false)
    }

    /// Visible elements for a given card.
    func visibleElements(for card: HomeCardID) -> [HomeElementID] {
        card.subElements.filter { isElementVisible($0, in: card) }
    }

    // MARK: - Mutations

    /// Hide a card.
    /// Note: cards auto-hidden (all elements toggled off) must be manually re-shown —
    /// there is no implicit/explicit distinction stored.
    mutating func hideCard(_ card: HomeCardID) {
        hiddenCards.insert(card)
    }

    /// Show a previously hidden card.
    mutating func showCard(_ card: HomeCardID) {
        hiddenCards.remove(card)
    }

    <!-- RESOLVED: M3 — Removed dead code branch (auto-show comment). Added clarifying comment on hideCard instead. -->

    /// Toggle element visibility. Auto-hides parent card if ALL elements become hidden.
    mutating func toggleElement(_ element: HomeElementID, in card: HomeCardID) {
        var set = hiddenElements[card] ?? []
        if set.contains(element) {
            set.remove(element)
        } else {
            set.insert(element)
        }
        hiddenElements[card] = set.isEmpty ? nil : set

        // Auto-hide card if ALL its elements are now hidden
        if !card.subElements.isEmpty && visibleElements(for: card).isEmpty {
            hideCard(card)
        }
    }

    /// Move a card from one position to another in cardOrder.
    mutating func moveCard(from source: IndexSet, to destination: Int) {
        cardOrder.move(fromOffsets: source, toOffset: destination)
    }

    /// Reset to default layout.
    mutating func reset() {
        self = .default
    }

    // MARK: - Future-proofing

    /// Ensures new cards added in future updates appear in the order.
    /// Call after decoding to reconcile with current `HomeCardID.allCases`.
    mutating func reconcileWithCurrentCards() {
        let known = Set(cardOrder)
        let newCards = HomeCardID.allCases.filter { !known.contains($0) }
        cardOrder.append(contentsOf: newCards)
        // Remove any cards that no longer exist in the enum
        let current = Set(HomeCardID.allCases)
        cardOrder.removeAll { !current.contains($0) }
        hiddenCards = hiddenCards.intersection(current)
    }
}
```

**Why**: Central model that all other components reference. Must be created first as everything depends on it.
**Dependencies**: None
**Risk**: Low

---

#### Step 2: Add homeLayout property to UserGoals
**File**: `WellPlate/Models/UserGoals.swift` (line ~37, after `sleepGoalHours`)
**Action**: Add a stored `homeLayoutJSON` property and computed `homeLayout` accessor.

Add after `var sleepGoalHours: Double` (line 37):

```swift
// MARK: - Home Layout

var homeLayoutJSON: String = "{}"
```

Add the `init` parameter (with default) to the existing initializer — add `homeLayoutJSON: String = "{}"` as the last parameter and `self.homeLayoutJSON = homeLayoutJSON` in the body.

Add a new extension at the bottom of the file:

```swift
// MARK: - Home Layout Accessor

extension UserGoals {

    var homeLayout: HomeLayoutConfig {
        get {
            guard let data = homeLayoutJSON.data(using: .utf8),
                  var config = try? JSONDecoder().decode(HomeLayoutConfig.self, from: data)
            else { return .default }
            config.reconcileWithCurrentCards()
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                homeLayoutJSON = json
            }
        }
    }
}
```

**Why**: Stores layout config in the existing SwiftData model. JSON encoding avoids SwiftData Codable limitations with complex nested types. The `reconcileWithCurrentCards()` call in the getter ensures forward-compatibility when new cards are added.
**Dependencies**: Step 1 (HomeLayoutConfig must exist)
**Risk**: Low — adding a property with a default value to an existing `@Model` is a lightweight migration that SwiftData handles automatically. Same pattern as `coffeeDailyCups` which was added post-initial-release.

---

### Phase 2: Context Menu & Inline Actions

#### Step 3: Create HomeCardContextMenu ViewModifier
**File**: `WellPlate/Features + UI/Home/Components/HomeCardContextMenu.swift` (NEW)
**Action**: Create a reusable ViewModifier that wraps `.contextMenu` for home cards.

<!-- RESOLVED: L2 — "Customize..." label now includes card name for VoiceOver context -->

```swift
import SwiftUI

// MARK: - HomeCardContextMenu

/// ViewModifier that adds a long-press context menu to home screen cards.
/// Provides Hide, Customize (for compound cards), and navigation to layout editor.
struct HomeCardContextMenu: ViewModifier {
    let card: HomeCardID
    @Binding var layout: HomeLayoutConfig
    let hasHiddenCards: Bool
    var onCustomize: (() -> Void)? = nil
    var onShowLayoutEditor: (() -> Void)? = nil
    var onHide: ((HomeCardID) -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Hide this card
                Button(role: .destructive) {
                    onHide?(card)
                } label: {
                    Label("Hide Card", systemImage: "eye.slash")
                }

                // Customize sub-elements (only for compound cards)
                if card.hasSubElements {
                    Button {
                        onCustomize?()
                    } label: {
                        Label("Customize \(card.displayName)", systemImage: "slider.horizontal.3")
                    }
                }

                Divider()

                // Manage layout (only when cards are hidden)
                if hasHiddenCards {
                    Button {
                        onShowLayoutEditor?()
                    } label: {
                        Label("Manage Layout...", systemImage: "square.grid.2x2")
                    }
                }
            }
    }
}

extension View {
    func homeCardMenu(
        card: HomeCardID,
        layout: Binding<HomeLayoutConfig>,
        hasHiddenCards: Bool,
        onCustomize: (() -> Void)? = nil,
        onShowLayoutEditor: (() -> Void)? = nil,
        onHide: ((HomeCardID) -> Void)? = nil
    ) -> some View {
        modifier(HomeCardContextMenu(
            card: card,
            layout: layout,
            hasHiddenCards: hasHiddenCards,
            onCustomize: onCustomize,
            onShowLayoutEditor: onShowLayoutEditor,
            onHide: onHide
        ))
    }
}
```

**Why**: Reusable modifier keeps context menu logic out of HomeView. The `View` extension provides a clean call-site API.
**Dependencies**: Step 1 (HomeCardID)
**Risk**: Low — `.contextMenu` is well-tested in SwiftUI and doesn't conflict with tap gestures.

---

#### Step 4: Create UndoToast overlay
**File**: `WellPlate/Features + UI/Home/Components/UndoToast.swift` (NEW)

<!-- RESOLVED: M2 — Added dismissID parameter and check to prevent stale timer from dismissing fresh toasts -->

```swift
import SwiftUI

// MARK: - UndoToast

/// Auto-dismissing toast with undo action. Appears at the bottom of the screen.
/// Uses `dismissID` to prevent stale timers from dismissing a newer toast.
struct UndoToast: View {
    let message: String
    let dismissID: UUID
    let onUndo: () -> Void
    let onDismiss: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            Button {
                HapticService.impact(.light)
                onUndo()
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.darkGray))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            let id = dismissID
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.25)) {
                    onDismiss(id)
                }
            }
        }
    }
}
```

**Why**: Prevents accidental hides. The `dismissID` pattern ensures that when a user hides cards rapidly, only the timer matching the current toast can dismiss it — stale timers from previous toasts are no-ops.
**Dependencies**: None
**Risk**: Low

---

#### Step 5: Create CardCustomizeSheet
**File**: `WellPlate/Features + UI/Home/Components/CardCustomizeSheet.swift` (NEW)
**Action**: Sheet for toggling sub-elements within a compound card.

```swift
import SwiftUI

// MARK: - CardCustomizeSheet

/// Presents toggle rows for each sub-element of a compound card.
struct CardCustomizeSheet: View {
    let card: HomeCardID
    @Binding var layout: HomeLayoutConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(card.subElements) { element in
                        let isVisible = layout.isElementVisible(element, in: card)
                        Toggle(isOn: Binding(
                            get: { isVisible },
                            set: { _ in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    layout.toggleElement(element, in: card)
                                }
                            }
                        )) {
                            Label(element.displayName, systemImage: element.iconName)
                        }
                    }
                } footer: {
                    Text("Hidden elements won't appear on your home screen. If all elements are hidden, the entire card will be hidden.")
                        .font(.system(size: 12, design: .rounded))
                }
            }
            .navigationTitle("Customize \(card.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
```

**Why**: Provides element-level control for WellnessRingsCard (4 rings) and QuickStatsRow (2 tiles). Uses standard List + Toggle pattern.
**Dependencies**: Step 1 (HomeCardID, HomeElementID)
**Risk**: Low

---

### Phase 3: Home View Refactor

#### Step 6: Extend HomeSheet enum for customize sheet
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift` (line 6–18)
**Action**: Add a `.customizeCard(HomeCardID)` case to the existing `HomeSheet` enum.

Add new case:
```swift
case customizeCard(HomeCardID)
```

Add to `id` switch:
```swift
case .customizeCard(let card): return "customizeCard_\(card.rawValue)"
```

Add to `.sheet(item:)` switch (line ~322–340):
```swift
case .customizeCard(let card):
    CardCustomizeSheet(card: card, layout: layoutBinding)
```

Where `layoutBinding` is a `Binding<HomeLayoutConfig>` computed from `writableGoals` (defined in Step 7).

**Why**: Reuses the existing single-sheet pattern. No additional `.sheet()` modifiers needed.
**Dependencies**: Step 5 (CardCustomizeSheet)
**Risk**: Low

---

#### Step 7: Refactor HomeView body to data-driven rendering
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`
**Action**: This is the core change. Replace the hardcoded card stack in the `LazyVStack` with a `ForEach` over `effectiveVisibleCards`.

<!-- RESOLVED: C1 — Added `writableGoals` helper using `UserGoals.current(in: modelContext)` for all write paths. `currentGoals` kept for reads only. -->
<!-- RESOLVED: H1 — Removed `@AppStorage("hideInsightCard")`. Added migration in `migrateHideInsightCardIfNeeded()` called from onAppear. `DailyInsightCard.onDismiss` wired to `hideCard(.dailyInsight)`. -->
<!-- RESOLVED: M1 — Added `effectiveVisibleCards` computed property. ForEach uses this instead of `layout.visibleCards`. Conditional mood/journal logic moved out of cardView into the filter. -->

**7a. Remove `@AppStorage("hideInsightCard")`** (line 59):

Delete this line:
```swift
@AppStorage("hideInsightCard") private var hideInsightCard = false
```

**7b. Add layout state and helpers** (after existing `@State` declarations, ~line 60):

```swift
// MARK: - Layout Customisation State
@State private var undoState: (card: HomeCardID, previousLayout: HomeLayoutConfig, id: UUID)? = nil
@State private var showLayoutEditor = false
```

Add a read-only computed property for layout:
```swift
private var layout: HomeLayoutConfig {
    currentGoals.homeLayout
}
```

Add a safe write accessor:
```swift
/// Safe writable accessor — always returns a context-tracked UserGoals instance.
/// Use for all WRITE operations. `currentGoals` is fine for reads.
private var writableGoals: UserGoals {
    UserGoals.current(in: modelContext)
}

private var layoutBinding: Binding<HomeLayoutConfig> {
    Binding(
        get: { currentGoals.homeLayout },
        set: { newValue in
            writableGoals.homeLayout = newValue
            try? modelContext.save()
        }
    )
}
```

Add the `effectiveVisibleCards` computed property:
```swift
/// Visible cards filtered by both layout config AND runtime conditions.
/// Mood/journal cards are excluded when their display conditions aren't met,
/// keeping the ForEach identity in sync with actual rendering.
private var effectiveVisibleCards: [HomeCardID] {
    layout.visibleCards.filter { card in
        switch card {
        case .moodCheckIn:
            return !hasLoggedMoodToday
        case .journalReflection:
            return hasLoggedMoodToday && !hasJournaledToday
        default:
            return true
        }
    }
}
```

**7c. Replace card stack** (lines ~82–177):

Replace the hardcoded card views inside the `LazyVStack` with:

```swift
LazyVStack(spacing: 16) {

    // 1. Header — always visible, not customisable
    homeHeader
        .padding(.horizontal, 20)
        .padding(.top, 12)

    // 2. Data-driven card stack
    ForEach(effectiveVisibleCards, id: \.self) { card in
        cardView(for: card)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
            .homeCardMenu(
                card: card,
                layout: layoutBinding,
                hasHiddenCards: layout.hiddenCount > 0,
                onCustomize: card.hasSubElements ? {
                    activeSheet = .customizeCard(card)
                } : nil,
                onShowLayoutEditor: { showLayoutEditor = true },
                onHide: { hideCard($0) }
            )
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: effectiveVisibleCards)

    // 3. Hidden cards pill
    if layout.hiddenCount > 0 {
        HiddenCardsPill(count: layout.hiddenCount) {
            showLayoutEditor = true
        }
        .padding(.top, 8)
    }
}
.padding(.bottom, 32)
```

**7d. Add `cardView(for:)` dispatch method:**

<!-- RESOLVED: H1 — DailyInsightCard.onDismiss wired to hideCard(.dailyInsight) instead of @AppStorage -->
<!-- RESOLVED: M4 — QuickStatsRow onCoffeeLog uses working tree's simplified closure -->

```swift
@ViewBuilder
private func cardView(for card: HomeCardID) -> some View {
    switch card {
    case .dailyInsight:
        DailyInsightCard(
            card: insightEngine.dailyInsight,
            isGenerating: insightEngine.isGenerating,
            actionLabel: insightActionLabel,
            actionIcon: insightActionIcon,
            onTap: { showInsightsHub = true },
            onAction: insightQuickAction,
            onDismiss: { hideCard(.dailyInsight) }
        )
        .padding(.horizontal, 16)

    case .wellnessRings:
        WellnessRingsCard(
            rings: filteredWellnessRings,
            completionPercent: wellnessCompletionPercent,
            deltaValues: wellnessDeltaValues,
            onRingTap: { destination in
                switch destination {
                case .calories: showLogMeal = true
                case .water:    showWaterDetail = true
                case .exercise: showBurnView = true
                case .stress:   selectedTab = 1
                }
            }
        )
        .padding(.horizontal, 16)

    case .stressSparkline:
        StressSparklineStrip(
            readings: todayStressReadings,
            stressLevel: todayWellnessLog?.stressLevel,
            scoreDelta: stressScoreDelta,
            onTap: { selectedTab = 1 }
        )
        .padding(.horizontal, 16)

    case .moodCheckIn:
        // Condition already handled by effectiveVisibleCards — always show here
        MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
            .padding(.horizontal, 16)

    case .journalReflection:
        // Condition already handled by effectiveVisibleCards — always show here
        JournalReflectionCard(
            prompt: journalPromptService.currentPrompt,
            promptCategory: journalPromptService.promptCategory,
            onWriteMore: { activeSheet = .journalEntry },
            isGeneratingPrompt: journalPromptService.isGenerating
        )
        .padding(.horizontal, 16)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))

    case .quickStats:
        QuickStatsRow(
            hydrationGlasses: $hydrationGlasses,
            hydrationGoal: currentGoals.waterDailyCups,
            coffeeCups: $coffeeCups,
            coffeeGoal: currentGoals.coffeeDailyCups,
            coffeeType: todayWellnessLog?.resolvedCoffeeType,
            yesterdayWater: foodJournalViewModel.yesterdayStats.water,
            yesterdayCoffee: foodJournalViewModel.yesterdayStats.coffee,
            cupSizeML: currentGoals.waterCupSizeML,
            showWater: layout.isElementVisible(.waterTile, in: .quickStats),
            showCoffee: layout.isElementVisible(.coffeeTile, in: .quickStats),
            onWaterTap: { showWaterDetail = true },
            onCoffeeTap: { showCoffeeDetail = true },
            onCoffeeLog: { activeSheet = .coffeeTypePicker }
        )
    }
}
```

**7e. Add `filteredWellnessRings` computed property** (near existing `wellnessRings`):

```swift
/// Wellness rings filtered by layout visibility.
private var filteredWellnessRings: [WellnessRingItem] {
    let elementToDestination: [HomeElementID: WellnessRingDestination] = [
        .calorieRing: .calories,
        .waterRing: .water,
        .exerciseRing: .exercise,
        .stressRing: .stress
    ]
    let visibleDestinations = Set(
        layout.visibleElements(for: .wellnessRings)
            .compactMap { elementToDestination[$0] }
    )
    return wellnessRings.filter { visibleDestinations.contains($0.destination) }
}
```

**7f. Add `hideCard` and `undoHide` methods with undo support:**

<!-- RESOLVED: C1 — Uses `writableGoals` (not `currentGoals`) for all writes -->
<!-- RESOLVED: M2 — undo state includes UUID; dismissal checks ID match -->

```swift
private func hideCard(_ card: HomeCardID) {
    let previousLayout = layout
    let undoID = UUID()
    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        var updated = layout
        updated.hideCard(card)
        writableGoals.homeLayout = updated
        try? modelContext.save()
    }
    HapticService.impact(.medium)

    // Set undo state (replaces any pending undo)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        undoState = (card: card, previousLayout: previousLayout, id: undoID)
    }
}

private func undoHide() {
    guard let undo = undoState else { return }
    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        writableGoals.homeLayout = undo.previousLayout
        try? modelContext.save()
        undoState = nil
    }
    HapticService.impact(.light)
}

/// Only dismiss if the toast ID matches the current undo state.
/// Prevents stale timers from dismissing a newer toast.
private func dismissUndo(id: UUID) {
    guard undoState?.id == id else { return }
    undoState = nil
}
```

**7g. Add undo toast overlay** — inside the existing `ZStack` (line ~79), after the `ScrollView`:

```swift
// Undo toast overlay
if let undo = undoState {
    VStack {
        Spacer()
        UndoToast(
            message: "\(undo.card.displayName) hidden",
            dismissID: undo.id,
            onUndo: { undoHide() },
            onDismiss: { id in dismissUndo(id: id) }
        )
        .padding(.bottom, 80) // above ContextualActionBar
    }
}
```

**7h. Add @AppStorage migration** (in the `.onAppear` block):

<!-- RESOLVED: H1 — One-time migration from @AppStorage to HomeLayoutConfig -->

```swift
// In .onAppear, add after existing calls:
migrateHideInsightCardIfNeeded()
```

Add the migration helper method:

```swift
/// One-time migration: if `@AppStorage("hideInsightCard")` was true,
/// transfer that state into HomeLayoutConfig and remove the key.
private func migrateHideInsightCardIfNeeded() {
    let key = "hideInsightCard"
    guard UserDefaults.standard.bool(forKey: key) else { return }
    var updatedLayout = writableGoals.homeLayout
    updatedLayout.hideCard(.dailyInsight)
    writableGoals.homeLayout = updatedLayout
    try? modelContext.save()
    UserDefaults.standard.removeObject(forKey: key)
}
```

**7i. Add navigationDestination for layout editor** (after existing `.navigationDestination` calls):

```swift
.navigationDestination(isPresented: $showLayoutEditor) {
    HomeLayoutEditor(layout: layoutBinding)
}
```

**Why**: This is the core refactor. The `ForEach` loop renders only effective visible cards in user-defined order. The `cardView(for:)` dispatch keeps the body clean. Element-level filtering happens via `filteredWellnessRings` and `showWater`/`showCoffee` params. `writableGoals` ensures writes always go to a context-tracked object. `effectiveVisibleCards` ensures ForEach identity matches actual rendering for clean animations.
**Dependencies**: Steps 1–5
**Risk**: Medium — largest single change. The `ForEach` + `LazyVStack` animation needs testing.

---

### Phase 4: QuickStatsRow Element Filtering

#### Step 8: Add showWater/showCoffee parameters to QuickStatsRow
**File**: `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` (line ~17)
**Action**: Add two parameters with defaults, and conditionally render tiles.

Add after `var onCoffeeLog: () -> Void` (line 17):

```swift
var showWater: Bool = true
var showCoffee: Bool = true
```

Modify the `body` to conditionally render tiles:

```swift
var body: some View {
    HStack(spacing: 10) {
        if showWater {
            LiquidGaugeTile(
                style: .water,
                // ... existing params unchanged
            )
        }

        if showCoffee {
            LiquidGaugeTile(
                style: .coffee,
                // ... existing params unchanged
            )
        }
    }
    .padding(.horizontal, 16)
}
```

**Why**: When only one tile is visible, it naturally expands to fill the `HStack`. When both are hidden, the card itself is hidden by the layout config (auto-hide when all elements hidden). Default values ensure all existing call sites continue to work without changes.
**Dependencies**: None (additive change)
**Risk**: Low

---

### Phase 5: Profile Home Layout Editor

#### Step 9: Create HiddenCardsPill
**File**: `WellPlate/Features + UI/Home/Components/HiddenCardsPill.swift` (NEW)
**Action**: Subtle pill shown at the bottom of the home scroll when cards are hidden.

```swift
import SwiftUI

struct HiddenCardsPill: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count) card\(count == 1 ? "" : "s") hidden")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}
```

**Why**: Discoverability — users need a way to know cards are hidden and how to get them back without remembering to check Profile.
**Dependencies**: None
**Risk**: Low

---

#### Step 10: Create HomeLayoutEditor
**File**: `WellPlate/Features + UI/Tab/HomeLayoutEditor.swift` (NEW)

<!-- RESOLVED: H3 — Added `.deleteDisabled(true)` to both sections while keeping `.editMode(.constant(.active))` for always-visible drag handles -->
<!-- RESOLVED: L1 — Element-level customisation from ProfileEditor deferred to future enhancement. Noted in code comment. -->

```swift
import SwiftUI

struct HomeLayoutEditor: View {
    @Binding var layout: HomeLayoutConfig
    @State private var showResetAlert = false

    private var visibleCards: [HomeCardID] {
        layout.cardOrder.filter { !layout.hiddenCards.contains($0) }
    }

    private var hiddenCards: [HomeCardID] {
        layout.cardOrder.filter { layout.hiddenCards.contains($0) }
    }

    var body: some View {
        List {
            // Visible cards — reorderable
            Section {
                ForEach(visibleCards, id: \.self) { card in
                    cardRow(card, isVisible: true)
                }
                .onMove { source, destination in
                    moveVisibleCards(from: source, to: destination)
                }
                .deleteDisabled(true)
            } header: {
                Text("Visible Cards")
            } footer: {
                Text("Drag to reorder. Cards appear on your home screen in this order.")
                    .font(.system(size: 12, design: .rounded))
            }

            // Hidden cards
            if !hiddenCards.isEmpty {
                Section("Hidden Cards") {
                    ForEach(hiddenCards, id: \.self) { card in
                        cardRow(card, isVisible: false)
                    }
                    .deleteDisabled(true)
                }
            }

            // Reset
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset to Default Layout", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Home Layout")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .alert("Reset Layout?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                withAnimation {
                    layout.reset()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all cards to their default order and visibility.")
        }
    }

    @ViewBuilder
    private func cardRow(_ card: HomeCardID, isVisible: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: card.iconName)
                .font(.system(size: 16))
                .foregroundStyle(isVisible ? .primary : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(isVisible ? .primary : .secondary)

                if card.hasSubElements {
                    let visible = layout.visibleElements(for: card)
                    let total = card.subElements.count
                    Text("\(visible.count)/\(total) elements visible")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                // TODO: Future — add NavigationLink for element-level customisation from here
            }

            Spacer()

            // Toggle visibility
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if isVisible {
                        layout.hideCard(card)
                    } else {
                        layout.showCard(card)
                    }
                }
            } label: {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(isVisible ? AppColors.brand : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    /// Maps movement within the visible-only list back to the full cardOrder array.
    private func moveVisibleCards(from source: IndexSet, to destination: Int) {
        var visible = visibleCards
        visible.move(fromOffsets: source, toOffset: destination)

        // Rebuild cardOrder: visible in new order, then hidden in original order
        var newOrder: [HomeCardID] = visible
        for card in layout.cardOrder where layout.hiddenCards.contains(card) {
            newOrder.append(card)
        }
        layout.cardOrder = newOrder
    }
}
```

**Why**: The Profile editor provides full management — drag-to-reorder (via `List` + `.onMove`, which is reliable), visibility toggles, and reset. Hidden cards are shown in a separate section at the bottom.
**Dependencies**: Step 1 (HomeLayoutConfig)
**Risk**: Low

---

#### Step 11: Add Home Layout section to ProfileView
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`
**Action**: Add a "Home Layout" card between the goals section and symptom tracking section.

**11a. Add state variable** (near existing state declarations, ~line 77):

```swift
@State private var showHomeLayout = false
```

**11b. Add the section card** in the `VStack` inside the `ScrollView`, after `goalsSnapshotCard` (~line 136) and before `symptomTrackingCard`:

```swift
// ── Home layout ─────────────────────
homeLayoutCard
    .padding(.horizontal, 16)
```

**11c. Add the card computed property** (as a private var in the view body section):

<!-- RESOLVED: C1 — ProfileView binding uses `UserGoals.current(in: modelContext)` for safe writes -->

```swift
private var homeLayoutCard: some View {
    Button {
        showHomeLayout = true
    } label: {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Home Layout")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                let goals = userGoalsList.first ?? UserGoals.defaults()
                let hidden = goals.homeLayout.hiddenCount
                Text(hidden > 0 ? "\(hidden) card\(hidden == 1 ? "" : "s") hidden" : "All cards visible")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }
    .buttonStyle(.plain)
}
```

**11d. Add navigationDestination** (near existing `.navigationDestination` calls, ~line 204):

```swift
.navigationDestination(isPresented: $showHomeLayout) {
    HomeLayoutEditor(layout: Binding(
        get: { (userGoalsList.first ?? UserGoals.defaults()).homeLayout },
        set: { newValue in
            let goals = UserGoals.current(in: modelContext)
            goals.homeLayout = newValue
            try? modelContext.save()
        }
    ))
}
```

**Why**: Natural discovery point — Profile is where users manage their preferences. The card shows hidden count as a subtitle for at-a-glance status. The binding setter uses `UserGoals.current(in:)` to ensure writes always hit a context-tracked object.
**Dependencies**: Step 10 (HomeLayoutEditor)
**Risk**: Low

---

### Phase 6: Build Verification & Polish

#### Step 12: Build verification
**Action**: Run all 4 build targets:

```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Why**: Verify all targets compile with the new code.
**Dependencies**: All previous steps
**Risk**: Low if steps followed correctly

---

#### Step 13: Edge case handling
**File**: Various
**Action**: Verify and handle edge cases:

1. **Empty ForEach**: If all cards are hidden, the `ForEach` produces no views — the header and hidden-cards pill still render, so the screen isn't blank
2. **Minimum visible cards**: NOT enforced — users can hide everything. The HiddenCardsPill and Profile editor are always accessible for recovery
3. **MoodCheckIn + JournalReflection**: Conditional logic now lives in `effectiveVisibleCards` — if the card is layout-hidden OR its condition is false, it's excluded from the ForEach entirely. Clean identity tracking.
4. **ContextualActionBar**: Remains always visible and functional. Its actions (log meal, add water, etc.) work regardless of which cards are visible — they trigger navigation/state changes, not card interactions
5. **`wellnessCompletionPercent`**: Continues using all 4 rings for calculation, regardless of visibility. Hiding is cosmetic, not functional
6. **@AppStorage migration**: One-time migration in `onAppear` transfers `hideInsightCard` state to HomeLayoutConfig and removes the UserDefaults key

**Dependencies**: Step 7
**Risk**: Low

---

## Testing Strategy

### Build Verification
- All 4 xcodebuild targets pass

### Manual Verification Flows

1. **Hide a card**: Long-press WellnessRingsCard → tap "Hide Card" → verify card animates out → verify undo toast appears → tap "Undo" → verify card reappears
2. **Rapid hide**: Hide card A, immediately hide card B → verify toast shows card B → verify 3-second timer only dismisses card B's toast (not prematurely)
3. **Customize elements**: Long-press WellnessRingsCard → tap "Customize Wellness Rings" → toggle off Calorie Ring → dismiss sheet → verify only 3 rings visible
4. **Hide all elements**: Toggle off all 4 rings → verify card auto-hides
5. **Profile editor**: Navigate to Profile → tap "Home Layout" → verify all cards listed → drag to reorder → verify order persists on home screen
6. **Show hidden card**: In Profile editor → tap eye icon on hidden card → verify it appears on home screen
7. **Reset**: In Profile editor → tap "Reset to Default Layout" → confirm → verify all cards visible in original order
8. **Hidden cards pill**: Hide 2 cards → scroll to bottom of home → verify "2 cards hidden" pill visible → tap it → verify navigates to Profile editor
9. **Persistence**: Hide a card → kill app → relaunch → verify card still hidden
10. **Conditional cards**: Hide MoodCheckIn → log mood → verify MoodCheckIn stays hidden (user preference overrides). Un-hide MoodCheckIn in Profile → verify it appears only when mood not logged.
11. **QuickStats single tile**: Customize QuickStats → hide Coffee → verify Water tile takes full width
12. **DailyInsightCard dismiss button**: Tap DailyInsightCard's dismiss button → verify card hides via HomeLayoutConfig (not AppStorage)
13. **@AppStorage migration**: On a device that had `hideInsightCard=true`, verify DailyInsightCard starts hidden after update, and UserDefaults key is removed
14. **Fresh install**: On first launch with no UserGoals, hide a card → verify it persists (tests `writableGoals` path)

## Risks & Mitigations

- **Risk**: `ForEach` animation glitches in `LazyVStack` when items change
  - Mitigation: Use `.animation(.spring(...), value: effectiveVisibleCards)` on the `ForEach` block. `effectiveVisibleCards` ensures identity matches rendering. If glitches persist, switch to regular `VStack` (6 cards is well within non-lazy performance bounds)

- **Risk**: Context menu triggering accidental hides on quick users
  - Mitigation: Undo toast with 3-second window. "Hide" is marked `role: .destructive` (red text) for visual warning

- **Risk**: SwiftData lightweight migration failure with new `homeLayoutJSON` property
  - Mitigation: Default value of `"{}"` should trigger automatic lightweight migration. If not, add explicit `SchemaMigrationPlan`. Test on device with existing data.

- **Risk**: `layoutBinding` writes triggering excessive SwiftData saves
  - Mitigation: Saves only happen on explicit user actions (hide, show, reorder, toggle). No continuous saves. The binding set closure calls `try? modelContext.save()` which is idempotent.

- **Risk**: `writableGoals` fetch-or-create on every call
  - Mitigation: `UserGoals.current(in:)` does a single `FetchDescriptor` query — O(1) since there's at most one UserGoals instance. The cost is negligible and only triggered on user-initiated writes (not per-frame).

## Success Criteria

- [ ] Users can hide any card via long-press context menu
- [ ] Users can restore hidden cards from Profile "Home Layout" section
- [ ] Users can reorder cards via Profile editor drag-to-reorder
- [ ] WellnessRingsCard supports per-ring visibility toggles
- [ ] QuickStatsRow supports per-tile visibility toggles
- [ ] Preferences persist across app launches
- [ ] Undo toast appears after hiding with working undo
- [ ] Rapid hide doesn't cause premature toast dismissal
- [ ] "N cards hidden" pill appears on home screen when cards are hidden
- [ ] DailyInsightCard dismiss button uses HomeLayoutConfig (not @AppStorage)
- [ ] @AppStorage("hideInsightCard") migrated on first launch
- [ ] Fresh install with no UserGoals → hide card persists correctly
- [ ] All 4 build targets pass
- [ ] Existing home screen functionality (meal logging, water/coffee, mood, journal, navigation) works unchanged
