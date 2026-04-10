import SwiftUI

struct VitalsSection: View {
    let data: ReportData

    private var availableVitals: [VitalMetric] {
        data.context.availableVitals.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        ReportSectionCard(title: "Vitals", domain: .stress) {
            ForEach(availableVitals) { metric in
                let points = vitalPoints(for: metric)
                if !points.isEmpty {
                    VitalTrendChart(points: points, metric: metric)
                }
            }
        }
    }

    private func vitalPoints(for metric: VitalMetric) -> [DailyMetricSample] {
        data.context.days.compactMap { d -> DailyMetricSample? in
            let value: Double?
            switch metric {
            case .heartRate:        value = d.heartRateAvg
            case .restingHeartRate: value = d.restingHeartRateAvg
            case .hrv:              value = d.hrvAvg
            case .systolicBP:       value = d.systolicBPAvg
            case .diastolicBP:      value = d.diastolicBPAvg
            case .respiratoryRate:  value = d.respiratoryRateAvg
            }
            guard let v = value else { return nil }
            return DailyMetricSample(date: d.date, value: v)
        }
    }
}
