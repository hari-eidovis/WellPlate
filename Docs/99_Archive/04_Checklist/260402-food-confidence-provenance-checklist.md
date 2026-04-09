# Implementation Checklist: Food Confidence & Data Provenance UI

**Source Plan**: `Docs/02_Planning/Specs/260402-food-confidence-provenance-plan-RESOLVED.md`
**Date**: 2026-04-02

---

## Pre-Implementation

- [ ] Read the resolved plan at `Docs/02_Planning/Specs/260402-food-confidence-provenance-plan-RESOLVED.md`
- [ ] Confirm `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` exists and is open
  - Verify: Locate `func logFood(on date: Date, ...)` and find the `insertLog(from: result, ...)` call (around line 118)
- [ ] Confirm `WellPlate/Features + UI/Home/Components/MealLogCard.swift` exists and is open
  - Verify: Locate `private func mealRow(entry: FoodLogEntry)` and the macro chips `HStack` inside it (around lines 113–127)

---

## Phase 0: Fix Data at Source

### 0.1 — Add `logSource: "text"` to `HomeViewModel.logFood()`

- [ ] Open `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`
- [ ] Find the `insertLog` call inside `logFood()` that saves the API result — it currently reads:
  ```swift
  insertLog(from: result, day: day, typedName: canonicalName, key: key, context: context)
  ```
- [ ] Change it to:
  ```swift
  insertLog(from: result, day: day, typedName: canonicalName, key: key,
            context: context, logSource: "text")
  ```
  - Verify: The line now has `logSource: "text"` as the last argument. The `insertLog(from: NutritionalInfo, ...)` overload already accepts `logSource: String? = nil` so no signature change is needed.

---

## Phase 1: Add Provenance Pill Helper

### 1.1 — Add `LogProvenance` enum to `MealLogCard.swift`

- [ ] Open `WellPlate/Features + UI/Home/Components/MealLogCard.swift`
- [ ] After the closing brace of the existing `mealList` computed property (or at the end of `MealLogCard`'s private section, before `// MARK: - Helpers`), add the following private nested enum:
  ```swift
  private enum LogProvenance {
      case barcodeVerified
      case aiHigh
      case aiEstimated

      init?(logSource: String?, confidence: Double?) {
          guard let source = logSource else { return nil }
          if source == "barcode" { self = .barcodeVerified; return }
          if let c = confidence, c >= 0.8 {
              self = .aiHigh
          } else {
              self = .aiEstimated
          }
      }

      var label: String {
          switch self {
          case .barcodeVerified: return "Barcode ✓"
          case .aiHigh:          return "AI · High"
          case .aiEstimated:     return "AI · Est."
          }
      }

      var color: Color {
          switch self {
          case .barcodeVerified: return .green
          case .aiHigh:          return AppColors.primary
          case .aiEstimated:     return .orange
          }
      }
  }
  ```
  - Verify: The enum compiles — it references only `Color` (already imported via SwiftUI) and `AppColors` (already used elsewhere in the file). No new imports needed.

### 1.2 — Add `provenancePill(for:)` view builder

- [ ] In `MealLogCard`, after the existing `macroPill(_:color:)` helper function, add:
  ```swift
  @ViewBuilder
  private func provenancePill(for entry: FoodLogEntry) -> some View {
      if let provenance = LogProvenance(logSource: entry.logSource, confidence: entry.confidence) {
          Text(provenance.label)
              .font(.r(10, .medium))
              .foregroundColor(provenance.color)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                  Capsule()
                      .fill(provenance.color.opacity(0.12))
              )
      }
  }
  ```
  - Verify: Function signature matches `macroPill`'s style (private, returns `some View`). The `if let` branch means `EmptyView` is returned for nil provenance — no empty space rendered.

---

## Phase 2: Wire Into Meal Row

### 2.1 — Wrap chips HStack in ScrollView and add provenance pill

- [ ] In `mealRow(entry:)`, locate the `// Macro chips` comment and the `HStack(spacing: 5)` immediately below it
- [ ] Wrap the entire `HStack` in `ScrollView(.horizontal, showsIndicators: false)`:

  **Before**:
  ```swift
  // Macro chips
  HStack(spacing: 5) {
      if let qty = entry.quantity, !qty.isEmpty, let unit = entry.quantityUnit {
          macroPill("\(qty)\(unit)", color: AppColors.primary)
      } else if let serving = entry.servingSize, !serving.isEmpty {
          macroPill(serving, color: AppColors.primary)
      }
      macroPill("\(Int(entry.protein))g P", color: Color(red: 0.85, green: 0.25, blue: 0.25))
      macroPill("\(Int(entry.carbs))g C", color: .blue)
      macroPill("\(Int(entry.fat))g F", color: .orange)
      if entry.fiber > 0.5 {
          macroPill("\(Int(entry.fiber))g F·ib", color: .green)
      }
  }
  ```

  **After**:
  ```swift
  // Macro chips
  ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 5) {
          if let qty = entry.quantity, !qty.isEmpty, let unit = entry.quantityUnit {
              macroPill("\(qty)\(unit)", color: AppColors.primary)
          } else if let serving = entry.servingSize, !serving.isEmpty {
              macroPill(serving, color: AppColors.primary)
          }
          macroPill("\(Int(entry.protein))g P", color: Color(red: 0.85, green: 0.25, blue: 0.25))
          macroPill("\(Int(entry.carbs))g C", color: .blue)
          macroPill("\(Int(entry.fat))g F", color: .orange)
          if entry.fiber > 0.5 {
              macroPill("\(Int(entry.fiber))g F·ib", color: .green)
          }
          provenancePill(for: entry)
      }
  }
  ```
  - Verify: `provenancePill(for: entry)` is the last item inside the `HStack`, after the fiber pill. The `ScrollView` is the outermost wrapper of the chips row only — not wrapping the entire `mealRow`.

---

## Post-Implementation

### Build Verification

- [ ] Build main app target:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: Output ends with `** BUILD SUCCEEDED **`. Zero new errors or warnings.

- [ ] Build extension targets:
  ```bash
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
  xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
  ```
  - Verify: All 3 end with `** BUILD SUCCEEDED **`.

### Manual Verification

- [ ] **Text entry → AI pill**: Log a meal via text input → open FoodJournalView → confirm "AI · High" or "AI · Est." pill appears in the meal row
  - Verify: Pill is visible, uses capsule style matching macro pills, correct color (blue = High, orange = Est.)

- [ ] **Voice entry → AI pill**: Log a meal via voice → open FoodJournalView → confirm "AI · High" or "AI · Est." pill appears
  - Verify: Same appearance as text entry pill

- [ ] **Barcode entry → Barcode pill**: Scan a barcode → open FoodJournalView → confirm green "Barcode ✓" pill appears
  - Verify: Green color, checkmark in label

- [ ] **Legacy entry → no pill**: Open any entry logged before this change (if available) → confirm no pill renders and no blank gap appears in the chips row
  - Verify: Row looks identical to pre-change for old entries

- [ ] **iPhone SE simulator — no clipping**: Run on iPhone SE (4.7" or 375pt width simulator) → log a meal with all macro pills visible → swipe the chips row horizontally → confirm provenance pill is reachable via scroll
  - Verify: No pills are clipped; scroll gesture works

- [ ] **Dark mode**: Switch device/simulator to dark mode → open FoodJournalView → confirm all pill foreground and background colors are legible
  - Verify: Green, blue, orange pills all readable against dark background

### Git Commit

- [ ] Stage changes:
  ```bash
  git add "WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift"
  git add "WellPlate/Features + UI/Home/Components/MealLogCard.swift"
  ```
- [ ] Commit:
  ```bash
  git commit -m "feat: food provenance pill (Barcode / AI·High / AI·Est.) in meal rows"
  ```
  - Verify: `git status` shows clean working tree for these two files
