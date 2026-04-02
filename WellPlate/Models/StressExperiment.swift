import Foundation
import SwiftData

enum InterventionType: String, CaseIterable, Identifiable {
    case caffeine     = "caffeine"
    case screenCurfew = "screenCurfew"
    case sleep        = "sleep"
    case exercise     = "exercise"
    case diet         = "diet"
    case custom       = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .caffeine:     return "Caffeine Cutoff"
        case .screenCurfew: return "Screen Curfew"
        case .sleep:        return "Sleep Schedule"
        case .exercise:     return "Exercise"
        case .diet:         return "Diet Change"
        case .custom:       return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .caffeine:     return "cup.and.saucer.fill"
        case .screenCurfew: return "iphone.slash"
        case .sleep:        return "moon.fill"
        case .exercise:     return "figure.run"
        case .diet:         return "leaf.fill"
        case .custom:       return "flask.fill"
        }
    }

    var suggestedHypothesis: String {
        switch self {
        case .caffeine:     return "Cutting caffeine after 2pm will lower my evening stress."
        case .screenCurfew: return "No screens after 10pm will reduce my stress the next morning."
        case .sleep:        return "Going to bed at a consistent time will lower my weekly stress."
        case .exercise:     return "Daily movement will bring my stress score down."
        case .diet:         return "Reducing processed food will improve my stress baseline."
        case .custom:       return ""
        }
    }
}

@Model
final class StressExperiment {
    var name: String
    var hypothesis: String?
    var interventionType: String   // InterventionType.rawValue
    var startDate: Date
    var durationDays: Int          // 7 or 14
    var cachedBaselineAvg: Double?
    var cachedExperimentAvg: Double?
    var cachedDelta: Double?
    var cachedCILow: Double?
    var cachedCIHigh: Double?
    var completedAt: Date?         // nil = in progress
    var createdAt: Date

    init(
        name: String,
        hypothesis: String? = nil,
        interventionType: String,
        startDate: Date,
        durationDays: Int
    ) {
        self.name = name
        self.hypothesis = hypothesis
        self.interventionType = interventionType
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.durationDays = durationDays
        self.createdAt = .now
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationDays, to: startDate) ?? startDate
    }

    var isComplete: Bool { Date() >= endDate }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    var daysElapsed: Int {
        min(durationDays, Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0)
    }

    var resolvedInterventionType: InterventionType {
        InterventionType(rawValue: interventionType) ?? .custom
    }
}
