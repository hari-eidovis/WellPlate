import Foundation
import SwiftData

@Model
final class JournalEntry {
    @Attribute(.unique) var day: Date       // Calendar.startOfDay — one per day (MVP)
    var text: String                         // User's journal text
    var moodRaw: Int?                        // Snapshot of MoodOption.rawValue at write time
    var promptUsed: String?                  // The prompt shown (nil if free-form)
    var stressScore: Double?                 // Snapshot of today's stress score if available
    var createdAt: Date
    var updatedAt: Date

    init(
        day: Date,
        text: String = "",
        moodRaw: Int? = nil,
        promptUsed: String? = nil,
        stressScore: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.day = Calendar.current.startOfDay(for: day)
        self.text = text
        self.moodRaw = moodRaw
        self.promptUsed = promptUsed
        self.stressScore = stressScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Convenience

    var mood: MoodOption? {
        guard let raw = moodRaw else { return nil }
        return MoodOption(rawValue: raw)
    }
}
