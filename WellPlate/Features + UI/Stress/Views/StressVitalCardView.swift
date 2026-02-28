//
//  StressVitalCardView.swift
//  WellPlate
//
//  Created on 25.02.2026.
//

import SwiftUI

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
            // Icon
            Image(systemName: metric.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(metric.accentColor)
                .frame(width: 40, height: 40)
                .background(metric.accentColor.opacity(0.12))
                .clipShape(Circle())

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.rawValue)
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(.primary)
                Text("Today's average")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Value + unit + status dot + chevron
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let value = todayValue {
                    Text(String(format: "%.0f", value))
                        .font(.r(17, .bold))
                        .foregroundColor(metric.accentColor)
                        .monospacedDigit()
                    Text(metric.unit)
                        .font(.r(.caption, .medium))
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(metric.statusColor(for: value))
                        .frame(width: 8, height: 8)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                } else {
                    Text("—")
                        .font(.r(17, .bold))
                        .foregroundColor(.secondary)
                }
            }

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 10, y: 4)
        )
    }
}
