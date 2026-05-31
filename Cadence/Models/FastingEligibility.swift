import Foundation
import SwiftData

/// One-per-user eligibility record for the fasting feature.
///
/// Persisted state from the wellness-screening flow (age/pregnancy/lactation
/// + SCOFF). Five separate Bool fields for SCOFF answers — SwiftData has no
/// precedent in this repo for stored array attributes, and per-question fields
/// also make the SCOFF Intervention Rate KPI queryable later.
@Model final class FastingEligibility {
    var cleared: Bool = false
    var clearedAt: Date?
    var age18Plus: Bool = false
    var notPregnant: Bool = false
    var notLactating: Bool = false
    var scoffCleared: Bool = false

    // SCOFF — five questions, persisted individually.
    var scoffSick: Bool = false        // Q1: vomiting because uncomfortably full
    var scoffControl: Bool = false     // Q2: lost control over how much you eat
    var scoffOneStone: Bool = false    // Q3: >14lb / 6.35kg loss in 3 months
    var scoffFat: Bool = false         // Q4: believe yourself fat when others say thin
    var scoffFood: Bool = false        // Q5: food dominates your life

    var lastScreenedAt: Date?

    init() {}

    var scoffPositiveCount: Int {
        [scoffSick, scoffControl, scoffOneStone, scoffFat, scoffFood].filter { $0 }.count
    }

    var canInitiate: Bool {
        cleared && age18Plus && notPregnant && notLactating && scoffCleared
    }
}
