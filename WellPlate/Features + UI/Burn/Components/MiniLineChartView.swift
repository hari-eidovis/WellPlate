//
//  MiniLineChartView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import Charts

/// Compact 7-day sparkline used inside metric cards.
/// Matches the LineMark + AreaMark gradient pattern from ProgressInsightsView.
struct MiniLineChartView: View {
    let samples: [DailyMetricSample]
    let color: Color

    var body: some View {
        Chart {
            ForEach(samples) { s in
                LineMark(
                    x: .value("Date",  s.date, unit: .day),
                    y: .value("Value", s.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date",  s.date, unit: .day),
                    y: .value("Value", s.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

#Preview {
    let samples = (0..<7).map { i -> DailyMetricSample in
        let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        return DailyMetricSample(date: date, value: Double.random(in: 200...600))
    }
    MiniLineChartView(samples: samples.reversed(), color: AppColors.brand)
        .frame(height: 50)
        .padding()
}
