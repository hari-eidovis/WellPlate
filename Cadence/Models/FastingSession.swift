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

    // v1 additive fields (optional — SwiftData auto-migrates additive optionals).
    // `completed: Bool` is retained for backward compatibility; new code prefers
    // `resolvedStatus` (see FastingCompletionStatus.swift).
    var completionStatus: String? = nil
    var contextualHRV: Double? = nil
    var contextualSleepScore: Int? = nil

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

    convenience init(
        startedAt: Date = .now,
        targetHours: Double,
        scheduleType: FastingScheduleType
    ) {
        let safeTargetHours = max(1, targetHours)
        self.init(
            startedAt: startedAt,
            targetEndAt: startedAt.addingTimeInterval(safeTargetHours * 3600),
            scheduleType: scheduleType
        )
    }

    var isActive: Bool { actualEndAt == nil }

    var actualDurationSeconds: TimeInterval {
        let end = actualEndAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    var actualDurationHours: Double {
        actualDurationSeconds / 3600.0
    }

    var targetDurationSeconds: TimeInterval {
        targetEndAt.timeIntervalSince(startedAt)
    }

    var targetDurationHours: Double {
        targetDurationSeconds / 3600.0
    }

    var progress: Double {
        guard targetDurationSeconds > 0 else { return 0 }
        return min(actualDurationSeconds / targetDurationSeconds, 1.0)
    }

    var day: Date { Calendar.current.startOfDay(for: startedAt) }
}
