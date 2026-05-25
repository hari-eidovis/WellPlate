//
//  VitalChartCardView.swift
//  WellPlate
//

import SwiftUI
import Charts

struct VitalChartCardView: View {

    let metric: VitalMetric
    let todayValue: Double?
    let samples: [DailyMetricSample]
    var onTap: (() -> Void)? = nil

    private var statusText: String {
        guard let v = todayValue else { return "No data" }
        return metric.statusColor(for: v) == .green ? "Normal" : "Elevated"
    }

    private var statusIsNormal: Bool {
        guard let v = todayValue else { return false }
        return metric.statusColor(for: v) == .green
    }

    private var last7: [DailyMetricSample] {
        Array(samples.sorted { $0.date < $1.date }.suffix(7))
    }

    private var yRange: (min: Double, max: Double) {
        let vals = last7.map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else {
            let v = vals.first ?? 70
            return (v - 20, v + 20)
        }
        let pad = (hi - lo) * 0.25
        return (lo - pad, hi + pad)
    }

    private var yTicks: [Double] {
        let span = yRange.max - yRange.min
        let step: Double = span <= 20 ? 5 : span <= 60 ? 10 : span <= 120 ? 25 : 50
        var ticks: [Double] = []
        var v = (yRange.min / step).rounded(.up) * step
        while v <= yRange.max { ticks.append(v); v += step }
        return ticks
    }

    var body: some View {
        Button {
            HapticService.impact(.light)
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text(metric.rawValue.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .tracking(0.8)
                    Spacer()
                    if todayValue != nil {
                        HStack(spacing: 4) {
                            Image(systemName: statusIsNormal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(statusText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                }
                .padding(.bottom, 2)

                // Big value
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let v = todayValue {
                        Text("\(Int(v))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                        Text(metric.unit.lowercased())
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("—")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.bottom, 12)

                // Chart
                if last7.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.25))
                        Text("No data yet")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(height: 120, alignment: .center)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 4) {
                        Chart {
                            let avg = last7.map(\.value).reduce(0, +) / Double(last7.count)
                            RuleMark(y: .value("Avg", avg))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1))

                            ForEach(last7) { s in
                                BarMark(
                                    x: .value("Day", s.date, unit: .day),
                                    y: .value("Val", s.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.black.opacity(0.25)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .cornerRadius(3)
                            }
                        }
                        .chartYScale(domain: yRange.min...yRange.max)
                        .chartYAxis {
                            AxisMarks(values: yTicks) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.white.opacity(0.15))
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.55))
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { value in
                                AxisValueLabel {
                                    if let d = value.as(Date.self) {
                                        Text(d, format: .dateTime.weekday(.narrow))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.55))
                                    }
                                }
                            }
                        }
                        .chartLegend(.hidden)
                        .frame(height: 120)

                        HStack {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                            Image(systemName: "moon.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(metric.accentColor.gradient)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}
