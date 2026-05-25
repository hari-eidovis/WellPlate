//
//  StressVitalCardView.swift
//  WellPlate
//

import SwiftUI

/// A flat, emoji-icon row card for showing a single vital metric.
/// Inspired by the reference design: emoji left, label + subtitle in centre,
/// value right — all on a soft translucent background.
struct StressVitalCardView: View {

    let metric: VitalMetric
    let todayValue: Double?
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: {
                HapticService.impact(.light)
                onTap()
            }) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        HStack(spacing: 14) {
            // Emoji-style icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(metric.accentColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: metric.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(metric.accentColor)
            }

            // Label + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                if let value = todayValue {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.0f", value))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                        Text(metric.unit)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                    }
                } else {
                    Text("No data")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status dot + chevron
            HStack(spacing: 8) {
                if let value = todayValue {
                    Circle()
                        .fill(metric.statusColor(for: value))
                        .frame(width: 9, height: 9)
                }
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground).opacity(0.85))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}
