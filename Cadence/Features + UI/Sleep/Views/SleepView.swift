//
//  SleepView.swift
//  WellPlate
//
//  Created by Hari's Mac on 21.02.2026.
//

import SwiftUI
import SwiftData
import Charts

struct SleepView: View {

    @Query private var userGoalsList: [UserGoals]
    @StateObject private var viewModel = SleepViewModel()
    @State private var showStages = true
    @State private var showDetail = false

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showDetail) {
                SleepDetailView(
                    summaries: viewModel.last30Days,
                    stats: viewModel.stats()
                )
            }
        }
        .task { await viewModel.requestPermissionAndLoad() }
        .onAppear { viewModel.sleepGoal = currentGoals.sleepGoalHours }
        .onChange(of: userGoalsList.first?.sleepGoalHours) { _, newValue in
            viewModel.sleepGoal = newValue ?? 8.0
        }
    }

    // MARK: - Main Scroll Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                lastNightHeroCard
                weeklyChartCard
                if let summary = viewModel.lastNightSleep {
                    stageBreakdownCard(summary: summary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Last Night Hero Card

    private var lastNightHeroCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Night")
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", viewModel.totalHoursLastNight))
                            .font(.r(48, .heavy))
                            .foregroundColor(.indigo)
                            .monospacedDigit()
                        Text("hrs")
                            .font(.r(.title3, .semibold))
                            .foregroundColor(.secondary)
                    }

                    Text("Total Sleep")
                        .font(.r(.caption, .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                ProgressRingView(
                    progress: viewModel.sleepGoalProgress,
                    color: .indigo,
                    size: 86
                )
            }

            Divider()

            HStack(spacing: 0) {
                statPill(
                    label: "Deep",
                    value: String(format: "%.1fh", viewModel.deepHoursLastNight),
                    color: SleepStage.deep.color
                )
                Divider().frame(height: 32)
                statPill(
                    label: "7D Avg",
                    value: "\(viewModel.weekAvgHours)h",
                    color: .indigo
                )
                Divider().frame(height: 32)
                statPill(
                    label: "Best Night",
                    value: "\(viewModel.bestNightHours)h",
                    color: .purple
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
                Picker("", selection: $showStages) {
                    Text("Stages").tag(true)
                    Text("Total").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }

            let data = viewModel.last7Days
            if data.isEmpty {
                emptyChartPlaceholder
            } else {
                SleepChartView(summaries: data, showStages: showStages)
                    .frame(height: 200)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Stage Breakdown Card

    private func stageBreakdownCard(summary: DailySleepSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Stage Breakdown")
                    .font(.r(.headline, .semibold))
                Spacer()

                // Quality badge
                Text(summary.quality.rawValue)
                    .font(.r(.caption, .bold))
                    .foregroundColor(summary.quality.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(summary.quality.color.opacity(0.12))
                    )
            }

            SleepStageBarView(summary: summary)

            // Tap to see details
            Button {
                HapticService.impact(.light)
                showDetail = true
            } label: {
                HStack {
                    Text("View 30-Day Details")
                        .font(.r(.subheadline, .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.indigo)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - States

    private var permissionView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.15), .purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Connect Apple Health")
                    .font(.r(.title2, .bold))
                Text("WellPlate needs access to your\nsleep data to show Sleep insights.")
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
                                    colors: [.indigo, .purple],
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
                .tint(.indigo)
            Text("Loading sleep data…")
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
}

#Preview {
    SleepView()
}
