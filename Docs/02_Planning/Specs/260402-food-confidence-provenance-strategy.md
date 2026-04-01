# Strategy: Food Confidence & Data Provenance UI

**Date**: 2026-04-02
**Source**: `Docs/01_Brainstorming/260402-feature-prioritization-from-deep-research-brainstorm.md` (Feature 1D)
**Status**: Ready for Planning

---

## Chosen Approach

**Inline provenance pill in `MealLogCard` meal rows.**

Add a small source/confidence badge directly inside each meal row in `MealLogCard.swift`. The badge reads the already-stored `logSource` and `confidence` fields on `FoodLogEntry` and renders a compact, color-coded label: "Barcode" (green, verified), "AI · High" (blue), "AI · Low" (orange/amber). No new data model changes, no new services, no new screens.

---

## Rationale

- **The data already exists.** `FoodLogEntry` already stores `logSource: String?` ("barcode", "voice", "text") and `confidence: Double?`. This is a pure UI exposure task — no model migrations, no service work.
- **Minimal scope, maximum trust signal.** A single pill per meal row answers the user's implicit question: "How reliable is this number?" This directly addresses the competitor pain point (Lose It! reviews: "barcode entries can still be wrong") without adding UI complexity.
- **Chosen over alternatives**:
  - *Detail sheet approach* (tap meal → see confidence in detail view): Over-engineered for a single confidence value. Provenance should be glanceable, not hidden behind a tap.
  - *Separate "data quality" screen*: Too much overhead; users won't navigate to it. Inline is the right level.
  - *Color-coded calorie number*: Ambiguous — users may interpret color as calorie level, not confidence.

---

## Affected Files & Components

- `WellPlate/Features + UI/Home/Components/MealLogCard.swift` — Add provenance pill to `mealRow()`. The `entry.logSource` and `entry.confidence` are already accessible here.
- No other file changes required.

---

## Architectural Direction

Single-file change. Inside `MealLogCard.mealRow()`, after the existing macro chips `HStack`, add a `provenancePill(for:)` helper that:

1. Reads `entry.logSource` → determines source icon + label
2. If source is `"barcode"` → show `"Barcode ✓"` in green (verified, no confidence needed)
3. If source is `"text"` or `"voice"` → read `entry.confidence` and show:
   - `confidence >= 0.8` → `"AI · High"` in blue
   - `confidence >= 0.5` → `"AI · Est."` in secondary color
   - `confidence < 0.5` or `nil` → `"AI · Low"` in amber/orange
4. Pill style: same capsule pattern as existing `macroPill()` — consistent, no new design language

The pill is added **inline in the macro chips row**, keeping the row height unchanged (no layout shift).

---

## Design Constraints

- Must use the same `macroPill()` capsule style already in `MealLogCard` for visual consistency
- Must NOT increase the row height — pill goes into the existing macro chips `HStack`
- Color tokens: use `AppColors` — green for verified, `AppColors.primary` (blue) for high confidence, `.orange` for low
- Font: `.r(10, .medium)` — matches existing macro pills
- `logSource == nil` → show nothing (graceful degradation for legacy entries logged before this field existed)
- Do not show a confidence percentage number — label only (avoids false precision)

---

## Non-Goals

- No new screen, sheet, or detail view
- No changes to `FoodLogEntry` model (zero migration risk)
- No changes to how `logSource` or `confidence` are computed or stored — those are set correctly at log time already
- No tooltip or info popover ("What does this mean?") in MVP — label copy is self-explanatory
- No changes to `MealLogView`, `BarcodeScanView`, `VoiceMealLogView`, or any ViewModel

---

## Open Risks

- **Legacy entries** have `logSource == nil` → provenance pill simply won't render. Acceptable — no misleading information shown.
- **Voice entries** currently set `logSource = "voice"` but are processed through the same Groq nutrition pipeline as text, so confidence scores apply equally. No special casing needed.
- **Barcode entries** may have `confidence` set from the USDA lookup — should still be shown as "Barcode ✓" (source takes precedence over confidence score for barcode).
