import Foundation
import SwiftData

@Model
final class FastingSession {
    var startedAt: Date
    var targetEndAt: Date
    var actualEndAt: Date?
    var completed: Bool
    var scheduleType: String
    var createdAt: Date

    init(
        startedAt: Date,
        targetEndAt: Date,
        scheduleType: FastingScheduleType
    ) {
        self.startedAt = startedAt
        self.targetEndAt = targetEndAt
        self.completed = false
        self.scheduleType = scheduleType.rawValue
        self.createdAt = .now
    }

    var isActive: Bool { actualEndAt == nil }

    var actualDurationSeconds: TimeInterval {
        let end = actualEndAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    var targetDurationSeconds: TimeInterval {
        targetEndAt.timeIntervalSince(startedAt)
    }

    var progress: Double {
        guard targetDurationSeconds > 0 else { return 0 }
        return min(actualDurationSeconds / targetDurationSeconds, 1.0)
    }

    var day: Date { Calendar.current.startOfDay(for: startedAt) }
}
