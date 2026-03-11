import Foundation

enum SecretsLoader {
    private static let plistName = "Secrets"

    static var groqAPIKey: String? {
        value(for: "GROQ_API_KEY")
    }

    static var geminiAPIKey: String? {
        value(for: "GEMINI_API_KEY")
    }

    static func value(for key: String, bundle: Bundle = .main) -> String? {
        if let envValue = ProcessInfo.processInfo.environment[key], !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envValue
        }

        guard
            let url = bundle.url(forResource: plistName, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let rawValue = plist[key] as? String
        else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
