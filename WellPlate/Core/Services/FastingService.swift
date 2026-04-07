import Foundation
import Combine
import UserNotifications

// MARK: - Fasting State

enum FastingState: Equatable {
    case fasting(remaining: TimeInterval)
    case eating(remaining: TimeInterval)
    case notConfigured

    static func == (lhs: FastingState, rhs: FastingState) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured): return true
        case (.fasting, .fasting): return true
        case (.eating, .eating): return true
        default: return false
        }
    }

    var isFasting: Bool {
        if case .fasting = self { return true }
        return false
    }

    var isEating: Bool {
        if case .eating = self { return true }
        return false
    }
}

// MARK: - FastingService

@MainActor
final class FastingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentState: FastingState = .notConfigured
    @Published private(set) var progress: Double = 0
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var isCaffeineCutoffActive: Bool = false
    @Published var notificationsBlocked: Bool = false

    // MARK: - Private

    private var timerCancellable: AnyCancellable?
    private var currentSchedule: FastingSchedule?

    // MARK: - Notification IDs

    private static let notifWindowClosed   = "wp.fasting.windowClosed"
    private static let notifOneHourLeft    = "wp.fasting.oneHourLeft"
    private static let notifComplete       = "wp.fasting.complete"
    private static let notifCaffeineCutoff = "wp.fasting.caffeineCutoff"

    // MARK: - Configure

    /// Computes current fasting state from schedule times vs. now and starts the timer.
    func configure(schedule: FastingSchedule, activeSession: FastingSession?) {
        guard schedule.isActive else {
            stop()
            return
        }

        currentSchedule = schedule
        updateState(schedule: schedule, activeSession: activeSession)
        startTimer(schedule: schedule, activeSession: activeSession)
    }

    /// Stops the timer and resets to not configured.
    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        currentState = .notConfigured
        progress = 0
        timeRemaining = 0
        isCaffeineCutoffActive = false
        currentSchedule = nil
    }

    // MARK: - Timer

    private func startTimer(schedule: FastingSchedule, activeSession: FastingSession?) {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateState(schedule: schedule, activeSession: activeSession)
            }
    }

    private func updateState(schedule: FastingSchedule, activeSession: FastingSession?) {
        let now = Date()
        let cal = Calendar.current

        // Compute today's eat window start/end as full Date
        let eatStart = eatWindowStart(for: now, schedule: schedule, calendar: cal)
        let eatEnd = eatStart.addingTimeInterval(schedule.eatWindowDurationHours * 3600)

        // Determine current state
        if now >= eatStart && now < eatEnd {
            // Currently in eat window
            let remaining = eatEnd.timeIntervalSince(now)
            currentState = .eating(remaining: remaining)
            timeRemaining = remaining
            let elapsed = now.timeIntervalSince(eatStart)
            let total = schedule.eatWindowDurationHours * 3600
            progress = min(elapsed / total, 1.0)
        } else {
            // Currently fasting
            let fastEnd: Date
            if now >= eatEnd {
                // Past today's eat window — fast ends at tomorrow's eat window start
                let tomorrowEatStart = cal.date(byAdding: .day, value: 1, to: eatStart) ?? eatStart
                fastEnd = tomorrowEatStart
            } else {
                // Before today's eat window — fast ends at today's eat window start
                fastEnd = eatStart
            }

            let remaining = fastEnd.timeIntervalSince(now)
            currentState = .fasting(remaining: remaining)
            timeRemaining = remaining

            // Progress based on active session if available, otherwise from schedule
            if let session = activeSession, session.isActive {
                progress = session.progress
            } else {
                let fastDuration = schedule.fastDurationHours * 3600
                let elapsed = fastDuration - remaining
                progress = min(max(elapsed / fastDuration, 0), 1.0)
            }
        }

        // Caffeine cutoff
        if schedule.caffeineCutoffEnabled {
            let cutoffTime = eatEnd.addingTimeInterval(-Double(schedule.caffeineCutoffMinutesBefore) * 60)
            isCaffeineCutoffActive = now >= cutoffTime && now < eatEnd
        } else {
            isCaffeineCutoffActive = false
        }
    }

    /// Computes the eat window start Date for a given day based on the schedule.
    private func eatWindowStart(for date: Date, schedule: FastingSchedule, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: schedule.eatWindowStartHour,
                             minute: schedule.eatWindowStartMinute,
                             second: 0, of: startOfDay) ?? startOfDay
    }

    /// Computes the most recent past eat window end time (for retroactive session creation).
    func mostRecentEatWindowEnd(for schedule: FastingSchedule) -> Date {
        let cal = Calendar.current
        let now = Date()
        let todayEatStart = eatWindowStart(for: now, schedule: schedule, calendar: cal)
        let todayEatEnd = todayEatStart.addingTimeInterval(schedule.eatWindowDurationHours * 3600)

        if now >= todayEatEnd {
            return todayEatEnd
        } else {
            // Yesterday's eat window end
            let yesterdayEatStart = cal.date(byAdding: .day, value: -1, to: todayEatStart) ?? todayEatStart
            return yesterdayEatStart.addingTimeInterval(schedule.eatWindowDurationHours * 3600)
        }
    }

    /// Computes the next eat window start (target end for a new fasting session).
    func nextEatWindowStart(for schedule: FastingSchedule) -> Date {
        let cal = Calendar.current
        let now = Date()
        let todayEatStart = eatWindowStart(for: now, schedule: schedule, calendar: cal)
        let todayEatEnd = todayEatStart.addingTimeInterval(schedule.eatWindowDurationHours * 3600)

        if now < todayEatStart {
            return todayEatStart
        } else {
            // Next day's eat window start
            return cal.date(byAdding: .day, value: 1, to: todayEatStart) ?? todayEatEnd
        }
    }

    // MARK: - Notifications

    /// Request notification permission. Called when user first activates a schedule.
    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                notificationsBlocked = !granted
            } catch {
                notificationsBlocked = true
            }
        case .denied:
            notificationsBlocked = true
        case .authorized, .provisional, .ephemeral:
            notificationsBlocked = false
        @unknown default:
            notificationsBlocked = false
        }
    }

    /// Schedule all fasting notifications for the given schedule.
    func scheduleNotifications(for schedule: FastingSchedule) {
        let center = UNUserNotificationCenter.current()
        clearNotifications()

        guard !notificationsBlocked, schedule.isActive else { return }

        let cal = Calendar.current
        let eatStartDate = eatWindowStart(for: Date(), schedule: schedule, calendar: cal)
        let eatEndDate = eatStartDate.addingTimeInterval(schedule.eatWindowDurationHours * 3600)
        let fastEndDate = cal.date(byAdding: .day, value: 1, to: eatStartDate) ?? eatStartDate

        // 1. Eat window closed (fast starts)
        let eatEndComps = cal.dateComponents([.hour, .minute], from: eatEndDate)
        let windowClosedContent = UNMutableNotificationContent()
        windowClosedContent.title = "Eating Window Closed"
        windowClosedContent.body = "Your \(schedule.resolvedScheduleType.label) fast has begun."
        windowClosedContent.sound = .default
        let windowClosedTrigger = UNCalendarNotificationTrigger(dateMatching: eatEndComps, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.notifWindowClosed,
                                         content: windowClosedContent, trigger: windowClosedTrigger))

        // 2. One hour before fast ends
        let oneHourBeforeEnd = fastEndDate.addingTimeInterval(-3600)
        let oneHourComps = cal.dateComponents([.hour, .minute], from: oneHourBeforeEnd)
        let oneHourContent = UNMutableNotificationContent()
        oneHourContent.title = "1 Hour Left"
        oneHourContent.body = "Your fast ends in 1 hour."
        oneHourContent.sound = .default
        let oneHourTrigger = UNCalendarNotificationTrigger(dateMatching: oneHourComps, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.notifOneHourLeft,
                                         content: oneHourContent, trigger: oneHourTrigger))

        // 3. Fast complete (eat window opens)
        let eatStartComps = cal.dateComponents([.hour, .minute], from: eatStartDate)
        let completeContent = UNMutableNotificationContent()
        completeContent.title = "Fast Complete"
        completeContent.body = "Your eating window is open."
        completeContent.sound = .default
        let completeTrigger = UNCalendarNotificationTrigger(dateMatching: eatStartComps, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.notifComplete,
                                         content: completeContent, trigger: completeTrigger))

        // 4. Caffeine cutoff (optional)
        if schedule.caffeineCutoffEnabled {
            let cutoffDate = eatEndDate.addingTimeInterval(-Double(schedule.caffeineCutoffMinutesBefore) * 60)
            let cutoffComps = cal.dateComponents([.hour, .minute], from: cutoffDate)
            let cutoffContent = UNMutableNotificationContent()
            cutoffContent.title = "Caffeine Cutoff"
            cutoffContent.body = "Last call for caffeine — cutoff is now."
            cutoffContent.sound = .default
            let cutoffTrigger = UNCalendarNotificationTrigger(dateMatching: cutoffComps, repeats: true)
            center.add(UNNotificationRequest(identifier: Self.notifCaffeineCutoff,
                                             content: cutoffContent, trigger: cutoffTrigger))
        }
    }

    /// Clear all fasting notifications.
    func clearNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            Self.notifWindowClosed,
            Self.notifOneHourLeft,
            Self.notifComplete,
            Self.notifCaffeineCutoff
        ])
    }
}
