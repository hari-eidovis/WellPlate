//
//  StressModels.swift
//  WellPlate
//
//  Created on 21.02.2026.
//

import SwiftUI

// MARK: - Stress Level

enum StressLevel: String, CaseIterable {
    case excellent = "Excellent"
    case good      = "Good"
    case moderate  = "Moderate"
    case high      = "High"
    case veryHigh  = "Very High"

    init(score: Double) {
        switch score {
        case ..<21:   self = .excellent
        case 21..<41: self = .good
        case 41..<61: self = .moderate
        case 61..<81: self = .high
        default:      self = .veryHigh
        }
    }

    var label: String { rawValue }

//    var color: Color {
//        switch self {
//        case .excellent: return Color(hue: 0.33, saturation: 0.75, brightness: 0.80)
//        case .good:      return Color(hue: 0.27, saturation: 0.70, brightness: 0.78)
//        case .moderate:  return Color(hue: 0.17, saturation: 0.80, brightness: 0.82)
//        case .high:      return Color(hue: 0.08, saturation: 0.80, brightness: 0.82)
//        case .veryHigh:  return Color(hue: 0.00, saturation: 0.75, brightness: 0.80)
//        }
//    }
    var color: Color {
        let blue = Color(hex: "5E9FFF")
        switch self {
        case .excellent: return blue.opacity(0.45)
        case .good:      return blue.opacity(0.58)
        case .moderate:  return blue.opacity(0.72)
        case .high:      return blue.opacity(0.86)
        case .veryHigh:  return blue
        }
    }

    var encouragementText: String {
        switch self {
        case .excellent: return "You're doing great today!"
        case .good:      return "Keep up the good work!"
        case .moderate:  return "Not bad — room to improve."
        case .high:      return "Take a break, you deserve it."
        case .veryHigh:  return "Time to recharge — prioritize self-care."
        }
    }

    var systemImage: String {
        switch self {
        case .excellent: return "face.smiling.inverse"
        case .good:      return "face.smiling"
        case .moderate:  return "face.dashed"
        case .high:      return "exclamationmark.triangle"
        case .veryHigh:  return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Stress Factor Result

struct StressFactorResult: Identifiable {
    let id = UUID()
    let title: String
    let score: Double          // 0–25
    let maxScore: Double       // always 25
    let icon: String           // SF Symbol name
    let statusText: String     // e.g. "7,245 steps"
    let detailText: String     // e.g. "Above average today"
    /// true  → exercise / sleep / diet  (high score = good = green)
    /// false → screen time              (high score = bad  = red)
    let higherIsBetter: Bool
    /// false when this factor has no valid input for the current day.
    let hasValidData: Bool

    init(
        title: String,
        score: Double,
        maxScore: Double,
        icon: String,
        statusText: String,
        detailText: String,
        higherIsBetter: Bool,
        hasValidData: Bool = true
    ) {
        self.title = title
        self.score = score
        self.maxScore = maxScore
        self.icon = icon
        self.statusText = statusText
        self.detailText = detailText
        self.higherIsBetter = higherIsBetter
        self.hasValidData = hasValidData
    }

    var progress: Double { score / maxScore }

    /// How much this factor contributes to total stress (0–25).
    var stressContribution: Double {
        guard hasValidData else { return 0 }
        return higherIsBetter ? (maxScore - score) : score
    }

    /// Green = healthy end, Red = stressed end — direction depends on `higherIsBetter`.
    var accentColor: Color {
        guard hasValidData else { return Color(.systemGray3) }
        let t = min(max(score / maxScore, 0), 1)
        // stressRatio: 0 → green, 1 → red
        let stressRatio = higherIsBetter ? (1.0 - t) : t
        return Color(hue: 0.33 * (1.0 - stressRatio), saturation: 0.75, brightness: 0.80)
    }

    /// Default factor when no data is available (does not contribute to stress).
    static func neutral(title: String, icon: String, higherIsBetter: Bool) -> StressFactorResult {
        StressFactorResult(
            title: title,
            score: 0,
            maxScore: 25,
            icon: icon,
            statusText: "No data",
            detailText: "Waiting for data",
            higherIsBetter: higherIsBetter,
            hasValidData: false
        )
    }
}
