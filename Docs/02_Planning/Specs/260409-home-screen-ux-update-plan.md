# Implementation Plan: Home Screen UX Update

**Date**: 2026-04-09
**Strategy Source**: `Docs/02_Planning/Specs/260409-home-screen-ux-update-strategy.md`
**Status**: Ready for Implementation

---

## Overview

Replace `DragToLogOverlay` with a persistent `ContextualActionBar`, compress `HydrationCard` + `CoffeeCard` into a `QuickStatsRow`, re-enable `MealLogCard` inline, slim the header from 4 icon buttons to 2, and add delta badges to `WellnessRingsCard`. All changes are additive or surgical — no SwiftData migrations, no new ViewModels, no new `@StateObject` declarations in `HomeView`.

---

## Requirements

- Replace `DragToLogOverlay` in `.safeAreaInset(edge: .bottom)` with `ContextualActionBar`
- Remove `HydrationCard` + `CoffeeCard` from scroll stack; add `QuickStatsRow` in their place
- Re-enable `MealLogCard` at card position 3 (after mood/journal, before `QuickStatsRow`)
- Cap `MealLogCard` list height at 360 pt via a `ScrollView` wrapper
- Slim the header icon buttons from 4 to 2 (`sparkles` + `book.fill`); keep mood badge
- Add `deltaValues` parameter to `WellnessRingsCard` for delta badges
- Add `prefillFromEntry(_:)` and `@Published var yesterdayStats` to `HomeViewModel`
- Remove `dragLogProgress` state and associated `.blur` / `.overlay` effects from `HomeView`
- Remove `showWellnessCalendar` navigation destination (calendar button removed from header; `showWellnessCalendar` can be kept as dead state or removed — keep it to avoid touching the `.navigationDestination` chain)
- Extend `greeting` computed property with weekday-aware personality text

---

## Architecture Changes

| File | Change type | Summary |
|---|---|---|
| `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift` | New | `ContextualBarState` enum + bar view |
| `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift` | New | Three-tile compressed row |
| `WellPlate/Features + UI/Home/Components/QuickStatTile.swift` | New | Single tile with split touch zones |
| `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` | Modify | Add `prefillFromEntry`, `@Published var yesterdayStats` |
| `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift` | Modify | Accept `deltaValues` param; render Δ badges |
| `WellPlate/Features + UI/Home/Components/MealLogCard.swift` | Modify | Wrap `mealList` body in `ScrollView` with `.frame(maxHeight: 360)` |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | Modify | Wire everything; remove `DragToLogOverlay`; slim header |

---

## Implementation Steps

### Phase 1: New Components (zero existing-file changes — always build-safe)

---

#### Step 1.1 — Create `QuickStatTile.swift`

**File**: `WellPlate/Features + UI/Home/Components/QuickStatTile.swift`

**What to create**: A standalone tile view used inside `QuickStatsRow`. Carries a split touch zone: body area navigates, `+` button increments.

**Props**:
```swift
struct QuickStatTile: View {
    let emoji: String
    let label: String
    let value: String          // e.g. "5 / 8"
    let deltaText: String?     // e.g. "Δ +800" or nil
    let deltaPositive: Bool    // true = green, false = amber
    let showIncrementButton: Bool
    var onTap: () -> Void
    var onIncrement: (() -> Void)?
}
```

**Layout spec** (inner structure):
```
VStack(spacing: 6) {
    HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
            Text(emoji + " " + label)          // .r(11, .semibold), .secondary
            Text(value)                        // .r(15, .semibold), .primary, .contentTransition(.numericText())
            if let delta = deltaText {
                deltaBadge(delta, positive: deltaPositive)  // Capsule, 10pt
            }
        }
        Spacer()
        if showIncrementButton {
            plusButton                         // 36×36 Circle, brand color
        }
    }
}
.frame(maxWidth: .infinity, alignment: .leading)
.padding(14)
.background(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.systemBackground))
        .appShadow(radius: 12, y: 4)
)
.contentShape(RoundedRectangle(cornerRadius: 16))
.onTapGesture { onTap() }
```

**Delta badge helper** (private):
```swift
private func deltaBadge(_ text: String, positive: Bool) -> some View {
    Text(text)
        .font(.r(10, .semibold))
        .foregroundStyle(positive ? AppColors.success : AppColors.warning)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill((positive ? AppColors.success : AppColors.warning).opacity(0.12))
        )
}
```

**Plus button** (private, 44pt touch target):
```swift
private var plusButton: some View {
    Button {
        HapticService.impact(.light)
        onIncrement?()
    } label: {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppColors.brand)
            .frame(width: 36, height: 36)
            .background(Circle().fill(AppColors.brand.opacity(0.12)))
    }
    .buttonStyle(.plain)
    .frame(minWidth: 44, minHeight: 44)
    .accessibilityLabel("Add one \(label)")
}
```

**Accessibility**:
- Tile body: `.accessibilityLabel("\(label): \(value)")`
- Plus button: `.accessibilityLabel("Add one \(label)")`
- Wrap in `.accessibilityElement(children: .contain)`

**Patterns to follow**: `QuickLogTile` in `QuickLogSection.swift` for press scale effect; `HydrationCard` for haptic + sound pattern.

**Preview**:
```swift
#Preview {
    QuickStatTile(
        emoji: "💧", label: "Water", value: "5 / 8",
        deltaText: "Δ +1", deltaPositive: true,
        showIncrementButton: true,
        onTap: {}, onIncrement: {}
    )
    .padding()
}
```

**Build verification**: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

#### Step 1.2 — Create `QuickStatsRow.swift`

**File**: `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift`

**What to create**: Three `QuickStatTile` views side by side in one card container.

**Props**:
```swift
struct QuickStatsRow: View {
    @Binding var hydrationGlasses: Int
    let hydrationGoal: Int
    @Binding var coffeeCups: Int
    let coffeeGoal: Int
    let coffeeType: CoffeeType?
    let steps: Int?                         // from WellnessDayLog.steps; nil = no data
    let yesterdayWater: Int                 // for delta badge
    let yesterdayCoffee: Int                // for delta badge
    let yesterdaySteps: Int                 // for delta badge
    var onWaterTap: () -> Void
    var onCoffeeTap: () -> Void
    var onActivityTap: () -> Void
    var onCoffeeFirstCup: () -> Void        // triggers CoffeeTypePicker sheet path
}
```

**Layout**:
```swift
HStack(spacing: 10) {
    QuickStatTile(
        emoji: "💧", label: "Water",
        value: "\(hydrationGlasses) / \(hydrationGoal)",
        deltaText: waterDeltaText,
        deltaPositive: hydrationGlasses >= yesterdayWater,
        showIncrementButton: hydrationGlasses < hydrationGoal,
        onTap: { onWaterTap() },
        onIncrement: {
            SoundService.play("water_log_sound", ext: "mp3")
            hydrationGlasses += 1
        }
    )
    QuickStatTile(
        emoji: "☕", label: "Coffee",
        value: "\(coffeeCups) / \(coffeeGoal)",
        deltaText: coffeeDeltaText,
        deltaPositive: coffeeCups >= yesterdayCoffee,
        showIncrementButton: coffeeCups < coffeeGoal,
        onTap: { onCoffeeTap() },
        onIncrement: {
            SoundService.playConfirmation()
            if coffeeCups == 0 && coffeeType == nil {
                onCoffeeFirstCup()
            } else {
                coffeeCups += 1
            }
        }
    )
    QuickStatTile(
        emoji: "🏃", label: "Steps",
        value: stepsText,
        deltaText: stepsDeltaText,
        deltaPositive: (steps ?? 0) >= yesterdaySteps,
        showIncrementButton: false,
        onTap: { onActivityTap() },
        onIncrement: nil
    )
}
.padding(.horizontal, 16)
```

**Delta text helpers** (private computed vars):
```swift
private var waterDeltaText: String? {
    let diff = hydrationGlasses - yesterdayWater
    guard diff != 0 else { return nil }
    return diff > 0 ? "Δ +\(diff)" : "Δ \(diff)"
}
private var coffeeDeltaText: String? {
    let diff = coffeeCups - yesterdayCoffee
    guard diff != 0 else { return nil }
    return diff > 0 ? "Δ +\(diff)" : "Δ \(diff)"
}
private var stepsDeltaText: String? {
    guard let s = steps, yesterdaySteps > 0 else { return nil }
    let diff = s - yesterdaySteps
    if diff == 0 { return nil }
    return diff > 0 ? "Δ +\(diff)" : "Δ \(diff)"
}
private var stepsText: String {
    guard let s = steps, s > 0 else { return "—" }
    let formatted = NumberFormatter.localizedString(from: NSNumber(value: s), number: .decimal)
    return formatted
}
```

Note: `QuickStatsRow` does NOT wrap in a card container itself — the three `QuickStatTile` items each have their own card background. The row is just horizontal spacing. This matches how `HydrationCard` and `CoffeeCard` each had their own card backgrounds in the existing stack.

**Build verification**: build after creating both Step 1.1 and 1.2 files.

---

#### Step 1.3 — Create `ContextualActionBar.swift`

**File**: `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift`

**What to create**: The `ContextualBarState` enum and the `ContextualActionBar` view.

**ContextualBarState enum** (in the same file, exported — used by `HomeView`):
```swift
enum ContextualBarState: Equatable {
    case defaultActions
    case logNextMeal(mealLabel: String)
    case waterBehindPace(glassesNeeded: Int)
    case goalsCelebration
    case stressActionable(level: String)
}
```

**ContextualActionBar view props**:
```swift
struct ContextualActionBar: View {
    let state: ContextualBarState
    var onLogMeal: () -> Void
    var onAddWater: () -> Void
    var onAddCoffee: () -> Void
    var onStressTab: () -> Void
    var onSeeInsight: () -> Void
    var onLogSymptom: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
```

**Visual container** (52 pt capsule, shadow upward):
```swift
var body: some View {
    barContent
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Actions")
}

private var barContent: some View {
    HStack(spacing: 12) {
        primaryPill
        Spacer()
        trailingActions
    }
    .padding(.horizontal, 20)
    .frame(height: 52)
    .background(
        Capsule()
            .fill(Color(.secondarySystemBackground))
            .appShadow(radius: 16, y: -4)
    )
}
```

**primaryPill** (switches on state):
```swift
@ViewBuilder
private var primaryPill: some View {
    switch state {
    case .defaultActions:
        actionPill(icon: "fork.knife", label: "Log Meal", color: AppColors.brand) {
            HapticService.impact(.medium); onLogMeal()
        }
    case .logNextMeal(let label):
        actionPill(icon: "fork.knife", label: "Log \(label)", color: AppColors.brand) {
            HapticService.impact(.medium); onLogMeal()
        }
    case .waterBehindPace(let n):
        actionPill(icon: "drop.fill", label: "\(n) more to stay on track",
                   color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82)) {
            HapticService.impact(.light); onAddWater()
        }
    case .goalsCelebration:
        actionPill(icon: "party.popper", label: "All goals met!", color: AppColors.success) {
            onSeeInsight()
        }
    case .stressActionable(let level):
        actionPill(icon: "figure.mind.and.body", label: "Stress is \(level) — try breathing",
                   color: AppColors.warning) {
            onStressTab()
        }
    }
}
```

**actionPill helper** (private):
```swift
private func actionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.r(13, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(color))
    }
    .buttonStyle(.plain)
    .frame(minWidth: 44, minHeight: 44)
    .accessibilityLabel(label)
}
```

**trailingActions** (switches on state):
```swift
@ViewBuilder
private var trailingActions: some View {
    switch state {
    case .defaultActions, .logNextMeal:
        HStack(spacing: 8) {
            trailingIconButton(icon: "drop.fill",
                               color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                               label: "Add water") {
                HapticService.impact(.light)
                SoundService.play("water_log_sound", ext: "mp3")
                onAddWater()
            }
            trailingIconButton(icon: "cup.and.saucer.fill",
                               color: Color(hue: 0.08, saturation: 0.70, brightness: 0.72),
                               label: "Add coffee") {
                HapticService.impact(.light)
                SoundService.playConfirmation()
                onAddCoffee()
            }
            trailingIconButton(icon: "heart.text.square.fill",
                               color: AppColors.brand.opacity(0.8),
                               label: "Log symptom") {
                HapticService.impact(.light)
                onLogSymptom()
            }
        }
    case .waterBehindPace:
        trailingIconButton(icon: "plus", color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                           label: "Add water glass") {
            HapticService.impact(.light)
            SoundService.play("water_log_sound", ext: "mp3")
            onAddWater()
        }
    case .goalsCelebration:
        trailingIconButton(icon: "chevron.right", color: AppColors.brand, label: "See AI insight") {
            onSeeInsight()
        }
    case .stressActionable:
        trailingIconButton(icon: "play.fill", color: AppColors.warning, label: "Start breathing") {
            onStressTab()
        }
    }
}
```

**trailingIconButton helper** (private):
```swift
private func trailingIconButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(Circle().fill(color.opacity(0.12)))
    }
    .buttonStyle(.plain)
    .frame(minWidth: 44, minHeight: 44)
    .accessibilityLabel(label)
}
```

**Reduce Motion compliance**: wrap `barContent` in a conditional transition:
```swift
// In the view body, transition on state change:
barContent
    .id(state)          // forces view identity to change on state switch
    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97)))
    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: state)
```

Note: `ContextualBarState` must conform to `Equatable` for the `.animation(value:)` modifier — already declared above.

**Preview** (two states):
```swift
#Preview("Default") {
    ContextualActionBar(
        state: .defaultActions,
        onLogMeal: {}, onAddWater: {}, onAddCoffee: {},
        onStressTab: {}, onSeeInsight: {}, onLogSymptom: {}
    )
    .padding()
}

#Preview("Water Behind Pace") {
    ContextualActionBar(
        state: .waterBehindPace(glassesNeeded: 3),
        onLogMeal: {}, onAddWater: {}, onAddCoffee: {},
        onStressTab: {}, onSeeInsight: {}, onLogSymptom: {}
    )
    .padding()
}
```

**Build verification**: build all 3 new files together.

---

### Phase 2: HomeViewModel Additions

---

#### Step 2.1 — Add `yesterdayStats` and `prefillFromEntry` to `HomeViewModel`

**File**: `WellPlate/Features + UI/HomeViewModels/HomeViewModel.swift`

**Current end of file**: line 285, closing `}` of the class.

**What to add** (insert before the final `}`):

```swift
// MARK: - Yesterday Stats (for delta badges)

/// Computed once per onAppear. Not live-updated.
@Published var yesterdayStats: (water: Int, coffee: Int, steps: Int) = (0, 0, 0)

func loadYesterdayStats() {
    guard let ctx = modelContext else { return }
    let yesterday = Calendar.current.date(
        byAdding: .day, value: -1,
        to: Calendar.current.startOfDay(for: Date())
    )!
    let descriptor = FetchDescriptor<WellnessDayLog>(
        predicate: #Predicate { $0.day == yesterday }
    )
    let log = try? ctx.fetch(descriptor).first
    yesterdayStats = (
        water: log?.waterGlasses ?? 0,
        coffee: log?.coffeeCups ?? 0,
        steps: log?.steps ?? 0
    )
}

// MARK: - Add Again Prefill

/// Pre-populates the food name field so the user can quickly re-log a previous meal.
/// The serving size field is also pre-populated when available.
func prefillFromEntry(_ entry: FoodLogEntry) {
    foodDescription = entry.foodName
    if let serving = entry.servingSize, !serving.isEmpty {
        servingSize = serving
    }
}
```

**Why this approach**: `@Published var yesterdayStats` lets `HomeView` observe it without a computed property on the view layer. `loadYesterdayStats()` is called from `HomeView.onAppear`, following the same pattern as `bindContext(_:)` which is also called from `onAppear` (line 223 of `HomeView.swift`).

Note on tuple `@Published`: Swift allows publishing tuple types, but the publisher won't fire granularly on inner-value changes. Since this is set once and read once, this is acceptable. If the compiler rejects `@Published` on a tuple (rare but possible in some Swift versions), replace with a small struct:
```swift
struct YesterdayStats: Equatable {
    var water: Int = 0
    var coffee: Int = 0
    var steps: Int = 0
}
@Published var yesterdayStats = YesterdayStats()
```
Use the struct form if the tuple causes issues — it is strictly safer.

**Build verification**: build `WellPlate` scheme after this step.

---

### Phase 3: WellnessRingsCard Delta Badges

---

#### Step 3.1 — Add `deltaValues` parameter to `WellnessRingsCard`

**File**: `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift`

**Current signature** (line 25–29):
```swift
struct WellnessRingsCard: View {
    let rings: [WellnessRingItem]
    let completionPercent: Int
    var onRingTap: (WellnessRingDestination) -> Void = { _ in }
```

**New signature**:
```swift
struct WellnessRingsCard: View {
    let rings: [WellnessRingItem]
    let completionPercent: Int
    var onRingTap: (WellnessRingDestination) -> Void = { _ in }
    /// Optional delta values per ring. nil = render card identically to before (backward-compatible).
    var deltaValues: [WellnessRingDestination: Int]? = nil
```

**Where delta badges render**: inside `WellnessRingButton`, in the `VStack(spacing: 10)` below the ring circle and label stack (lines 88–139 of current file). Thread `deltaValues` down by passing it to `WellnessRingButton`.

**WellnessRingButton change** — add `deltaValue: Int?` parameter:

Current call site (line 54):
```swift
WellnessRingButton(ring: ring, animate: animate) {
```

New call site:
```swift
WellnessRingButton(ring: ring, animate: animate, deltaValue: deltaValues?[ring.destination]) {
```

Current `WellnessRingButton` struct declaration (line 78):
```swift
private struct WellnessRingButton: View {
    let ring: WellnessRingItem
    let animate: Bool
    let action: () -> Void
```

New declaration:
```swift
private struct WellnessRingButton: View {
    let ring: WellnessRingItem
    let animate: Bool
    let deltaValue: Int?
    let action: () -> Void
```

**Delta badge in WellnessRingButton body** — append after the `VStack(spacing: 2)` block (lines 130–138 of current file) that contains the label and sublabel texts. Insert:
```swift
if let delta = deltaValue, delta != 0 {
    Text(delta > 0 ? "Δ +\(delta)" : "Δ \(delta)")
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(delta > 0 ? AppColors.success : AppColors.warning)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((delta > 0 ? AppColors.success : AppColors.warning).opacity(0.12))
        )
        .transition(.scale(scale: 0.8).combined(with: .opacity))
}
```

This badge sits below the sublabel line, contained within the existing `VStack(spacing: 10)` in the button body. No layout restructuring needed.

**Existing preview** (line 159 in current file): unchanged — it passes no `deltaValues`, which defaults to `nil`, so the preview renders identically.

**Build verification**: build after this step. Confirm existing preview compiles without changes.

---

### Phase 4: MealLogCard Height Cap

---

#### Step 4.1 — Wrap `mealList` in a height-capped `ScrollView`

**File**: `WellPlate/Features + UI/Home/Components/MealLogCard.swift`

**Current `mealList` body** (lines 46–77):
```swift
private var mealList: some View {
    VStack(spacing: 0) {
        ForEach(Array(foodLogs.enumerated()), id: \.element.id) { index, entry in
            ...
        }
    }
    .background(
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    )
    .padding(.horizontal, 16)
}
```

**New `mealList` body** — wrap the `VStack` in a `ScrollView`:
```swift
private var mealList: some View {
    ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
            ForEach(Array(foodLogs.enumerated()), id: \.element.id) { index, entry in
                mealRow(entry: entry)
                    .contextMenu { ... }        // unchanged

                if index < foodLogs.count - 1 {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
    }
    .frame(maxHeight: 360)
    .background(
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    )
    .padding(.horizontal, 16)
}
```

**Important**: the `ScrollView` wraps only the `VStack(spacing: 0)` — not the `.background` modifier, which stays on the outer container. The `.frame(maxHeight: 360)` is applied to the `ScrollView`, not to the `VStack` inside it.

**Swipe actions**: `swipeActions` on a row inside a `ScrollView` within a `LazyVStack` context may behave differently from a bare `List`. Since `MealLogCard` uses `ForEach` inside `VStack` (not `List`), the `swipeActions(edge: .trailing)` modifier (line 135–141) will NOT work inside a plain `ScrollView` — `swipeActions` only works within `List` or `ForEach` in a `List`. **Resolution**: remove the `swipeActions` modifier from `mealRow` since the `contextMenu` already provides "Delete" via long-press (lines 51–63). The swipe-delete is a convenience; the context menu is the primary path.

Alternatively, wrap in a `List` instead of `ScrollView` to preserve swipe actions — but `List` introduces its own styling that conflicts with the custom `RoundedRectangle` background. The context menu path is sufficient and simpler. Remove `swipeActions` from `mealRow`.

**Build verification**: build after this step.

---

### Phase 5: HomeView Surgery

This is the largest change. Each sub-step leaves the project in a buildable state.

---

#### Step 5.1 — Add `todayFoodLogs` computed var and `contextualBarState` computed property

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Location**: add after the `todayCalories` computed property (currently around line 438).

**Add `todayFoodLogs`**:
```swift
/// Today's food log entries, filtered from the `@Query` result.
/// Used by MealLogCard and ContextualBarState.
private var todayFoodLogs: [FoodLogEntry] {
    allFoodLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
}
```

**Add `contextualBarState`** — after `todayFoodLogs`:
```swift
/// Pure computed property. Evaluated on every body call.
/// Priority: goalsCelebration > stressActionable > waterBehindPace > logNextMeal > defaultActions
private var contextualBarState: ContextualBarState {
    // 1. Goals celebration
    if wellnessCompletionPercent >= 100 {
        return .goalsCelebration
    }

    // 2. Stress actionable
    if let level = todayWellnessLog?.stressLevel?.lowercased(),
       level == "high" || level == "very high" {
        return .stressActionable(level: todayWellnessLog?.stressLevel ?? "High")
    }

    // 3. Water behind pace
    let behind = expectedCupsDeficit()
    if behind > 1 {
        return .waterBehindPace(glassesNeeded: behind)
    }

    // 4. Log next meal
    if let mealLabel = nextMealLabel() {
        return .logNextMeal(mealLabel: mealLabel)
    }

    // 5. Default
    return .defaultActions
}

/// Returns how many cups behind the user is vs. expected pace.
private func expectedCupsDeficit() -> Int {
    let target = currentGoals.waterDailyCups
    guard target > 0 else { return 0 }

    let cal = Calendar.current
    let now = Date()
    let todayStart = cal.startOfDay(for: now)
    let wakeComponents = DateComponents(hour: 7, minute: 0)
    let sleepComponents = DateComponents(hour: 22, minute: 0)
    guard let wake = cal.date(byAdding: wakeComponents, to: todayStart),
          let sleep = cal.date(byAdding: sleepComponents, to: todayStart) else { return 0 }

    let total = sleep.timeIntervalSince(wake)
    guard total > 0 else { return 0 }
    let elapsed = max(0, min(now.timeIntervalSince(wake), total))
    let fraction = elapsed / total
    let expected = Int(ceil(fraction * Double(target)))
    let behind = expected - hydrationGlasses
    return max(0, behind)
}

/// Returns the contextual meal label based on time-of-day and today's logs.
private func nextMealLabel() -> String? {
    let hour = Calendar.current.component(.hour, from: Date())

    // Breakfast window: 05:00–10:59
    if (5..<11).contains(hour) {
        let hasBreakfast = todayFoodLogs.contains {
            let h = Calendar.current.component(.hour, from: $0.createdAt)
            return (5..<11).contains(h)
        }
        return hasBreakfast ? nil : "Breakfast"
    }

    // Lunch window: 11:00–13:59
    if (11..<14).contains(hour) {
        let hasLunch = todayFoodLogs.contains {
            let h = Calendar.current.component(.hour, from: $0.createdAt)
            return (11..<14).contains(h)
        }
        return hasLunch ? nil : "Lunch"
    }

    // Dinner window: 17:00–20:59
    if (17..<21).contains(hour) {
        let hasDinner = todayFoodLogs.contains {
            let h = Calendar.current.component(.hour, from: $0.createdAt)
            return (17..<21).contains(h)
        }
        return hasDinner ? nil : "Dinner"
    }

    return nil
}
```

**Build verification**: build after adding these computed properties (no view changes yet).

---

#### Step 5.2 — Remove `dragLogProgress` state and related blur/overlay

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Remove line 52**:
```swift
@State private var dragLogProgress: CGFloat = 0   // DELETE THIS LINE
```

**Remove lines 164–169** (the `.blur` and `.overlay` modifiers applied to the `ScrollView`):
```swift
.blur(radius: dragLogProgress * 14)             // DELETE
.overlay(                                        // DELETE
    Color.black.opacity(dragLogProgress * 0.25)  // DELETE
        .ignoresSafeArea()                       // DELETE
        .allowsHitTesting(false)                 // DELETE
)                                                // DELETE
```

After removal, the `ZStack` in `body` becomes:
```swift
ZStack {
    ScrollView {
        LazyVStack(spacing: 16) {
            // cards
        }
        .padding(.bottom, 32)
    }
}
```

**Build verification**: build to confirm `dragLogProgress` is not referenced anywhere else.

---

#### Step 5.3 — Slim the header: remove `calendar` and `heart.text.square.fill` buttons

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current header** (lines 333–403): contains 4 buttons: `sparkles`, `calendar`, `heart.text.square.fill`, `book.fill`.

**Remove the calendar button block** (approximately lines 358–365):
```swift
// Calendar button — DELETE ENTIRE BLOCK
Button {
    HapticService.impact(.light)
    showWellnessCalendar = true
} label: {
    headerIcon("calendar")
}
.buttonStyle(.plain)
```

**Remove the symptom button block** (approximately lines 367–374):
```swift
// Symptom quick-log button — DELETE ENTIRE BLOCK
Button {
    HapticService.impact(.light)
    activeSheet = .symptomLog
} label: {
    headerIcon("heart.text.square.fill")
}
.buttonStyle(.plain)
.accessibilityLabel("Log a symptom")
```

**Keep**: `sparkles` button (AI Insight) and `book.fill` button (Journal History). Keep the mood badge block unchanged.

**Update the comment** on the `headerIcon` helper (line 406):
```swift
// MARK: - Header Icon Helper (38pt — 2 icons + optional mood badge)
```

**Note on `showWellnessCalendar`**: the `@State private var showWellnessCalendar = false` (line 44) and its `.navigationDestination(isPresented: $showWellnessCalendar)` (lines 210–212) are kept as-is — removing them would require also removing the navigation destination, which risks a compile error if anything else references them. Leave them as harmless dead state for now. The strategy's non-goals section explicitly defers moving the calendar to Profile tab.

**Build verification**: build after this step.

---

#### Step 5.4 — Extend `greeting` with weekday-aware personality

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current `greeting` computed property** (lines 547–554):
```swift
private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12:  return "Good Morning, Alex"
    case 12..<17: return "Good Afternoon, Alex"
    default:      return "Good Evening, Alex"
    }
}
```

**New `greeting`** — weekday-aware, streak-acknowledging:
```swift
private var greeting: String {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: Date())
    let weekday = cal.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ..., 7=Sat

    let timePrefix: String
    switch hour {
    case 5..<12:  timePrefix = "Good Morning"
    case 12..<17: timePrefix = "Good Afternoon"
    default:      timePrefix = "Good Evening"
    }

    // Personality suffixes by weekday
    let suffix: String
    switch weekday {
    case 2: suffix = "— new week, fresh start"   // Monday
    case 4: suffix = "— halfway there"           // Wednesday
    case 6: suffix = "— almost the weekend"      // Friday
    case 7: suffix = "— enjoy your Saturday"     // Saturday
    case 1: suffix = "— rest and recharge"       // Sunday
    default: suffix = ""
    }

    return suffix.isEmpty ? "\(timePrefix), Alex" : "\(timePrefix) \(suffix)"
}
```

**Build verification**: build after this step.

---

#### Step 5.5 — Wire `yesterdayStats` load into `onAppear`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current `onAppear` block** (lines 221–229):
```swift
.onAppear {
    foodJournalViewModel.bindContext(modelContext)
    insightService.bindContext(modelContext)
    refreshTodayMoodState()
    refreshTodayHydrationState()
    refreshTodayCoffeeState()
    refreshTodayJournalState()
}
```

**New `onAppear`** — add `loadYesterdayStats()` call:
```swift
.onAppear {
    foodJournalViewModel.bindContext(modelContext)
    insightService.bindContext(modelContext)
    refreshTodayMoodState()
    refreshTodayHydrationState()
    refreshTodayCoffeeState()
    refreshTodayJournalState()
    foodJournalViewModel.loadYesterdayStats()
}
```

**Build verification**: build after this step.

---

#### Step 5.6 — Replace `HydrationCard` + `CoffeeCard` with `QuickStatsRow` in scroll stack

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current card positions 5–6** (lines 133–148):
```swift
// 5. Hydration
HydrationCard(
    glassesConsumed: $hydrationGlasses,
    totalGlasses: currentGoals.waterDailyCups,
    cupSizeML: currentGoals.waterCupSizeML,
    onTap: { showWaterDetail = true }
)
.padding(.horizontal, 16)

// 6. Coffee
CoffeeCard(
    cupsConsumed: $coffeeCups,
    totalCups: currentGoals.coffeeDailyCups,
    coffeeType: todayWellnessLog?.resolvedCoffeeType,
    onTap: { showCoffeeDetail = true }
)
.padding(.horizontal, 16)
```

**Replace with**:
```swift
// 5. Quick Stats (Water + Coffee + Activity)
QuickStatsRow(
    hydrationGlasses: $hydrationGlasses,
    hydrationGoal: currentGoals.waterDailyCups,
    coffeeCups: $coffeeCups,
    coffeeGoal: currentGoals.coffeeDailyCups,
    coffeeType: todayWellnessLog?.resolvedCoffeeType,
    steps: todayWellnessLog?.steps,
    yesterdayWater: foodJournalViewModel.yesterdayStats.water,
    yesterdayCoffee: foodJournalViewModel.yesterdayStats.coffee,
    yesterdaySteps: foodJournalViewModel.yesterdayStats.steps,
    onWaterTap: { showWaterDetail = true },
    onCoffeeTap: { showCoffeeDetail = true },
    onActivityTap: { showBurnView = true },
    onCoffeeFirstCup: { activeSheet = .coffeeTypePicker }
)
```

Note: `QuickStatsRow` does not take `.padding(.horizontal, 16)` because the individual tiles already have horizontal padding inside the `HStack` — the row handles its own internal padding via `.padding(.horizontal, 16)` inside `QuickStatsRow.swift`.

**Important**: the `coffeeCups` binding in `QuickStatsRow` must drive `HomeView.onChange(of: coffeeCups)` correctly. The increment paths in `QuickStatTile` mutate `coffeeCups += 1` directly on the binding, which will fire `onChange(of: coffeeCups)` in `HomeView` exactly as before — no change to the coffee logging logic is needed.

The `onCoffeeFirstCup` closure sets `activeSheet = .coffeeTypePicker` to show the picker when incrementing from 0 with no type set. The tile in `QuickStatsRow` checks `coffeeCups == 0 && coffeeType == nil` before deciding which path to take (see Step 1.2 above).

**Build verification**: build after this step.

---

#### Step 5.7 — Re-enable `MealLogCard` at position 3

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Location**: insert after the mood/journal block (position 4, currently ending around line 130) and before the new `QuickStatsRow` (position 5).

**New card position 4 (Today's Meals)**:
```swift
// 4. Today's Meals
MealLogCard(
    foodLogs: todayFoodLogs,
    isToday: true,
    onDelete: { entry in
        modelContext.delete(entry)
        try? modelContext.save()
    },
    onAddAgain: { entry in
        foodJournalViewModel.prefillFromEntry(entry)
        showLogMeal = true
    }
)
.padding(.horizontal, 16)
```

Note: `.padding(.horizontal, 16)` is applied at the call site in `HomeView`, NOT inside `MealLogCard`. Looking at `MealLogCard.swift`, `mealList` already applies its own `.padding(.horizontal, 16)` to the card container (line 76–77), and `emptyState` also applies `.padding(.horizontal, 16)` (line 248–249). This means if `HomeView` also applies `.padding(.horizontal, 16)`, the result is double-padded.

**Resolution**: the call site in `HomeView` should NOT add `.padding(.horizontal, 16)` for `MealLogCard` — the padding is already baked into the component. The strategy document's code snippet shows `.padding(.horizontal, 16)` at the call site, but this conflicts with the internal padding. Follow the existing component behavior: no external horizontal padding.

```swift
// 4. Today's Meals — no .padding(.horizontal, 16) here
MealLogCard(
    foodLogs: todayFoodLogs,
    isToday: true,
    onDelete: { entry in
        modelContext.delete(entry)
        try? modelContext.save()
    },
    onAddAgain: { entry in
        foodJournalViewModel.prefillFromEntry(entry)
        showLogMeal = true
    }
)
```

**Build verification**: build after this step.

---

#### Step 5.8 — Add `WellnessRingsCard` delta values

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current `WellnessRingsCard` call** (lines 83–95):
```swift
WellnessRingsCard(
    rings: wellnessRings,
    completionPercent: wellnessCompletionPercent,
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
```

**New call** — add `deltaValues`:
```swift
WellnessRingsCard(
    rings: wellnessRings,
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
```

**Add `wellnessDeltaValues` computed property** to `HomeView` (add near `wellnessRings`):
```swift
/// Delta values passed to WellnessRingsCard for Δ badges.
/// Uses yesterdayStats from the VM for water and activity;
/// calories delta computed from allFoodLogs for yesterday.
private var wellnessDeltaValues: [WellnessRingDestination: Int]? {
    let stats = foodJournalViewModel.yesterdayStats
    // Only show deltas when we have yesterday data
    guard stats.water > 0 || stats.coffee > 0 || stats.steps > 0 else { return nil }

    var values: [WellnessRingDestination: Int] = [:]

    // Water delta: current glasses vs yesterday
    let waterDiff = hydrationGlasses - stats.water
    if waterDiff != 0 { values[.water] = waterDiff }

    // Activity (steps) delta
    if let steps = todayWellnessLog?.steps, stats.steps > 0 {
        let stepsDiff = steps - stats.steps
        if stepsDiff != 0 { values[.exercise] = stepsDiff }
    }

    return values.isEmpty ? nil : values
}
```

Note: calories delta is omitted for now because yesterday's food log calories require a separate filtered query that is not currently available in `HomeViewModel.yesterdayStats`. This is acceptable per strategy scope — the strategy mentions Δ on calories ring as a visual but doesn't require it if data is unavailable. The badge renders only when a non-nil delta exists.

**Build verification**: build after this step.

---

#### Step 5.9 — Replace `DragToLogOverlay` with `ContextualActionBar` in `.safeAreaInset`

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

**Current `.safeAreaInset` block** (lines 183–188):
```swift
.safeAreaInset(edge: .bottom) {
    DragToLogOverlay(onTrigger: {
        showLogMeal = true
    }, dragProgress: $dragLogProgress)
    .padding(.bottom, 4)
}
```

**Replace with**:
```swift
.safeAreaInset(edge: .bottom) {
    ContextualActionBar(
        state: contextualBarState,
        onLogMeal: { showLogMeal = true },
        onAddWater: {
            guard hydrationGlasses < currentGoals.waterDailyCups else { return }
            hydrationGlasses += 1
        },
        onAddCoffee: {
            if coffeeCups == 0 && todayWellnessLog?.coffeeType == nil {
                activeSheet = .coffeeTypePicker
            } else {
                coffeeCups += 1
            }
        },
        onStressTab: { selectedTab = 1 },
        onSeeInsight: {
            showAIInsight = true
            Task { await insightService.generateInsight() }
        },
        onLogSymptom: {
            HapticService.impact(.light)
            activeSheet = .symptomLog
        }
    )
    .padding(.bottom, 4)
}
```

**Why `onAddWater` doesn't call the sound**: the `ContextualActionBar` component calls `SoundService.play("water_log_sound", ext: "mp3")` internally in its trailing button action (see Step 1.3). If `HomeView` also calls sound here, there will be a double-play. Two approaches:
- Option A: `ContextualActionBar` handles sound internally (as written in Step 1.3) and `HomeView.onAddWater` closure only mutates state.
- Option B: `ContextualActionBar` has no sound logic, `HomeView` closure handles sound.

**Use Option A** (already specified in Step 1.3): the bar's button handlers call sound internally before invoking the callback. The `onAddWater` closure in `HomeView` only does `hydrationGlasses += 1`. This keeps `HomeView` consistent — it never directly calls sound, following the pattern where `HydrationCard` called sound internally.

**Build verification**: full build after this step. This is the final significant change.

---

#### Step 5.10 — Final cleanup: update `LazyVStack` comment numbering

**File**: `WellPlate/Features + UI/Home/Views/HomeView.swift`

After all changes, the card stack comments become:
```
// 1. Header
// 2. Wellness Rings Card
// (3. Quick Log — commented out, kept)
// 3. Mood Check-In / Journal Reflection
// 4. Today's Meals (MealLogCard)
// 5. Quick Stats (Water + Coffee + Activity)
```

Update the in-code comments to match the new numbering so the file remains readable.

**Build verification**: final full build of all 4 targets:
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

---

## Testing Strategy

### Build verification (after each phase)
- Phase 1 complete: `WellPlate` scheme builds with 3 new unreferenced files
- Phase 2 complete: `HomeViewModel` compiles with new published property and methods
- Phase 3 complete: `WellnessRingsCard` compiles; existing preview renders unchanged
- Phase 4 complete: `MealLogCard` compiles; `swipeActions` removed
- Phase 5 complete: all 4 targets build clean

### Manual verification flows

1. **ContextualActionBar states**:
   - Fresh launch (no data) → `logNextMeal` or `defaultActions` based on time of day
   - Log 8 water glasses (all rings complete) → `goalsCelebration` state
   - Set stress level to High in Stress tab → `stressActionable` state
   - Delete most water glasses mid-day → `waterBehindPace` state
   - Tap "Log Meal" pill → `FoodJournalView` pushes correctly

2. **QuickStatsRow interactions**:
   - Tap `+` on water tile → `hydrationGlasses` increments; sound plays; `WellnessRingsCard` ring updates
   - Tap `+` on coffee tile from 0 cups → `CoffeeTypePickerSheet` appears
   - Tap `+` on coffee tile from 1+ cups → `coffeeCups` increments; `showCoffeeWaterAlert` fires
   - Tap tile body (water) → `WaterDetailView` pushes; detail shows correct count
   - Tap activity tile → `BurnView` pushes

3. **MealLogCard**:
   - Log 0 meals → empty state shows ("No meals logged yet")
   - Log 3 meals → all visible in card
   - Log 8 meals → card is capped at 360 pt; scroll works inside cap
   - Context menu long-press → "Add Again" pre-fills food name in `FoodJournalView`
   - Context menu → "Delete" removes entry

4. **Header**:
   - Confirm only 2 icon buttons visible (sparkles, book.fill)
   - Mood badge appears after logging mood
   - `sparkles` → `HomeAIInsightView` pushes
   - `book.fill` → `JournalHistoryView` pushes

5. **Delta badges**:
   - Yesterday: 5 water, 2 coffee, 7000 steps (simulated via SwiftData seed)
   - Today: log 6 water → `WellnessRingsCard` water ring shows "Δ +1" badge
   - `QuickStatsRow` water tile shows "Δ +1" (green)

6. **Reduce Motion**:
   - Enable Reduce Motion in Settings → `ContextualActionBar` state transitions are instant (no crossfade animation)

---

## Risks & Watchouts

### W1: `@Published` tuple type in `HomeViewModel`

`@Published var yesterdayStats: (water: Int, coffee: Int, steps: Int)` — Swift's `Combine` framework can publish tuple values, but `ObservableObject` synthesis may not detect inner mutations on the tuple (only full replacement). Since `loadYesterdayStats()` always replaces the full tuple (`yesterdayStats = (...)`), this works correctly. If the compiler complains about `@Published` on a non-`Equatable` type, use a small named struct (shown in Step 2.1 fallback).

### W2: `swipeActions` only works in `List` context

`MealLogCard.mealList` uses `ForEach` inside `VStack`. After wrapping in a `ScrollView` (Step 4.1), `swipeActions` on individual rows will silently have no effect (not a compile error). Removing `swipeActions` (lines 135–141 of `MealLogCard.swift`) is required to avoid dead code. The `contextMenu` provides the same delete path.

### W3: Double horizontal padding on `MealLogCard`

`MealLogCard` applies `.padding(.horizontal, 16)` internally on both `mealList` and `emptyState`. Adding it again at the `HomeView` call site would create 32 pt total padding. Do not add `.padding(.horizontal, 16)` at the `HomeView` call site for `MealLogCard` (Step 5.7 accounts for this).

### W4: `onCoffeeFirstCup` interaction in `QuickStatsRow`

`QuickStatsRow` fires `onCoffeeFirstCup()` when `coffeeCups == 0 && coffeeType == nil`. But `coffeeCups` at this moment is still 0 — the increment hasn't happened yet. `HomeView.onChange(of: coffeeCups)` relies on `newCups > oldCups` to detect addition and trigger the picker. If `onCoffeeFirstCup` sets `activeSheet = .coffeeTypePicker` without incrementing `coffeeCups` first, the `onChange` won't fire and the optimistic cup count won't be saved until the picker closes.

**Resolution**: inside `QuickStatsRow.onIncrement` for coffee, increment `coffeeCups += 1` first, then call `onCoffeeFirstCup()` for the first cup. This matches the existing `HydrationCard` approach where addition happens inline and side-effects are handled by `onChange`. Specifically in `QuickStatTile`'s increment button for the coffee tile:
```swift
onIncrement: {
    SoundService.playConfirmation()
    coffeeCups += 1        // mutate binding first
    if coffeeCups == 1 && coffeeType == nil {
        onCoffeeFirstCup() // then trigger picker
    }
}
```
This means `QuickStatsRow` needs to know whether this is the "first cup + no type" scenario. Pass this as a computed flag:
```swift
// In QuickStatsRow
private var isFirstCupNoType: Bool {
    coffeeCups == 0 && coffeeType == nil
}
```
And the increment closure:
```swift
onIncrement: {
    let wasFirst = isFirstCupNoType
    SoundService.playConfirmation()
    coffeeCups += 1
    if wasFirst { onCoffeeFirstCup() }
}
```

### W5: `ContextualBarState.Equatable` conformance for `stressActionable`

`ContextualBarState` must conform to `Equatable` for `.animation(value: state)`. Swift auto-synthesizes `Equatable` for enums with associated values only if all associated values are `Equatable`. `String` and `Int` are both `Equatable`, so auto-synthesis works. No manual conformance needed. Verify this compiles correctly — if not, add explicit `static func ==` implementation.

### W6: `contextualBarState` recomputes every body evaluation

Per the strategy's Open Risks section: if `allFoodLogs` or `allWellnessDayLogs` triggers frequent SwiftData change notifications, this could cause excessive body re-evaluations. At current app scale this is acceptable. If profiling reveals a problem, the strategy recommends elevating to a `@State` var updated via `onChange(of:)`. Keep this risk in mind during testing.

### W7: `WellnessRingsCard` delta badge layout impact

Adding a delta badge below the sublabel in `WellnessRingButton` increases the ring item's vertical height. The `VStack(spacing: 10)` (line 88 of `WellnessRingsCard.swift`) already has a fixed-height ring (64×64) above the text block. Adding the badge below the sublabel could push adjacent rings taller and cause layout inconsistency if only some rings have badges. 

**Mitigation**: use `.frame(minHeight: 14)` on the badge slot (empty when nil) to reserve constant space:
```swift
// Always reserve space for badge slot
Group {
    if let delta = deltaValue, delta != 0 {
        deltaBadgeView(delta)
    } else {
        Color.clear.frame(height: 14)  // reserve badge slot height
    }
}
```
This keeps all ring columns the same height regardless of badge presence.

### W8: `SoundService.play` call site in `ContextualActionBar`

`ContextualActionBar` calls `SoundService.play("water_log_sound", ext: "mp3")` in the trailing water button action. This requires `SoundService` to be accessible from the new component file. Since `SoundService` is in `WellPlate/Core/Services/` and all files in `WellPlate/` are auto-included in the build target (per `PBXFileSystemSynchronizedRootGroup`), this import is automatic. No explicit import needed — just call `SoundService.play(...)` directly.

### W9: `steps` in `QuickStatTile` activity tile shows `WellnessDayLog.steps`

`WellnessDayLog.steps` is written by the HealthKit integration. In the current codebase, steps are fetched by `HealthKitService` but the synchronization path into `WellnessDayLog` is not visible in the files read. If `todayWellnessLog?.steps` is always 0 (because the HealthKit sync hasn't written it today), the activity tile will show "—". This is acceptable per the strategy ("If no data, show `—`"). No code change needed — just be aware during manual testing.

---

## Success Criteria

- [ ] Project builds clean on all 4 targets with zero new warnings
- [ ] `DragToLogOverlay` is absent from `HomeView.body` (confirmed via `@safeAreaInset`)
- [ ] `dragLogProgress` state variable is removed from `HomeView`
- [ ] `HydrationCard` and `CoffeeCard` are absent from `HomeView`'s `LazyVStack` body
- [ ] `QuickStatsRow` renders water, coffee, and steps tiles in a single row
- [ ] `MealLogCard` renders inline with today's food entries
- [ ] `MealLogCard` list is capped at 360 pt height; scrollable beyond 5 entries
- [ ] Header shows exactly 2 icon buttons (`sparkles` + `book.fill`) plus optional mood badge
- [ ] `ContextualActionBar` is persistent above tab bar at all times
- [ ] Bar state changes to `logNextMeal(mealLabel:)` correctly at 08:00 with no breakfast logged
- [ ] Bar state changes to `waterBehindPace` when behind expected pace midday
- [ ] Bar state changes to `goalsCelebration` when all rings ≥ 100%
- [ ] Tapping "Log Meal" pill navigates to `FoodJournalView`
- [ ] Tapping `💧` in bar increments `hydrationGlasses`; plays water sound
- [ ] Tapping `☕` in bar increments `coffeeCups`; triggers picker on first cup
- [ ] Delta badges appear in `WellnessRingsCard` when yesterday data is available
- [ ] Delta badges appear in `QuickStatsRow` tiles when data differs from yesterday
- [ ] "Add Again" in `MealLogCard` context menu pre-fills food name in `FoodJournalView`
- [ ] `greeting` varies by day of week and time of day
- [ ] Reduce Motion setting disables bar transition animation
- [ ] All interactive elements have minimum 44×44 pt touch target
