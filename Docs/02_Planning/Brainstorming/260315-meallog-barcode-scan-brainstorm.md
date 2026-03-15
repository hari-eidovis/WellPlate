# Brainstorm: Meal Log Barcode Scan

**Date**: 2026-03-15
**Status**: Ready for Planning

## Problem Statement
Add a barcode-based meal logging flow to the existing meal log experience so users can scan packaged foods instead of typing them manually. The feature should fit the current `MealLogSheetContent` entry modes, reuse the existing save/widget pipeline where possible, and avoid creating a disconnected logging path that bypasses meal context, reflection, or downstream history views.

## Constraints
- `MealLogView` and `MealLogModePickerView` already expose barcode entry points, but both are still `TODO` placeholders.
- The current save pipeline is text-first: `MealLogViewModel` gathers context and `HomeViewModel.logFood(on:coachOverride:context:)` runs `MealCoachService` plus `NutritionService`.
- That text pipeline is a poor fit for packaged foods when a barcode lookup can provide exact label nutrition.
- The app target already has `NSCameraUsageDescription`; no new camera permission key is needed for v1.
- The main app target deployment target is `iOS 18.6`, so `VisionKit` is available, but `DataScannerViewController` still requires `isSupported` and availability checks at runtime.
- Widget refresh is triggered from `HomeViewModel.refreshWidget(for:)`, so any barcode path should preserve the same post-save behavior.
- `FoodLogEntry` does not currently store barcode provenance, brand, or scan source metadata.

## Impacted Targets
- `WellPlate`
- Shared models/services used by `WellPlate`: `FoodLogEntry`, `HomeViewModel`, `MealLogViewModel`, `NutritionService`, widget refresh helpers
- `WellPlateWidget` regression verification only, because new logs should still flow through shared widget refresh data
- `ScreenTimeMonitor` and `ScreenTimeReport`: no expected code changes

## Approach 1: Barcode as Text Prefill
**Summary**: Scan a barcode, look up only a product name, prefill `foodDescription`, then send the user through the existing text-based save flow.
**Pros**:
- Lowest implementation scope
- Reuses `MealLogViewModel`, disambiguation, and save flow almost unchanged
- No new nutrition mapping logic or model fields required
**Cons**:
- Wastes the main benefit of barcode scanning: exact package nutrition
- Packaged-food accuracy still depends on `MealCoachService` and Groq estimation
- Users still need to review/edit and then wait for a second nutrition lookup
- Duplicate network work if the barcode provider already returned usable nutrition
**Complexity**: Low
**Risk**: Medium

## Approach 2: Direct Packaged-Food Logging
**Summary**: Scan a barcode, fetch product + nutriments from a barcode product database, show a compact confirmation UI, and save directly without using `MealCoachService` or `NutritionService`.
**Pros**:
- Best accuracy for packaged foods
- Faster perceived save path for successful lookups
- Avoids LLM cost and ambiguity for products that already have label data
- Clean separation between packaged-food logging and freeform meal logging
**Cons**:
- Requires a new lookup service and response mapping layer
- Needs UX decisions for serving basis: per serving, per 100g, full pack, or user-entered portion
- Products missing nutrition or portion data become hard failures unless fallback is added
- Increases data-shape/provenance questions for cached entries and logs
**Complexity**: Medium
**Risk**: Medium

## Approach 3: Hybrid Barcode Resolver with Graceful Fallback
**Summary**: Scan a barcode, attempt product lookup first, and use direct packaged-food logging when the result is complete enough. If lookup fails or data is incomplete, fall back to prefilling the standard meal log form so the user can still save through the existing text pipeline.
**Pros**:
- Preserves the speed/accuracy benefits of barcode for packaged foods
- Prevents dead ends when the barcode database is incomplete
- Keeps `MealLogSheetContent` as the single meal-log hub instead of spawning a separate product flow
- Lets the team ship a useful v1 without solving every packaged-food edge case upfront
**Cons**:
- More UI state transitions to manage
- Requires clear rules for when a lookup is “good enough” to bypass the text path
- Needs careful testing so save behavior, widget refresh, and dismiss flows stay consistent
**Complexity**: Medium
**Risk**: Low

## Edge Cases
- [ ] Camera permission denied, restricted, or unavailable at runtime
- [ ] `DataScannerViewController.isSupported` is false on some devices even though the app runs on iOS 18.6
- [ ] UPC-A codes may arrive in EAN-13-compatible form and need normalization before lookup
- [ ] Barcode resolves to a product without usable nutriments or without serving information
- [ ] Barcode is valid but the product database has no entry
- [ ] Product data is present but is only per 100g / 100ml, while the user wants to log a custom quantity
- [ ] User scans a non-food code or multi-pack item with misleading nutrition data
- [ ] Duplicate scans should not create accidental duplicate entries while the lookup/save is in flight
- [ ] Offline or slow network should not strand the user in the scanner flow
- [ ] Barcode flow must still respect the selected meal type, quantity field, triggers, and reflection context

## Open Questions
- [ ] Should barcode v1 support only packaged foods, or should it also try to infer loose items when a lookup misses?
- [ ] What is the logging default when package nutrition is returned per 100g / 100ml but no serving is defined: ask the user, assume one serving, or require quantity input?
- [ ] Do we want to store barcode/source metadata on `FoodLogEntry` now for auditability and future re-scan flows?
- [ ] Is Open Food Facts sufficient for v1 coverage, or does the product need a higher-coverage paid provider later?
- [ ] Do we need a non-`VisionKit` fallback scanner in v1, or is hiding/soft-disabling barcode on unsupported hardware acceptable?

## Recommendation
Recommend **Approach 3: Hybrid Barcode Resolver with Graceful Fallback**.

Use `VisionKit.DataScannerViewController` as the primary scanner UI inside the `.barcode` route of `MealLogSheetContent`, because it already wraps the underlying capture/recognition stack, exposes barcode payloads directly, and Apple explicitly recommends checking `isSupported` plus runtime availability before presenting it. After scan, call a dedicated barcode lookup service against a product database endpoint such as Open Food Facts `GET /api/v2/product/{barcode}`. If the lookup returns a product name plus enough nutriment data to map into `NutritionalInfo`, show a small confirmation/edit step and save through a direct packaged-food insert path that still applies `MealContext` and widget refresh. If lookup fails or is incomplete, prefill the existing meal form with the product name and let the user continue through the current text-based save flow.

This keeps barcode scanning inside the same meal-log surface, avoids forcing Groq to estimate packaged-food labels, and gives the team a clean fallback story instead of a brittle all-or-nothing scanner.

## Planner Handoff
- Recommended implementation direction: add a barcode scan mode backed by `VisionKit` scanning, a new barcode product lookup service, and a hybrid resolution path that either saves direct packaged-food nutrition or falls back to the existing typed meal flow
- Impacted files or areas: `MealLogView.swift`, `MealLogSheetContent` barcode destination, new scanner view/wrapper, new barcode lookup service(s), `HomeViewModel` save API, possible `FoodLogEntry` source metadata, tests around barcode normalization and fallback behavior
- Targets to verify later: `WellPlate` save/dismiss flows, widget refresh after barcode logs, unsupported-device behavior, permission-denied behavior, and no regressions in voice/type meal entry modes
