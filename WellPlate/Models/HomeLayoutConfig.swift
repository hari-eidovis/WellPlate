import SwiftUI

// MARK: - Home Card Identification

/// Identifies each customisable card on the home screen.
/// Case order matches the default display order (used by CaseIterable).
/// Raw values are used for JSON persistence — do not rename without migration.
enum HomeCardID: String, Codable, CaseIterable, Identifiable, Hashable {
    case dailyInsight       // Position 1b — after header
    case wellnessRings      // Position 2
    case stressSparkline    // Position 2b
    case moodCheckIn        // Position 3a (conditional)
    case journalReflection  // Position 3b (conditional)
    case quickStats         // Position 4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dailyInsight:       return "Daily Insight"
        case .wellnessRings:      return "Wellness Rings"
        case .stressSparkline:    return "Stress Sparkline"
        case .moodCheckIn:        return "Mood Check-In"
        case .journalReflection:  return "Journal Reflection"
        case .quickStats:         return "Water & Coffee"
        }
    }

    var iconName: String {
        switch self {
        case .dailyInsight:       return "sparkles"
        case .wellnessRings:      return "circle.circle"
        case .stressSparkline:    return "waveform.path.ecg"
        case .moodCheckIn:        return "face.smiling"
        case .journalReflection:  return "book"
        case .quickStats:         return "drop.fill"
        }
    }

    /// Cards that support element-level customisation.
    var hasSubElements: Bool {
        switch self {
        case .wellnessRings, .quickStats: return true
        default: return false
        }
    }

    /// Element IDs belonging to this card.
    var subElements: [HomeElementID] {
        switch self {
        case .wellnessRings: return [.calorieRing, .waterRing, .exerciseRing, .stressRing]
        case .quickStats:    return [.waterTile, .coffeeTile]
        default:             return []
        }
    }
}

// MARK: - Home Element Identification

/// Identifies toggleable sub-elements within compound cards.
enum HomeElementID: String, Codable, CaseIterable, Identifiable, Hashable {
    case calorieRing
    case waterRing
    case exerciseRing
    case stressRing
    case waterTile
    case coffeeTile

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calorieRing:  return "Calorie Ring"
        case .waterRing:    return "Water Ring"
        case .exerciseRing: return "Exercise Ring"
        case .stressRing:   return "Stress Ring"
        case .waterTile:    return "Water"
        case .coffeeTile:   return "Coffee"
        }
    }

    var iconName: String {
        switch self {
        case .calorieRing:  return "flame.fill"
        case .waterRing:    return "drop.fill"
        case .exerciseRing: return "figure.run"
        case .stressRing:   return "brain.head.profile"
        case .waterTile:    return "drop.fill"
        case .coffeeTile:   return "cup.and.saucer.fill"
        }
    }
}

// MARK: - Home Layout Configuration

/// Persisted layout configuration. Codable for JSON storage in UserGoals.
struct HomeLayoutConfig: Codable, Equatable {

    /// Ordered list of ALL card IDs. Cards appear in this order on the home screen.
    var cardOrder: [HomeCardID]

    /// Cards the user has explicitly hidden.
    var hiddenCards: Set<HomeCardID>

    /// Per-card element visibility overrides.
    /// Key = parent card ID, Value = set of HIDDEN element IDs within that card.
    var hiddenElements: [HomeCardID: Set<HomeElementID>]

    // MARK: - Defaults

    init(
        cardOrder: [HomeCardID] = HomeCardID.allCases,
        hiddenCards: Set<HomeCardID> = [],
        hiddenElements: [HomeCardID: Set<HomeElementID>] = [:]
    ) {
        self.cardOrder = cardOrder
        self.hiddenCards = hiddenCards
        self.hiddenElements = hiddenElements
    }

    static let `default` = HomeLayoutConfig()

    // MARK: - Queries

    /// Visible cards in display order.
    var visibleCards: [HomeCardID] {
        cardOrder.filter { !hiddenCards.contains($0) }
    }

    /// Number of hidden cards.
    var hiddenCount: Int { hiddenCards.count }

    /// Check if a specific element is visible within a card.
    func isElementVisible(_ element: HomeElementID, in card: HomeCardID) -> Bool {
        !(hiddenElements[card]?.contains(element) ?? false)
    }

    /// Visible elements for a given card.
    func visibleElements(for card: HomeCardID) -> [HomeElementID] {
        card.subElements.filter { isElementVisible($0, in: card) }
    }

    // MARK: - Mutations

    /// Hide a card.
    /// Note: cards auto-hidden (all elements toggled off) must be manually re-shown —
    /// there is no implicit/explicit distinction stored.
    mutating func hideCard(_ card: HomeCardID) {
        hiddenCards.insert(card)
    }

    /// Show a previously hidden card.
    mutating func showCard(_ card: HomeCardID) {
        hiddenCards.remove(card)
    }

    /// Toggle element visibility. Auto-hides parent card if ALL elements become hidden.
    mutating func toggleElement(_ element: HomeElementID, in card: HomeCardID) {
        var set = hiddenElements[card] ?? []
        if set.contains(element) {
            set.remove(element)
        } else {
            set.insert(element)
        }
        hiddenElements[card] = set.isEmpty ? nil : set

        // Auto-hide card if ALL its elements are now hidden
        if !card.subElements.isEmpty && visibleElements(for: card).isEmpty {
            hideCard(card)
        }
    }

    /// Move a card from one position to another in cardOrder.
    mutating func moveCard(from source: IndexSet, to destination: Int) {
        cardOrder.move(fromOffsets: source, toOffset: destination)
    }

    /// Reset to default layout.
    mutating func reset() {
        self = .default
    }

    // MARK: - Future-proofing

    /// Ensures new cards added in future updates appear in the order.
    /// Call after decoding to reconcile with current `HomeCardID.allCases`.
    mutating func reconcileWithCurrentCards() {
        let known = Set(cardOrder)
        let newCards = HomeCardID.allCases.filter { !known.contains($0) }
        cardOrder.append(contentsOf: newCards)
        // Remove any cards that no longer exist in the enum
        let current = Set(HomeCardID.allCases)
        cardOrder.removeAll { !current.contains($0) }
        hiddenCards = hiddenCards.intersection(current)
    }
}
