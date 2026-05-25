//
//  InterventionTimer.swift
//  WellPlate
//
//  Phase-aware countdown engine shared by reset session views
//  (PMR, Sigh, and future resets). Uses ObservableObject +
//  @Published to match the project-wide observable pattern.
//

import Foundation
import Combine
import UIKit

// MARK: - Supporting types

struct InterventionPhase {
    let name: String            // e.g. "Tense shoulders", "First inhale"
    let duration: TimeInterval
    let hapticOnStart: HapticPattern?
}

enum HapticPattern {
    case rise    // repeated .heavy impacts every 280ms for the full phase
    case snap    // single .success notification (fired once at phase start)
    case softPulse(count: Int, interval: TimeInterval)
}

// MARK: - InterventionTimer

final class InterventionTimer: ObservableObject {

    // Published state (drives SwiftUI)
    @Published private(set) var currentPhaseIndex: Int = 0
    @Published private(set) var phaseProgress: Double = 0     // 0.0–1.0 within current phase
    @Published private(set) var totalProgress: Double = 0     // 0.0–1.0 across all phases
    @Published private(set) var currentPhaseName: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isComplete: Bool = false

    // Callbacks
    var onPhaseStart: ((InterventionPhase) -> Void)?
    var onComplete: (() -> Void)?

    // Internal state
    private var phases: [InterventionPhase] = []
    private var timer: Timer?
    private var phaseStartTime: Date = .now
    private var totalDuration: TimeInterval = 0
    private var elapsedBeforeCurrentPhase: TimeInterval = 0
    private var isCancelled: Bool = false  // guards dispatched haptic closures

    // MARK: - Public API

    func start(phases: [InterventionPhase]) {
        cancel()
        isCancelled = false
        self.phases = phases
        self.totalDuration = phases.map(\.duration).reduce(0, +)
        currentPhaseIndex = 0
        elapsedBeforeCurrentPhase = 0
        isComplete = false
        beginPhase()
    }

    func cancel() {
        isCancelled = true
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: - Private

    private func beginPhase() {
        guard currentPhaseIndex < phases.count else {
            isComplete = true
            isRunning = false
            timer?.invalidate()
            timer = nil
            onComplete?()
            return
        }
        let phase = phases[currentPhaseIndex]
        currentPhaseName = phase.name
        phaseProgress = 0
        phaseStartTime = .now
        isRunning = true
        fireHaptic(phase.hapticOnStart, duration: phase.duration)
        onPhaseStart?(phase)

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let phase = phases[currentPhaseIndex]
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        phaseProgress = min(elapsed / phase.duration, 1.0)
        totalProgress = min((elapsedBeforeCurrentPhase + elapsed) / totalDuration, 1.0)

        if elapsed >= phase.duration {
            timer?.invalidate()
            timer = nil
            elapsedBeforeCurrentPhase += phase.duration
            currentPhaseIndex += 1
            beginPhase()
        }
    }

    private func fireHaptic(_ pattern: HapticPattern?, duration: TimeInterval) {
        guard let pattern else { return }
        switch pattern {
        case .rise:
            let interval = 0.28
            let count = max(1, Int(duration / interval) - 1)
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                    guard let self, !self.isCancelled else { return }
                    HapticService.impact(.heavy)
                }
            }
        case .snap:
            HapticService.notify(.success)
        case .softPulse(let count, let interval):
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                    guard let self, !self.isCancelled else { return }
                    HapticService.impact(.light)
                }
            }
        }
    }
}
