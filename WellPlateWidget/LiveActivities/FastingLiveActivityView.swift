import ActivityKit
import WidgetKit
import SwiftUI

struct FastingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            // LOCK SCREEN view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED — tapped/long-pressed
                DynamicIslandExpandedRegion(.leading) {
                    logoProgressRing(progress: context.state.progress,
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
                Image("WellPlate_Logo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                progressRing(progress: context.state.progress,
                             state: context.state,
                             ringSize: 20,
                             lineWidth: 2)
            } minimal: {
                progressRing(progress: context.state.progress,
                             state: context.state,
                             ringSize: 20,
                             lineWidth: 2)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<FastingActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            logoProgressRing(progress: context.state.progress,
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

    // MARK: - Logo + Progress Ring

    @ViewBuilder
    private func logoProgressRing(progress: Double,
                                  state: FastingActivityAttributes.ContentState,
                                  logoSize: CGFloat,
                                  ringSize: CGFloat,
                                  lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1.0)))
                .stroke(ringColor(for: state).gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image("WellPlate_Logo")
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: logoSize, height: logoSize)
                .clipShape(Circle())
        }
        .frame(width: ringSize, height: ringSize)
    }

    @ViewBuilder
    private func progressRing(progress: Double,
                              state: FastingActivityAttributes.ContentState,
                              ringSize: CGFloat,
                              lineWidth: CGFloat) -> some View {
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
}
