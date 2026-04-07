import Foundation
import SwiftUI
import SwiftData

// MARK: - SupplementCategory

enum SupplementCategory: String, CaseIterable, Identifiable, Codable {
    case vitamin, mineral, omega, probiotic, herb, protein, medication, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vitamin:    return "Vitamin"
        case .mineral:    return "Mineral"
        case .omega:      return "Omega"
        case .probiotic:  return "Probiotic"
        case .herb:       return "Herb"
        case .protein:    return "Protein"
        case .medication: return "Medication"
        case .custom:     return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .vitamin:    return "capsule"
        case .mineral:    return "atom"
        case .omega:      return "drop.fill"
        case .probiotic:  return "allergens"
        case .herb:       return "leaf.fill"
        case .protein:    return "dumbbell.fill"
        case .medication: return "pill.fill"
        case .custom:     return "plus.circle"
        }
    }

    var color: Color {
        switch self {
        case .vitamin:    return Color(hue: 0.14, saturation: 0.70, brightness: 0.95) // amber
        case .mineral:    return Color(hue: 0.55, saturation: 0.60, brightness: 0.80) // teal
        case .omega:      return Color(hue: 0.60, saturation: 0.65, brightness: 0.85) // blue
        case .probiotic:  return Color(hue: 0.38, saturation: 0.55, brightness: 0.75) // green
        case .herb:       return Color(hue: 0.30, saturation: 0.60, brightness: 0.70) // olive
        case .protein:    return Color(hue: 0.00, saturation: 0.55, brightness: 0.85) // red-ish
        case .medication: return Color(hue: 0.72, saturation: 0.50, brightness: 0.80) // purple
        case .custom:     return Color(hue: 0.08, saturation: 0.50, brightness: 0.85) // orange
        }
    }
}

// MARK: - SupplementEntry

@Model
final class SupplementEntry {
    var id: UUID
    var name: String
    var dosage: String
    var category: String          // Raw value of SupplementCategory
    var scheduledTimes: [Int]     // Minutes from midnight [480, 1200] = 8am, 8pm
    var activeDays: [Int]         // 0=Sun..6=Sat; empty = every day
    var isActive: Bool
    var notificationsEnabled: Bool
    var notes: String?
    var startDate: Date
    var createdAt: Date

    init(
        name: String,
        dosage: String = "",
        category: SupplementCategory = .vitamin,
        scheduledTimes: [Int] = [480],
        activeDays: [Int] = [],
        isActive: Bool = true,
        notificationsEnabled: Bool = true,
        notes: String? = nil,
        startDate: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.dosage = dosage
        self.category = category.rawValue
        self.scheduledTimes = scheduledTimes
        self.activeDays = activeDays
        self.isActive = isActive
        self.notificationsEnabled = notificationsEnabled
        self.notes = notes
        self.startDate = startDate
        self.createdAt = .now
    }

    // MARK: - Convenience

    var resolvedCategory: SupplementCategory? {
        SupplementCategory(rawValue: category)
    }

    var formattedTimes: [String] {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return scheduledTimes.sorted().map { minutes in
            let hour = minutes / 60
            let min = minutes % 60
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = min
            let date = Calendar.current.date(from: comps) ?? Date()
            return f.string(from: date)
        }
    }
}
