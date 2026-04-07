//
//  InterventionSession.swift
//  WellPlate
//
//  SwiftData history log for acute reset exercises. Biometric fields
//  are nil on iPhone; populated by Watch companion when it ships.
//

import Foundation
import SwiftData

@Model
final class InterventionSession {
    var resetType: String          // ResetType.rawValue
    var startedAt: Date
    var durationSeconds: Int       // actual elapsed duration
    var completed: Bool            // false if user cancelled mid-session

    // Watch bolt-on fields — nil on iPhone until Watch ships
    var preHeartRate: Double?
    var postHeartRate: Double?
    var preHRV: Double?
    var postHRV: Double?

    init(resetType: ResetType, startedAt: Date, durationSeconds: Int, completed: Bool) {
        self.resetType = resetType.rawValue
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.completed = completed
    }

    var resolvedResetType: ResetType {
        ResetType(rawValue: resetType) ?? .pmr
    }
}
