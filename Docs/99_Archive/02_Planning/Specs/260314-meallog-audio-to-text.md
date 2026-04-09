# Implementation Plan: MealLog Audio-to-Text Transcription (Phase 1)

> **Revision history**
> - v1 — initial plan
> - v2 (2026-03-14) — audit fixes applied; see [Audit Resolution Checklist](#audit-resolution-checklist) at end of document

## Overview

Repurpose the existing `mic.fill` quick action button in `MealLogView` to trigger live speech-to-text transcription using Apple's on-device `Speech` + `AVAudioEngine` stack. The final transcript populates only the `foodDescription` field. No audio is persisted. The existing save pipeline is unchanged.

## Requirements

- Tapping "Speak meal" starts live on-device speech recognition
- A live transcript preview appears below the food field while recording is active
- Recording stops on tap or after ~25s hard timeout (silence detection handled by framework natively)
- If `foodDescription` is empty, the transcript replaces it; if it has text, append with a space
- Microphone and speech recognition permissions are requested on first use with a clear description
- Permission denial shows a user-facing alert with a Settings deep-link (no crash, no silent failure)
- No raw audio saved; no SwiftData model changes; `voiceNoteSection` untouched

## Architecture Changes

- New: `WellPlate/Core/Services/SpeechTranscriptionServiceProtocol.swift`
- New: `WellPlate/Core/Services/AppleSpeechTranscriptionService.swift`
- Modified: `WellPlate/Features + UI/Home/ViewModels/MealLogViewModel.swift` — new transcription state + methods
- Modified: `WellPlate/Features + UI/Home/Views/MealLogView.swift` — mic button state, live preview, permission alert
- Modified: `WellPlate.xcodeproj` — two new `INFOPLIST_KEY_*` entries via Xcode target Info tab

> **Pre-flight:** Verify `Speech.framework` is listed under the main target's "Frameworks, Libraries, and Embedded Content" in Xcode. It is not auto-linked. If missing, add it before building.

---

## Implementation Steps

### Phase 1: Service Layer

#### Step 1 — Create `SpeechTranscriptionServiceProtocol.swift`

**File:** `WellPlate/Core/Services/SpeechTranscriptionServiceProtocol.swift`

**Action:** Define the protocol that `AppleSpeechTranscriptionService` will conform to and `MealLogViewModel` will depend on.

```swift
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
        case .engineError(let msg):
            return msg
        }
    }
}

/// Contract for live speech-to-text. Conforms to AnyObject so the VM can hold a weak reference.
@MainActor
protocol SpeechTranscriptionServiceProtocol: AnyObject {
    /// Live query of system permission state. Never cached — always reflects current Settings value.
    var hasPermission: Bool { get }

    /// Requests microphone + speech recognition permissions.
    /// Throws `SpeechTranscriptionError.permissionDenied` if either is denied.
    func requestPermissions() async throws

    /// Starts a live recognition session. Calls `onPartial` with each in-flight transcript
    /// and `onFinal` with the committed text when the session ends (stop called or timeout).
    /// Throws `SpeechTranscriptionError` on setup failure.
    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws

    /// Stops the current session and commits the final transcript.
    func stopTranscription()

    /// Cancels without committing any transcript.
    func cancelTranscription()
}
```

**Why:** Abstracting behind a protocol lets `MealLogViewModel` be tested with a mock, and keeps Apple-framework imports out of the ViewModel.

**Risk:** Low.

---

#### Step 2 — Create `AppleSpeechTranscriptionService.swift`

**File:** `WellPlate/Core/Services/AppleSpeechTranscriptionService.swift`

**Action:** Concrete implementation using `Speech` + `AVAudioEngine`.

```swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class AppleSpeechTranscriptionService: SpeechTranscriptionServiceProtocol {

    // MARK: - Permission (live query — never cached)

    /// Always reads from the system. Reflects permission revocations without relaunch.
    var hasPermission: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted &&
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - State

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    // Hard timeout: auto-stop after this many seconds.
    // Note: the framework ends the session itself after a few seconds of silence — this
    // is a backstop to prevent indefinite recording if the user walks away.
    private let maxDurationSeconds: TimeInterval = 25
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Permissions

    func requestPermissions() async throws {
        // 1. Microphone — AVAudioSession API available since iOS 7
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micStatus else { throw SpeechTranscriptionError.permissionDenied }

        // 2. Speech recognition
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { throw SpeechTranscriptionError.permissionDenied }
    }

    // MARK: - Transcription

    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognitionUnavailable
        }

        // .playAndRecord ducks background audio rather than cutting it entirely (.record would mute it).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device only — audio never leaves the device.
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            // Use else-if to ensure only one branch runs per callback.
            // Apple can deliver a final result AND a non-nil error in the same invocation;
            // processing both would cause double-teardown on an already-stopped engine.
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    onFinal(text)
                    self.teardown()
                } else {
                    onPartial(text)
                }
            } else if let error {
                let nsErr = error as NSError
                // Code 1110 = no speech detected; 203/301 = cancelled — not user-visible errors.
                if nsErr.code == 1110 {
                    onError(.noSpeechDetected)
                } else if nsErr.code != 203 && nsErr.code != 301 {
                    onError(.engineError(error.localizedDescription))
                }
                self.teardown()
            }
        }

        // Hard timeout backstop
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxDurationSeconds ?? 25))
            guard !Task.isCancelled else { return }
            await self?.stopTranscription()
        }
    }

    func stopTranscription() {
        recognitionRequest?.endAudio()
        // The framework will call the result handler with isFinal = true → onFinal fires → teardown runs.
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func cancelTranscription() {
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        teardown()
    }

    // MARK: - Teardown

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recognitionRequest = nil
        recognitionTask = nil
    }
}
```

**Why:** All audio stays on-device (`requiresOnDeviceRecognition = true`). The `else if` guard on the result handler prevents double-teardown. `.playAndRecord` preserves background audio. `hasPermission` is a live system query, not a stale flag.

**Risk:** Medium — `AVAudioEngine` setup can throw if another app holds the audio session exclusively. The service propagates this as `engineError` which the VM surfaces to the user. On-device recognition may be unavailable on some locales; `recognitionUnavailable` error covers this.

---

### Phase 2: ViewModel

#### Step 3 — Add transcription state to `MealLogViewModel`

**File:** `WellPlate/Features + UI/Home/ViewModels/MealLogViewModel.swift`

**Action:** Add the following properties under the existing `// MARK: - Save flow state` block, then add the three transcription methods at the bottom of the class.

**New properties (after `shouldDismiss`):**

```swift
// MARK: - Transcription state
@Published var isTranscribing: Bool = false
@Published var liveTranscript: String = ""
@Published var showTranscriptionPermissionAlert: Bool = false

// `any` keyword required for existential type in Swift 5.7+
private lazy var speechService: any SpeechTranscriptionServiceProtocol = AppleSpeechTranscriptionService()
```

**New methods (above or beside `showErrorMessage`):**

```swift
// MARK: - Transcription

/// Entry point wired to the "Speak meal" button in MealLogView.
func startMealTranscription() {
    guard !isTranscribing else {
        stopMealTranscription()
        return
    }

    Task {
        if !speechService.hasPermission {
            do {
                try await speechService.requestPermissions()
            } catch {
                showTranscriptionPermissionAlert = true
                return
            }
        }

        do {
            isTranscribing = true
            liveTranscript = ""
            try speechService.startTranscription(
                onPartial: { [weak self] partial in
                    self?.liveTranscript = partial
                },
                onFinal: { [weak self] final in
                    guard let self else { return }
                    self.applyTranscriptToFoodDescription(final)
                    self.liveTranscript = ""
                    self.isTranscribing = false
                },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.liveTranscript = ""
                    self.isTranscribing = false
                    if case .noSpeechDetected = error {
                        // Soft failure — user just didn't speak. Don't clobber existing text.
                        return
                    }
                    self.showErrorMessage(error.localizedDescription ?? "Transcription failed.")
                }
            )
        } catch {
            isTranscribing = false
            liveTranscript = ""
            showErrorMessage(error.localizedDescription ?? "Could not start recording.")
        }
    }
}

func stopMealTranscription() {
    speechService.stopTranscription()
    // Belt-and-suspenders reset: callbacks should clear these, but ensures we never get stuck
    // in a "Listening..." state if the framework delivers neither onFinal nor onError.
    isTranscribing = false
    liveTranscript = ""
}

/// Merges `transcript` into `foodDescription`.
/// Replaces if field is empty; appends with a space if field has existing text.
/// Note: trims both sides before merging — whitespace in `foodDescription` is normalised.
func applyTranscriptToFoodDescription(_ transcript: String) {
    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let existing = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if existing.isEmpty {
        foodDescription = trimmed
    } else {
        foodDescription = existing + " " + trimmed
    }
}
```

**Why:** The ViewModel owns all state changes. The view only calls `startMealTranscription()`. Append vs replace logic lives here, not in the view, so it's easily unit-tested. `stopMealTranscription()` now resets state immediately as a safety net in case callbacks don't fire.

**Risk:** Low.

---

### Phase 3: View

#### Step 4 — Update the mic quick action button

**File:** `WellPlate/Features + UI/Home/Views/MealLogView.swift`

**Action:** In `quickActionRow`, replace the mic button with a stateful version. The other two buttons remain unchanged.

Replace:
```swift
quickActionButton(icon: "mic.fill", label: "Voice note") { /* TODO */ }
```

With:
```swift
speakMealButton
```

Add a new computed property `speakMealButton` in the view (alongside the other `private var` sections):

```swift
// MARK: - Speak Meal Button

private var speakMealButton: some View {
    Button {
        HapticService.impact(.light)
        viewModel.startMealTranscription()
    } label: {
        HStack(spacing: 6) {
            Image(systemName: viewModel.isTranscribing ? "waveform" : "mic.fill")
                .font(.system(size: 14))
                .symbolEffect(.variableColor.iterative, isActive: viewModel.isTranscribing)
            Text(viewModel.isTranscribing ? "Listening..." : "Speak meal")
                .font(.r(.caption, .medium))
        }
        .foregroundColor(viewModel.isTranscribing ? AppColors.primary : AppColors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.isTranscribing
                      ? AppColors.primaryContainer
                      : Color(.secondarySystemBackground))
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTranscribing)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isLoading) // Prevent recording while a save is in-flight
}
```

**Why:** The label "Speak meal" describes what the feature does. The `.disabled(viewModel.isLoading)` guard prevents simultaneous recording + save, consistent with how the food TextField is disabled during saves.

**Risk:** Low.

---

#### Step 5 — Add live transcript preview below the food field

**File:** `WellPlate/Features + UI/Home/Views/MealLogView.swift`

**Action:** Wrap the `foodInputSection` and a new conditional preview into a `VStack`.

In `body`, replace:
```swift
foodInputSection
```

With:
```swift
foodInputGroup
```

Add a new computed property:
```swift
// MARK: - Food Input Group (field + live preview)

private var foodInputGroup: some View {
    VStack(alignment: .leading, spacing: 8) {
        foodInputSection

        if viewModel.isTranscribing {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.primary)
                Text(viewModel.liveTranscript.isEmpty
                     ? "Say the food and amount if you know it..."
                     : viewModel.liveTranscript)
                    .font(.r(.caption, .regular))
                    .foregroundColor(viewModel.liveTranscript.isEmpty
                                     ? AppColors.textSecondary
                                     : AppColors.textPrimary)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.liveTranscript)
            }
            .padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    .animation(.easeInOut(duration: 0.2), value: viewModel.isTranscribing)
}
```

**Why:** The live preview shows speech is being captured without touching `foodDescription` until the session ends. The placeholder copy guides first-time users.

**Risk:** Low.

---

#### Step 6 — Add permission alert and dismiss-time cleanup

**File:** `WellPlate/Features + UI/Home/Views/MealLogView.swift`

**Action:** Two changes:

**A — Add permission alert** after the existing `.alert("Error", ...)`:
```swift
.alert("Microphone Access Required", isPresented: $viewModel.showTranscriptionPermissionAlert) {
    Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("WellPlate needs microphone and speech recognition access to transcribe your meal. Enable both in Settings > Privacy.")
}
```

**B — Stop transcription on manual dismiss** (back button in the toolbar):
```swift
// Replace the existing back button action:
Button {
    HapticService.impact(.light)
    if viewModel.isTranscribing { viewModel.stopMealTranscription() }
    dismiss()
} label: {
    Image(systemName: "chevron.left")
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(AppColors.primary)
}
```

> The existing `onChange(of: viewModel.shouldDismiss)` block does **not** need changes — `speechService` deinits with the ViewModel when the sheet is dismissed via `shouldDismiss`, running teardown automatically. Do not add any `viewModel.speechService` access in the view (it is `private`).

**Why:** Settings deep-link is the standard iOS recovery pattern for denied permissions. Explicit stop on manual dismiss ensures the audio engine is not running after the sheet is gone.

**Risk:** Low.

---

### Phase 4: Project Settings

#### Step 7 — Add Info.plist privacy keys

**Target:** Main `WellPlate` app target

**Action:** In Xcode, select the `WellPlate` target → **Info** tab → **Custom iOS Target Properties**. Add two new keys (do not edit `project.pbxproj` manually — the Xcode UI is less error-prone):

| Key | Value |
|-----|-------|
| `NSMicrophoneUsageDescription` | `WellPlate uses the microphone so you can speak meal entries instead of typing them.` |
| `NSSpeechRecognitionUsageDescription` | `WellPlate converts your speech into text to help you log meals faster.` |

Xcode will write the corresponding `INFOPLIST_KEY_*` entries to the pbxproj automatically for both Debug and Release configurations.

**Why:** Without these two keys the app crashes at runtime with a privacy entitlement assertion on the first call to `requestRecordPermission` or `requestAuthorization`. Apple reviewers also check that the strings accurately reflect actual usage.

**Risk:** High if skipped — guaranteed runtime crash on first recording attempt.

---

## Testing Strategy

### Unit Tests

Create `WellPlateTests/MealLogViewModelTranscriptionTests.swift`.

Include a `MockSpeechTranscriptionService` at the top of the file that conforms to `SpeechTranscriptionServiceProtocol` and exposes `capturedOnPartial`, `capturedOnFinal`, `capturedOnError` closure handles for test-driving callbacks.

Test cases:

- `test_startTranscription_setsIsTranscribing_true` — mock service, verify `isTranscribing == true` after start
- `test_onFinal_replacesEmptyField` — `foodDescription = ""`, fire `onFinal("oatmeal")` → `"oatmeal"`
- `test_onFinal_appendsToExistingText` — `foodDescription = "rice"`, fire `onFinal("and dal")` → `"rice and dal"`
- `test_onFinal_trimsExistingWhitespace` — `foodDescription = "  rice  "`, fire `onFinal("and dal")` → `"rice and dal"` (whitespace normalised)
- `test_permissionDenied_showsAlert` — mock throws `.permissionDenied`, verify `showTranscriptionPermissionAlert == true`
- `test_noSpeechDetected_doesNotClobberExistingText` — fire `onError(.noSpeechDetected)`, verify existing `foodDescription` unchanged
- `test_stopToggle_whenAlreadyRecording` — call `startMealTranscription()` twice, verify second call delegates to `stop`
- `test_stopMealTranscription_resetsStateImmediately` — verify `isTranscribing` and `liveTranscript` clear on `stopMealTranscription()` even before callbacks fire

### Manual QA Checklist

- [ ] First launch: both permission dialogs appear in sequence (microphone then speech recognition)
- [ ] Deny microphone → "Microphone Access Required" alert with "Open Settings" appears
- [ ] Deny speech recognition → same alert
- [ ] Grant permissions, speak "two eggs and a banana" → live preview updates in real-time; commits to food field on stop
- [ ] Speak with existing typed text "oatmeal" → transcript appended
- [ ] Tap "Listening..." to stop mid-speech → partial transcript committed, `isTranscribing` clears
- [ ] Speak nothing, wait 25 seconds → auto-stops without clearing existing text
- [ ] Background noise test (play crowd noise) — transcript is editable before save
- [ ] Dismiss sheet via back button while recording → no audio engine crash on next open
- [ ] Start recording, save is triggered by external means → mic button is disabled during `isLoading`
- [ ] Revoke microphone in Settings while app is running, then tap "Speak meal" → permission alert fires (not a generic error)

---

## Risks & Mitigations

- **Risk:** `AVAudioEngine` or `SFSpeechRecognizer` unavailable on Simulator
  - Mitigation: `recognizer?.isAvailable` guard throws `recognitionUnavailable`; view shows error. No crash.

- **Risk:** Multiple rapid taps on "Speak meal"
  - Mitigation: `startMealTranscription()` calls `stopMealTranscription()` when `isTranscribing` is already true (toggle pattern).

- **Risk:** Audio session conflicts with system sounds / other apps
  - Mitigation: `setActive(false)` in teardown always runs, even on error paths. `.playAndRecord` + `.duckOthers` is cooperative rather than exclusive.

- **Risk:** Missing Info.plist keys cause runtime crash
  - Mitigation: Step 7 is explicitly called out as high risk; add keys before first device run.

- **Risk:** On-device recognition unavailable for the user's locale
  - Mitigation: `requiresOnDeviceRecognition = true` will throw `recognitionUnavailable` immediately, which is displayed as a user-facing error. No silent fallback to cloud.

- **Risk:** Permission revoked in Settings between sessions
  - Mitigation: `hasPermission` is a live system query (not cached). On next tap, the permission check fails, `requestPermissions()` is called, and the standard OS alert or the Settings deep-link alert fires depending on whether the system shows its own prompt.

---

## Success Criteria

- [ ] Tapping "Speak meal" requests permissions (first time) and starts live transcription
- [ ] `liveTranscript` updates in real-time under the food field while recording
- [ ] Final transcript replaces empty `foodDescription` or appends to existing text
- [ ] Recording auto-stops after ~25 seconds
- [ ] Tapping "Listening..." stops recording immediately and resets state
- [ ] Permission denial shows an actionable alert with a Settings deep link
- [ ] Post-revocation tap shows the permission alert (not a generic error)
- [ ] `voiceNoteSection` is unchanged
- [ ] Existing `saveMeal()` and disambiguation flows work identically
- [ ] No audio files written to disk
- [ ] No SwiftData model changes
- [ ] Mic button disabled while `isLoading`

---

## File Summary

| Action | Path |
|--------|------|
| Create | `WellPlate/Core/Services/SpeechTranscriptionServiceProtocol.swift` |
| Create | `WellPlate/Core/Services/AppleSpeechTranscriptionService.swift` |
| Modify | `WellPlate/Features + UI/Home/ViewModels/MealLogViewModel.swift` |
| Modify | `WellPlate/Features + UI/Home/Views/MealLogView.swift` |
| Modify | `WellPlate.xcodeproj` — Info.plist keys via Xcode target Info tab |
| Create | `WellPlateTests/MealLogViewModelTranscriptionTests.swift` |

---

## Audit Resolution Checklist

Resolved from audit `Docs/05_Audits/Code/260314-meallog-audio-to-text-audit.md` (2026-03-14).

### CRITICAL

- [x] **#1 — Double teardown crash**: Changed `if let error` to `else if let error` in the `recognitionTask` closure. Apple can deliver both a final result and a non-nil error in the same callback; the `else if` ensures only one branch runs and `teardown()` is never called twice.

- [x] **#2 — `requiresOnDeviceRecognition = false` contradicts privacy goal**: Changed to `true`. Audio never leaves the device. If on-device recognition is unavailable for a locale, the service throws `recognitionUnavailable` and the user sees a clear error.

### HIGH

- [x] **#3 — `AVAudioApplication.requestRecordPermission` iOS 17+ only**: Replaced with `AVAudioSession.sharedInstance().requestRecordPermission` (available since iOS 7). Resolves potential build failure on any deployment target below iOS 17.

- [x] **#4 — `.symbolEffect(.variableColor.iterative, isActive:)` iOS 17+ only**: Project targets iOS 26.1 (confirmed from project memory). iOS 26.1 > iOS 17, so this API is available. No change required; noted as resolved by deployment target confirmation.

- [x] **#5 — Stale `hasPermission` flag after permission revocation**: Replaced `private(set) var hasPermission: Bool = false` (set once, never re-checked) with a computed property that queries `AVAudioSession.recordPermission` and `SFSpeechRecognizer.authorizationStatus()` live. Post-revocation taps now correctly reach the permission alert rather than a generic error.

- [x] **#6 — Broken no-op `viewModel.speechService` in Step 6**: Removed the dead-code line entirely. The `onChange` block for `shouldDismiss` is left unchanged from the original — `speechService` deinits with the ViewModel naturally. Only the back-button explicit stop was added (a net-new change, not a replacement of the existing block).

### MEDIUM

- [x] **#7 — `.record` audio category mutes background music**: Changed `setCategory(.record, ...)` to `setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)`. Background audio is now ducked, not silenced.

- [x] **#8 — `stopMealTranscription()` relied solely on callbacks to reset state**: Added immediate `isTranscribing = false` and `liveTranscript = ""` in `stopMealTranscription()` as a safety net. The UI resets instantly on tap regardless of whether `onFinal`/`onError` fires.

- [x] **#9 — `lazy var speechService` missing `any` keyword**: Changed to `private lazy var speechService: any SpeechTranscriptionServiceProtocol`. Correct Swift 5.7+ existential syntax.

- [x] **#10 — `isLoading` + `isTranscribing` simultaneously possible**: Added `.disabled(viewModel.isLoading)` to `speakMealButton`, consistent with the food TextField's disabled state during saves.

### LOW

- [x] **#11 — Silence-based auto-stop mechanism not explained**: Added a clarifying comment in the service and in the Requirements section. Framework handles silence detection natively (typically 2-3s of silence). The 25s `Task` is an explicit hard-cap backstop, not the primary silence mechanism.

- [x] **#12 — Missing test for `applyTranscriptToFoodDescription` whitespace trim**: Added `test_onFinal_trimsExistingWhitespace` to the unit test list.

- [x] **#13 — `Speech.framework` linkage not mentioned**: Added a pre-flight note at the top of the Architecture Changes section.

### UNRESOLVED / DEFERRED

- [ ] **Backgrounding mid-session**: The plan does not handle `AVAudioSession.interruptionNotification` (phone call, Siri, etc.). Deferred to a follow-up — the existing teardown-on-deinit path is a reasonable v1 fallback. Track as a known gap.
