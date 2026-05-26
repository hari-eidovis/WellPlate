//
//  CelebrationCoordinator.swift
//  Cadence
//
//  Global source-of-truth for the stress shift overlay. Any place in the app
//  that recomputes the stress score reports the prev/new pair to
//  `evaluate(previousScore:newScore:)`; subscribers (currently
//  `CelebrationWindowPresenter`) react to `event` changes to show/hide the
//  overlay anywhere on screen — including over presented sheets.
//
//  Two directions are detected:
//    • Drop ≥ 8 points — celebratory overlay with confetti.
//    • Rise ≥ 7 points — warning overlay with error haptics.
//

import Foundation
import Combine

@MainActor
final class CelebrationCoordinator: ObservableObject {

    static let shared = CelebrationCoordinator()

    /// Non-nil while a shift overlay is queued or visible. Driven by
    /// `evaluate(previousScore:newScore:)` and cleared by `acknowledge()`.
    @Published private(set) var event: StressCelebrationEvent? = nil

    /// Minimum drop (in stress points) required to fire the celebration.
    private static let minDrop: Double = 8.0
    /// Minimum rise (in stress points) required to fire the warning.
    private static let minRise: Double = 7.0

    /// The very first evaluation after launch compares against the default
    /// score (0), which would otherwise look like a huge upward swing — gate
    /// on this flag to avoid spurious fires at cold launch.
    private var hasEvaluatedOnce = false

    private init() {}

    /// Compares the previous score against the new one and publishes an event
    /// whenever the change crosses either direction's threshold. Fires on
    /// every qualifying shift — no time throttle. Because the baseline
    /// (`previousScore`) is the most-recently-published score, the same shift
    /// can't double-fire: once published, subsequent recomputes start from
    /// the new baseline.
    func evaluate(previousScore: Double, newScore: Double) {
        defer { hasEvaluatedOnce = true }
        guard hasEvaluatedOnce else { return }

        let delta = newScore - previousScore

        if delta <= -Self.minDrop {
            // Ignore degenerate cases where previous is already at/below
            // threshold (the "drop" is just noise around a near-zero baseline).
            guard previousScore >= Self.minDrop else { return }
            event = StressCelebrationEvent(
                kind: .drop,
                magnitude: Int((-delta).rounded()),
                previousScore: previousScore,
                newScore: newScore
            )
        } else if delta >= Self.minRise {
            // Symmetrically, a rise into a still-low score (e.g. 0 → 6) is
            // not worth alerting on. Require the new score to be in territory
            // that genuinely warrants attention.
            guard newScore >= Self.minRise else { return }
            event = StressCelebrationEvent(
                kind: .rise,
                magnitude: Int(delta.rounded()),
                previousScore: previousScore,
                newScore: newScore
            )
        }
    }

    /// Called by the overlay when it dismisses (auto or user-driven).
    func acknowledge() {
        event = nil
    }
}
