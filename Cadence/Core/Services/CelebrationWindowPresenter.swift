//
//  CelebrationWindowPresenter.swift
//  Cadence
//
//  Hosts `StressCelebrationOverlay` in its own `UIWindow` so the celebration
//  appears above whatever the user is currently looking at — including any
//  presented sheet — instead of being scoped to the Stress tab.
//

import SwiftUI
import UIKit
import Combine

@MainActor
final class CelebrationWindowPresenter {

    static let shared = CelebrationWindowPresenter()

    private var window: UIWindow?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Wires the presenter to `CelebrationCoordinator`. Idempotent.
    func install() {
        guard cancellable == nil else { return }
        cancellable = CelebrationCoordinator.shared.$event
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                if let event {
                    self?.present(event)
                } else {
                    self?.dismiss()
                }
            }
    }

    private func present(_ event: StressCelebrationEvent) {
        // If an overlay is already showing, tear it down so the newer event
        // gets its turn — every qualifying drop should be celebrated.
        if window != nil { dismiss() }

        guard let scene = activeWindowScene() else { return }

        let host = UIHostingController(
            rootView: StressCelebrationOverlay(event: event) {
                CelebrationCoordinator.shared.acknowledge()
            }
        )
        host.view.backgroundColor = .clear

        let win = CelebrationPassthroughWindow(windowScene: scene)
        win.rootViewController = host
        win.windowLevel = .alert + 1
        win.backgroundColor = .clear
        win.isHidden = false
        window = win
    }

    private func dismiss() {
        window?.isHidden = true
        window = nil
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }
}

/// Window whose root view is touch-transparent — only the overlay's own subviews
/// (scrim + card) intercept taps. Background touches fall through to the app
/// underneath. The overlay's scrim covers the full screen, so in practice this
/// just guards against the unlikely case where the host view's bounds extend
/// beyond the scrim.
private final class CelebrationPassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === rootViewController?.view { return nil }
        return hit
    }
}
