# Strategy: No-Watch Stress Interventions (Phase 1–3)

**Date**: 2026-04-05
**Source**: `Docs/01_Brainstorming/260405-no-watch-interventions-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Approach 3 + 4 hybrid**: A toolbar "Interventions" button on StressView (mirroring the existing "Lab" flask button) that opens an `InterventionsView` sheet containing all reset exercises, **plus** an inline contextual card surfaced in the Stress tab when stress score is elevated.

All 5 features ship across 3 phases, each building on shared infrastructure from the prior phase. Phase 1 (PMR + Sigh) is the planning scope for the immediate next step; Phases 2–3 are architecturally described but will have their own plan documents.

---

## Rationale

- **Approach 3 wins over Approach 1** (inline section) because StressView's `mainScrollView` is already content-dense — score gauge, day/week charts, 4 factor cards, vitals grid, stress lab card. Adding a horizontal scroll row bloats it further. A toolbar button keeps the surface clean.
- **Approach 3 wins over Approach 2** (5th tab) because 5 intervention features without Watch biometric proof are too thin to justify a new tab. A sheet off StressView is the exact precedent set by Stress Lab, which has proven to work.
- **Approach 4 (contextual card)** augments Approach 3 by surfacing a "Try a reset" recommendation card when `stressScore > 65` (existing `StressLevel.high` threshold), linking directly to the interventions sheet. This is additive, not structural.
- **Phase 1 scope (PMR + Sigh)** because they share the same infrastructure (timer + haptics), require zero new permission domains, and validate the entire Interventions architecture with minimal surface area.

---

## Affected Files & Components

### New Files (Phase 1)

| File | Purpose |
|------|---------|
| `WellPlate/Core/Services/InterventionTimer.swift` | Phase-aware countdown timer engine (`@Observable`) |
| `WellPlate/Models/InterventionSession.swift` | SwiftData `@Model` for session history (type, start, duration, completed) |
| `WellPlate/Models/ResetType.swift` | Enum for reset session types (`.pmr`, `.sigh`, `.vocalEntrainment`, `.grounding`) — separate from existing `InterventionType` which is for Stress Lab experiments |
| `WellPlate/Features + UI/Stress/Views/InterventionsView.swift` | Sheet listing all available resets (grid of cards) |
| `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` | Full-screen dark PMR exercise (8 muscle groups, haptic-guided) |
| `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` | Breathing guide (Canvas animation + haptics, 3 cycles) |
| `WellPlate/Features + UI/Stress/Views/SessionCompleteView.swift` | Shared post-session summary (reusable across all reset types) |

### Modified Files (Phase 1)

| File | Change |
|------|--------|
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Add `.interventions` case to `StressSheet` enum; add second leading toolbar button (or group Lab + Interventions into a menu); handle `.interventions` in sheet switch |
| `WellPlate/App/WellPlateApp.swift` | Add `InterventionSession.self` to `modelContainer` schema array |

### Existing Files Referenced (No Changes)

| File | Why Referenced |
|------|---------------|
| `WellPlate/Core/Services/HapticService.swift` | Extend with new patterns: `.pmrTense(intensity:)`, `.pmrRelease()`, `.sighInhale()`, `.sighExhale()` — OR keep HapticService as-is and call existing API from session views directly |
| `WellPlate/Core/Services/SoundService.swift` | Optional: confirmation sound on session complete |
| `WellPlate/Models/StressExperiment.swift` | Contains existing `InterventionType` enum — new `ResetType` intentionally separate |

### Future Phase Files (Architecture Awareness Only)

| Phase | Key Files |
|-------|-----------|
| Phase 2 | `AudioEngine.swift` (sine wave generator), `VocalEntrainmentSessionView.swift`, `GroundingWidget.swift` (WidgetKit), `GroundingWidgetIntent.swift` (AppIntents) |
| Phase 3 | `EventKitService.swift`, `MeetingForecasterView.swift`, `MeetingStrainCard.swift` |

---

## Architectural Direction

### 1. StressSheet Extension Pattern

Add two new cases to the existing `StressSheet` enum:

```swift
enum StressSheet: Identifiable {
    // ... existing cases ...
    case interventions             // opens InterventionsView grid
    case resetSession(ResetType)   // opens specific session full-screen

    var id: String {
        switch self {
        // ... existing ...
        case .interventions:         return "interventions"
        case .resetSession(let t):   return "reset_\(t.rawValue)"
        }
    }
}
```

This avoids a sheet-within-sheet problem: tapping a card in `InterventionsView` dismisses the sheet and sets `activeSheet = .resetSession(.pmr)`, which opens the session view directly. Alternatively, `InterventionsView` can use `NavigationStack` push internally — either pattern works, but the `StressSheet` associated-value approach is cleaner and consistent with `.vital(VitalMetric)`.

### 2. InterventionTimer Engine

```swift
@Observable
final class InterventionTimer {
    var phase: String = ""
    var progress: Double = 0      // 0.0–1.0 within current phase
    var totalProgress: Double = 0  // 0.0–1.0 across all phases
    var isRunning: Bool = false
    var isComplete: Bool = false
    
    func start(phases: [TimerPhase]) { ... }
    func pause() { ... }
    func cancel() { ... }
}

struct TimerPhase {
    let name: String          // "Tense shoulders", "Inhale × 2"
    let duration: TimeInterval
    let hapticPattern: HapticPattern?  // optional haptic to fire
}
```

Each session view creates its own `InterventionTimer` with a custom phase array. The timer fires `@Published` updates that drive SwiftUI animations. This is the single reusable engine for PMR (8 phases × ~7.5s each), Sigh (6 phases: [inhale, inhale, exhale] × 3 cycles), and future Vocal Entrainment (1 phase × 120s).

### 3. InterventionSession SwiftData Model

```swift
@Model
final class InterventionSession {
    var type: String              // ResetType.rawValue
    var startedAt: Date
    var durationSeconds: Int
    var completed: Bool
    // Watch bolt-on fields (nil on iPhone)
    var preHeartRate: Double?
    var postHeartRate: Double?
    var preHRV: Double?
    var postHRV: Double?
}
```

Optional biometric fields are `nil` on iPhone. When Watch ships, populate them via `HKAnchoredObjectQuery` before and after the session. The session complete view conditionally shows "HR: 94 → 72 BPM" only when `postHeartRate != nil`.

### 4. Toolbar Button Strategy

StressView already has two toolbar items (leading: Lab flask, trailing: Insights chart). Adding a third risks crowding. Two options:

**Option A — Leading toolbar menu**:
```swift
ToolbarItem(placement: .topBarLeading) {
    Menu {
        Button("Lab", systemImage: "flask.fill") { activeSheet = .stressLab }
        Button("Resets", systemImage: "bolt.heart.fill") { activeSheet = .interventions }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
}
```

**Option B — Two separate leading buttons**: Keep flask for Lab, add `bolt.heart.fill` for Interventions.

**Decision**: Option A (Menu) is cleaner and scales as features grow. The menu icon uses the stress-level accent color for consistency.

### 5. Contextual Recommendation Card

In `mainScrollView`, below the factor cards section, add a conditional card:

```swift
if viewModel.stressScore > 65 {
    ResetRecommendationCard {
        activeSheet = .interventions
    }
}
```

This is a simple `VStack` card with "Feeling stressed? Try a quick reset →" text using the existing card pattern. It only appears when stress is high — not always present.

---

## Design Constraints

1. **Single `.sheet(item:)` rule**: All new presentations must go through the existing `activeSheet` state variable and `StressSheet` enum — no new `.sheet()` modifiers on StressView
2. **No Watch code in Phase 1**: Optional biometric fields exist in the data model, but no HealthKit queries or WatchKit imports. The `SessionCompleteView` hides biometric sections when data is `nil`
3. **HapticService stays static**: Don't refactor `HapticService` into a protocol/instance — it's a static utility used everywhere. Session views call `HapticService.impact(.heavy)` directly; pattern orchestration lives in `InterventionTimer`
4. **Dark session views**: PMR and Sigh full-screen views use a dark background (`.black` or very dark gray) with minimal text to reduce cognitive load during acute stress — this is the doc's explicit UX direction
5. **Font/shadow conventions**: All new views use `.r(.headline, .semibold)`, `.appShadow(radius:y:)`, `RoundedRectangle(cornerRadius: 20)` as specified in CLAUDE.md
6. **ResetType is separate from InterventionType**: Stress Lab's `InterventionType` (caffeine cutoff, screen curfew, etc.) represents multi-day experiments. `ResetType` (pmr, sigh, entrainment, grounding) represents acute 30-120 second exercises. Different semantic domains, different enums.

---

## Non-Goals

- **Apple Watch companion app** — no WatchKit, no WKExtension, no Taptic Engine patterns. Watch bolt-on is a future phase.
- **Microphone-based sigh detection** — cut from Phase 1 entirely. Mic permission is a UX cost with high false-positive risk. May revisit in a future brainstorm, but it's not on the roadmap.
- **Live Activities for interventions** — the grounding widget (Phase 2) will explore ActivityKit, but Phase 1 sessions are too short (40–60s) to warrant a Live Activity.
- **AI-generated post-session insights** — Foundation Models narrative ("Your breathing reset was 30% more effective today") is premature without Watch data. Defer until biometric validation is available.
- **Meeting Strain Forecaster** — Phase 3 scope. Not planned here; will get its own strategy + plan documents when Phase 2 completes.
- **Sensory Anchoring Widget** — Phase 2 scope. Requires WidgetKit/AppIntents infrastructure that's separate from the intervention engine.

---

## Open Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Haptic "rise" pattern (rapid-fire `.heavy` impacts) may drain battery or feel janky on older devices | Medium | Test on physical device; cap rapid-fire to 3Hz; fall back to single strong impact if device is older than iPhone 12 |
| `StressSheet` enum growing unwieldy (now 8+ cases) | Low | The associated-value pattern (`.resetSession(ResetType)`) keeps it contained. One new case covers all future reset types |
| Users don't discover the toolbar menu | Low | Contextual recommendation card provides a second entry point when stress is high |
| SwiftData migration needed for `InterventionSession` | Low | Additive migration — new model, no existing data touched. Same pattern as `StressExperiment` |
| Session views need to prevent screen sleep during exercise | Low | Set `UIApplication.shared.isIdleTimerDisabled = true` on appear, reset on disappear |

---

## Phase Summary

| Phase | Features | New Infra | Effort |
|-------|----------|-----------|--------|
| **1 (plan now)** | Micro-PMR + Somatic Sigh | InterventionTimer, InterventionSession model, InterventionsView, StressSheet extension | 1–2 weeks |
| **2 (plan later)** | Vocal Entrainment + Grounding Widget | AudioEngine (AVFoundation), WidgetKit interactive widget, App Group, AppIntents | 2–3 weeks |
| **3 (plan later)** | Meeting Strain Forecaster | EventKitService, Gantt chart view, MeetingBlock model | 2–3 weeks |
