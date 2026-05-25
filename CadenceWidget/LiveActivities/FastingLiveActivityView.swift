import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

struct FastingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            // LOCK SCREEN / WATCH view — switches on activityFamily
            FastingLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED — tapped/long-pressed
                DynamicIslandExpandedRegion(.leading) {
                    LogoProgressRing(progress: context.state.progress,
                                     state: context.state,
                                     logoSize: 46,
                                     ringSize: 56,
                                     lineWidth: 4)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(percentLabel(for: context.state))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                            .monospacedDigit()
                        Text("complete")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.scheduleLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))

                        if context.state.isCompleted {
                            Text("Fast complete")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.green)
                        } else if context.state.isBroken {
                            Text("Fast ended early")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.red)
                        } else {
                            Text(timerInterval: Date.now...context.state.targetEndDate,
                                 countsDown: true)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isCompleted && !context.state.isBroken {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                            Text("Eat window opens \(eatWindowLabel(for: context.state.targetEndDate))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
            } compactLeading: {
                Image(.cadenceLogo)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                ProgressRing(progress: context.state.progress,
                             state: context.state,
                             ringSize: 20,
                             lineWidth: 2)
            } minimal: {
                ProgressRing(progress: context.state.progress,
                             state: context.state,
                             ringSize: 20,
                             lineWidth: 2)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Lock Screen / Watch View

private struct FastingLockScreenView: View {
    let context: ActivityViewContext<FastingActivityAttributes>
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        switch activityFamily {
        case .small:
            watchView
        default:
            phoneView
        }
    }

    @ViewBuilder
    private var phoneView: some View {
        HStack(spacing: 16) {
            LogoProgressRing(progress: context.state.progress,
                             state: context.state,
                             logoSize: 46,
                             ringSize: 56,
                             lineWidth: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.scheduleLabel)
                    .font(.system(size: 14, weight: .semibold))

                if context.state.isCompleted {
                    Text("Fast complete")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                } else if context.state.isBroken {
                    Text("Fast ended early")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.red)
                } else {
                    Text(timerInterval: Date.now...context.state.targetEndDate,
                         countsDown: true)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text("Eat window opens at \(eatWindowLabel(for: context.state.targetEndDate))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
    }

    // Watch (.small) family — tiny canvas, logo bytes baked in via UIImage so the
    // view archive shipped to Apple Watch carries pixels, not an asset-name lookup.
    @ViewBuilder
    private var watchView: some View {
        HStack(spacing: 8) {
            WatchLogoRing(progress: context.state.progress,
                          state: context.state)

            VStack(alignment: .leading, spacing: 1) {
                Text(context.attributes.scheduleLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                if context.state.isCompleted {
                    Text("Complete")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                } else if context.state.isBroken {
                    Text("Ended early")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                } else {
                    Text(timerInterval: Date.now...context.state.targetEndDate,
                         countsDown: true)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .activityBackgroundTint(.black.opacity(0.7))
    }
}

// MARK: - Logo + Progress Ring (phone / Dynamic Island)

private struct LogoProgressRing: View {
    let progress: Double
    let state: FastingActivityAttributes.ContentState
    let logoSize: CGFloat
    let ringSize: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1.0)))
                .stroke(ringColor(for: state).gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(.cadenceLogo)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: logoSize, height: logoSize)
                .clipShape(Circle())
        }
        .frame(width: ringSize, height: ringSize)
    }
}

private struct ProgressRing: View {
    let progress: Double
    let state: FastingActivityAttributes.ContentState
    let ringSize: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1.0)))
                .stroke(ringColor(for: state).gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: ringSize, height: ringSize)
    }
}

// Watch-targeted ring: loads the logo via UIImage so the rendered bitmap is
// embedded in the view archive shipped to Apple Watch (asset-by-name lookup
// fails in that transport and renders as a blank rectangle).
private struct WatchLogoRing: View {
    let progress: Double
    let state: FastingActivityAttributes.ContentState

    private let logoSize: CGFloat = 28
    private let ringSize: CGFloat = 36
    private let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1.0)))
                .stroke(ringColor(for: state).gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let uiImage = UIImage(named: "Cadence_Logo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(Circle())
            }
        }
        .frame(width: ringSize, height: ringSize)
    }
}

// MARK: - Helpers

private func ringColor(for state: FastingActivityAttributes.ContentState) -> Color {
    if state.isCompleted { return .green }
    if state.isBroken { return .red }
    return .orange
}

private func percentLabel(for state: FastingActivityAttributes.ContentState) -> String {
    if state.isCompleted { return "100%" }
    let clamped = max(0, min(state.progress, 1.0))
    return "\(Int((clamped * 100).rounded()))%"
}

private func eatWindowLabel(for date: Date) -> String {
    let formatter = Date.FormatStyle.dateTime.hour().minute()
    return date.formatted(formatter)
}
