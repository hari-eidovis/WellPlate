//
//  HealthModels.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import Charts

// MARK: - Data Structures

struct DailyMetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct SleepSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double   // hours
    let stage: SleepStage
}

// MARK: - Sleep Stage

enum SleepStage: String, CaseIterable, Identifiable, Plottable {
    case deep         = "Deep"
    case core         = "Core"
    case rem          = "REM"
    case unspecified  = "Asleep"

    var id: String { rawValue }

    var primitivePlottable: String { rawValue }

    init?(primitivePlottable: String) {
        self.init(rawValue: primitivePlottable)
    }

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .deep:        return Color(red: 0.40, green: 0.20, blue: 0.85)  // rich purple
        case .core:        return Color(red: 0.45, green: 0.55, blue: 0.95)  // soft blue
        case .rem:         return Color(red: 0.35, green: 0.30, blue: 0.75)  // indigo
        case .unspecified: return Color(red: 0.60, green: 0.55, blue: 0.80)  // muted lavender
        }
    }

    var systemImage: String {
        switch self {
        case .deep:        return "moon.fill"
        case .core:        return "moon.haze.fill"
        case .rem:         return "sparkles"
        case .unspecified: return "zzz"
        }
    }
}

// MARK: - Sleep Quality

enum SleepQuality: String {
    case poor      = "Poor"
    case fair      = "Fair"
    case good      = "Good"
    case excellent = "Excellent"

    var color: Color {
        switch self {
        case .poor:      return .red
        case .fair:      return .orange
        case .good:      return .green
        case .excellent: return .mint
        }
    }

    init(hours: Double) {
        switch hours {
        case ..<5:      self = .poor
        case 5..<6.5:   self = .fair
        case 6.5..<8:   self = .good
        default:        self = .excellent
        }
    }
}

// MARK: - Daily Sleep Summary

struct DailySleepSummary: Identifiable {
    let id = UUID()
    let date: Date        // morning date (wake-up calendar day)
    let totalHours: Double
    let coreHours: Double
    let remHours: Double
    let deepHours: Double

    var quality: SleepQuality { SleepQuality(hours: totalHours) }

    /// Breakdown as an ordered array for charts.
    var stageBreakdown: [(stage: SleepStage, hours: Double)] {
        [
            (.deep, deepHours),
            (.rem, remHours),
            (.core, coreHours)
        ].filter { $0.hours > 0 }
    }
}

// MARK: - Burn Metrics

enum BurnMetric: String, CaseIterable, Identifiable {
    case activeEnergy = "Active Energy"
    case steps        = "Steps"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .activeEnergy: return "kcal"
        case .steps:        return "steps"
        }
    }

    var systemImage: String {
        switch self {
        case .activeEnergy: return "flame.fill"
        case .steps:        return "figure.walk"
        }
    }

    var accentColor: Color {
        switch self {
        case .activeEnergy: return AppColors.brand
        case .steps:        return .green
        }
    }
}
