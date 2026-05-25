//
//  BurnDetailView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import Charts

/// Detail sheet — 30-day chart + Min / Max / Avg stats for a single Burn metric.
struct BurnDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let metric: BurnMetric
    let samples: [DailyMetricSample]   // 30-day window

    private var stats: (min: Double, max: Double, avg: Double) {
        let values = samples.map(\.value)
        guard !values.isEmpty else { return (0, 0, 0) }
        return (
            values.min()!,
            values.max()!,
            values.reduce(0, +) / Double(values.count)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // KPI header card
                        kpiCard

                        // 30-day chart card
                        chartCard

                        // Stats card
                        statsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(metric.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.brand)
                }
            }
        }
    }

    // MARK: - KPI Header

    private var kpiCard: some View {
        HStack(spacing: 20) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(metric.accentColor)
                .frame(width: 56, height: 56)
                .background(metric.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedToday)
                        .font(.r(36, .heavy))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text(metric.unit)
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

            if samples.isEmpty {
                emptyState
            } else {
                DetailBarChartView(
                    samples: samples,
                    color: metric.accentColor,
                    unit: metric.unit
                )
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
                value: formattedValue(stats.min),
                icon: "arrow.down.circle.fill",
                color: .blue
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Maximum",
                value: formattedValue(stats.max),
                icon: "arrow.up.circle.fill",
                color: metric.accentColor
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Average",
                value: formattedValue(stats.avg),
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
                Text(metric.unit)
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
        let today = samples.first { Calendar.current.isDateInToday($0.date) }?.value ?? 0
        return formattedValue(today)
    }

    private func formattedValue(_ v: Double) -> String {
        if metric == .steps {
            return NumberFormatter.localizedString(
                from: NSNumber(value: Int(v)), number: .decimal
            )
        }
        return "\(Int(v))"
    }
}

#Preview("Light") {
    BurnDetailView(
        metric: .activeEnergy,
        samples: []
    )
}

#Preview("Dark") {
    BurnDetailView(
        metric: .activeEnergy,
        samples: []
    )
    .preferredColorScheme(.dark)
}
