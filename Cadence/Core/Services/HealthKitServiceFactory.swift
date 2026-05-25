//
//  HealthKitServiceFactory.swift
//  WellPlate
//
//  Factory for providing the appropriate HealthKitServiceProtocol implementation.
//  Returns MockHealthKitService or real HealthKitService based on AppConfig.mockMode.
//
//  IMPORTANT: This factory caches the service instance on first access.
//  Changing mockMode requires app restart for changes to take effect.
//

import Foundation

enum HealthKitServiceFactory {

    /// Cached singleton — evaluated once at first access.
    private static let _shared: HealthKitServiceProtocol = {
        #if DEBUG
        if AppConfig.shared.mockMode {
            WPLogger.app.block(emoji: "🎭", title: "HEALTHKIT · MOCK", lines: [
                "Mode: Offline — serving StressMockSnapshot data",
                "Toggle: AppConfig.shared.mockMode = false → restart"
            ])
            return MockHealthKitService(snapshot: .default)
        }
        #endif
        return HealthKitService()
    }()

    /// Shared instance — returns cached singleton.
    static var shared: HealthKitServiceProtocol { _shared }

    /// Whether health data is available (real HK or mock).
    /// Use this instead of `HealthKitService.isAvailable` everywhere.
    static var isDataAvailable: Bool {
        #if DEBUG
        if AppConfig.shared.mockMode { return true }
        #endif
        return HealthKitService.isAvailable
    }

    // MARK: - Testing Support

    #if DEBUG
    private(set) static var _testInstance: HealthKitServiceProtocol?

    static func setTestInstance(_ instance: HealthKitServiceProtocol?) {
        _testInstance = instance
    }

    static var testable: HealthKitServiceProtocol {
        _testInstance ?? _shared
    }
    #endif
}
