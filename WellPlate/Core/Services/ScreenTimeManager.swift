//
//  ScreenTimeManager.swift
//  WellPlate
//
//  Created on 21.02.2026.
//
//  NOTE: The DeviceActivityReport extension runs in a privacy sandbox.
//  It cannot write data (UserDefaults, CoreData, network) back to the main app.
//  The DeviceActivityReport view is VISUAL ONLY — used to display screen time in the UI.
//
//  The only supported way to get a numeric value into the main app is via
//  DeviceActivityMonitor threshold events, which fire when the user crosses
//  a usage milestone (every 15 min here) and CAN write to a shared App Group.

import Foundation
import Combine

enum ScreenTimeAccuracy {
    case nearestThreshold15m
    case unavailable
}

struct ScreenTimeReading {
    let rawHours: Double
    let displayRoundedHours: Int
    let accuracy: ScreenTimeAccuracy
}

#if canImport(FamilyControls)
import FamilyControls
import DeviceActivity

@MainActor
final class ScreenTimeManager: ObservableObject {

    // MARK: - Constants

    static let shared = ScreenTimeManager()
    static let appGroupID = "group.com.hariom.wellplate"
    static let thresholdKey = "screenTimeThresholdHours"
    static let thresholdDateKey = "screenTimeThresholdDate"
    private static let logPrefix = "[ScreenTimeManager]"

    // MARK: - Published State

    @Published var isAuthorized = false
    @Published var authorizationError: String?

    // MARK: - Private

    private let center = DeviceActivityCenter()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Init

    private init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            authorizationError = nil
        } catch {
            isAuthorized = false
            authorizationError = error.localizedDescription
        }
    }

    // MARK: - Monitoring

    /// Schedule daily monitoring with thresholds starting at 4h, then every 1h up to 12h.
    /// When the user crosses each threshold, DeviceActivityMonitor fires
    /// and writes the value to the shared App Group UserDefaults.
    func startMonitoring() {
        guard isAuthorized else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // Non-uniform schedule: ±7.5 min resolution for < 2h (where most users fall),
        // ±15 min for 2–4h, ±1h for 4–12h. 17 events total.
        let thresholdMinutes = [15, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300, 360, 480, 600, 720]
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in thresholdMinutes {
            let name = DeviceActivityEvent.Name("threshold_\(minutes)m")
            events[name] = DeviceActivityEvent(
                threshold: DateComponents(hour: minutes / 60, minute: minutes % 60)
            )
        }

        do {
            try center.startMonitoring(
                .init("daily_screen_time"),
                during: schedule,
                events: events
            )
        } catch {
            WPLogger.stress.error("ScreenTimeManager failed to start monitoring: \(error)")
        }
    }

    func stopMonitoring() {
        center.stopMonitoring([.init("daily_screen_time")])
    }

    // MARK: - Read Threshold Data

    /// Returns the latest threshold-based reading for today from the shared App Group.
    /// Resolution: ±7.5 min for < 2h, ±15 min for 2–4h, ±1h for 4–12h.
    /// Returns nil if the user hasn't crossed the first 15-minute threshold yet today.
    var currentAutoDetectedReading: ScreenTimeReading? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return nil }

        let today = Self.todayDateString()
        let storedDate = defaults.string(forKey: Self.thresholdDateKey)

        #if DEBUG
        let rawThreshold: String = defaults.object(forKey: Self.thresholdKey) != nil
            ? String(defaults.double(forKey: Self.thresholdKey))
            : "nil"
        WPLogger.stress.debug("ScreenTime snapshot: thresholdDate=\(storedDate ?? "nil") raw=\(rawThreshold) today=\(today)")
        #endif

        // Clean stale data from a previous day
        if let storedDate, storedDate != today {
            defaults.removeObject(forKey: Self.thresholdKey)
            defaults.removeObject(forKey: Self.thresholdDateKey)
            WPLogger.stress.debug("ScreenTime: cleaned stale threshold from \(storedDate)")
            return nil
        }

        guard let storedDate, storedDate == today,
              defaults.object(forKey: Self.thresholdKey) != nil else {
            WPLogger.stress.debug("ScreenTime: no threshold data for today yet (user < 15 min usage)")
            return nil
        }

        let hours = max(0, defaults.double(forKey: Self.thresholdKey))
        guard hours > 0 else { return nil }

        WPLogger.stress.debug("ScreenTime: fetched thresholdHours=\(hours)")

        return ScreenTimeReading(
            rawHours: hours,
            displayRoundedHours: Int(hours.rounded()),
            accuracy: .nearestThreshold15m
        )
    }

    var currentAutoDetectedHours: Int? {
        currentAutoDetectedReading?.displayRoundedHours
    }

    // MARK: - Helpers

    static func todayDateString() -> String {
        dayFormatter.string(from: Date())
    }
}

#else

// MARK: - Stub for Simulator / platforms without FamilyControls

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    static let appGroupID = "group.com.hariom.wellplate"

    @Published var isAuthorized = false
    @Published var authorizationError: String? = "FamilyControls not available"

    private init() {}

    func requestAuthorization() async { /* no-op */ }
    func startMonitoring() { /* no-op */ }
    func stopMonitoring() { /* no-op */ }

    var currentAutoDetectedReading: ScreenTimeReading? { nil }
    var currentAutoDetectedHours: Int? { nil }

    static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
#endif
