//
//  SleepDetailView.swift
//  WellPlate
//
//  Created by Hari's Mac on 21.02.2026.
//

import SwiftUI
import Charts

/// Detail sheet — 30-day chart + Min / Max / Avg stats for sleep.
struct SleepDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let summaries: [DailySleepSummary]
    let stats: (min: Double, max: Double, avg: Double)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        kpiCard
                        chartCard
                        statsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.indigo)
                }
            }
        }
    }

    // MARK: - KPI Header

    private var kpiCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.indigo)
                .frame(width: 56, height: 56)
                .background(.indigo.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Last Night")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedToday)
                        .font(.r(36, .heavy))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("hrs")
                        .font(.r(.title3, .semibold))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days")
                .font(.r(.headline, .semibold))

            if summaries.isEmpty {
                emptyState
            } else {
                SleepDetailChartView(summaries: summaries)
                    .frame(height: 200)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 0) {
            statRow(
                label: "Minimum",
                value: String(format: "%.1f", stats.min),
                icon: "arrow.down.circle.fill",
                color: .blue
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Maximum",
                value: String(format: "%.1f", stats.max),
                icon: "arrow.up.circle.fill",
                color: .indigo
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Average",
                value: String(format: "%.1f", stats.avg),
                icon: "chart.bar.fill",
                color: .purple
            )
        }
        .padding(.vertical, 8)
        .background(cardBackground)
    }

    private func statRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 32)

            Text(label)
                .font(.r(14, .medium))
                .foregroundColor(.secondary)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.r(14, .semibold))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                Text("hrs")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.3))
            Text("No data for this period")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var formattedToday: String {
        let today = summaries.last?.totalHours ?? 0
        return String(format: "%.1f", today)
    }
}
