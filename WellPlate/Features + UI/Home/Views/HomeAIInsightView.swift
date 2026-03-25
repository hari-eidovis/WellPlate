import SwiftUI
import Charts

// MARK: - HomeAIInsightView
//
// Editorial "Spotify Wrapped"-style stress insight report.
// Three display states: loading, insufficient data, loaded report.

struct HomeAIInsightView: View {
    @ObservedObject var insightService: StressInsightService

    var body: some View {
        ZStack {
            if insightService.isGenerating {
                loadingView
            } else if insightService.insufficientData {
                insufficientDataView
            } else if let report = insightService.report {
                reportView(report)
            } else {
                // Transient state: generation not yet started (should be brief)
                loadingView
            }
        }
        .navigationTitle("AI Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Analyzing your last 10 days...")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Insufficient Data

    private var insufficientDataView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.brand.opacity(0.6))

            Text("Not Enough Data")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Log your stress for a few more days to unlock AI insights.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Report

    private func reportView(_ report: StressInsightReport) -> some View {
        ScrollView {
            VStack(spacing: 14) {

                // Hero
                InsightHeroCard(headline: report.headline)
                    .insightEntrance(index: 0)

                // Charts
                InsightStressTrendCard(days: report.days)
                    .insightEntrance(index: 1)

                if report.days.contains(where: { $0.sleepHours != nil }) {
                    InsightSleepChartCard(days: report.days)
                        .insightEntrance(index: 2)
                }

                if report.days.contains(where: { $0.steps != nil }) {
                    InsightActivityChartCard(days: report.days)
                        .insightEntrance(index: 3)
                }

                // Summary
                InsightTextCard(
                    label: "Overview",
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: AppColors.brand,
                    bodyText: report.summary
                )
                .insightEntrance(index: 4)

                // Positive factor
                InsightFactorCard(
                    label: "What helped",
                    factor: report.strongestPositiveFactor,
                    isPositive: true
                )
                .insightEntrance(index: 5)

                // Negative factor
                InsightFactorCard(
                    label: "What drove stress",
                    factor: report.strongestNegativeFactor,
                    isPositive: false
                )
                .insightEntrance(index: 6)

                // Suggestions
                ForEach(Array(report.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                    InsightSuggestionCard(text: suggestion)
                        .insightEntrance(index: 7 + idx)
                }

                // Caution note
                if !report.cautionNote.isEmpty {
                    InsightCautionCard(note: report.cautionNote)
                        .insightEntrance(index: 7 + report.suggestions.count)
                }

                // Footer
                InsightFooter(report: report, insightService: insightService)
                    .insightEntrance(index: 8 + report.suggestions.count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - InsightHeroCard

private struct InsightHeroCard: View {
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                Text("YOUR LAST 10 DAYS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                    .tracking(1.2)
            }
            Text(headline)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.brand.opacity(0.08))
        )
    }
}

// MARK: - InsightTextCard

private struct InsightTextCard: View {
    let label: String
    let icon: String
    let iconColor: Color
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .tracking(1.0)
            }
            Text(bodyText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }
}

// MARK: - InsightFactorCard

private struct InsightFactorCard: View {
    let label: String
    let factor: String
    let isPositive: Bool

    private var accentColor: Color { isPositive ? AppColors.success : AppColors.error }
    private var icon: String { isPositive ? "arrow.down.circle.fill" : "arrow.up.circle.fill" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .tracking(1.0)
                Text(factor)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
    }
}

// MARK: - InsightSuggestionCard

private struct InsightSuggestionCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.brand)
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(cardBackground)
    }
}

// MARK: - InsightCautionCard

private struct InsightCautionCard: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.warning)
            Text(note)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.warning.opacity(0.08))
        )
    }
}

// MARK: - InsightFooter

private struct InsightFooter: View {
    let report: StressInsightReport
    @ObservedObject var insightService: StressInsightService

    private var generatedAtText: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "Generated today at \(f.string(from: report.generatedAt))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(generatedAtText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)

            Button {
                HapticService.impact(.light)
                Task { await insightService.clearAndRegenerate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Regenerate")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AppColors.brand)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppColors.brand.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .disabled(insightService.isGenerating)
            .appDisabled(insightService.isGenerating)
        }
        .padding(.top, 8)
    }
}

// MARK: - InsightStressTrendCard

private struct InsightStressTrendCard: View {
    let days: [StressInsightDaySummary]

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Double
    }

    private var points: [ChartPoint] {
        days.compactMap { d in
            guard let s = d.stressScore else { return nil }
            return ChartPoint(date: d.date, score: s)
        }
    }

    private var avg: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.score).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                Text("STRESS TREND")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                    .tracking(1.0)
                Spacer()
                Text("Avg \(Int(avg))/100")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(points) { p in
                    AreaMark(
                        x: .value("Day", p.date, unit: .day),
                        y: .value("Stress", p.score)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [AppColors.brand.opacity(0.25), AppColors.brand.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", p.date, unit: .day),
                        y: .value("Stress", p.score)
                    )
                    .foregroundStyle(AppColors.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", p.date, unit: .day),
                        y: .value("Stress", p.score)
                    )
                    .foregroundStyle(stressColor(p.score))
                    .symbolSize(30)
                }

                RuleMark(y: .value("Mid", 50))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private func stressColor(_ score: Double) -> Color {
        if score < 40 { return AppColors.success }
        if score < 65 { return AppColors.warning }
        return AppColors.error
    }
}

// MARK: - InsightSleepChartCard

private struct InsightSleepChartCard: View {
    let days: [StressInsightDaySummary]

    private struct Bar: Identifiable {
        let id = UUID()
        let date: Date
        let hours: Double
        let deepHours: Double?
    }

    private var bars: [Bar] {
        days.compactMap { d in
            guard let h = d.sleepHours else { return nil }
            return Bar(date: d.date, hours: h, deepHours: d.deepSleepHours)
        }
    }

    private var avg: Double {
        guard !bars.isEmpty else { return 0 }
        return bars.map(\.hours).reduce(0, +) / Double(bars.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("SLEEP")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.indigo)
                    .tracking(1.0)
                Spacer()
                Text(String(format: "Avg %.1fh", avg))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(bars) { b in
                    BarMark(
                        x: .value("Day", b.date, unit: .day),
                        y: .value("Sleep", b.hours)
                    )
                    .foregroundStyle(sleepColor(b.hours))
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Target", 8.0))
                    .foregroundStyle(AppColors.success.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("8h")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(AppColors.success)
                    }
            }
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 4, 8]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 110)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private func sleepColor(_ hours: Double) -> Color {
        if hours >= 7.5 { return AppColors.success }
        if hours >= 6.0 { return AppColors.warning }
        return AppColors.error
    }
}

// MARK: - InsightActivityChartCard

private struct InsightActivityChartCard: View {
    let days: [StressInsightDaySummary]

    private struct Bar: Identifiable {
        let id = UUID()
        let date: Date
        let steps: Int
    }

    private var bars: [Bar] {
        days.compactMap { d in
            guard let s = d.steps else { return nil }
            return Bar(date: d.date, steps: s)
        }
    }

    private var avg: Int {
        guard !bars.isEmpty else { return 0 }
        return bars.map(\.steps).reduce(0, +) / bars.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.brand)
                    .tracking(1.0)
                Spacer()
                Text("Avg \(avg.formatted()) steps")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(bars) { b in
                    BarMark(
                        x: .value("Day", b.date, unit: .day),
                        y: .value("Steps", b.steps)
                    )
                    .foregroundStyle(stepsColor(b.steps))
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", 10_000))
                    .foregroundStyle(AppColors.success.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("10k")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(AppColors.success)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 110)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private func stepsColor(_ steps: Int) -> Color {
        if steps >= 10_000 { return AppColors.success }
        if steps >= 6_000  { return AppColors.brand }
        if steps >= 3_000  { return AppColors.warning }
        return AppColors.error
    }
}

// MARK: - Shared Card Background

private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color(.systemBackground))
        .appShadow(radius: 12, y: 4)
}

// MARK: - Staggered Entrance Modifier

private struct InsightEntrance: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.78)
                .delay(Double(index) * 0.08),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

private extension View {
    func insightEntrance(index: Int) -> some View {
        modifier(InsightEntrance(index: index))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeAIInsightView(insightService: {
            let svc = StressInsightService()
            svc.report = StressInsightReport(
                headline: "Stress climbed mid-week, then eased off",
                summary: "Over the last 3 days your stress score peaked on Wednesday, likely linked to shorter sleep and higher caffeine. Thursday showed a clear improvement after you hit 8,500 steps.",
                strongestPositiveFactor: "Thursday's physical activity",
                strongestNegativeFactor: "Short sleep on Wednesday (5.2h)",
                suggestions: [
                    "Aim to be in bed by 10:30 PM — even one extra hour of sleep can noticeably lower next-day stress.",
                    "Keep caffeine to 2 cups or fewer on high-demand days."
                ],
                cautionNote: "Sleep data was unavailable for 1 day.",
                generatedAt: Date(),
                isTemplateGenerated: false,
                days: []
            )
            return svc
        }())
    }
}
