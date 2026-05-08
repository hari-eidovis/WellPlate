# Brainstorm: Stress → Apple Watch Workout Mission Pipeline

**Date**: 2026-04-28
**Status**: Ready for Strategize
**Related**: `260408-apple-watch-companion-brainstorm.md` (note: that doc explicitly excluded workout tracking — this brainstorm reverses that decision and should be reconciled during strategize)

---

## Problem Statement

When WellPlate detects elevated stress, the app should suggest a short physical intervention (e.g., "Take a 1 km outdoor walk") and hand it off to Apple Watch with one tap. After the user completes the workout, WellPlate records the "mission" as completed, ties it back to the triggering stress reading, and uses the history to motivate further engagement. The end goal is a closed feedback loop: high stress → suggested mission → watch workout → completion record → measurable stress reduction → continued engagement.

---

## Critical Constraint (set expectations upfront)

**Apple does not allow an iPhone app to programmatically start a workout session on Apple Watch.** The user must always tap to begin. This is a watchOS privacy/safety design — there is no API to bypass it. The pipeline must therefore be designed around *suggesting + handing off + observing*, not *remote-starting*.

The realistic flow is:

```
iPhone (stress high) → suggest mission → hand off to Watch
  → Watch shows prompt → user taps Start
  → HKWorkoutSession runs → HKWorkout saved to HealthKit
  → iPhone observes HealthKit → marks mission complete → motivate
```

---

## Core Requirements

- Suggest physical missions when stress score is high and confidence is sufficient
- Hand mission off to Apple Watch as a pre-loaded workout
- Detect workout completion via HealthKit and tie back to the originating mission
- Persist mission history (SwiftData) with stress-before/stress-after deltas
- Surface motivation surface (streak, count, "last walk dropped your stress 15 pts")
- Graceful fallback when no Watch is paired or watchOS is too old
- Cooldown logic to avoid nagging
- Re-engagement notifications when stress trends high but no missions are being completed

---

## Constraints

- No watchOS target exists yet — all current targets are iPhone/iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- iOS 26.1 / watchOS 26 — WorkoutKit (iOS 17+/watchOS 10+) is fully available
- `HKWorkoutSession` is unreliable on watchOS simulator — real device needed for end-to-end testing
- HealthKit observer queries require background mode entitlements and add cold-start cost
- WorkoutKit's `WorkoutScheduler` does not pass arbitrary metadata to the resulting `HKWorkout` — mission ↔ workout matching has to be done by activity type + time window unless a custom watchOS app stamps `HKMetadataKey`
- A previous brainstorm (260408) declared "No GPS workout tracking" as a hard rule — this initiative explicitly revisits that decision

---

## Architecture Options

### Option A — WorkoutKit only (no watchOS target)

`CustomWorkout` scheduled via `WorkoutScheduler.shared.schedule(plan:)`. The workout shows up on Apple Watch as a notification; the user taps and runs it inside the stock Apple Workout app.

- **Pros**: Zero watchOS code, system-managed UX, fastest to ship
- **Cons**: No branded UI on Watch, no in-workout custom data, completion matching by time-window heuristic (less precise), no rich completion summary

### Option B — WatchConnectivity + custom watchOS app

Build a watchOS app target. iPhone sends mission payload via `WCSession`. Watch app runs `HKWorkoutSession` directly, stamps `HKMetadataKey` with the mission UUID, and ships the completion summary back via `WCSession.transferUserInfo`.

- **Pros**: Full UI control, branded "Mission #3 — 1 km walk" experience, exact mission↔workout matching, custom completion screen
- **Cons**: New target, more code, harder testing, simulator caveats

### Option C — Hybrid (recommended once MVP proven)

WorkoutKit defines the workout. A minimal watchOS companion shows mission context and uses the scheduled workout. Best UX/effort ratio in the long run, but most moving parts.

### Recommendation

**Start with Option A** to validate the loop end-to-end with minimal scope. Layer in Option C only after the basic flow is proven and there is a clear UX gap that requires custom Watch UI.

---

## Step-by-Step Requirements

### Phase 1 — Project & Capabilities Setup

1. Add watchOS app target if going Option B/C (skip for Option A). Bundle ID: `com.you.wellplate.watchkitapp`.
2. App Groups (`group.com.you.wellplate`) on iOS, watch app, and any extension that needs shared state.
3. Capabilities:
   - HealthKit on iOS *and* watchOS, with read/write for `HKWorkoutType`
   - Background Modes → "Workout processing" (watchOS), "Background fetch" + "Remote notifications" (iOS)
   - Push Notifications for re-engagement nudges
4. Info.plist: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` on both targets, plus `NSMotionUsageDescription` on watch.
5. Frameworks: `WorkoutKit`, `HealthKit`, `WatchConnectivity` (Option B/C only).

### Phase 2 — Data Model (SwiftData)

6. New model `StressMission`:
   - `id: UUID`
   - `suggestedAt: Date`, `triggeringStressScore: Int`
   - `type: MissionType` enum: `.walkOutdoor`, `.walkIndoor`, `.breathwork`, `.run`, `.cycle`, `.yoga`
   - `targetDistanceMeters: Double?`, `targetDurationSec: Int?`
   - `status: MissionStatus`: `.suggested`, `.accepted`, `.handedOffToWatch`, `.completed`, `.skipped`, `.expired`
   - `workoutUUID: UUID?` (resulting `HKWorkout.uuid`)
   - `completedAt: Date?`, `actualDistanceMeters: Double?`, `actualDurationSec: Int?`
   - `stressScoreAfter: Int?` (snapshot 1–2 hours post-completion for delta computation)
7. Register in `WellPlateApp.swift` `ModelContainer` alongside `StressReading` etc.
8. New `MissionLibrary` (plain Swift) mapping stress level + context (time of day, weather if available) → ranked mission suggestions.

### Phase 3 — Suggestion Engine (iOS)

9. Hook `StressViewModel`: when `confidence` is high *and* `score >= threshold` *and* no active mission in last N hours, surface a `StressMission` via a published property.
10. `MissionCard` view on Stress screen — uses existing card patterns (`RoundedRectangle(cornerRadius: 20)…appShadow`). CTA: "Start on Watch".
11. Cooldown: don't re-suggest within ~2 hours of a skip; expire suggestions after ~30 minutes.

### Phase 4 — Workout Definition (WorkoutKit)

12. `MissionWorkoutBuilder` returns a `CustomWorkout` per mission type:
    - Activity: `.walking` / `.running` / `.cycling` / `.mindAndBody`
    - Location: `.outdoor` / `.indoor`
    - Blocks: warmup (5 min, low HR) → work (target distance or duration) → cooldown (3 min)
13. Mission ↔ workout matching strategy:
    - **Option A**: store `(missionID, expectedStartWindow)` in App Group UserDefaults; match the next `HKWorkout` of the right activity type that lands inside the window
    - **Option B/C**: stamp `HKMetadataKey` on the workout from the watch app

### Phase 5 — Hand-Off to Watch

14. On "Start on Watch" tap:
    - Check `WorkoutScheduler.shared.authorizationState` → request if `.notDetermined`
    - Build `WorkoutPlan(.custom(workout))`
    - `WorkoutScheduler.shared.schedule(plan, at: Date())`
    - Update mission `status = .handedOffToWatch`
15. Result on Watch: notification appears with the workout pre-loaded; user taps → workout starts in Apple Workout app. (Option B/C: send `WCSession.sendMessage` to a custom watch view instead.)
16. Fallback path: if `WCSession.default.isPaired == false` or watchOS < 10, show "Log manually" or "Start on iPhone" so the feature does not dead-end.

### Phase 6 — Watch Side (Option B/C only)

17. `WCSessionDelegate` on watchOS receives mission payload; persist via App Group.
18. SwiftUI mission view: name + target. Tap "Start" → `HKWorkoutSession(configuration:)` + `HKLiveWorkoutBuilder`.
19. On finish: `builder.endCollection`, `builder.finishWorkout` → `HKWorkout`. Stamp `HKMetadataKey` with `missionID`.
20. Send completion summary back via `WCSession.transferUserInfo` (queued, survives reachability gaps — better than `sendMessage` for completion data).

### Phase 7 — Completion Detection (iOS)

21. `HKObserverQuery` on `HKWorkoutType.workoutType()` with `enableBackgroundDelivery`.
22. On callback, run `HKAnchoredObjectQuery` to fetch new workouts since the last anchor.
23. Match new workout to a pending mission:
    - Option A: match by activity type + start time within scheduled window
    - Option B/C: match by `HKMetadataKey` stamped on Watch
24. Update mission: `status = .completed`, store `workoutUUID`, distance, duration. Save via SwiftData.
25. Trigger motivational UI: streak count, stress-delta callout, push notification if app is backgrounded.

### Phase 8 — Motivation Loop

26. New "Missions" section on Stress tab or Profile: completed count, current streak, longest streak, total distance.
27. Compute post-mission stress delta: snapshot stress at suggestion time vs. score 1–2 hours after completion. This is the killer feedback ("Walking dropped your stress 15 points last time").
28. Weekly summary card: "You completed 4/6 missions this week."
29. Re-engagement notifications: silent push when stress trends high and no mission completed in 24h.

### Phase 9 — Permissions UX

30. Onboarding screen: "WellPlate suggests short physical missions when your stress is high. We'll send these to your Apple Watch so you can start with one tap."
31. Just-in-time permission requests (fire when first mission is suggested), not all upfront — better acceptance rates.
32. Graceful empty/error states for: no Watch paired, HealthKit denied, WorkoutKit unauthorized, watchOS too old.

### Phase 10 — Testing & Ship

33. Add watch scheme to build commands: `xcodebuild -scheme WellPlateWatch …`.
34. Mock mode (`AppConfig.mockMode`): allow "fake complete" of a mission to test motivation loop without a real workout.
35. **Real device required** for `HKWorkoutSession` end-to-end testing. Plan paired iPhone+Watch test passes early.
36. Edge cases:
    - Watch out of range when scheduling
    - User starts the workout but force-quits Apple Workout app
    - User completes the suggested activity in a different app (Strava, Nike Run Club) — credit it or not?
    - Multiple suggestions in flight
    - Time zone changes mid-workout
    - HK observer fires before WCSession completion payload (race condition)

---

## Minimal Viable Slice (1 week target)

Skip Phase 6 + Option C. Build A-only:

- `StressMission` model + suggestion card on Stress tab
- WorkoutKit hand-off (1 mission type: outdoor walk, 1 km)
- HK observer matching by activity + time window
- Simple "missions completed" counter

That closes the loop end-to-end. Custom watch UI, breathwork, streak gamification, and stress-delta feedback layer on top once the core is proven.

---

## Open Questions

- Reconcile with the 260408 brainstorm's "no GPS workout tracking" rule — has the product direction officially changed?
- Should missions completed in 3rd-party apps (Strava, Nike Run Club) count? (User intent vs. attribution complexity.)
- Streak granularity: daily? per-suggestion? weekly?
- Should we ever suggest indoor breathwork-only missions when no Watch is paired, so non-Watch users still get value?
- How does this interact with the existing `Burn` feature's calorie tracking — do mission workouts double-count?
- Notification fatigue policy: hard cap on mission suggestions per day?

---

## Next Step

Run `/develop strategize 260428-stress-watch-mission-pipeline-brainstorm.md` to lock in Option A vs. C and produce a strategy doc, then `/develop plan` for the MVP slice.
