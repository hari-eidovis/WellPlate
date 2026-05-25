//
//  CelebrationCoordinator.swift
//  Cadence
//
//  Global source-of-truth for the stress-drop celebration overlay. Any place
//  in the app that recomputes the stress score reports the prev/new pair to
//  `evaluate(previousScore:newScore:)`; subscribers (currently
//  `CelebrationWindowPresenter`) react to `event` changes to show/hide the
//  overlay anywhere on screen — including over presented sheets.
//

import Foundation
import Combine

@MainActor
final class CelebrationCoordinator: ObservableObject {

    static let shared = CelebrationCoordinator()

    /// Non-nil while a celebration is queued or visible. Driven by
    /// `evaluate(previousScore:newScore:)` and cleared by `acknowledge()`.
    @Published private(set) var event: StressCelebrationEvent? = nil

    /// Minimum drop (in stress points) required to fire.
    private static let minDrop: Double = 8.0

    /// The very first evaluation after launch compares against the default
    /// score (0), which would otherwise look like a huge upward swing — gate
    /// on this flag to avoid spurious fires at cold launch.
    private var hasEvaluatedOnce = false

    private init() {}

    /// Compares the previous score against the new one and publishes an
    /// `event` whenever the drop crosses the threshold. Fires on every
    /// qualifying drop — no time throttle. Because the baseline (`previousScore`)
    /// is the most-recently-published score, the same drop can't double-fire:
    /// once published, subsequent recomputes start from the new lower baseline.
    func evaluate(previousScore: Double, newScore: Double) {
        defer { hasEvaluatedOnce = true }
        guard hasEvaluatedOnce else { return }

        let drop = previousScore - newScore
        guard drop >= Self.minDrop else { return }
        // Ignore degenerate cases where previous is already at/below threshold
        // (the "drop" is just noise around a near-zero baseline).
        guard previousScore >= Self.minDrop else { return }

        event = StressCelebrationEvent(
            dropPoints: Int(drop.rounded()),
            previousScore: previousScore,
            newScore: newScore
        )
    }

    /// Called by the overlay when it dismisses (auto or user-driven).
    func acknowledge() {
        event = nil
    }
}
