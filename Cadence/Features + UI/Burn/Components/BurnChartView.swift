//
//  BurnChartView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import Charts

/// 7-day bar chart displayed inside the Burn weekly card.
/// Axis style mirrors ProgressInsightsView.
struct BurnChartView: View {
    let samples: [DailyMetricSample]
    let color: Color

    var body: some View {
        Chart {
            ForEach(samples) { s in
                BarMark(
                    x: .value("Date",  s.date, unit: .day),
                    y: .value("Value", s.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(5)
            }
        }
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
                        Text("\(Int(v))")
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
    }
}

/// 30-day bar chart for the detail sheet.
struct DetailBarChartView: View {
    let samples: [DailyMetricSample]
    let color: Color
    let unit: String

    var body: some View {
        Chart {
            ForEach(samples) { s in
                BarMark(
                    x: .value("Date",  s.date, unit: .day),
                    y: .value(unit, s.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.5)],
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
                        Text("\(Int(v))")
                            .font(.r(.caption2, .regular))
                    }
                }
            }
        }
    }
}
