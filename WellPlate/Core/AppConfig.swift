//
//  AppConfig.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Application-wide configuration manager.
final class AppConfig {
    static let shared = AppConfig()

    private enum Keys {
        static let mockMode = "app.networking.mockMode"
        static let groqModel = "app.nutrition.groqModel"
        static let legacyGeminiModel = "app.nutrition.geminiModel"
        static let mockResponseDelay = "app.nutrition.mockResponseDelay"
        static let apiTimeout = "app.networking.apiTimeout"
    }

    private init() {}

    /// Single source of truth for nutrition mode.
    /// - true: use local mock nutrition responses
    /// - false: use real Groq API
    var mockMode: Bool {
        get {
            #if DEBUG
            guard UserDefaults.standard.object(forKey: Keys.mockMode) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: Keys.mockMode)
            #else
            return false
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue, forKey: Keys.mockMode)
            print("🔧 [AppConfig] Mock Mode changed to: \(newValue)")
            #endif
        }
    }

    var groqModel: String {
        get {
            #if DEBUG
            if let value = UserDefaults.standard.string(forKey: Keys.groqModel)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            if let legacyValue = UserDefaults.standard.string(forKey: Keys.legacyGeminiModel)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyValue.isEmpty {
                return legacyValue
            }
            #endif
            return "llama-3.3-70b-versatile"
        }
        set {
            #if DEBUG
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(value, forKey: Keys.groqModel)
            #endif
        }
    }

    var mockResponseDelay: TimeInterval {
        get {
            #if DEBUG
            guard UserDefaults.standard.object(forKey: Keys.mockResponseDelay) != nil else {
                return 0.5
            }
            return UserDefaults.standard.double(forKey: Keys.mockResponseDelay)
            #else
            return 0.0
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(max(0.0, newValue), forKey: Keys.mockResponseDelay)
            #endif
        }
    }

    var apiTimeout: TimeInterval {
        get {
            #if DEBUG
            guard UserDefaults.standard.object(forKey: Keys.apiTimeout) != nil else {
                return 30.0
            }
            return max(1.0, UserDefaults.standard.double(forKey: Keys.apiTimeout))
            #else
            return 30.0
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(max(1.0, newValue), forKey: Keys.apiTimeout)
            #endif
        }
    }

    var hasGroqAPIKey: Bool {
        guard let key = SecretsLoader.groqAPIKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nutritionSourceLabel: String {
        mockMode ? "Mock" : "Groq"
    }

    /// Log current configuration.
    func logCurrentMode() {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔧 [AppConfig] Mock Mode: \(mockMode ? "ENABLED ✅" : "DISABLED ❌")")
        print("🧠 [AppConfig] Nutrition Source: \(nutritionSourceLabel)")
        print("🔐 [AppConfig] Groq API Key: \(hasGroqAPIKey ? "PRESENT ✅" : "MISSING ❌")")
        print("🤖 [AppConfig] Groq Model: \(groqModel)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
    }
}
