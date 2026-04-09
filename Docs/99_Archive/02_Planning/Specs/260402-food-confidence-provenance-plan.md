# Implementation Plan: Food Confidence & Data Provenance UI

**Date**: 2026-04-02
**Strategy**: `Docs/02_Planning/Specs/260402-food-confidence-provenance-strategy.md`
**Status**: Ready for Audit

---

## Overview

Add a small inline provenance badge to each meal row in `MealLogCard.swift` that tells users how reliable their nutrition data is. `FoodLogEntry` already stores `logSource: String?` ("barcode", "voice", "text") and `confidence: Double?` — this plan exposes those fields in the UI with zero model changes, zero service changes, and zero new screens. Single-file edit.

---

## Requirements

- Each meal row shows a provenance label: "Barcode ✓", "AI · High", "AI · Est.", or "AI · Low"
- Barcode-sourced entries always show "Barcode ✓" (green) regardless of confidence value
- Voice and text entries use confidence thresholds: ≥ 0.8 = High, ≥ 0.5 = Est., < 0.5 = Low
- Legacy entries with `logSource == nil` show nothing (no pill rendered)
- Pill must use the same capsule style as existing `macroPill()` — no new design language
- Must not increase row height or cause layout shift
- Must compile cleanly across all 4 targets

---

## Architecture Changes

- `WellPlate/Features + UI/Home/Components/MealLogCard.swift` — only file changed
  - Add private `provenancePill(for entry: FoodLogEntry) -> some View` helper (using `@ViewBuilder`)
  - Call it inside the macro chips `HStack` in `mealRow(entry:)`
  - No other files touched

---

## Implementation Steps

### Phase 1: Add Provenance Pill Helper

**Step 1 — Define `LogProvenance` local enum** (`MealLogCard.swift`)
- **Action**: Add a `private enum LogProvenance` inside `MealLogCard` with cases:
  ```swift
  private enum LogProvenance {
      case barcodeVerified
      case aiHigh
      case aiEstimated
      case aiLow
  }
  ```
  Add a computed init from `(logSource: String?, confidence: Double?)`:
  ```swift
  init?(logSource: String?, confidence: Double?) {
      guard let source = logSource else { return nil }   // legacy entry → no pill
      if source == "barcode" { self = .barcodeVerified; return }
      switch confidence {
      case let c? where c >= 0.8: self = .aiHigh
      case let c? where c >= 0.5: self = .aiEstimated
      default:                    self = .aiLow
      }
  }
  ```
  Add computed properties for display:
  ```swift
  var label: String {
      switch self {
      case .barcodeVerified: return "Barcode ✓"
      case .aiHigh:          return "AI · High"
      case .aiEstimated:     return "AI · Est."
      case .aiLow:           return "AI · Low"
      }
  }
  var color: Color {
      switch self {
      case .barcodeVerified: return .green
      case .aiHigh:          return AppColors.primary
      case .aiEstimated:     return AppColors.textSecondary
      case .aiLow:           return .orange
      }
  }
  ```
- **Why**: Encapsulating the logic in an enum makes it testable, readable, and keeps `mealRow` clean.
- **Dependencies**: None
- **Risk**: Low

---

**Step 2 — Add `provenancePill(for:)` view helper** (`MealLogCard.swift`)
- **Action**: Add a `@ViewBuilder private func provenancePill(for entry: FoodLogEntry) -> some View` method:
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
- **Why**: `@ViewBuilder` with an `if let` produces `EmptyView` for legacy entries — no conditional rendering complexity in the call site.
- **Dependencies**: Step 1 (requires `LogProvenance` enum)
- **Risk**: Low

---

### Phase 2: Wire Into Meal Row

**Step 3 — Insert pill into `mealRow(entry:)`** (`MealLogCard.swift`)
- **Action**: In the macro chips `HStack` inside `mealRow(entry:)` (currently lines 113–127), append `provenancePill(for: entry)` as the last item after the fiber pill:

  **Before** (end of the HStack):
  ```swift
  if entry.fiber > 0.5 {
      macroPill("\(Int(entry.fiber))g F·ib", color: .green)
  }
  ```

  **After**:
  ```swift
  if entry.fiber > 0.5 {
      macroPill("\(Int(entry.fiber))g F·ib", color: .green)
  }
  provenancePill(for: entry)
  ```
- **Why**: Provenance is metadata about the data quality, not a macro — placing it last in the chips row keeps macros first and provenance as a subtle qualifier.
- **Dependencies**: Steps 1 + 2
- **Risk**: Low — the `HStack` already scrolls/wraps with `.fixedSize()` not set, so an extra pill won't break layout

---

## Testing Strategy

**Build verification** (all 4 targets must compile):
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Manual verification flows**:
1. Log a meal via **text** → confirm "AI · High" or "AI · Est." or "AI · Low" pill appears in FoodJournalView meal row
2. Log a meal via **barcode scan** → confirm "Barcode ✓" (green) pill appears
3. Log a meal via **voice** → confirm AI confidence pill appears (voice uses same Groq pipeline)
4. Open an **existing entry** logged before this change (no `logSource`) → confirm NO pill renders
5. Verify row height is unchanged across all three entry types
6. Verify dark mode — all pill colors readable on dark background (`.opacity(0.12)` fill is adaptive)

---

## Risks & Mitigations

- **Risk**: `logSource == nil` for entries logged before this feature ships could show wrong state
  - **Mitigation**: The `LogProvenance` failable init returns `nil` for `logSource == nil`, so `provenancePill` emits `EmptyView`. Handled in Step 1.

- **Risk**: Macro chips row becomes too wide on small screens (iPhone SE)
  - **Mitigation**: The existing chips `HStack` has no fixed width — it naturally clips or wraps. The provenance pill is max ~75pt wide, same as existing macro pills. Observe on 4.7" simulator during manual testing. If crowded, move pill to a second line with minimal layout change (not expected to be necessary).

- **Risk**: `"voice"` entries currently set `logSource = "voice"` but may not always have a confidence score if Groq times out and falls back to template
  - **Mitigation**: `LogProvenance` init handles `confidence == nil` → falls to `default: .aiLow` case, showing "AI · Low". Honest and correct.

---

## Success Criteria

- [ ] All 4 build targets compile without errors or warnings introduced by this change
- [ ] Barcode-scanned entries show green "Barcode ✓" pill
- [ ] Text/voice entries with confidence ≥ 0.8 show blue "AI · High" pill
- [ ] Text/voice entries with confidence 0.5–0.79 show secondary "AI · Est." pill
- [ ] Text/voice entries with confidence < 0.5 or nil confidence show orange "AI · Low" pill
- [ ] Legacy entries (nil `logSource`) show no pill — no empty space or layout gap
- [ ] Row height is visually unchanged from before the change
- [ ] Pill style matches existing `macroPill()` capsule pattern exactly
