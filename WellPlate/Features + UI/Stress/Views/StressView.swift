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
    case screenTimeEntry
    case vital(VitalMetric)

    var id: String {
        switch self {
        case .exercise:         return "exercise"
        case .sleep:            return "sleep"
        case .diet:             return "diet"
        case .screenTimeDetail: return "screenTimeDetail"
        case .screenTimeEntry:  return "screenTimeEntry"
        case .vital(let m):     return "vital_\(m.id)"
        }
    }
}

// MARK: - StressView

struct StressView: View {

    @StateObject var viewModel: StressViewModel
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: StressSheet? = nil
    @State private var pendingManualHours: Double = 0
    #if DEBUG
    @State private var debugScreenTimeHours: Double = 0
    @State private var didSeedDebugScreenTimeHours = false
    #endif
    private let refreshTicker   = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                // Warm tinted background that shifts with stress level
                levelBackground
                    .ignoresSafeArea()

                Group {
                    if !HealthKitService.isAvailable {
                        unavailableView
                    } else if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.isAuthorized {
                        permissionView
                    } else {
                        mainContent
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .task {
            await ScreenTimeManager.shared.requestAuthorization()
            ScreenTimeManager.shared.startMonitoring()
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
            #if DEBUG
            seedDebugScreenTimeInputIfNeeded()
            #endif
        }
        .onReceive(refreshTicker) { _ in
            guard viewModel.isAuthorized else { return }
            viewModel.refreshScreenTimeOnly()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, viewModel.isAuthorized else { return }
            Task { await viewModel.loadData() }
        }
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
                    source: viewModel.screenTimeSource
                )
            case .screenTimeEntry:
                ScreenTimeInputSheet(
                    hours: $pendingManualHours,
                    autoDetectedHours: ScreenTimeManager.shared.currentAutoDetectedReading.map { Double($0.displayRoundedHours) }
                ) {
                    viewModel.setManualScreenTime(pendingManualHours)
                }
            case .vital(let metric):
                VitalDetailView(
                    metric: metric,
                    samples: viewModel.vitalHistory(for: metric)
                )
            }
        }
    }

    // MARK: - Background

    private var levelBackground: some View {
        ZStack {
            // Base warm cream
            Color(.systemGroupedBackground)

            // Subtle level-tinted gradient overlaid on top
            LinearGradient(
                colors: [
                    viewModel.stressLevel.color.opacity(0.10),
                    viewModel.stressLevel.color.opacity(0.03),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────
                headerSection
                    .padding(.top, 56)
                    .padding(.horizontal, 24)

                // ── Score Gauge ───────────────────────────────
                StressScoreGaugeView(
                    score: viewModel.totalScore,
                    level: viewModel.stressLevel
                )
                .padding(.top, 4)

                // ── Contextual comparison blurb ───────────────
                comparisonBadge
                    .padding(.top, 2)

                // ── Auto Logging Note ─────────────────────────
                autoLoggingNote
                    .padding(.top, 10)
                    .padding(.bottom, 28)

                // ── Quick Vitals ──────────────────────────────
                vitalsQuickSection
                    .padding(.horizontal, 16)

                // ── Stress Factors ────────────────────────────
                factorsSection
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                #if DEBUG
                debugScreenTimeSection
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                #endif

                // ── Timeline ──────────────────────────────────
                timelineSection
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
            }
        }
        .refreshable {
            await viewModel.loadData()
            viewModel.refreshScreenTimeOnly()
            viewModel.loadReadings()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY'S STRESS")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1.2)
                Text(viewModel.stressLevel.label)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
            // Level icon badge
            ZStack {
                Circle()
                    .fill(viewModel.stressLevel.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: viewModel.stressLevel.systemImage)
                    .font(.system(size: 22))
                    .foregroundColor(viewModel.stressLevel.color)
            }
        }
    }

    // MARK: - Comparison Badge

    private var comparisonBadge: some View {
        let weekPercentile = stressPercentile
        return HStack(spacing: 4) {
            Text("Your stress is lower than")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            Text("\(weekPercentile)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(viewModel.stressLevel.color)
            Text("of this week")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    /// Simple heuristic: invert the score to a "lower than X%" reading.
    private var stressPercentile: Int {
        let pct = Int((1.0 - viewModel.totalScore / 100.0) * 100)
        return max(0, min(100, pct))
    }

    // MARK: - Quick Vitals (Heart Rate · Sleep · Activity)

    private var vitalsQuickSection: some View {
        VStack(spacing: 10) {
            // Heart Rate row
            quickVitalRow(
                icon: "heart.fill",
                iconColor: .pink,
                label: "HEART RATE",
                value: viewModel.todayHeartRate.map { "\(Int($0)) bpm" } ?? "—",
                subtitle: viewModel.todayRestingHR.map { "Resting: \(Int($0)) bpm" } ?? "Resting",
                onTap: { activeSheet = .vital(.heartRate) }
            )

            // Sleep Quality — derived from sleep factor
            quickVitalRow(
                icon: "moon.zzz.fill",
                iconColor: Color(hue: 0.68, saturation: 0.55, brightness: 0.75),
                label: "SLEEP QUALITY",
                value: sleepDisplayValue,
                subtitle: sleepSubtitle,
                onTap: { activeSheet = .sleep }
            )

            // Activity — derived from exercise factor
            quickVitalRow(
                icon: "figure.walk",
                iconColor: Color(hue: 0.55, saturation: 0.55, brightness: 0.60),
                label: "ACTIVITY",
                value: viewModel.exerciseFactor.statusText,
                subtitle: viewModel.exerciseFactor.detailText,
                onTap: { activeSheet = .exercise }
            )
        }
    }

    private var sleepDisplayValue: String {
        let st = viewModel.sleepFactor.statusText
        // statusText is like "7.2h total · 1.5h deep"
        if st.contains("total") {
            let parts = st.components(separatedBy: " · ")
            return parts.first ?? st
        }
        return st
    }

    private var sleepSubtitle: String {
        let st = viewModel.sleepFactor.statusText
        if st.contains("·") {
            let parts = st.components(separatedBy: " · ")
            if parts.count > 1 {
                // "1.5h deep" → "Deep 42%" style
                return parts[1]
            }
        }
        return viewModel.sleepFactor.detailText
    }

    @ViewBuilder
    private func quickVitalRow(
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
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Labels
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.85))
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
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
            FactorItem(factor: viewModel.screenTimeFactor, sheet: nil),
        ]
        .sorted { $0.factor.stressContribution > $1.factor.stressContribution }
    }

    private var factorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("STRESS FACTORS")
            VStack(spacing: 10) {
                ForEach(sortedFactors, id: \.factor.id) { item in
                    if let sheet = item.sheet {
                        StressFactorCardView(factor: item.factor, onTap: { activeSheet = sheet })
                    } else {
                        StressFactorCardView(factor: item.factor)
                    }
                }
            }
        }
    }

    #if DEBUG
    private var debugScreenTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("DEBUG · SCREEN TIME")

            VStack(spacing: 12) {
                HStack {
                    Text("Manual override")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(String(format: "%.2f h", debugScreenTimeHours))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.cyan)
                }

                Slider(value: $debugScreenTimeHours, in: 0...24, step: 0.25)
                    .tint(.cyan)

                HStack {
                    Text("0h")
                    Spacer()
                    Text("24h")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button("Apply") {
                        let rounded = (debugScreenTimeHours * 4).rounded() / 4
                        debugScreenTimeHours = rounded
                        viewModel.setManualScreenTime(rounded)
                        viewModel.setDebugManualScreenTimeOverride(rounded)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Button("Use Auto") {
                        viewModel.clearDebugManualScreenTimeOverride()
                        viewModel.refreshScreenTimeOnly()
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.debugManualScreenTimeOverrideHours != nil {
                    Text("Debug override is active.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.88))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
            )
        }
    }

    private func seedDebugScreenTimeInputIfNeeded() {
        guard !didSeedDebugScreenTimeHours else { return }
        if let debugOverride = viewModel.debugManualScreenTimeOverrideHours {
            debugScreenTimeHours = debugOverride
        } else if let auto = screenTimeManager.currentAutoDetectedReading?.rawHours {
            debugScreenTimeHours = auto
        } else {
            debugScreenTimeHours = viewModel.currentManualHours
        }
        didSeedDebugScreenTimeHours = true
    }
    #endif

    // MARK: - Auto Logging Note

    private var autoLoggingNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(viewModel.stressLevel.color)
            Text("Stress is logged automatically with time and value whenever it changes.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.systemBackground).opacity(0.85))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - Timeline Section (Real Charts)

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // ── Today's intraday chart ──
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("STRESS THROUGH THE DAY")
                StressDayChartView(readings: viewModel.todayReadings)
            }

            // ── 7-day trend ──
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("7-DAY TREND")
                StressWeekChartView(readings: viewModel.weekReadings)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
            .tracking(1.0)
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
                .tint(viewModel.stressLevel.color)
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
    StressView(
        viewModel: StressViewModel(
            modelContext: try! ModelContainer(for: FoodLogEntry.self, StressReading.self).mainContext
        )
    )
}
