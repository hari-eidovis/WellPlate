//
//  StressReading.swift
//  WellPlate
//
//  Persists an individual stress score snapshot captured automatically
//  whenever the computed stress value changes.
//

import Foundation
import SwiftData

@Model
final class StressReading {

    // MARK: - Stored Properties

    /// Exact time this reading was captured.
    var timestamp: Date

    /// Computed stress score 0–100 at the time of capture.
    var score: Double

    /// Label string e.g. "Excellent", "Good", "Moderate", "High", "Very High".
    var levelLabel: String

    /// "auto" = system-driven refresh, "manual" = user-entered screen-time change.
    var source: String

    // MARK: - Init

    init(
        timestamp: Date = .now,
        score: Double,
        levelLabel: String,
        source: String = "auto"
    ) {
        self.timestamp = timestamp
        self.score = score
        self.levelLabel = levelLabel
        self.source = source
    }

    // MARK: - Convenience

    /// Calendar day (start-of-day) derived from the timestamp.
    var day: Date { Calendar.current.startOfDay(for: timestamp) }

    /// Hour component (0–23) extracted from the timestamp.
    var hour: Int { Calendar.current.component(.hour, from: timestamp) }
}
