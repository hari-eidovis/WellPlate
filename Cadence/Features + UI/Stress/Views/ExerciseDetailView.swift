//
//  ExerciseDetailView.swift
//  WellPlate
//
//  Created on 25.02.2026.
//

import SwiftUI
import Charts

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let stepsSamples: [DailyMetricSample]
    let energySamples: [DailyMetricSample]

    @State private var selectedMetric: BurnMetric = .steps

    private var activeSamples: [DailyMetricSample] {
        selectedMetric == .steps ? stepsSamples : energySamples
    }

    private var todaySteps: Double? {
        stepsSamples.first(where: { Calendar.current.isDateInToday($0.date) })?.value
    }

    private var todayEnergy: Double? {
        energySamples.first(where: { Calendar.current.isDateInToday($0.date) })?.value
    }

    private var stats: (min: Double, max: Double, avg: Double) {
        let values = activeSamples.map(\.value)
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
                        kpiHeader
                        pickerCard
                        chartCard
                        statsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Dual KPI Header

    private var kpiHeader: some View {
        HStack(spacing: 12) {
            kpiTile(
                icon: BurnMetric.steps.systemImage,
                color: BurnMetric.steps.accentColor,
                label: "Steps",
                value: todaySteps.map { NumberFormatter.localizedString(from: NSNumber(value: Int($0)), number: .decimal) } ?? "—",
                unit: ""
            )
            kpiTile(
                icon: BurnMetric.activeEnergy.systemImage,
                color: BurnMetric.activeEnergy.accentColor,
                label: "Active Energy",
                value: todayEnergy.map { "\(Int($0))" } ?? "—",
                unit: "kcal"
            )
        }
    }

    private func kpiTile(icon: String, color: Color, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                Text(label)
                    .font(.r(.caption, .medium))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.r(28, .heavy))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.r(.caption, .semibold))
                        .foregroundColor(.secondary)
                }
            }
            Text("Today")
                .font(.r(.caption2, .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Picker

    private var pickerCard: some View {
        Picker("Metric", selection: $selectedMetric) {
            Text("Steps").tag(BurnMetric.steps)
            Text("Energy").tag(BurnMetric.activeEnergy)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 2)
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days")
                .font(.r(.headline, .semibold))

            if activeSamples.isEmpty {
                emptyState
            } else {
                DetailBarChartView(
                    samples: activeSamples,
                    color: selectedMetric.accentColor,
                    unit: selectedMetric.unit
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
                color: selectedMetric.accentColor
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
                Text(selectedMetric.unit)
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func formattedValue(_ v: Double) -> String {
        if selectedMetric == .steps {
            return NumberFormatter.localizedString(from: NSNumber(value: Int(v)), number: .decimal)
        }
        return "\(Int(v))"
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
