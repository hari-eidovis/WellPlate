import Foundation
import ActivityKit

@MainActor
final class ActivityManager {

    // MARK: - Singleton

    nonisolated static let shared = ActivityManager()

    // MARK: - State

    private(set) var isFastingActivityActive = false
    private var hasReconnected = false

    // MARK: - Private

    private var fastingActivity: Activity<FastingActivityAttributes>?

    // MARK: - Init

    private nonisolated init() {}

    /// Reconnect to any existing activities on first use.
    private func reconnectIfNeeded() {
        guard !hasReconnected else { return }
        hasReconnected = true
        reconnectFastingActivity()
    }

    // MARK: - Fasting Activity

    /// Start a fasting Live Activity. Called when FastingView detects eating → fasting transition.
    func startFastingActivity(
        scheduleLabel: String,
        fastStartDate: Date,
        targetEndDate: Date
    ) {
        reconnectIfNeeded()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Race-safe: save old ref, nil it, create new, then async-end old
        let oldActivity = fastingActivity
        fastingActivity = nil
        isFastingActivityActive = false

        let attributes = FastingActivityAttributes(scheduleLabel: scheduleLabel)
        let now = Date()
        let elapsed = now.timeIntervalSince(fastStartDate)
        let total = targetEndDate.timeIntervalSince(fastStartDate)
        let progress = total > 0 ? min(elapsed / total, 1.0) : 0

        let state = FastingActivityAttributes.ContentState(
            fastStartDate: fastStartDate,
            targetEndDate: targetEndDate,
            progress: progress,
            isCompleted: false,
            isBroken: false
        )

        let content = ActivityContent(state: state, staleDate: targetEndDate.addingTimeInterval(60))

        do {
            fastingActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isFastingActivityActive = true
        } catch {
            isFastingActivityActive = false
        }

        // Fire-and-forget end of old activity (after new one is created)
        if let oldActivity {
            Task {
                await oldActivity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// End the fasting Live Activity. Called when fast completes or is broken.
    func endFastingActivity(completed: Bool) {
        reconnectIfNeeded()
        Task {
            await endFastingActivityInternal(completed: completed, broken: !completed)
        }
    }

    private func endFastingActivityInternal(completed: Bool, broken: Bool) async {
        guard let activity = fastingActivity else { return }

        var finalState = activity.content.state
        finalState.isCompleted = completed
        finalState.isBroken = broken
        finalState.progress = completed ? 1.0 : finalState.progress

        let content = ActivityContent(state: finalState, staleDate: .now)
        await activity.end(content, dismissalPolicy: .default)

        fastingActivity = nil
        isFastingActivityActive = false
    }

    /// Reconnect to any live fasting activity that survived an app kill.
    private func reconnectFastingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<FastingActivityAttributes>.activities
        if let existing = activities.first {
            fastingActivity = existing
            isFastingActivityActive = true

            // If the activity's target end date has passed, end it
            if existing.content.state.targetEndDate < Date() {
                Task {
                    await endFastingActivityInternal(completed: true, broken: false)
                }
            }
        }
    }

    // MARK: - Breathing Activity

    private var breathingActivity: Activity<BreathingActivityAttributes>?

    func startBreathingActivity(
        sessionName: String,
        totalSteps: Int,
        stepLabel: String,
        firstPhaseName: String,
        firstPhaseEndDate: Date,
        totalSessionDuration: TimeInterval
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = BreathingActivityAttributes(
            sessionName: sessionName,
            totalSteps: totalSteps,
            stepLabel: stepLabel
        )
        let state = BreathingActivityAttributes.ContentState(
            phaseName: firstPhaseName,
            phaseEndDate: firstPhaseEndDate,
            currentStep: 1,
            totalProgress: 0,
            isCompleted: false
        )
        let staleDate = Date().addingTimeInterval(totalSessionDuration + 30)
        let content = ActivityContent(state: state, staleDate: staleDate)

        do {
            breathingActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            breathingActivity = nil
        }
    }

    func updateBreathingActivity(phaseName: String, phaseEndDate: Date, currentStep: Int, totalProgress: Double) {
        guard let activity = breathingActivity else { return }
        let state = BreathingActivityAttributes.ContentState(
            phaseName: phaseName,
            phaseEndDate: phaseEndDate,
            currentStep: currentStep,
            totalProgress: totalProgress,
            isCompleted: false
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func endBreathingActivity() {
        guard let activity = breathingActivity else { return }
        Task {
            var finalState = activity.content.state
            finalState.isCompleted = true
            finalState.totalProgress = 1.0
            await activity.end(ActivityContent(state: finalState, staleDate: .now), dismissalPolicy: .default)
        }
        breathingActivity = nil
    }
}
