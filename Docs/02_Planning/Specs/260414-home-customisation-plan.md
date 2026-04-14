# Implementation Plan: Home Screen Content Customisation

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
- `WellPlate/Features + UI/Home/Views/HomeView.swift` — **MODIFY**: Replace hardcoded card stack with data-driven `ForEach`; add context menus; add undo toast overlay; add hidden-cards pill
- `WellPlate/Features + UI/Home/Components/HomeCardContextMenu.swift` — **NEW**: ViewModifier for `.contextMenu` on home cards
- `WellPlate/Features + UI/Home/Components/CardCustomizeSheet.swift` — **NEW**: Sheet view for toggling sub-elements within a card
- `WellPlate/Features + UI/Home/Components/HiddenCardsPill.swift` — **NEW**: Pill overlay showing count of hidden cards
- `WellPlate/Features + UI/Home/Components/UndoToast.swift` — **NEW**: Auto-dismiss toast overlay for undo after hiding
- `WellPlate/Features + UI/Tab/HomeLayoutEditor.swift` — **NEW**: Profile sub-view with `List` + `.onMove` + visibility toggles
- `WellPlate/Features + UI/Tab/ProfileView.swift` — **MODIFY**: Add "Home Layout" section card with `NavigationLink`
- `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` — **MODIFY**: No changes to the view itself; filtering happens at the call site in HomeView
- `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` — **MODIFY**: Add `showWater`/`showCoffee` parameters for conditional tile rendering

## Implementation Steps

### Phase 1: Data Model & Persistence

#### Step 1: Create HomeLayoutConfig model
**File**: `WellPlate/Models/HomeLayoutConfig.swift` (NEW)
**Action**: Create the core data model with three types:

```swift
import Foundation

// MARK: - Home Card Identification

/// Identifies each customisable card on the home screen.
/// Raw values are used for JSON persistence — do not rename without migration.
enum HomeCardID: String, Codable, CaseIterable, Identifiable, Hashable {
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

    // MARK: - Mutations (return new copies for SwiftUI binding patterns)

    /// Hide a card. Returns updated config.
    mutating func hideCard(_ card: HomeCardID) {
        hiddenCards.insert(card)
    }

    /// Show a card. Returns updated config.
    mutating func showCard(_ card: HomeCardID) {
        hiddenCards.remove(card)
    }

    /// Toggle element visibility. Auto-hides parent card if all elements hidden.
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
        // Auto-show card if it was hidden due to all-elements-hidden and now has visible elements
        if hiddenCards.contains(card) && !visibleElements(for: card).isEmpty {
            // Only auto-show if the card was hidden implicitly (all elements off).
            // We can't distinguish implicit vs. explicit hide here, so don't auto-show.
            // User must explicitly re-show the card.
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
**File**: `WellPlate/Models/UserGoals.swift` (line ~35, after `sleepGoalHours`)
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
                        Label("Customize...", systemImage: "slider.horizontal.3")
                    }
                }

                Divider()

                // Show hidden cards (only when cards are hidden)
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
**Action**: Lightweight auto-dismiss toast shown after hiding a card.

```swift
import SwiftUI

// MARK: - UndoToast

/// Auto-dismissing toast with undo action. Appears at the bottom of the screen.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

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
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.25)) {
                    onDismiss()
                }
            }
        }
    }
}
```

**Why**: Prevents accidental hides. Standard pattern in iOS apps (Mail, Notes). Auto-dismisses after 3 seconds.
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

Where `layoutBinding` is a `Binding<HomeLayoutConfig>` computed from `currentGoals` (defined in Step 7).

**Why**: Reuses the existing single-sheet pattern. No additional `.sheet()` modifiers needed.
**Dependencies**: Step 5 (CardCustomizeSheet)
**Risk**: Low

---

#### Step 7: Refactor HomeView body to data-driven rendering
**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`
**Action**: This is the core change. Replace the hardcoded card stack in the `LazyVStack` with a `ForEach` over `layout.visibleCards`.

**7a. Add layout state and helpers** (after existing `@State` declarations, ~line 60):

```swift
// MARK: - Layout Customisation State
@State private var undoState: (card: HomeCardID, previousLayout: HomeLayoutConfig)? = nil
@State private var showLayoutEditor = false
```

Add a computed binding for layout:
```swift
private var layout: HomeLayoutConfig {
    get { currentGoals.homeLayout }
}

private var layoutBinding: Binding<HomeLayoutConfig> {
    Binding(
        get: { currentGoals.homeLayout },
        set: { newValue in
            currentGoals.homeLayout = newValue
            try? modelContext.save()
        }
    )
}
```

**7b. Replace card stack** (lines ~81–179):

Replace the hardcoded card views inside the `LazyVStack` with:

```swift
LazyVStack(spacing: 16) {

    // 1. Header — always visible, not customisable
    homeHeader
        .padding(.horizontal, 20)
        .padding(.top, 12)

    // 2. Data-driven card stack
    ForEach(layout.visibleCards, id: \.self) { card in
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
    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: layout.visibleCards)

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

**7c. Add `cardView(for:)` dispatch method:**

```swift
@ViewBuilder
private func cardView(for card: HomeCardID) -> some View {
    switch card {
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
        if !hasLoggedMoodToday {
            MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
                .padding(.horizontal, 16)
        }

    case .journalReflection:
        if hasLoggedMoodToday && !hasJournaledToday {
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
        }

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
            onCoffeeLog: {
                let wasFirst = coffeeCups == 0 && todayWellnessLog?.coffeeType == nil
                coffeeCups += 1
                if wasFirst {
                    activeSheet = .coffeeTypePicker
                } else {
                    showCoffeeWaterAlert = true
                }
            }
        )

    case .dailyInsight:
        DailyInsightCard(
            card: insightEngine.dailyInsight,
            isGenerating: insightEngine.isGenerating,
            actionLabel: insightActionLabel,
            actionIcon: insightActionIcon,
            onTap: { showInsightsHub = true },
            onAction: insightQuickAction
        )
        .padding(.horizontal, 16)
    }
}
```

**7d. Add `filteredWellnessRings` computed property** (near existing `wellnessRings`):

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

**7e. Add `hideCard` method with undo support:**

```swift
private func hideCard(_ card: HomeCardID) {
    let previousLayout = layout
    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        var updated = layout
        updated.hideCard(card)
        currentGoals.homeLayout = updated
        try? modelContext.save()
    }
    HapticService.impact(.medium)

    // Set undo state (replaces any pending undo)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        undoState = (card: card, previousLayout: previousLayout)
    }
}

private func undoHide() {
    guard let undo = undoState else { return }
    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        currentGoals.homeLayout = undo.previousLayout
        try? modelContext.save()
        undoState = nil
    }
    HapticService.impact(.light)
}
```

**7f. Add undo toast overlay** — inside the existing `ZStack` (line ~79), after the `ScrollView`:

```swift
// Undo toast overlay
if let undo = undoState {
    VStack {
        Spacer()
        UndoToast(
            message: "\(undo.card.displayName) hidden",
            onUndo: { undoHide() },
            onDismiss: { undoState = nil }
        )
        .padding(.bottom, 80) // above ContextualActionBar
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: undoState != nil)
}
```

**7g. Add navigationDestination for layout editor** (after existing `.navigationDestination` calls):

```swift
.navigationDestination(isPresented: $showLayoutEditor) {
    HomeLayoutEditor(layout: layoutBinding)
}
```

**Why**: This is the core refactor. The `ForEach` loop renders only visible cards in user-defined order. The `cardView(for:)` dispatch keeps the body clean. Element-level filtering happens via `filteredWellnessRings` and `showWater`/`showCoffee` params.
**Dependencies**: Steps 1–5
**Risk**: Medium — largest single change. The `ForEach` + `LazyVStack` animation needs testing. The existing conditional logic for mood/journal cards is preserved within the dispatch.

---

### Phase 4: QuickStatsRow Element Filtering

#### Step 8: Add showWater/showCoffee parameters to QuickStatsRow
**File**: `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` (line ~6)
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
**Action**: Full layout management view with drag-to-reorder and visibility toggles.

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
                    // Map from visible indices to cardOrder indices
                    moveVisibleCards(from: source, to: destination)
                }
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
        .environment(\.editMode, .constant(.active)) // Always in edit mode for drag handles
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
**Risk**: Low — `List` + `.onMove` is the most reliable reorder mechanism in SwiftUI.

---

#### Step 11: Add Home Layout section to ProfileView
**File**: `WellPlate/Features + UI/Tab/ProfileView.swift`
**Action**: Add a "Home Layout" card between the goals section and widget setup section.

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
            let goals = userGoalsList.first ?? UserGoals.defaults()
            goals.homeLayout = newValue
            try? modelContext.save()
        }
    ))
}
```

**Why**: Natural discovery point — Profile is where users manage their preferences. The card shows hidden count as a subtitle for at-a-glance status.
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
3. **MoodCheckIn + JournalReflection**: Both have existing conditional logic (`!hasLoggedMoodToday`, `hasLoggedMoodToday && !hasJournaledToday`). The layout hide takes precedence — if the card is in `hiddenCards`, the `ForEach` skips it entirely, so the inner condition never evaluates
4. **ContextualActionBar**: Remains always visible and functional. Its actions (log meal, add water, etc.) work regardless of which cards are visible — they trigger navigation/state changes, not card interactions
5. **`wellnessCompletionPercent`**: Continues using all 4 rings for calculation, regardless of visibility. Hiding is cosmetic, not functional

**Dependencies**: Step 7
**Risk**: Low

---

## Testing Strategy

### Build Verification
- All 4 xcodebuild targets pass

### Manual Verification Flows

1. **Hide a card**: Long-press WellnessRingsCard → tap "Hide Card" → verify card animates out → verify undo toast appears → tap "Undo" → verify card reappears
2. **Customize elements**: Long-press WellnessRingsCard → tap "Customize..." → toggle off Calorie Ring → dismiss sheet → verify only 3 rings visible
3. **Hide all elements**: Toggle off all 4 rings → verify card auto-hides
4. **Profile editor**: Navigate to Profile → tap "Home Layout" → verify all cards listed → drag to reorder → verify order persists on home screen
5. **Show hidden card**: In Profile editor → tap eye icon on hidden card → verify it appears on home screen
6. **Reset**: In Profile editor → tap "Reset to Default Layout" → confirm → verify all cards visible in original order
7. **Hidden cards pill**: Hide 2 cards → scroll to bottom of home → verify "2 cards hidden" pill visible → tap it → verify navigates to Profile editor
8. **Persistence**: Hide a card → kill app → relaunch → verify card still hidden
9. **Conditional cards**: Hide MoodCheckIn → log mood → verify MoodCheckIn stays hidden (user preference overrides)
10. **QuickStats single tile**: Customize QuickStats → hide Coffee → verify Water tile takes full width

## Risks & Mitigations

- **Risk**: `ForEach` animation glitches in `LazyVStack` when items change
  - Mitigation: Use `.animation(.spring(...), value: layout.visibleCards)` on the `ForEach` block. If glitches persist, switch to regular `VStack` (6 cards is well within non-lazy performance bounds)

- **Risk**: Context menu triggering accidental hides on quick users
  - Mitigation: Undo toast with 3-second window. "Hide" is marked `role: .destructive` (red text) for visual warning

- **Risk**: SwiftData lightweight migration failure with new `homeLayoutJSON` property
  - Mitigation: Default value of `"{}"` should trigger automatic lightweight migration. If not, add explicit `SchemaMigrationPlan`. Test on device with existing data.

- **Risk**: `layoutBinding` writes triggering excessive SwiftData saves
  - Mitigation: Saves only happen on explicit user actions (hide, show, reorder, toggle). No continuous saves. The binding set closure calls `try? modelContext.save()` which is idempotent.

## Success Criteria

- [ ] Users can hide any card via long-press context menu
- [ ] Users can restore hidden cards from Profile "Home Layout" section
- [ ] Users can reorder cards via Profile editor drag-to-reorder
- [ ] WellnessRingsCard supports per-ring visibility toggles
- [ ] QuickStatsRow supports per-tile visibility toggles
- [ ] Preferences persist across app launches
- [ ] Undo toast appears after hiding with working undo
- [ ] "N cards hidden" pill appears on home screen when cards are hidden
- [ ] All 4 build targets pass
- [ ] Existing home screen functionality (meal logging, water/coffee, mood, journal, navigation) works unchanged
