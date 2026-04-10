import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Widget size selection

enum StressWidgetSize: String, CaseIterable, Identifiable {
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
        case .small:  return "Score ring + level"
        case .medium: return "Ring + top factor + vitals"
        case .large:  return "Full breakdown + 7-day trend"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .small:  return 1.0
        case .medium: return 2.12
        case .large:  return 1.0
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

// MARK: - ProfileSheet

enum ProfileSheet: Identifiable {
    case widgetInstructions
    case editName
    case editWeight
    case editHeight
    case symptomLog
    case addSupplement

    var id: String {
        switch self {
        case .widgetInstructions: return "widgetInstructions"
        case .editName:           return "editName"
        case .editWeight:         return "editWeight"
        case .editHeight:         return "editHeight"
        case .symptomLog:         return "symptomLog"
        case .addSupplement:      return "addSupplement"
        }
    }
}

// MARK: - Profile View

struct ProfilePlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userGoalsList: [UserGoals]
    @State private var selectedSize: StressWidgetSize = .medium
    @State private var isWidgetInstalled            = false
    @State private var activeSheet: ProfileSheet?
    @State private var showGoals                    = false
    // Symptom state
    @State private var showSymptomHistory           = false
    @State private var showSymptomCorrelation       = false
    @State private var selectedSymptomForCorrelation: String?
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var allSymptomEntries: [SymptomEntry]
    @StateObject private var correlationEngine      = SymptomCorrelationEngine()
    // Supplement state
    @State private var showSupplementList            = false
    @Query private var allSupplements: [SupplementEntry]
    @Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]
    @StateObject private var supplementService       = SupplementService()
    @State private var editedName                   = UserProfileManager.shared.userName
    @State private var editedWeight                 = UserProfileManager.shared.weightKg
    @State private var editedHeight                 = UserProfileManager.shared.heightCm
    @State private var editWeightUnit               = UserProfileManager.shared.weightUnit
    @State private var editHeightUnit               = UserProfileManager.shared.heightUnit
    @Namespace private var sizeNamespace
    #if DEBUG
    @State private var mockModeEnabled: Bool = AppConfig.shared.mockMode
    @State private var hasGroqAPIKey: Bool = AppConfig.shared.hasGroqAPIKey
    @State private var showMockModeRestartAlert = false
    #endif

    private let profile = UserProfileManager.shared

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    private var bmi: Double? {
        let h = profile.heightCm / 100
        guard h > 0, profile.weightKg > 0 else { return nil }
        return profile.weightKg / (h * h)
    }

    private var bmiCategory: (label: String, color: Color) {
        guard let bmi else { return ("--", .secondary) }
        switch bmi {
        case ..<18.5: return ("Underweight", .orange)
        case 18.5..<25: return ("Normal", AppColors.brand)
        case 25..<30: return ("Overweight", .orange)
        default: return ("Obese", .red)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ── Hero header ──────────────────────────
                    profileHero
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // ── Body metrics ─────────────────────────
                    bodyMetricsCard
                        .padding(.horizontal, 16)

                    // ── Goals snapshot ────────────────────────
                    goalsSnapshotCard
                        .padding(.horizontal, 16)

                    // ── Symptom tracking ─────────────────────
                    symptomTrackingCard
                        .padding(.horizontal, 16)

                    // ── Symptom insights ──────────────────────
                    if uniqueSymptomDays >= 7 {
                        symptomInsightsCard
                            .padding(.horizontal, 16)
                    }

                    // ── Health regimen (supplements) ─────────
                    supplementRegimenCard
                        .padding(.horizontal, 16)

                    // ── Widget setup ─────────────────────────
                    WidgetSetupCard(
                        selectedSize: $selectedSize,
                        isInstalled: isWidgetInstalled,
                        namespace: sizeNamespace,
                        onAddTapped: { activeSheet = .widgetInstructions }
                    )
                    .padding(.horizontal, 16)

                    #if DEBUG
                    MockModeDebugCard(
                        isMockMode: $mockModeEnabled,
                        hasGroqAPIKey: hasGroqAPIKey,
                        onToggle: { enabled in
                            AppConfig.shared.mockMode = enabled
                            if enabled {
                                MockDataInjector.inject(into: modelContext)
                            } else {
                                MockDataInjector.deleteAll(from: modelContext)
                            }
                            showMockModeRestartAlert = true
                        }
                    )
                    .padding(.horizontal, 16)
                    #endif

                    // ── App info footer ──────────────────────
                    appInfoFooter
                        .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                refreshProfileData()
                checkWidgetStatus()
                supplementService.createPendingLogs(context: modelContext, supplements: allSupplements)
                #if DEBUG
                refreshDebugNutritionState()
                #endif
            }
            #if DEBUG
            .alert("Restart Required", isPresented: $showMockModeRestartAlert) {
                Button("OK") { }
            } message: {
                Text(mockModeEnabled
                     ? "Mock mode enabled. Restart the app for all screens to use mock data."
                     : "Mock mode disabled. Restart the app to use real data.")
            }
            #endif
            .navigationDestination(isPresented: $showGoals) {
                GoalsView(viewModel: GoalsViewModel(modelContext: modelContext))
            }
            .navigationDestination(isPresented: $showSymptomHistory) {
                SymptomHistoryView()
            }
            .navigationDestination(isPresented: $showSymptomCorrelation) {
                if let name = selectedSymptomForCorrelation {
                    SymptomCorrelationView(symptomName: name, engine: correlationEngine)
                }
            }
            .navigationDestination(isPresented: $showSupplementList) {
                SupplementListView(service: supplementService)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .widgetInstructions:
                    WidgetInstructionsSheet(size: selectedSize)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                case .editName:
                    editNameSheet
                        .presentationDetents([.height(220)])
                        .presentationDragIndicator(.visible)
                case .editWeight:
                    editWeightSheet
                        .presentationDetents([.height(280)])
                        .presentationDragIndicator(.visible)
                case .editHeight:
                    editHeightSheet
                        .presentationDetents([.height(280)])
                        .presentationDragIndicator(.visible)
                case .symptomLog:
                    SymptomLogSheet()
                case .addSupplement:
                    AddSupplementSheet(service: supplementService)
                }
            }
        }
    }

    // MARK: - Hero Header

    private var profileHero: some View {
        VStack(spacing: 0) {
            // Gradient top area
            ZStack {
                // Background gradient
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.brand.opacity(0.15),
                                AppColors.brand.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 14) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.brand.opacity(0.2), AppColors.brand.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 88)

                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [AppColors.brand, AppColors.brand.opacity(0.3), AppColors.brand],
                                    center: .center
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 88, height: 88)

                        Text(initials)
                            .font(.r(28, .bold))
                            .foregroundStyle(AppColors.brand)
                    }

                    // Name
                    Text(profile.userName.isEmpty ? "Your Profile" : profile.userName)
                        .font(.r(.title2, .bold))
                        .foregroundStyle(.primary)

                    // Stats row
                    HStack(spacing: 16) {
                        if profile.weightKg > 0 {
                            profileStatPill(icon: "scalemass.fill", value: profile.formattedWeight)
                        }
                        if profile.heightCm > 0 {
                            profileStatPill(icon: "ruler.fill", value: profile.formattedHeight)
                        }
                        if let bmi {
                            profileStatPill(
                                icon: "heart.text.clipboard.fill",
                                value: "BMI \(String(format: "%.1f", bmi))",
                                tint: bmiCategory.color
                            )
                        }
                    }
                }
                .padding(.vertical, 24)
            }
        }
    }

    private func profileStatPill(icon: String, value: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.r(.caption, .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(.systemBackground).opacity(0.8))
        )
    }

    private var initials: String {
        let name = profile.userName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Body Metrics Card

    private var bodyMetricsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "figure.stand")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.brand)
                }
                Text("Body")
                    .font(.r(.headline, .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            // Name row
            metricRow(
                icon: "person.fill",
                label: "Name",
                value: profile.userName.isEmpty ? "Not set" : profile.userName,
                action: {
                    editedName = profile.userName
                    activeSheet = .editName
                }
            )

            Divider().padding(.leading, 56)

            // Weight row
            metricRow(
                icon: "scalemass.fill",
                label: "Weight",
                value: profile.formattedWeight,
                action: {
                    editedWeight = profile.weightKg
                    editWeightUnit = profile.weightUnit
                    activeSheet = .editWeight
                }
            )

            Divider().padding(.leading, 56)

            // Height row
            metricRow(
                icon: "ruler.fill",
                label: "Height",
                value: profile.formattedHeight,
                action: {
                    editedHeight = profile.heightCm
                    editHeightUnit = profile.heightUnit
                    activeSheet = .editHeight
                }
            )
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func metricRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.impact(.light)
            action()
        } label: {
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

    // MARK: - Goals Snapshot

    private var goalsSnapshotCard: some View {
        Button {
            HapticService.impact(.light)
            showGoals = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.brand.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "target")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.brand)
                    }
                    Text("Daily Goals")
                        .font(.r(.headline, .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // 2x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    goalMiniCard(
                        icon: "flame.fill",
                        label: "Calories",
                        value: "\(currentGoals.calorieGoal)",
                        unit: "cal",
                        color: .orange
                    )
                    goalMiniCard(
                        icon: "drop.fill",
                        label: "Water",
                        value: "\(currentGoals.waterDailyCups)",
                        unit: "cups",
                        color: .cyan
                    )
                    goalMiniCard(
                        icon: "figure.run",
                        label: "Workout",
                        value: "\(currentGoals.todayWorkoutGoal)",
                        unit: "min",
                        color: .green
                    )
                    goalMiniCard(
                        icon: "moon.fill",
                        label: "Sleep",
                        value: String(format: "%.0f", currentGoals.sleepGoalHours),
                        unit: "hrs",
                        color: .indigo
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 15, y: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private func goalMiniCard(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.r(.caption2, .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.r(.subheadline, .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(unit)
                        .font(.r(.caption2, .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Edit Sheets

    private var editNameSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Your name", text: $editedName)
                    .font(.r(.title3, .medium))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editedName = profile.userName
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.userName = editedName
                        activeSheet = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var editWeightSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Unit toggle
                Picker("Unit", selection: $editWeightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Value
                let displayValue: Binding<Double> = Binding(
                    get: {
                        editWeightUnit == .kg ? editedWeight : editedWeight * 2.20462
                    },
                    set: { newVal in
                        editedWeight = editWeightUnit == .kg ? newVal : newVal / 2.20462
                    }
                )

                TextField(
                    "Weight",
                    value: displayValue,
                    format: .number.precision(.fractionLength(1))
                )
                .font(.r(.title, .medium))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editedWeight = profile.weightKg
                        editWeightUnit = profile.weightUnit
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.weightKg = editedWeight
                        profile.weightUnit = editWeightUnit
                        activeSheet = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var editHeightSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Unit toggle
                Picker("Unit", selection: $editHeightUnit) {
                    ForEach(HeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Value
                let displayValue: Binding<Double> = Binding(
                    get: {
                        editHeightUnit == .cm ? editedHeight : editedHeight / 2.54
                    },
                    set: { newVal in
                        editedHeight = editHeightUnit == .cm ? newVal : newVal * 2.54
                    }
                )

                if editHeightUnit == .ft {
                    // Feet + inches display
                    let totalInches = editedHeight / 2.54
                    let feet = Int(totalInches) / 12
                    let inches = Int(totalInches) % 12
                    Text("\(feet)' \(inches)\"")
                        .font(.r(.title, .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }

                TextField(
                    editHeightUnit == .cm ? "Height (cm)" : "Height (inches)",
                    value: displayValue,
                    format: .number.precision(.fractionLength(editHeightUnit == .cm ? 0 : 1))
                )
                .font(.r(.title, .medium))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Edit Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editedHeight = profile.heightCm
                        editHeightUnit = profile.heightUnit
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.heightCm = editedHeight
                        profile.heightUnit = editHeightUnit
                        activeSheet = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Supplement Regimen Card

    private var todayAdherenceLogs: [AdherenceLog] {
        allAdherenceLogs.filter { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    private var supplementRegimenCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "pill.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.brand)
                Text("Health Regimen")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    HapticService.impact(.light)
                    activeSheet = .addSupplement
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppColors.brand)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(AppColors.brand.opacity(0.12)))
                }
            }

            if allSupplements.isEmpty {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .addSupplement
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(AppColors.brand)
                        Text("Add your first supplement")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColors.brand)
                    }
                }
            } else {
                let pct = supplementService.todayAdherencePercent(todayLogs: todayAdherenceLogs)
                let taken = todayAdherenceLogs.filter { $0.status == "taken" }.count
                let total = todayAdherenceLogs.count
                let streak = supplementService.currentStreak(allLogs: allAdherenceLogs)

                VStack(spacing: 8) {
                    HStack {
                        Text("\(taken)/\(total) doses taken")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        if streak > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("\(streak)d")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 6)
                            Capsule().fill(AppColors.brand).frame(width: geo.size.width * CGFloat(pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                Button {
                    HapticService.impact(.light)
                    showSupplementList = true
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppColors.brand)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Symptom Tracking Card

    private var uniqueSymptomDays: Int {
        Set(allSymptomEntries.map { $0.day }).count
    }

    private var topSymptomNames: [String] {
        let counts = Dictionary(grouping: allSymptomEntries, by: \.name)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        return Array(counts.prefix(3).map(\.key))
    }

    private var symptomTrackingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.brand)
                Text("Symptom Tracking")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    HapticService.impact(.light)
                    activeSheet = .symptomLog
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Log")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppColors.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppColors.brand.opacity(0.12)))
                }
            }

            // Recent entries
            if allSymptomEntries.isEmpty {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .symptomLog
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(AppColors.brand)
                        Text("Log your first symptom")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColors.brand)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(allSymptomEntries.prefix(3)) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            severityPill(entry.severity)
                            Text(relativeTimeString(for: entry.timestamp))
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    HapticService.impact(.light)
                    showSymptomHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Text("View History")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppColors.brand)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private var symptomInsightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.brand)
                Text("Symptom Insights")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(topSymptomNames, id: \.self) { symptomName in
                    // Show strongest correlation if available
                    let corr = correlationEngine.correlations
                        .filter { $0.symptomName == symptomName && $0.isSignificant }
                        .max(by: { abs($0.spearmanR) < abs($1.spearmanR) })

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(symptomName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            if let c = corr {
                                Text("\(c.interpretation) with \(c.factorName)")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Analysing patterns…")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            HapticService.impact(.light)
                            selectedSymptomForCorrelation = symptomName
                            showSymptomCorrelation = true
                        } label: {
                            Text("Details")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.brand)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func severityPill(_ severity: Int) -> some View {
        let color: Color = {
            switch severity {
            case 1...3: return Color(hue: 0.38, saturation: 0.58, brightness: 0.72)
            case 4...6: return Color(hue: 0.14, saturation: 0.72, brightness: 0.95)
            default:    return Color(hue: 0.00, saturation: 0.72, brightness: 0.85)
            }
        }()
        return Text("\(severity)/10")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func relativeTimeString(for date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "yesterday"
    }

    // MARK: - App Info Footer

    private var appInfoFooter: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.brand.opacity(0.3))

            Text("WellPlate")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("v\(version) (\(build))")
                    .font(.r(.caption2, .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private func checkWidgetStatus() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async {
                if case .success(let infos) = result {
                    isWidgetInstalled = infos.contains {
                        $0.kind == "com.hariom.wellplate.stressWidget"
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
        editHeightUnit = profile.heightUnit
    }

    #if DEBUG
    private func refreshDebugNutritionState() {
        mockModeEnabled = AppConfig.shared.mockMode
        hasGroqAPIKey = AppConfig.shared.hasGroqAPIKey
    }
    #endif
}

// MARK: - Widget Setup Card

private struct WidgetSetupCard: View {
    @Binding var selectedSize: StressWidgetSize
    let isInstalled:  Bool
    let namespace:    Namespace.ID
    let onAddTapped:  () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // Header row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.brand)
                }
                Text("Widget")
                    .font(.r(.headline, .semibold))
                Spacer()
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
                    ForEach(StressWidgetSize.allCases) { size in
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
                        Text(isInstalled ? "Widget Active — Add Another" : "Add Widget")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppColors.brand)
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
                .appShadow(radius: 15, y: 5)
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
    let size:       StressWidgetSize
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
                    .fill(isSelected ? Color.clear : Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

// MARK: - Widget Preview

private struct WidgetPreview: View {
    let size: StressWidgetSize

    private let mockData = WidgetStressData.placeholder

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

// MARK: Widget preview bodies (mirror the real stress widget views)

private struct SmallPreview: View {
    let data: WidgetStressData

    private var levelColor: Color { previewLevelColor(for: data.levelRaw) }
    private var fraction: Double { min(data.totalScore / 100.0, 1.0) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), levelColor.opacity(0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    Text("Stress").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "brain.head.profile.fill").font(.system(size: 9)).foregroundStyle(levelColor)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle().stroke(levelColor.opacity(0.18), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(levelColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(data.totalScore))").font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("/100").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 62, height: 62)
                Spacer(minLength: 4)
                Text(data.levelRaw)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(levelColor)
                Spacer(minLength: 6)
                Text(data.encouragement)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
        }
    }
}

private struct MediumPreview: View {
    let data: WidgetStressData

    private var levelColor: Color { previewLevelColor(for: data.levelRaw) }
    private var fraction: Double { min(data.totalScore / 100.0, 1.0) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), levelColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Stress").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    ZStack {
                        Circle().stroke(levelColor.opacity(0.18), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(levelColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(data.totalScore))").font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("/100").font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 60, height: 60)
                    Text(data.levelRaw)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(levelColor)
                }
                .frame(width: 88)

                Rectangle().fill(Color(.separator).opacity(0.4)).frame(width: 0.5).padding(.vertical, 8)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(data.factors.prefix(3), id: \.title) { factor in
                        MiniFactorBar(factor: factor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }
}

private struct LargePreview: View {
    let data: WidgetStressData

    private var levelColor: Color { previewLevelColor(for: data.levelRaw) }
    private var fraction: Double { min(data.totalScore / 100.0, 1.0) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), levelColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile.fill").font(.system(size: 12)).foregroundStyle(levelColor)
                    Text("Stress Level").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text("Today").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(levelColor.opacity(0.18), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(levelColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(data.totalScore))").font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("/100").font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(data.levelRaw)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(levelColor)
                        Text(data.encouragement)
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.bottom, 10)

                Divider().padding(.bottom, 8)

                VStack(spacing: 6) {
                    ForEach(data.factors, id: \.title) { factor in
                        MiniFactorBar(factor: factor)
                    }
                }
                .padding(.bottom, 10)

                Divider().padding(.bottom, 8)

                Text("7-Day Trend").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
                    .textCase(.uppercase).padding(.bottom, 4)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(data.weeklyScores, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(levelColor.opacity(0.6))
                            .frame(height: max(CGFloat(day.score ?? 0) / 100.0 * 24, 2))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 28)

                Spacer(minLength: 4)
            }
            .padding(12)
        }
    }
}

private struct MiniFactorBar: View {
    let factor: WidgetStressFactor

    private var fraction: Double { min(factor.contribution / 25.0, 1.0) }
    private var barColor: Color {
        let ratio = min(max(factor.contribution / 25.0, 0), 1)
        return Color(hue: 0.33 * (1.0 - ratio), saturation: 0.65, brightness: 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: factor.icon).font(.system(size: 7)).foregroundStyle(barColor)
                Text(factor.title).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(factor.contribution))/25").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(barColor.opacity(0.2)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(barColor)
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

private func previewLevelColor(for levelRaw: String) -> Color {
    switch levelRaw {
    case "Excellent":  return Color(hue: 0.33, saturation: 0.60, brightness: 0.72)
    case "Good":       return Color(hue: 0.27, saturation: 0.55, brightness: 0.70)
    case "Moderate":   return Color(hue: 0.12, saturation: 0.55, brightness: 0.72)
    case "High":       return Color(hue: 0.06, saturation: 0.60, brightness: 0.70)
    case "Very High":  return Color(hue: 0.01, saturation: 0.65, brightness: 0.65)
    default:           return Color.gray
    }
}

// MARK: - Instructions Sheet

private struct WidgetInstructionsSheet: View {
    let size: StressWidgetSize
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

                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.brand)
                        Text("Add the Stress Widget")
                            .font(.r(.title3, .bold))
                        Text("Follow these steps to add the \(size.rawValue) widget to your Home Screen.")
                            .font(.r(.subheadline, .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

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
                            .fill(Color(.secondarySystemGroupedBackground))
                    )

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

#if DEBUG
#endif

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SymptomEntry.self, UserGoals.self, SupplementEntry.self, AdherenceLog.self, configurations: config)
    return ProfilePlaceholderView()
        .modelContainer(container)
}
