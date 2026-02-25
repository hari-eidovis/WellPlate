//
//  ScreenTimeMonitorExtension.swift
//  ScreenTimeMonitor
//
//  Created on 21.02.2026.
//

import DeviceActivity
import Foundation

/// DeviceActivityMonitor extension that fires when hourly usage thresholds are reached.
/// Writes the current threshold value to a shared App Group UserDefaults so the main app
/// can read it for stress scoring.
class ScreenTimeMonitorExtension: DeviceActivityMonitor {

    private let appGroupID = "group.com.hariom.wellplate"
    private let thresholdKey = "screenTimeThresholdHours"
    private let thresholdDateKey = "screenTimeThresholdDate"

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    // MARK: - Interval Start (new day)

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(dayFormatter.string(from: Date()), forKey: thresholdDateKey)
        // Clear previous threshold value at day start. A zero value is ambiguous and should
        // not be treated as real usage by the app-side resolver.
        defaults.removeObject(forKey: thresholdKey)
        #if DEBUG
        print("[ScreenTimeMonitorExtension] intervalDidStart reset threshold for \(activity.rawValue)")
        #endif
    }

    // MARK: - Threshold Reached

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        // Event names follow pattern: "threshold_Xm" (minutes)
        let name = event.rawValue
        guard let suffix = name.split(separator: "_").last else { return }

        // Parse the minute value (remove trailing "m"), convert to hours
        let hours: Double
        if suffix.hasSuffix("m") {
            guard let minutes = Double(suffix.dropLast()) else { return }
            hours = minutes / 60.0
        } else if suffix.hasSuffix("h") {
            // Legacy hourly format
            guard let h = Double(suffix.dropLast()) else { return }
            hours = h
        } else {
            return
        }

        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let current = defaults.double(forKey: thresholdKey)
        if hours > current {
            defaults.set(hours, forKey: thresholdKey)
            defaults.set(dayFormatter.string(from: Date()), forKey: thresholdDateKey)
            #if DEBUG
            print("[ScreenTimeMonitorExtension] event=\(name) wrote thresholdHours=\(hours) previous=\(current)")
            #endif
        } else {
            #if DEBUG
            print("[ScreenTimeMonitorExtension] event=\(name) ignored thresholdHours=\(hours) current=\(current)")
            #endif
        }
    }

    // MARK: - Interval End

    override func intervalDidEnd(for activity: DeviceActivityName) {
        // Data stays in UserDefaults for the main app to read until next day reset
    }
}
