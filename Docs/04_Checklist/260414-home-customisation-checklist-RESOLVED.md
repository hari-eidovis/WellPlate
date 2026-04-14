# Implementation Checklist: Home Screen Content Customisation (RESOLVED)

**Source Plan**: `Docs/02_Planning/Specs/260414-home-customisation-plan-RESOLVED.md`
**Date**: 2026-04-14

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|----|----------|-------|------------|
| M1 | MEDIUM | `resetToDefaults()` not updated — stale layout on reset | Added checklist item to add `homeLayoutJSON = "{}"` to `resetToDefaults()` |
| M2 | MEDIUM | Migration ordering in `onAppear` not explicit | Specified placement: after `insightEngine.bindContext()`, before `generateInsights()` |
| L1 | LOW | Init parameter placement could be more specific | Clarified: "after `sleepGoalHours: Double = 8.0`" |

---

## Pre-Implementation

- [ ] Read and understand the RESOLVED plan
- [ ] Verify affected files exist:
  - [ ] `WellPlate/Models/UserGoals.swift` — exists, will be modified
  - [ ] `WellPlate/Features + UI/Home/Views/HomeView.swift` — exists, will be modified
  - [ ] `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` — exists, will be modified
  - [ ] `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` — exists, no changes (filtering at call site)
  - [ ] `WellPlate/Features + UI/Tab/ProfileView.swift` — exists, will be modified
- [ ] Verify new file directories exist:
  - [ ] `WellPlate/Models/` — for `HomeLayoutConfig.swift`
  - [ ] `WellPlate/Features + UI/Home/Components/` — for 4 new component files
  - [ ] `WellPlate/Features + UI/Tab/` — for `HomeLayoutEditor.swift`

---

## Phase 1: Data Model & Persistence

### 1.1 — Create HomeLayoutConfig model

- [ ] Create new file `WellPlate/Models/HomeLayoutConfig.swift`
- [ ] Add `import Foundation` at the top
- [ ] Define `HomeCardID` enum:
  - [ ] Conforms to `String, Codable, CaseIterable, Identifiable, Hashable`
  - [ ] Cases in working-tree display order: `dailyInsight`, `wellnessRings`, `stressSparkline`, `moodCheckIn`, `journalReflection`, `quickStats`
  - [ ] Add `var id: String { rawValue }`
  - [ ] Add `displayName` computed property (switch over all cases)
  - [ ] Add `iconName` computed property (SF Symbol names)
  - [ ] Add `hasSubElements: Bool` (true for `.wellnessRings`, `.quickStats`)
  - [ ] Add `subElements: [HomeElementID]` (returns ring/tile element IDs for compound cards, `[]` for others)
  - Verify: Enum compiles, `HomeCardID.allCases.count == 6`, order is dailyInsight-first
- [ ] Define `HomeElementID` enum:
  - [ ] Conforms to `String, Codable, CaseIterable, Identifiable, Hashable`
  - [ ] Cases: `calorieRing`, `waterRing`, `exerciseRing`, `stressRing`, `waterTile`, `coffeeTile`
  - [ ] Add `var id: String { rawValue }`
  - [ ] Add `displayName` and `iconName` computed properties
  - Verify: Enum compiles, `HomeElementID.allCases.count == 6`
- [ ] Define `HomeLayoutConfig` struct:
  - [ ] Conforms to `Codable, Equatable`
  - [ ] Properties: `var cardOrder: [HomeCardID]`, `var hiddenCards: Set<HomeCardID>`, `var hiddenElements: [HomeCardID: Set<HomeElementID>]`
  - [ ] Init with defaults: `cardOrder: HomeCardID.allCases`, `hiddenCards: []`, `hiddenElements: [:]`
  - [ ] Add `static let default = HomeLayoutConfig()`
  - [ ] Add `var visibleCards: [HomeCardID]` (filters cardOrder by hiddenCards)
  - [ ] Add `var hiddenCount: Int`
  - [ ] Add `func isElementVisible(_:in:) -> Bool`
  - [ ] Add `func visibleElements(for:) -> [HomeElementID]`
  - [ ] Add `mutating func hideCard(_:)`
  - [ ] Add `mutating func showCard(_:)`
  - [ ] Add `mutating func toggleElement(_:in:)` — includes auto-hide when all elements hidden, NO dead-code auto-show branch
  - [ ] Add `mutating func moveCard(from:to:)`
  - [ ] Add `mutating func reset()`
  - [ ] Add `mutating func reconcileWithCurrentCards()` — appends new enum cases, removes stale ones
  - Verify: File compiles. `HomeLayoutConfig.default.visibleCards.count == 6`. `HomeLayoutConfig.default.hiddenCount == 0`.

### 1.2 — Add homeLayout property to UserGoals

- [ ] Open `WellPlate/Models/UserGoals.swift`
- [ ] Add stored property after `var sleepGoalHours: Double` (~line 37):
  ```swift
  // MARK: - Home Layout
  var homeLayoutJSON: String = "{}"
  ```
<!-- RESOLVED: L1 — Clarified init parameter placement: after sleepGoalHours -->
- [ ] Add `homeLayoutJSON: String = "{}"` after the `sleepGoalHours: Double = 8.0` parameter in the `init(...)` method
- [ ] Add `self.homeLayoutJSON = homeLayoutJSON` in the init body (after `self.sleepGoalHours = sleepGoalHours`)
<!-- RESOLVED: M1 — Added checklist item to reset homeLayoutJSON in resetToDefaults() -->
- [ ] Add `homeLayoutJSON = "{}"` to `resetToDefaults()` method (~line 167, after `sleepGoalHours = 8.0`)
  - Verify: `resetToDefaults()` now resets all properties including home layout
- [ ] Add new extension at the bottom of the file:
  ```swift
  // MARK: - Home Layout Accessor
  extension UserGoals {
      var homeLayout: HomeLayoutConfig {
          get { /* decode JSON, reconcile, return */ }
          set { /* encode to JSON */ }
      }
  }
  ```
  - [ ] Getter: decode `homeLayoutJSON` → `HomeLayoutConfig`, call `reconcileWithCurrentCards()`, return `.default` on failure
  - [ ] Setter: encode `HomeLayoutConfig` → JSON string, assign to `homeLayoutJSON`
- [ ] Verify: `UserGoals.defaults().homeLayout == HomeLayoutConfig.default`
- [ ] Verify: Build succeeds — SwiftData lightweight migration handles the new property

---

## Phase 2: Context Menu & Inline Actions

### 2.1 — Create HomeCardContextMenu ViewModifier

- [ ] Create new file `WellPlate/Features + UI/Home/Components/HomeCardContextMenu.swift`
- [ ] Add `import SwiftUI`
- [ ] Define `HomeCardContextMenu: ViewModifier`:
  - [ ] Properties: `let card: HomeCardID`, `@Binding var layout: HomeLayoutConfig`, `let hasHiddenCards: Bool`, `var onCustomize: (() -> Void)?`, `var onShowLayoutEditor: (() -> Void)?`, `var onHide: ((HomeCardID) -> Void)?`
  - [ ] `body`: wraps content with `.contextMenu` containing:
    - [ ] "Hide Card" button (`role: .destructive`, icon `eye.slash`)
    - [ ] "Customize [card.displayName]" button (only if `card.hasSubElements`, icon `slider.horizontal.3`)
    - [ ] `Divider()`
    - [ ] "Manage Layout..." button (only if `hasHiddenCards`, icon `square.grid.2x2`)
- [ ] Add `View` extension with `.homeCardMenu(card:layout:hasHiddenCards:onCustomize:onShowLayoutEditor:onHide:)` convenience method
- [ ] Verify: File compiles

### 2.2 — Create UndoToast

- [ ] Create new file `WellPlate/Features + UI/Home/Components/UndoToast.swift`
- [ ] Add `import SwiftUI`
- [ ] Define `UndoToast: View`:
  - [ ] Properties: `let message: String`, `let dismissID: UUID`, `let onUndo: () -> Void`, `let onDismiss: (UUID) -> Void`
  - [ ] Body: `HStack` with message text (white) + "Undo" button (yellow, bold)
  - [ ] Background: `Capsule` filled with `Color(.darkGray)` + shadow
  - [ ] Transition: `.move(edge: .bottom).combined(with: .opacity)`
  - [ ] `.onAppear`: captures `dismissID`, starts `Task.sleep(for: .seconds(3))`, then calls `onDismiss(id)` with animation
- [ ] Verify: File compiles. The `onDismiss` closure receives the UUID, NOT a void closure.

### 2.3 — Create CardCustomizeSheet

- [ ] Create new file `WellPlate/Features + UI/Home/Components/CardCustomizeSheet.swift`
- [ ] Add `import SwiftUI`
- [ ] Define `CardCustomizeSheet: View`:
  - [ ] Properties: `let card: HomeCardID`, `@Binding var layout: HomeLayoutConfig`, `@Environment(\.dismiss) private var dismiss`
  - [ ] Body: `NavigationStack` → `List` → `Section` with `ForEach(card.subElements)` → `Toggle` for each element
  - [ ] Toggle binding: custom `Binding(get: { isVisible }, set: { _ in layout.toggleElement(element, in: card) })` with `withAnimation`
  - [ ] Footer text explaining auto-hide behavior
  - [ ] Navigation title: "Customize \(card.displayName)"
  - [ ] Toolbar: "Done" button to dismiss
  - [ ] Presentation: `.presentationDetents([.medium])`, `.presentationDragIndicator(.visible)`
- [ ] Verify: File compiles

---

## Phase 3: HomeView Refactor

### 3.1 — Extend HomeSheet enum

- [ ] Open `WellPlate/Features + UI/Home/Views/HomeView.swift`
- [ ] Add case to `HomeSheet` enum (~line 9):
  ```swift
  case customizeCard(HomeCardID)
  ```
- [ ] Add to `id` switch:
  ```swift
  case .customizeCard(let card): return "customizeCard_\(card.rawValue)"
  ```
- [ ] Verify: Enum compiles

### 3.2 — Remove @AppStorage and add layout state

- [ ] Delete line `@AppStorage("hideInsightCard") private var hideInsightCard = false` (~line 59)
- [ ] Add after existing `@State` declarations (~line 60):
  ```swift
  @State private var undoState: (card: HomeCardID, previousLayout: HomeLayoutConfig, id: UUID)? = nil
  @State private var showLayoutEditor = false
  ```
- [ ] Add computed properties after `currentGoals` (~line 68):
  ```swift
  private var layout: HomeLayoutConfig {
      currentGoals.homeLayout
  }

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
- [ ] Add `effectiveVisibleCards` computed property:
  ```swift
  private var effectiveVisibleCards: [HomeCardID] {
      layout.visibleCards.filter { card in
          switch card {
          case .moodCheckIn: return !hasLoggedMoodToday
          case .journalReflection: return hasLoggedMoodToday && !hasJournaledToday
          default: return true
          }
      }
  }
  ```
- [ ] Verify: All added properties compile. No references to `hideInsightCard` remain.

### 3.3 — Replace hardcoded card stack with ForEach

- [ ] Replace the content inside the `LazyVStack(spacing: 16)` (lines ~82–177) with:
  - [ ] Header (unchanged): `homeHeader` with padding
  - [ ] `ForEach(effectiveVisibleCards, id: \.self) { card in ... }` wrapping `cardView(for: card)` with:
    - [ ] `.transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))` on each card
    - [ ] `.homeCardMenu(card:layout:hasHiddenCards:onCustomize:onShowLayoutEditor:onHide:)` on each card
  - [ ] `.animation(.spring(response: 0.4, dampingFraction: 0.75), value: effectiveVisibleCards)` on the `ForEach`
  - [ ] `HiddenCardsPill` at the bottom (conditional: `layout.hiddenCount > 0`)
- [ ] Remove the old hardcoded card calls (WellnessRingsCard, StressSparklineStrip, `if !hideInsightCard`, MoodCheckInCard, JournalReflectionCard, QuickStatsRow, DailyInsightCard)
- [ ] Verify: No duplicate card rendering. The old `if !hideInsightCard { ... }` block is fully removed.

### 3.4 — Add cardView(for:) dispatch method

- [ ] Add `@ViewBuilder private func cardView(for card: HomeCardID) -> some View` with a switch over all 6 cases:
  - [ ] `.dailyInsight`: `DailyInsightCard(...)` — include `onDismiss: { hideCard(.dailyInsight) }` (NOT `hideInsightCard = true`)
  - [ ] `.wellnessRings`: `WellnessRingsCard(rings: filteredWellnessRings, ...)` — uses filtered rings
  - [ ] `.stressSparkline`: `StressSparklineStrip(...)` — unchanged params
  - [ ] `.moodCheckIn`: `MoodCheckInCard(...)` — no `if !hasLoggedMoodToday` wrapper (condition handled by `effectiveVisibleCards`)
  - [ ] `.journalReflection`: `JournalReflectionCard(...)` — no `if` wrapper, keep `.transition(.asymmetric(...))`
  - [ ] `.quickStats`: `QuickStatsRow(...)` — add `showWater:` and `showCoffee:` params, use `layout.isElementVisible(...)`. `onCoffeeLog` matches working tree: `{ activeSheet = .coffeeTypePicker }`
- [ ] Verify: Switch is exhaustive. All card parameters match the current working tree's call sites.

### 3.5 — Add filteredWellnessRings

- [ ] Add computed property near existing `wellnessRings`:
  ```swift
  private var filteredWellnessRings: [WellnessRingItem] { ... }
  ```
  - [ ] Maps `HomeElementID` → `WellnessRingDestination` (calorieRing→calories, waterRing→water, exerciseRing→exercise, stressRing→stress)
  - [ ] Filters `wellnessRings` to only include destinations whose elements are visible
- [ ] Verify: When all elements visible, `filteredWellnessRings.count == wellnessRings.count`

### 3.6 — Add hideCard, undoHide, dismissUndo methods

- [ ] Add `private func hideCard(_ card: HomeCardID)`:
  - [ ] Captures `previousLayout` before mutation
  - [ ] Creates `UUID` for undo tracking
  - [ ] Uses `writableGoals.homeLayout = updated` (NOT `currentGoals`)
  - [ ] Calls `modelContext.save()`
  - [ ] Fires `HapticService.impact(.medium)`
  - [ ] Sets `undoState` with animation
- [ ] Add `private func undoHide()`:
  - [ ] Restores `undo.previousLayout` to `writableGoals.homeLayout`
  - [ ] Calls `modelContext.save()`
  - [ ] Sets `undoState = nil`
  - [ ] Fires `HapticService.impact(.light)`
- [ ] Add `private func dismissUndo(id: UUID)`:
  - [ ] Only clears `undoState` if `undoState?.id == id` (prevents stale timer race)
- [ ] Verify: All three methods compile. `writableGoals` is used (not `currentGoals`) for writes.

### 3.7 — Add undo toast overlay

- [ ] Inside the existing `ZStack` (after `ScrollView`, before `.simultaneousGesture`), add:
  ```swift
  if let undo = undoState {
      VStack {
          Spacer()
          UndoToast(
              message: "\(undo.card.displayName) hidden",
              dismissID: undo.id,
              onUndo: { undoHide() },
              onDismiss: { id in dismissUndo(id: id) }
          )
          .padding(.bottom, 80)
      }
  }
  ```
- [ ] Verify: Toast appears correctly in ZStack. The `.padding(.bottom, 80)` keeps it above ContextualActionBar.

### 3.8 — Add @AppStorage migration

- [ ] Add `private func migrateHideInsightCardIfNeeded()`:
  - [ ] Reads `UserDefaults.standard.bool(forKey: "hideInsightCard")`
  - [ ] If true: updates `writableGoals.homeLayout` to hide `.dailyInsight`, saves context, removes the UserDefaults key
<!-- RESOLVED: M2 — Specified exact placement in onAppear: after bindContext, before generateInsights -->
- [ ] Call `migrateHideInsightCardIfNeeded()` in the `.onAppear` block — place it immediately after `insightEngine.bindContext(modelContext)` and BEFORE `Task { await insightEngine.generateInsights() }` (~line 248-249)
- [ ] Verify: No references to `@AppStorage("hideInsightCard")` or `hideInsightCard` variable remain in HomeView.

### 3.9 — Add sheet handler and navigation destinations

- [ ] Add to `.sheet(item: $activeSheet)` switch:
  ```swift
  case .customizeCard(let card):
      CardCustomizeSheet(card: card, layout: layoutBinding)
  ```
- [ ] Add navigation destination:
  ```swift
  .navigationDestination(isPresented: $showLayoutEditor) {
      HomeLayoutEditor(layout: layoutBinding)
  }
  ```
- [ ] Verify: Sheet presents correctly for `.customizeCard`. Navigation pushes HomeLayoutEditor.

---

## Phase 4: QuickStatsRow Element Filtering

### 4.1 — Add showWater/showCoffee parameters

- [ ] Open `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift`
- [ ] Add after `var onCoffeeLog: () -> Void` (~line 17):
  ```swift
  var showWater: Bool = true
  var showCoffee: Bool = true
  ```
- [ ] Wrap the water `LiquidGaugeTile` in `if showWater { ... }`
- [ ] Wrap the coffee `LiquidGaugeTile` in `if showCoffee { ... }`
- [ ] Verify: File compiles. Existing call sites (without new params) still work due to default values. When `showWater = false`, only coffee tile renders. When `showCoffee = false`, only water tile renders.

---

## Phase 5: Profile Home Layout Editor

### 5.1 — Create HiddenCardsPill

- [ ] Create new file `WellPlate/Features + UI/Home/Components/HiddenCardsPill.swift`
- [ ] Add `import SwiftUI`
- [ ] Define `HiddenCardsPill: View`:
  - [ ] Properties: `let count: Int`, `let onTap: () -> Void`
  - [ ] Body: `Button(action: onTap)` wrapping `HStack` with eye.slash icon + "\(count) card(s) hidden" text + chevron.right
  - [ ] Styling: `Capsule` background with `Color(.tertiarySystemFill)`, `.buttonStyle(.plain)`
- [ ] Verify: File compiles

### 5.2 — Create HomeLayoutEditor

- [ ] Create new file `WellPlate/Features + UI/Tab/HomeLayoutEditor.swift`
- [ ] Add `import SwiftUI`
- [ ] Define `HomeLayoutEditor: View`:
  - [ ] Properties: `@Binding var layout: HomeLayoutConfig`, `@State private var showResetAlert = false`
  - [ ] Computed: `visibleCards` (layout.cardOrder filtered visible), `hiddenCards` (filtered hidden)
  - [ ] Body: `List` with 3 sections:
    - [ ] **Visible Cards** section: `ForEach(visibleCards)` with `.onMove` and `.deleteDisabled(true)`. Footer: "Drag to reorder."
    - [ ] **Hidden Cards** section (conditional: `!hiddenCards.isEmpty`): `ForEach(hiddenCards)` with `.deleteDisabled(true)`
    - [ ] **Reset** section: destructive "Reset to Default Layout" button
  - [ ] `cardRow(_:isVisible:)` helper:
    - [ ] Icon + display name + sub-element count (if applicable) + eye toggle button
    - [ ] Eye button: toggles card visibility with spring animation
  - [ ] `moveVisibleCards(from:to:)` helper:
    - [ ] Rebuilds cardOrder: visible cards in new order, then hidden cards in original order
  - [ ] Modifiers: `.navigationTitle("Home Layout")`, `.navigationBarTitleDisplayMode(.inline)`, `.environment(\.editMode, .constant(.active))`
  - [ ] Alert: "Reset Layout?" confirmation with destructive "Reset" and "Cancel" buttons
  - [ ] TODO comment for future element-level NavigationLink
- [ ] Verify: File compiles. List shows drag handles. Delete buttons are suppressed.

### 5.3 — Add Home Layout section to ProfileView

- [ ] Open `WellPlate/Features + UI/Tab/ProfileView.swift`
- [ ] Add state variable (~line 77):
  ```swift
  @State private var showHomeLayout = false
  ```
- [ ] Add `homeLayoutCard` computed property:
  - [ ] Button with HStack: icon (square.grid.2x2 in branded tint), "Home Layout" title, hidden-count subtitle, chevron
  - [ ] Card background: `RoundedRectangle(cornerRadius: 16)` with system background + shadow
- [ ] Insert `homeLayoutCard.padding(.horizontal, 16)` in the VStack after `goalsSnapshotCard` and before `symptomTrackingCard`
- [ ] Add navigation destination:
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
  - [ ] Verify: Setter uses `UserGoals.current(in: modelContext)` (NOT `userGoalsList.first ?? .defaults()`)
- [ ] Verify: "Home Layout" card appears in Profile between Goals and Symptom Tracking. Tapping navigates to HomeLayoutEditor.

---

## Post-Implementation

### Build Verification

- [ ] Build main target:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] Build ScreenTimeMonitor:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] Build ScreenTimeReport:
  ```
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
- [ ] Build WellPlateWidget:
  ```
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```

### Final Checks

- [ ] Grep for stale references: `grep -r "hideInsightCard" WellPlate/` — should return NO results in Swift files
- [ ] Verify no duplicate card rendering — search for direct `WellnessRingsCard(` calls in HomeView body (should only be in `cardView(for:)`)
- [ ] Verify `writableGoals` is used for ALL writes, `currentGoals` only for reads
- [ ] Verify `HomeCardID.allCases` order: dailyInsight, wellnessRings, stressSparkline, moodCheckIn, journalReflection, quickStats
- [ ] Verify `resetToDefaults()` includes `homeLayoutJSON = "{}"`

### Manual Testing Flows

- [ ] **Hide a card**: Long-press WellnessRingsCard → "Hide Card" → card animates out → undo toast appears → tap "Undo" → card reappears
- [ ] **Rapid hide**: Hide card A, immediately hide card B → toast shows card B → previous toast doesn't dismiss prematurely
- [ ] **Customize rings**: Long-press WellnessRingsCard → "Customize Wellness Rings" → toggle off Calorie Ring → dismiss → only 3 rings visible
- [ ] **Hide all elements**: Toggle off all 4 rings → card auto-hides → appears in "hidden" section of Profile editor
- [ ] **Profile reorder**: Profile → Home Layout → drag to reorder → back to Home → verify new order
- [ ] **Show hidden card**: Profile → Home Layout → tap eye icon on hidden card → card appears on Home
- [ ] **Reset**: Profile → Home Layout → "Reset to Default Layout" → confirm → all cards visible in default order
- [ ] **Hidden cards pill**: Hide 2 cards → scroll bottom of Home → "2 cards hidden" pill → tap → navigates to Profile editor
- [ ] **Persistence**: Hide a card → kill app → relaunch → card still hidden
- [ ] **Conditional cards**: Hide MoodCheckIn in Profile → log mood → MoodCheckIn stays hidden. Un-hide → appears only when mood not logged.
- [ ] **QuickStats single tile**: Customize QuickStats → hide Coffee → Water tile takes full width
- [ ] **DailyInsight dismiss**: Tap DailyInsightCard's X → hides via HomeLayoutConfig → can restore from Profile
- [ ] **Fresh install**: Delete app → install → hide a card → restart → verify card still hidden
- [ ] **Goals reset**: Profile → Goals → Reset to Defaults → verify home layout also resets to default
