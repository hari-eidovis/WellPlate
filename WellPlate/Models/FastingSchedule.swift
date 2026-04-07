import Foundation
import SwiftData

/// Fasting schedule preset types.
enum FastingScheduleType: String, CaseIterable, Identifiable {
    case ratio16_8  = "16:8"
    case ratio14_10 = "14:10"
    case ratio18_6  = "18:6"
    case ratio20_4  = "20:4"
    case custom     = "Custom"

    var id: String { rawValue }

    var label: String { rawValue }

    /// Default eat window duration in hours for each preset.
    var defaultEatHours: Double {
        switch self {
        case .ratio16_8:  return 8
        case .ratio14_10: return 10
        case .ratio18_6:  return 6
        case .ratio20_4:  return 4
        case .custom:     return 8
        }
    }

    /// Default eat window start hour (24h format).
    var defaultEatStartHour: Int {
        switch self {
        case .ratio16_8:  return 12
        case .ratio14_10: return 10
        case .ratio18_6:  return 12
        case .ratio20_4:  return 12
        case .custom:     return 12
        }
    }

    var icon: String {
        switch self {
        case .ratio16_8:  return "clock"
        case .ratio14_10: return "clock.arrow.circlepath"
        case .ratio18_6:  return "clock.badge.checkmark"
        case .ratio20_4:  return "clock.badge.exclamationmark"
        case .custom:     return "slider.horizontal.3"
        }
    }
}

@Model
final class FastingSchedule {
    var scheduleType: String
    var eatWindowStartHour: Int
    var eatWindowStartMinute: Int
    var eatWindowDurationHours: Double
    var isActive: Bool
    var caffeineCutoffEnabled: Bool
    var caffeineCutoffMinutesBefore: Int
    var createdAt: Date

    init(
        scheduleType: FastingScheduleType = .ratio16_8,
        eatWindowStartHour: Int = 12,
        eatWindowStartMinute: Int = 0,
        eatWindowDurationHours: Double = 8,
        isActive: Bool = true,
        caffeineCutoffEnabled: Bool = false,
        caffeineCutoffMinutesBefore: Int = 120
    ) {
        self.scheduleType = scheduleType.rawValue
        self.eatWindowStartHour = eatWindowStartHour
        self.eatWindowStartMinute = eatWindowStartMinute
        self.eatWindowDurationHours = eatWindowDurationHours
        self.isActive = isActive
        self.caffeineCutoffEnabled = caffeineCutoffEnabled
        self.caffeineCutoffMinutesBefore = caffeineCutoffMinutesBefore
        self.createdAt = .now
    }

    var resolvedScheduleType: FastingScheduleType {
        FastingScheduleType(rawValue: scheduleType) ?? .custom
    }

    var fastDurationHours: Double {
        24.0 - eatWindowDurationHours
    }
}
