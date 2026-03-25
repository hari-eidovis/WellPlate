# MealLogView Audio-to-Text Transcription Brainstorm
**Date**: 2026-03-14  
**Session Type**: Feature Brainstorm / Implementation Framing

---

## Goal

Add an audio-to-text transcription flow inside `MealLogView` so a user can speak their meal instead of typing it, then review and save the parsed text through the existing meal logging pipeline.

This should speed up meal capture without introducing a second, disconnected logging flow.

---

## Current Repo Context

### Existing Meal Logging Touchpoints

- `MealLogView.swift`
  - has the main `foodDescription` text field
  - has a quick action row with a `mic.fill` button labeled `Voice note`, currently `TODO`
  - has a separate `voiceNoteSection` with "Add a voice note" and a `Coming soon` button
- `MealLogViewModel.swift`
  - owns `foodDescription`, loading state, validation, save flow, and disambiguation
  - already performs async work and is the correct place for transcription state
- `HomeViewModel.swift`
  - already handles nutrition analysis and atomic save via `MealContext`
  - does not need major structural changes for transcription if the output is just text

### Important Constraint

There are currently two microphone concepts in the UI:

1. Quick action mic in the row near photo / barcode
2. Voice note card lower in the form

If audio-to-text is added without clarifying this, users will not know whether the mic fills the meal field, records a reflection, or stores raw audio.

---

## Product Framing

### Recommended v1 Scope

Use speech-to-text to populate the meal description field only.

Example:

- User taps mic
- User says: "Two slices of whole wheat toast with peanut butter and a banana"
- Transcript appears in `foodDescription`
- User edits text if needed
- Existing `saveMeal()` flow runs unchanged

This is the lowest-risk version because it reuses the current save path and avoids new persistence requirements.

### Explicit Non-Goals for v1

- Do not save raw audio files
- Do not attach permanent voice notes to `FoodLogEntry`
- Do not transcribe directly into the reflection field by default
- Do not auto-submit after speech ends

Those can be phase 2+ features, but combining them into the first pass will blur the UX and expand the permission/model surface unnecessarily.

---

## UX Direction

### Recommended UX Decision

Repurpose the quick action mic as `Speak meal`.

Keep the lower `voiceNoteSection` focused on reflection text for now, or relabel it later if the product really wants recorded reflections.

### Why

- The quick action row is already action-oriented
- The speech result belongs in the primary meal input
- The lower card visually reads like reflection / journaling, not food entry

### Suggested v1 Interaction

Idle state:
- Quick action button label becomes `Speak meal`

Recording state:
- Quick action button changes to `Listening...`
- Food field container gets a subtle active border or tint
- Optional helper copy under the food field: `Try: oatmeal with berries and coffee`

After speech ends:
- Transcript replaces or appends to `foodDescription`
- User can edit manually before save

Failure states:
- Permission denied: show alert with a clear explanation
- No speech detected: toast/inline hint and keep prior text untouched
- Recognition unavailable: fall back to manual typing

### Replace vs Append

Recommended default:
- If `foodDescription` is empty, replace it with transcript
- If it already has text, append transcript with a space

This avoids destructive behavior when users speak a correction after typing something manually.

---

## Technical Approach

### Recommended v1 Stack

Use Apple local frameworks:

- `Speech` for recognition
- `AVFoundation` for microphone capture / audio session
- `AVAudioEngine` for live transcription

### Why This Fits the Current App

- No backend dependency required
- No need to upload audio
- Works as a UI enhancement on top of the existing text-based save flow
- Keeps privacy risk lower than cloud transcription

### Recommended Service Shape

Add a speech service abstraction under `WellPlate/Core/Services`.

Suggested files:

- `SpeechTranscriptionServiceProtocol.swift`
- `AppleSpeechTranscriptionService.swift`

Suggested responsibilities:

- request microphone + speech recognition permissions
- start live transcription
- stream partial transcript updates
- stop / cancel cleanly
- surface high-level app errors instead of framework-specific noise

### ViewModel State Additions

`MealLogViewModel` is the right owner for speech state.

Suggested additions:

- `@Published var isTranscribing = false`
- `@Published var liveTranscript = ""`
- `@Published var transcriptionError: String?`
- `@Published var showTranscriptionPermissionAlert = false`

Suggested methods:

- `startMealTranscription()`
- `stopMealTranscription(commitResult: Bool = true)`
- `applyTranscriptToFoodDescription(_:)`

### UI Integration Point

Primary integration should be the quick action mic in `MealLogView.swift`.

Minimal UI changes:

- swap the quick action mic label from `Voice note` to `Speak meal`
- show active visual state while recording
- optionally show a small live transcript preview under the food input

The lower `voiceNoteSection` should not start speech-to-text in v1 unless the product explicitly wants reflection dictation too.

---

## Suggested State Flow

1. User taps `Speak meal`
2. App requests permissions if needed
3. `MealLogViewModel` starts transcription session
4. Partial transcript updates appear in UI
5. User taps stop, or session auto-stops after silence / timeout
6. Final transcript is merged into `foodDescription`
7. User edits and taps `Save & Reflect`
8. Existing `saveMeal(selectedDate:)` continues as-is

### Important Separation

Transcription should produce text only.

Nutrition analysis should still happen only when the user explicitly saves. That keeps the current async/disambiguation flow predictable and avoids repeated API calls while the user is still speaking.

---

## Permissions and Project Changes

The main app target already defines camera and photo usage descriptions in `WellPlate.xcodeproj/project.pbxproj`, but it does not currently define the keys needed for speech input.

### Required Additions

- `INFOPLIST_KEY_NSMicrophoneUsageDescription`
- `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`

Suggested copy:

- Microphone: `WellPlate uses the microphone so you can speak meal entries instead of typing them.`
- Speech recognition: `WellPlate converts your speech into text to help you log meals faster.`

### Risk

If either key is missing, the feature will fail at runtime.

---

## Architecture Notes

### Keep Transcription Out of `HomeViewModel`

`HomeViewModel` already owns nutrition lookup and persistence. It should receive text, not audio-session concerns.

That separation keeps responsibilities clean:

- `MealLogViewModel`: input capture and form state
- `HomeViewModel`: nutrition analysis and save

### Do Not Persist Transcript Metadata in v1

No model changes are required if transcription only fills `foodDescription`.

That is a major advantage:

- no SwiftData migration
- no audio file cleanup
- no extra privacy storage questions

### If Phase 2 Needs Reflection Dictation

Then add a targeted input destination concept rather than reusing one generic mic blindly.

Example:

- `enum TranscriptionTarget { case foodDescription, reflection }`

Without that, the UI will become ambiguous fast.

---

## UI Copy Recommendations

Current labels are not ideal if the feature is transcription rather than audio attachment.

### Recommended copy changes

- Quick action button: `Speak meal`
- Recording state: `Listening... Tap to stop`
- Helper text: `Say the food and amount if you know it`

### Copy to avoid

- `Voice note`
- `Only you can hear this`
- `Coming soon`

Those imply raw audio storage, not text transcription.

---

## Edge Cases

### Partial transcript quality

Speech recognition often produces unstable partial text. The UI should distinguish live transcript from committed text.

Recommended behavior:

- show live text in a temporary preview
- commit to `foodDescription` only on stop / final result

### Locale

If the app is English-only today, start with the current device locale or `en-US`.

Open question:
- Should nutrition parsing expect Indian food names, regional accents, or mixed-language utterances?

That affects recognition quality more than the save flow.

### Background noise

Meal logging may happen in restaurants or kitchens. The user must be able to edit the transcript before save.

### Long utterances

Set a practical cap for v1:

- auto-stop after silence
- or hard-stop around 20-30 seconds

The current meal logging use case does not need long recordings.

---

## Suggested Files to Touch in Implementation

### New

- `WellPlate/Core/Services/SpeechTranscriptionServiceProtocol.swift`
- `WellPlate/Core/Services/AppleSpeechTranscriptionService.swift`

### Existing

- `WellPlate/Features + UI/Home/ViewModels/MealLogViewModel.swift`
- `WellPlate/Features + UI/Home/Views/MealLogView.swift`
- `WellPlate.xcodeproj/project.pbxproj`

### Optional

- `WellPlateTests/...` for speech-state unit tests around the view model

---

## Testing Strategy

### Unit Tests

Add view model tests for:

- start transcription toggles `isTranscribing`
- successful final transcript updates `foodDescription`
- append vs replace behavior
- permission denial surfaces a user-facing error
- stopping transcription clears transient state

### Manual QA

- first launch permission flow
- deny microphone, then retry
- deny speech recognition, then retry
- speak a simple meal
- speak a meal with quantity
- interrupt recording manually
- start recording with existing typed text
- save after transcript and verify existing disambiguation still works

---

## Phased Rollout

### Phase 1

Live speech-to-text for `foodDescription` only.

### Phase 2

Optional dictation target for reflection text.

### Phase 3

Optional parsing improvements:

- detect quantity phrases from transcript
- prefill `quantity` and `quantityUnit`
- normalize common meal shorthand before save

### Phase 4

If the product still wants true voice notes, build that as a separate feature:

- raw audio recording
- file storage
- playback UI
- deletion cleanup
- explicit privacy messaging

This should not be bundled into the first transcription pass.

---

## Recommendation

Implement audio-to-text in `MealLogView` as a focused transcription feature tied to the main food entry field, not as a generic voice note feature.

The cleanest path is:

1. Add a speech transcription service
2. Let `MealLogViewModel` own transcription state
3. Bind the quick action mic to `Speak meal`
4. Keep `HomeViewModel` unchanged except for consuming the resulting text
5. Avoid raw audio persistence in v1

This gives the app a faster meal-entry workflow with minimal model churn and much lower implementation risk than full voice-note support.

---

## Open Questions

1. Should the transcript only fill `foodDescription`, or should users also be able to dictate `reflection`?
2. Should transcription auto-stop after silence, or require an explicit tap to stop?
3. Should we support one-tap overwrite of the meal field, or always append when text already exists?
4. Is English-only acceptable for v1, or do we need multilingual recognition from day one?
