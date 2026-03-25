# Plan Audit Report: Barcode Meal Logging

**Audit Date:** 2026-03-15
**Plan:** `Docs/02_Planning/Plans/260315-barcode-scan-plan.md`
**Auditor:** plan-auditor agent
**Verdict:** APPROVED (all critical and high issues resolved; medium/low items noted for implementation)

---

## Executive Summary

The plan is well-structured and architecturally sound — it correctly targets the right files, reuses the existing save pipeline, and the hybrid fallback approach is the right call. However, two critical bugs in the camera permission/error-handling design would cause silent failures at runtime, and three high-priority issues (reactive state, mixed nutritional basis, orphaned Task) would cause incorrect UI or data corruption. These must be resolved before implementation begins.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. Wrong error type in Step 9 (camera permission denial)

- **Location:** Phase 6, Step 9 — "Camera permission denial handling"
- **Problem:** The plan says to check for `AVError.applicationIsNotAuthorizedToUseDevice` or `CaptureError.sessionConfigurationFailed` in the `DataScannerViewControllerDelegate` callback. Neither type is what the delegate actually delivers. The correct method signature is:
  ```swift
  func dataScanner(_ dataScanner: DataScannerViewController,
                   becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable)
  ```
  `DataScannerViewController.ScanningUnavailable` is an enum with cases like `.cameraRestricted`, `.unsupported` — not `AVError` or `CaptureError`. Code written as described will not compile.
- **Impact:** Step 9 as written produces a compile error. Camera-denied flows would not be handled at all.
- **Recommendation:** Replace the error-type references in Step 9 with `DataScannerViewController.ScanningUnavailable`. Switch on the enum cases (`.cameraRestricted`, `.unsupported`) to produce the appropriate error message string passed to `onError`.

---

#### 2. `try? uiViewController.startScanning()` silently swallows startup errors

- **Location:** Phase 2, Step 3 — `BarcodeScannerView.updateUIViewController`
- **Problem:** `DataScannerViewController.startScanning()` throws `DataScannerViewController.ScanningUnavailable` if the camera is restricted or the device is unsupported. The plan uses `try?`, discarding this error. The `becameUnavailableWithError` delegate method does NOT fire for errors thrown synchronously by `startScanning()` — only for errors that occur after scanning has started. So if the camera is denied before scanning starts (the common permission-denied case), the error is swallowed, `onError` never fires, and the user sees a frozen scanner UI with no feedback.
- **Impact:** Camera permission denied shows nothing — no error state, no Settings button, frozen screen.
- **Recommendation:** Catch the error from `startScanning()` explicitly and forward it through `onError`:
  ```swift
  do {
      try uiViewController.startScanning()
  } catch let error as DataScannerViewController.ScanningUnavailable {
      context.coordinator.onError?(errorMessage(for: error))
  } catch {}
  ```
  This must be done in `updateUIViewController` (or a lifecycle coordinator override) rather than discarding with `try?`.

---

### HIGH (Should Fix Before Proceeding)

#### 3. `@State` properties cannot live "within `confirmProductView`"

- **Location:** Phase 3, Step 4 — "confirmProductView — the confirmation card UI"
- **Problem:** The plan says "State needed within `confirmProductView`: a `@State private var confirmedQuantity: String`..." This implies declaring `@State` properties inside a `@ViewBuilder` computed property or method. Swift does not allow `@State` (or any property wrapper) inside a closure, function, or computed property — only at the top level of a `View` struct. Implementing it as described produces a compiler error.
- **Impact:** Compile failure if the implementor follows the plan literally.
- **Recommendation:** Declare `confirmedQuantity: String`, `confirmedUnit: QuantityUnit`, and `isSaving: Bool` as top-level `@State` properties on `BarcodeScanView` (alongside `phase`, `lookupTask`, `toastMessage`). Note in the plan that these are top-level states, not local to the helper view builder.

---

#### 4. `homeViewModel` declared as `let` — no reactive UI updates

- **Location:** Phase 3, Step 4 — `BarcodeScanView` view structure
- **Problem:** The plan declares `let homeViewModel: HomeViewModel`. Since `HomeViewModel` is an `ObservableObject`, using `let` means SwiftUI does not subscribe to its `@Published` properties. During a save, `homeViewModel.isLoading` becomes `true` and then `false`, but `BarcodeScanView` will not re-render, so the "Log This Food" button cannot be disabled during the save. More critically, `homeViewModel.showError` and `homeViewModel.errorMessage` are checked after `await`, which works once inside the `Task`, but any subsequent reactive display of `errorMessage` in the UI won't update.
- **Impact:** Loading indicator / button disabled state during save does not work. Error state may not be reflected in the UI.
- **Recommendation:** Change to `@ObservedObject var homeViewModel: HomeViewModel`. This is consistent with how `MealLogView` uses its `viewModel`.

---

#### 5. Mixed nutritional basis in `buildNutritionalInfo`

- **Location:** Phase 3, Step 4 — `buildNutritionalInfo`
- **Problem:** The plan uses per-serving values and falls back per-field to per-100g:
  ```swift
  let cals  = product.nutritionPerServing?.calories ?? product.nutritionPer100g?.calories ?? 0
  let prot  = product.nutritionPerServing?.protein  ?? product.nutritionPer100g?.protein  ?? 0
  ```
  If a product has `nutritionPerServing.calories = 200` but `nutritionPerServing.protein = nil`, the result mixes 200 kcal (per serving) with per-100g protein. These are different bases and produce nutritionally incorrect data that could be significantly wrong (e.g. a serving is 30g, so per-100g protein is 3× higher).
- **Impact:** Logged nutrition data is silently wrong for products with partial per-serving fields, which is a common occurrence in Open Food Facts.
- **Recommendation:** Choose a single base consistently. Preferred logic: if `nutritionPerServing` has `calories != nil`, use ALL per-serving fields (nil fields stay nil/0); otherwise fall back to ALL per-100g fields. Do not mix bases field-by-field.
  ```swift
  let useServing = product.nutritionPerServing?.calories != nil
  let src = useServing ? product.nutritionPerServing : nil
  let src100 = product.nutritionPer100g
  let cals  = (useServing ? src?.calories  : src100?.calories)  ?? 0
  let prot  = (useServing ? src?.protein   : src100?.protein)   ?? 0
  // ... etc
  ```

---

#### 6. Detached `Task` in `saveBarcodeMeal` not cancelled on view dismissal

- **Location:** Phase 3, Step 4 — `saveBarcodeMeal`
- **Problem:** `saveBarcodeMeal` creates a `Task { ... }` that `await`s `homeViewModel.logFoodDirectly(...)` and then sets `viewModel.shouldDismiss = true`. If the user swipe-dismisses or cancels the sheet while the save is in flight (race condition), the Task continues and sets `shouldDismiss = true` on a ViewModel whose sheet is already gone, potentially triggering a double-dismiss or phantom `didSave = true` in the parent.
- **Impact:** Rare but real: phantom widget refresh, stale `shouldDismiss` triggering on a subsequent sheet presentation.
- **Recommendation:** Store the save task in a `@State private var saveTask: Task<Void, Never>?` (similar to `lookupTask`). Cancel it in the cancel toolbar button action and in an `.onDisappear` modifier on `BarcodeScanView`.

---

### MEDIUM (Fix During Implementation)

#### 7. `lookupTask` not cancelled on system back-swipe gesture

- **Problem:** The cancel toolbar button calls `lookupTask?.cancel()`, but the iOS system back-swipe gesture (interactive pop) doesn't. If the user swipe-dismisses during `.resolving` phase, the lookup task continues to completion and attempts to update `phase` on a disappeared view.
- **Recommendation:** Add `.onDisappear { lookupTask?.cancel() }` to `BarcodeScanView.body`. SwiftUI calls `onDisappear` for both explicit back and interactive-pop navigation.

---

#### 8. Force-unwrap `group.next()!` in `handleScan` timeout pattern

- **Problem:** `let result = try await group.next()!` — if both tasks somehow complete before `next()` is awaited (possible under heavy system load), `group.next()` returns the first result, and the `!` is safe. But `TaskGroup.next()` returns `nil` only when the group is exhausted — and since exactly two tasks are always added, the `!` is technically safe here. However, defensive code should use `guard let`:
  ```swift
  guard let result = try await group.next() else { throw BarcodeProductError.decodingError }
  ```
- **Recommendation:** Replace `group.next()!` with `guard let` for clarity and safety.

---

#### 9. Inconsistent fallback UX depending on entry path

- **Problem:** `applyFallback` calls `dismiss()` in both entry scenarios, but the result differs:
  - Entry via **ModePicker → `.barcode`** (path: `[.barcode]`): `dismiss()` pops to ModePickerView. `foodDescription` is pre-filled, but the user must still tap "Type" to get to MealLogView — an extra tap.
  - Entry via **MealLogView quick-action button** (path: `[.notepad, .barcode]`): `dismiss()` pops to MealLogView. `foodDescription` is pre-filled and immediately visible — better UX.

  The plan only documents the first scenario and doesn't acknowledge the second is better. This inconsistency exists in v1 but should be documented so it can be improved.
- **Recommendation:** Document both paths explicitly. For a v1.1 improvement, pass the `NavigationPath` binding into `BarcodeScanView` and use `path.removeLast(path.count - 1); path.append(.notepad)` from the ModePicker path to give consistent one-step UX.

---

#### 10. `isComplete` passes products with zero macros to confirmation UI

- **Problem:** `isComplete` requires only `productName` + any calories field. A product can be "complete" with calories = 150 and protein/carbs/fat/fiber all nil. `buildNutritionalInfo` maps nil macros to `0.0`. The confirmation card would display 0g protein, 0g carbs, 0g fat — which is technically logged and could be audited later as if the food has no macros.
- **Recommendation:** Either (a) add a data-quality caveat label in the confirmation UI ("Macro data unavailable"), or (b) tighten `isComplete` to also require at least one macro field. Option (a) is lower risk for v1.

---

### LOW (Consider for Future)

#### 11. Step 3 and Step 9 define `BarcodeScannerView` inconsistently

- **Problem:** Step 3 defines `BarcodeScannerView` with only `onScan`. Step 9 adds `onError` as a separate amendment. This means the implementation must mentally merge two non-adjacent steps to get the final signature. If Step 3 is implemented first and tested, it will be immediately invalidated by Step 9.
- **Recommendation:** Move `onError: ((String) -> Void)?` into the Step 3 definition so the struct is complete from the start.

---

#### 12. No haptic/sound feedback for barcode saves

- **Problem:** `MealLogView.onChange(of: viewModel.shouldDismiss)` plays `HapticService.notify(.success)` and `SoundService.playConfirmation()`. When the user enters via ModePicker → BarcodeScanView (without ever seeing MealLogView), `MealLogView` is not in the NavigationStack, so its `onChange` never fires. Barcode saves are silent.
- **Recommendation:** Add explicit `HapticService.notify(.success)` and `SoundService.playConfirmation()` calls in `saveBarcodeMeal` after confirming `!homeViewModel.showError`, before setting `viewModel.shouldDismiss = true`.

---

#### 13. Open Food Facts uses `energy_100g` (kJ) for some products, not `energy-kcal_100g`

- **Problem:** The plan maps `nutriments["energy-kcal_100g"]` for calories. Some products in OFF only have `energy_100g` (in kilojoules, not kcal). For these products, the calories field would be `nil`, causing `isComplete` to return `false` (fallback triggered) even though full nutrition is present.
- **Recommendation:** Add a fallback: if `energy-kcal_100g` is nil, try `energy_100g` and divide by 4.184 to convert kJ → kcal. Also check `energy-kcal_serving` vs `energy_serving`. This handles a meaningful chunk of European product barcodes.

---

## Missing Elements

- [ ] No mention of cancelling `lookupTask` in `.onDisappear` (only explicit cancel button)
- [ ] No mention of cancelling `saveTask` (the task inside `saveBarcodeMeal`) on disappear
- [ ] The `onError` closure on `BarcodeScannerView` is missing from Step 3 (appears only in Step 9)
- [ ] No UI indication of data quality when macros are nil/zero in confirmation card
- [ ] No documentation of the two different fallback UX paths (ModePicker vs MealLogView quick-action)
- [ ] No haptic/sound feedback specified for barcode-path successful saves

---

## Unverified Assumptions

- [ ] `DataScannerViewController.startScanning()` throws synchronously for permission-denied (vs. only via delegate) — Risk: **High** (this is what CRITICAL issue #2 is about; verify against Apple's VisionKit docs before Step 3)
- [ ] `try? uiViewController.startScanning()` is safe to call on every `updateUIViewController` pass — Risk: **Medium** (confirmed idempotent in Apple samples, but should verify iOS 18.6 behavior)
- [ ] Open Food Facts `nutriments` dictionary always uses `Double` for numeric fields — Risk: **Medium** (some fields come as `Int` in real responses; the plan mentions this in the Risks table but the fallback pattern `?? (nutriments?["field"] as? Int).map(Double.init)` is mentioned only in the Risks table, not in the actual parsing code in Step 2)
- [ ] SwiftData lightweight migration is automatic for added optional `@Model` properties — Risk: **Low** (this is correct for iOS 17+, confirmed)
- [ ] `normalizeFoodKey` is accessible from `logFoodDirectly` (same class) — Risk: **None** (confirmed: `private` is fine within the same type)

---

## Security Considerations

- [ ] The Open Food Facts API URL is constructed by string interpolation of a raw barcode value: `"https://world.openfoodfacts.org/api/v2/product/\(barcode).json"`. If the barcode payload contains path-traversal characters (`/`, `..`) or URL special characters, this could produce an unexpected URL. **Mitigation:** Add percent-encoding or a whitelist check (barcodes should only contain digits; reject non-numeric payloads before calling the service).
- [ ] The `UIApplication.openSettingsURLString` usage in `errorView` is standard and safe.
- [ ] No credentials or API keys are involved (Open Food Facts is open and unauthenticated for v1).

---

## Performance Considerations

- [ ] The `confirmProductView` is re-rendered every time `phase` changes (since `.confirmProduct` always `!=` under the custom `Equatable`). This is acceptable but could cause layout recalculation. If the confirmation card is complex, consider caching the rendered card.
- [ ] `BarcodeProductService` uses `URLSession.shared` by default — this shares the session pool with all other network activity. Not a concern for v1 but worth noting if other services also use `.shared`.
- [ ] The 10-second timeout is reasonable for the scan-to-confirmation flow, but users on slow networks may perceive a 10-second spinner as a crash. Consider a visual progress indicator or a shorter first-timeout (5s) with an optional retry.

---

## Questions for Clarification

1. **Step 5, `logFoodDirectly`:** The plan adds `barcodeValue` and `logSource` parameters to the `insertLog(from:NutritionalInfo:...)` overload. Does this require updating the `FoodCache` overload as well, to allow future text-logged entries to carry `logSource: "text"`? If provenance is valuable for analytics, the `FoodCache` overload should be updated now, before the parameter list diverges further.

2. **`BarcodeScanView` `confirmProductView` quantity pre-fill:** When `product.servingSizeG` is available (numeric grams), the plan pre-fills the quantity field with it and sets unit to `.grams`. But `servingSize` (the human-readable string, e.g. "1 can (355 ml)") may indicate a liquid. Should the unit default to `.millilitres` when the serving size string contains "ml" or "oz"? Or is `.grams` always the safe default for v1?

3. **`MealLogSheetContent` dismiss after barcode save:** The `MealLogSheetContent.onChange(of: mealLogViewModel.shouldDismiss)` only sets `didSave = true`. The actual sheet dismissal must be triggered by the parent binding the `didSave` flag. Is this confirmed to work for the barcode path (entering via ModePicker → BarcodeScanView, where `MealLogView.onChange` never fires and thus `dismiss()` is never called from `MealLogView`)? Verify that the parent caller (likely `HomeView` or the sheet presenter) observes `didSave` and dismisses accordingly.

---

## Recommendations

1. **Fix CRITICAL #1 and #2 together in Step 3 / Step 9:** Rewrite `updateUIViewController` to catch and forward `DataScannerViewController.ScanningUnavailable` errors, and rewrite Step 9's coordinator delegate method to handle the correct error type. These two fixes share a surface area and should be written atomically.

2. **Fix HIGH #5 (mixed basis) in `buildNutritionalInfo` before writing any other BarcodeScanView code:** This is a data correctness bug that would affect every barcode-logged entry for products with partial per-serving data. It is cheap to fix at the design stage but expensive to correct in stored `FoodLogEntry` records after logging.

3. **Consolidate `BarcodeScannerView` definition:** Merge Steps 3 and 9 so `BarcodeScannerView` is fully specified once, including `onError`. Implement Phase 6 edge-case handling as part of Phase 2, not as a later amendment.

4. **Add `.onDisappear { lookupTask?.cancel(); saveTask?.cancel() }` to the plan** as a first-class implementation step in Phase 3, not just a testing note.

5. **Add kJ → kcal fallback to `BarcodeProductService`** before merging. This is a one-line addition but meaningfully widens coverage for European barcodes.

---

## Sign-off Checklist

- [x] CRITICAL #1 resolved — correct `DataScannerViewController.ScanningUnavailable` error type used in Step 9 (Option A: switch on cases with precise per-case messages)
- [x] CRITICAL #2 resolved — `didStartScanning` flag guards `startScanning()`; errors caught and forwarded via `handleUnavailable()` shared by both startup catch and `becameUnavailableWithError` delegate
- [x] HIGH #3 resolved — `confirmedQuantity`, `confirmedUnit`, `isSaving` declared as top-level `@State` on `BarcodeScanView`; pre-filled in `onChange(of: phase)`
- [x] HIGH #4 resolved — `homeViewModel` changed to `@ObservedObject`; init uses `_homeViewModel = ObservedObject(wrappedValue:)`
- [x] HIGH #5 resolved — `buildNutritionalInfo` commits to a single base (per-serving if calories present, else per-100g); no field-by-field mixing
- [x] HIGH #6 resolved — `saveTask` stored as `@State`, cancelled in cancel button and `.onDisappear`; `Task.isCancelled` guard before post-save state updates
- [ ] Security review completed (barcode URL injection)
- [ ] Performance implications understood (10s timeout UX)
- [ ] Rollback strategy: all new fields on `FoodLogEntry` are optional with `nil` defaults — existing data is unaffected; new views can be reverted without a schema rollback
