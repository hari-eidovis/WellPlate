import Foundation

// MARK: - CoffeeType
// String raw-value enum covering common coffee drinks.
// Raw value is stored in WellnessDayLog.coffeeType (one type per calendar day).

enum CoffeeType: String, CaseIterable, Identifiable {
    case espresso   = "Espresso"
    case americano  = "Americano"
    case latte      = "Latte"
    case cappuccino = "Cappuccino"
    case flatWhite  = "Flat White"
    case macchiato  = "Macchiato"
    case coldBrew   = "Cold Brew"
    case pourOver   = "Pour Over"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var symbol: String {
        switch self {
        case .espresso:   return "cup.and.saucer.fill"
        case .americano:  return "drop.fill"
        case .latte:      return "mug.fill"
        case .cappuccino: return "cup.and.saucer.fill"
        case .flatWhite:  return "mug.fill"
        case .macchiato:  return "cup.and.saucer.fill"
        case .coldBrew:   return "takeoutbag.and.cup.and.straw.fill"
        case .pourOver:   return "drop.fill"
        }
    }

    /// Approximate caffeine per standard cup/serving in mg.
    var caffeineMg: Int {
        switch self {
        case .espresso:   return 63
        case .americano:  return 77
        case .latte:      return 63
        case .cappuccino: return 63
        case .flatWhite:  return 130
        case .macchiato:  return 63
        case .coldBrew:   return 200
        case .pourOver:   return 95
        }
    }
}
