//
//  SleepStageBarView.swift
//  WellPlate
//
//  Created by Hari's Mac on 21.02.2026.
//

import SwiftUI

/// Horizontal proportional bar showing last night's sleep stage breakdown.
struct SleepStageBarView: View {
    let summary: DailySleepSummary

    private var segments: [(stage: SleepStage, hours: Double, pct: Double)] {
        let total = summary.totalHours
        guard total > 0 else { return [] }
        return summary.stageBreakdown.map { entry in
            (entry.stage, entry.hours, (entry.hours / total) * 100)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Proportional bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                        let width = geo.size.width * (seg.hours / summary.totalHours)
                        RoundedRectangle(cornerRadius: idx == 0 ? 8 : (idx == segments.count - 1 ? 8 : 3))
                            .fill(seg.stage.color)
                            .frame(width: max(width - 2, 4))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 14)

            // Legend
            HStack(spacing: 16) {
                ForEach(segments, id: \.stage) { seg in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(seg.stage.color)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(seg.stage.displayName)
                                .font(.r(.caption2, .semibold))
                                .foregroundColor(.primary)
                            Text(String(format: "%.1fh · %.0f%%", seg.hours, seg.pct))
                                .font(.r(.caption2, .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

#Preview {
    SleepStageBarView(summary: DailySleepSummary(
        date: Date(),
        totalHours: 7.5,
        coreHours: 3.5,
        remHours: 1.8,
        deepHours: 2.2
    ))
    .padding()
}
