//
//  StressView.swift
//  WellPlate
//
//  Created on 21.02.2026.
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
    private let refreshTicker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
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
            .navigationTitle("Stress")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await ScreenTimeManager.shared.requestAuthorization()
            ScreenTimeManager.shared.startMonitoring()
            await viewModel.requestPermissionAndLoad()
            viewModel.refreshScreenTimeOnly()
        }
        .onAppear {
            viewModel.refreshDietFactor()
            viewModel.refreshScreenTimeOnly()
        }
        .onReceive(refreshTicker) { _ in
            guard viewModel.isAuthorized else { return }
            viewModel.refreshScreenTimeOnly()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            viewModel.refreshScreenTimeOnly()
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

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                gaugeCard
                factorsSection
                vitalsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.loadData()
            viewModel.refreshScreenTimeOnly()
        }
    }

    // MARK: - Gauge Card

    private var gaugeCard: some View {
        VStack(spacing: 12) {
            StressScoreGaugeView(
                score: viewModel.totalScore,
                level: viewModel.stressLevel
            )

            Text(viewModel.stressLevel.encouragementText)
                .font(.r(.subheadline, .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated just now")
                    .font(.r(.caption2, .regular))
            }
            .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Factors Section

    private struct FactorItem {
        let factor: StressFactorResult
        let sheet: StressSheet
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
            Text("Stress Factors")
                .font(.r(.headline, .semibold))
                .padding(.leading, 4)

            VStack(spacing: 12) {
                ForEach(sortedFactors, id: \.factor.id) { item in
                    StressFactorCardView(factor: item.factor, onTap: { activeSheet = item.sheet })
                }
            }
        }
    }

    // MARK: - Vitals Section

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vitals")
                .font(.r(.headline, .semibold))
                .padding(.leading, 4)

            VStack(spacing: 10) {
                StressVitalCardView(
                    metric: .heartRate,
                    todayValue: viewModel.todayHeartRate,
                    onTap: { activeSheet = .vital(.heartRate) }
                )
                StressVitalCardView(
                    metric: .restingHeartRate,
                    todayValue: viewModel.todayRestingHR,
                    onTap: { activeSheet = .vital(.restingHeartRate) }
                )
                StressVitalCardView(
                    metric: .hrv,
                    todayValue: viewModel.todayHRV,
                    onTap: { activeSheet = .vital(.hrv) }
                )

                // Blood pressure: sub-label + two half-width cards side by side
                Text("Blood Pressure")
                    .font(.r(.caption, .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                HStack(spacing: 10) {
                    bpHalfCard(metric: .systolicBP, value: viewModel.todaySystolicBP)
                    bpHalfCard(metric: .diastolicBP, value: viewModel.todayDiastolicBP)
                }

                StressVitalCardView(
                    metric: .respiratoryRate,
                    todayValue: viewModel.todayRespiratoryRate,
                    onTap: { activeSheet = .vital(.respiratoryRate) }
                )
            }
        }
    }

    private func bpHalfCard(metric: VitalMetric, value: Double?) -> some View {
        Button {
            HapticService.impact(.light)
            activeSheet = .vital(metric)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(metric.accentColor)
                    Text(metric == .systolicBP ? "Systolic" : "Diastolic")
                        .font(.r(.caption, .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.4))
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let v = value {
                        Text(String(format: "%.0f", v))
                            .font(.r(22, .bold))
                            .foregroundColor(metric.accentColor)
                            .monospacedDigit()
                        Text(metric.unit)
                            .font(.r(.caption2, .regular))
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(metric.statusColor(for: v))
                            .frame(width: 8, height: 8)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    } else {
                        Text("—")
                            .font(.r(22, .bold))
                            .foregroundColor(.secondary)
                        Text(metric.unit)
                            .font(.r(.caption2, .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
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
                    .font(.r(.title2, .bold))
                Text("Allow HealthKit access to track exercise, sleep, and more for your stress score.")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                HapticService.impact(.medium)
                Task { await viewModel.requestPermissionAndLoad() }
            } label: {
                Text("Allow Access")
                    .font(.r(.headline, .semibold))
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
                .tint(.teal)
            Text("Analyzing stress factors…")
                .font(.r(.subheadline, .medium))
                .foregroundColor(.secondary)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("HealthKit Unavailable")
                .font(.r(.headline, .semibold))
            Text("Stress tracking requires a device with HealthKit support.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Shared Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    }
}

// MARK: - Preview

#Preview {
    StressView(
        viewModel: StressViewModel(
            modelContext: try! ModelContainer(for: FoodLogEntry.self).mainContext
        )
    )
}
