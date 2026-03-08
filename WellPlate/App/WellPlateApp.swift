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
        .modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self])

    }

    #if DEBUG
    /// Verify that MockData folder is properly included in the bundle
    private func verifyMockDataBundle() {
        if Bundle.main.url(forResource: "MockData", withExtension: nil) != nil {
            print("✅ [Bundle] MockData folder found in bundle")
        } else {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("❌ [Bundle] WARNING: MockData folder NOT in bundle!")
            print("")
            print("   Mock mode is enabled but MockData folder was not found.")
            print("   This will cause all API calls to fail.")
            print("")
            print("   Solutions:")
            print("   1. Add MockData folder to Xcode project:")
            print("      - Right-click Resources in Xcode")
            print("      - Select 'Add Files to WellPlate...'")
            print("      - Choose WellPlate/Resources/MockData")
            print("      - Select 'Create folder references' (blue icon)")
            print("      - Check 'WellPlate' target")
            print("")
            print("   2. Verify in Build Phases:")
            print("      - Xcode → WellPlate target → Build Phases")
            print("      - Copy Bundle Resources")
            print("      - MockData should appear in the list")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }
    #endif
}
