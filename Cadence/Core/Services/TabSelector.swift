import SwiftUI
import Combine

/// Identifies one of the app's primary tabs. Matches `MainTabView`'s tab order.
enum TabKind: String, Hashable {
    case home, stress, history, profile

    /// Legacy `Int` index (kept while `HomeView` uses `Binding<Int>`).
    var legacyIndex: Int {
        switch self {
        case .home:    return 0
        case .stress:  return 1
        case .history: return 2
        case .profile: return 3
        }
    }

    static func fromLegacyIndex(_ idx: Int) -> TabKind {
        switch idx {
        case 0: return .home
        case 1: return .stress
        case 2: return .history
        case 3: return .profile
        default: return .home
        }
    }
}

/// Sheets that can be presented as a side-effect of a tab switch (e.g. an
/// engagement-gap CTA jumping to Home + opening the Water logger).
enum TabSheetKind: String, Identifiable {
    case water, foodLog
    var id: String { rawValue }
}

/// Cross-tab navigation surface used by the engagement-gaps card and other
/// CTAs to bounce the user into a different tab and optionally present a
/// logger sheet on arrival.
@MainActor
final class TabSelector: ObservableObject {
    @Published var selectedTab: TabKind = .home
    @Published var presentedSheet: TabSheetKind? = nil

    func switchTo(_ tab: TabKind, andPresent sheet: TabSheetKind? = nil) {
        selectedTab = tab
        presentedSheet = sheet
    }
}
