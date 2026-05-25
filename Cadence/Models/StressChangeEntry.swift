//
//  StressChangeEntry.swift
//  WellPlate
//
//  Transaction-style change-log entry for the stress score. Each row
//  represents a single moved factor / engagement gap / pattern penalty /
//  calibrator delta emitted from a recompute. See
//  Docs/02_Planning/Specs/260510-stress-change-log-plan-RESOLVED.md.
//

import Foundation
import SwiftData

// MARK: - ChangeEntryKind

enum ChangeEntryKind: String {
    case factor               // one of the 13 stress factors moved
    case engagementGap        // a sub-cause of engagementPenalty changed
    case patternPenalty       // pattern penalty changed
    case calibrator           // calibrator multiplier shifted score by >=1 pt at today's raw
    case anchor               // "Day started" or first-install anchor — no delta
    case engagementActivated  // first-time activation marker — see L4
}

// MARK: - StressChangeSource

enum StressChangeSource: String, CaseIterable, Codable {
    // Auto sources — recompute fired without explicit user action
    case autoTicker             // 30s refreshTicker (StressView.refreshTicker.onReceive)
    case autoEngagementTick     // 5-min StressTimerService.tickerPulse
    case autoScenePhase         // app foregrounded (.onChange(scenePhase) -> loadData)
    case autoAppOpen            // first load on app launch / .task
    case autoRefreshable        // pull-to-refresh on Stress tab
    case autoOnAppear           // onAppear path on Stress tab
    case autoHealthKitChange    // HK observer query (reserved; not wired in v1)

    // Manual sources — user did something
    case manualScreenTime
    case manualFoodLog
    case manualFoodDelete
    case manualWater
    case manualCoffee
    case manualMood
    case manualSymptoms
    case manualFasting
    case manualIntervention
    case manualOther            // catch-all for QuickLog / DailyPromptCoordinator pipe

    var isAuto: Bool { rawValue.hasPrefix("auto") }

    var displayLabel: String {
        switch self {
        case .autoTicker:           return "30s refresh"
        case .autoEngagementTick:   return "Engagement tick"
        case .autoScenePhase:       return "App foregrounded"
        case .autoAppOpen:          return "App opened"
        case .autoRefreshable:      return "Pull to refresh"
        case .autoOnAppear:         return "Tab opened"
        case .autoHealthKitChange:  return "HealthKit update"
        case .manualScreenTime:     return "Screen time logged"
        case .manualFoodLog:        return "Logged food"
        case .manualFoodDelete:     return "Removed food"
        case .manualWater:          return "Logged water"
        case .manualCoffee:         return "Logged coffee"
        case .manualMood:           return "Mood logged"
        case .manualSymptoms:       return "Symptoms logged"
        case .manualFasting:        return "Fasting updated"
        case .manualIntervention:   return "Reset completed"
        case .manualOther:          return "Manual update"
        }
    }
}

// MARK: - StressChangeEntry (@Model)

@Model
final class StressChangeEntry {
    // Identity & ordering
    var timestamp: Date          // Time of the recompute (all entries in a group share this)
    var groupID: UUID            // Same UUID for all rows emitted in one recompute
    var sequence: Int            // 0-based order within the group (stable sort tie-breaker)

    // What kind of row this is — drives icon/color/wording in the UI
    var kind: String             // ChangeEntryKind.rawValue
    var subjectKey: String       // factor key ("sleep"), engagement key ("no_mood"), or "calibrator"
    var subjectIcon: String      // SF Symbol name cached at write time

    // The change itself
    var deltaPoints: Double      // signed; negative = score went down (good for user)
    var prevValue: Double
    var nextValue: Double

    // Total score context
    var totalBefore: Double
    var totalAfter: Double

    // Cause / source
    var sourceRaw: String        // StressChangeSource.rawValue
    var detailText: String       // human-readable

    init(
        timestamp: Date,
        groupID: UUID,
        sequence: Int,
        kind: String,
        subjectKey: String,
        subjectIcon: String,
        deltaPoints: Double,
        prevValue: Double,
        nextValue: Double,
        totalBefore: Double,
        totalAfter: Double,
        sourceRaw: String,
        detailText: String
    ) {
        self.timestamp = timestamp
        self.groupID = groupID
        self.sequence = sequence
        self.kind = kind
        self.subjectKey = subjectKey
        self.subjectIcon = subjectIcon
        self.deltaPoints = deltaPoints
        self.prevValue = prevValue
        self.nextValue = nextValue
        self.totalBefore = totalBefore
        self.totalAfter = totalAfter
        self.sourceRaw = sourceRaw
        self.detailText = detailText
    }

    // Convenience
    var day: Date { Calendar.current.startOfDay(for: timestamp) }
    var entryKind: ChangeEntryKind { ChangeEntryKind(rawValue: kind) ?? .factor }
    var source: StressChangeSource { StressChangeSource(rawValue: sourceRaw) ?? .autoTicker }
}

// MARK: - MockChangeEntry (struct DTO for mock mode)
// MARK: keep in sync with StressChangeEntry

struct MockChangeEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let groupID: UUID
    let sequence: Int
    let kind: ChangeEntryKind
    let subjectKey: String
    let subjectIcon: String
    let deltaPoints: Double
    let prevValue: Double
    let nextValue: Double
    let totalBefore: Double
    let totalAfter: Double
    let source: StressChangeSource
    let detailText: String
}

// MARK: - ChangeEntryDisplayable

protocol ChangeEntryDisplayable {
    var timestamp: Date { get }
    var groupID: UUID { get }
    var sequence: Int { get }
    var entryKind: ChangeEntryKind { get }
    var subjectIcon: String { get }
    var deltaPoints: Double { get }
    var detailText: String { get }
    var source: StressChangeSource { get }
    var totalBefore: Double { get }
    var totalAfter: Double { get }
}

extension StressChangeEntry: ChangeEntryDisplayable {}

extension MockChangeEntry: ChangeEntryDisplayable {
    var entryKind: ChangeEntryKind { kind }
}

// MARK: - StressLastResultEnvelope (versioned cold-launch payload)

struct StressLastResultEnvelope: Codable {
    static let currentVersion: Int = 1

    let version: Int
    let capturedAt: Date
    let result: StressScoring.StressResult
}

// MARK: - StressChangeFilter (view-state)

enum StressChangeFilter: Hashable {
    case all
    case auto                                   // any .autoX
    case logs                                   // any .manualX
    case mood, symptoms, screenTime, food, calibration

    /// Sources allowed by this filter.
    /// Returns nil for .all (no source predicate) and .calibration
    /// (filtered by `kind == "calibrator"` client-side).
    var sources: Set<StressChangeSource>? {
        switch self {
        case .all:          return nil
        case .auto:         return Set(StressChangeSource.allCases.filter(\.isAuto))
        case .logs:         return Set(StressChangeSource.allCases.filter { !$0.isAuto })
        case .mood:         return [.manualMood]
        case .symptoms:     return [.manualSymptoms]
        case .screenTime:   return [.manualScreenTime]
        case .food:         return [.manualFoodLog, .manualFoodDelete]
        case .calibration:  return nil
        }
    }
}
