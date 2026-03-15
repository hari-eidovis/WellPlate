import SwiftUI
import VisionKit

// MARK: - Phase

private enum BarcodeScanPhase: Equatable {
    case scanning
    case resolving(barcode: String)
    case confirmProduct(BarcodeProduct, NutritionalInfo)
    case error(String)

    static func == (lhs: BarcodeScanPhase, rhs: BarcodeScanPhase) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning):                 return true
        case (.resolving(let a), .resolving(let b)): return a == b
        case (.error(let a), .error(let b)):         return a == b
        default: return false
        // .confirmProduct excluded — BarcodeProduct is not Equatable,
        // and this case never needs equality comparison in practice.
        }
    }
}

// MARK: - View

struct BarcodeScanView: View {
    @ObservedObject var viewModel: MealLogViewModel
    @ObservedObject var homeViewModel: HomeViewModel
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    // Scan / lookup state
    @State private var phase: BarcodeScanPhase = .scanning
    @State private var lookupTask: Task<Void, Never>?
    @State private var toastMessage: String?

    // Confirmation card state — must be top-level @State; cannot live inside
    // a @ViewBuilder computed property or method.
    @State private var confirmedQuantity: String = ""
    @State private var confirmedUnit: QuantityUnit = .grams
    @State private var isSaving: Bool = false

    // Save task — stored so it can be cancelled on disappear or explicit cancel.
    @State private var saveTask: Task<Void, Never>?

    private let productService: any BarcodeProductServiceProtocol
    private let nutritionService: any NutritionServiceProtocol

    init(viewModel: MealLogViewModel,
         homeViewModel: HomeViewModel,
         selectedDate: Date,
         productService: any BarcodeProductServiceProtocol = BarcodeProductService(),
         nutritionService: any NutritionServiceProtocol = NutritionService()) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _homeViewModel = ObservedObject(wrappedValue: homeViewModel)
        self.selectedDate = selectedDate
        self.productService = productService
        self.nutritionService = nutritionService
    }

    var body: some View {
        ZStack {
            scannerOrFallbackContent
            toastOverlay
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { cancelToolbarItem }
        .onChange(of: phase) { _, newPhase in
            if case .confirmProduct(let product, _) = newPhase {
                confirmedQuantity = product.servingSizeG.map { "\(Int($0))" } ?? "100"
                confirmedUnit = .grams
            }
        }
        .onDisappear {
            lookupTask?.cancel()
            saveTask?.cancel()
        }
    }

    // MARK: - Phase rendering

    @ViewBuilder
    private var scannerOrFallbackContent: some View {
        switch phase {
        case .scanning:
            if #available(iOS 17, *), DataScannerViewController.isSupported {
                BarcodeScannerView(
                    onScan: { barcode in handleScan(barcode: barcode) },
                    onError: { message in phase = .error(message) }
                )
                .ignoresSafeArea()
            } else {
                unsupportedDeviceView
            }

        case .resolving:
            resolvingView

        case .confirmProduct(let product, let nutrition):
            confirmProductView(product: product, nutrition: nutrition)

        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Scan handling

    private func handleScan(barcode: String) {
        print("[BarcodeScan] handleScan called — barcode: \(barcode), phase: \(phase)")
        guard case .scanning = phase else {
            print("[BarcodeScan] ignoring scan — phase is not .scanning")
            return
        }
        phase = .resolving(barcode: barcode)
        print("[BarcodeScan] phase → .resolving, starting lookup task")
        lookupTask = Task {
            do {
                print("[BarcodeScan] calling productService.lookupProduct(\(barcode))")
                let product = try await withThrowingTaskGroup(of: BarcodeProduct?.self) { group in
                    group.addTask { try await self.productService.lookupProduct(barcode: barcode) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        throw BarcodeProductError.networkError(URLError(.timedOut))
                    }
                    guard let result = try await group.next() else {
                        throw BarcodeProductError.decodingError
                    }
                    group.cancelAll()
                    return result
                }

                guard !Task.isCancelled else {
                    print("[BarcodeScan] task cancelled after lookup — skipping phase update")
                    return
                }

                if let product {
                    print("[BarcodeScan] product found: '\(product.productName)' | isComplete: \(product.isComplete) | per100g calories: \(product.nutritionPer100g?.calories as Any) | perServing calories: \(product.nutritionPerServing?.calories as Any)")
                } else {
                    print("[BarcodeScan] product nil — not found in OFF")
                }

                if let product {
                    // Show confirmation immediately with whatever OFF has.
                    // If nutrition is missing, GROQ will be called when user taps "Log This Food".
                    let nutrition = buildNutritionalInfo(from: product)
                    print("[BarcodeScan] phase → .confirmProduct | cal: \(nutrition.calories) | hasNutrition: \(product.isComplete)")
                    phase = .confirmProduct(product, nutrition)
                } else {
                    print("[BarcodeScan] product not found — fallback with empty prefill")
                    showToast("Product not found. Type your meal instead.")
                    scheduleApplyFallback(prefill: "")
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[BarcodeScan] ❌ lookup error: \(error)")
                showToast("Couldn't reach product database. Type your meal instead.")
                scheduleApplyFallback(prefill: "")
            }
        }
    }

    // MARK: - Nutrition builder

    private func buildNutritionalInfo(from product: BarcodeProduct) -> NutritionalInfo {
        // Commit to a single nutritional base — never mix per-serving and per-100g
        // fields, as they represent different absolute quantities.
        // Priority: per-serving (if calories present) → per-100g → zeros.
        let useServing = product.nutritionPerServing?.calories != nil
        let calories: Double?
        let protein:  Double?
        let carbs:    Double?
        let fat:      Double?
        let fiber:    Double?

        if useServing, let s = product.nutritionPerServing {
            (calories, protein, carbs, fat, fiber) = (s.calories, s.protein, s.carbs, s.fat, s.fiber)
        } else if let h = product.nutritionPer100g {
            (calories, protein, carbs, fat, fiber) = (h.calories, h.protein, h.carbs, h.fat, h.fiber)
        } else {
            (calories, protein, carbs, fat, fiber) = (nil, nil, nil, nil, nil)
        }

        let serving = product.servingSize
            ?? product.servingSizeG.map { "\(Int($0)) g" }
            ?? "100 g"

        return NutritionalInfo(
            foodName:    product.productName,
            servingSize: serving,
            calories:    Int(calories ?? 0),
            protein:     protein ?? 0,
            carbs:       carbs   ?? 0,
            fat:         fat     ?? 0,
            fiber:       fiber   ?? 0,
            confidence:  1.0
        )
    }

    // MARK: - Save

    private func saveBarcodeMeal(product: BarcodeProduct, nutrition: NutritionalInfo) {
        isSaving = true
        // Capture @State values before entering the async Task.
        let qty  = confirmedQuantity
        let unit = confirmedUnit
        let context = MealContext(
            mealType:       viewModel.selectedMealType,
            eatingTriggers: Array(viewModel.selectedTriggers),
            hungerLevel:    viewModel.hungerLevel,
            presenceLevel:  viewModel.presenceLevel,
            reflection:     viewModel.reflection.isEmpty ? nil : viewModel.reflection,
            quantity:       qty.isEmpty ? nil : qty,
            quantityUnit:   qty.isEmpty ? nil : unit.rawValue
        )

        saveTask = Task {
            // 1. Determine final nutrition.
            let finalNutrition: NutritionalInfo
            if !product.isComplete {
                // OFF had no calorie data — ask GROQ using the product name + user's quantity.
                let query = [product.productName, product.brandName].compactMap { $0 }.joined(separator: " ")
                let serving = qty.isEmpty ? nil : "\(qty) \(unit.rawValue)"
                print("[BarcodeScan] OFF incomplete — querying GROQ for '\(query)', serving: \(serving ?? "nil")")
                do {
                    let groqResult = try await nutritionService.analyzeFood(
                        request: NutritionAnalysisRequest(foodDescription: query, servingSize: serving)
                    )
                    // Keep the barcode product name; use GROQ macros.
                    finalNutrition = NutritionalInfo(
                        foodName:    product.productName,
                        servingSize: groqResult.servingSize,
                        calories:    groqResult.calories,
                        protein:     groqResult.protein,
                        carbs:       groqResult.carbs,
                        fat:         groqResult.fat,
                        fiber:       groqResult.fiber,
                        confidence:  groqResult.confidence
                    )
                    print("[BarcodeScan] GROQ nutrition | cal: \(finalNutrition.calories) protein: \(finalNutrition.protein) carbs: \(finalNutrition.carbs) fat: \(finalNutrition.fat)")
                } catch {
                    print("[BarcodeScan] GROQ failed: \(error) — logging with 0 values")
                    finalNutrition = nutrition
                }
            } else if product.nutritionPerServing == nil,
                      let grams = Double(qty), grams > 0,
                      let h = product.nutritionPer100g {
                // OFF has per-100g data — scale to user's entered quantity.
                let ratio = grams / 100.0
                finalNutrition = NutritionalInfo(
                    foodName:    nutrition.foodName,
                    servingSize: "\(qty) \(unit.rawValue)",
                    calories:    Int((h.calories ?? 0) * ratio),
                    protein:     (h.protein ?? 0) * ratio,
                    carbs:       (h.carbs   ?? 0) * ratio,
                    fat:         (h.fat     ?? 0) * ratio,
                    fiber:       (h.fiber   ?? 0) * ratio,
                    confidence:  1.0
                )
            } else {
                finalNutrition = nutrition
            }

            guard !Task.isCancelled else { return }

            // 2. Save.
            await homeViewModel.logFoodDirectly(
                nutrition: finalNutrition,
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

    // MARK: - Fallback

    /// Waits for the toast to be readable, then pops back to the mode picker
    /// with foodDescription pre-filled. Called directly (not via onChange) to
    /// avoid the unreliable dismiss()-inside-onChange pattern.
    private func scheduleApplyFallback(prefill: String) {
        lookupTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            applyFallback(prefill: prefill)
        }
    }

    private func applyFallback(prefill: String) {
        viewModel.foodDescription = prefill
        dismiss()
    }

    // MARK: - Sub-views

    private var resolvingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Looking up product…")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func confirmProductView(product: BarcodeProduct, nutrition: NutritionalInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Product header
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.productName)
                        .font(.r(.headline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    if let brand = product.brandName, !brand.isEmpty {
                        Text(brand)
                            .font(.r(.caption, .regular))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.top, 4)

                // Nutrition summary
                HStack(spacing: 0) {
                    nutritionCell(label: "Cal", value: "\(nutrition.calories)")
                    Divider().frame(height: 36)
                    nutritionCell(label: "Protein", value: String(format: "%.1fg", nutrition.protein))
                    Divider().frame(height: 36)
                    nutritionCell(label: "Carbs", value: String(format: "%.1fg", nutrition.carbs))
                    Divider().frame(height: 36)
                    nutritionCell(label: "Fat", value: String(format: "%.1fg", nutrition.fat))
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 8, y: 3)
                )

                // Quantity
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quantity")
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    HStack(spacing: 12) {
                        TextField("Amount", text: $confirmedQuantity)
                            .keyboardType(.decimalPad)
                            .font(.r(.body, .regular))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                            .frame(maxWidth: 100)
                        Picker("Unit", selection: $confirmedUnit) {
                            ForEach(QuantityUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Meal type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal Type")
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(MealType.allCases) { type in
                                let selected = viewModel.selectedMealType == type
                                Button {
                                    viewModel.selectedMealType = type
                                } label: {
                                    Text(type.rawValue.capitalized)
                                        .font(.r(.subheadline, selected ? .semibold : .regular))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule().fill(selected ? AppColors.primary : Color(.systemBackground))
                                        )
                                        .foregroundColor(selected ? AppColors.onPrimary : AppColors.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Eating triggers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Eating Triggers")
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(EatingTrigger.allCases) { trigger in
                            let selected = viewModel.selectedTriggers.contains(trigger)
                            Button {
                                if selected { viewModel.selectedTriggers.remove(trigger) }
                                else        { viewModel.selectedTriggers.insert(trigger) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(trigger.emoji)
                                    Text(trigger.displayName)
                                        .font(.r(.caption, .regular))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selected ? AppColors.primary.opacity(0.15) : Color(.systemBackground))
                                )
                                .foregroundColor(selected ? AppColors.primary : AppColors.textPrimary)
                                .overlay(Capsule().stroke(selected ? AppColors.primary : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Actions
                VStack(spacing: 12) {
                    Button {
                        HapticService.impact(.medium)
                        saveBarcodeMeal(product: product, nutrition: nutrition)
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Log This Food")
                                    .font(.r(.body, .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(AppColors.primary))
                        .foregroundColor(AppColors.onPrimary)
                    }
                    .disabled(isSaving)
                    .buttonStyle(.plain)

                    Button {
                        applyFallback(prefill: product.productName)
                    } label: {
                        Text("Edit Details")
                            .font(.r(.subheadline, .regular))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Confirm Food")
    }

    private func nutritionCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.r(.subheadline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text(label)
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

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

    // MARK: - Toast

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
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: toastMessage)
    }

    // MARK: - Toolbar

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
}
