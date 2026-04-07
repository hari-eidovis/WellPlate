import Foundation
import SwiftData

@Model
final class AdherenceLog {
    var id: UUID
    var supplementName: String    // Denormalized for display/export
    var supplementID: UUID        // FK to SupplementEntry.id
    var day: Date                 // Calendar.startOfDay
    var scheduledMinute: Int      // Which dose time (480 = 8am)
    var status: String            // "taken", "skipped", "pending"
    var takenAt: Date?            // When marked taken (nil if skipped/pending)
    var createdAt: Date

    init(
        supplementName: String,
        supplementID: UUID,
        day: Date,
        scheduledMinute: Int,
        status: String = "pending",
        takenAt: Date? = nil
    ) {
        self.id = UUID()
        self.supplementName = supplementName
        self.supplementID = supplementID
        self.day = Calendar.current.startOfDay(for: day)
        self.scheduledMinute = scheduledMinute
        self.status = status
        self.takenAt = takenAt
        self.createdAt = .now
    }
}
