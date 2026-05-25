import Foundation
import SwiftData

@Model
final class SymptomEntry {
    // MARK: - Stored Properties

    var id: UUID
    var name: String            // e.g. "Headache"
    var category: String        // Raw value of SymptomCategory
    var severity: Int           // 1–10
    var timestamp: Date         // Exact time of logging
    var day: Date               // Calendar.startOfDay — for daily aggregation
    var notes: String?
    var createdAt: Date

    // MARK: - Init

    init(
        name: String,
        category: SymptomCategory,
        severity: Int,
        timestamp: Date = .now,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.category = category.rawValue
        self.severity = max(1, min(10, severity))
        self.timestamp = timestamp
        self.day = Calendar.current.startOfDay(for: timestamp)
        self.notes = notes
        self.createdAt = .now
    }

    // MARK: - Convenience

    var resolvedCategory: SymptomCategory? {
        SymptomCategory(rawValue: category)
    }
}
