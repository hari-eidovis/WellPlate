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

    /// Update the running fasting Live Activity with a fresh progress value.
    /// No-op when no activity is active. Throttling is the caller's
    /// responsibility — the system rate-limits frequent updates anyway.
    func updateFastingActivity(progress: Double) {
        reconnectIfNeeded()
        guard let activity = fastingActivity else { return }
        let clamped = max(0, min(progress, 1.0))
        var state = activity.content.state
        // Avoid no-op churn that still hits the system rate limiter.
        guard abs(state.progress - clamped) > 0.001 else { return }
        state.progress = clamped
        let stale = state.targetEndDate.addingTimeInterval(60)
        let content = ActivityContent(state: state, staleDate: stale)
        Task {
            await activity.update(content)
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
}
