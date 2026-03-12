import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Widget size selection

enum FoodWidgetSize: String, CaseIterable, Identifiable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .small:  return "square.fill"
        case .medium: return "rectangle.fill"
        case .large:  return "rectangle.portrait.fill"
        }
    }

    var description: String {
        switch self {
        case .small:  return "Calorie ring + quick add"
        case .medium: return "Ring + macro bars"
        case .large:  return "Full log + recent foods"
        }
    }

    /// Aspect ratio of the iOS widget for visual preview
    var aspectRatio: CGFloat {
        switch self {
        case .small:  return 1.0
        case .medium: return 2.12
        case .large:  return 1.0   // large is roughly square but taller — use 0.95
        }
    }

    var previewHeight: CGFloat {
        switch self {
        case .small:  return 130
        case .medium: return 130
        case .large:  return 260
        }
    }
}

// MARK: - Profile View

struct ProfilePlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userGoalsList: [UserGoals]
    @State private var selectedSize: FoodWidgetSize = .medium
    @State private var isWidgetInstalled            = false
    @State private var showInstructions             = false
    @State private var showGoals                    = false
    @State private var showEditName                 = false
    @State private var showEditWeight               = false
    @State private var showEditHeight               = false
    @State private var editedName                   = UserProfileManager.shared.userName
    @State private var editedWeight                 = UserProfileManager.shared.weightKg
    @State private var editedHeight                 = UserProfileManager.shared.heightCm
    @State private var editWeightUnit               = UserProfileManager.shared.weightUnit
    @Namespace private var sizeNamespace
    #if DEBUG
    @State private var mockModeEnabled: Bool = AppConfig.shared.mockMode
    @State private var hasGroqAPIKey: Bool = AppConfig.shared.hasGroqAPIKey
    #endif

    private let profile = UserProfileManager.shared

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Profile header ──────────────────────────
                    ProfileHeaderSection(
                        name: profile.userName,
                        statsText: "\(profile.formattedWeight) · \(profile.formattedHeight)"
                    )
                    .padding(.top, 12)

                    // ── Personal info card ─────────────────────
                    PersonalInfoCard(
                        name: profile.userName.isEmpty ? "Not set" : profile.userName,
                        weight: profile.formattedWeight,
                        height: profile.formattedHeight,
                        onNameTap: { showEditName = true },
                        onWeightTap: { showEditWeight = true },
                        onHeightTap: { showEditHeight = true }
                    )
                    .padding(.horizontal, 16)

                    // ── Goals card ─────────────────────────────
                    GoalsNavigationCard(goals: currentGoals) {
                        HapticService.impact(.light)
                        showGoals = true
                    }
                    .padding(.horizontal, 16)

                    // ── Widget setup card ────────────────────────────
                    WidgetSetupCard(
                        selectedSize:      $selectedSize,
                        isInstalled:       isWidgetInstalled,
                        namespace:         sizeNamespace,
                        onAddTapped:       { showInstructions = true }
                    )
                    .padding(.horizontal, 16)

                    // ── App info card ──────────────────────────
                    AppInfoCard()
                        .padding(.horizontal, 16)

                    #if DEBUG
                    NutritionSourceDebugCard(
                        isMockMode: $mockModeEnabled,
                        hasGroqAPIKey: hasGroqAPIKey
                    )
                    .padding(.horizontal, 16)
                    #endif
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                refreshProfileData()
                checkWidgetStatus()
                #if DEBUG
                refreshDebugNutritionState()
                #endif
            }
            #if DEBUG
            .onChange(of: mockModeEnabled) { _, newValue in
                AppConfig.shared.mockMode = newValue
                refreshDebugNutritionState()
            }
            #endif
            .navigationDestination(isPresented: $showGoals) {
                GoalsView(viewModel: GoalsViewModel(modelContext: modelContext))
            }
            .sheet(isPresented: $showInstructions) {
                WidgetInstructionsSheet(size: selectedSize)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Edit Name", isPresented: $showEditName) {
                TextField("Name", text: $editedName)
                Button("Save") {
                    profile.userName = editedName
                }
                Button("Cancel", role: .cancel) {
                    editedName = profile.userName
                }
            }
            .alert("Edit Weight (kg)", isPresented: $showEditWeight) {
                TextField("Weight", value: $editedWeight, format: .number)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    profile.weightKg = editedWeight
                }
                Button("Cancel", role: .cancel) {
                    editedWeight = profile.weightKg
                }
            }
            .alert("Edit Height (cm)", isPresented: $showEditHeight) {
                TextField("Height", value: $editedHeight, format: .number)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    profile.heightCm = editedHeight
                }
                Button("Cancel", role: .cancel) {
                    editedHeight = profile.heightCm
                }
            }
        }
    }

    private func checkWidgetStatus() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async {
                if case .success(let infos) = result {
                    isWidgetInstalled = infos.contains {
                        $0.kind == "com.hariom.wellplate.foodWidget"
                    }
                }
            }
        }
    }

    private func refreshProfileData() {
        editedName = profile.userName
        editedWeight = profile.weightKg
        editedHeight = profile.heightCm
        editWeightUnit = profile.weightUnit
    }

    #if DEBUG
    private func refreshDebugNutritionState() {
        mockModeEnabled = AppConfig.shared.mockMode
        hasGroqAPIKey = AppConfig.shared.hasGroqAPIKey
    }
    #endif
}

// MARK: - Profile Header

private struct ProfileHeaderSection: View {
    let name: String
    let statsText: String

    var body: some View {
        VStack(spacing: 10) {
            // Avatar with gradient ring
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [AppColors.brand, AppColors.brand.opacity(0.4), AppColors.brand],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.brand.opacity(0.75))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 4) {
                Text(name.isEmpty ? "Your Profile" : name)
                    .font(.r(.title3, .bold))
                    .foregroundStyle(.primary)

                if !statsText.isEmpty && statsText != "0 kg · 0 cm" {
                    Text(statsText)
                        .font(.r(.subheadline, .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Personal Info Card

private struct PersonalInfoCard: View {
    let name: String
    let weight: String
    let height: String
    let onNameTap: () -> Void
    let onWeightTap: () -> Void
    let onHeightTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.brand)
                Text("Personal Info")
                    .font(.r(.headline, .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ProfileInfoRow(icon: "person.fill", label: "Name", value: name, action: onNameTap)
            Divider().padding(.leading, 52)
            ProfileInfoRow(icon: "scalemass.fill", label: "Weight", value: weight, action: onWeightTap)
            Divider().padding(.leading, 52)
            ProfileInfoRow(icon: "ruler.fill", label: "Height", value: height, action: onHeightTap)
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 15, x: 0, y: 5)
        )
    }
}

private struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticService.impact(.light)
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.brand.opacity(0.7))
                    .frame(width: 24)

                Text(label)
                    .font(.r(.subheadline, .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(value)
                    .font(.r(.subheadline, .regular))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Info Card

private struct AppInfoCard: View {
    private let items: [(icon: String, title: String, detail: String?)] = [
        ("info.circle.fill", "About WellPlate", nil),
        ("lock.shield.fill", "Privacy Policy", nil),
        ("star.fill", "Rate Us", nil),
        ("gearshape.fill", "Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.brand)
                Text("App")
                    .font(.r(.headline, .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.brand.opacity(0.7))
                        .frame(width: 24)

                    Text(item.title)
                        .font(.r(.subheadline, .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    if let detail = item.detail {
                        Text(detail)
                            .font(.r(.subheadline, .regular))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < items.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 15, x: 0, y: 5)
        )
    }
}

#if DEBUG
private struct NutritionSourceDebugCard: View {
    @Binding var isMockMode: Bool
    let hasGroqAPIKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition Mode")
                .font(.r(.headline, .semibold))
                .foregroundStyle(.primary)

            Toggle("Use Mock Nutrition", isOn: $isMockMode)
                .font(.r(.subheadline, .semibold))
                .tint(AppColors.brand)

            if isMockMode {
                Text("Using local deterministic nutrition JSON responses.")
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hasGroqAPIKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasGroqAPIKey ? "GROQ_API_KEY detected in Secrets.plist" : "GROQ_API_KEY missing. Add WellPlate/Resources/Secrets.plist")
                        .font(.r(.caption, .medium))
                        .foregroundStyle(hasGroqAPIKey ? Color.green : Color.orange)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}
#endif

// MARK: - Widget Setup Card

private struct WidgetSetupCard: View {
    @Binding var selectedSize: FoodWidgetSize
    let isInstalled:  Bool
    let namespace:    Namespace.ID
    let onAddTapped:  () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // Header row
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.brand)
                Text("Widget")
                    .font(.r(.headline, .semibold))
                Spacer()
                // Status badge
                StatusBadge(isInstalled: isInstalled)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.r(14, .regular))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                // Size picker pills
                HStack(spacing: 8) {
                    ForEach(FoodWidgetSize.allCases) { size in
                        SizePill(
                            size:       size,
                            isSelected: selectedSize == size,
                            namespace:  namespace
                        )
                        .onTapGesture {
                            HapticService.selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                selectedSize = size
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Live widget preview
                WidgetPreview(size: selectedSize)
                    .transition(.opacity.combined(with: .scale(scale: 0.27)))
                    .animation(.spring(response: 0.38, dampingFraction: 0.8), value: selectedSize)
                    .id(selectedSize)

                // Add button
                Button(action: {
                    HapticService.impact(.medium)
                    onAddTapped()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isInstalled ? "checkmark.circle.fill" : "plus.circle.fill")
                        Text(isInstalled ? "Widget Active — Add Another" : "Add")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.brand.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 15, x: 0, y: 5)
        )
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isInstalled ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isInstalled ? "Active" : "Not added")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isInstalled ? .green : .orange)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isInstalled ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Size Pill

private struct SizePill: View {
    let size:       FoodWidgetSize
    let isSelected: Bool
    let namespace:  Namespace.ID

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.brand)
                    .matchedGeometryEffect(id: "pill", in: namespace)
            }

            HStack(spacing: 5) {
                Image(systemName: size.systemImageName)
                    .font(.caption)
                Text(size.rawValue)
                    .font(.r(.subheadline, .medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.clear : Color(.secondarySystemBackground))
            )
        }
    }
}

// MARK: - Widget Preview

/// Visual mock of the real widget — purely decorative so users know what to expect.
private struct WidgetPreview: View {
    let size: FoodWidgetSize

    private let mockData = WidgetFoodData(
        totalCalories: 1_243,
        totalProtein:  45,
        totalCarbs:    140,
        totalFat:      38,
        recentFoods: [
            WidgetFoodItem(id: UUID(), name: "Chicken Rice",  calories: 420),
            WidgetFoodItem(id: UUID(), name: "Greek Yogurt",  calories: 120),
            WidgetFoodItem(id: UUID(), name: "Oatmeal Bowl",  calories: 280)
        ],
        calorieGoal:  2000,
        proteinGoal:  60,
        carbsGoal:    225,
        fatGoal:      65,
        lastUpdated:  .now
    )

    var body: some View {
        Group {
            switch size {
            case .small:
                SmallPreview(data: mockData)
                    .frame(width: 130, height: 130)
                    .frame(maxWidth: .infinity, alignment: .center)

            case .medium:
                MediumPreview(data: mockData)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)

            case .large:
                LargePreview(data: mockData)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

// MARK: Widget preview bodies (mirror the real widget views)

private struct SmallPreview: View {
    let data: WidgetFoodData

    private var fraction: Double {
        min(Double(data.totalCalories) / Double(data.calorieGoal), 1.0)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), AppColors.brand.opacity(0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 0) {
                HStack {
                    Text("Today").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "fork.knife").font(.system(size: 9)).foregroundStyle(AppColors.brand)
                }
                Spacer(minLength: 4)
                // Mini ring
                ZStack {
                    Circle().stroke(AppColors.brand.opacity(0.18), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(AngularGradient(colors: [AppColors.brand, .pink],
                                               center: .center,
                                               startAngle: .degrees(-90),
                                               endAngle: .degrees(270)),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(data.totalCalories)").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("cal").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 62, height: 62)
                Spacer(minLength: 4)
                Text("\(data.calorieGoal - data.totalCalories) cal left")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 8)).foregroundStyle(AppColors.brand)
                    Text("Add Food").font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(AppColors.brand.opacity(0.12)))
            }
            .padding(10)
        }
    }
}

private struct MediumPreview: View {
    let data: WidgetFoodData

    private var fraction: Double { min(Double(data.totalCalories) / Double(data.calorieGoal), 1.0) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), AppColors.brand.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Today").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    ZStack {
                        Circle().stroke(AppColors.brand.opacity(0.18), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(AngularGradient(colors: [AppColors.brand, .pink],
                                                   center: .center,
                                                   startAngle: .degrees(-90),
                                                   endAngle: .degrees(270)),
                                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(data.totalCalories)").font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("cal").font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 60, height: 60)
                    HStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 7)).foregroundStyle(AppColors.brand)
                        Text("Add").font(.system(size: 8, weight: .semibold)).foregroundStyle(AppColors.brand)
                    }
                }
                .frame(width: 88)

                Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5).padding(.vertical, 8)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 7) {
                    MiniMacroBar(label: "Protein", value: data.totalProtein, goal: data.proteinGoal, color: .green)
                    MiniMacroBar(label: "Carbs",   value: data.totalCarbs,   goal: data.carbsGoal,   color: .blue)
                    MiniMacroBar(label: "Fat",     value: data.totalFat,     goal: data.fatGoal,     color: .orange)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

private struct LargePreview: View {
    let data: WidgetFoodData

    private var fraction: Double { min(Double(data.totalCalories) / Double(data.calorieGoal), 1.0) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), AppColors.brand.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife.circle.fill").font(.system(size: 12)).foregroundStyle(AppColors.brand)
                    Text("Nutrition").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text("Today").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // Calorie number
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(data.totalCalories)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.brand)
                    Text("/ \(data.calorieGoal) cal")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                // Calorie progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(AppColors.brand.opacity(0.15)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [AppColors.brand, .pink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * fraction, height: 6)
                    }
                }
                .frame(height: 6)
                .padding(.bottom, 10)

                Divider().padding(.bottom, 8)

                VStack(spacing: 6) {
                    MiniMacroBar(label: "Protein", value: data.totalProtein, goal: data.proteinGoal, color: .green)
                    MiniMacroBar(label: "Carbs",   value: data.totalCarbs,   goal: data.carbsGoal,   color: .blue)
                    MiniMacroBar(label: "Fat",     value: data.totalFat,     goal: data.fatGoal,     color: .orange)
                }
                .padding(.bottom, 10)

                Divider().padding(.bottom, 8)

                Text("Recent").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 5)
                VStack(spacing: 4) {
                    ForEach(data.recentFoods.prefix(3)) { food in
                        HStack(spacing: 5) {
                            Circle().fill(AppColors.brand.opacity(0.35)).frame(width: 5, height: 5)
                            Text(food.name).font(.system(size: 9)).lineLimit(1)
                            Spacer()
                            Text("\(food.calories)").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Food").fontWeight(.semibold)
                }
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(LinearGradient(colors: [AppColors.brand, .pink.opacity(0.85)],
                                                          startPoint: .leading, endPoint: .trailing)))
            }
            .padding(12)
        }
    }
}

private struct MiniMacroBar: View {
    let label: String
    let value: Double
    let goal:  Double
    let color: Color

    private var fraction: Double { min(value / max(goal, 1), 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))g").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Instructions Sheet

private struct WidgetInstructionsSheet: View {
    let size: FoodWidgetSize
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, color: Color, text: String)] = [
        ("hand.tap.fill",               .blue,   "Long-press any empty area on your Home Screen until icons jiggle."),
        ("plus.circle.fill",            .green,  "Tap the  +  button in the top-left corner."),
        ("magnifyingglass",             AppColors.brand, "Search for WellPlate in the widget gallery."),
        ("rectangle.3.group.fill",      .purple, "Swipe to choose your preferred size, then tap Add Widget."),
        ("arrow.up.left.and.arrow.down.right", .pink, "Drag the widget wherever you like and tap Done.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header illustration
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.brand)
                        Text("Add the Food Widget")
                            .font(.r(.title3, .bold))
                        Text("Follow these steps to add the \(size.rawValue) widget to your Home Screen.")
                            .font(.r(.subheadline, .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Step-by-step
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            InstructionRow(number: index + 1,
                                           icon: step.icon,
                                           color: step.color,
                                           text: step.text)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // Tip
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Tip: Once the widget is on your Home Screen, it refreshes automatically whenever you log food in the app.")
                            .font(.r(.footnote, .regular))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(0.08))
                    )
                }
                .padding(20)
                .padding(.bottom, 16)
            }
            .navigationTitle("How to Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct InstructionRow: View {
    let number: Int
    let icon:   String
    let color:  Color
    let text:   String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(number)")
                    .font(.r(.caption, .semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.r(.subheadline, .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
// MARK: - Goals Navigation Card

private struct GoalsNavigationCard: View {
    let goals: UserGoals
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.brand)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Goals")
                        .font(.r(.headline, .semibold))
                        .foregroundStyle(.primary)

                    Text(goalSummary)
                        .font(.r(.caption, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 15, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private var goalSummary: String {
        "\(goals.calorieGoal) cal · \(goals.waterDailyCups) cups · \(goals.todayWorkoutGoal) min"
    }
}

#Preview {
    ProfilePlaceholderView()
}
