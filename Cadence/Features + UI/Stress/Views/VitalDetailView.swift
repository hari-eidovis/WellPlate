//
//  VitalDetailView.swift
//  WellPlate
//
//  Created on 25.02.2026.
//

import SwiftUI
import Charts

struct VitalDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let metric: VitalMetric
    let samples: [DailyMetricSample]

    /// Derived internally — avoids two-source discrepancy.
    private var todayValue: Double? {
        samples.first(where: { Calendar.current.isDateInToday($0.date) })?.value
    }

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
                        kpiCard
                        chartCard
                        statsCard
                        normalRangeCard
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
                        .foregroundColor(metric.accentColor)
                }
            }
        }
    }

    // MARK: - KPI Card

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
                    if let value = todayValue {
                        Text(String(format: "%.0f", value))
                            .font(.r(36, .heavy))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(.r(36, .heavy))
                            .foregroundColor(.secondary)
                    }
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
                value: String(format: "%.0f", stats.min),
                icon: "arrow.down.circle.fill",
                color: .blue
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Maximum",
                value: String(format: "%.0f", stats.max),
                icon: "arrow.up.circle.fill",
                color: metric.accentColor
            )
            Divider().padding(.leading, 52)
            statRow(
                label: "Average",
                value: String(format: "%.0f", stats.avg),
                icon: "chart.bar.fill",
                color: .purple
            )
        }
        .padding(.vertical, 8)
        .background(cardBackground)
    }

    // MARK: - Normal Range Card

    private var normalRangeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(metric.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Normal Range")
                    .font(.r(.subheadline, .semibold))
                Text(metric.normalRange)
                    .font(.r(.caption, .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Helpers

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
}
