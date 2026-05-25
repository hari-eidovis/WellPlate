//
//  HapticService.swift
//  WellPlate
//
//  Created on 28.02.2026.
//

import UIKit

/// Centralized haptic feedback utility.
/// Uses pre-warmed generators for responsive feedback.
enum HapticService {

    // MARK: - Generators (lazy, thread-safe)

    private static let lightImpact   = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact  = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact   = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidImpact   = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact    = UIImpactFeedbackGenerator(style: .soft)
    private static let notification  = UINotificationFeedbackGenerator()
    private static let selection     = UISelectionFeedbackGenerator()

    // MARK: - Public API

    /// Triggers an impact haptic with the given style.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            lightImpact.impactOccurred()
        case .medium:
            mediumImpact.impactOccurred()
        case .heavy:
            heavyImpact.impactOccurred()
        case .rigid:
            rigidImpact.impactOccurred()
        case .soft:
            softImpact.impactOccurred()
        @unknown default:
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    /// Triggers a notification haptic (success, error, warning).
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }

    /// Triggers a selection-changed tick.
    static func selectionChanged() {
        selection.selectionChanged()
    }

    /// Double light tap — fired when the AI narrator starts speaking.
    static func narratorStart() {
        lightImpact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            lightImpact.impactOccurred()
        }
    }

    /// Success notification followed by three rigid pulses — fired when a daily goal is fully met.
    static func goalAchieved() {
        notification.notificationOccurred(.success)
        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                rigidImpact.impactOccurred()
            }
        }
    }

    /// Heavy, attention-grabbing celebration burst — fired when the stress
    /// score drops sharply. Layers a success notification, an escalating
    /// crescendo of heavy/rigid impacts, and a closing success tap so the
    /// sensation lasts ~0.9s.
    static func celebrationBurst() {
        notification.notificationOccurred(.success)
        let pattern: [(delay: Double, gen: UIImpactFeedbackGenerator, intensity: CGFloat)] = [
            (0.00, heavyImpact,  1.0),
            (0.08, rigidImpact,  0.8),
            (0.16, mediumImpact, 0.7),
            (0.24, rigidImpact,  0.9),
            (0.34, heavyImpact,  1.0),
            (0.46, rigidImpact,  0.7),
            (0.56, rigidImpact,  0.9),
            (0.70, heavyImpact,  1.0)
        ]
        for step in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                step.gen.impactOccurred(intensity: step.intensity)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) {
            notification.notificationOccurred(.success)
        }
    }

    /// Pre-warms all generators. Call early (e.g. on app launch) for best latency.
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        notification.prepare()
        selection.prepare()
    }
}
