//
//  BurnView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import SwiftData
import Charts

struct BurnView: View {

    @Query private var userGoalsList: [UserGoals]
    @StateObject private var viewModel = BurnViewModel()
    @State private var selectedMetric: BurnMetric = .activeEnergy
    @State private var detailMetric: BurnMetric? = nil

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            Group {
                if !HealthKitServiceFactory.isDataAvailable {
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
        .navigationTitle("Burn")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $detailMetric) { metric in
            BurnDetailView(
                metric: metric,
                samples: viewModel.last30Days(for: metric)
            )
        }
        .task { await viewModel.requestPermissionAndLoad() }
        .onAppear { syncGoals() }
        .onChange(of: userGoalsList.first?.activeEnergyGoalKcal) { _, _ in syncGoals() }
        .onChange(of: userGoalsList.first?.dailyStepsGoal) { _, _ in syncGoals() }
    }

    private func syncGoals() {
        viewModel.activeEnergyGoal = Double(currentGoals.activeEnergyGoalKcal)
        viewModel.dailyStepsGoal = Double(currentGoals.dailyStepsGoal)
    }

    // MARK: - Main Scroll Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                todayHeroCard
                weeklyChartCard
                metricsGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Today Hero Card

    private var todayHeroCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(viewModel.todayActiveEnergy))")
                            .font(.r(48, .heavy))
                            .foregroundColor(AppColors.brand)
                            .monospacedDigit()
                        Text("kcal")
                            .font(.r(.title3, .semibold))
                            .foregroundColor(.secondary)
                    }

                    Text("Active Energy Burned")
                        .font(.r(.caption, .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                ProgressRingView(
                    progress: viewModel.activeEnergyProgress,
                    color: AppColors.brand,
                    size: 86
                )
            }

            Divider()

            HStack(spacing: 0) {
                statPill(
                    label: "Steps",
                    value: stepsFormatted,
                    color: .green
                )
                Divider().frame(height: 32)
                statPill(
                    label: "7D Avg",
                    value: "\(viewModel.weekAvgEnergy) kcal",
                    color: AppColors.brand
                )
                Divider().frame(height: 32)
                statPill(
                    label: "Best Day",
                    value: "\(viewModel.bestDayEnergy) kcal",
                    color: .red
                )
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.r(13, .bold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.r(.caption2, .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weekly Chart Card

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("7-Day History")
                    .font(.r(.headline, .semibold))
                Spacer()
                Picker("", selection: $selectedMetric) {
                    ForEach(BurnMetric.allCases) { m in
                        Label(m == .activeEnergy ? "Energy" : "Steps",
                              systemImage: m.systemImage)
                            .tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }

            let samples = viewModel.last7Days(for: selectedMetric)
            if samples.isEmpty {
                emptyChartPlaceholder
            } else {
                BurnChartView(samples: samples, color: selectedMetric.accentColor)
                    .frame(height: 200)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(BurnMetric.allCases) { metric in
                BurnMetricCardView(
                    metric: metric,
                    samples: viewModel.last7Days(for: metric),
                    currentValue: viewModel.todayValue(for: metric)
                ) {
                    detailMetric = metric
                }
            }
        }
    }

    // MARK: - States

    private var permissionView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.15), .red.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Connect Apple Health")
                    .font(.r(.title2, .bold))
                Text("WellPlate needs access to your\nactivity data to show Burn insights.")
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
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .red],
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
                .tint(AppColors.brand)
            Text("Loading health data…")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("HealthKit Unavailable")
                .font(.r(.title3, .bold))
            Text("Run on a physical iPhone to access health data.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.25))
            Text("No data yet")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    }

    private var stepsFormatted: String {
        NumberFormatter.localizedString(
            from: NSNumber(value: Int(viewModel.todaySteps)),
            number: .decimal
        )
    }
}

#Preview("Light") {
    BurnView()
}

#Preview("Dark") {
    BurnView()
        .preferredColorScheme(.dark)
}
