import AVFoundation
import Foundation
import Speech

@MainActor
final class AppleSpeechTranscriptionService: SpeechTranscriptionServiceProtocol {
    var hasPermission: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted &&
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let maxDurationSeconds: TimeInterval = 25
    private var timeoutTask: Task<Void, Never>?
    private var isTapInstalled = false

    func requestPermissions() async throws {
        let hasMicrophoneAccess = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard hasMicrophoneAccess else {
            throw SpeechTranscriptionError.permissionDenied
        }

        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechTranscriptionError.permissionDenied
        }
    }

    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws {
        guard hasPermission else {
            throw SpeechTranscriptionError.permissionDenied
        }
        // `supportsOnDeviceRecognition` is intentionally not checked here — on first use the
        // on-device model may still be downloading, causing a false-negative. The recognition
        // task itself will fail with a system error if on-device isn't ready, which is surfaced
        // via `onError(.recognitionUnavailable)` through the standard callback path.
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognitionUnavailable
        }

        if recognitionTask != nil || audioEngine.isRunning {
            cancelTranscription()
        }

        let session = AVAudioSession.sharedInstance()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            isTapInstalled = true

            recognitionRequest = request
            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        let text = result.bestTranscription.formattedString
                        if result.isFinal {
                            onFinal(text)
                            self.teardown()
                        } else {
                            onPartial(text)
                        }
                    } else if let error {
                        let nsError = error as NSError
                        if nsError.code == 1110 {
                            onError(.noSpeechDetected)
                        } else if nsError.code != 203 && nsError.code != 301 {
                            onError(.engineError(error.localizedDescription))
                        }
                        self.teardown()
                    }
                }
            }

            timeoutTask = Task { [weak self] in
                let duration = self?.maxDurationSeconds ?? 25
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                await self?.stopTranscription()
            }
        } catch {
            teardown()
            throw SpeechTranscriptionError.engineError(error.localizedDescription)
        }
    }

    func stopTranscription() {
        recognitionRequest?.endAudio()
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func cancelTranscription() {
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        teardown()
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recognitionRequest = nil
        recognitionTask = nil
    }
}
