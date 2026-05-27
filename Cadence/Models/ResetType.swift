//
//  ResetType.swift
//  Cadence
//
//  Acute stress-relief reset exercises.
//

import Foundation
import SwiftUI

enum ResetType: String, CaseIterable, Identifiable, Codable {
    case pmr       = "pmr"
    case sigh      = "sigh"
    case grounding = "grounding"
    // Phase 2 additions (not implemented yet)
    // case vocalEntrainment = "vocalEntrainment"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pmr:       return "Muscle Release"
        case .sigh:      return "Physiological Sigh"
        case .grounding: return "5-4-3-2-1 Grounding"
        }
    }

    var subtitle: String {
        switch self {
        case .pmr:       return "60-sec full-body tension reset"
        case .sigh:      return "3 breath cycles · ~35 seconds"
        case .grounding: return "Sensory anchor · ~60 seconds"
        }
    }

    var icon: String {
        switch self {
        case .pmr:       return "figure.mind.and.body"
        case .sigh:      return "wind"
        case .grounding: return "leaf.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .pmr:       return .teal
        case .sigh:      return .indigo
        case .grounding: return .mint
        }
    }
}
