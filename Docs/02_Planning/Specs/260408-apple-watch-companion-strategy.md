# Strategy: F8 — Apple Watch Companion

**Date**: 2026-04-08
**Source**: `Docs/01_Brainstorming/260408-apple-watch-companion-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**WCSession Companion Watch App** (Brainstorm Approach 2). A new `WellPlateWatch` watchOS target with a SwiftUI app, WidgetKit complications, and WatchConnectivity as the sole data bridge. iPhone remains the single source of truth — Watch is a glanceable read surface with quick-log write actions and a standalone Sigh breathing session.

---

## Rationale

- **WCSession over SharedSwiftData**: `SharedStressData.swift` already proves the App Group pattern works for widget reads, but SwiftData multi-process writes between iPhone and Watch are fragile (brainstorm Approach 3 risk). WCSession's `applicationContext` is designed for exactly this: background-delivered, last-write-wins, Codable dictionaries.
- **WCSession over Watch-native HealthKit**: The stress score formula includes screen time (iPhone-only data). Recomputing on Watch would produce a different number — instant user trust erosion.
- **InterventionTimer reused, not ported**: The file is pure Foundation/Combine (no UIKit dependency beyond `HapticService`). Dual target membership is cleaner than a rewrite. On Watch, haptics route through `WKInterfaceDevice.current().play(_:)` instead of `HapticService`.
- **Sigh only for MVP**: The brainstorm flags PMR (8 muscle groups × tense/release) as awkward on a 45mm screen. Sigh (3 cycles × inhale/inhale/exhale) is 33 seconds — perfect for Watch.
- **Existing `WidgetStressData` pattern proven**: The App Group `group.com.hariom.wellplate` and `UserDefaults`-based Codable store already feeds the stress widget. Watch complications can read from the same store (updated by `PhoneSessionService` via WCSession).

---

## Affected Files & Components

### New Target

| Item | Detail |
|------|--------|
| Target name | `WellPlateWatch` |
| Platform | watchOS 26 |
| Template | watchOS App (SwiftUI) |
| Bundle ID | `com.hariom.wellplate.watchapp` |
| App Group | `group.com.hariom.wellplate` (same as widget) |

### New Files (~9)

| File | Purpose |
|------|---------|
| `WellPlateWatch/WellPlateWatchApp.swift` | Entry point, activates `WatchSessionService` |
| `WellPlateWatch/Views/WatchHomeView.swift` | Stress gauge + level label + suggestion card + quick-action buttons (mood, water, breathe) |
| `WellPlateWatch/Views/WatchMoodPicker.swift` | Digital Crown picker for 5 mood emojis, sends selection to iPhone via `sendMessage` |
| `WellPlateWatch/Views/WatchBreathingView.swift` | Sigh session — reuses `InterventionTimer` with Watch-native haptics (`WKInterfaceDevice`) |
| `WellPlateWatch/Views/WatchSessionCompleteView.swift` | Post-Sigh summary (duration, cycle count), auto-dismiss after 3s |
| `WellPlateWatch/Services/WatchSessionService.swift` | `WCSessionDelegate` on Watch: receives `applicationContext`, sends mood/water messages |
| `WellPlateWatch/Complications/StressComplication.swift` | WidgetKit `Widget` for `.accessoryCircular` (gauge) and `.accessoryRectangular` (score + level + trend arrow) |
| `WellPlate/Core/Services/PhoneSessionService.swift` | `WCSessionDelegate` on iPhone: pushes context updates, receives + applies mood/water writes |
| `WellPlate/Shared/WatchTransferPayload.swift` | Codable structs for WCSession data (dual target membership: WellPlate + WellPlateWatch) |

### Modified Files (~3)

| File | Change |
|------|--------|
| `WellPlate/App/WellPlateApp.swift` | Activate `PhoneSessionService.shared` in `init()` to start WCSession |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | After `loadData()` completes, call `PhoneSessionService.shared.pushUpdate(...)` with current stress score + factors + mood + water |
| `WellPlate/Core/Services/InterventionTimer.swift` | Add `WellPlateWatch` to target membership (Xcode manual step). Replace `HapticService` calls with a protocol/closure injection so Watch can substitute `WKInterfaceDevice` haptics |

### Shared Files (Dual Target Membership)

| File | Targets |
|------|---------|
| `WellPlate/Core/Services/InterventionTimer.swift` | WellPlate + WellPlateWatch |
| `WellPlate/Shared/WatchTransferPayload.swift` | WellPlate + WellPlateWatch |

### Existing Files Referenced (No Changes)

| File | Why |
|------|-----|
| `WellPlate/Widgets/SharedStressData.swift` | Reference for App Group ID (`group.com.hariom.wellplate`) and Codable store pattern |
| `WellPlate/Models/StressModels.swift` | `StressLevel` enum used in payload mapping |
| `WellPlate/Core/Services/StressScoring.swift` | Scoring runs on iPhone only — Watch receives the result |

---

## Architectural Direction

### 1. Data Flow

```
iPhone (authoritative)                    Watch (glanceable surface)
┌──────────────────────┐                 ┌──────────────────────┐
│ StressViewModel      │  applicationContext  │ WatchSessionService  │
│   loadData() ────────┼──────────────────►│   .stressPayload     │
│                      │                 │                      │
│ PhoneSessionService  │  sendMessage(reply)  │ WatchHomeView        │
│   onMoodReceived() ◄─┼──────────────────┤   tapMood / tapWater │
│   onWaterReceived() ◄┤                 │                      │
└──────────────────────┘                 └──────────────────────┘
```

- **iPhone → Watch**: `WCSession.default.updateApplicationContext(_:)` — called after every `StressViewModel.loadData()`. Contains full `WatchStressPayload`. Background-delivered; survives disconnects.
- **Watch → iPhone**: `WCSession.default.sendMessage(_:replyHandler:)` — for mood and water logs. Requires iPhone reachable. If unreachable, queue in `UserDefaults` and retry in `sessionReachabilityDidChange`.
- **Complications**: Read from App Group `UserDefaults` (same `WidgetStressData` store updated by `StressViewModel`). No WCSession needed — iOS widget refresh helper already writes to App Group.

### 2. WatchTransferPayload

```swift
struct WatchStressPayload: Codable {
    let stressScore: Double           // 0–100
    let stressLevel: String           // StressLevel.rawValue
    let encouragement: String
    let suggestion: String            // rule-based "one suggestion"
    let topStressorTitle: String?     // "Screen Time", "Sleep", etc.
    let currentMoodRaw: Int?          // 0–4 or nil
    let waterGlasses: Int             // 0–8
    let isFasting: Bool
    let fastEndDate: Date?
    let lastUpdated: Date
}

struct WatchActionMessage: Codable {
    enum Action: String, Codable {
        case logMood
        case logWater
        case breathingCompleted
    }
    let action: Action
    let moodRaw: Int?                 // for .logMood
    let waterDelta: Int?              // for .logWater (+1 / -1)
    let breathingDurationSeconds: Int? // for .breathingCompleted
}
```

### 3. "One Suggestion" — Rule-Based Engine

No LLM/Groq on Watch. Pure rule-based on iPhone, result sent in payload:

| Condition | Suggestion |
|-----------|------------|
| `stressScore > 65` | "Try a breathing exercise" |
| Top stressor = Exercise | "Take a 10-minute walk" |
| Top stressor = Sleep | "Wind down 30 min earlier tonight" |
| Top stressor = Diet | "Add a protein-rich snack" |
| Top stressor = Screen Time | "Take a screen break" |
| No valid data | "Log your first meal to get started" |

Priority: high stress override → top stressor → default.

### 4. InterventionTimer Haptic Abstraction

Current `InterventionTimer` calls `HapticService.impact(.heavy)` directly — `HapticService` uses `UIImpactFeedbackGenerator` which doesn't exist on watchOS.

**Fix**: Replace the `fireHaptic()` method's direct `HapticService` calls with a closure property:

```swift
var hapticHandler: ((HapticPattern, TimeInterval) -> Void)?
```

iPhone sets `timer.hapticHandler = { pattern, duration in /* HapticService calls */ }`.
Watch sets `timer.hapticHandler = { pattern, _ in WKInterfaceDevice.current().play(.click) }`.

This avoids adding a protocol, keeps the change minimal, and doesn't break existing iPhone callers (they just set the closure before calling `start()`).

### 5. Watch Complications

Two families for MVP:

- **`.accessoryCircular`**: Gauge showing stress score 0–100, tinted by `StressLevel.color`
- **`.accessoryRectangular`**: Score number + level label + trend arrow (↑/↓/→ vs yesterday)

Data source: `WidgetStressData.load()` from App Group — same data the iOS stress widget reads. Timeline: reload every 30 minutes via `TimelineReloadPolicy.after(...)`.

### 6. Watch Breathing Session

- Uses shared `InterventionTimer` with Sigh phases (same 3-cycle config as `SighSessionView`)
- Haptics via `WKInterfaceDevice.current().play(.start)` / `.click` / `.success`
- `WKExtendedRuntimeSession` keeps the app alive during the 33-second session
- On completion, sends `WatchActionMessage(.breathingCompleted)` to iPhone for `InterventionSession` SwiftData persistence
- Watch does **not** start a Live Activity — that's iPhone-side only

---

## Design Constraints

1. **iPhone is the sole data authority**: Watch never computes stress scores, never writes to SwiftData, never queries HealthKit. All writes go to iPhone via `sendMessage`.
2. **Single WCSession pair**: `PhoneSessionService` is a `@MainActor` singleton on iPhone. `WatchSessionService` is `@MainActor` singleton on Watch. Both activate in their respective `App.init()`.
3. **InterventionTimer shared file**: Must not import UIKit or WatchKit at the top level. Haptic dispatch goes through a closure, not a static call.
4. **No SwiftData on Watch**: The Watch app has no `ModelContainer`. All persistence happens on iPhone.
5. **Optimistic UI for writes**: Mood/water taps update Watch UI immediately (local state), then send to iPhone. If send fails, retry on reconnect. Never block UI on network.
6. **Complication reads from App Group, not WCSession**: Complications run in a separate process; they can't access WCSession. They read from `UserDefaults(suiteName: "group.com.hariom.wellplate")`.
7. **Font/shadow conventions don't apply on Watch**: watchOS has its own `Font.system(.body, design: .rounded)` patterns. Use system fonts and standard watchOS spacing.
8. **Dark background is the default**: watchOS is always dark — no need for the iPhone `.preferredColorScheme(.dark)` pattern.

---

## Non-Goals

- **PMR on Watch** — too many steps for small screen. Sigh only for MVP.
- **Fasting countdown view on Watch** — fasting state already visible via Live Activity (F7) on Lock Screen. Watch shows "Fasting" badge in home view but no timer UI.
- **Watch-initiated fasting start/stop** — too complex for MVP. Fasting management stays on iPhone.
- **SharePlay co-breathing** — F10 territory.
- **HealthKit queries on Watch** — no direct HK reads. All data proxied from iPhone.
- **Custom Watch face** — Apple doesn't allow third-party Watch faces.
- **Offline-first Watch app** — if iPhone hasn't pushed context, Watch shows "Open WellPlate on iPhone" placeholder.

---

## Open Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `sendMessage` fails when iPhone is not reachable (e.g., iPhone left at home during a walk) | Medium | Queue writes in `UserDefaults`; flush on `sessionReachabilityDidChange`. Show "Synced" / "Pending" indicator. |
| `applicationContext` delivery can be delayed by system (up to minutes in background) | Low | Complications use App Group (faster path). Main Watch app shows `lastUpdated` time so user knows data freshness. |
| `WKExtendedRuntimeSession` may be denied by system under resource pressure | Low | Breathing session still works — timer runs as long as app is foreground. Session just won't survive wrist-down. Keep sessions under 60s (Sigh is 33s). |
| InterventionTimer haptic closure breaks existing iPhone callers | Medium | Make closure optional (`hapticHandler: ((HapticPattern, TimeInterval) -> Void)?`). Existing `fireHaptic()` checks closure first, falls back to `HapticService` if nil. Zero-change for current iPhone code. |
| Watch target creation is an Xcode manual step (not automatable via code) | Low | Checklist will include explicit Xcode instructions. All file creation is automatable once the target exists. |
| App Group entitlement must be added to Watch target provisioning profile | Low | Same App Group already exists for widget. Just add Watch target to its entitlement. |
