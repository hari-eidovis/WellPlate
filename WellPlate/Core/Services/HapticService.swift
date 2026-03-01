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
    private static let rigidImpact   = UIImpactFeedbackGenerator(style: .rigid)
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
        case .rigid:
            rigidImpact.impactOccurred()
        default:
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

    /// Pre-warms all generators. Call early (e.g. on app launch) for best latency.
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        notification.prepare()
        selection.prepare()
    }
}
