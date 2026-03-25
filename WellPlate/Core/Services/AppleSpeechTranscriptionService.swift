import AVFoundation
import Foundation
import Speech
import OSLog

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
        WPLogger.speech.info("Requesting microphone + speech recognition permissions…")

        let hasMicrophoneAccess = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard hasMicrophoneAccess else {
            WPLogger.speech.error("Permission denied — microphone access refused by user")
            throw SpeechTranscriptionError.permissionDenied
        }

        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            WPLogger.speech.error("Permission denied — speech recognition status: \(String(describing: speechStatus))")
            throw SpeechTranscriptionError.permissionDenied
        }

        WPLogger.speech.info("Permissions granted — mic ✓  speech recognition ✓")
    }

    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws {
        guard hasPermission else {
            WPLogger.speech.error("startTranscription aborted — permissions not granted")
            throw SpeechTranscriptionError.permissionDenied
        }
        // `supportsOnDeviceRecognition` is intentionally not checked here — on first use the
        // on-device model may still be downloading, causing a false-negative. The recognition
        // task itself will fail with a system error if on-device isn't ready, which is surfaced
        // via `onError(.recognitionUnavailable)` through the standard callback path.
        guard let recognizer, recognizer.isAvailable else {
            WPLogger.speech.error("startTranscription aborted — SFSpeechRecognizer unavailable for locale \(Locale.current.identifier)")
            throw SpeechTranscriptionError.recognitionUnavailable
        }

        if recognitionTask != nil || audioEngine.isRunning {
            WPLogger.speech.warning("Previous session still active — cancelling before starting new one")
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

            WPLogger.speech.block(
                emoji: "▶️",
                title: "SESSION START",
                lines: [
                    "Locale:       \(Locale.current.identifier)",
                    "On-device:    ✓  (requiresOnDeviceRecognition)",
                    "Max duration: \(Int(maxDurationSeconds))s",
                    "Partial:      ✓  (shouldReportPartialResults)",
                    "Buffer size:  1024 frames"
                ]
            )

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        let text = result.bestTranscription.formattedString
                        if result.isFinal {
                            let wordCount = text.split(separator: " ").count
                            WPLogger.speech.block(
                                emoji: "✅",
                                title: "TRANSCRIPT FINAL",
                                lines: [
                                    "Words:   \(wordCount)",
                                    "Text:    \"\(text)\""
                                ]
                            )
                            onFinal(text)
                            self.teardown()
                        } else {
                            WPLogger.speech.debug("Partial: \"\(text)\"")
                            onPartial(text)
                        }
                    } else if let error {
                        let nsError = error as NSError
                        if nsError.code == 1110 {
                            WPLogger.speech.info("No speech detected (code 1110) — silent timeout")
                            onError(.noSpeechDetected)
                        } else if nsError.code != 203 && nsError.code != 301 {
                            WPLogger.speech.error("Recognition engine error (code \(nsError.code)): \(error.localizedDescription)")
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
                WPLogger.speech.warning("Max duration (\(Int(duration))s) reached — sending endAudio")
                await self?.stopTranscription()
            }
        } catch {
            WPLogger.speech.error("Audio engine setup failed: \(error.localizedDescription)")
            teardown()
            throw SpeechTranscriptionError.engineError(error.localizedDescription)
        }
    }

    func stopTranscription() {
        WPLogger.speech.info("Stop requested — sending endAudio signal, awaiting final result")
        recognitionRequest?.endAudio()
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func cancelTranscription() {
        WPLogger.speech.warning("Transcription cancelled — no final result will be delivered")
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
        WPLogger.speech.debug("Audio engine torn down — session resources released")
    }
}
