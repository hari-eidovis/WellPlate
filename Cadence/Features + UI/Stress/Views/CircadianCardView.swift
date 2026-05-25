//
//  CircadianCardView.swift
//  WellPlate
//

import SwiftUI

struct CircadianCardView: View {

    let result: CircadianService.CircadianResult
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: {
            HapticService.impact(.light)
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(levelColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(levelColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.35))
                }

                if result.hasEnoughData {
                    dataContent
                } else {
                    noDataContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.85))
                    .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Circadian Health: \(Int(result.score)) out of 100, \(result.level.rawValue)")
    }

    // MARK: - Data Content

    private var dataContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Score + level
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Int(result.score))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("/ 100")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(result.level.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(levelColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(levelColor.opacity(0.12))
                    )
            }

            // Sub-score pills
            HStack(spacing: 8) {
                subScorePill(label: "Regularity", value: Int(result.regularityScore), icon: "bed.double.fill")
                if let daylight = result.daylightScore {
                    subScorePill(label: "Daylight", value: Int(daylight), icon: "sun.max.fill")
                } else {
                    noWatchPill
                }
            }

            // Tip
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(result.tip)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - No Data Content

    private var noDataContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Circadian Health")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text("Need 5+ nights of sleep data to calculate your circadian score")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Components

    private func subScorePill(label: String, value: Int, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var noWatchPill: some View {
        VStack(spacing: 4) {
            Image(systemName: "applewatch")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Daylight")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Helpers

    private var levelColor: Color {
        switch result.level {
        case .aligned:   return .green
        case .adjusting: return .orange
        case .disrupted: return .red
        }
    }
}
