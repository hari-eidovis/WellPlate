//
//  WellPlateApp.swift
//  WellPlate
//
//  Created by Hari's Mac on 26.01.2026.
//  Updated by Claude on 16.02.2026.
//

import SwiftUI
import SwiftData

@main
struct WellPlateApp: App {
    init() {
        // Log current configuration on app start
        AppConfig.shared.logCurrentMode()

        // Trigger API client factory initialization to log which client is being used
        _ = APIClientFactory.shared

        #if DEBUG
        // Verify MockData bundle inclusion (only in DEBUG builds)
        if AppConfig.shared.mockMode {
            verifyMockDataBundle()
        }
        #endif
    }


    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self])

    }

    #if DEBUG
    /// Verify that MockData folder is properly included in the bundle
    private func verifyMockDataBundle() {
        if Bundle.main.url(forResource: "MockData", withExtension: nil) != nil {
            WPLogger.app.info("MockData folder found in bundle ✅")
        } else {
            WPLogger.app.block(emoji: "❌", title: "MOCK DATA MISSING", lines: [
                "MockData folder NOT found in bundle!",
                "Mock mode is ON but all API calls will fail.",
                "",
                "Fix: Right-click Resources in Xcode",
                "  → Add Files to WellPlate...",
                "  → Choose WellPlate/Resources/MockData",
                "  → Select 'Create folder references' (blue icon)",
                "  → Enable 'WellPlate' target",
                "",
                "Then confirm it appears under Build Phases → Copy Bundle Resources"
            ])
        }
    }
    #endif
}
