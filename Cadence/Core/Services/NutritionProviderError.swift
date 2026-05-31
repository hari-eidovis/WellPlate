import Foundation

enum NutritionProviderError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponseShape
    case invalidModelOutput
    case requestFailed(statusCode: Int, message: String?)
    case timeout
    case network(Error)
}

extension NutritionProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key is missing."
        case .invalidURL:
            return "Invalid Groq URL configuration."
        case .invalidResponseShape:
            return "Groq returned an unexpected response shape."
        case .invalidModelOutput:
            return "Groq returned invalid nutrition JSON."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Groq request failed (\(statusCode)): \(message)"
            }
            return "Groq request failed with status code \(statusCode)."
        case .timeout:
            return "Groq request timed out."
        case .network(let error):
            return "Groq network error: \(error.localizedDescription)"
        }
    }
}
