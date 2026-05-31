import Foundation

/// Reason or context for eating (emotional/contextual trigger).
enum EatingTrigger: String, Codable, CaseIterable, Identifiable {
    case hungry
    case stressed
    case bored
    case social
    case rushed
    case reward
    case poorSleep
    case screenTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hungry: return "Hungry"
        case .stressed: return "Stressed"
        case .bored: return "Bored"
        case .social: return "Social"
        case .rushed: return "Rushed"
        case .reward: return "Reward"
        case .poorSleep: return "Poor Sleep"
        case .screenTime: return "Screen Time"
        }
    }

    var emoji: String {
        switch self {
        case .hungry: return "🍽️"
        case .stressed: return "😥"
        case .bored: return "🙂"
        case .social: return "🥂"
        case .rushed: return "⚡"
        case .reward: return "🎁"
        case .poorSleep: return "😴"
        case .screenTime: return "📱"
        }
    }
}
