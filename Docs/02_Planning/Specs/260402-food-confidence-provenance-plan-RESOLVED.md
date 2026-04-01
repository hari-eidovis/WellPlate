# Implementation Plan: Food Confidence & Data Provenance UI — RESOLVED

**Date**: 2026-04-02
**Strategy**: `Docs/02_Planning/Specs/260402-food-confidence-provenance-strategy.md`
**Audit**: `Docs/03_Audits/260402-food-confidence-provenance-plan-audit.md`
**Status**: Awaiting User Approval

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| C1: `logSource` never set for text/voice entries | CRITICAL | RESOLVED — New Step 0 added: set `logSource: "text"` in `HomeViewModel.logFood()` |
| M1: Plain `HStack` clips on narrow screens | MEDIUM | RESOLVED — Step 3 updated: wrap chips HStack in `ScrollView(.horizontal)` |
| L1: Scope statement listed only one file | LOW | RESOLVED — Architecture Changes updated to include `HomeViewModel.swift` |
| L2: `"AI · Est."` label ambiguity | LOW | ACKNOWLEDGED — Simplified to two tiers: "AI · High" (≥ 0.8) and "AI · Est." (< 0.8). Middle tier color changed from secondary/gray to `.orange.opacity(0.8)` for clearer visual distinction |

---

## Overview

<!-- RESOLVED: L1 — updated scope to reflect two-file change -->
Add a small inline provenance badge to each meal row in `MealLogCard.swift` that tells users how reliable their nutrition data is. `FoodLogEntry` already stores `logSource: String?` and `confidence: Double?`. However, the text/voice logging path in `HomeViewModel` does not yet write `logSource` — this plan fixes that data gap first, then exposes provenance in the UI. **Two-file edit**: `HomeViewModel.swift` (one line) + `MealLogCard.swift` (new enum + helper + HStack wrapper). Zero model migrations, zero service changes, zero new screens.

---

## Requirements

- Each meal row shows a provenance label: "Barcode ✓", "AI · High", or "AI · Est."
- Barcode-sourced entries always show "Barcode ✓" (green) regardless of confidence value
- Text and voice entries use confidence threshold: ≥ 0.8 = "AI · High" (blue), < 0.8 = "AI · Est." (orange)
- Legacy entries with `logSource == nil` show nothing (no pill rendered) — graceful degradation
- Pill must use the same capsule style as existing `macroPill()` — no new design language
- Chips row must not clip on narrow screens (iPhone SE, 4.7")
- Must compile cleanly across all 4 targets

<!-- RESOLVED: L2 — simplified to two AI tiers (High / Est.) for clearer UX. "AI · Low" removed;
     entries with confidence < 0.8 all show "AI · Est." in orange. Avoids ambiguous three-tier gradient. -->

---

## Architecture Changes

<!-- RESOLVED: L1, C1 — HomeViewModel.swift added as affected file -->
- `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` — add `logSource: "text"` to one `insertLog` call in `logFood()`
- `WellPlate/Features + UI/Home/Components/MealLogCard.swift` — add `LogProvenance` enum, `provenancePill()` helper, wrap chips `HStack` in `ScrollView`

---

## Implementation Steps

### Phase 0: Fix Data at Source

<!-- RESOLVED: C1 — new step that was entirely missing from original plan -->
**Step 0 — Set `logSource: "text"` in `HomeViewModel.logFood()`** (`HomeViewModel.swift`)
- **Action**: In `HomeViewModel.logFood()`, find the `insertLog` call that saves API results (currently around line 118):

  **Before**:
  ```swift
  insertLog(from: result, day: day, typedName: canonicalName, key: key, context: context)
  ```

  **After**:
  ```swift
  insertLog(from: result, day: day, typedName: canonicalName, key: key,
            context: context, logSource: "text")
  ```

- **Why**: Both text-typed and voice-dictated entries flow through `logFood()` → the same Groq nutrition pipeline → `insertLog(from: NutritionalInfo, ...)`. Using `"text"` as the source value for both is accurate: both produce AI-estimated nutrition. Without this fix, all text/voice entries have `logSource == nil` and the provenance pill never renders (audit finding C1).
- **Dependencies**: None — standalone fix
- **Risk**: Very Low — one argument addition to an existing internal call. No API surface change. No model migration needed (`logSource` is already an optional field on `FoodLogEntry`).

> **Note on deferred items**: The `insertLog(from: FoodCache, ...)` overload (used only in mock mode) still has no `logSource` parameter. This is intentional — mock-mode entries are development data, not user-facing. Deferred per audit recommendation.

---

### Phase 1: Add Provenance Pill Helper

**Step 1 — Define `LogProvenance` local enum** (`MealLogCard.swift`)
- **Action**: Add a `private enum LogProvenance` inside `MealLogCard`:

  ```swift
  private enum LogProvenance {
      case barcodeVerified
      case aiHigh
      case aiEstimated

      init?(logSource: String?, confidence: Double?) {
          guard let source = logSource else { return nil }  // legacy → no pill
          if source == "barcode" { self = .barcodeVerified; return }
          // text + voice both show AI tiers based on confidence
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

<!-- RESOLVED: L2 — simplified from four tiers (barcodeVerified/aiHigh/aiEstimated/aiLow) to three
     (barcodeVerified/aiHigh/aiEstimated). "AI · Low" merged into "AI · Est." — orange color for
     both sub-0.8 cases. Removes ambiguity between Est. and Low labels. -->

- **Why**: Encapsulates all provenance logic in one place. Failable init returns `nil` for legacy entries → `EmptyView` at call site. Two-tier AI (High/Est.) is easier to understand than three-tier.
- **Dependencies**: None
- **Risk**: Low

---

**Step 2 — Add `provenancePill(for:)` view helper** (`MealLogCard.swift`)
- **Action**: Add a `@ViewBuilder private func provenancePill(for entry: FoodLogEntry) -> some View`:

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

- **Why**: `@ViewBuilder` + `if let` produces `EmptyView` for nil provenance — no conditional complexity at the call site.
- **Dependencies**: Step 1
- **Risk**: Low

---

### Phase 2: Wire Into Meal Row

**Step 3 — Wrap chips HStack in ScrollView and append pill** (`MealLogCard.swift`)
- **Action**: In `mealRow(entry:)`, wrap the existing macro chips `HStack` in a horizontal `ScrollView` and add `provenancePill(for: entry)` as the final item:

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

<!-- RESOLVED: M1 — replaced plain HStack with ScrollView(.horizontal, showsIndicators: false).
     Prevents clipping on iPhone SE / 4.7" screens where 6 pills would overflow available width.
     Matches the pattern used by the triggers row in MealLogView. -->

- **Why**: `ScrollView(.horizontal)` lets all pills remain visible on any screen width. Users on small devices can scroll right to see provenance. The `showsIndicators: false` keeps it visually clean.
- **Dependencies**: Steps 1 + 2 + Step 0
- **Risk**: Low — `ScrollView` wrapping doesn't affect outer layout; the row's vertical size is unchanged

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
1. Log a meal via **text** → confirm "AI · High" or "AI · Est." pill appears in FoodJournalView meal row
2. Log a meal via **voice** → confirm "AI · High" or "AI · Est." pill appears (same pipeline as text)
3. Log a meal via **barcode scan** → confirm green "Barcode ✓" pill appears
4. Open an **existing entry** logged before this change (`logSource == nil`) → confirm NO pill renders, no blank gap
5. Verify on **iPhone SE simulator** (4.7") — pills row scrolls horizontally, provenance pill visible
6. Verify **dark mode** — all pill colors readable on dark background (`.opacity(0.12)` fill adapts)

<!-- RESOLVED: C1 test coverage — steps 1 and 2 now explicitly cover text and voice paths,
     which were not tested in the original plan (would have caught the missing logSource bug) -->

---

## Risks & Mitigations

- **Risk**: `logSource == nil` for entries logged before this feature ships
  - **Mitigation**: `LogProvenance` failable init returns `nil` → `provenancePill` emits `EmptyView`. No pill, no gap. Handled in Step 1.

- ~~**Risk**: Macro chips row becomes too wide on small screens~~ — **RESOLVED via M1 fix** (ScrollView wrapping in Step 3)

- **Risk**: `"text"` entries may have `confidence == nil` if Groq times out and returns template nutrition
  - **Mitigation**: `LogProvenance` init handles `confidence == nil` → `.aiEstimated` case → shows "AI · Est." in orange. Honest and correct.

- **Risk**: `ScrollView` horizontal scroll conflicts with parent vertical scroll in `FoodJournalView`
  - **Mitigation**: SwiftUI's scroll gesture disambiguation handles nested horizontal/vertical scrolls correctly. Horizontal scroll in pill row won't interfere with vertical page scroll. No special handling required.

---

## Success Criteria

- [ ] All 4 build targets compile without errors or warnings introduced by this change
- [ ] Text-logged entries show "AI · High" (blue) or "AI · Est." (orange) pill
- [ ] Voice-logged entries show "AI · High" (blue) or "AI · Est." (orange) pill
- [ ] Barcode-scanned entries show green "Barcode ✓" pill
- [ ] Legacy entries (`logSource == nil`) show no pill — no empty space or layout gap
- [ ] On iPhone SE simulator — all pills visible via horizontal scroll, no clipping
- [ ] Row height unchanged across all entry types
- [ ] Pill style matches existing `macroPill()` capsule pattern exactly
- [ ] Dark mode: all pill foreground and background colors are legible
