import ActivityKit
import WidgetKit
import SwiftUI

struct BreathingLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreathingActivityAttributes.self) { context in
            // LOCK SCREEN
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: context.state.totalProgress)
                        .stroke(Color.indigo.gradient,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "wind")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.sessionName)
                        .font(.system(size: 13, weight: .semibold))

                    if context.state.isCompleted {
                        Text("Session complete")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Text(context.state.phaseName)
                            .font(.system(size: 17, weight: .bold))

                        Text("\(context.attributes.stepLabel) \(context.state.currentStep) of \(context.attributes.totalSteps)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        Text(context.state.phaseName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .contentTransition(.opacity)

                        if !context.state.isCompleted {
                            Text(timerInterval: Date.now...context.state.phaseEndDate,
                                 countsDown: true)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Text("\(context.attributes.stepLabel) \(context.state.currentStep)/\(context.attributes.totalSteps)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            } compactLeading: {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
            } compactTrailing: {
                if !context.state.isCompleted {
                    Text(timerInterval: Date.now...context.state.phaseEndDate,
                         countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.indigo)
                        .frame(width: 36)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
            } minimal: {
                Image(systemName: "wind")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
            }
        }
    }
}
