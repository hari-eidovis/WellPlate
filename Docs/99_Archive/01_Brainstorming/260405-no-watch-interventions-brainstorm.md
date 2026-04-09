# Brainstorm: No-Watch Intervention Features — Phased Implementation Plan

**Date**: 2026-04-05
**Status**: Ready for Planning
**Scope**: 5 features from the Creative Stress Features doc that are implementable on iPhone without Apple Watch

---

## Problem Statement

The 260403 brainstorm evaluated all 20 creative stress features and deferred most intervention-style features (Taptic Vagus Resonator, Micro-PMR, Dive Reflex) as Watch-dependent. However, 5 features are either fully or partially implementable on iPhone alone. The question is: **how do we phase and architect these 5 features coherently**, ensuring they integrate cleanly into the existing Stress tab, share infrastructure efficiently, and are designed for easy Watch biometric bolt-on when the time comes?

The 5 features:

| # | Feature | iPhone Status | Watch Dependency |
|---|---------|---------------|-----------------|
| 17 | Sensory Anchoring Widget | Fully implementable | None |
| 14 | Somatic Sigh Validator | Intervention only (no biometric proof) | HR/HRV validation |
| 15 | Ambient Vocal Entrainment | Intervention only (no biometric proof) | HR/HRV validation |
| 16 | Micro-PMR Sequence | Adaptable to iPhone haptics | Richer WKHapticType patterns |
| 2  | Meeting Strain Forecaster | Calendar analysis only (no HRV overlay) | Physiological cost scoring |

---

## What's Already Built (Relevant)

- `StressSheet` enum + single `.sheet(item:)` pattern in StressView
- `StressViewModel` with HealthKit fetching + 30-day histories
- Card-based UI: `RoundedRectangle(cornerRadius: 20).appShadow(radius: 15, y: 5)`
- Stress Lab interventions pattern (user runs a timed experiment)
- Mood check-in flow (brief, contextual, non-intrusive)
- Widget target already exists: `WellPlateWidget.appex`

---

## Core Constraints

- No Apple Watch available — no WKInterfaceDevice, no WatchKit, no real-time HR streaming
- Solo dev — shared infrastructure is critical to avoid code duplication
- Existing navigation: 4 tabs + StressSheet enum pattern — must not add random `.sheet()` calls
- iOS 26+ target — interactive widgets, Live Activities, Foundation Models all available
- PBXFileSystemSynchronizedRootGroup — new files auto-included, no pbxproj edits

---

## Approach 1: "Rescue Toolkit" Section Inside Stress Tab

**Summary**: Add a horizontally-scrollable "Interventions" card row within the existing StressView, housing all intervention features. Meeting Forecaster gets its own card below the existing factor cards. No new tab.

**Pros**:
- Zero navigation surgery — uses existing StressSheet enum pattern
- Contextually appropriate (interventions live where stress is shown)
- Consistent with how Stress Lab (flask button) was integrated
- Progressive disclosure: card row only shows when stress score is elevated

**Cons**:
- StressView already has a lot of content (score, vitals, 4 factor cards, stress lab)
- Horizontal scroll row adds visual weight
- Meeting Forecaster's Gantt/timeline UI feels different in tone from the intervention cards

**Complexity**: Low | **Risk**: Low

---

## Approach 2: New "Toolkit" 5th Tab

**Summary**: Add a 5th tab to `MainTabView` — "Toolkit" or "Reset" — dedicated to all intervention features plus the Meeting Forecaster.

**Pros**:
- Clean separation of "measuring stress" (Stress tab) from "acting on stress" (Toolkit tab)
- Room for the Meeting Forecaster's richer UI without crowding StressView
- Scalable — can add future interventions (Dive Reflex Reset, Taptic Vagus Resonator) here as Watch features arrive

**Cons**:
- iOS 18+ Tab API is used; CLAUDE.md states 4 tabs: Home, Burn, Stress, Profile. Adding a 5th changes the core nav identity
- Interventions without Watch biometric proof might feel "thin" as a dedicated tab
- May confuse users about which tab to use first

**Complexity**: Low-Medium | **Risk**: Medium (nav identity change)

---

## Approach 3: "Interventions" Sheet from Stress Tab Header

**Summary**: Add a toolbar button (e.g., "bolt" or "bandaid" SF Symbol) to StressView that opens a dedicated InterventionsView sheet — a scrollable menu of all intervention options. Meeting Forecaster gets its own `.stressLab`-style case in `StressSheet`.

**Pros**:
- Follows exact precedent of Stress Lab's "Lab" toolbar button
- Interventions are accessible without cluttering the main scroll
- InterventionsView can use a list/grid layout with rich cards
- `StressSheet` enum scales cleanly: add `.interventions`, `.meetingForecaster` cases

**Cons**:
- Two toolbar buttons (Lab flask + new Interventions icon) may feel cluttered
- Sheet-within-sheet risk if an intervention needs its own modal (timer screen)

**Complexity**: Low | **Risk**: Low

---

## Approach 4: Contextual Recommendation Cards (Smart Surfacing)

**Summary**: No dedicated home for interventions. Instead, when stress score is elevated, WellPlate surfaces a "Try This" recommendation card inline in the stress feed, linking to the relevant intervention. The widget lives on the home screen independently.

**Pros**:
- Most elegant UX — interventions appear when needed, not as a menu to browse
- No navigation overhead
- Pairs naturally with Ghost Stress Detector (detect spike → recommend reset)

**Cons**:
- Discoverability is low — users may never find the interventions unless triggered
- Harder to "explore" the toolkit on calm days
- Contextual trigger logic adds complexity before core features are built

**Complexity**: Medium | **Risk**: Medium

---

## Recommendation: Approach 3 (Interventions Sheet) + Approach 4 (Contextual Cards)

Combine both: a toolbar "Interventions" button for exploration, **plus** a contextual recommendation card on the Stress tab when score exceeds threshold. This is the exact Stress Lab precedent (discoverable via toolbar, but also surfaced when relevant).

---

## Shared Infrastructure Analysis

All 5 features share or can share common building blocks. Building these as reusable services prevents duplication:

### A. `InterventionTimerEngine`
- Protocol-based countdown timer: `start(duration:)`, `pause()`, `cancel()`
- Used by: Somatic Sigh (40s protocol), PMR Sequence (60s), Vocal Entrainment (2min)
- `@Published` progress (0.0–1.0), elapsed, phase label
- Phase-aware: each intervention has named phases (e.g., "Inhale × 2", "Exhale", "Hold")
- Watch bolt-on: same engine drives WatchKit session timer

### B. `HapticEngine` (wrapper)
- Thin wrapper over `UIImpactFeedbackGenerator` + `UINotificationFeedbackGenerator`
- Pattern enum: `.rise(duration:)`, `.snap`, `.pulse(count:interval:)`, `.heavyThud`
- Used by: PMR Sequence (rise/snap), Sigh Validator (inhale cue taps), Entrainment (optional)
- Watch bolt-on: swap implementation to `WKInterfaceDevice.current().play(.hapticType)`

### C. `AudioEngine` (AVFoundation wrapper)
- Sine wave tone generator at configurable Hz
- `play(frequency: Double, duration: TimeInterval)`
- Used by: Ambient Vocal Entrainment (432 Hz drone)
- Optional fade-in/fade-out envelope
- Must handle audio session interruptions (phone calls, notifications)

### D. `EventKitService`
- Authorization request flow
- Fetch events in date range: `fetchEvents(from:to:)`
- Back-to-back detection algorithm: events with <10 min gap
- "Cumulative strain" scoring: meeting count × duration × context-switch penalty
- Break window detection: find 10-min gaps in a workday
- Watch bolt-on: overlay HRV data against calendar timeline

### E. `InterventionSession` (SwiftData model)
- Lightweight session log: type (enum), start time, duration, completed bool
- Used by all 4 intervention features for history tracking
- No PII, no biometrics (on iPhone); add HR/HRV fields when Watch ships

---

## Watch Bolt-On Architecture Strategy

Every intervention feature should be designed with a "biometric validation" hook that is currently a no-op:

```swift
protocol BiometricValidatable {
    var preSessionMetrics: BiometricSnapshot? { get set }
    var postSessionMetrics: BiometricSnapshot? { get set }
    var validationAvailable: Bool { get }  // returns false on iPhone-only
}

struct BiometricSnapshot {
    var heartRate: Double?
    var hrv: Double?
    var timestamp: Date
}
```

- On iPhone: `validationAvailable = false` → hide "validation" UI, show "Add Apple Watch for biometric proof" prompt
- On Watch-connected: populate snapshots via `HKAnchoredObjectQuery`
- This means zero Watch code ships in Phase 1, but the model is Watch-ready

---

## Feature Deep Dives

### Feature A: Micro-PMR Sequence (#16) — Simplest, Ship First

**UX Flow**:
1. User taps "Interventions" → taps "Muscle Release" card
2. Full-screen dark view: muscle group name + instruction ("Tense your shoulders... now")
3. `HapticEngine.rise(duration: 5s)` → building vibration → `HapticEngine.snap` at release
4. 8 muscle groups: shoulders, jaw, hands, abdomen, glutes, thighs, calves, feet
5. Progress indicator (8 dots). Total: ~60 seconds.
6. End screen: "Session complete" + `InterventionSession` saved to SwiftData
7. Watch bolt-on: show HR delta before/after on end screen

**iPhone Haptic Adaptation**:
- "Rise" = `.impactFeedbackGenerator` with `.heavy` style, fired in rapid succession (simulates building tension)
- "Snap" = `.notificationFeedbackGenerator(.success)` — sharp, decisive
- Not as nuanced as Watch Taptic Engine but functional and satisfying

**Data requirement**: None (immediate)
**Effort**: S

---

### Feature B: Somatic Sigh Validator (#14)

**UX Flow**:
1. User taps "Physiological Sigh" card
2. Screen: animated lung illustration (using Canvas API + TimelineView)
3. Phase 1: "Two quick inhales" — two rapid haptic taps, lung expands
4. Phase 2: "Long exhale (8s)" — slow haptic pulse fading out, lung contracts
5. 3 cycles total (~40 seconds)
6. End: "Well done. Your nervous system just reset." + session saved
7. Watch bolt-on: "Heart rate dropped from X to Y" validation card

**Microphone Detection (Optional, Phase 2)**:
- `AVAudioEngine` tap on input bus
- Detect amplitude spike (inhale) followed by 200ms gap (between first and second inhale)
- High false-positive risk (ambient noise). Gate with: only activate detection in quiet environments (ambient < threshold)
- Risk: invasive permission request. Consider haptic-only as the default.

**Data requirement**: None
**Effort**: M (without mic), M+ (with mic — Phase 2 add-on)

---

### Feature C: Ambient Vocal Entrainment (#15)

**UX Flow**:
1. User taps "Vocal Reset" card
2. "Find a private space. Hum along to this tone."
3. 432 Hz drone plays via `AudioEngine`. Visual: slow pulsing waveform (Canvas).
4. Timer: 2:00 countdown
5. Optional: pitch guidance ("Match this tone" with a visual frequency indicator)
6. End: session saved. Brief note on vagal nerve stimulation.
7. Watch bolt-on: HR/HRV delta shown post-session

**Audio Considerations**:
- 432 Hz is a pure sine wave — trivially generated with AVAudioEngine's `AVAudioPlayerNode` + buffer
- Must respect silent mode / Ringer switch — use `.playback` AVAudioSession category (overrides silent mode is opt-in; show "Enable sound" prompt if ringer is off)
- Headphone vs. speaker: recommend headphones for immersion but not required
- Volume fade-in/fade-out to avoid jarring start/stop

**Data requirement**: None
**Effort**: M

---

### Feature D: Sensory Anchoring Widget (#17)

**UX Flow (Widget)**:
1. User adds "Grounding" widget from widget gallery (small or medium size)
2. Widget shows: "Feeling overwhelmed?" + current count progress (e.g. "3 / 5 things you can SEE")
3. Tapping increments the counter for current sense
4. Sense progression: See (5) → Feel (4) → Hear (3) → Smell (2) → Taste (1)
5. On completion: widget resets to a calm state ("Grounded ✓") for 5 minutes, then resets

**Dynamic Island / Live Activity**:
- Start a Live Activity when the user taps "Start Grounding" from inside the app
- Compact view: current sense + remaining count
- Expanded view: sense name + instruction text
- Ends automatically when all 5 senses complete

**WidgetKit Interactive Widget**:
- iOS 17+ interactive widgets support tap actions via AppIntents
- `GoundingWidgetIntent` increments counter via `AppStorage` or shared `UserDefaults` app group
- Must use App Group container for shared state between widget and app process
- State resets after 30 minutes of inactivity (stale session)

**In-App Entry**:
- Also accessible from the Interventions sheet as a full-screen guided flow (for users who prefer in-app over widget)

**Data requirement**: None
**Effort**: M (widget infra) — most complex of the 5 due to WidgetKit/AppIntent bridging

---

### Feature E: Meeting Strain Forecaster (#2)

**UX Flow**:
1. New card in Stress tab: "Today's Meeting Load" (only shown if EventKit access granted)
2. Card shows: meeting count, back-to-back count, total meeting duration, "strain score"
3. Tap → opens `MeetingForecasterView` sheet (`.meetingForecaster` case in StressSheet)
4. Horizontal Gantt timeline of today's calendar
5. Blocks colored green→yellow→red based on back-to-back proximity and duration
6. "Recommended breaks" highlighted in teal: "10-min gap at 2:30 PM could reduce afternoon strain by ~40%"
7. Tomorrow view: same analysis for next workday
8. Watch bolt-on: actual HRV measurements overlaid on the timeline blocks

**Strain Scoring (Without HRV)**:
- Algorithmic (no biometrics needed):
  - Base score per meeting: duration_minutes × 0.5
  - Back-to-back penalty: +15 points per consecutive meeting pair
  - Context-switch penalty: +10 if meeting type changes (based on event title keywords: video/call/standup)
  - Cumulative decay: each additional hour of meetings reduces recovery coefficient
- This is transparent and explainable — label it "Cognitive Load Score" not "Stress Score" to avoid implying biometric accuracy

**EventKit Integration**:
- `EKEventStore.requestFullAccessToEvents()` (iOS 17+ API)
- Fetch today + tomorrow's events from all calendars
- Filter: duration > 15 minutes, not all-day events
- Privacy: all processing on-device; never log event titles to SwiftData (only timestamps + durations)

**Data requirement**: Calendar access grant (immediate)
**Effort**: M

---

## Phasing Recommendation

### Phase 1: Haptic Interventions (No New Infrastructure)
> Theme: "Quick physiological resets in your pocket"
> **Estimated effort: 1–2 weeks**

| Feature | Why First |
|---------|-----------|
| **Micro-PMR Sequence (#16)** | Smallest effort, pure haptics, no new services needed. Validates the InterventionTimerEngine + HapticEngine pattern. |
| **Somatic Sigh Validator (#14)** | Reuses timer + haptic engine from PMR. Adds Canvas breathing animation. Ships without mic detection. |

**Infrastructure built**: `InterventionTimerEngine`, `HapticEngine`, `InterventionSession` model, `StressSheet.interventions` case, `InterventionsView` (list of available resets).

---

### Phase 2: Audio + Widget (New Infra)
> Theme: "Sonic and ambient resets"
> **Estimated effort: 2–3 weeks**

| Feature | Why Second |
|---------|-----------|
| **Ambient Vocal Entrainment (#15)** | Builds `AudioEngine`. Reuses existing InterventionTimerEngine. Standalone enough to not need other Phase 2 features. |
| **Sensory Anchoring Widget (#17)** | Requires WidgetKit interactive widget + App Group shared state. Highest setup overhead but zero biometric dependency. |

**Infrastructure built**: `AudioEngine`, App Group shared container, `GroundingWidget` target additions, `AppIntent` for tap actions, optional `ActivityKit` Live Activity.

---

### Phase 3: Calendar Intelligence
> Theme: "See stress coming before it hits"
> **Estimated effort: 2–3 weeks**

| Feature | Why Third |
|---------|-----------|
| **Meeting Strain Forecaster (#2)** | Requires `EventKitService` (new permission domain). Richer UI than interventions. Benefits from Phase 1 being shipped (users are already in "stress management" mindset). |

**Infrastructure built**: `EventKitService`, `MeetingBlock` model, `MeetingForecasterView`, Gantt chart component (SwiftCharts or Canvas).

---

## Risk Areas & Complexity Hotspots

| Risk | Feature | Severity | Mitigation |
|------|---------|----------|------------|
| WidgetKit App Group state sync bugs | Widget (#17) | High | Use `UserDefaults(suiteName:)` with clear key namespace; test widget + app process independently |
| Audio session interrupted mid-session | Vocal Entrainment (#15) | Medium | Observe `AVAudioSession.interruptionNotification`; auto-pause and show resume prompt |
| Haptic "rise" pattern not satisfying on older iPhones | PMR (#16) | Low-Medium | Test on iPhone 12–15 range; have fallback to single `.heavy` impact if multi-fire feels wrong |
| Calendar permission denial UX | Forecaster (#2) | Medium | Show value proposition card before requesting; graceful empty state if denied |
| Interactive widget AppIntent not triggering on first tap | Widget (#17) | Medium | Known WidgetKit edge case; test on iOS 17/18/26 |
| Users expect Watch validation but don't have one | All interventions | Low | "Add Apple Watch for real-time feedback" prompt is educational, not critical |
| StressSheet enum getting too large | All 5 features | Medium | Consider grouping: `.intervention(InterventionType)` as associated value instead of 5 separate cases |

---

## Open Questions

- [ ] Should all 4 interventions share one `InterventionsView` grid, or does each get a direct StressSheet case?
- [ ] Should `InterventionSession` history be visible inside the Interventions sheet (e.g., "Last used 3 days ago")? Or reserved for a future "Interventions History" view?
- [ ] For the Somatic Sigh mic detection — is it a Phase 2 add-on or cut entirely? Mic permission is a UX cost.
- [ ] Meeting Strain Forecaster: should it also show on the Home tab (today's meeting load as a ring or bar)? Or strictly inside Stress?
- [ ] Should Vocal Entrainment override silent mode (requires explicit user consent) or silently degrade to haptics-only if ringer is off?
- [ ] Widget grounding sessions — should completed sessions be logged to `InterventionSession`? (Requires App Group → SwiftData bridge, nontrivial)
- [ ] Should the Interventions toolbar button use a SF Symbol that communicates "reset/rescue" (e.g., `cross.case`, `bandage`, `bolt.heart`) vs. a more generic symbol?

---

## Progressive Disclosure Strategy

| When | What Unlocks |
|------|-------------|
| Day 1 | All 4 intervention features (no data needed) + Grounding Widget |
| Day 1 (after calendar grant) | Meeting Strain Forecaster card appears in Stress tab |
| Future (Watch connected) | Biometric validation cards appear post-session for Sigh, PMR, Entrainment |
| Future (30 days) | "You've completed 12 resets this month" summary in Interventions sheet |

No progressive data-lock here — all 5 features work on Day 1. This is a deliberate contrast to the biometric-heavy features (Recovery Slope, Archetyping) which require weeks of baseline.

---

## Recommendation

**Build in this order**: PMR → Sigh → Vocal Entrainment → Widget → Meeting Forecaster.

Start with the two haptic interventions because they share infrastructure and validate the pattern with minimal surface area. The Widget is the most complex due to WidgetKit/AppIntent overhead and should not be rushed. The Meeting Forecaster is the most architecturally distinct (new permission domain + richer data model) and benefits from the Interventions home being established first.

The `StressSheet` enum pattern should be extended with an associated value approach to avoid enum bloat:
```swift
case intervention(InterventionType)  // .intervention(.pmr), .intervention(.sigh), etc.
case meetingForecaster
```

This keeps StressView's sheet switch clean as features multiply.

---

## Research References

- `Docs/01_Brainstorming/260403-creative-stress-features-brainstorm.md` — Prior evaluation (deferred these features)
- `Docs/01_Brainstorming/260402-feature-prioritization-from-deep-research-brainstorm.md` — Architecture constraints
- `Docs/02_Planning/Specs/260402-stress-lab-plan-RESOLVED.md` — StressSheet enum pattern (exact precedent)
- `Docs/06_Miscellaneous/WellPlate_ Creative Stress Features.md` — Source feature descriptions
- Apple Docs: `WidgetKit`, `AppIntents`, `AVAudioEngine`, `EventKit`, `UIImpactFeedbackGenerator`
