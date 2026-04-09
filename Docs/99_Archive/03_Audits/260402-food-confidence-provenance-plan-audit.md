# Plan Audit Report: Food Confidence & Data Provenance UI

**Audit Date**: 2026-04-02
**Plan Audited**: `Docs/02_Planning/Specs/260402-food-confidence-provenance-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is well-structured and the UI approach is sound, but it rests on a **false assumption** about the current state of `logSource` data. Codebase inspection reveals that `logSource` is only ever written as `"barcode"` (in `HomeViewModel.logFoodDirectly()`). The text/voice path (`HomeViewModel.logFood()`) never passes `logSource` to `insertLog()`, so all text and voice entries have `logSource == nil`. Since the plan treats `nil` as "legacy entry → no pill", the AI confidence display — which is 2/3 of the feature's value — will silently produce nothing. One additional layout concern exists for narrow screens. Both issues are straightforward to fix.

---

## Issues Found

### CRITICAL

#### C1: `logSource` is never set for text/voice entries — confidence pills will never appear

- **Location**: Plan Step 1 (`LogProvenance` failable init) and Plan Overview ("The data already exists")
- **Problem**: The plan assumes `logSource` is already stored as `"text"` or `"voice"` for non-barcode entries. Codebase evidence contradicts this.

  In `HomeViewModel.swift`:
  - `logFoodDirectly()` (barcode path) → passes `logSource: "barcode"` ✅ (line 239)
  - `logFood()` (text + voice path) → calls `insertLog(from: result, day: day, typedName: canonicalName, key: key, context: context)` with **no** `logSource` argument (line 118) → stored as `nil`
  - `insertLog(from: cache, ...)` overload (mock-mode cache hit, line 160) → has **no** `logSource` parameter at all → stored as `nil`

  A grep across the entire codebase confirms `logSource` is set in exactly one place: `logSource: "barcode"` on line 239.

- **Impact**: With the plan as written, text and voice entries get `logSource == nil`. The `LogProvenance` failable init returns `nil` for `nil` logSource → `provenancePill()` emits `EmptyView` → no pill is shown. The feature ships appearing to work for barcode entries only. Users logging via text (the most common path) get zero provenance signal. The feature's primary value proposition is broken.

- **Recommendation**: Add `logSource: "text"` to the `insertLog(from: result, ...)` call in `HomeViewModel.logFood()` (line 118). Both text and voice flow through this method and both display as "AI · X" labels — using `"text"` for both is correct and honest. The plan must be revised to include this as an explicit step, updating the "zero ViewModel changes" scope claim accordingly.

  Revised `insertLog` call in `logFood()`:
  ```swift
  insertLog(from: result, day: day, typedName: canonicalName, key: key,
            context: context, logSource: "text")
  ```

  Note: The cache-hit `insertLog` overload (line 160) also needs `logSource` support if cache hits should show provenance. However, the cache-hit path only runs in mock mode (`AppConfig.shared.mockMode`), so this can be deferred without user impact.

---

### MEDIUM

#### M1: Plain `HStack` chips row will clip on narrow screens, not wrap

- **Location**: Plan Phase 2, Step 3 ("Insert pill into `mealRow(entry:)`"). Plan notes: "The HStack already scrolls/wraps with `.fixedSize()` not set, so an extra pill won't break layout."
- **Problem**: This statement is incorrect. A plain `HStack` in SwiftUI **clips** content that exceeds the container width — it does not wrap or scroll. The existing macro chips row already has up to 5 pills (serving + P + C + F + fiber). Adding a 6th pill ("AI · Low" is the longest at ~75pt) on an iPhone SE (320pt screen, ~218pt usable width in the row after accounting for the 32pt time column, horizontal padding, and spacing) will cause the rightmost pills to be clipped or compressed.
- **Impact**: On 4.7" (iPhone SE, iPhone 8) and some 5.4" devices, the provenance pill may be partially or fully hidden. Users on smaller devices — who may be disproportionately budget-conscious and thus more trust-sensitive — will not see the feature.
- **Recommendation**: Wrap the macro chips `HStack` in a `ScrollView(.horizontal, showsIndicators: false)` at the call site in `mealRow()`. This is a one-line change, preserves layout on all screen sizes, and matches how the triggers row in `MealLogView` handles overflow. The provenance pill should remain the last item in the row.

  ```swift
  ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 5) {
          // ... existing pills ...
          provenancePill(for: entry)
      }
  }
  ```

---

### LOW

#### L1: Scope statement "zero ViewModel changes" is now incorrect

- **Location**: Plan Overview and Architecture Changes section
- **Problem**: The plan states "Zero model changes, zero service changes, zero new screens" and lists only `MealLogCard.swift` as the affected file. Fix C1 requires editing `HomeViewModel.swift`, making the scope statement wrong.
- **Impact**: Low — scope creep of a single line in one method. But it should be stated accurately so the checklist reflects the full change set.
- **Recommendation**: Update the Architecture Changes section to include `HomeViewModel.swift` — add `logSource: "text"` to one `insertLog` call in `logFood()`.

#### L2: `"AI · Est."` label may be confusing vs. `"AI · Low"`

- **Location**: Plan Step 1, `LogProvenance.label` computed property
- **Problem**: The distinction between `"AI · Est."` (confidence 0.5–0.79) and `"AI · Low"` (< 0.5) is semantically unclear to a user. "Estimated" could be interpreted as medium-quality, but the color (secondary/gray) is the weakest visual differentiator in the set. Users may not know what "Est." means.
- **Impact**: Low. The labels are functional but the middle tier's meaning may not be immediately obvious.
- **Recommendation**: Consider `"AI · Med"` instead of `"AI · Est."` for clearer gradient communication (High → Med → Low). Or simplify to two tiers: `"AI · Verified"` (≥ 0.8, blue) and `"AI · Estimated"` (< 0.8, orange). Decision can be made during implementation without blocking.

---

## Missing Elements

- [ ] `HomeViewModel.swift` not listed as an affected file — must be added (fix for C1)
- [ ] No mention of testing the text-logging path specifically for provenance display (would have caught C1 earlier)
- [ ] Cache-hit path (`insertLog(from: cache, ...)`) has no `logSource` parameter — not addressed in plan (deferred is acceptable since it only runs in mock mode)

---

## Unverified Assumptions

- [ ] **"The HStack already scrolls/wraps"** — INCORRECT per code inspection (see M1) — Risk: Medium
- [ ] **"`logSource` is already 'text'/'voice' for non-barcode entries"** — INCORRECT per code inspection (see C1) — Risk: Critical

---

## Questions for Clarification

1. Should voice entries (`logSource: "voice"`) show a distinct pill label from text entries (e.g., "Voice · High" vs "AI · High"), or is "AI · X" sufficient for both? The current plan treats both identically, which seems correct since both go through the Groq pipeline — but this should be an explicit decision.

2. For the cache-hit path (mock mode only): should it also set `logSource: "text"`? Low priority since it only affects mock mode.

---

## Recommendations

1. **Fix C1 first** — add `logSource: "text"` to `HomeViewModel.logFood()` line 118's `insertLog` call. Without this, the feature is barcode-only and misleadingly incomplete.
2. **Fix M1** — wrap the macro chips `HStack` in `ScrollView(.horizontal)` in `mealRow()`. One-line change, prevents clipping on small devices.
3. Update plan's Architecture Changes to include `HomeViewModel.swift`.
4. Update plan's scope statement from "single-file change" to "two-file change."
5. After RESOLVED plan is approved, the checklist should include explicit manual test steps for: (a) text entry → AI pill visible, (b) voice entry → AI pill visible, (c) barcode entry → Barcode pill visible, (d) iPhone SE simulator → no clipping.
