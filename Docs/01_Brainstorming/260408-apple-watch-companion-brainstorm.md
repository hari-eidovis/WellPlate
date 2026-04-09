# Brainstorm: F8 — Apple Watch Companion

**Date**: 2026-04-08
**Status**: Ready for Planning

---

## Problem Statement

WellPlate's core value — knowing your stress score, logging mood/water, launching a breathing intervention — requires pulling out your iPhone. The Watch is the right surface for glanceable wellness data and sub-5-second interactions. F7 (Live Activities) already shows fasting/breathing on Lock Screen; F8 extends that presence to the wrist.

---

## Core Requirements

- Glanceable stress score complication (current score + level label)
- Quick mood log (5 emoji options via crown or tap)
- Quick water log (+ glass button)
- Breathing session launch (Sigh or PMR, runs on Watch using timer)
- "One suggestion" card — the single highest-impact action right now
- **No GPS workout tracking** (hard rule from roadmap)
- **Only ship what looks correct** (design rule: don't ship ugly Watch UI)

---

## Constraints

- No WatchKit target exists yet — this is a brand-new app extension
- Main app is iOS 26.1 (Xcode 26) — paired platform is watchOS 26
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` carry to Watch target
- `PBXFileSystemSynchronizedRootGroup` only applies to `WellPlate/` folder — Watch target needs `WellPlateWatch/` sibling folder
- SwiftData is available on watchOS but has known caveats (no background context, limited migrations)
- Breathing session needs `InterventionTimer` — either share the file or reimplement a Watch-native timer
- Budget: ~8–10 new files (roadmap estimate)

---

## Approach 1: Complications-Only (WidgetKit, No Full App)

**Summary**: Add Watch complications to the existing `WellPlateWidget` WidgetKit bundle — no standalone Watch app, no WatchConnectivity.

**How it works**:
- Extend `WellPlateWidget` bundle with `@main` `Widget` entries targeting `watchOS`
- Use `AppIntentTimelineProvider` to fetch stress score from HealthKit or a shared App Group UserDefaults key that the iPhone writes on each update
- Tapping the complication deep-links into the iPhone app (standard WatchKit behavior)

**Pros**:
- Zero new target — complications live in existing widget bundle (dual-platform since watchOS 9)
- Minimal code: 1–2 new files
- No WatchConnectivity complexity
- Complication looks native immediately

**Cons**:
- No quick-log actions (mood/water) — Watch is read-only
- Breathing launch impossible without a full Watch app
- Deep-link on tap bounces user to iPhone, defeating the "wrist-first" value
- Can't show "one suggestion" in any interactive way

**Complexity**: Low
**Risk**: Low
**Verdict**: Too limited — misses quick-log and breathing, which are the core interactive value.

---

## Approach 2: Full Companion Watch App via WatchConnectivity (WCSession)

**Summary**: New `WellPlateWatch` target with a full SwiftUI Watch app. iPhone↔Watch sync via `WCSession`. Watch stores a lightweight ephemeral cache; all writes go back to iPhone.

**How it works**:
- `WatchConnectivityService` on both sides (iPhone `@MainActor` singleton + Watch `@MainActor` singleton)
- iPhone pushes `applicationContext` update whenever stress score, mood, water, or fasting state changes
- Watch reads cached values from `WCSession.applicationContext` for glanceability — no persistent storage needed
- Quick-log actions (mood, water) send `sendMessage()` to iPhone which writes to SwiftData/HealthKit
- Breathing session: Watch-side `InterventionTimerWatch` (simplified port, ~40 lines) runs locally — no iPhone needed mid-session
- Complications: WidgetKit-based, pull from shared `AppGroup` UserDefaults (iPhone writes, Watch reads)

**Pros**:
- Full interactive experience: glance + log + breathe all on wrist
- Offline-capable for display (cached applicationContext survives disconnects)
- Breathing works without iPhone in range (runs on-device timer)
- WCSession is well-understood, battle-tested
- Complications use existing WidgetKit pattern

**Cons**:
- WCSession sync adds latency (~1–3s for message round-trips)
- Two-way sync is stateful — must handle "iPhone not reachable" gracefully (queue writes, retry on reconnect)
- New target adds CI build time
- InterventionTimer must be ported or shared (shared file is cleaner but requires dual target membership)

**Complexity**: Medium
**Risk**: Medium (WCSession edge cases on first pairing, background reachability)
**Verdict**: Best balance of interactivity and correctness for MVP.

---

## Approach 3: Shared SwiftData Container (App Groups)

**Summary**: Use an App Group shared container so Watch reads/writes the same `SwiftData` `WellnessDayLog` as iPhone. WCSession used only for session-launching.

**How it works**:
- Configure App Group entitlement (`group.com.wellplate.app`)
- Move `ModelContainer` to shared container URL on both iPhone and Watch
- Watch directly queries/mutates `WellnessDayLog` — no WCSession for data
- WCSession only needed to launch a breathing session (Wake Watch → start timer)

**Pros**:
- Eliminates sync complexity entirely — single source of truth
- Mutations on Watch are immediately visible on iPhone (next HealthKit poll)

**Cons**:
- SwiftData shared-container between two targets has edge cases: concurrent writes from both sides without merge conflict resolution can corrupt the store
- Watch background execution is extremely limited — model saves might not flush before Watch sleeps
- App Group entitlement is a new manual Xcode step (provisioning profile change)
- No offline-read guarantee — if SwiftData store is locked by iPhone, Watch read blocks
- Significantly higher risk for a feature that's already Medium-High effort

**Complexity**: Medium-High
**Risk**: High (SwiftData multi-process is not well-tested in production Watch apps)
**Verdict**: Elegant in theory, risky in practice. Skip for MVP.

---

## Approach 4: Watch-Native HealthKit Reads (No iPhone Bridge for Data)

**Summary**: Watch reads all data directly from HealthKit (where available) and falls back to WCSession only for WellPlate-specific data (mood, water).

**How it works**:
- Stress score = recomputed on Watch from HealthKit HRV + HR + sleep (Watch has direct HK access)
- Mood + water: WCSession for logs (no HK storage for these)
- Breathing: on-device timer
- Complications: HealthKit background delivery

**Pros**:
- Stress score on Watch is live from Watch sensors (potentially more accurate)
- Reduces WCSession message volume

**Cons**:
- Stress scoring logic must be duplicated on Watch (StressScoring.swift) or shared
- WellPlate's stress score formula includes screen time — that's iPhone-only data
- The Watch score would be a different number than what iPhone shows — confusing
- "One suggestion" requires all four factor scores, which requires iPhone data anyway

**Complexity**: High
**Risk**: Medium-High (score divergence creates user trust issues)
**Verdict**: Don't compute a different score on Watch. Always mirror iPhone's score.

---

## Edge Cases to Consider

- [ ] Watch app launched when iPhone is off / out of range — must display last-known cached state gracefully (no spinner of death)
- [ ] Mood already logged today — show current mood, allow change via crown
- [ ] Fasting active when Watch app opens — show fasting countdown (mirrors Live Activity)
- [ ] Breathing session started on Watch while iPhone starts one too — in practice impossible (Watch breathing is Watch-only), but handle ActivityManager state
- [ ] WCSession "not reachable" during mood/water log — queue the write, show optimistic UI, sync when connection restores
- [ ] Watch app opens for first time (no cached applicationContext) — show loading state, not empty/broken UI
- [ ] Crown scroll on mood picker — 5 emoji options, crown increments through them
- [ ] Breathing session interrupted by notification / Watch sleep — timer must survive backgrounding (use `WKExtendedRuntimeSession`)
- [ ] Complication refresh rate — WidgetKit complications update on timeline; stress score only meaningful if refreshed at least hourly

---

## Open Questions

- [ ] Should breathing on Watch also start a Live Activity on iPhone Lock Screen? (Possibly yes — `ActivityManager.shared.startBreathingActivity()` called via WCSession on iPhone)
- [ ] Does "one suggestion" require LLM (Groq) or can it be rule-based on Watch? (Rule-based is safer — no network dependency on Watch)
- [ ] WatchKit app vs. watchOS App — which Xcode template? (watchOS App in Xcode 26 is the modern SwiftUI-first template)
- [ ] Should `InterventionTimer` be a shared file (dual Watch + iPhone target membership) or ported as `WatchInterventionTimer`? (Shared is DRY; dual membership has no Watch-specific issues since InterventionTimer is pure Swift)
- [ ] Complication placement — which Watch face families to target? (Minimum: `.accessoryCircular`, `.accessoryRectangular`, `.accessoryCorner`)
- [ ] Does tapping a Watch complication open the WellPlate Watch app or the iPhone app? (Watch app — always stays on wrist)

---

## Recommendation

**Approach 2** (Companion Watch App via WCSession) is the right call.

- It's the established pattern for iPhone-dependent wellness apps (e.g., Oura, Whoop Watch faces use the same WCSession bridge).
- iPhone remains the authoritative data source — no score divergence, no SwiftData multi-process risk.
- Breathing works offline (on-device timer + `WKExtendedRuntimeSession`).
- The ~8–10 file budget maps cleanly: `WatchConnectivityService.swift` (shared or two-file), 3–4 Watch views, complication provider, `WatchInterventionTimer.swift`, `WatchAppMain.swift`.
- WCSession's "not reachable" states are well-documented and manageable with optimistic UI + queued writes.

**MVP scope for F8** (ship what looks correct):
1. Complications: Stress score circular + rectangular
2. Glance screen: Score + level + "one suggestion" (rule-based)
3. Quick log: Mood (crown picker) + Water (stepper)
4. Breathing launch: Sigh only for MVP (PMR is long — 8 muscle groups on a small screen is awkward)

**Defer to V2**: PMR on Watch, fasting countdown view (mirrors Live Activity), SharePlay co-breathing (F10 territory).

---

## Research References

- WatchConnectivity framework docs: bidirectional sync via `applicationContext` (background) + `sendMessage` (foreground interactive)
- WidgetKit on watchOS: same `TimelineProvider` pattern as iOS complications, `.accessoryFamily` widget families
- `WKExtendedRuntimeSession`: keeps Watch app active during workout/mindfulness — use for breathing timer
- WellPlate existing pattern: `ActivityManager.swift` (F7) as reference for singleton service pattern
- Related WellPlate doc: `260405-no-watch-interventions-strategy.md` — previously decided to NOT put interventions on Watch; F8 revisits this with a narrowed scope (Sigh only, no PMR for MVP)
