import Foundation

/// The three branches every fasting-initiation entry point must route through.
/// Centralizes the "can this user start a fast?" decision so adding a new
/// surface (Home card, Stress factor sheet, in-app deeplink) doesn't risk
/// bypassing the SCOFF / demographic gate.
enum FastingAccessState {
    /// No FastingEligibility row exists yet — present onboarding flow.
    case onboarding
    /// Row exists but `canInitiate == false` (SCOFF positive or demographic
    /// disqualification) — present care intervention.
    case careBlocked
    /// Row exists and all gates passed — open FastingView normally.
    case granted
}

extension FastingEligibility {
    /// Single source of truth for fasting-feature routing. All initiation
    /// surfaces should call this rather than re-implementing the check.
    static func accessState(from rows: [FastingEligibility]) -> FastingAccessState {
        #if DEBUG
        if let forced = AppConfig.shared.fastingAccessOverride.resolved() {
            return forced
        }
        #endif
        guard let row = rows.first else { return .onboarding }
        return row.canInitiate ? .granted : .careBlocked
    }
}
