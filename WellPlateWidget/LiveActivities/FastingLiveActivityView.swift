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
                    fastingProgressRing(progress: context.state.progress)
                        .frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.scheduleLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        if context.state.isCompleted {
                            Text("Fast complete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        } else if context.state.isBroken {
                            Text("Fast ended early")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        } else {
                            Text(timerInterval: Date.now...context.state.targetEndDate,
                                 countsDown: true)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 24)
                }
            } compactLeading: {
                Image(systemName: "fork.knife")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            } compactTrailing: {
                if context.state.isCompleted || context.state.isBroken {
                    Image(systemName: context.state.isCompleted ? "checkmark" : "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(context.state.isCompleted ? .green : .red)
                } else {
                    Text(timerInterval: Date.now...context.state.targetEndDate,
                         countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.orange)
                        .frame(width: 40)
                }
            } minimal: {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<FastingActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            fastingProgressRing(progress: context.state.progress)
                .frame(width: 56, height: 56)

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

                    let formatter = Date.FormatStyle.dateTime.hour().minute()
                    Text("Eat window opens at \(context.state.targetEndDate.formatted(formatter))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
    }

    // MARK: - Progress Ring

    @ViewBuilder
    private func fastingProgressRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange.gradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)
        }
    }
}
