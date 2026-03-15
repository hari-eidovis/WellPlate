# Implementation Plan: Barcode Meal Logging

**Date:** 2026-03-15
**Status:** Ready for Implementation
**Approach:** Hybrid Barcode Resolver with Graceful Fallback (Approach 3 from brainstorm)

---

## Executive Summary

Add a barcode-scan meal-logging path to the existing `MealLogSheetContent` `.barcode` navigation destination and the `MealLogView` "Scan barcode" quick-action button, both of which are currently `TODO` placeholders. When a scan succeeds and the Open Food Facts lookup returns complete nutrition data, the user is shown a compact confirmation card and the meal is saved directly — bypassing `MealCoachService` and `NutritionService` — via a new `HomeViewModel.logFoodDirectly()` method that reuses the existing `upsertCache`/`insertLog`/`refreshWidget` pipeline. When the lookup fails or data is incomplete, the flow dismisses the scanner and pre-fills `MealLogViewModel.foodDescription` so the user continues through the standard text-based save path. Two optional provenance fields (`barcodeValue`, `logSource`) are added to `FoodLogEntry` for auditability; all existing `FoodLogEntry` initialiser call sites are unaffected because both fields default to `nil`.

---

## Decisions Made (Open Questions Resolved)

| Question | Decision |
|---|---|
| Serving default when only per-100g data available | Show quantity input pre-filled with "100 g" in confirmation UI; compute `NutritionalInfo` from entered quantity on "Log" tap |
| Non-VisionKit fallback in v1 | Not implemented; show `Text("Barcode scanning is not supported on this device.")` + back button when `DataScannerViewController.isSupported == false` |
| Barcode provenance on `FoodLogEntry` | YES — add optional `barcodeValue: String?` and `logSource: String?` with default `nil` |
| Open Food Facts coverage | Sufficient for v1; no paid provider needed |
| Missed lookup for loose items | Fallback to empty prefill; user types manually via the existing text path |

---

## File Map

| Action | Path |
|---|---|
| CREATE | `WellPlate/Core/Services/BarcodeProductService.swift` |
| CREATE | `WellPlate/Features + UI/Home/Views/BarcodeScannerView.swift` |
| CREATE | `WellPlate/Features + UI/Home/Views/BarcodeScanView.swift` |
| MODIFY | `WellPlate/Models/Food Log Entry/FoodLogEntry.swift` |
| MODIFY | `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift` |
| MODIFY | `WellPlate/Features + UI/Home/Views/MealLogView.swift` |

---

## Implementation Steps

### Phase 1: Data Layer

#### Step 1 — Add provenance fields to `FoodLogEntry`

**File:** `WellPlate/Models/Food Log Entry/FoodLogEntry.swift`

**Action:** Add two optional stored properties inside the `@Model` class, after the existing `quantityUnit` property. Then add both as optional parameters with `nil` defaults at the end of the designated `init`.

```swift
// Barcode provenance (optional — nil for voice/text log entries)
var barcodeValue: String?   // raw scanned barcode string (e.g. "0049000028911")
var logSource: String?      // "barcode", "voice", or "text" — for future analytics
```

In `init`, add at the end of the parameter list:
```swift
barcodeValue: String? = nil,
logSource: String? = nil
```

And in the body:
```swift
self.barcodeValue = barcodeValue
self.logSource = logSource
```

**Why:** Auditability for future re-scan or history-diff flows. Default `nil` means all existing `FoodLogEntry(...)` call sites in `HomeViewModel.insertLog` compile without change.

**Acceptance criteria:**
- `FoodLogEntry` compiles; all existing `insertLog` call sites in `HomeViewModel` require no changes.
- A newly created `FoodLogEntry` without the new parameters has `barcodeValue == nil` and `logSource == nil`.

**Risk:** Low. Adding optional SwiftData properties with default values is an additive, non-breaking migration.

> **SwiftData migration note:** SwiftData handles additive optional properties automatically via lightweight migration. No `VersionedSchema` or `MigrationPlan` is required for this change.

---

#### Step 2 — Create `BarcodeProductService.swift`

**File:** `WellPlate/Core/Services/BarcodeProductService.swift`

**Action:** Create the file with the following types. Follow the same file-header style as `NutritionServiceProtocol.swift` (no boilerplate comment block needed given the project convention).

**Types to define:**

```swift
import Foundation

// MARK: - Error

enum BarcodeProductError: LocalizedError {
    case notFound
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .notFound:           return "Product not found."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError:      return "Could not read product data."
        }
    }
}

// MARK: - Value types

struct NutritionPer100g {
    let calories: Double?
    let protein:  Double?
    let carbs:    Double?
    let fat:      Double?
    let fiber:    Double?
}

struct NutritionPerServing {
    let calories: Double?
    let protein:  Double?
    let carbs:    Double?
    let fat:      Double?
    let fiber:    Double?
}

struct BarcodeProduct {
    let barcode:              String
    let productName:          String
    let brandName:            String?
    let servingSize:          String?       // "serving_size" field, human-readable
    let servingSizeG:         Double?       // "serving_size_g" numeric
    let nutritionPer100g:     NutritionPer100g?
    let nutritionPerServing:  NutritionPerServing?
    let imageURL:             URL?

    /// True when the product has a non-empty name AND at least one calories value.
    var isComplete: Bool {
        !productName.isEmpty &&
        (nutritionPerServing?.calories != nil || nutritionPer100g?.calories != nil)
    }
}

// MARK: - Protocol

protocol BarcodeProductServiceProtocol {
    func lookupProduct(barcode: String) async throws -> BarcodeProduct?
}

// MARK: - Implementation

final class BarcodeProductService: BarcodeProductServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookupProduct(barcode: String) async throws -> BarcodeProduct? {
        // Try original barcode first; if not found, try stripping leading zeros (UPC-A/EAN-13 variants).
        if let product = try await fetchProduct(barcode: barcode) { return product }
        let stripped = barcode.drop(while: { $0 == "0" })
        if !stripped.isEmpty, stripped != barcode.dropFirst(0) {
            return try await fetchProduct(barcode: String(stripped))
        }
        return nil
    }

    private func fetchProduct(barcode: String) async throws -> BarcodeProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeProductError.decodingError
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw BarcodeProductError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil   // product does not exist — caller tries stripped barcode next
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any] else {
            throw BarcodeProductError.decodingError
        }
        let name = (product["product_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let nutriments = product["nutriments"] as? [String: Any]
        let per100g = NutritionPer100g(
            calories: nutriments?["energy-kcal_100g"] as? Double,
            protein:  nutriments?["proteins_100g"]    as? Double,
            carbs:    nutriments?["carbohydrates_100g"] as? Double,
            fat:      nutriments?["fat_100g"]          as? Double,
            fiber:    nutriments?["fiber_100g"]        as? Double
        )
        let perServing = NutritionPerServing(
            calories: nutriments?["energy-kcal_serving"] as? Double,
            protein:  nutriments?["proteins_serving"]    as? Double,
            carbs:    nutriments?["carbohydrates_serving"] as? Double,
            fat:      nutriments?["fat_serving"]          as? Double,
            fiber:    nutriments?["fiber_serving"]        as? Double
        )

        return BarcodeProduct(
            barcode:             barcode,
            productName:         name,
            brandName:           product["brands"]       as? String,
            servingSize:         product["serving_size"] as? String,
            servingSizeG:        product["serving_size_g"] as? Double,
            nutritionPer100g:    per100g,
            nutritionPerServing: perServing,
            imageURL:            (product["image_url"] as? String).flatMap(URL.init)
        )
    }
}
```

**Key implementation notes:**
- `isComplete` on `BarcodeProduct` is the single gate that decides whether to show confirmation UI vs fall back.
- `JSONSerialization` is used instead of `Codable` because the Open Food Facts `nutriments` dictionary uses dynamic keys with numeric suffixes (`_100g`, `_serving`), making a fully `Codable` model fragile.
- No `User-Agent` header is required for v1; OFF free tier does not enforce one for low-volume apps.
- The `session` parameter enables test injection of `URLProtocol`-based mocks.

**Acceptance criteria:**
- `BarcodeProductService` compiles with no imports beyond `Foundation`.
- `lookupProduct` returns `nil` (not throws) for a 404 response.
- `isComplete` returns `false` when `productName` is empty.
- `isComplete` returns `false` when both calorie fields are `nil`.

**Risk:** Low. Pure networking/parsing code with no SwiftData involvement.

---

### Phase 2: Scanner UI

#### Step 3 — Create `BarcodeScannerView.swift`

**File:** `WellPlate/Features + UI/Home/Views/BarcodeScannerView.swift`

**Action:** Create a `UIViewControllerRepresentable` wrapping `DataScannerViewController`. Place after other view files; no additional imports needed beyond `SwiftUI` and `VisionKit`.

```swift
import SwiftUI
import VisionKit

@available(iOS 17, *)
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// Called exactly once per distinct scan. Parent must reset `isActive` to re-enable.
    let onScan: (String) -> Void
    /// Called if the scanner becomes unavailable (permission denied, unsupported hardware,
    /// or a runtime camera failure). Message is already user-facing.
    let onError: ((String) -> Void)?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.upce, .ean8, .ean13, .code128, .qr, .aztec, .pdf417])
            ],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Only attempt to start once. Repeated calls from SwiftUI re-renders are ignored.
        guard !context.coordinator.didStartScanning else { return }
        context.coordinator.didStartScanning = true
        do {
            try uiViewController.startScanning()
        } catch let error as DataScannerViewController.ScanningUnavailable {
            // startScanning() throws synchronously for camera-restricted/unsupported
            // before any delegate callback fires — must be caught here, not only in
            // becameUnavailableWithError.
            context.coordinator.handleUnavailable(error)
        } catch {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onError: ((String) -> Void)?
        private var hasFired = false   // de-duplicate: only fire once per BarcodeScannerView lifetime
        var didStartScanning = false   // guard against repeated startScanning() calls on re-render

        init(onScan: @escaping (String) -> Void, onError: ((String) -> Void)?) {
            self.onScan = onScan
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasFired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue, !payload.isEmpty {
                    hasFired = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }

        /// Handles both synchronous throws from `startScanning()` and runtime delegate errors.
        func handleUnavailable(_ error: DataScannerViewController.ScanningUnavailable) {
            switch error {
            case .cameraRestricted:
                onError?("Camera access is required. Enable it in Settings.")
            case .unsupported:
                onError?("Barcode scanning is not supported on this device.")
            @unknown default:
                onError?("Camera unavailable.")
            }
        }

        // Runtime camera failure after scanning has started (e.g. interrupted by a call).
        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            handleUnavailable(error)
        }
    }
}
```

**Key implementation notes:**
- `@available(iOS 17, *)` guard is required for `DataScannerViewController`. The deployment target is iOS 18.6 so this is always satisfied at runtime, but the annotation is correct and avoids a compiler warning.
- `isGuidanceEnabled: true` renders the built-in "Point at a barcode" guidance label — no custom overlay needed.
- `isHighlightingEnabled: true` draws a bounding-box highlight on detected barcodes, giving visual feedback at zero cost.
- `hasFired` prevents duplicate `onScan` callbacks from multiple `didAdd` delegate calls within the same scan session.
- `didStartScanning` ensures `startScanning()` is called exactly once regardless of how many times SwiftUI calls `updateUIViewController`. This also ensures the caught error fires only once.
- `stopScanning()` is called immediately in the coordinator after a match to prevent further delegate callbacks while `BarcodeScanView` transitions away from `.scanning` phase.
- `handleUnavailable` is shared between the `startScanning()` catch block and the `becameUnavailableWithError` delegate, so both startup and runtime camera failures route through the same message logic.
- `BarcodeScanView` controls whether to show `BarcodeScannerView` at all (only rendered in `.scanning` phase), so there is no "reset `isActive`" protocol needed on the view itself.

**Acceptance criteria:**
- `BarcodeScannerView` compiles with `@available(iOS 17, *)`.
- `onScan` is called exactly once per scan session even if the delegate fires multiple times.
- No custom overlay is drawn (the DataScanner system UI is sufficient).

**Risk:** Low. DataScannerViewController wraps its own camera permission UI.

---

### Phase 3: Scan Flow UI

#### Step 4 — Create `BarcodeScanView.swift`

**File:** `WellPlate/Features + UI/Home/Views/BarcodeScanView.swift`

**Action:** Create the orchestrating view that drives the full scan-to-save flow. This is the view that `MealLogSheetContent` will route to for `.barcode`.

**State machine — `BarcodeScanPhase` enum:**

```swift
enum BarcodeScanPhase: Equatable {
    case scanning
    case resolving(barcode: String)
    case confirmProduct(BarcodeProduct, NutritionalInfo)
    case fallback(prefill: String)
    case error(String)

    static func == (lhs: BarcodeScanPhase, rhs: BarcodeScanPhase) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning): return true
        case (.resolving(let a), .resolving(let b)): return a == b
        case (.fallback(let a), .fallback(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        // .confirmProduct is excluded from equality — product data is not Equatable,
        // and this case never needs equality comparison in practice.
        }
    }
}
```

**View structure overview:**

```swift
import SwiftUI
import VisionKit

struct BarcodeScanView: View {
    @ObservedObject var viewModel: MealLogViewModel
    @ObservedObject var homeViewModel: HomeViewModel   // ObservedObject — drives loading/error UI
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    // Scan / lookup state
    @State private var phase: BarcodeScanPhase = .scanning
    @State private var lookupTask: Task<Void, Never>?
    @State private var toastMessage: String?

    // Confirmation card state — declared here (top-level) because @State cannot live
    // inside a @ViewBuilder computed property or method.
    @State private var confirmedQuantity: String = ""
    @State private var confirmedUnit: QuantityUnit = .grams
    @State private var isSaving: Bool = false

    // Save task — stored so it can be cancelled on disappear or explicit cancel.
    @State private var saveTask: Task<Void, Never>?

    private let productService: any BarcodeProductServiceProtocol

    init(viewModel: MealLogViewModel,
         homeViewModel: HomeViewModel,
         selectedDate: Date,
         productService: any BarcodeProductServiceProtocol = BarcodeProductService()) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _homeViewModel = ObservedObject(wrappedValue: homeViewModel)
        self.selectedDate = selectedDate
        self.productService = productService
    }

    var body: some View {
        ZStack {
            scannerOrFallbackContent
            toastOverlay
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { cancelToolbarItem }
        .onChange(of: phase) { _, newPhase in
            if case .fallback(let prefill) = newPhase {
                applyFallback(prefill: prefill)
            }
            // Pre-fill confirmedQuantity when entering confirmProduct phase
            if case .confirmProduct(let product, _) = newPhase {
                confirmedQuantity = product.servingSizeG.map { "\(Int($0))" } ?? "100"
                confirmedUnit = .grams
            }
        }
        .onDisappear {
            // Cancel any in-flight lookup or save if the user navigates away
            // (swipe-back gesture, system dismiss, etc.)
            lookupTask?.cancel()
            saveTask?.cancel()
        }
    }
}
```

**Phase rendering — `scannerOrFallbackContent`:**

```swift
@ViewBuilder
private var scannerOrFallbackContent: some View {
    switch phase {
    case .scanning:
        if #available(iOS 17, *), DataScannerViewController.isSupported {
            BarcodeScannerView { barcode in
                handleScan(barcode: barcode)
            }
            .ignoresSafeArea()
        } else {
            unsupportedDeviceView
        }

    case .resolving:
        resolvingView

    case .confirmProduct(let product, let nutrition):
        confirmProductView(product: product, nutrition: nutrition)

    case .fallback:
        // applyFallback() fires in onChange; show brief spinner while NavigationStack pops
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .error(let message):
        errorView(message: message)
    }
}
```

**`handleScan` — called by `BarcodeScannerView.onScan`:**

```swift
private func handleScan(barcode: String) {
    guard case .scanning = phase else { return }   // ignore if resolving/confirming already
    phase = .resolving(barcode: barcode)
    lookupTask = Task {
        do {
            // 10-second timeout backstop
            let product = try await withThrowingTaskGroup(of: BarcodeProduct?.self) { group in
                group.addTask { try await self.productService.lookupProduct(barcode: barcode) }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw BarcodeProductError.networkError(URLError(.timedOut))
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            guard !Task.isCancelled else { return }

            if let product, product.isComplete {
                let nutrition = buildNutritionalInfo(from: product)
                phase = .confirmProduct(product, nutrition)
            } else if let product {
                // Product found but incomplete nutrition
                showToast("Nutrition data incomplete. Log manually.")
                phase = .fallback(prefill: product.productName)
            } else {
                // Not found
                showToast("Product not found. Type your meal instead.")
                phase = .fallback(prefill: "")
            }
        } catch {
            guard !Task.isCancelled else { return }
            showToast("Couldn't reach product database. Type your meal instead.")
            phase = .fallback(prefill: "")
        }
    }
}
```

**`buildNutritionalInfo` — converts `BarcodeProduct` to `NutritionalInfo`:**

```swift
private func buildNutritionalInfo(from product: BarcodeProduct) -> NutritionalInfo {
    // Use a single consistent nutritional base — never mix per-serving and per-100g fields,
    // as they have different absolute values and mixing produces incorrect totals.
    // Priority: per-serving (if calories are present) → per-100g → zeros.
    let useServing = product.nutritionPerServing?.calories != nil
    let src: (calories: Double?, protein: Double?, carbs: Double?, fat: Double?, fiber: Double?)

    if useServing, let s = product.nutritionPerServing {
        src = (s.calories, s.protein, s.carbs, s.fat, s.fiber)
    } else if let h = product.nutritionPer100g {
        src = (h.calories, h.protein, h.carbs, h.fat, h.fiber)
    } else {
        src = (nil, nil, nil, nil, nil)
    }

    let serving = product.servingSize
        ?? (product.servingSizeG.map { "\(Int($0)) g" })
        ?? "100 g"    // triggers quantity input in confirmProductView when no serving data

    return NutritionalInfo(
        foodName:    product.productName,
        servingSize: serving,
        calories:    Int(src.calories ?? 0),
        protein:     src.protein ?? 0,
        carbs:       src.carbs   ?? 0,
        fat:         src.fat     ?? 0,
        fiber:       src.fiber   ?? 0,
        confidence:  1.0   // barcode lookup = label accuracy, not LLM estimation
    )
}
```

**`confirmProductView` — the confirmation card UI:**

`confirmedQuantity`, `confirmedUnit`, and `isSaving` are top-level `@State` properties on `BarcodeScanView` (declared in the view structure above). They are pre-filled in the `onChange(of: phase)` handler when entering `.confirmProduct`. Do not attempt to declare `@State` inside `confirmProductView` itself — Swift does not allow property wrappers inside closures or computed properties.

The card should show:
- Product name (`Text(product.productName).font(.r(.headline, .semibold))`)
- Brand name if non-nil (`Text(product.brandName ?? "").font(.r(.caption, .regular)).foregroundColor(AppColors.textSecondary)`)
- Nutrition summary row: calories, protein, carbs, fat (use existing `AppColors` and `.r()` font extension — follow the style in the existing nutrition card views)
- `quantitySection` equivalent: `TextField("Amount", ...)` + `QuantityUnit` segmented picker — reuse the same layout from `MealLogView.quantitySection`. Pre-fill quantity from `product.servingSizeG` formatted as a string, or "100" when only per-100g data exists.
- Meal type picker row — reuse `viewModel.selectedMealType` and `MealType.allCases` (same capsule button row as `MealLogView.mealTypePicker`)
- Eating triggers row — reuse `viewModel.selectedTriggers` and the `EatingTrigger.allCases` grid
- "Log This Food" primary button — calls `saveBarcodeMeal(product:originalNutrition:quantity:unit:)`
- "Edit Details" secondary button — transitions to `.fallback(prefill: product.productName)`

> **Quantity-adjusts-nutrition rule:** When only per-100g data is available (`product.nutritionPerServing == nil`), the "Log This Food" button must recalculate `NutritionalInfo` using the entered quantity before calling `saveBarcodeMeal`. Use the formula: `scaledCalories = per100g.calories * (enteredGrams / 100.0)`. Apply the same ratio to protein/carbs/fat/fiber.

**`saveBarcodeMeal` — the direct save path:**

```swift
private func saveBarcodeMeal(
    product: BarcodeProduct,
    nutrition: NutritionalInfo,
    quantity: String,
    unit: QuantityUnit
) {
    isSaving = true
    let context = MealContext(
        mealType:        viewModel.selectedMealType,
        eatingTriggers:  Array(viewModel.selectedTriggers),
        hungerLevel:     viewModel.hungerLevel,
        presenceLevel:   viewModel.presenceLevel,
        reflection:      viewModel.reflection.isEmpty ? nil : viewModel.reflection,
        quantity:        quantity.isEmpty ? nil : quantity,
        quantityUnit:    quantity.isEmpty ? nil : unit.rawValue
    )
    // Store the task so .onDisappear and the cancel button can cancel it
    // if the user navigates away mid-save (swipe dismiss, etc.).
    saveTask = Task {
        await homeViewModel.logFoodDirectly(
            nutrition: nutrition,
            barcode: product.barcode,
            on: selectedDate,
            context: context
        )
        guard !Task.isCancelled else { return }
        isSaving = false
        if homeViewModel.showError {
            showToast(homeViewModel.errorMessage)
        } else {
            HapticService.notify(.success)
            SoundService.playConfirmation()
            viewModel.shouldDismiss = true
        }
    }
}
```

**`applyFallback` — pre-fills text form and pops back:**

```swift
private func applyFallback(prefill: String) {
    lookupTask?.cancel()
    lookupTask = nil
    viewModel.foodDescription = prefill
    // NavigationStack pops automatically when BarcodeScanView disappears; MealLogView
    // (the .notepad destination) is not in the current path, so we pop all the way
    // to MealLogModePickerView and then immediately push .notepad.
    // Simplest mechanism: dismiss the NavigationStack layer via dismiss() so the user
    // lands on MealLogModePickerView, which will still use the shared mealLogViewModel
    // with foodDescription pre-filled. The mode picker doesn't clear foodDescription,
    // so the user just taps "Type" and sees the prefill.
    //
    // Alternative: pass a NavigationPath binding from MealLogSheetContent into BarcodeScanView
    // and use path.removeLast() + path.append(.notepad) for a zero-tap transition.
    // v1 uses the simpler dismiss() approach; the path binding approach is deferred.
    dismiss()
}
```

> **Fallback UX clarification:** In v1, `applyFallback` calls `dismiss()` which pops `BarcodeScanView` off the `NavigationStack` defined in `MealLogSheetContent`. The user lands back on `MealLogModePickerView`. `viewModel.foodDescription` is already set (the VM is shared via `@StateObject` in `MealLogSheetContent`), so the user taps "Type" and arrives at `MealLogView` with the food field pre-filled. If a zero-tap navigation to the type form is desired in a future iteration, pass the `NavigationPath` binding from `MealLogSheetContent` into `BarcodeScanView` and replace `dismiss()` with `path.removeLast(path.count); path.append(MealLogEntryMode.notepad)`.

**Toast helper:**

```swift
private func showToast(_ message: String) {
    toastMessage = message
    Task {
        try? await Task.sleep(for: .seconds(3))
        toastMessage = nil
    }
}

private var toastOverlay: some View {
    VStack {
        Spacer()
        if let msg = toastMessage {
            Text(msg)
                .font(.r(.caption, .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .padding(.bottom, 48)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    .animation(.easeInOut(duration: 0.25), value: toastMessage)
}
```

**`unsupportedDeviceView`:**

```swift
private var unsupportedDeviceView: some View {
    VStack(spacing: 16) {
        Image(systemName: "barcode.viewfinder")
            .font(.system(size: 48))
            .foregroundColor(AppColors.textSecondary)
        Text("Barcode scanning is not supported on this device.")
            .font(.r(.body, .regular))
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
```

**Cancel toolbar item:**

```swift
private var cancelToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
        Button {
            HapticService.impact(.light)
            lookupTask?.cancel()
            saveTask?.cancel()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppColors.primary)
        }
    }
}
```

**Acceptance criteria:**
- Tapping cancel from any phase dismisses the view without modifying `viewModel.foodDescription`.
- When `handleScan` is called while `phase != .scanning` (e.g. rapid double-scan), the second call is silently ignored.
- `buildNutritionalInfo` returns `calories == 0` rather than crashing when all nutrition fields are nil (guarded by `isComplete` upstream, but defensively safe).
- `saveBarcodeMeal` does not call `MealCoachService` or `NutritionService`.
- `viewModel.shouldDismiss = true` on successful save triggers the existing `MealLogSheetContent.onChange` dismiss handler and sets `didSave = true`.

**Risk:** Medium. State machine has seven distinct transitions; test each path manually.

---

### Phase 4: HomeViewModel — `logFoodDirectly`

#### Step 5 — Add `logFoodDirectly` to `HomeViewModel`

**File:** `WellPlate/Features + UI/Home/ViewModels/HomeViewModel.swift`

**Action:** Add the following method inside `HomeViewModel`, after the existing `logFood` method. It must call the currently-`private` helpers `upsertCache`, `insertLog` (both overloads exist; use the `NutritionalInfo` overload), and `refreshWidget`. Because `logFoodDirectly` lives in the same class, `private` access is fine — no visibility change is needed on the helpers.

To propagate `barcodeValue` and `logSource` to `FoodLogEntry`, the `insertLog(from:day:typedName:key:context:)` overload that takes `NutritionalInfo` must be extended with two new optional parameters. See note below.

```swift
/// Direct packaged-food save path — skips MealCoachService and NutritionService.
/// Called by BarcodeScanView after a successful barcode lookup.
func logFoodDirectly(
    nutrition: NutritionalInfo,
    barcode: String? = nil,
    on date: Date,
    context: MealContext? = nil
) async {
    isLoading = true
    showError = false
    errorMessage = ""
    defer { isLoading = false }

    let key = normalizeFoodKey(nutrition.foodName)
    let day = Calendar.current.startOfDay(for: date)

    do {
        try upsertCache(from: nutrition, key: key, displayName: nutrition.foodName)
        insertLog(
            from: nutrition,
            day: day,
            typedName: nutrition.foodName,
            key: key,
            context: context,
            barcodeValue: barcode,
            logSource: "barcode"
        )
        try modelContext.save()
        refreshWidget(for: day)
    } catch {
        #if DEBUG
        print("❌ [HomeViewModel] logFoodDirectly failed: \(error)")
        #endif
        showErrorMessage(userFacingErrorMessage(for: error))
    }
}
```

**Also modify the `NutritionalInfo` overload of `insertLog`** to accept and forward the new provenance fields:

```swift
private func insertLog(
    from info: NutritionalInfo,
    day: Date,
    typedName: String,
    key: String,
    context: MealContext? = nil,
    barcodeValue: String? = nil,
    logSource: String? = nil
) {
    let entry = FoodLogEntry(
        day: day,
        foodName: typedName,
        key: key,
        servingSize: info.servingSize,
        calories: info.calories,
        protein: info.protein,
        carbs: info.carbs,
        fat: info.fat,
        fiber: info.fiber,
        confidence: info.confidence,
        mealType: context?.mealType?.rawValue,
        eatingTriggers: context?.eatingTriggers.isEmpty == false ? context?.eatingTriggers.map(\.rawValue) : nil,
        hungerLevel: context?.hungerLevel,
        presenceLevel: context?.presenceLevel,
        reflection: context?.reflection?.isEmpty == false ? context?.reflection : nil,
        quantity: context?.quantity,
        quantityUnit: context?.quantityUnit,
        barcodeValue: barcodeValue,
        logSource: logSource
    )
    modelContext.insert(entry)
}
```

The `FoodCache` overload of `insertLog` is not modified (barcode provenance lives on `FoodLogEntry`, not `FoodCache`).

**Why `logFoodDirectly` does not call the `FoodCache` overload of `insertLog`:** The `FoodCache` overload is used when re-logging a previously cached item (mock mode). `logFoodDirectly` always has fresh `NutritionalInfo` from the barcode lookup, so the `NutritionalInfo` overload is correct.

**Acceptance criteria:**
- `logFoodDirectly` sets `isLoading = true` before await and `false` after, matching `logFood` behaviour.
- On success: `showError` is `false`, `errorMessage` is `""`, widget is refreshed.
- On `modelContext.save()` failure: `showError = true`, `errorMessage` is non-empty.
- Existing `logFood` call sites are unmodified and compile cleanly.
- `FoodLogEntry` created by this path has `barcodeValue == barcode` and `logSource == "barcode"`.

**Risk:** Low. Method reuses existing private helpers; no new logic paths in the save pipeline.

---

### Phase 5: Wire into MealLogSheetContent and Quick-Action Button

#### Step 6 — Replace the `.barcode` placeholder in `MealLogSheetContent`

**File:** `WellPlate/Features + UI/Home/Views/MealLogView.swift`

**Action:** In `MealLogSheetContent.body`, inside the `navigationDestination(for: MealLogEntryMode.self)` switch, replace:

```swift
case .barcode:
    // TODO: barcode scanner
    Text("Barcode scanner coming soon")
        .foregroundColor(AppColors.textSecondary)
```

With:

```swift
case .barcode:
    BarcodeScanView(
        viewModel: mealLogViewModel,
        homeViewModel: homeViewModel,
        selectedDate: selectedDate
    )
```

No other changes to `MealLogSheetContent` are required. `mealLogViewModel` is already the shared `@StateObject`; `homeViewModel` and `selectedDate` are already in scope.

**Acceptance criteria:**
- Selecting "Barcode" in `MealLogModePickerView` navigates to `BarcodeScanView`.
- `MealLogSheetContent` compiles; no new stored properties needed.

**Risk:** Low. Single line replacement.

---

#### Step 7 — Wire the "Scan barcode" quick-action button in `MealLogView`

**File:** `WellPlate/Features + UI/Home/Views/MealLogView.swift`

**Context:** `MealLogView` is reached from `MealLogSheetContent` when the user taps "Type" in the mode picker. The `.notepad` destination in `MealLogSheetContent` passes `viewModel` and `selectedDate` but does NOT currently pass a `NavigationPath` binding. To navigate to `.barcode` from within `MealLogView`, the view needs a way to append to the parent `NavigationStack`'s path.

**Approach:** Add an optional `onBarcodeTap: (() -> Void)?` callback parameter to `MealLogView`. `MealLogSheetContent` passes `{ navigationPath.append(MealLogEntryMode.barcode) }` when constructing `MealLogView` for the `.notepad` destination. The quick-action button calls this closure.

**Change 1 — Add parameter to `MealLogView`:**

```swift
struct MealLogView: View {
    // ... existing properties ...
    var onBarcodeTap: (() -> Void)? = nil   // add this line
```

**Change 2 — Update the "Scan barcode" quick-action button in `quickActionRow`:**

Replace:
```swift
quickActionButton(icon: "barcode.viewfinder", label: "Scan barcode") { /* TODO */ }
```

With:
```swift
quickActionButton(icon: "barcode.viewfinder", label: "Scan barcode") {
    onBarcodeTap?()
}
```

**Change 3 — Pass closure from `MealLogSheetContent`:**

In `MealLogSheetContent`, inside `navigationDestination(for: MealLogEntryMode.self)`, update the `.notepad` case:

```swift
case .notepad:
    MealLogView(
        viewModel: mealLogViewModel,
        selectedDate: selectedDate,
        onBarcodeTap: { navigationPath.append(MealLogEntryMode.barcode) }
    )
```

**Change 4 — Update the existing `#Preview` in `MealLogView.swift`:**

The existing preview at line ~680 constructs `MealLogView(viewModel: mealLogVM, selectedDate: Date())`. With the new optional `onBarcodeTap` defaulting to `nil`, this compiles unchanged. No edit required unless the team wants to verify the button visually in preview.

**Acceptance criteria:**
- Tapping "Scan barcode" in `MealLogView.quickActionRow` navigates to `BarcodeScanView` within the same `NavigationStack`.
- `MealLogView` used outside of `MealLogSheetContent` (e.g. in other previews or direct references) still compiles with `onBarcodeTap: nil` default.

**Risk:** Low. The `onBarcodeTap` parameter is optional with a nil default, so no other existing call site breaks.

---

### Phase 6: Edge Case Handling and Polish

#### Step 8 — Verify `DataScannerViewController.isSupported` guard

**File:** `WellPlate/Features + UI/Home/Views/BarcodeScanView.swift` (already covered in Step 4)

**Action:** Confirm the `unsupportedDeviceView` branch in `scannerOrFallbackContent` covers both:
1. `DataScannerViewController.isSupported == false` (hardware limitation)
2. `#available(iOS 17, *)` resolves to false (impossible on iOS 18.6 deployment target, but the `@available` annotation requires the guard)

No additional changes needed beyond what was described in Step 4.

---

#### Step 9 — Camera permission denial handling

**File:** `WellPlate/Features + UI/Home/Views/BarcodeScannerView.swift`

**Action:** Add `onError: ((String) -> Void)?` to `BarcodeScannerView` and implement `DataScannerViewControllerDelegate.dataScanner(_:becameUnavailableWithError:)` in the `Coordinator`. The error parameter is `DataScannerViewController.ScanningUnavailable` — switch on its cases to produce precise, actionable messages. The "Open Settings" button should only appear for `.cameraRestricted`; `.unsupported` shows the error message with only the back button.

**Updated `BarcodeScannerView` signature:**
```swift
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: ((String) -> Void)?   // add this
```

**Updated `Coordinator` — add delegate method:**
```swift
func dataScanner(_ dataScanner: DataScannerViewController,
                 becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
    switch error {
    case .cameraRestricted:
        onError?("Camera access is required. Enable it in Settings.")
    case .unsupported:
        onError?("Barcode scanning is not supported on this device.")
    @unknown default:
        onError?("Camera unavailable.")
    }
}
```

Also update `Coordinator.init` to store `onError`:
```swift
init(onScan: @escaping (String) -> Void, onError: ((String) -> Void)?) {
    self.onScan = onScan
    self.onError = onError
}
```

And `makeCoordinator`:
```swift
func makeCoordinator() -> Coordinator {
    Coordinator(onScan: onScan, onError: onError)
}
```

**In `BarcodeScanView.scannerOrFallbackContent`, pass both callbacks:**
```swift
BarcodeScannerView(onScan: { barcode in
    handleScan(barcode: barcode)
}, onError: { message in
    phase = .error(message)
})
```

**`errorView` UI — "Open Settings" button is conditional:**

The error message already encodes whether Settings is relevant (only `.cameraRestricted` produces a message that references Settings). Show the button whenever the message contains "Settings":

```swift
private func errorView(message: String) -> some View {
    VStack(spacing: 20) {
        Image(systemName: "camera.slash")
            .font(.system(size: 48))
            .foregroundColor(AppColors.textSecondary)
        Text(message)
            .font(.r(.body, .regular))
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 32)
        if message.contains("Settings") {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.r(.subheadline, .semibold))
            .foregroundColor(AppColors.primary)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
```

**Acceptance criteria:**
- `.cameraRestricted` → `.error("Camera access is required. Enable it in Settings.")` → error view shows "Open Settings" button.
- `.unsupported` → `.error("Barcode scanning is not supported on this device.")` → error view shows no "Open Settings" button (the back/cancel button is still present via the toolbar).
- `@unknown default` is handled; no unexhaustive switch warning.
- The `.error` phase does not auto-dismiss; user must tap the toolbar cancel button.

**Risk:** Low.

---

#### Step 10 — Duplicate scan guard

Already handled structurally:
- `BarcodeScannerView.Coordinator.hasFired` prevents duplicate `onScan` callbacks from the delegate.
- `BarcodeScanView.handleScan` guards with `guard case .scanning = phase else { return }`.

No additional code needed. Verify in manual testing.

---

#### Step 11 — Offline / slow network timeout

Already handled in `handleScan` via the `withThrowingTaskGroup` timeout pattern described in Step 4. The 10-second racing task throws `URLError(.timedOut)` which is caught and transitions to `.fallback(prefill: "")`.

No additional code needed. Verify in manual testing with network conditions set to "Very Poor" in the device proxy settings.

---

## Testing Strategy

### Unit Tests

**Create `WellPlateTests/BarcodeProductServiceTests.swift`:**
- `test_isComplete_falseWhenNameEmpty` — product with empty name returns `isComplete == false`
- `test_isComplete_falseWhenBothCaloriesNil` — product with non-empty name but nil calories both per serving and per 100g
- `test_isComplete_trueWhenServingCaloriesPresent` — per-serving calories only
- `test_isComplete_trueWhenPer100gCaloriesPresent` — per-100g calories only
- `test_lookupProduct_returns404AsNil` — inject `URLProtocol` mock returning HTTP 404; expect `nil` (not throw)
- `test_lookupProduct_throwsNetworkError` — inject mock returning network failure; expect `BarcodeProductError.networkError`
- `test_lookupProduct_tripsStrippedBarcode` — mock that returns 404 for "0049000028911" and real product for "49000028911"; verify stripping logic
- `test_lookupProduct_parsesNutrimentsCorrectly` — inject mock JSON with known nutriment values; verify all five fields on `NutritionPer100g` and `NutritionPerServing`

**Create `WellPlateTests/HomeViewModelBarcodeSaveTests.swift`:**
- `test_logFoodDirectly_setsIsLoadingDuringExecution` — use `XCTestExpectation` on `isLoading`
- `test_logFoodDirectly_insertsEntryWithBarcodeSource` — verify `barcodeValue` and `logSource == "barcode"` on inserted `FoodLogEntry`
- `test_logFoodDirectly_callsRefreshWidget` — subclass `HomeViewModel` and override `refreshWidget`; verify called once
- `test_logFoodDirectly_setsShowErrorOnSaveFailure` — inject failing `ModelContext`; verify `showError == true`

### Manual QA Checklist

**Save pipeline:**
- [ ] Scan a known EAN-13 barcode (e.g. Coca-Cola) → confirmation card appears with correct calories
- [ ] Tap "Log This Food" → entry appears in today's food journal
- [ ] Widget updates after barcode log (no widget refresh regression)
- [ ] `FoodLogEntry.barcodeValue` is non-nil; `logSource == "barcode"` (verify via SwiftData browser or debug print)

**Widget refresh:**
- [ ] Widget calorie count increases after barcode-logged meal

**Fallback flow:**
- [ ] Scan a barcode not in Open Food Facts → toast "Product not found." appears → MealLogModePickerView shown; tapping "Type" opens MealLogView with empty `foodDescription` (no prefill for not-found)
- [ ] Scan a barcode with partial data (name only, no calories) → toast "Nutrition data incomplete." → same fallback
- [ ] "Edit Details" from confirmation card → fallback to picker; MealLogView opens with product name pre-filled

**Unsupported device:**
- [ ] On Simulator or unsupported hardware, tapping "Barcode" shows `unsupportedDeviceView` (not a crash)

**Permission denied:**
- [ ] Deny camera in Settings → tap "Barcode" → `errorView` with "Open Settings" button appears
- [ ] Tap "Open Settings" → Settings app opens to WellPlate privacy settings

**Duplicate scan guard:**
- [ ] During `.resolving` phase, no second lookup fires even if the coordinator's delegate would re-fire

**Offline handling:**
- [ ] With airplane mode on, scan a barcode → 10-second timeout fires → toast + fallback to picker

**No regression on voice / text modes:**
- [ ] Full voice auto-log flow (VoiceMealLogView) unchanged
- [ ] Full text log flow (MealLogView) unchanged: save, disambiguation, widget refresh all work
- [ ] "Speak meal" quick-action button in MealLogView still transcribes correctly

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Open Food Facts returns inconsistent JSON field types (e.g. calories as `Int` instead of `Double`) | Medium | Use `as? Double` with `?? (nutriments?["field"] as? Int).map(Double.init)` fallback; test against real responses during development |
| `DataScannerViewController` delegate fires on background thread | Low | All `onScan` and `onError` callbacks are dispatched to main actor via `BarcodeScanView`'s `@MainActor` environment; verify no data races in testing |
| SwiftData lightweight migration fails for existing `FoodLogEntry` records when adding optional fields | Very Low | Optional properties always migrate cleanly; no schema version bump required |
| `upsertCache` is `private` and `logFoodDirectly` is in the same class | None | Same class access; no visibility change needed |
| `normalizeFoodKey` produces collisions between a barcode product name and an existing typed food name | Low | Same collision risk exists today for the text path; `FoodCache` uses `@Attribute(.unique)` which overwrites — this is acceptable and consistent |
| `BarcodeScanView` `dismisses` when `shouldDismiss = true` fires on the shared `mealLogViewModel` | Low | `MealLogSheetContent.onChange(of: mealLogViewModel.shouldDismiss)` handles this and sets `didSave = true`, the same path used by all other modes |

---

## Success Criteria

- [ ] Scanning a common packaged food (EAN-13) shows confirmation UI with correct nutrition within 3 seconds on a good network connection
- [ ] "Log This Food" saves the entry, refreshes the widget, and dismisses the sheet
- [ ] A `FoodLogEntry` created via barcode has `barcodeValue` set and `logSource == "barcode"`
- [ ] When Open Food Facts returns no product, the user sees a toast and is returned to `MealLogModePickerView`
- [ ] When only per-100g data exists, the confirmation screen shows a quantity field; entering a custom gram value rescales the nutrition before saving
- [ ] `DataScannerViewController.isSupported == false` shows the unsupported device message (not a crash or blank screen)
- [ ] Camera permission denied shows an error view with a Settings deep-link
- [ ] Scanning twice in quick succession does not create two lookup tasks or two entries
- [ ] After a 10-second network timeout, the user sees a toast and fallback, not a frozen spinner
- [ ] Voice auto-log (`VoiceMealLogView`), text log (`MealLogView`), disambiguation, and widget refresh all behave identically to before this feature
