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
    @State private var showHomeLayout               = false
    // Symptom state
    @State private var showSymptomCorrelation       = false
    @State private var selectedSymptomForCorrelation: String?
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var allSymptomEntries: [SymptomEntry]
    @StateObject private var correlationEngine      = SymptomCorrelationEngine()
    // Supplement state
    @Query private var allSupplements: [SupplementEntry]
    @Query(sort: \AdherenceLog.day, order: .reverse) private var allAdherenceLogs: [AdherenceLog]
    @StateObject private var supplementService       = SupplementService()
    // Daily check-in prompt toggle
    @State private var promptsEnabled: Bool = !UserDefaults.standard.bool(forKey: "wp.stress.dontAskAgain")
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

                    // ── Notifications & Prompts ──────────────
                    notificationsAndPromptsCard
                        .padding(.horizontal, 16)

                    // ── Home layout ─────────────────────
                    homeLayoutCard
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
            .navigationDestination(isPresented: $showHomeLayout) {
                HomeLayoutEditor(layout: Binding(
                    get: { (userGoalsList.first ?? UserGoals.defaults()).homeLayout },
                    set: { newValue in
                        let goals = UserGoals.current(in: modelContext)
                        goals.homeLayout = newValue
                        try? modelContext.save()
                    }
                ))
            }
            .navigationDestination(isPresented: $showSymptomCorrelation) {
                if let name = selectedSymptomForCorrelation {
                    SymptomCorrelationView(symptomName: name, engine: correlationEngine)
                }
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
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill).opacity(0.7))
                    .frame(width: 104, height: 104)

                Text(initials)
                    .font(.r(34, .heavy))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Text(profile.userName.isEmpty ? "Your Profile" : profile.userName)
                        .font(.r(.title2, .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Button {
                        HapticService.impact(.light)
                        editedName = profile.userName
                        activeSheet = .editName
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(.tertiarySystemFill).opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit name")
                }
                Text("Welcome back")
                    .font(.r(13, .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                heroStatTile(
                    icon: "scalemass.fill",
                    value: profile.weightKg > 0 ? profile.formattedWeight : "—",
                    label: "Weight"
                )
                heroStatTile(
                    icon: "ruler.fill",
                    value: profile.heightCm > 0 ? profile.formattedHeight : "—",
                    label: "Height"
                )
                heroStatTile(
                    icon: "heart.text.clipboard.fill",
                    value: bmi.map { String(format: "%.1f", $0) } ?? "—",
                    label: bmi != nil ? bmiCategory.label : "BMI"
                )
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(cardBackground())
    }

    private func heroStatTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 18)
            Text(value)
                .font(.r(15, .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.r(9, .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
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

    // MARK: - Shared Card Chrome

    private func cardHeader(
        eyebrow: String? = nil,
        title: String,
        icon: String,
        iconColor: Color = .primary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.6))
                )
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.r(10, .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.r(16, .bold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Body Metrics Card

    private var bodyMetricsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(eyebrow: "PERSONAL", title: "Body Profile", icon: "figure.stand")

            VStack(spacing: 0) {
                metricRow(
                    icon: "person.fill",
                    label: "Name",
                    value: profile.userName.isEmpty ? "Not set" : profile.userName,
                    showDivider: true
                ) {
                    editedName = profile.userName
                    activeSheet = .editName
                }
                metricRow(
                    icon: "scalemass.fill",
                    label: "Weight",
                    value: profile.formattedWeight,
                    showDivider: true
                ) {
                    editedWeight = profile.weightKg
                    editWeightUnit = profile.weightUnit
                    activeSheet = .editWeight
                }
                metricRow(
                    icon: "ruler.fill",
                    label: "Height",
                    value: profile.formattedHeight,
                    showDivider: false
                ) {
                    editedHeight = profile.heightCm
                    editHeightUnit = profile.heightUnit
                    activeSheet = .editHeight
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground())
    }

    private func metricRow(icon: String, label: String, value: String, showDivider: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.impact(.light)
            action()
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                    Text(label)
                        .font(.r(15, .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(value)
                        .font(.r(14, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)

                if showDivider {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35))
                        .frame(height: 0.5)
                        .padding(.leading, 42)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notifications & Prompts

    private var notificationsAndPromptsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(eyebrow: "REMINDERS", title: "Notifications", icon: "bell.badge.fill")

            Toggle(isOn: Binding(
                get: { promptsEnabled },
                set: { newValue in
                    promptsEnabled = newValue
                    UserDefaults.standard.set(!newValue, forKey: "wp.stress.dontAskAgain")
                    if newValue {
                        clearTodayManualAskedFlags()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily check-in prompts")
                        .font(.r(15, .semibold))
                        .foregroundStyle(.primary)
                    Text("Quick morning + evening overlays when sensors miss data")
                        .font(.r(12, .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground())
    }

    private func clearTodayManualAskedFlags() {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ManualDailyInput>(
            predicate: #Predicate { $0.day == today }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.morningAskedAt = nil
            existing.eveningAskedAt = nil
            try? modelContext.save()
        }
    }

    // MARK: - Home Layout

    private var homeLayoutCard: some View {
        Button {
            HapticService.impact(.light)
            showHomeLayout = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("CUSTOMIZE")
                        .font(.r(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text("Home Layout")
                        .font(.r(16, .bold))
                        .foregroundStyle(.primary)
                    let goals = userGoalsList.first ?? UserGoals.defaults()
                    let hidden = goals.homeLayout.hiddenCount
                    Text(hidden > 0 ? "\(hidden) card\(hidden == 1 ? "" : "s") hidden" : "All cards visible")
                        .font(.r(12, .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground())
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
                HStack {
                    cardHeader(eyebrow: "TARGETS", title: "Daily Goals", icon: "target")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    goalMiniCard(
                        icon: "flame.fill",
                        label: "Calories",
                        value: "\(currentGoals.calorieGoal)",
                        unit: "cal"
                    )
                    goalMiniCard(
                        icon: "drop.fill",
                        label: "Water",
                        value: "\(currentGoals.waterDailyCups)",
                        unit: "cups"
                    )
                    goalMiniCard(
                        icon: "figure.run",
                        label: "Workout",
                        value: "\(currentGoals.todayWorkoutGoal)",
                        unit: "min"
                    )
                    goalMiniCard(
                        icon: "moon.fill",
                        label: "Sleep",
                        value: String(format: "%.0f", currentGoals.sleepGoalHours),
                        unit: "hrs"
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground())
        }
        .buttonStyle(.plain)
    }

    private func goalMiniCard(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.r(22, .heavy))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.r(11, .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(label.uppercased())
                .font(.r(10, .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.5))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                cardHeader(eyebrow: "REGIMEN", title: "Health Regimen", icon: "pill.fill")
                Spacer()
                Button {
                    HapticService.impact(.light)
                    activeSheet = .addSupplement
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.r(12, .bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
                }
                .buttonStyle(.plain)
            }

            if allSupplements.isEmpty {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .addSupplement
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Add your first supplement")
                            .font(.r(14, .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            } else {
                let pct = supplementService.todayAdherencePercent(todayLogs: todayAdherenceLogs)
                let taken = todayAdherenceLogs.filter { $0.status == "taken" }.count
                let total = todayAdherenceLogs.count
                let streak = supplementService.currentStreak(allLogs: allAdherenceLogs)

                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(taken)")
                                .font(.r(28, .heavy))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                            Text("/ \(total)")
                                .font(.r(15, .semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text("doses today")
                                .font(.r(12, .medium))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if streak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(streak)d")
                                    .font(.r(13, .bold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)).frame(height: 7)
                            Capsule()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: max(geo.size.width * CGFloat(pct), 7), height: 7)
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground())
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                cardHeader(eyebrow: "TRACK", title: "Symptoms", icon: "heart.text.square.fill")
                Spacer()
                Button {
                    HapticService.impact(.light)
                    activeSheet = .symptomLog
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Log")
                            .font(.r(12, .bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
                }
                .buttonStyle(.plain)
            }

            if allSymptomEntries.isEmpty {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .symptomLog
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Log your first symptom")
                            .font(.r(14, .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(allSymptomEntries.prefix(3)) { entry in
                        HStack(spacing: 12) {
                            Text(entry.name)
                                .font(.r(14, .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            severityPill(entry.severity)
                            Text(relativeTimeString(for: entry.timestamp))
                                .font(.r(11, .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemFill).opacity(0.5))
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground())
    }

    private var symptomInsightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(eyebrow: "INSIGHTS", title: "Patterns", icon: "chart.line.uptrend.xyaxis")

            VStack(spacing: 8) {
                ForEach(topSymptomNames, id: \.self) { symptomName in
                    let corr = correlationEngine.correlations
                        .filter { $0.symptomName == symptomName && $0.isSignificant }
                        .max(by: { abs($0.spearmanR) < abs($1.spearmanR) })

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(symptomName)
                                .font(.r(14, .bold))
                                .foregroundStyle(.primary)
                            if let c = corr {
                                Text("\(c.interpretation) with \(c.factorName)")
                                    .font(.r(11, .medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Analysing patterns…")
                                    .font(.r(11, .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button {
                            HapticService.impact(.light)
                            selectedSymptomForCorrelation = symptomName
                            showSymptomCorrelation = true
                        } label: {
                            HStack(spacing: 3) {
                                Text("View")
                                    .font(.r(11, .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill).opacity(0.5))
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground())
    }

    private func severityPill(_ severity: Int) -> some View {
        let label: String = {
            switch severity {
            case 1...3: return "Low"
            case 4...6: return "Mod"
            default:    return "High"
            }
        }()
        return HStack(spacing: 4) {
            Text("\(severity)/10")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
    }

    private func relativeTimeString(for date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "yesterday"
    }

    // MARK: - App Info Footer

    private var appInfoFooter: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(.tertiarySystemFill).opacity(0.6)))

            VStack(spacing: 3) {
                Text("WellPlate")
                    .font(.r(15, .bold))
                    .foregroundStyle(.primary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) · Build \(build)")
                        .font(.r(11, .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func checkWidgetStatus() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async {
                if case .success(let infos) = result {
                    isWidgetInstalled = infos.contains {
                        $0.kind == "com.hariom.cadence.stressWidget"
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
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemFill).opacity(0.6))
                    )
                Text("Widget")
                    .font(.r(.headline, .semibold))
                Spacer()
                StatusBadge(isInstalled: isInstalled)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.r(14, .regular))
                    .foregroundStyle(.secondary)
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(Color(.systemBackground))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary)
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.primary)
                .frame(width: 6, height: 6)
                .opacity(isInstalled ? 1 : 0.35)
            Text(isInstalled ? "Active" : "Not added")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(.tertiarySystemFill).opacity(0.7)))
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
                    .fill(Color.primary)
                    .matchedGeometryEffect(id: "pill", in: namespace)
            }

            HStack(spacing: 5) {
                Image(systemName: size.systemImageName)
                    .font(.caption)
                Text(size.rawValue)
                    .font(.r(.subheadline, .medium))
            }
            .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.clear : Color(.tertiarySystemFill).opacity(0.6))
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

    private var fraction: Double { min(factor.contribution / factor.maxScore, 1.0) }
    private var barColor: Color {
        let ratio = min(max(factor.contribution / factor.maxScore, 0), 1)
        return Color(hue: 0.33 * (1.0 - ratio), saturation: 0.65, brightness: 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: factor.icon).font(.system(size: 7)).foregroundStyle(barColor)
                Text(factor.title).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(factor.contribution))/\(Int(factor.maxScore))").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
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
