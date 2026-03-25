//
//  ScreenTimeDetailView.swift
//  WellPlate
//
//  Created on 25.02.2026.
//

import SwiftUI

struct ScreenTimeDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let factor: StressFactorResult
    let source: ScreenTimeSource
    /// Caller-supplied hours value; avoids direct ScreenTimeManager singleton reads.
    var currentHours: Double? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        kpiCard
                        scoreMappingCard
                        tipsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Screen Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                }
            }
        }
    }

    // MARK: - KPI Card

    private var kpiCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "iphone")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.cyan)
                .frame(width: 56, height: 56)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currentHoursText)
                        .font(.r(36, .heavy))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("hrs")
                        .font(.r(.title3, .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                sourceBadge
                VStack(spacing: 2) {
                    (Text(String(format: "%.0f", factor.score))
                        .font(.r(22, .bold))
                        .foregroundColor(factor.accentColor)
                    + Text(" /25")
                        .font(.r(.caption, .medium))
                        .foregroundColor(.secondary))
                    Text("stress pts")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var currentHoursText: String {
        switch source {
        case .auto:
            return currentHours.map { String(format: "%.1f", $0) } ?? "—"
        case .none:
            return "< 0.25"
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch source {
        case .auto:
            Text("Live")
                .font(.r(.caption2, .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.cyan))
        case .none:
            Text("Under 15 min")
                .font(.r(.caption2, .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.systemGray5)))
        }
    }

    // MARK: - Score Mapping Card

    private var scoreMappingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Your Score Is Calculated")
                .font(.r(.headline, .semibold))

            Text("Screen time directly adds to your stress score: 2 points per hour, up to 25 points.")
                .font(.r(.caption, .regular))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                scoreMappingRow(hours: "0 h", points: "0 pts", color: .green)
                scoreMappingRow(hours: "2.5 h", points: "5 pts", color: .mint)
                scoreMappingRow(hours: "5 h", points: "10 pts", color: .yellow)
                scoreMappingRow(hours: "8 h", points: "16 pts", color: .orange)
                scoreMappingRow(hours: "12.5 h+", points: "25 pts (max)", color: .red)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func scoreMappingRow(hours: String, points: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(hours)
                .font(.r(.subheadline, .medium))
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)
            Text("→")
                .font(.r(.caption, .regular))
                .foregroundColor(.secondary)
            Text(points)
                .font(.r(.subheadline, .semibold))
                .foregroundColor(color)
            Spacer()
        }
    }

    // MARK: - Tips Card

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tips to Reduce Screen Time")
                    .font(.r(.headline, .semibold))
            }

            tipRow(icon: "moon.fill", color: .indigo,
                   text: "Enable Do Not Disturb during meals and the hour before bed.")
            tipRow(icon: "figure.walk", color: .green,
                   text: "Replace 15 minutes of scrolling with a short walk to lower stress hormones.")
            tipRow(icon: "app.badge", color: .orange,
                   text: "Set App Limits in Screen Time settings to cap your most-used apps.")
        }
        .padding(20)
        .background(cardBackground)
    }

    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(text)
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    }
}
