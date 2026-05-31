import SwiftUI

// MARK: - HomeStressScoreCard
//
// Home dashboard section surfacing today's stress score: a large "NN /100"
// headline followed by a row of context pills (factor coverage, day-over-day
// strain, and the HRV/RHR calibrator). Mirrors the score header that used to
// live atop the Stress tab. Renders directly on the Home background (no card
// chrome); tapping opens the Stress tab for the full breakdown.
//
// Pills wrap to a second line via `ViewThatFits` when the row is too narrow to
// hold all three (e.g. on smaller devices).

struct HomeStressScoreCard: View {

    @ObservedObject var viewModel: StressViewModel
    var onTap: () -> Void

    /// True while we expect a score but the first compute hasn't produced one
    /// yet. Mirrors `HomeView.liveStressScore`'s convention of treating a
    /// non-positive `totalScore` as "not loaded". Stays false when HealthKit is
    /// unauthorized (and not mock), since no score will ever arrive there.
    private var isAwaitingScore: Bool {
        (viewModel.isAuthorized || viewModel.usesMockData) && viewModel.totalScore <= 0
    }

    var body: some View {
        Button(action: { HapticService.impact(.light); onTap() }) {
            VStack(alignment: .leading, spacing: 12) {
                score
                pills
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Until the first compute lands, redact the "NN /100" + pills into a
            // shimmering placeholder skeleton rather than flashing a misleading "0".
            .redacted(reason: isAwaitingScore ? .placeholder : [])
            .shimmering(active: isAwaitingScore)
        }
        .buttonStyle(.plain)
        .disabled(isAwaitingScore)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAwaitingScore
            ? "Stress score loading"
            : "Stress score \(Int(viewModel.totalScore.rounded())) out of 100")
        .accessibilityHint("Opens the Stress tab")
    }

    // MARK: - Score

    private var score: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(Int(viewModel.totalScore.rounded()))")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text("/100")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Pills

    private var pills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                factorPill
                strainPill
                calibratorChip
            }
            VStack(alignment: .leading, spacing: 8) {
                factorPill
                HStack(spacing: 8) {
                    strainPill
                    calibratorChip
                }
            }
        }
    }

    /// "N of 13 factors logged" with a confidence-gauge glyph.
    private var factorPill: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.stressConfidence.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text("\(viewModel.factorCoverage) of 12 factors logged")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(0.2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(.systemGray6)))
    }

    private var calibratorChip: some View {
        CalibratorChip(
            calibrator: viewModel.calibratorMultiplier,
            hasBaseline: viewModel.todayHRV != nil || viewModel.todayRestingHR != nil
        )
    }

    /// Day-over-day score change vs yesterday. Hidden without a prior baseline.
    @ViewBuilder
    private var strainPill: some View {
        if let delta = strainDeltaPercent {
            let isUp = delta >= 0
            let color: Color = isUp ? Color(hex: "E08A2B") : Color(hex: "1FA971")
            HStack(spacing: 2) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(isUp ? "+" : "")\(delta)% strain")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.13)))
        }
    }

    /// Rounded integer % change in stress score from yesterday's most recent
    /// reading to today's, or nil when there's no comparison data.
    private var strainDeltaPercent: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return nil }

        let yesterdayReadings = viewModel.weekReadings.filter {
            cal.isDate($0.timestamp, inSameDayAs: yesterday)
        }
        guard let yesterdayScore = yesterdayReadings.last?.score, yesterdayScore > 0 else { return nil }

        let current = viewModel.totalScore
        guard current > 0 else { return nil }

        let pct = ((current - yesterdayScore) / yesterdayScore) * 100
        let rounded = Int(pct.rounded())
        return rounded == 0 ? nil : rounded
    }
}
