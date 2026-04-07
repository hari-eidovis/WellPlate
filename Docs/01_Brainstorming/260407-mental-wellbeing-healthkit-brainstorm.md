# Brainstorm: HealthKit Mental Wellbeing Integration (F2)

**Date**: 2026-04-07
**Status**: Ready for Planning
**Roadmap ref**: `Docs/02_Planning/260406-10-feature-roadmap.md` — F2

---

## Problem Statement

WellPlate already captures daily mood via a 5-emoji picker (`MoodOption`, stored in `WellnessDayLog.moodRaw`). That data is siloed — it lives only in our SwiftData store and doesn't participate in the Apple Health ecosystem. Meanwhile, iOS 18 introduced `HKStateOfMind`, giving HealthKit a first-class mood/emotion type. Users who track mood in Apple Health or with other apps get no benefit from WellPlate's check-in.

The goal is to close this gap: **make WellPlate a HealthKit citizen for mental wellbeing data** — writing our mood check-in into the Health app, optionally reading back State of Mind data the user may have logged elsewhere, and surfacing PHQ-9/GAD-7 assessment scores from clinical records if available.

---

## Core Requirements

- Write MoodOption → `HKStateOfMind` sample when user logs mood (iOS 18+)
- Read `HKStateOfMind` history for trend display (complement existing data)
- Optionally surface PHQ-9/GAD-7 scores read from Health (display-only, not diagnostic)
- Respect HealthKit authorization — request share + read for state of mind; read-only for assessments
- Degrade gracefully on devices / iOS versions that don't support these types
- Maintain trust brand: "informational, not diagnostic" — Apple's own language for mental health in Health app

---

## Constraints

- App targets iOS 26+ — `HKStateOfMind` (iOS 18+) is available on all targets
- `HealthKitService` currently calls `requestAuthorization(toShare: [], read: readTypes)` — adding `HKStateOfMind` share requires changing the share set
- HealthKitServiceProtocol is a protocol — changes need to propagate to the mock too
- PHQ-9/GAD-7 via HealthKit come through FHIR clinical records (`HKClinicalRecord`) — a different authorization flow (`requestAuthorization` with `.clinicalRecord` type) — this is separate from the main authorization
- No custom backend; all data stays on-device / in Apple Health

---

## Approach 1: Write-Only Shadow (Minimal)

**Summary**: Silently write a `HKStateOfMind` sample to Apple Health every time the user confirms a mood. No new UI. No reads. One helper method added to `HealthKitService`.

**How it works**:
1. Add `HKStateOfMind` (write/share) to `HealthKitService.requestAuthorization`
2. After user taps a mood in `MoodCheckInCard` → `onConfirm` fires → call `healthKit.writeMood(moodOption)`
3. Map `MoodOption` → `HKStateOfMind`:
   - awful → valence: -1.0, kind: `.dailyMood`
   - bad → valence: -0.5
   - okay → valence: 0.0
   - good → valence: 0.5
   - great → valence: 1.0
4. The Health app immediately shows the mood entry under "State of Mind"
5. No new views, no new models

**Pros**:
- Extremely low effort (~30 lines of code)
- Zero UI risk — existing UX unchanged
- User data appears in Apple Health without them doing anything
- No read authorization needed (one fewer permission dialog)
- Composes perfectly with Apple's own mental health logging

**Cons**:
- Write-only: can't prefill from Health app or surface outside data
- Authorization dialog will mention "mental health" data — some users may be surprised
- If HealthKit write fails (user denied), mood still saves to SwiftData — silent
- No visible feedback to user that sync happened

**Complexity**: Very Low | **Risk**: Low
**New files**: 0 (extend `HealthKitService` + `HealthKitServiceProtocol` only)
**Effort**: Half a day

---

## Approach 2: Bidirectional Sync with Prefill

**Summary**: Write mood to `HKStateOfMind` on confirmation, and read back the last State of Mind sample from Health to prefill the picker if today's mood hasn't been logged yet.

**How it works**:
1. Everything from Approach 1 +
2. Add `HKStateOfMind` to readTypes
3. On `HomeViewModel.loadTodayLog()`: if `moodRaw == nil`, fetch last `HKStateOfMind` sample from today → reverse-map valence to nearest `MoodOption` → set as suggestion
4. Show a subtle "Synced from Health" badge on `MoodCheckInCard` when prefilled
5. User can override the suggestion by tapping a different emoji

**Pros**:
- Users who log mood in Apple Mindfulness or other apps see it prefilled here
- Reinforces "system integration" story
- Minimal new UI (just a badge)
- WellPlate and Apple Health stay in sync regardless of which app the user logs from

**Cons**:
- Reverse-mapping valence → `MoodOption` is lossy (valence is continuous, ours is 5-step)
- If user logged 3 moods today in Health app, which one do we prefill? (need recency heuristic)
- Two-way sync can cause subtle consistency bugs (user logs in Health, we overwrite on next save)
- Requires both read + write auth for State of Mind

**Complexity**: Low–Medium | **Risk**: Low–Medium
**New files**: 0 (service extensions + small UI tweak to MoodCheckInCard)
**Effort**: 1–2 days

---

## Approach 3: Mental Wellbeing Card (Full Feature)

**Summary**: Add a dedicated "Mental Wellbeing" section or card to the app — showing the user's 30-day mood trend from HealthKit (combined WellPlate + other sources), and optionally showing PHQ-9/GAD-7 scores if clinical records are available.

**How it works**:
1. Everything from Approach 2 +
2. New `MentalWellbeingService` that handles:
   - Writing HKStateOfMind
   - Fetching 30-day HKStateOfMind history (all sources: WellPlate + Health app + others)
   - Optionally requesting FHIR clinical record access for PHQ-9/GAD-7
3. New `MentalWellbeingCardView` on StressView or a sub-tab:
   - 30-day mood trend chart (small bar chart, same style as other vitals)
   - "From Apple Health" badge when data spans multiple sources
   - PHQ-9 score (if available) shown as "Assessment (from Health)" — non-diagnostic framing
4. PHQ-9/GAD-7 gated behind a separate "Enable Clinical Data" flow — not prompted automatically

**Pros**:
- Most complete "HealthKit citizen" story
- 30-day chart turns ephemeral daily mood into a longitudinal pattern
- PHQ-9/GAD-7 display adds professional credibility (clinician export story)
- Creates natural home for Apple's mental health investment in WellPlate

**Cons**:
- PHQ-9/GAD-7 via FHIR requires a *different* authorization path (`healthRecords` entitlement) — this is a new App Store entitlement
- Clinical records only available if user has a connected healthcare provider in Health app — most users won't have this
- 30-day chart needs careful design to avoid looking like a diagnostic tool
- Medical framing risk: need "informational only" disclaimers, similar to Apple's own PHQ-9 presentation
- Medium effort, especially the clinical records path

**Complexity**: Medium | **Risk**: Medium (clinical records entitlement, medical framing)
**New files**: ~3–4 (`MentalWellbeingService`, `MentalWellbeingCardView`, optional assessment model)
**Effort**: 1–2 weeks

---

## Approach 4: Mood as Stress Factor

**Summary**: Write mood → HKStateOfMind, read back 30-day history, and integrate mood as a formal stress-factor input — mood impacts the composite stress score, and is shown alongside HRV, sleep, screen time in the factor breakdown.

**How it works**:
1. Everything from Approach 3 +
2. Mood feeds into `StressViewModel` calculation:
   - Negative mood boosts stress score contribution
   - Positive mood is protective (lowers stress component)
3. Factor card added to StressView: "Mood" card, same style as Sleep/Diet/Screen Time
4. Mood trend shown in factor detail sheet

**Pros**:
- Most deeply integrated — mood finally matters to the stress score
- Makes daily mood check-in feel consequential (users who ignored it will engage)
- Scientifically defensible (affect is a known stress modulator)

**Cons**:
- Changing the stress score formula is a breaking change — users who ignored mood will see score shifts
- Requires careful weighting to avoid over-claiming
- The stress model is already multi-factor — adding mood needs regression testing across data states
- Large scope expansion beyond F2's stated intent

**Complexity**: High | **Risk**: Medium–High
**New files**: ~5+ 
**Effort**: 2–3 weeks

---

## Edge Cases to Consider

- [ ] `HKStateOfMind` write fails (user denied write auth, or iOS <18 somehow) — mood should still save to SwiftData
- [ ] User revokes HealthKit write permission mid-session — subsequent mood logs should fail silently
- [ ] User logs mood multiple times in one day — each confirmation writes a new HKStateOfMind sample; reading back should use most recent
- [ ] Valence reverse-mapping: if Health app stores valence at 0.3 (between "okay" and "good"), snap to nearest MoodOption
- [ ] What if the user has already logged mood today in WellPlate AND has HKStateOfMind from another app — don't overwrite the SwiftData value on prefill
- [ ] PHQ-9/GAD-7 scores: must never infer diagnosis, only show raw score + Apple's own "informational" framing
- [ ] `healthRecords` entitlement requires explicit App Store Review justification — only add if clinical records approach is chosen
- [ ] Authorization dialog timing: adding mood to HealthKit authorization should ideally happen at onboarding, not on first mood tap (avoid mid-flow permission dialogs)

---

## Open Questions

- [ ] Should we request HealthKit write authorization for HKStateOfMind at onboarding (alongside existing request) or lazily on first mood log?
- [ ] Is the `healthRecords` entitlement worth pursuing for PHQ-9/GAD-7 given how few users have FHIR-connected providers?
- [ ] Should we show a "synced to Apple Health" confirmation toast on first successful write?
- [ ] Does Apple's Human Interface Guidelines require a specific disclosure when writing mental health data (similar to the menstrual/reproductive health disclosure requirement)?
- [ ] How do we handle mock mode? Write HKStateOfMind in mock mode would fail — should `MockAPIClient` also mock health writes?

---

## Recommendation

**Ship Approach 2 (Bidirectional Sync)** as the F2 implementation.

Rationale:
- Approach 1 (write-only) is so thin it feels incomplete — users get no feedback that sync happened and can't benefit from other apps' data
- Approach 2 adds meaningful value (prefill from Health, cross-app sync) at very low cost
- Approach 3 is worth deferring: PHQ-9/GAD-7 requires a new App Store entitlement and the entitlement is unlikely to be approved for a wellness app (vs. a clinical tool). The 30-day mood chart can be added later as a natural extension.
- Approach 4 (stress factor) is the right long-term home for mood, but the scope is too large for F2 and the formula change needs careful product consideration first

**MVP Scope for F2**:
1. Add `HKStateOfMind` to HealthKit share + read types
2. Write mood → HKStateOfMind on confirmation (in HomeViewModel, where MoodCheckInCard's `onConfirm` already fires)
3. On page load: if today's mood is unlogged, fetch today's latest HKStateOfMind → prefill mood picker
4. Subtle "From Health" badge when prefilled
5. Graceful degradation when HealthKit is unavailable or unauthorized

**Deferred to later**:
- 30-day mood chart from HK (good F3/Circadian companion)
- PHQ-9/GAD-7 display (needs entitlement + significant design work)
- Mood as stress factor (F4 or later)

---

## Research References

- `Docs/02_Planning/260406-10-feature-roadmap.md` — F2 definition
- `Docs/01_Brainstorming/260402-feature-prioritization-from-deep-research-brainstorm.md` — Feature 2C context
- Existing: `WellPlate/Shared/Components/MoodCheckInCard.swift` — 5-emoji picker, `onConfirm` callback
- Existing: `WellPlate/Models/WellnessDayLog.swift` — `moodRaw: Int?` storage
- Existing: `WellPlate/Core/Services/HealthKitService.swift` — authorization flow, `toShare: []` currently
- Apple: `HKStateOfMind` introduced iOS 18 — `valence` (Double, -1 to 1), `arousal`, `kind` (momentaryEmotion / dailyMood), `labels`
- Apple HIG: Mental health data requires "informational, not diagnostic" framing; HealthKit share auth prompts show data category name to user
