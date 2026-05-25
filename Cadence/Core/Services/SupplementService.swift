import Foundation
import SwiftUI
import SwiftData
import Combine
import UserNotifications

// MARK: - SupplementService
//
// Manages supplement notification scheduling, adherence tracking, and aggregation.
// Follows the FastingService notification pattern (UNCalendarNotificationTrigger).

@MainActor
final class SupplementService: ObservableObject {

    @Published var notificationsBlocked: Bool = false

    // MARK: - Notification Permission (mirrors FastingService)

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

    // MARK: - Schedule Notifications

    func scheduleNotifications(for supplement: SupplementEntry) {
        let center = UNUserNotificationCenter.current()
        clearNotifications(for: supplement)

        guard !notificationsBlocked,
              supplement.isActive,
              supplement.notificationsEnabled else { return }

        for time in supplement.scheduledTimes {
            let content = UNMutableNotificationContent()
            content.title = "Time for \(supplement.name)"
            content.body = supplement.dosage.isEmpty ? "Tap to mark as taken" : supplement.dosage
            content.sound = .default

            var comps = DateComponents()
            comps.hour = time / 60
            comps.minute = time % 60

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let id = notificationID(for: supplement, time: time)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        WPLogger.home.info("Scheduled \(supplement.scheduledTimes.count) notifications for \(supplement.name)")
    }

    // MARK: - Clear Notifications

    func clearNotifications(for supplement: SupplementEntry) {
        let ids = supplement.scheduledTimes.map { notificationID(for: supplement, time: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func notificationID(for supplement: SupplementEntry, time: Int) -> String {
        "supplement_\(supplement.id.uuidString)_\(time)"
    }

    // MARK: - Adherence Management

    /// Called on app appear. Auto-resolves yesterday's pending → skipped, then creates today's pending logs.
    func createPendingLogs(context: ModelContext, supplements: [SupplementEntry]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 1. Auto-resolve: mark all previous-day "pending" logs as "skipped"
        let allPending = FetchDescriptor<AdherenceLog>(
            predicate: #Predicate { $0.status == "pending" && $0.day < today }
        )
        if let stale = try? context.fetch(allPending) {
            for log in stale {
                log.status = "skipped"
            }
        }

        // 2. Create today's entries for active supplements
        let activeSupplements = supplements.filter { $0.isActive }
        let todayDescriptor = FetchDescriptor<AdherenceLog>(
            predicate: #Predicate { $0.day == today }
        )
        let existingToday = (try? context.fetch(todayDescriptor)) ?? []

        for supplement in activeSupplements {
            // Check if today is an active day (empty = every day)
            if !supplement.activeDays.isEmpty {
                let weekday = cal.component(.weekday, from: Date()) - 1 // 0=Sun..6=Sat
                guard supplement.activeDays.contains(weekday) else { continue }
            }

            for time in supplement.scheduledTimes {
                let alreadyExists = existingToday.contains {
                    $0.supplementID == supplement.id && $0.scheduledMinute == time
                }
                if !alreadyExists {
                    let log = AdherenceLog(
                        supplementName: supplement.name,
                        supplementID: supplement.id,
                        day: Date(),
                        scheduledMinute: time
                    )
                    context.insert(log)
                }
            }
        }

        try? context.save()
    }

    /// Toggle a dose between taken and pending.
    func markDose(context: ModelContext, log: AdherenceLog, status: String) {
        log.status = status
        log.takenAt = status == "taken" ? Date() : nil
        try? context.save()
        if status == "taken" {
            HapticService.notify(.success)
        }
    }

    // MARK: - Aggregation

    func todayAdherencePercent(todayLogs: [AdherenceLog]) -> Double {
        guard !todayLogs.isEmpty else { return 0 }
        let taken = todayLogs.filter { $0.status == "taken" }.count
        return Double(taken) / Double(todayLogs.count)
    }

    func currentStreak(allLogs: [AdherenceLog]) -> Int {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: allLogs) { $0.day }
        var streak = 0
        var checkDate = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()

        while true {
            let dayLogs = grouped[checkDate] ?? []
            guard !dayLogs.isEmpty else { break }
            let allTaken = dayLogs.allSatisfy { $0.status == "taken" }
            guard allTaken else { break }
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    func adherenceByDay(allLogs: [AdherenceLog]) -> [Date: Double] {
        let grouped = Dictionary(grouping: allLogs) { $0.day }
        return grouped.compactMapValues { dayLogs in
            guard !dayLogs.isEmpty else { return nil }
            let taken = dayLogs.filter { $0.status == "taken" }.count
            return Double(taken) / Double(dayLogs.count)
        }
    }
}
