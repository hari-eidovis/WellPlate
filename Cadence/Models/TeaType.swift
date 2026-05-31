import Foundation

// MARK: - TeaType
// String raw-value enum covering common tea drinks. Mirrors CoffeeType.
// Used by TeaTypePickerSheet when the user logs a generic "tea" or "chai" entry.

enum TeaType: String, CaseIterable, Identifiable {
    case black      = "Black Tea"
    case milkTea    = "Milk Tea"
    case masalaChai = "Masala Chai"
    case green      = "Green Tea"
    case herbal     = "Herbal Tea"
    case iced       = "Iced Tea"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var symbol: String {
        switch self {
        case .black:      return "cup.and.saucer.fill"
        case .milkTea:    return "mug.fill"
        case .masalaChai: return "mug.fill"
        case .green:      return "leaf.fill"
        case .herbal:     return "leaf.fill"
        case .iced:       return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    /// Approximate caffeine per standard cup/serving in mg.
    var caffeineMg: Int {
        switch self {
        case .black:      return 47
        case .milkTea:    return 47
        case .masalaChai: return 50
        case .green:      return 28
        case .herbal:     return 0
        case .iced:       return 47
        }
    }
}
