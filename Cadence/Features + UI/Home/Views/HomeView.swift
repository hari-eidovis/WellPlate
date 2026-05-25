import SwiftUI
import SwiftData

// MARK: - HomeSheet

enum HomeSheet: Identifiable, Equatable {
    case coffeeTypePicker
    case journalEntry
    case symptomLog
    case customizeCard(HomeCardID)
    case changeMood

    var id: String {
        switch self {
        case .coffeeTypePicker: return "coffeeTypePicker"
        case .journalEntry: return "journalEntry"
        case .symptomLog: return "symptomLog"
        case .customizeCard(let card): return "customizeCard_\(card.rawValue)"
        case .changeMood: return "changeMood"
        }
    }
}

// MARK: - HomeView
// Redesigned dashboard: header, wellness rings, quick log, mood check-in,
// hydration, activity, and stress insight sections.

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var userGoalsList: [UserGoals]
    @Query(sort: \FoodLogEntry.createdAt, order: .forward) private var allFoodLogs: [FoodLogEntry]
    @Query private var allWellnessDayLogs: [WellnessDayLog]
    @Query private var allJournalEntries: [JournalEntry]
    @Query(sort: \StressReading.timestamp) private var allStressReadings: [StressReading]

    @Binding var selectedTab: Int
    /// Shared instance from MainTabView. HomeView observes `totalScore` /
    /// `stressLevel` directly so the sparkline card stays in sync with the
    /// Stress tab even when the user is logging mood/water/food/etc.
    @ObservedObject var stressViewModel: StressViewModel

    // MARK: - State

    @State private var selectedMood: MoodOption?
    @State private var hasLoggedMoodToday = false
    @State private var healthSuggestedMood: MoodOption?
    @State private var hydrationGlasses: Int = 0
    @State private var coffeeCups: Int = 0
    @State private var showLogMeal = false
    @State private var showWaterDetail = false
    @State private var showCoffeeDetail = false
    @State private var showWellnessCalendar = false
    // TODO: F-next — re-home WellnessCalendarView to Profile tab.
    // The calendar button has been removed from the header as of the Home Screen UX Update.
    // This state and its .navigationDestination are kept as dead code to avoid touching the
    // navigation chain. Remove both when the Profile tab relocation is implemented.
    @State private var activeSheet: HomeSheet?
    @State private var showCoffeeWaterAlert = false
    /// Guards against onChange(of: coffeeCups) firing during initial state restoration.
    @State private var hasCoffeeStateLoaded = false
    /// Handoff variable for the sheet→alert race-safe pattern.
    /// Set by the picker closure, read by onChange(of: activeSheet).
    @State private var pendingCoffeeType: CoffeeType? = nil
    @State private var showInsightsHub = false
    @State private var showBurnView = false
    // Layout customisation
    @State private var undoState: (card: HomeCardID, previousLayout: HomeLayoutConfig, id: UUID)? = nil
    @State private var showLayoutEditor = false
    // Journal state
    @State private var journalText: String = ""
    @State private var hasJournaledToday = false
    @StateObject private var foodJournalViewModel = HomeViewModel()
    @StateObject private var insightEngine = InsightEngine()
    @StateObject private var journalPromptService = JournalPromptService()

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    private var layout: HomeLayoutConfig {
        currentGoals.homeLayout
    }

    /// Safe writable accessor — always returns a context-tracked UserGoals instance.
    private var writableGoals: UserGoals {
        UserGoals.current(in: modelContext)
    }

    private var layoutBinding: Binding<HomeLayoutConfig> {
        Binding(
            get: { currentGoals.homeLayout },
            set: { newValue in
                writableGoals.homeLayout = newValue
                try? modelContext.save()
            }
        )
    }

    /// Visible cards filtered by both layout config AND runtime conditions.
    private var effectiveVisibleCards: [HomeCardID] {
        layout.visibleCards.filter { card in
            switch card {
            case .moodCheckIn:
                return !hasLoggedMoodToday
            case .journalReflection:
                return hasLoggedMoodToday && !hasJournaledToday
            default:
                return true
            }
        }
    }

    private var todayJournalEntry: JournalEntry? {
        allJournalEntries.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    // MARK: - Card Dispatch

    @ViewBuilder
    private func cardView(for card: HomeCardID) -> some View {
        switch card {
        case .dailyInsight:
            DailyInsightCard(
                card: insightEngine.dailyInsight,
                isGenerating: insightEngine.isGenerating,
                actionLabel: insightActionLabel,
                actionIcon: insightActionIcon,
                onTap: { showInsightsHub = true },
                onAction: insightQuickAction,
                onDismiss: { hideCard(.dailyInsight) }
            )
            .padding(.horizontal, 16)

        case .wellnessRings:
            WellnessRingsCard(
                rings: filteredWellnessRings,
                completionPercent: wellnessCompletionPercent,
                deltaValues: wellnessDeltaValues,
                onRingTap: { destination in
                    switch destination {
                    case .calories: showLogMeal = true
                    case .water:    showWaterDetail = true
                    case .exercise: showBurnView = true
                    case .stress:   selectedTab = 1
                    }
                }
            )
            .padding(.horizontal, 16)

        case .stressSparkline:
            StressSparklineStrip(
                readings: todayStressReadings,
                stressLevel: todayWellnessLog?.stressLevel,
                scoreDelta: stressScoreDelta,
                liveScore: liveStressScore,
                onTap: { selectedTab = 1 }
            )
            .padding(.horizontal, 16)

        case .moodCheckIn:
            MoodCheckInCard(selectedMood: $selectedMood, suggestion: healthSuggestedMood)
                .padding(.horizontal, 16)

        case .journalReflection:
            JournalReflectionCard(
                prompt: journalPromptService.currentPrompt,
                promptCategory: journalPromptService.promptCategory,
                onWriteMore: { activeSheet = .journalEntry },
                isGeneratingPrompt: journalPromptService.isGenerating
            )
            .padding(.horizontal, 16)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))

        case .quickStats:
            QuickStatsRow(
                hydrationGlasses: $hydrationGlasses,
                hydrationGoal: currentGoals.waterDailyCups,
                coffeeCups: $coffeeCups,
                coffeeGoal: currentGoals.coffeeDailyCups,
                coffeeType: todayWellnessLog?.resolvedCoffeeType,
                yesterdayWater: foodJournalViewModel.yesterdayStats.water,
                yesterdayCoffee: foodJournalViewModel.yesterdayStats.coffee,
                cupSizeML: currentGoals.waterCupSizeML,
                onWaterTap: { showWaterDetail = true },
                onCoffeeTap: { showCoffeeDetail = true },
                onCoffeeLog: { activeSheet = .coffeeTypePicker },
                showWater: layout.isElementVisible(.waterTile, in: .quickStats),
                showCoffee: layout.isElementVisible(.coffeeTile, in: .quickStats)
            )
        }
    }

    /// Wellness rings filtered by layout visibility.
    private var filteredWellnessRings: [WellnessRingItem] {
        let elementToDestination: [HomeElementID: WellnessRingDestination] = [
            .calorieRing: .calories,
            .waterRing: .water,
            .exerciseRing: .exercise,
            .stressRing: .stress
        ]
        let visibleDestinations = Set(
            layout.visibleElements(for: .wellnessRings)
                .compactMap { elementToDestination[$0] }
        )
        return wellnessRings.filter { visibleDestinations.contains($0.destination) }
    }

    // MARK: - Layout Actions

    private func hideCard(_ card: HomeCardID) {
        let previousLayout = layout
        let undoID = UUID()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            var updated = layout
            updated.hideCard(card)
            writableGoals.homeLayout = updated
            try? modelContext.save()
        }
        HapticService.impact(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            undoState = (card: card, previousLayout: previousLayout, id: undoID)
        }
    }

    private func undoHide() {
        guard let undo = undoState else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            writableGoals.homeLayout = undo.previousLayout
            try? modelContext.save()
            undoState = nil
        }
        HapticService.impact(.light)
    }

    private func dismissUndo(id: UUID) {
        guard undoState?.id == id else { return }
        undoState = nil
    }

    /// One-time migration: if @AppStorage("hideInsightCard") was true,
    /// transfer that state into HomeLayoutConfig and remove the key.
    private func migrateHideInsightCardIfNeeded() {
        let key = "hideInsightCard"
        guard UserDefaults.standard.bool(forKey: key) else { return }
        var updatedLayout = writableGoals.homeLayout
        updatedLayout.hideCard(.dailyInsight)
        writableGoals.homeLayout = updatedLayout
        try? modelContext.save()
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Home Scroll Content

    private var homeScrollContent: some View {
        LazyVStack(spacing: 16) {
            homeHeader
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ForEach(effectiveVisibleCards, id: \.self) { card in
                cardView(for: card)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .homeCardMenu(
                        card: card,
                        layout: layoutBinding,
                        hasHiddenCards: layout.hiddenCount > 0,
                        onCustomize: card.hasSubElements ? {
                            activeSheet = .customizeCard(card)
                        } : nil,
                        onShowLayoutEditor: { showLayoutEditor = true },
                        onHide: { hideCard($0) }
                    )
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: effectiveVisibleCards)

            if layout.hiddenCount > 0 {
                HiddenCardsPill(count: layout.hiddenCount) {
                    showLayoutEditor = true
                }
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Contextual Action Bar

    private var contextualActionBar: some View {
        ContextualActionBar(
            state: contextualBarState,
            onLogMeal: { showLogMeal = true },
//            onAddWater: {
//                guard hydrationGlasses < currentGoals.waterDailyCups else { return }
//                hydrationGlasses += 1
//            },
            onStressTab: { selectedTab = 1 },
            onSeeInsight: {
                showInsightsHub = true
            },
            onLogSymptom: {
                HapticService.impact(.light)
                activeSheet = .symptomLog
            }
        )
        .padding(.bottom, 4)
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private var navigationDestinations: some View {
        Color.clear
            .navigationDestination(isPresented: $showLogMeal) {
                FoodJournalView(viewModel: foodJournalViewModel)
            }
            .navigationDestination(isPresented: $showWaterDetail) {
                WaterDetailView(
                    totalGlasses: currentGoals.waterDailyCups,
                    cupSizeML: currentGoals.waterCupSizeML
                )
            }
            .navigationDestination(isPresented: $showCoffeeDetail) {
                CoffeeDetailView(
                    totalCups: currentGoals.coffeeDailyCups,
                    coffeeType: todayWellnessLog?.resolvedCoffeeType
                )
            }
            .navigationDestination(isPresented: $showBurnView) {
                BurnView()
            }
            .navigationDestination(isPresented: $showWellnessCalendar) {
                WellnessCalendarView()
            }
            .navigationDestination(isPresented: $showInsightsHub) {
                InsightsHubView(engine: insightEngine)
            }
            .navigationDestination(isPresented: $showLayoutEditor) {
                HomeLayoutEditor(layout: layoutBinding)
            }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: HomeSheet) -> some View {
        switch sheet {
        case .coffeeTypePicker:
            CoffeeTypePickerSheet { type in
                pendingCoffeeType = type
                activeSheet = nil
            }
        case .journalEntry:
            JournalEntryView(
                mood: selectedMood,
                stressLevel: todayWellnessLog?.stressLevel,
                entryText: $journalText,
                prompt: journalPromptService.currentPrompt,
                promptService: journalPromptService,
                onSave: saveJournalEntry
            )
        case .symptomLog:
            SymptomLogSheet()
        case .customizeCard(let card):
            CardCustomizeSheet(card: card, layout: layoutBinding)
        case .changeMood:
            MoodCheckInSheet(onSaved: { stressViewModel.recompute(reason: .manualMood) })
        }
    }

    // MARK: - Undo Toast Overlay

    @ViewBuilder
    private var undoToastOverlay: some View {
        if let undo = undoState {
            VStack {
                Spacer()
                UndoToast(
                    message: "\(undo.card.displayName) hidden",
                    dismissID: undo.id,
                    onUndo: { undoHide() },
                    onDismiss: { id in dismissUndo(id: id) }
                )
                .padding(.bottom, 80)
            }
        }
    }

    // MARK: - Navigation Content

    private var navigationContent: some View {
        ZStack {
          ScrollView {
            homeScrollContent
          }
          undoToastOverlay
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let hAmt = value.translation.width
                    let vAmt = abs(value.translation.height)
                    if hAmt > 80 && hAmt > vAmt * 1.5 {
                        HapticService.impact(.medium)
                        showLogMeal = true
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            contextualActionBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationDestination(isPresented: $showLogMeal) {
            FoodJournalView(viewModel: foodJournalViewModel)
        }
        .navigationDestination(isPresented: $showWaterDetail) {
            WaterDetailView(totalGlasses: currentGoals.waterDailyCups, cupSizeML: currentGoals.waterCupSizeML)
        }
        .navigationDestination(isPresented: $showCoffeeDetail) {
            CoffeeDetailView(totalCups: currentGoals.coffeeDailyCups, coffeeType: todayWellnessLog?.resolvedCoffeeType)
        }
        .navigationDestination(isPresented: $showBurnView) { BurnView() }
        .navigationDestination(isPresented: $showWellnessCalendar) { WellnessCalendarView() }
        .navigationDestination(isPresented: $showInsightsHub) { InsightsHubView(engine: insightEngine) }
        .navigationDestination(isPresented: $showLayoutEditor) { HomeLayoutEditor(layout: layoutBinding) }
        .navigationBarHidden(true)
    }

    // MARK: - Body

    var body: some View {
        bodyPart1
            .onChange(of: hasLoggedMoodToday) { _, logged in
                if logged {
                    Task {
                        await journalPromptService.generatePrompt(
                            mood: selectedMood,
                            stressLevel: todayWellnessLog?.stressLevel
                        )
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshTodayMoodState()
                refreshTodayHydrationState()
                refreshTodayCoffeeState()
                refreshTodayJournalState()
                refreshTodayActivityFromHealthKit()
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            .alert("Stay Hydrated!", isPresented: $showCoffeeWaterAlert) {
                Button("Log Water") {
                    if hydrationGlasses < currentGoals.waterDailyCups {
                        hydrationGlasses += 1
                    }
                }
                Button("Skip", role: .cancel) {}
            } message: {
                Text("Coffee can cause dehydration. Want to log a glass of water too?")
            }
    }

    private var bodyPart1: some View {
        NavigationStack {
            navigationContent
        }
        .onAppear {
            foodJournalViewModel.bindContext(modelContext)
            insightEngine.bindContext(modelContext)
            migrateHideInsightCardIfNeeded()
            Task { await insightEngine.generateInsights() }
            refreshTodayMoodState()
            refreshTodayHydrationState()
            refreshTodayCoffeeState()
            hasCoffeeStateLoaded = true
            refreshTodayJournalState()
            foodJournalViewModel.loadYesterdayStats()
            refreshTodayActivityFromHealthKit()
        }
        .onChange(of: showWaterDetail) { _, showing in
            if !showing { refreshTodayHydrationState() }
        }
        .onChange(of: showCoffeeDetail) { _, showing in
            if !showing { refreshTodayCoffeeState() }
        }
        .onChange(of: selectedMood) { _, mood in
            guard let mood else { return }
            logMoodForTodayIfNeeded(mood)
        }
        .onChange(of: hydrationGlasses) { _, cups in
            updateHydrationForToday(cups)
        }
        .onChange(of: coffeeCups) { _, newCups in
            guard hasCoffeeStateLoaded else { return }
            updateCoffeeForToday(cups: newCups, type: todayWellnessLog?.resolvedCoffeeType)
        }
        .onChange(of: activeSheet) { old, new in
            if old == .coffeeTypePicker && new == nil {
                if let type = pendingCoffeeType {
                    pendingCoffeeType = nil
                    coffeeCups += 1
                    updateCoffeeForToday(cups: coffeeCups, type: type)
                    showCoffeeWaterAlert = true
                }
            }
            if old == .journalEntry && new == nil {
                refreshTodayJournalState()
            }
            if old == .changeMood && new == nil {
                // Sheet's `onSaved` already triggered recompute(); just refresh
                // the badge emoji from the persisted log here.
                refreshTodayMoodState()
            }
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)

                if userName.isEmpty {
                    Text(greetingPrefix)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    HStack(spacing: 4) {
                        Text("\(greetingPrefix),")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(userName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .background(alignment: .top) {
                                LottieLoopView(name: "hiddencat")
                                    .frame(width: 60, height: 60)
                                    .offset(y: -60)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                    }
                }
            }

            Spacer()

            // AI Insights button
            Button {
                HapticService.impact(.light)
                showInsightsHub = true
            } label: {
                headerIcon("sparkles")
            }
            .buttonStyle(.plain)

            // Mood badge — visible only when mood is logged today (38pt to match icons)
            if hasLoggedMoodToday, let mood = selectedMood {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .changeMood
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 38, height: 38)
                            .shadow(color: mood.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)

                        Circle()
                            .stroke(mood.accentColor.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 38, height: 38)

                        Text(mood.emoji)
                            .font(.system(size: 19))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change today's mood")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header Icon Helper (38pt — 2 icons + optional mood badge)

    @ViewBuilder
    private func headerIcon(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.brand.opacity(0.65), AppColors.brand.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .shadow(color: AppColors.brand.opacity(0.12), radius: 6, x: 0, y: 3)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Wellness Rings Data

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayWellnessLog: WellnessDayLog? {
        allWellnessDayLogs.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    // MARK: - Stress Sparkline Data

    private var todayStressReadings: [StressReading] {
        allStressReadings.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var yesterdayLastStressReading: StressReading? {
        allStressReadings.last { Calendar.current.isDateInYesterday($0.timestamp) }
    }

    private var stressScoreDelta: Int? {
        guard let today = todayStressReadings.last,
              let yesterday = yesterdayLastStressReading else { return nil }
        let delta = Int(today.score.rounded()) - Int(yesterday.score.rounded())
        return delta == 0 ? nil : delta
    }

    /// Live score from the shared StressViewModel. Nil until the first
    /// successful `loadData()` so the card can fall back to the latest
    /// persisted reading instead of showing 0.
    private var liveStressScore: Double? {
        guard stressViewModel.isAuthorized || stressViewModel.usesMockData else { return nil }
        guard stressViewModel.totalScore > 0 else { return nil }
        return stressViewModel.totalScore
    }

    private var todayCalories: Int {
        allFoodLogs.filter { $0.day == todayStart }.reduce(0) { $0 + $1.calories }
    }

    /// Today's food log entries, filtered from the `@Query` result.
    /// Used by MealLogCard and contextualBarState.
    // RESOLVED: M7 — using $0.day == todayStart for consistency with the existing todayCalories
    // pattern in HomeView. Direct equality avoids a Calendar call on every element.
    private var todayFoodLogs: [FoodLogEntry] {
        allFoodLogs.filter { $0.day == todayStart }
    }

    /// Pure computed property. Evaluated on every body call.
    /// Priority: goalsCelebration > stressActionable > waterBehindPace > logNextMeal > defaultActions
    private var contextualBarState: ContextualBarState {
        // 1. Goals celebration
        if wellnessCompletionPercent >= 100 {
            return .goalsCelebration
        }

        // 2. Stress actionable
        if let level = effectiveStressLevel?.lowercased(),
           level == "high" || level == "very high" {
            return .stressActionable(level: effectiveStressLevel ?? "High")
        }

        // 3. Log next meal
        if let mealLabel = nextMealLabel() {
            return .logNextMeal(mealLabel: mealLabel)
        }

        // 5. Default
        return .defaultActions
    }

    // MARK: - Insight Quick Action

    /// Label for the nudge button on the daily insight card, based on insight domain.
    private var insightActionLabel: String? {
        guard let domain = insightEngine.dailyInsight?.domain else { return nil }
        switch domain {
        case .hydration: return "Add"
        case .nutrition: return "Log"
        case .stress:    return "Breathe"
        case .caffeine:  return "Log"
        default:         return nil
        }
    }

    /// SF Symbol for the nudge button on the daily insight card.
    private var insightActionIcon: String? {
        guard let domain = insightEngine.dailyInsight?.domain else { return nil }
        switch domain {
        case .hydration: return "plus"
        case .nutrition: return "plus"
        case .stress:    return "wind"
        case .caffeine:  return "cup.and.saucer.fill"
        default:         return nil
        }
    }

    /// Quick action closure for the nudge button, domain-specific.
    private var insightQuickAction: (() -> Void)? {
        guard let domain = insightEngine.dailyInsight?.domain else { return nil }
        switch domain {
        case .hydration:
            return {
                guard hydrationGlasses < currentGoals.waterDailyCups else { return }
                hydrationGlasses += 1
            }
        case .nutrition:
            return { showLogMeal = true }
        case .stress:
            return { selectedTab = 1 }
        case .caffeine:
            return {
                let wasFirst = coffeeCups == 0 && todayWellnessLog?.coffeeType == nil
                coffeeCups += 1
                if wasFirst {
                    activeSheet = .coffeeTypePicker
                } else {
                    showCoffeeWaterAlert = true
                }
            }
        default:
            return nil
        }
    }

    /// Returns how many cups behind the user is vs. expected pace (wake 07:00, sleep 22:00).
    private func expectedCupsDeficit() -> Int {
        let target = currentGoals.waterDailyCups
        guard target > 0 else { return 0 }

        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let wakeComponents = DateComponents(hour: 7, minute: 0)
        let sleepComponents = DateComponents(hour: 22, minute: 0)
        guard let wake = cal.date(byAdding: wakeComponents, to: dayStart),
              let sleep = cal.date(byAdding: sleepComponents, to: dayStart) else { return 0 }

        let total = sleep.timeIntervalSince(wake)
        guard total > 0 else { return 0 }
        let elapsed = max(0, min(now.timeIntervalSince(wake), total))
        let fraction = elapsed / total
        let expected = Int(ceil(fraction * Double(target)))
        let behind = expected - hydrationGlasses
        return max(0, behind)
    }

    /// Returns the contextual meal label based on time-of-day and today's logs.
    private func nextMealLabel() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())

        // Breakfast window: 05:00–10:59
        if (5..<11).contains(hour) {
            let hasBreakfast = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (5..<11).contains(h)
            }
            return hasBreakfast ? nil : "Breakfast"
        }

        // Lunch window: 11:00–13:59
        if (11..<14).contains(hour) {
            let hasLunch = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (11..<14).contains(h)
            }
            return hasLunch ? nil : "Lunch"
        }

        // Dinner window: 17:00–20:59
        if (17..<21).contains(hour) {
            let hasDinner = todayFoodLogs.contains {
                let h = Calendar.current.component(.hour, from: $0.createdAt)
                return (17..<21).contains(h)
            }
            return hasDinner ? nil : "Dinner"
        }

        return nil
    }

    /// Resolves today's stress level from the first available source:
    ///  1. Persisted `WellnessDayLog.stressLevel` (set by StressViewModel after a load).
    ///  2. The shared StressViewModel's live `totalScore` (Stress tab has run).
    ///  3. The most recent `StressReading` for today (mock injector seeds these,
    ///     so the ring still shows a value even when MockDataInjector skipped
    ///     today's WellnessDayLog because one already existed).
    private var effectiveStressLevel: String? {
        if let level = todayWellnessLog?.stressLevel, !level.isEmpty {
            return level
        }
        if let score = liveStressScore {
            return StressLevel(score: score).label
        }
        if let latest = todayStressReadings.last {
            return latest.levelLabel
        }
        return nil
    }

    private var wellnessRings: [WellnessRingItem] {
        let cupGoal = currentGoals.waterDailyCups
        let energyGoal = currentGoals.activeEnergyGoalKcal
        let calorieGoal = currentGoals.calorieGoal
        let log = todayWellnessLog
        let stressLevel = effectiveStressLevel

        let calorieProgress: CGFloat = calorieGoal > 0
            ? min(1.0, CGFloat(todayCalories) / CGFloat(calorieGoal))
            : 0
        let waterProgress = cupGoal > 0 ? min(1.0, CGFloat(hydrationGlasses) / CGFloat(cupGoal)) : 0
        let burnedKcal = log?.caloriesBurned ?? 0
        let exerciseProgress: CGFloat = energyGoal > 0
            ? min(1.0, CGFloat(burnedKcal) / CGFloat(energyGoal))
            : 0
        let stressProgress = stressProgressFromLevel(stressLevel)

        return [
            WellnessRingItem(
                label: "Calories",
                sublabel: "/ \(calorieGoal)",
                value: "\(todayCalories)",
                progress: calorieProgress,
                color: AppColors.brand,
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .calories
            ),
            WellnessRingItem(
                label: "Water",
                sublabel: "/ \(cupGoal) cups",
                value: "\(hydrationGlasses)",
                progress: waterProgress,
                color: Color(hue: 0.58, saturation: 0.68, brightness: 0.82),
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .water
            ),
            WellnessRingItem(
                label: "Exercise",
                sublabel: "/ \(energyGoal) kcal",
                value: "\(burnedKcal)",
                progress: exerciseProgress,
                color: Color(hue: 0.50, saturation: 0.62, brightness: 0.70),
                emojiOrSymbol: nil,
                inlineLabel: nil,
                destination: .exercise
            ),
            WellnessRingItem(
                label: "Stress",
                sublabel: "Today",
                value: "",
                progress: stressProgress,
                color: Color(hue: 0.76, saturation: 0.50, brightness: 0.75),
                emojiOrSymbol: stressEmojiFromLevel(stressLevel),
                inlineLabel: stressLevel,
                destination: .stress
            )
        ]
    }

    /// Delta values passed to WellnessRingsCard for Δ badges.
    /// Uses yesterdayStats from the VM for water and activity.
    /// Returns nil when no yesterday data is available.
    private var wellnessDeltaValues: [WellnessRingDestination: Int]? {
        let stats = foodJournalViewModel.yesterdayStats
        // Only show deltas when we have yesterday data
        guard stats.water > 0 || stats.coffee > 0 || stats.steps > 0 else { return nil }

        var values: [WellnessRingDestination: Int] = [:]

        // Water delta: current glasses vs yesterday
        let waterDiff = hydrationGlasses - stats.water
        if waterDiff != 0 { values[.water] = waterDiff }

        // Activity (steps) delta
        if let steps = todayWellnessLog?.steps, stats.steps > 0 {
            let stepsDiff = steps - stats.steps
            if stepsDiff != 0 { values[.exercise] = stepsDiff }
        }

        return values.isEmpty ? nil : values
    }

    private var wellnessCompletionPercent: Int {
        let cupGoal = currentGoals.waterDailyCups
        let energyGoal = currentGoals.activeEnergyGoalKcal
        let calorieGoal = currentGoals.calorieGoal
        let log = todayWellnessLog

        let calorieProgress = calorieGoal > 0 ? min(1.0, CGFloat(todayCalories) / CGFloat(calorieGoal)) : 0
        let waterProgress = cupGoal > 0 ? min(1.0, CGFloat(hydrationGlasses) / CGFloat(cupGoal)) : 0
        let burnedKcal = log?.caloriesBurned ?? 0
        let exerciseProgress = energyGoal > 0 ? min(1.0, CGFloat(burnedKcal) / CGFloat(energyGoal)) : 0
        let stressProgress = stressProgressFromLevel(effectiveStressLevel)

        let average = (calorieProgress + waterProgress + exerciseProgress + stressProgress) / 4
        return min(100, Int(round(average * 100)))
    }

    private func stressProgressFromLevel(_ level: String?) -> CGFloat {
        switch level?.lowercased() {
        case "excellent": return 0.05
        case "good":      return 0.25
        case "moderate":  return 0.50
        case "high":      return 0.75
        case "very high": return 1.0
        default:          return 0
        }
    }

    private func stressEmojiFromLevel(_ level: String?) -> String? {
        switch level?.lowercased() {
        case "excellent": return "😄"
        case "good":      return "😌"
        case "moderate":  return "😐"
        case "high":      return "😣"
        case "very high": return "😰"
        default:          return "—"
        }
    }

    // MARK: - Helpers

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    private var userName: String {
        UserProfileManager.shared.userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var greeting: String {
        userName.isEmpty ? greetingPrefix : "\(greetingPrefix), \(userName)"
    }

    // MARK: - Mood Logging

    private func refreshTodayMoodState() {
        guard let log = fetchTodayWellnessLog() else {
            hasLoggedMoodToday = false
            selectedMood = nil
            healthSuggestedMood = nil
            fetchHealthMoodSuggestion()
            return
        }

        if let mood = log.mood {
            hasLoggedMoodToday = true
            selectedMood = mood
            healthSuggestedMood = nil
        } else {
            hasLoggedMoodToday = false
            selectedMood = nil
            healthSuggestedMood = nil
            fetchHealthMoodSuggestion()
        }
    }

    private func fetchHealthMoodSuggestion() {
        guard HealthKitServiceFactory.isDataAvailable else { return }
        if AppConfig.shared.mockMode { return }
        Task {
            let service = HealthKitServiceFactory.shared
            do {
                try await service.requestAuthorization()
                if let mood = try await service.fetchTodayMood() {
                    healthSuggestedMood = mood
                }
            } catch {
                WPLogger.healthKit.error("Mood suggestion from Health failed: \(error.localizedDescription)")
            }
        }
    }

    private func logMoodForTodayIfNeeded(_ mood: MoodOption) {
        guard !hasLoggedMoodToday else { return }

        let todayLog = fetchOrCreateTodayWellnessLog()
        if todayLog.moodRaw != nil {
            hasLoggedMoodToday = true
            selectedMood = todayLog.mood
            return
        }

        todayLog.moodRaw = mood.rawValue
        do {
            try modelContext.save()
            if HealthKitServiceFactory.isDataAvailable && !AppConfig.shared.mockMode {
                Task { try? await HealthKitServiceFactory.shared.writeMood(mood) }
            }
            healthSuggestedMood = nil
            // Mood feeds the stress score (mood factor, mindful bonus, no_mood
            // engagement penalty). Trigger the shared VM to recompute so the
            // Stress ring + sparkline reflect the new mood immediately.
            stressViewModel.recompute(reason: .manualMood)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasLoggedMoodToday = true
            }
        } catch {
            hasLoggedMoodToday = false
            selectedMood = nil
            WPLogger.home.error("Mood save failed: \(error.localizedDescription)")
        }
    }

    private func refreshTodayHydrationState() {
        hydrationGlasses = fetchTodayWellnessLog()?.waterGlasses ?? 0
    }

    /// Pulls today's active energy + steps from HealthKit and persists them
    /// into the today `WellnessDayLog` so the Exercise ring reads non-zero
    /// even before the user has visited the Stress tab. In mock mode the
    /// factory routes to `MockHealthKitService`, which keeps Home and Burn
    /// reading from the same source even when `MockDataInjector` skipped
    /// today (its guard skips dates that already have a WellnessDayLog).
    private func refreshTodayActivityFromHealthKit() {
        guard HealthKitServiceFactory.isDataAvailable else { return }

        Task {
            let service = HealthKitServiceFactory.shared
            do {
                try await service.requestAuthorization()
                guard service.isAuthorized else { return }

                let cal = Calendar.current
                let startOfDay = cal.startOfDay(for: Date())
                let now = Date()
                guard now > startOfDay else { return }
                let range = DateInterval(start: startOfDay, end: now)

                async let energySamples = service.fetchActiveEnergy(for: range)
                async let stepSamples = service.fetchSteps(for: range)
                let (energy, steps) = try await (energySamples, stepSamples)

                let burnedKcal = Int((energy.first { cal.isDateInToday($0.date) }?.value ?? 0).rounded())
                let stepCount = Int((steps.first { cal.isDateInToday($0.date) }?.value ?? 0).rounded())

                let log = fetchOrCreateTodayWellnessLog()
                var didChange = false
                if burnedKcal > 0, log.caloriesBurned != burnedKcal {
                    log.caloriesBurned = burnedKcal
                    didChange = true
                }
                if stepCount > 0, log.steps != stepCount {
                    log.steps = stepCount
                    didChange = true
                }
                if didChange {
                    try? modelContext.save()
                }
            } catch {
                WPLogger.healthKit.error("Home activity refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateHydrationForToday(_ cups: Int) {
        let safeCups = max(cups, 0)
        let todayLog = fetchOrCreateTodayWellnessLog()
        guard todayLog.waterGlasses != safeCups else { return }

        todayLog.waterGlasses = safeCups
        do {
            try modelContext.save()
        } catch {
            WPLogger.home.error("Hydration save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Coffee Logging

    private func refreshTodayCoffeeState() {
        coffeeCups = fetchTodayWellnessLog()?.coffeeCups ?? 0
    }

    private func updateCoffeeForToday(cups: Int, type: CoffeeType?) {
        let log = fetchOrCreateTodayWellnessLog()
        log.coffeeCups = max(0, cups)
        if let type { log.coffeeType = type.rawValue }
        do {
            try modelContext.save()
        } catch {
            WPLogger.home.error("Coffee save failed: \(error.localizedDescription)")
        }
    }

    private func fetchTodayWellnessLog() -> WellnessDayLog? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WellnessDayLog>(
            predicate: #Predicate { $0.day == today }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateTodayWellnessLog() -> WellnessDayLog {
        if let existing = fetchTodayWellnessLog() {
            return existing
        }

        let newLog = WellnessDayLog(day: Date())
        modelContext.insert(newLog)
        return newLog
    }

    // MARK: - Journal

    /// Restores journal state from SwiftData. Intentionally does NOT animate —
    /// called from onAppear and scenePhase for state restore, not user interactions.
    private func refreshTodayJournalState() {
        if let entry = todayJournalEntry {
            hasJournaledToday = true
            journalText = entry.text
        } else {
            hasJournaledToday = false
            journalText = ""
        }
        // If mood is already logged and no journal yet, generate a prompt
        if hasLoggedMoodToday && !hasJournaledToday {
            Task {
                await journalPromptService.generatePrompt(
                    mood: selectedMood,
                    stressLevel: todayWellnessLog?.stressLevel
                )
            }
        }
    }

    /// Saves today's journal entry. Uses withAnimation() so the card removal transition fires.
    private func saveJournalEntry() {
        let trimmed = journalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = todayJournalEntry {
            existing.text = trimmed
            existing.updatedAt = .now
        } else {
            let entry = JournalEntry(
                day: Date(),
                text: trimmed,
                moodRaw: selectedMood?.rawValue,
                promptUsed: journalPromptService.currentPrompt,
                stressScore: nil
            )
            modelContext.insert(entry)
        }

        do {
            try modelContext.save()
            HapticService.notify(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasJournaledToday = true
            }
            activeSheet = nil // Dismiss journal sheet if open
            WPLogger.home.info("Journal entry saved for today")
        } catch {
            WPLogger.home.error("Journal save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview("Home Dashboard") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, JournalEntry.self, StressReading.self,
        configurations: config
    )
    return HomeView(
        selectedTab: .constant(0),
        stressViewModel: StressViewModel(modelContext: container.mainContext)
    )
    .modelContainer(container)
}
