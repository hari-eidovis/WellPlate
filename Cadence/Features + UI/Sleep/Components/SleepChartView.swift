//
//  SleepChartView.swift
//  WellPlate
//
//  Created by Hari's Mac on 21.02.2026.
//

import SwiftUI
import Charts

/// 7-day stacked bar chart showing sleep stages per night.
struct SleepChartView: View {
    let summaries: [DailySleepSummary]
    let showStages: Bool

    var body: some View {
        Chart {
            if showStages {
                ForEach(summaries) { s in
                    ForEach(s.stageBreakdown, id: \.stage) { entry in
                        BarMark(
                            x: .value("Date",  s.date, unit: .day),
                            y: .value("Hours", entry.hours)
                        )
                        .foregroundStyle(by: .value("Stage", entry.stage))
                        .cornerRadius(3)
                    }
                }
            } else {
                ForEach(summaries) { s in
                    BarMark(
                        x: .value("Date",  s.date, unit: .day),
                        y: .value("Hours", s.totalHours)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .indigo.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(5)
                }
            }
        }
        .chartForegroundStyleScale([
            SleepStage.deep:        SleepStage.deep.color,
            SleepStage.rem:         SleepStage.rem.color,
            SleepStage.core:        SleepStage.core.color,
            SleepStage.unspecified: SleepStage.unspecified.color
        ])
        .chartLegend(showStages ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(Color.gray.opacity(0.3))
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.weekday(.abbreviated))
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(Color.gray.opacity(0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0fh", v))
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
    }
}

/// 30-day bar chart for the sleep detail sheet.
struct SleepDetailChartView: View {
    let summaries: [DailySleepSummary]

    var body: some View {
        Chart {
            ForEach(summaries) { s in
                BarMark(
                    x: .value("Date",  s.date, unit: .day),
                    y: .value("Hours", s.totalHours)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .indigo.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisGridLine()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0fh", v))
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
    }
}
