# Plan Audit Report: MealLog Audio-to-Text Transcription (Phase 1)

**Audit Date**: 2026-03-14
**Plan Version**: v1 — `Docs/02_Planning/Specs/260314-meallog-audio-to-text.md`
**Auditor**: plan-auditor agent
**Verdict**: NEEDS REVISION

## Executive Summary

The plan is well-scoped and architecturally sound at a high level. The protocol abstraction, ViewModel ownership of state, and teardown strategy are all correct. However, there are two bugs in the service code that will cause real failures (double-teardown and a stale `hasPermission` flag), a direct contradiction between the privacy claim and the `requiresOnDeviceRecognition` setting, two iOS 17-only APIs used without a deployment-target check, and a broken no-op code snippet in Step 6 that will produce a compile error. These must be fixed before implementation begins.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### 1. Double teardown crash — `result` and `error` checked in separate `if` blocks

- **Location:** Step 2, `recognitionTask` closure in `AppleSpeechTranscriptionService`
- **Problem:** The closure uses separate `if let result` and `if let error` blocks. Apple's `SFSpeechRecognizer` can and does deliver a final result AND a non-nil error in the same callback invocation (e.g., the session is ending). This means:
  1. `onFinal(text)` is called → `teardown()` runs (stops engine, removes tap, nils request/task)
  2. Then `onError(...)` fires → `teardown()` runs again on an already-torn-down engine
  - `audioEngine.inputNode.removeTap(onBus: 0)` on a stopped engine with no tap installed will throw an assertion in debug and crash in some configurations.
  - `isTranscribing` in the ViewModel would be set `false` twice (harmless), but the duplicate `teardown()` is the real hazard.
- **Recommendation:** Use `else if let error` (not a second `if`), so only one branch runs per callback. Alternatively, add a guard flag (`private var isFinished = false`) at the top of the closure.

---

#### 2. `requiresOnDeviceRecognition = false` contradicts the stated privacy goal

- **Location:** Step 2, `startTranscription` — line `request.requiresOnDeviceRecognition = false`
- **Problem:** The brainstorm explicitly states "All audio stays on-device" and "No need to upload audio" as core reasons for choosing Apple's stack. The plan repeats this in the `Why` section of Step 2. But `requiresOnDeviceRecognition = false` means audio **will be sent to Apple's servers** when on-device recognition is not available (most devices on iOS < 16, and many on iOS 16 if on-device models aren't downloaded). The comment "set true if iOS 16+ on-device quality is sufficient" defers a privacy decision that was already made in the brainstorm.
- **Impact:** Privacy promise in the plan is false. If App Store review or a privacy-conscious user inspects the binary, this is a discrepancy.
- **Recommendation:** Set `requiresOnDeviceRecognition = true`. Accept that it may fail on some older devices/locales with `recognitionUnavailable`; that error path already exists. If cloud fallback is genuinely desired, it must be an explicit product decision with appropriate privacy disclosures — not a default.

---

### HIGH (Should Fix Before Proceeding)

#### 3. `AVAudioApplication.requestRecordPermission` requires iOS 17+

- **Location:** Step 2, `requestPermissions()`
- **Problem:** `AVAudioApplication` was introduced in iOS 17. The existing codebase pattern and project configuration have not been confirmed to target iOS 17+. If the deployment target is iOS 16.x, this will fail to compile.
- **Impact:** Build failure on any iOS 16 target.
- **Recommendation:** Check the project's minimum deployment target in `WellPlate.xcodeproj`. If it is below iOS 17, use `AVAudioSession.requestRecordPermission` (available since iOS 7) instead. Keep the `AVAudioApplication` variant behind an `#available(iOS 17, *)` check if you want to use it for newer devices.

---

#### 4. `.symbolEffect(.variableColor.iterative, isActive:)` requires iOS 17+

- **Location:** Step 4, `speakMealButton`
- **Problem:** The `symbolEffect` modifier with `isActive:` parameter was introduced in iOS 17. Same deployment target concern as issue #3.
- **Impact:** Compile error or runtime crash on iOS 16.
- **Recommendation:** Wrap in `#available(iOS 17, *)` or replace with a simple `opacity` / `scaleEffect` animation that works on iOS 16.

---

#### 5. `hasPermission` can go stale after in-session permission revocation

- **Location:** Step 3, `startMealTranscription()` — the `if !speechService.hasPermission` guard
- **Problem:** `hasPermission` is set to `true` after the first successful `requestPermissions()` call and never re-checked from the system. The user can revoke microphone or speech recognition in Settings while the app is backgrounded (without killing it). On the next `startMealTranscription()` call, the guard passes (`hasPermission == true`), `startTranscription` is called, and the audio engine setup either silently produces empty results or crashes with an engine error — not the friendly `permissionDenied` path with the Settings link.
- **Impact:** After permission revocation, the user sees either a generic error message or silence, not the actionable "Open Settings" alert.
- **Recommendation:** Query the live system status before starting. Replace the cached flag with a live check:
  ```swift
  var hasPermission: Bool {
      AVAudioSession.sharedInstance().recordPermission == .granted &&
      SFSpeechRecognizer.authorizationStatus() == .authorized
  }
  ```
  Remove `private(set) var hasPermission: Bool = false` from the service entirely, or keep it as a lazy baseline and always re-check before starting.

---

#### 6. Step 6 `onChange` block contains broken no-op that won't compile

- **Location:** Step 6, the updated `onChange(of: viewModel.shouldDismiss)` snippet
- **Problem:** The plan shows:
  ```swift
  .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
      if shouldDismiss {
          viewModel.speechService  // (no direct access needed — the VM stops on deinit)
  ```
  Two problems:
  1. `viewModel.speechService` is `private` in `MealLogViewModel` — accessing it from the View is a compile error.
  2. Even if accessible, it's a bare property-access expression with no effect — it is dead code.
  The intent (relying on deinit) is valid, but the code as written is harmful noise that will break the build.
- **Recommendation:** Remove the `viewModel.speechService` line entirely. The comment about deinit cleanup is sufficient justification; no code change to the existing `onChange` block is needed. The only real addition needed here is the back-button `stopMealTranscription()` guard shown below the snippet — pull that out as the actual step.

---

### MEDIUM (Fix During Implementation)

#### 7. `.record` audio session category will mute background music

- **Location:** Step 2, `startTranscription` — `session.setCategory(.record, ...)`
- **Problem:** `AVAudioSession.Category.record` deactivates all other audio output. If the user is listening to music or a podcast while logging a meal, starting transcription will abruptly cut their audio.
- **Recommendation:** Use `.playAndRecord` with the `.duckOthers` option instead. This ducks background audio to a lower volume during recording (standard iOS behavior for voice memos, Siri, etc.) rather than killing it.

---

#### 8. `stopTranscription()` comment implies `onFinal` will always fire — this is not guaranteed

- **Location:** Step 3, `stopMealTranscription()` — comment: *"isTranscribing and liveTranscript cleared by onFinal / onError callbacks"*
- **Problem:** `recognitionRequest?.endAudio()` signals the framework that no more audio is coming and it should finalize. However, if the session was running but the user spoke nothing at all, the framework may call `onError(.noSpeechDetected)` rather than `onFinal`. The `onError` handler correctly sets `isTranscribing = false` (it does this before the early-return on `.noSpeechDetected`), so this specific path is handled.
  The remaining gap: if the recognition framework delivers neither a final result nor an error (possible if the request was already ended externally, or on some OS versions), `isTranscribing` will remain `true` indefinitely.
- **Recommendation:** Add a safety reset in `stopMealTranscription()`:
  ```swift
  func stopMealTranscription() {
      speechService.stopTranscription()
      // Belt-and-suspenders: callbacks should clear these, but ensure we never stay stuck.
      isTranscribing = false
      liveTranscript = ""
  }
  ```
  The ViewModel can still apply the transcript if `onFinal` fires after this reset (since `applyTranscriptToFoodDescription` is idempotent and the callbacks only append/replace text, not set recording state).

---

#### 9. `isLoading` and `isTranscribing` can be simultaneously `true`

- **Location:** Step 4, `speakMealButton` — button has no disabled state for `isLoading`
- **Problem:** The save button is disabled during `isLoading`, but the mic button is not. A user could theoretically tap "Save & Reflect" and then immediately tap "Speak meal" before the save completes. The ViewModel's `startMealTranscription()` would start a session while `isLoading = true`, and the resulting transcript update to `foodDescription` would silently update a field that is mid-save.
- **Recommendation:** Add `.disabled(viewModel.isLoading)` to `speakMealButton`, consistent with how the food `TextField` is `.disabled(viewModel.isLoading)`.

---

#### 10. `lazy var speechService` exact syntax will require `any` keyword in Swift 5.7+

- **Location:** Step 3, `private lazy var speechService: SpeechTranscriptionServiceProtocol`
- **Problem:** The project uses Swift 5 mode (from memory context). In Swift 5.7+, using an existential type as a variable type requires the `any` keyword: `any SpeechTranscriptionServiceProtocol`. The plan's syntax will produce a warning (or error in strict mode).
- **Recommendation:** Write `private lazy var speechService: any SpeechTranscriptionServiceProtocol = AppleSpeechTranscriptionService()`.

---

### LOW (Consider for Future)

#### 11. Silence-based auto-stop is handled by the framework, not the app — this should be stated

- **Location:** Requirements section — *"Recording stops on tap or after ~20s silence timeout"*
- **Problem:** The plan implements a 25-second **hard** timeout via `Task.sleep`, but the brainstorm requirement is silence detection. Apple's `SFSpeechRecognizer` auto-finalizes after a period of silence natively (typically 2-3 seconds of silence in practice). This natural finalization fires `isFinal = true` → `onFinal` → session ends. The 25s `Task` is a backstop, not the primary silence mechanism.
- **Recommendation:** Clarify in the plan that silence detection is delegated to the framework (no custom VAD needed) and the timeout is a hard cap. This also explains why the 25s cap is correct even if the requirement says "~20s" — the framework will usually end the session far sooner.

#### 12. No test for `applyTranscriptToFoodDescription` with whitespace-heavy inputs

- **Location:** Testing strategy
- **Problem:** The append logic trims the existing `foodDescription` before appending. This means `"  rice  "` + `"and dal"` → `"rice and dal"` (good). But `foodDescription` is then set to the trimmed result, silently normalizing whatever the user typed. The test list doesn't cover this implicit trim side-effect.
- **Recommendation:** Add `test_applyTranscript_trimsExistingWhitespace` to verify the trim-and-assign behavior is intentional.

#### 13. Plan doesn't mention `import Speech` requirement for the framework

- **Location:** Step 7 / Architecture changes
- **Problem:** The `Speech` framework is not automatically linked. While the `PBXFileSystemSynchronizedRootGroup` handles new Swift files, `Speech.framework` still needs to be explicitly linked in the target's "Frameworks, Libraries, and Embedded Content" — unless it's already included.
- **Recommendation:** Add a note to check (and if needed, add) `Speech.framework` to the linked libraries before building. This is a 30-second Xcode UI step but easy to miss.

---

## Missing Elements

- [ ] No mention of what happens to `isTranscribing` state if the app is backgrounded mid-session (system will terminate the audio session; the app should handle `AVAudioSession.interruptionNotification` to clean up state)
- [ ] No mention of `AVAudioSession` interruption handling (phone call mid-transcription, Siri activation, etc.)
- [ ] `MockSpeechTranscriptionService` implementation is described but not specified — the test file creation should include the mock definition
- [ ] Step 7 instructs manual pbxproj editing; Xcode's target Info tab is safer and less error-prone for adding privacy usage description strings

## Unverified Assumptions

- [ ] Project minimum deployment target is iOS 17+ — Risk: **High** (affects `AVAudioApplication` and `symbolEffect`)
- [ ] `Speech.framework` is already linked in the main target — Risk: **Medium** (build failure if not)
- [ ] `SFSpeechRecognizer` result handler is always called on main thread — Risk: **Low** (Apple docs imply this, but it's not formally guaranteed in all iOS versions)

## Security Considerations

- [ ] With `requiresOnDeviceRecognition = false` (as currently written), meal content is sent to Apple's servers — must be disclosed in the privacy policy if shipped this way
- [ ] `UIApplication.openSettingsURLString` deep-link is safe and appropriate; no issues here

## Performance Considerations

- [ ] `AVAudioEngine` with a 1024-buffer tap will fire the handler frequently; `request.append(buffer)` is thread-safe but high-frequency — acceptable for this use case
- [ ] `liveTranscript` publishes every partial result to the View — with rapid speech, this triggers frequent SwiftUI re-renders of the full `foodInputGroup`. Consider debouncing updates at >10 per second, though in practice this is unlikely to be a real issue for meal logging

## Questions for Clarification

1. What is the minimum iOS deployment target? This determines which `AVAudioSession` permission API to use and whether `symbolEffect` is available.
2. Is cloud transcription acceptable as a fallback (with `requiresOnDeviceRecognition = false`), or is on-device only required? The brainstorm says on-device; the plan code says otherwise.
3. Should the microphone be stopped when the app is backgrounded (e.g., user switches apps mid-log)? The current plan has no `scenePhase` or notification observer for this.

## Recommendations

1. **Fix the double-teardown** (Issue #1) before any other work — it's a latent crash.
2. **Decide on `requiresOnDeviceRecognition`** (Issue #2) as a product decision, not a code comment.
3. **Check the deployment target** (Issues #3, #4) immediately — if it's iOS 16, both the permission API and the animation modifier need alternatives.
4. **Replace the cached `hasPermission` flag** (Issue #5) with a live system query.
5. **Delete the broken `viewModel.speechService` no-op** (Issue #6) from Step 6.
6. **Change audio session category to `.playAndRecord`** (Issue #7) to avoid muting background audio.
7. **Add `.disabled(viewModel.isLoading)`** (Issue #9) to the mic button.

## Sign-off Checklist

- [ ] All CRITICAL issues resolved (Issues #1, #2)
- [ ] All HIGH issues resolved or accepted with rationale (Issues #3–#6)
- [ ] Deployment target confirmed and APIs adjusted if < iOS 17
- [ ] `requiresOnDeviceRecognition` decision documented as an explicit product choice
- [ ] Audio session category changed to `.playAndRecord`
- [ ] `Speech.framework` linkage verified in Xcode target settings
- [ ] Security review: privacy policy updated if cloud transcription is permitted
