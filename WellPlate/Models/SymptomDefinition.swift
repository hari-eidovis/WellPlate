import SwiftUI

// MARK: - SymptomCategory

enum SymptomCategory: String, CaseIterable, Identifiable, Codable {
    case digestive, pain, energy, cognitive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .digestive: return "Digestive"
        case .pain:      return "Pain"
        case .energy:    return "Energy"
        case .cognitive: return "Cognitive"
        }
    }

    var icon: String {
        switch self {
        case .digestive: return "stomach"
        case .pain:      return "bandage"
        case .energy:    return "bolt.fill"
        case .cognitive: return "brain.head.profile"
        }
    }

    var color: Color {
        switch self {
        case .digestive: return Color(hue: 0.08, saturation: 0.70, brightness: 0.90)  // warm orange
        case .pain:      return Color(hue: 0.00, saturation: 0.72, brightness: 0.85)  // red
        case .energy:    return Color(hue: 0.14, saturation: 0.65, brightness: 0.98)  // amber
        case .cognitive: return Color(hue: 0.72, saturation: 0.55, brightness: 0.82)  // purple
        }
    }
}

// MARK: - SymptomDefinition

struct SymptomDefinition: Identifiable, Hashable {
    let name: String
    let category: SymptomCategory
    let icon: String        // SF Symbol
    let isCustom: Bool

    var id: String { name }

    static func custom(name: String) -> SymptomDefinition {
        SymptomDefinition(name: name, category: .cognitive, icon: "plus.circle", isCustom: true)
    }

    static func forCategory(_ category: SymptomCategory) -> [SymptomDefinition] {
        library.filter { $0.category == category }
    }

    // MARK: - Preset library (20 symptoms, 5 per category)

    static let library: [SymptomDefinition] = [
        // Digestive
        SymptomDefinition(name: "Bloating",              category: .digestive, icon: "circle.fill",        isCustom: false),
        SymptomDefinition(name: "Nausea",                category: .digestive, icon: "wind",               isCustom: false),
        SymptomDefinition(name: "Acid reflux",           category: .digestive, icon: "flame",              isCustom: false),
        SymptomDefinition(name: "Stomach pain",          category: .digestive, icon: "exclamationmark.circle", isCustom: false),
        SymptomDefinition(name: "Irregular digestion",   category: .digestive, icon: "arrow.triangle.2.circlepath", isCustom: false),

        // Pain
        SymptomDefinition(name: "Headache",              category: .pain, icon: "bolt.horizontal",         isCustom: false),
        SymptomDefinition(name: "Migraine",              category: .pain, icon: "bolt.horizontal.fill",    isCustom: false),
        SymptomDefinition(name: "Joint pain",            category: .pain, icon: "figure.walk",             isCustom: false),
        SymptomDefinition(name: "Muscle soreness",       category: .pain, icon: "dumbbell",                isCustom: false),
        SymptomDefinition(name: "Back pain",             category: .pain, icon: "person.fill",             isCustom: false),

        // Energy
        SymptomDefinition(name: "Fatigue",               category: .energy, icon: "battery.25",            isCustom: false),
        SymptomDefinition(name: "Energy crash",          category: .energy, icon: "bolt.slash.fill",       isCustom: false),
        SymptomDefinition(name: "Brain fog",             category: .energy, icon: "cloud.fill",            isCustom: false),
        SymptomDefinition(name: "Dizziness",             category: .energy, icon: "arrow.2.circlepath",    isCustom: false),
        SymptomDefinition(name: "Insomnia",              category: .energy, icon: "moon.zzz",              isCustom: false),

        // Cognitive
        SymptomDefinition(name: "Anxiety",               category: .cognitive, icon: "heart.fill",         isCustom: false),
        SymptomDefinition(name: "Irritability",          category: .cognitive, icon: "exclamationmark.2",  isCustom: false),
        SymptomDefinition(name: "Low mood",              category: .cognitive, icon: "arrow.down.heart",   isCustom: false),
        SymptomDefinition(name: "Difficulty concentrating", category: .cognitive, icon: "scope",           isCustom: false),
        SymptomDefinition(name: "Restlessness",          category: .cognitive, icon: "figure.walk.motion", isCustom: false),
    ]
}
