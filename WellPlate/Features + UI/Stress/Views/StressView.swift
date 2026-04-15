//
//  StressView.swift
//  WellPlate
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
    case stressLab
    case interventions
    case fasting
    case circadian

    var id: String {
        switch self {
        case .exercise:         return "exercise"
        case .sleep:            return "sleep"
        case .diet:             return "diet"
        case .screenTimeDetail: return "screenTimeDetail"
        case .vital(let m):     return "vital_\(m.id)"
        case .stressLab:        return "stressLab"
        case .interventions:    return "interventions"
        case .fasting:          return "fasting"
        case .circadian:        return "circadian"
        }
    }
}

// MARK: - StressView

struct StressView: View {

    static let themeBlue = Color(hex: "5E9FFF")

    @StateObject var viewModel: StressViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: StressSheet? = nil
    @State private var showInsights = false

    // Entrance animation states
    @State private var scoreAppeared   = false
    @State private var chartAppeared   = false
    @State private var weekAppeared    = false
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
                        Menu {
                            // Lab is gated — requires HealthKit for experiment biometrics
                            if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized {
                                Button {
                                    HapticService.impact(.light)
                                    activeSheet = .stressLab
                                } label: {
                                    Label("Lab", systemImage: "flask.fill")
                                }
                            }
                            // Resets are always available — no HealthKit dependency
                            Button {
                                HapticService.impact(.light)
                                activeSheet = .interventions
                            } label: {
                                Label("Resets", systemImage: "bolt.heart.fill")
                            }
                            Button {
                                HapticService.impact(.light)
                                activeSheet = .fasting
                            } label: {
                                Label("Fast", systemImage: "fork.knife.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Self.themeBlue)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
                        Button {
                            HapticService.impact(.light)
                            showInsights = true
                        } label: {
                            Label("Insights", systemImage: "chart.bar.xaxis.ascending")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Self.themeBlue)
                        }
                    }
                }
            }
        }
        .task {
            if !viewModel.usesMockData {
                await ScreenTimeManager.shared.requestAuthorization()
                ScreenTimeManager.shared.startMonitoring()
            }
            await viewModel.requestPermissionAndLoad()
            if viewModel.isAuthorized {
                viewModel.refreshScreenTimeOnly()
                viewModel.loadReadings()
            }
        }
        .onAppear {
            if viewModel.isAuthorized {
                viewModel.refreshDietFactorAndLogIfNeeded()
                viewModel.refreshScreenTimeOnly()
            }
            triggerEntranceAnimations()
        }
        .onReceive(refreshTicker) { _ in
            guard viewModel.isAuthorized else { return }
            viewModel.refreshScreenTimeOnly()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, viewModel.isAuthorized else { return }
            Task { await viewModel.loadData() }
        }
        // MARK: Insights sheet
        .sheet(isPresented: $showInsights) {
            insightsSheet
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
            case .stressLab:
                StressLabView()
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
        withAnimation(.easeOut(duration: 0.45).delay(0.38)) {
            weekAppeared = true
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

                // ── Score Header ──────────────────────────────────
                scoreHeader
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .opacity(scoreAppeared ? 1 : 0)
                    .scaleEffect(scoreAppeared ? 1 : 0.93, anchor: .topLeading)

                // ── TODAY'S PATTERN ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Today's Pattern")
                    StressDayChartView(readings: viewModel.todayReadings)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .opacity(chartAppeared ? 1 : 0)
                .offset(y: chartAppeared ? 0 : 12)

                // ── THIS WEEK ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("This Week")
                    weekColourBar
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .opacity(weekAppeared ? 1 : 0)
                .offset(y: weekAppeared ? 0 : 12)

                // ── ADVICE ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Suggestion")
                    adviceCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .opacity(adviceAppeared ? 1 : 0)
                .offset(y: adviceAppeared ? 0 : 16)

                // ── QUICK RESET (conditional) ─────────────────────
                if viewModel.stressLevel == .high || viewModel.stressLevel == .veryHigh {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Quick Reset")
                        resetRecommendationCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                    .opacity(adviceAppeared ? 1 : 0)
                    .offset(y: adviceAppeared ? 0 : 16)
                } else {
                    Spacer().frame(height: 40)
                }
            }
        }
        .refreshable {
            await viewModel.loadData()
            viewModel.refreshScreenTimeOnly()
            viewModel.loadReadings()
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(Int(viewModel.totalScore))")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .contentTransition(.numericText())

            Text("/100")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
        }
    }

    private var formattedToday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: Date())
    }

    // MARK: - Week Colour Bar

    private var weekColourBar: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Build Sunday-of-this-week → Saturday
        let weekday = cal.component(.weekday, from: today) // 1=Sun
        let sundayOffset = -(weekday - 1)
        let sunday = cal.date(byAdding: .day, value: sundayOffset, to: today)!

        // Group weekReadings by day
        let grouped: [Date: [StressReading]] = Dictionary(
            grouping: viewModel.weekReadings,
            by: { cal.startOfDay(for: $0.timestamp) }
        )

        return HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: offset, to: sunday)!
                let isToday = cal.isDate(day, inSameDayAs: today)
                let label = dayLetter(for: day)
                let readings = grouped[day] ?? []
                let avgScore = readings.isEmpty ? nil : readings.map(\.score).reduce(0, +) / Double(readings.count)
                let barHeight: CGFloat = 56

                VStack(spacing: 4) {
                    // Mini gradient bar
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                            .frame(height: barHeight)

                        if let score = avgScore, score > 0 {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            weekDayColor(score: score).opacity(0.30),
                                            weekDayColor(score: score)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: max(8, barHeight * CGFloat(score / 100.0)))
                                .padding(.horizontal, 2)
                                .padding(.bottom, 2)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isToday ? weekDayColor(score: avgScore ?? 0).opacity(0.45) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .opacity(weekAppeared ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.35).delay(Double(offset) * 0.055),
                        value: weekAppeared
                    )

                    // Score + day label
                    VStack(spacing: 1) {
                        if let score = avgScore, score > 0 {
                            Text("\(Int(score))")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(weekDayColor(score: score))
                        } else {
                            Text("—")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.25))
                        }
                        Text(label)
                            .font(.system(size: 10, weight: isToday ? .bold : .regular, design: .rounded))
                            .foregroundColor(isToday ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }

    private func dayLetter(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // single letter: S, M, T, W, T, F, S
        return f.string(from: date)
    }

    private static let chartBlue = Color(hex: "5E9FFF")

    private func weekDayColor(score: Double) -> Color {
        let t = min(max(score / 100.0, 0), 1)
        let opacity = 0.45 + t * 0.55
        return Self.chartBlue.opacity(opacity)
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

    private var adviceCard: some View {
        let topFactor = sortedFactors.first
        let factorIcon = topFactor?.factor.icon ?? "leaf.fill"
        let accent = topFactor?.factor.accentColor ?? Self.themeBlue
        let sheet = topFactor?.sheet

        return HStack(spacing: 0) {
            // Leading accent strip
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 12) {
                // Icon + factor label
                HStack(spacing: 8) {
                    Image(systemName: factorIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                    Text(topFactor?.factor.title.uppercased() ?? "LIFESTYLE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                }

                // Insight text
                Text(adviceText(for: topFactor?.factor))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary.opacity(0.88))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // CTA
                Button {
                    HapticService.impact(.light)
                    if let s = sheet { activeSheet = s }
                } label: {
                        Text(actionLabel(for: topFactor?.factor))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .padding(.vertical, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func adviceText(for factor: StressFactorResult?) -> AttributedString {
        guard let f = factor else {
            return AttributedString("Track your habits daily to better understand what affects your stress.")
        }
        var base = AttributedString(f.detailText)
        // Bold any number with a unit (e.g. "6.4h", "4,200 steps")
        // This is a simple heuristic: bold words containing digits
        let words = f.detailText.components(separatedBy: " ")
        var result = AttributedString()
        for (i, word) in words.enumerated() {
            var part = AttributedString(word + (i < words.count - 1 ? " " : ""))
            let hasDigit = word.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            if hasDigit {
                part.font = .system(size: 15, weight: .bold)
            }
            result.append(part)
        }
        return result.runs.isEmpty ? base : result
    }

    private func actionLabel(for factor: StressFactorResult?) -> String {
        guard let f = factor else { return "view details" }
        switch f.title.lowercased() {
        case let n where n.contains("screen"): return "set screen reminder"
        case let n where n.contains("sleep"):  return "view sleep details"
        case let n where n.contains("diet"),
             let n where n.contains("food"):   return "view nutrition"
        case let n where n.contains("exercise"),
             let n where n.contains("activ"):  return "view activity"
        default: return "view details"
        }
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

                    // 7-Day Trend
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("7-DAY TREND")
                        StressWeekChartView(readings: viewModel.weekReadings)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                    // Stress through the day (detailed)
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("STRESS THROUGH THE DAY")
                        StressDayChartView(readings: viewModel.todayReadings)
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

    // MARK: - Factors Section

    private struct FactorItem {
        let factor: StressFactorResult
        let sheet: StressSheet?
    }

    private var sortedFactors: [FactorItem] {
        [
            FactorItem(factor: viewModel.exerciseFactor,   sheet: .exercise),
            FactorItem(factor: viewModel.sleepFactor,      sheet: .sleep),
            FactorItem(factor: viewModel.dietFactor,       sheet: .diet),
            FactorItem(factor: viewModel.screenTimeFactor, sheet: .screenTimeDetail),
        ]
        .sorted { $0.factor.stressContribution > $1.factor.stressContribution }
    }

    private var factorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("STRESS FACTORS")
            VStack(spacing: 10) {
                ForEach(sortedFactors, id: \.factor.id) { item in
                    if let sheet = item.sheet {
                        StressFactorCardView(factor: item.factor, onTap: { activeSheet = sheet; showInsights = false })
                    } else {
                        StressFactorCardView(factor: item.factor)
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
                Task { await viewModel.requestPermissionAndLoad() }
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
