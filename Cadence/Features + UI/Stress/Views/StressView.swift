//
//  StressView.swift
//  Cadence
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Sheet Enum

enum StressSheet: Identifiable {
    case exercise
    case sleep
    case diet
    case screenTimeDetail
    case vital(VitalMetric)
    case interventions
    case fasting
    case circadian
    case allFactors
    case manualLog
    case mood
    case symptoms
    case todayPatternDetail

    var id: String {
        switch self {
        case .exercise:           return "exercise"
        case .sleep:              return "sleep"
        case .diet:               return "diet"
        case .screenTimeDetail:   return "screenTimeDetail"
        case .vital(let m):       return "vital_\(m.id)"
        case .interventions:      return "interventions"
        case .fasting:            return "fasting"
        case .circadian:          return "circadian"
        case .allFactors:         return "allFactors"
        case .manualLog:          return "manualLog"
        case .mood:               return "mood"
        case .symptoms:           return "symptoms"
        case .todayPatternDetail: return "todayPatternDetail"
        }
    }
}

// MARK: - StressView

struct StressView: View {

    static let themeBlue = Color(hex: "5E9FFF")

    @ObservedObject var viewModel: StressViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var promptCoordinator: DailyPromptCoordinator
    @EnvironmentObject private var tabSelector: TabSelector
    @State private var activeSheet: StressSheet? = nil
    @State private var showInsights = false
    @State private var showActivity = false
    @State private var showV3Banner: Bool = !UserDefaults.standard.bool(forKey: "wp.stress.v3AnnouncementShown")

    // Entrance animation states
    @State private var scoreAppeared   = false
    @State private var chartAppeared   = false
    @State private var adviceAppeared  = false

    private let refreshTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                levelBackground.ignoresSafeArea()

                Group {
                    if !HealthKitService.isAvailable && !viewModel.usesMockData {
                        unavailableView
                    } else if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.isAuthorized {
                        permissionView
                    } else {
                        mainScrollView
                    }
                }
            }
            .navigationTitle("Stress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isLoading {
                        Button {
                            HapticService.impact(.light)
                            activeSheet = .interventions
                        } label: {
                            Image(systemName: "bolt.heart.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Self.themeBlue)
                        }
                        .accessibilityLabel("Quick reset")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
                        Button {
                            HapticService.impact(.light)
                            showInsights = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis.ascending")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Self.themeBlue)
                        }
                        .accessibilityLabel("Insights")

                        Button {
                            HapticService.impact(.light)
                            showActivity = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Self.themeBlue)
                        }
                        .accessibilityLabel("Stress activity")
                    }
                }
            }
        }
        .task {
            viewModel.bindManualInputUpdates(from: promptCoordinator)
            if !viewModel.usesMockData {
                await ScreenTimeManager.shared.requestAuthorization()
                ScreenTimeManager.shared.startMonitoring()
            }
            await viewModel.requestPermissionAndLoad(reason: .autoAppOpen)
            if viewModel.isAuthorized {
                viewModel.refreshScreenTimeOnly(reason: .autoOnAppear)
                viewModel.loadReadings()
            }
        }
        .onAppear {
            if viewModel.isAuthorized {
                viewModel.refreshDietFactorAndLogIfNeeded(reason: .autoOnAppear)
                viewModel.refreshScreenTimeOnly(reason: .autoOnAppear)
            }
            triggerEntranceAnimations()
            Task {
                await promptCoordinator.evaluateOnStressTabAppear(
                    now: Date(),
                    modelContext: modelContext,
                    healthService: HealthKitServiceFactory.shared
                )
            }
        }
        .onReceive(refreshTicker) { _ in
            guard viewModel.isAuthorized else { return }
            viewModel.refreshScreenTimeOnly(reason: .autoTicker)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, viewModel.isAuthorized else { return }
            Task { await viewModel.loadData(reason: .autoScenePhase) }
        }
        // MARK: Insights sheet
        .sheet(isPresented: $showInsights) {
            insightsSheet
        }
        // MARK: Activity (change log) sheet
        .sheet(isPresented: $showActivity) {
            StressActivityView(viewModel: viewModel, modelContext: modelContext)
        }
        // MARK: Factor / vital detail sheets
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .exercise:
                ExerciseDetailView(
                    stepsSamples: viewModel.stepsHistory,
                    energySamples: viewModel.energyHistory
                )
            case .sleep:
                SleepDetailView(
                    summaries: viewModel.sleepHistory,
                    stats: viewModel.sleepStats
                )
            case .diet:
                DietDetailView(
                    factor: viewModel.dietFactor,
                    todayLogs: viewModel.currentDayLogs
                )
            case .screenTimeDetail:
                ScreenTimeDetailView(
                    factor: viewModel.screenTimeFactor,
                    source: viewModel.screenTimeSource,
                    currentHours: viewModel.screenTimeDisplayHours
                )
            case .vital(let metric):
                VitalDetailView(
                    metric: metric,
                    samples: viewModel.vitalHistory(for: metric)
                )
            case .interventions:
                InterventionsView()
            case .fasting:
                FastingView()
            case .circadian:
                CircadianDetailView(
                    result: viewModel.circadianResult,
                    sleepSummaries: viewModel.sleepHistory,
                    daylightSamples: viewModel.daylightHistory
                )
            case .allFactors:
                AllFactorsSheet(viewModel: viewModel)
            case .manualLog:
                QuickLogManualSheet()
            case .mood:
                MoodCheckInSheet(onSaved: { viewModel.recompute(reason: .manualMood) })
            case .symptoms:
                SymptomLogSheet()
            case .todayPatternDetail:
                StressPatternDetailView(
                    todayReadings: viewModel.todayReadings,
                    weekReadings: viewModel.weekReadings
                )
            }
        }
    }

    // MARK: - Entrance animations

    private func triggerEntranceAnimations() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.05)) {
            scoreAppeared = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
            chartAppeared = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.52)) {
            adviceAppeared = true
        }
    }

    // MARK: - Background

    private var levelBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Self.themeBlue.opacity(0.10),
                    Self.themeBlue.opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Main Scroll View

    private var mainScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── v3 announcement banner (one-time) ─────────────
                if showV3Banner {
                    v3AnnouncementBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                // ── Score Header ──────────────────────────────────
                scoreHeader
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .opacity(scoreAppeared ? 1 : 0)
                    .scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)

                // ── TODAY'S PATTERN ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Today's Pattern")
                    StressDayChartView(readings: viewModel.todayReadings) {
                        HapticService.impact(.medium)
                        activeSheet = .todayPatternDetail
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .opacity(chartAppeared ? 1 : 0)
                .offset(y: chartAppeared ? 0 : 12)

                // ── TOP DRIVERS (v3 top-5) ────────────────────────
                // Hidden for now
                // if !topDrivers.isEmpty {
                //     factorsSection
                //         .padding(.horizontal, 20)
                //         .padding(.top, 28)
                // }

                // ── ENGAGEMENT GAPS (v3) ──────────────────────────
                if viewModel.engagementPenaltyValue > 0 {
                    EngagementGapsCard(viewModel: viewModel, activeSheet: $activeSheet)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                }

                // ── ALL FACTORS DISCLOSURE ────────────────────────
                Button {
                    HapticService.impact(.light)
                    activeSheet = .allFactors
                } label: {
                    HStack {
                        Text("View all 13 factors")
                            .font(.r(.subheadline, .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.systemBackground))
                            .appShadow(radius: 15, y: 5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // ── TOP DRIVER (minimal pill) ─────────────────────
                topDriverPill
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .opacity(scoreAppeared ? 1 : 0)

                // ── QUICK RESET (conditional) ─────────────────────
                if viewModel.stressLevel == .high || viewModel.stressLevel == .veryHigh {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Quick Reset")
                        resetRecommendationCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .opacity(adviceAppeared ? 1 : 0)
                    .offset(y: adviceAppeared ? 0 : 16)
                }

                // ── QUICK LOG ─────────────────────────────────────
                // Hidden — sheet now auto-triggers via DailyPromptCoordinator
                // when HK data is missing after 10 AM on Stress-tab entry.
                // Button {
                //     HapticService.impact(.light)
                //     activeSheet = .manualLog
                // } label: {
                //     HStack(spacing: 8) {
                //         Image(systemName: "plus.circle.fill")
                //         Text("Quick Log")
                //     }
                //     .font(.r(.headline, .semibold))
                //     .frame(maxWidth: .infinity)
                //     .padding(.vertical, 14)
                //     .foregroundStyle(.white)
                //     .background(
                //         RoundedRectangle(cornerRadius: 14)
                //             .fill(Self.themeBlue)
                //     )
                // }
                // .buttonStyle(.plain)
                // .padding(.horizontal, 20)
                // .padding(.top, 28)
                // .padding(.bottom, 40)
                Color.clear.frame(height: 40)
            }
        }
        .refreshable {
            await viewModel.loadData(reason: .autoRefreshable)
            viewModel.refreshScreenTimeOnly(reason: .autoRefreshable)
            viewModel.loadReadings()
        }
    }

    // MARK: - V3 Announcement Banner

    private var v3AnnouncementBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.themeBlue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Now smarter")
                    .font(.r(.subheadline, .semibold))
                Text("Your stress score now considers mood, hydration, symptoms, and more — 13 factors total. Vitals like HRV are used to calibrate accuracy against your personal baseline.")
                    .font(.r(.caption, .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                UserDefaults.standard.set(true, forKey: "wp.stress.v3AnnouncementShown")
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showV3Banner = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Self.themeBlue.opacity(0.08))
        )
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(viewModel.totalScore.rounded()))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())

                Text("/100")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
            }
            confidenceBadge
        }
    }

    private var confidenceBadge: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.stressConfidence.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(viewModel.factorCoverage) of 13 factors logged")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .tracking(0.2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.systemGray6)))

            strainPill

            CalibratorChip(
                calibrator: viewModel.calibratorMultiplier,
                hasBaseline: viewModel.todayHRV != nil || viewModel.todayRestingHR != nil
            )
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Day-over-day score change vs yesterday, shown as a colored pill.
    /// Hidden when there's no prior baseline reading.
    @ViewBuilder
    private var strainPill: some View {
        if let delta = strainDeltaPercent {
            let isUp = delta >= 0
            let color: Color = isUp ? Color(hex: "E08A2B") : Color(hex: "1FA971")
            HStack(spacing: 2) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(isUp ? "+" : "")\(delta)% strain")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.13)))
        }
    }

    /// Returns the rounded integer % change in stress score from yesterday's
    /// most recent reading to today's, or nil when there's no comparison data.
    private var strainDeltaPercent: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return nil }

        let yesterdayReadings = viewModel.weekReadings.filter {
            cal.isDate($0.timestamp, inSameDayAs: yesterday)
        }
        guard let yesterdayScore = yesterdayReadings.last?.score, yesterdayScore > 0 else { return nil }

        let current = viewModel.totalScore
        guard current > 0 else { return nil }

        let pct = ((current - yesterdayScore) / yesterdayScore) * 100
        let rounded = Int(pct.rounded())
        return rounded == 0 ? nil : rounded
    }

    private var formattedToday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: Date())
    }

    // MARK: - Advice Card

    private var resetRecommendationCard: some View {
        Button {
            HapticService.impact(.light)
            activeSheet = .interventions
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.teal)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Try a Quick Reset")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("60-sec exercises to ease stress now")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 15, y: 5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Insights Sheet

    private var insightsSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Vitals Grid
                    vitalsGridSection
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    // Stress Factors
                    factorsSection
                        .padding(.horizontal, 16)
                        .padding(.top, 28)

                    // Circadian Health
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("CIRCADIAN HEALTH")
                        CircadianCardView(result: viewModel.circadianResult) {
                            activeSheet = .circadian
                            showInsights = false
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showInsights = false }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Vitals Grid

    private var vitalsGridSection: some View {
        VStack(spacing: 10) {
            sectionLabel("VITALS & ACTIVITY")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                gridVitalCard(
                    icon: "heart.fill",
                    iconColor: .pink,
                    label: "HEART RATE",
                    value: viewModel.todayHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                    subtitle: viewModel.todayRestingHR.map { "Resting: \(Int($0)) bpm" } ?? "Resting",
                    onTap: { activeSheet = .vital(.heartRate); showInsights = false }
                )
                gridVitalCard(
                    icon: "waveform.path.ecg",
                    iconColor: .purple,
                    label: "HRV",
                    value: viewModel.todayHRV.map { "\(Int($0)) ms" } ?? "—",
                    subtitle: "Heart rate variability",
                    onTap: { activeSheet = .vital(.hrv); showInsights = false }
                )
                gridVitalCard(
                    icon: "moon.zzz.fill",
                    iconColor: Color(hue: 0.68, saturation: 0.55, brightness: 0.75),
                    label: "SLEEP QUALITY",
                    value: sleepDisplayValue,
                    subtitle: sleepSubtitle,
                    onTap: { activeSheet = .sleep; showInsights = false }
                )
                gridVitalCard(
                    icon: "figure.walk",
                    iconColor: Color(hue: 0.55, saturation: 0.55, brightness: 0.60),
                    label: "ACTIVITY",
                    value: viewModel.exerciseFactor.statusText,
                    subtitle: viewModel.exerciseFactor.detailText,
                    onTap: { activeSheet = .exercise; showInsights = false }
                )
            }
        }
    }

    @ViewBuilder
    private func gridVitalCard(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        subtitle: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticService.impact(.light)
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.85))
                    .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Factors Section (v3: top-5 drivers ranked by stress contribution)

    private var topDrivers: [StressFactorResult] {
        viewModel.allFactors
            .filter(\.hasValidData)
            .sorted { $0.stressContribution > $1.stressContribution }
            .prefix(5)
            .map { $0 }
    }

    /// Minimal inline pill surfacing today's #1 stress driver. Hugs content,
    /// uses an ultra-thin material capsule (no card chrome) so it reads as
    /// a label, not another card. Tappable when a route exists.
    @ViewBuilder
    private var topDriverPill: some View {
        if let factor = topDrivers.first, factor.stressContribution > 0 {
            let sheet = sheetForFactor(factor)
            let tabAction = tabActionForFactor(factor)
            let isTappable = sheet != nil || tabAction != nil

            HStack {
                Button {
                    HapticService.impact(.light)
                    if let sheet { activeSheet = sheet }
                    else if let tabAction { tabAction() }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(factor.accentColor)
                            .frame(width: 6, height: 6)
                        Text("Top driver")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Text("·")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.45))
                        Text(factor.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        if isTappable {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(.leading, 1)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isTappable)

                Spacer(minLength: 0)
            }
        }
    }

    /// Routes a factor's title to its detail sheet/action. nil = non-tappable.
    private func sheetForFactor(_ factor: StressFactorResult) -> StressSheet? {
        switch factor.title {
        case "Sleep":           return .sleep
        case "Exercise":        return .exercise
        case "Caffeine":        return nil    // non-tappable in v3
        case "Screen Time":     return .screenTimeDetail
        case "Diet":            return .diet
        case "Hydration":       return nil    // routes via TabSelector below
        case "Circadian":       return .sleep
        case "Daylight":        return .sleep
        case "Meal Timing":     return .diet
        case "Fasting":         return .fasting
        case "Eating Triggers": return nil    // non-tappable in v3
        case "Mood":            return .mood
        case "Symptoms":        return .symptoms
        default:                return nil
        }
    }

    /// Cross-tab navigation for factors that route via TabSelector instead of a sheet.
    private func tabActionForFactor(_ factor: StressFactorResult) -> (() -> Void)? {
        switch factor.title {
        case "Hydration":
            return { tabSelector.switchTo(.home, andPresent: .water) }
        default:
            return nil
        }
    }

    private var factorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("TOP DRIVERS")
            VStack(spacing: 10) {
                ForEach(topDrivers, id: \.id) { factor in
                    let sheet = sheetForFactor(factor)
                    let tabAction = tabActionForFactor(factor)
                    if let sheet {
                        StressFactorCardView(factor: factor, onTap: {
                            activeSheet = sheet
                            showInsights = false
                        })
                    } else if let tabAction {
                        StressFactorCardView(factor: factor, onTap: tabAction)
                    } else {
                        StressFactorCardView(factor: factor)
                    }
                }
            }
        }
    }

    // MARK: - Sleep helpers

    private var sleepDisplayValue: String {
        let st = viewModel.sleepFactor.statusText
        if st.contains("total") {
            return st.components(separatedBy: " · ").first ?? st
        }
        return st
    }

    private var sleepSubtitle: String {
        let st = viewModel.sleepFactor.statusText
        if st.contains("·") {
            let parts = st.components(separatedBy: " · ")
            if parts.count > 1 { return parts[1] }
        }
        return viewModel.sleepFactor.detailText
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(1.2)
            .padding(.leading, 4)
    }

    // MARK: - State Views

    private var permissionView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal.opacity(0.15), .cyan.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom)
                    )
            }
            VStack(spacing: 8) {
                Text("Stress Insights")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Allow HealthKit access to track exercise, sleep, and more for your stress score.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                HapticService.impact(.medium)
                Task { await viewModel.requestPermissionAndLoad(reason: .autoAppOpen) }
            } label: {
                Text("Allow Access")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [.teal, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Self.themeBlue)
            Text("Analyzing stress factors…")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("HealthKit Unavailable")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Stress tracking requires a device with HealthKit support.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    let snap = StressMockSnapshot.default
    return StressView(
        viewModel: StressViewModel(
            healthService: MockHealthKitService(snapshot: snap),
            modelContext: try! ModelContainer(for: FoodLogEntry.self, StressReading.self).mainContext,
            mockSnapshot: snap
        )
    )
}
