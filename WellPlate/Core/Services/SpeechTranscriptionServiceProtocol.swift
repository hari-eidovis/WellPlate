import Foundation

enum SpeechTranscriptionError: LocalizedError {
    case permissionDenied
    case recognitionUnavailable
    case noSpeechDetected
    case engineError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition access was denied. Enable it in Settings."
        case .recognitionUnavailable:
            return "Speech recognition is not available right now."
        case .noSpeechDetected:
            return "No speech was detected. Try speaking more clearly."
        case .engineError(let message):
            return message
        }
    }
}

@MainActor
protocol SpeechTranscriptionServiceProtocol: AnyObject {
    var hasPermission: Bool { get }

    func requestPermissions() async throws

    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws

    func stopTranscription()
    func cancelTranscription()
}
