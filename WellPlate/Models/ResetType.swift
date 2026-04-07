//
//  ResetType.swift
//  WellPlate
//
//  Acute stress-relief reset exercises (distinct from Stress Lab's
//  multi-day InterventionType experiments).
//

import Foundation
import SwiftUI

enum ResetType: String, CaseIterable, Identifiable, Codable {
    case pmr  = "pmr"
    case sigh = "sigh"
    // Phase 2 additions (not implemented yet)
    // case vocalEntrainment = "vocalEntrainment"
    // case grounding        = "grounding"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pmr:  return "Muscle Release"
        case .sigh: return "Physiological Sigh"
        }
    }

    var subtitle: String {
        switch self {
        case .pmr:  return "60-sec full-body tension reset"
        case .sigh: return "3 breath cycles · ~35 seconds"
        }
    }

    var icon: String {
        switch self {
        case .pmr:  return "figure.mind.and.body"
        case .sigh: return "wind"
        }
    }

    var accentColor: Color {
        switch self {
        case .pmr:  return .teal
        case .sigh: return .indigo
        }
    }
}
