//
//  BurnMetricCardView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import Charts

/// Tappable summary card showing icon, today's value, and a 7-day sparkline.
struct BurnMetricCardView: View {
    let metric: BurnMetric
    let samples: [DailyMetricSample]   // 7-day window
    let currentValue: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticService.impact(.light)
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 10) {

                // Icon
                Image(systemName: metric.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(metric.accentColor)
                    .frame(width: 32, height: 32)
                    .background(metric.accentColor.opacity(0.12))
                    .clipShape(Circle())

                // Value + unit
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(formattedValue)
                            .font(.r(22, .bold))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                        Text(metric.unit)
                            .font(.r(.caption, .regular))
                            .foregroundColor(.secondary)
                    }
                    Text(metric.rawValue)
                        .font(.r(.caption, .regular))
                        .foregroundColor(.secondary)
                }

                // Sparkline
                if samples.isEmpty {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 44)
                } else {
                    MiniLineChartView(samples: samples, color: metric.accentColor)
                        .frame(height: 44)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 10, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private var formattedValue: String {
        if metric == .steps {
            return NumberFormatter.localizedString(
                from: NSNumber(value: Int(currentValue)), number: .decimal
            )
        }
        return "\(Int(currentValue))"
    }
}
