# Implementation Checklist: Home Screen UX Update

**Source Plan**: `Docs/02_Planning/Specs/260409-home-screen-ux-update-plan-RESOLVED.md`
**Strategy**: `Docs/02_Planning/Specs/260409-home-screen-ux-update-strategy.md`
**Date**: 2026-04-09

---

## Pre-Implementation

- [ ] Read the RESOLVED plan fully: `Docs/02_Planning/Specs/260409-home-screen-ux-update-plan-RESOLVED.md`
- [ ] Confirm the following files exist (they are the primary targets of modification):
  - `WellPlate/Features + UI/Home/Views/HomeView.swift`
  - `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`
  - `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift`
  - `WellPlate/Features + UI/Home/Components/MealLogCard.swift`
- [ ] Confirm the `Components/` directory exists: `WellPlate/Features + UI/Home/Components/`
  - Verify: directory contains at least `DragToLogOverlay.swift`, `HydrationCard.swift`, `CoffeeCard.swift`, `WellnessRingsCard.swift`, `MealLogCard.swift`
- [ ] Open `HomeView.swift` and note: `dragLogProgress` is at line 52, the blur/overlay block is around lines 164–169, the header icon buttons are around lines 351–383, and the `greeting` property is around lines 547–554
- [ ] Open `MealLogCard.swift` and note: `mealList` starts at line 46, `swipeActions` modifier is at lines 135–141
- [ ] Open `HomeViewModel.swift` and note: file ends at line 285 (closing `}` of the class). `foodDescription` and `servingSize` are `@Published` properties at lines 8–9
- [ ] Open `WellnessRingsCard.swift` and note: `WellnessRingDestination` enum is at line 5, `WellnessRingsCard` struct declaration is at lines 25–29, `WellnessRingButton` struct declaration is at line 78 (approx)
- [ ] Do NOT delete any existing files — all removed-from-HomeView components are kept in place

---

## Phase 1: New Components

> Create 3 new files in `WellPlate/Features + UI/Home/Components/`. These files are build-safe to add before any HomeView changes — they will be unreferenced until Phase 5.

### 1.1 — Create `QuickStatTile.swift`

- [ ] **1.1.a** — Create the file `WellPlate/Features + UI/Home/Components/QuickStatTile.swift`
  - Verify: file appears in Xcode's project navigator under `Home/Components/`

- [ ] **1.1.b** — Declare the `QuickStatTile` struct with these exact props:
  ```swift
  struct QuickStatTile: View {
      let emoji: String
      let label: String
      let value: String
      let deltaText: String?
      let deltaPositive: Bool
      let showIncrementButton: Bool
      var onTap: () -> Void
      var onIncrement: (() -> Void)?
  }
  ```
  - Verify: struct compiles without error (value/deltaText/deltaPositive types match plan)

- [ ] **1.1.c** — Implement the tile body layout: `VStack(spacing: 6)` containing an `HStack(alignment: .top)` with a left `VStack` (emoji+label at 11pt semibold secondary, value at 15pt semibold primary with `.contentTransition(.numericText())`, optional delta badge) and a right `plusButton` (shown only when `showIncrementButton == true`)
  - Verify: layout renders correctly in Xcode Preview for both increment and no-increment variants

- [ ] **1.1.d** — Apply frame/background/gesture to the tile body:
  ```swift
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
  - Verify: `.appShadow(radius:y:)` resolves (defined in `WellPlate/Shared/Color/AppColor.swift`)

- [ ] **1.1.e** — Implement the private `deltaBadge(_ text: String, positive: Bool) -> some View` helper as a `Capsule`-backed `Text` using `AppColors.success` / `AppColors.warning` with 0.12 opacity fill
  - Verify: badge text uses `.font(.r(10, .semibold))` (custom extension, not `.system`)

- [ ] **1.1.f** — Implement the private `plusButton: some View` computed property:
  - `Button` with `HapticService.impact(.light)` then `onIncrement?()`
  - Inner `Image(systemName: "plus")` at 14pt semibold, `AppColors.brand` foreground, 36×36 `Circle` background at 0.12 opacity
  - Outer `.frame(minWidth: 44, minHeight: 44)` for 44pt minimum touch target
  - `.accessibilityLabel("Add one \(label)")`
  - Verify: button is `.buttonStyle(.plain)` so it does not interfere with tile tap gesture

- [ ] **1.1.g** — Add accessibility to the tile:
  - Wrap tile body (the outermost view) in `.accessibilityElement(children: .contain)`
  - Add `.accessibilityLabel("\(label): \(value)")` to the tile body area (not the button, which has its own label)
  - Verify: VoiceOver would announce the tile label then the button label separately

- [ ] **1.1.h** — Add the `#Preview` block at the bottom of the file:
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
  - Verify: Preview compiles and renders the tile correctly

---

### 1.2 — Create `QuickStatsRow.swift`

- [ ] **1.2.a** — Create the file `WellPlate/Features + UI/Home/Components/QuickStatsRow.swift`
  - Verify: file is auto-included in build (no pbxproj edit needed)

- [ ] **1.2.b** — Declare the `QuickStatsRow` struct with these exact props:
  ```swift
  struct QuickStatsRow: View {
      @Binding var hydrationGlasses: Int
      let hydrationGoal: Int
      @Binding var coffeeCups: Int
      let coffeeGoal: Int
      let coffeeType: CoffeeType?
      let steps: Int?
      let yesterdayWater: Int
      let yesterdayCoffee: Int
      let yesterdaySteps: Int
      var onWaterTap: () -> Void
      var onCoffeeTap: () -> Void
      var onActivityTap: () -> Void
      var onCoffeeFirstCup: () -> Void
  }
  ```
  - Verify: `CoffeeType` type is available (it is used in `CoffeeCard.swift`; check import if needed)

- [ ] **1.2.c** — Implement the private `isFirstCupNoType: Bool` computed var:
  ```swift
  private var isFirstCupNoType: Bool {
      coffeeCups == 0 && coffeeType == nil
  }
  ```
  - Verify: this captures pre-increment state before any mutation (RESOLVED: H2 fix)

- [ ] **1.2.d** — Implement the three private delta text computed vars:
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
  ```

- [ ] **1.2.e** — Implement the private `stepsText: String` computed var:
  ```swift
  private var stepsText: String {
      guard let s = steps, s > 0 else { return "—" }
      let formatted = NumberFormatter.localizedString(from: NSNumber(value: s), number: .decimal)
      return formatted
  }
  ```
  - Verify: returns `"—"` for both `nil` and `0` — this is the RESOLVED M6 fix

- [ ] **1.2.f** — Implement `body` as an `HStack(spacing: 10)` containing three `QuickStatTile` calls:
  - **Water tile**: `emoji: "💧"`, `label: "Water"`, `value: "\(hydrationGlasses) / \(hydrationGoal)"`, `deltaText: waterDeltaText`, `deltaPositive: hydrationGlasses >= yesterdayWater`, `showIncrementButton: hydrationGlasses < hydrationGoal`, `onTap: { onWaterTap() }`, `onIncrement:` plays water sound then increments
  - **Coffee tile** (RESOLVED H2 fix — use `wasFirst` pattern):
    ```swift
    onIncrement: {
        let wasFirst = isFirstCupNoType
        SoundService.playConfirmation()
        coffeeCups += 1
        if wasFirst { onCoffeeFirstCup() }
    }
    ```
  - **Steps tile**: `emoji: "🏃"`, `label: "Steps"`, `value: stepsText`, `deltaText: stepsDeltaText`, `deltaPositive: (steps ?? 0) >= yesterdaySteps`, `showIncrementButton: false`, `onTap: { onActivityTap() }`, `onIncrement: nil`
  - Wrap the HStack with `.padding(.horizontal, 16)`
  - Verify: tiles are NOT wrapped in an additional card container — each `QuickStatTile` provides its own background

- [ ] **1.2.g** — Add a `#Preview` block:
  ```swift
  #Preview {
      QuickStatsRow(
          hydrationGlasses: .constant(5),
          hydrationGoal: 8,
          coffeeCups: .constant(2),
          coffeeGoal: 4,
          coffeeType: nil,
          steps: 6200,
          yesterdayWater: 4,
          yesterdayCoffee: 3,
          yesterdaySteps: 5400,
          onWaterTap: {}, onCoffeeTap: {}, onActivityTap: {}, onCoffeeFirstCup: {}
      )
      .padding()
  }
  ```
  - Verify: Preview compiles without error; all three tiles render side-by-side

---

### 1.3 — Create `ContextualActionBar.swift`

- [ ] **1.3.a** — Create the file `WellPlate/Features + UI/Home/Components/ContextualActionBar.swift`
  - Verify: file is in the same `Components/` directory as the other two new files

- [ ] **1.3.b** — Declare the `ContextualBarState` enum (top-level, exported from this file):
  ```swift
  enum ContextualBarState: Equatable {
      case defaultActions
      case logNextMeal(mealLabel: String)
      case waterBehindPace(glassesNeeded: Int)
      case goalsCelebration
      case stressActionable(level: String)
  }
  ```
  - Verify: `Equatable` conformance compiles (Swift auto-synthesizes it since all associated values are `Equatable` — `String` and `Int`)

- [ ] **1.3.c** — Declare the `ContextualActionBar` struct with these exact props and the reduce-motion environment value:
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

- [ ] **1.3.d** — Implement `body`: wrap `barContent` with `.padding(.horizontal, 32)`, `.padding(.bottom, 8)`, `.accessibilityElement(children: .contain)`, `.accessibilityLabel("Quick Actions")`. Add `.id(state)` and transition/animation modifiers for state changes:
  ```swift
  barContent
      .id(state)
      .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97)))
      .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: state)
  ```
  - Verify: `.animation(value:)` requires the value type to be `Equatable` — confirmed above

- [ ] **1.3.e** — Implement the private `barContent: some View` — an `HStack(spacing: 12)` of `primaryPill`, `Spacer()`, `trailingActions`, height 52, with a `Capsule` background:
  ```swift
  .background(
      Capsule()
          .fill(Color(.secondarySystemBackground))
          .appShadow(radius: 16, y: -4)
  )
  ```
  - Verify: shadow direction is `y: -4` (upward) to visually lift the bar off the tab bar

- [ ] **1.3.f** — Implement the private `primaryPill: some View` `@ViewBuilder` switching on all 5 `ContextualBarState` cases:
  - `.defaultActions` → `actionPill(icon: "fork.knife", label: "Log Meal", color: AppColors.brand) { HapticService.impact(.medium); onLogMeal() }`
  - `.logNextMeal(let label)` → same but `label: "Log \(label)"`
  - `.waterBehindPace(let n)` → `actionPill(icon: "drop.fill", label: "\(n) more to stay on track", color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82)) { HapticService.impact(.light); onAddWater() }`
  - `.goalsCelebration` → `actionPill(icon: "party.popper", label: "All goals met!", color: AppColors.success) { onSeeInsight() }`
  - `.stressActionable(let level)` → `actionPill(icon: "figure.mind.and.body", label: "Stress is \(level) — try breathing", color: AppColors.warning) { onStressTab() }`
  - Verify: all 5 cases compile

- [ ] **1.3.g** — Implement the private `actionPill(icon:label:color:action:) -> some View` helper:
  - `Button(action: action)` containing `HStack(spacing: 6)` of `Image(systemName:)` at 13pt semibold + `Text(label)` at `.r(13, .semibold)` with `.lineLimit(1)`, white foreground
  - `.padding(.horizontal, 14)`, `.padding(.vertical, 9)`, `Capsule` fill background
  - `.buttonStyle(.plain)`, `.frame(minWidth: 44, minHeight: 44)`, `.accessibilityLabel(label)`
  - Verify: `.r(13, .semibold)` resolves to the app's custom font extension

- [ ] **1.3.h** — Implement the private `trailingActions: some View` `@ViewBuilder` switching on all 5 states:
  - `.defaultActions, .logNextMeal` → `HStack(spacing: 8)` with three `trailingIconButton` calls:
    1. `icon: "drop.fill"`, water blue color (`Color(hue: 0.58, saturation: 0.68, brightness: 0.82)`), `label: "Add water"` → haptic + `SoundService.play("water_log_sound", ext: "mp3")` + `onAddWater()`
    2. `icon: "cup.and.saucer.fill"`, coffee brown color (`Color(hue: 0.08, saturation: 0.70, brightness: 0.72)`), `label: "Add coffee"` → haptic + `SoundService.playConfirmation()` + `onAddCoffee()`
    3. `icon: "heart.text.square.fill"`, `AppColors.brand.opacity(0.8)`, `label: "Log symptom"` → haptic + `onLogSymptom()`
  - `.waterBehindPace` → single `trailingIconButton` with `icon: "plus"`, water color, `label: "Add water glass"` → haptic + sound + `onAddWater()`
  - `.goalsCelebration` → single `trailingIconButton` with `icon: "chevron.right"`, `AppColors.brand`, `label: "See AI insight"` → `onSeeInsight()`
  - `.stressActionable` → single `trailingIconButton` with `icon: "play.fill"`, `AppColors.warning`, `label: "Start breathing"` → `onStressTab()`
  - Verify: all 5 cases compile

- [ ] **1.3.i** — Implement the private `trailingIconButton(icon:color:label:action:) -> some View` helper:
  - `Button(action: action)` with `Image(systemName:)` at 15pt semibold, foreground color, 36×36 `Circle` background at 0.12 opacity
  - `.buttonStyle(.plain)`, `.frame(minWidth: 44, minHeight: 44)`, `.accessibilityLabel(label)`

- [ ] **1.3.j** — Add two `#Preview` blocks at the bottom of the file:
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

### Phase 1 Build Verify

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: builds clean. All 3 new files compile. Zero errors. (New files are unreferenced — that is expected and not a warning.)

---

## Phase 2: HomeViewModel Additions

### 2.1 — Add `YesterdayStats`, `yesterdayStats`, `loadYesterdayStats()`, and `prefillFromEntry(_:)` to `HomeViewModel`

- [ ] **2.1.a** — Open `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`
  - Confirm the file ends at line 285 with the closing `}` of the class

- [ ] **2.1.b** — Insert the `YesterdayStats` struct **inside** the class, before the final `}` at line 285 (after the last existing method). Use the comment marker for organization:
  ```swift
  // MARK: - Yesterday Stats (for delta badges)

  struct YesterdayStats: Equatable {
      var water: Int = 0
      var coffee: Int = 0
      var steps: Int = 0
  }
  ```
  - Verify: struct is declared inside `HomeViewModel` (it is a nested type, not top-level)
  - Verify: `Equatable` conformance is explicit (RESOLVED: H3 fix — struct form, not labeled tuple)

- [ ] **2.1.c** — Add the `@Published` property for `yesterdayStats` directly after the struct:
  ```swift
  @Published var yesterdayStats = YesterdayStats()
  ```
  - Verify: this is inside the class body, uses the struct default (all zeros) as initial value

- [ ] **2.1.d** — Add the `loadYesterdayStats()` function:
  ```swift
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
      yesterdayStats = YesterdayStats(
          water: log?.waterGlasses ?? 0,
          coffee: log?.coffeeCups ?? 0,
          steps: log?.steps ?? 0
      )
  }
  ```
  - Verify: `WellnessDayLog` is importable (it is a SwiftData model in `WellPlate/Models/`)
  - Verify: `modelContext` is the `private var modelContext: ModelContext!` property at line 19

- [ ] **2.1.e** — Add the `prefillFromEntry(_:)` function under a new `MARK` comment:
  ```swift
  // MARK: - Add Again Prefill

  func prefillFromEntry(_ entry: FoodLogEntry) {
      foodDescription = entry.foodName
      if let serving = entry.servingSize, !serving.isEmpty {
          servingSize = serving
      }
  }
  ```
  - Verify: `entry.foodName` is a property on `FoodLogEntry` (confirmed in models)
  - Verify: `entry.servingSize` is `String?` on `FoodLogEntry` (confirmed)
  - Verify: `foodDescription` and `servingSize` are `@Published var` properties at lines 8–9 of this file

### Phase 2 Build Verify

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `HomeViewModel` compiles. `@Published var yesterdayStats` is accessible from `HomeView` via `foodJournalViewModel.yesterdayStats`.

---

## Phase 3: WellnessRingsCard Delta Badges

### 3.1 — Add `deltaValues` parameter and delta badge rendering to `WellnessRingsCard`

- [ ] **3.1.a** — Open `WellPlate/Features + UI/Home/Components/WellnessRingsCard.swift`
  - Locate `enum WellnessRingDestination: Identifiable` at line 5

- [ ] **3.1.b** — Add `Hashable` conformance to `WellnessRingDestination` (RESOLVED: M2 fix):
  ```swift
  // Before:
  enum WellnessRingDestination: Identifiable {
  // After:
  enum WellnessRingDestination: Identifiable, Hashable {
  ```
  - Verify: the enum compiles with `Hashable` — Swift auto-synthesizes it for plain enums without associated values; making it explicit prevents silent breakage if associated values are added later

- [ ] **3.1.c** — Add the `deltaValues` parameter to `WellnessRingsCard` with a default of `nil` (add after the existing `onRingTap` line):
  ```swift
  // Before (lines 25–29):
  struct WellnessRingsCard: View {
      let rings: [WellnessRingItem]
      let completionPercent: Int
      var onRingTap: (WellnessRingDestination) -> Void = { _ in }

  // After:
  struct WellnessRingsCard: View {
      let rings: [WellnessRingItem]
      let completionPercent: Int
      var onRingTap: (WellnessRingDestination) -> Void = { _ in }
      var deltaValues: [WellnessRingDestination: Int]? = nil
  ```
  - Verify: default `= nil` means no call-site changes needed for existing callers or Previews

- [ ] **3.1.d** — Thread `deltaValues` down to `WellnessRingButton` at its call site (approximately line 54):
  ```swift
  // Before:
  WellnessRingButton(ring: ring, animate: animate) {

  // After:
  WellnessRingButton(ring: ring, animate: animate, deltaValue: deltaValues?[ring.destination]) {
  ```
  - Verify: `ring.destination` is of type `WellnessRingDestination`, which is now `Hashable` — valid as Dictionary key

- [ ] **3.1.e** — Add `deltaValue: Int?` parameter to the `WellnessRingButton` private struct declaration (approximately line 78):
  ```swift
  // Before:
  private struct WellnessRingButton: View {
      let ring: WellnessRingItem
      let animate: Bool
      let action: () -> Void

  // After:
  private struct WellnessRingButton: View {
      let ring: WellnessRingItem
      let animate: Bool
      let deltaValue: Int?
      let action: () -> Void
  ```

- [ ] **3.1.f** — Add delta badge rendering in `WellnessRingButton.body`, after the `VStack(spacing: 2)` text block (the block containing the label and sublabel, approximately lines 130–138). Use the constant-height-slot pattern to avoid layout inconsistency (RESOLVED: W7 mitigation):
  ```swift
  Group {
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
      } else {
          Color.clear.frame(height: 14)   // reserve badge slot — all columns same height
      }
  }
  ```
  - Verify: the badge sits below the sublabel text, inside the existing `VStack(spacing: 10)` that wraps the ring button content
  - Verify: when `deltaValues` is `nil` (passed from HomeView before data loads), `deltaValue` is `nil`, the `else` branch renders `Color.clear.frame(height: 14)` — no visible badge, but column height is preserved

- [ ] **3.1.g** — Confirm the existing `#Preview` at the bottom of the file is unchanged — it does not pass `deltaValues`, which defaults to `nil`, so it renders identically to before
  - Verify: Preview still compiles without any changes

### Phase 3 Build Verify

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `WellnessRingsCard` compiles. Existing preview renders unchanged. No warnings about unused parameters.

---

## Phase 4: MealLogCard Height Cap

### 4.1 — Wrap `mealList` body in a height-capped `ScrollView` and remove `swipeActions`

- [ ] **4.1.a** — Open `WellPlate/Features + UI/Home/Components/MealLogCard.swift`
  - Locate `private var mealList: some View` at line 46
  - Confirm the `VStack(spacing: 0)` runs from line 47 to line ~131
  - Confirm `.swipeActions(edge: .trailing, allowsFullSwipe: true)` is at lines 135–141 (inside `mealRow`)

- [ ] **4.1.b** — Wrap the `VStack(spacing: 0)` inside `mealList` in a `ScrollView`:
  ```swift
  private var mealList: some View {
      ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 0) {
              // ... existing ForEach content unchanged ...
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
  - Verify: `.frame(maxHeight: 360)` is on the `ScrollView`, NOT on the inner `VStack`
  - Verify: `.background(...)` and `.padding(.horizontal, 16)` remain on the outer `ScrollView` (unchanged from current `VStack` position)

- [ ] **4.1.c** — Remove the `swipeActions` modifier from `mealRow` (lines 135–141):
  ```swift
  // DELETE the entire block:
  .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
          onDelete(entry)
      } label: {
          Label("Delete", systemImage: "trash")
      }
  }
  ```
  - Verify: `swipeActions` only works inside `List` context — it silently has no effect inside a `ScrollView`+`VStack`, so removing it eliminates dead code
  - Verify: the `contextMenu` block (which provides "Delete" via long-press) remains unchanged. The context menu is the primary delete path.
  - Verify: `onDelete` closure is still called from the context menu — the parameter is not removed from `MealLogCard`

### Phase 4 Build Verify

- [ ] Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: `MealLogCard` compiles with the `ScrollView` wrapper. No reference to `swipeActions`.

---

## Phase 5: HomeView Surgery

> Every sub-step leaves `HomeView.swift` in a buildable state. Run a build after each sub-step if uncertain.

### 5.1 — Add `todayFoodLogs` and `contextualBarState` computed properties

- [ ] **5.1.a** — Open `WellPlate/Features + UI/Home/Views/HomeView.swift`
  - Locate `private var todayCalories: Int` (approximately line 437)
  - Confirm `private var todayStart: Date` is already defined above it (line 429)

- [ ] **5.1.b** — Add `todayFoodLogs` computed property after `todayCalories` (RESOLVED: M7 fix — uses `$0.day == todayStart` not `Calendar.current.isDate`):
  ```swift
  /// Today's food log entries, filtered from the @Query result.
  /// Used by MealLogCard and contextualBarState.
  private var todayFoodLogs: [FoodLogEntry] {
      allFoodLogs.filter { $0.day == todayStart }
  }
  ```
  - Verify: `todayStart` is already defined as `Calendar.current.startOfDay(for: Date())` — consistent with `todayCalories` filter pattern

- [ ] **5.1.c** — Add `contextualBarState` computed property after `todayFoodLogs`:
  ```swift
  private var contextualBarState: ContextualBarState {
      if wellnessCompletionPercent >= 100 {
          return .goalsCelebration
      }
      if let level = todayWellnessLog?.stressLevel?.lowercased(),
         level == "high" || level == "very high" {
          return .stressActionable(level: todayWellnessLog?.stressLevel ?? "High")
      }
      let behind = expectedCupsDeficit()
      if behind > 1 {
          return .waterBehindPace(glassesNeeded: behind)
      }
      if let mealLabel = nextMealLabel() {
          return .logNextMeal(mealLabel: mealLabel)
      }
      return .defaultActions
  }
  ```
  - Verify: `ContextualBarState` is visible from `HomeView` — it is defined at the top level of `ContextualActionBar.swift`, which is in the same build target

- [ ] **5.1.d** — Add the `expectedCupsDeficit()` private function (after `contextualBarState`):
  ```swift
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
  ```
  - Note: `todayStart` is re-declared as a local `let` inside this function — this shadows the computed property version, which is fine in this local scope

- [ ] **5.1.e** — Add the `nextMealLabel()` private function (after `expectedCupsDeficit()`):
  ```swift
  private func nextMealLabel() -> String? {
      let hour = Calendar.current.component(.hour, from: Date())
      if (5..<11).contains(hour) {
          let hasBreakfast = todayFoodLogs.contains {
              let h = Calendar.current.component(.hour, from: $0.createdAt)
              return (5..<11).contains(h)
          }
          return hasBreakfast ? nil : "Breakfast"
      }
      if (11..<14).contains(hour) {
          let hasLunch = todayFoodLogs.contains {
              let h = Calendar.current.component(.hour, from: $0.createdAt)
              return (11..<14).contains(h)
          }
          return hasLunch ? nil : "Lunch"
      }
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
  - Verify: `$0.createdAt` is a property on `FoodLogEntry` (confirmed in model file)

- [ ] **5.1.f** — Build to confirm the new computed properties compile before any view changes:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.2 — Remove `dragLogProgress` state and the blur/overlay modifiers

- [ ] **5.2.a** — Delete line 52 (the `dragLogProgress` state declaration):
  ```swift
  // DELETE:
  @State private var dragLogProgress: CGFloat = 0
  ```
  - Verify: search the file for any other reference to `dragLogProgress` — there should be exactly 2 more: the `.blur` modifier (line 164) and the `DragToLogOverlay` binding (line 186). Both will be removed in the next steps.

- [ ] **5.2.b** — Delete lines 164–169 (the `.blur` and `.overlay` modifiers on the `ScrollView`):
  ```swift
  // DELETE these 6 lines:
  .blur(radius: dragLogProgress * 14)
  .overlay(
      Color.black.opacity(dragLogProgress * 0.25)
          .ignoresSafeArea()
          .allowsHitTesting(false)
  )
  ```
  - Verify: the `ScrollView` (or `ZStack` wrapping it) now has no blur/overlay modifiers referencing `dragLogProgress`

- [ ] **5.2.c** — After deletion, verify the `ZStack` in `body` wraps a single `ScrollView` child with no other children. Optionally either:
  - **Remove** the `ZStack` entirely, making `ScrollView` the direct child of `NavigationStack`, OR
  - **Keep** the `ZStack` with an explanatory comment:
    ```swift
    // ZStack kept intentionally — reserved for future overlay layers (e.g., confetti on goalsCelebration)
    ```
  - Verify: the file compiles after removal/comment of `ZStack`. If `ZStack` is removed, ensure no indentation or brace errors remain.

- [ ] **5.2.d** — Build to confirm `dragLogProgress` has zero remaining references:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`
  - Verify: if build fails with "use of unresolved identifier 'dragLogProgress'", locate any remaining reference and delete it

---

### 5.3 — Slim the header: remove `calendar` and `heart.text.square.fill` buttons

- [ ] **5.3.a** — Locate the header icon buttons block (approximately lines 351–383). Confirm 4 buttons exist: `sparkles`, `calendar`, `heart.text.square.fill`, `book.fill`.

- [ ] **5.3.b** — Delete the entire `calendar` button block (approximately lines 358–365):
  ```swift
  // DELETE:
  Button {
      HapticService.impact(.light)
      showWellnessCalendar = true
  } label: {
      headerIcon("calendar")
  }
  .buttonStyle(.plain)
  ```
  - Verify: `showWellnessCalendar` state variable is NOT deleted — it is intentionally kept as dead state (RESOLVED: L3)

- [ ] **5.3.c** — Delete the entire `heart.text.square.fill` (symptom log) button block (approximately lines 367–374):
  ```swift
  // DELETE:
  Button {
      HapticService.impact(.light)
      activeSheet = .symptomLog
  } label: {
      headerIcon("heart.text.square.fill")
  }
  .buttonStyle(.plain)
  .accessibilityLabel("Log a symptom")
  ```
  - Note: the symptom log action now lives in `ContextualActionBar`'s `trailingActions` (Step 1.3.h). This is the new home for the symptom shortcut.

- [ ] **5.3.d** — Add a TODO comment next to the `showWellnessCalendar` state declaration (line 44):
  ```swift
  @State private var showWellnessCalendar = false
  // TODO: F-next — re-home WellnessCalendarView to Profile tab.
  // The calendar button has been removed from the header as of the Home Screen UX Update.
  // This state and its .navigationDestination are kept as dead code to avoid touching the
  // navigation chain. Remove both when the Profile tab relocation is implemented.
  ```

- [ ] **5.3.e** — Update the comment on the `headerIcon` helper (approximately line 406) to reflect the new 2-button count:
  ```swift
  // MARK: - Header Icon Helper (38pt — 2 icons + optional mood badge)
  ```

- [ ] **5.3.f** — Build to confirm the slimmed header compiles:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.4 — Extend `greeting` with weekday-aware personality

- [ ] **5.4.a** — Locate `private var greeting: String` (approximately line 547). It currently has a 3-case switch returning hardcoded strings with "Alex".

- [ ] **5.4.b** — Replace the entire `greeting` computed property body with the weekday-aware version:
  ```swift
  private var greeting: String {
      // TODO: replace "Alex" with user's actual name when UserGoals.userName is available.
      // RESOLVED: L1 — "Alex" is a known limitation; no name field exists in current models.
      let cal = Calendar.current
      let hour = cal.component(.hour, from: Date())
      let weekday = cal.component(.weekday, from: Date()) // 1=Sun, 2=Mon, ..., 7=Sat

      let timePrefix: String
      switch hour {
      case 5..<12:  timePrefix = "Good Morning"
      case 12..<17: timePrefix = "Good Afternoon"
      default:      timePrefix = "Good Evening"
      }

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
  - Verify: Thursday (weekday 5) and Tuesday (weekday 3) return empty suffix, falling back to the plain `"\(timePrefix), Alex"` form

---

### 5.5 — Wire `yesterdayStats` load into `onAppear`

- [ ] **5.5.a** — Locate the `.onAppear` block (approximately line 221). It currently ends with `refreshTodayJournalState()`.

- [ ] **5.5.b** — Add `foodJournalViewModel.loadYesterdayStats()` as the last call inside `.onAppear`:
  ```swift
  .onAppear {
      foodJournalViewModel.bindContext(modelContext)
      insightService.bindContext(modelContext)
      refreshTodayMoodState()
      refreshTodayHydrationState()
      refreshTodayCoffeeState()
      refreshTodayJournalState()
      foodJournalViewModel.loadYesterdayStats()   // ADD THIS LINE
  }
  ```
  - Verify: `foodJournalViewModel` is the `@StateObject` of type `HomeViewModel` already present in `HomeView`
  - Verify: `loadYesterdayStats()` is called after `bindContext(modelContext)` — this is required because `loadYesterdayStats` uses `modelContext` which is set by `bindContext`

- [ ] **5.5.c** — Build to confirm the `onAppear` change compiles:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.6 — Replace `HydrationCard` + `CoffeeCard` with `QuickStatsRow`

- [ ] **5.6.a** — Locate the card positions 5 and 6 in the `LazyVStack` (approximately lines 132–148):
  ```swift
  // 5. Hydration
  HydrationCard(...)
  .padding(.horizontal, 16)

  // 6. Coffee
  CoffeeCard(...)
  .padding(.horizontal, 16)
  ```

- [ ] **5.6.b** — Replace both `HydrationCard` and `CoffeeCard` blocks (including their `.padding(.horizontal, 16)`) with a single `QuickStatsRow` call:
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
  - Verify: NO `.padding(.horizontal, 16)` is added after `QuickStatsRow` — the row handles its own internal padding via `.padding(.horizontal, 16)` inside `QuickStatsRow.swift`
  - Verify: `todayWellnessLog?.steps` is `Int?` (the `?` handles the case where no `WellnessDayLog` exists yet today)
  - Verify: `foodJournalViewModel.yesterdayStats` is now a `YesterdayStats` struct with `.water`, `.coffee`, `.steps` properties

- [ ] **5.6.c** — Build to confirm `QuickStatsRow` replaces the two old cards cleanly:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.7 — Re-enable `MealLogCard` at position 3 (after mood/journal, before `QuickStatsRow`)

- [ ] **5.7.a** — Locate the mood/journal card block (the existing card at position 3 in the stack, ending around line 130 before the old `HydrationCard`).

- [ ] **5.7.b** — Insert the `MealLogCard` call immediately after the mood/journal block and before the new `QuickStatsRow`:
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
  ```
  - Verify: NO `.padding(.horizontal, 16)` is added at the call site — `MealLogCard` applies this padding internally on both `mealList` and `emptyState`. Adding it here would double the padding to 32pt. (RESOLVED: W3 watchout)
  - Verify: `todayFoodLogs` is the computed property added in Step 5.1.b
  - Verify: `modelContext` is available via `@Environment(\.modelContext)` in `HomeView`
  - Verify: `foodJournalViewModel.prefillFromEntry(entry)` calls the method added in Step 2.1.e

- [ ] **5.7.c** — Build to confirm `MealLogCard` call compiles:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.8 — Add `wellnessDeltaValues` and update `WellnessRingsCard` call

- [ ] **5.8.a** — Add `wellnessDeltaValues` computed property near `wellnessRings` (approximately line 441 area):
  ```swift
  private var wellnessDeltaValues: [WellnessRingDestination: Int]? {
      let stats = foodJournalViewModel.yesterdayStats
      guard stats.water > 0 || stats.coffee > 0 || stats.steps > 0 else { return nil }

      var values: [WellnessRingDestination: Int] = [:]

      let waterDiff = hydrationGlasses - stats.water
      if waterDiff != 0 { values[.water] = waterDiff }

      if let steps = todayWellnessLog?.steps, stats.steps > 0 {
          let stepsDiff = steps - stats.steps
          if stepsDiff != 0 { values[.exercise] = stepsDiff }
      }

      return values.isEmpty ? nil : values
  }
  ```
  - Verify: `WellnessRingDestination` is now `Hashable` (Step 3.1.b) — required for use as Dictionary key
  - Verify: returns `nil` when no yesterday data exists (cold launch / first use safety)

- [ ] **5.8.b** — Update the `WellnessRingsCard` call site (approximately lines 83–95) to pass `deltaValues`:
  ```swift
  WellnessRingsCard(
      rings: wellnessRings,
      completionPercent: wellnessCompletionPercent,
      deltaValues: wellnessDeltaValues,       // ADD THIS LINE
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
  - Verify: the `deltaValues:` label matches the parameter name added in Step 3.1.c

- [ ] **5.8.c** — Build to confirm the `WellnessRingsCard` call compiles:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.9 — Replace `DragToLogOverlay` with `ContextualActionBar` in `.safeAreaInset`

- [ ] **5.9.a** — Locate the `.safeAreaInset(edge: .bottom)` block (approximately lines 183–188):
  ```swift
  .safeAreaInset(edge: .bottom) {
      DragToLogOverlay(onTrigger: {
          showLogMeal = true
      }, dragProgress: $dragLogProgress)
      .padding(.bottom, 4)
  }
  ```
  - Verify: `dragLogProgress` is already deleted from the file (Step 5.2.a). If this block still references it, the build would have failed at Step 5.2.d — this confirms it is removed now.

- [ ] **5.9.b** — Replace the entire `.safeAreaInset` block with `ContextualActionBar`:
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
              // RESOLVED: M8 — increment coffeeCups BEFORE checking first-cup path.
              // wasFirst captures pre-increment state to decide which side-effect to trigger.
              let wasFirst = coffeeCups == 0 && todayWellnessLog?.coffeeType == nil
              coffeeCups += 1
              if wasFirst { activeSheet = .coffeeTypePicker }
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
  - Verify: this is the ONLY `.safeAreaInset(edge: .bottom)` modifier on the view — do not add a second one
  - Verify: `onAddWater` does NOT call `SoundService` — the bar's trailing button handler calls sound internally (Option A from the plan)
  - Verify: `onAddCoffee` uses the `wasFirst` pattern (RESOLVED: M8 fix)
  - Verify: `todayWellnessLog?.coffeeType` — `coffeeType` is a `String?` raw value on `WellnessDayLog` (not an enum; the `resolvedCoffeeType` computed property converts it)

- [ ] **5.9.c** — Build to confirm the bar replacement compiles:
  - Run: `xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build`

---

### 5.10 — Final cleanup: update `LazyVStack` comment numbering

- [ ] **5.10.a** — Update the inline comments inside the `LazyVStack` body to reflect the final card order:
  ```
  // 1. Header (inline in body — not a separate component)
  // 2. Wellness Rings Card
  // (Quick Log section — commented out, kept for reference)
  // 3. Mood Check-In / Journal Reflection
  // 4. Today's Meals (MealLogCard)
  // 5. Quick Stats (Water + Coffee + Activity)
  ```
  - Verify: the numbered comments in the `LazyVStack` match the actual view order after all Phase 5 changes

---

## Post-Implementation

### Final Build — All 4 Targets

- [ ] Run WellPlate main app target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: zero errors, zero new warnings

- [ ] Run ScreenTimeMonitor extension target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: builds clean (this target is not modified; confirming no unintended side effects)

- [ ] Run ScreenTimeReport extension target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: builds clean

- [ ] Run WellPlateWidget target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: builds clean

### Git Commit

- [ ] Stage all changes:
  ```bash
  git add WellPlate/Features\ +\ UI/Home/Components/QuickStatTile.swift
  git add WellPlate/Features\ +\ UI/Home/Components/QuickStatsRow.swift
  git add WellPlate/Features\ +\ UI/Home/Components/ContextualActionBar.swift
  git add WellPlate/Features\ +\ UI/Home/ViewModels/HomeViewModel.swift
  git add WellPlate/Features\ +\ UI/Home/Components/WellnessRingsCard.swift
  git add WellPlate/Features\ +\ UI/Home/Components/MealLogCard.swift
  git add WellPlate/Features\ +\ UI/Home/Views/HomeView.swift
  ```
- [ ] Commit:
  ```bash
  git commit -m "feat: home screen UX update — ContextualActionBar, QuickStatsRow, MealLogCard inline, delta badges, slimmed header"
  ```

---

## Success Criteria Checklist

Verify each item by running the app in Simulator:

- [ ] Project builds clean on all 4 targets with zero new warnings
- [ ] `DragToLogOverlay` is absent from `HomeView.body` (grep confirms no reference in `.safeAreaInset`)
- [ ] `dragLogProgress` state variable is removed from `HomeView` (grep confirms zero references)
- [ ] `HydrationCard` and `CoffeeCard` are absent from `HomeView`'s `LazyVStack` body
- [ ] `QuickStatsRow` renders water, coffee, and steps tiles in a single row
- [ ] `MealLogCard` renders inline with today's food entries at card position 4
- [ ] `MealLogCard` list is capped at 360 pt height; content beyond 5 entries is scrollable inside the cap
- [ ] Header shows exactly 2 icon buttons (`sparkles` + `book.fill`) plus optional mood badge
- [ ] `ContextualActionBar` is persistent above tab bar at all times (not drag-triggered)
- [ ] Bar state shows `logNextMeal("Breakfast")` at 08:00 with no food logged in the 05:00–10:59 window
- [ ] Bar state shows `waterBehindPace(n)` when `hydrationGlasses < expectedCupsByNow()`
- [ ] Bar state shows `goalsCelebration` when all rings reach 100% (use mock mode to test)
- [ ] Cold launch with zero data: `ContextualActionBar` shows `defaultActions` or `logNextMeal` without crashing
- [ ] Tapping "Log Meal" pill navigates to `FoodJournalView`
- [ ] Tapping `💧` in bar increments `hydrationGlasses`; water sound plays (played by bar internally)
- [ ] Tapping `☕` in bar from 0 cups: `coffeeCups` becomes 1, THEN `CoffeeTypePickerSheet` appears (verify count is 1 when picker is visible)
- [ ] Tapping `☕` in bar from 1+ cups: increments without showing picker
- [ ] Delta badges appear in `WellnessRingsCard` when yesterday's `WellnessDayLog` data is available
- [ ] Delta badges appear in `QuickStatsRow` water and coffee tiles when values differ from yesterday
- [ ] "Add Again" in `MealLogCard` context menu pre-fills food name in `FoodJournalView`
- [ ] `greeting` varies: weekday personality suffix appears on Monday, Wednesday, Friday, Saturday, Sunday; Tuesday/Thursday/other use plain time-of-day form
- [ ] Reduce Motion enabled in Settings: `ContextualActionBar` state transitions are instant (no spring animation)
- [ ] All interactive elements in new components have minimum 44×44 pt touch target
