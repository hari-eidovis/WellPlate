//
//  CadenceApp.swift
//  Cadence
//
//  Created by Hari's Mac on 26.01.2026.
//  Updated by Claude on 16.02.2026.
//

import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    @StateObject private var promptCoordinator = DailyPromptCoordinator()
    @StateObject private var tabSelector = TabSelector()

    init() {
        // Log current configuration on app start
        AppConfig.shared.logCurrentMode()

        // Trigger API client factory initialization to log which client is being used
        _ = APIClientFactory.shared

        // Hook the global stress-drop celebration overlay into its own UIWindow
        // so it can appear over any tab or presented sheet.
        CelebrationWindowPresenter.shared.install()

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
                .environmentObject(promptCoordinator)
                .environmentObject(tabSelector)
        }
        .modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, InterventionSession.self, FastingSchedule.self, FastingSession.self, FastingEligibility.self, JournalEntry.self, SymptomEntry.self, SupplementEntry.self, AdherenceLog.self, ManualDailyInput.self, StressChangeEntry.self])

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
                "  → Add Files to Cadence...",
                "  → Choose Cadence/Resources/MockData",
                "  → Select 'Create folder references' (blue icon)",
                "  → Enable 'Cadence' target",
                "",
                "Then confirm it appears under Build Phases → Copy Bundle Resources"
            ])
        }
    }
    #endif
}
