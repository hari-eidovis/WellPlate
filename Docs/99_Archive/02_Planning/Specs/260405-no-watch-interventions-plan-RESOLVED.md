# Implementation Plan: No-Watch Stress Interventions — Phase 1 (Micro-PMR + Somatic Sigh) — RESOLVED

**Date**: 2026-04-05
**Strategy**: `Docs/02_Planning/Specs/260405-no-watch-interventions-strategy.md`
**Audit**: `Docs/03_Audits/260405-no-watch-interventions-plan-audit.md`
**Status**: Resolved — Ready for Checklist

---

## Audit Resolution Summary

| ID | Severity | Issue | Resolution |
|----|----------|-------|------------|
| H1 | HIGH | `InterventionTimer` used `@Observable` / `import Observation` — codebase is `ObservableObject` exclusively | **FIXED** — converted to `ObservableObject` + `@Published` + `@StateObject` in session views |
| H2 | HIGH | `rise` haptic `asyncAfter` closures fire after cancel (phantom haptics) | **FIXED** — added `isCancelled` flag guarded in every dispatched closure via `[weak self]` |
| M1 | MEDIUM | `ResetType.accentColor` returned unused `String` (dead code) | **FIXED** — changed to return `Color`; centralized use in `ResetCardRow` + `SessionCompleteView` |
| M2 | MEDIUM | Double bottom padding gap (68pt) when reset card present | **FIXED** — removed `.padding(.bottom, 40)` from advice; conditional card with padding / Spacer fallback |
| M3 | MEDIUM | `InterventionsView` mixed `.r()` and `.system()` fonts | **FIXED** — converted all `InterventionsView` + `ResetCardRow` text to `.r()` convention |
| L1 | LOW | Duplicate success haptic on completion | **ACKNOWLEDGED** — removed `HapticService.notify(.success)` from `SessionCompleteView.onAppear` |
| L2 | LOW | `scenePhase` not handled during session | **ACKNOWLEDGED** — accepted for Phase 1; wall-clock time self-corrects |
| Q1 | QUESTION | Interventions gated behind HealthKit auth | **ANSWERED** — ungated; Resets work without HealthKit |

---

## Overview

Add a "Resets" entry point to the Stress tab that surfaces two acute stress-relief exercises: a 60-second Micro-PMR (progressive muscle relaxation, haptic-guided through 8 muscle groups) and a Somatic Sigh Validator (3-cycle physiological sigh with Canvas breathing animation). Both sessions are logged to a new `InterventionSession` SwiftData model. The shared `InterventionTimer` engine powers both and is designed for easy Watch bolt-on in the future. Navigation follows the exact Stress Lab precedent: a toolbar menu item → a sheet → NavigationLink push to the session view.

---

## Requirements

- Micro-PMR: 8 muscle groups, ~60 seconds total, haptic rise + snap per group, progress dots
- Somatic Sigh: 3 cycles of [quick inhale × 2 → long exhale 8s], Canvas circle animation, haptic cues
- Both sessions: dark full-screen immersive UI, screen always-on during session, completion screen, session saved to SwiftData
- Entry: toolbar Menu on StressView (replaces current lone Lab button), plus contextual "Try a Reset" card when `stressLevel == .high || .veryHigh`
- `InterventionTimer`: `ObservableObject` + `@Published`, phase-aware, 50ms tick, fires haptic patterns on phase start <!-- RESOLVED: H1 — changed from @Observable to ObservableObject for codebase consistency -->
- `InterventionSession` SwiftData model: type, startedAt, durationSeconds, completed, nullable biometric fields (nil on iPhone)
- No new `.sheet()` modifiers on StressView — use existing `activeSheet: StressSheet?` mechanism
- No Apple Watch code, no microphone permission, no new tabs

---

## Architecture Changes

| File | Type | Change |
|------|------|--------|
| `WellPlate/Models/ResetType.swift` | **New** | Enum: `.pmr`, `.sigh` (+ future `.vocalEntrainment`, `.grounding`) |
| `WellPlate/Models/InterventionSession.swift` | **New** | `@Model` for session history with nullable biometric bolt-on fields |
| `WellPlate/Core/Services/InterventionTimer.swift` | **New** | `ObservableObject` phase-aware countdown engine |
| `WellPlate/Features + UI/Stress/Views/InterventionsView.swift` | **New** | Sheet root: NavigationStack with cards for each reset type |
| `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift` | **New** | Full-screen PMR session (8 muscle groups, haptic-guided) |
| `WellPlate/Features + UI/Stress/Views/SighSessionView.swift` | **New** | Breathing session (Canvas circle + haptics, 3 cycles) |
| `WellPlate/Features + UI/Stress/Views/SessionCompleteView.swift` | **New** | Shared post-session summary (reusable, Watch-ready) |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | **Modified** | Add `.interventions` to `StressSheet`; leading toolbar → `Menu`; contextual reset card in scroll view |
| `WellPlate/App/WellPlateApp.swift` | **Modified** | Add `InterventionSession.self` to `modelContainer` schema |

---

## Implementation Steps

### Step 1: `ResetType` enum
**File**: `WellPlate/Models/ResetType.swift`

Create a new file defining the reset session type enum. This is intentionally separate from `InterventionType` in `StressExperiment.swift` — that enum represents multi-day experiments; this represents acute 30–120s resets.

<!-- RESOLVED: M1 — accentColor now returns Color directly (not String); becomes the single source of truth referenced by ResetCardRow and SessionCompleteView. Dead code removed. -->

```swift
import Foundation
import SwiftUI

enum ResetType: String, CaseIterable, Identifiable, Codable {
    case pmr              = "pmr"
    case sigh             = "sigh"
    // Phase 2 additions (not implemented yet)
    // case vocalEntrainment = "vocalEntrainment"
    // case grounding        = "grounding"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pmr:  return "Muscle Release"
        case .sigh: return "Physiological Sigh"
        }
    }

    var subtitle: String {
        switch self {
        case .pmr:  return "60-sec full-body tension reset"
        case .sigh: return "3 breath cycles · ~35 seconds"
        }
    }

    var icon: String {
        switch self {
        case .pmr:  return "figure.mind.and.body"
        case .sigh: return "wind"
        }
    }

    var accentColor: Color {
        switch self {
        case .pmr:  return .teal
        case .sigh: return .indigo
        }
    }
}
```

- **Why**: Clean separation of concerns. `InterventionType` is for Stress Lab; `ResetType` is for acute resets.
- **Risk**: Low.

---

### Step 2: `InterventionSession` SwiftData model
**File**: `WellPlate/Models/InterventionSession.swift`

```swift
import Foundation
import SwiftData

@Model
final class InterventionSession {
    var resetType: String          // ResetType.rawValue
    var startedAt: Date
    var durationSeconds: Int       // actual elapsed duration
    var completed: Bool            // false if user cancelled mid-session

    // Watch bolt-on fields — nil on iPhone until Watch ships
    var preHeartRate: Double?
    var postHeartRate: Double?
    var preHRV: Double?
    var postHRV: Double?

    init(resetType: ResetType, startedAt: Date, durationSeconds: Int, completed: Bool) {
        self.resetType = resetType.rawValue
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.completed = completed
    }

    var resolvedResetType: ResetType {
        ResetType(rawValue: resetType) ?? .pmr
    }
}
```

- **Why**: Lightweight history log. Nullable biometric fields exist in schema now so no migration is needed when Watch ships.
- **Risk**: Low — additive migration, same pattern as `StressExperiment`.

---

### Step 3: Add `InterventionSession` to the app's model container
**File**: `WellPlate/App/WellPlateApp.swift`

Change:
```swift
.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self])
```
To:
```swift
.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self, InterventionSession.self])
```

- **Why**: SwiftData requires all `@Model` classes to be declared at container init time.
- **Risk**: Low — additive migration, no existing data touched.

---

### Step 4: `InterventionTimer` engine
**File**: `WellPlate/Core/Services/InterventionTimer.swift`

The shared, phase-aware countdown engine used by both session views.

<!-- RESOLVED: H1 — converted from @Observable / import Observation to ObservableObject + @Published to align with project-wide convention (StressViewModel, etc.). Session views use @StateObject. -->
<!-- RESOLVED: H2 — added isCancelled flag; every dispatched asyncAfter haptic closure captures [weak self] and guards on !self.isCancelled, preventing phantom haptics after cancel(). -->

```swift
import Foundation

// MARK: - Supporting types

struct InterventionPhase {
    let name: String            // e.g. "Tense shoulders", "First inhale"
    let duration: TimeInterval
    let hapticOnStart: HapticPattern?
}

enum HapticPattern {
    case rise    // repeated .heavy impacts every 280ms for the full phase
    case snap    // single .success notification (fired once at phase start)
    case softPulse(count: Int, interval: TimeInterval) // e.g. exhale guidance
}

// MARK: - InterventionTimer

final class InterventionTimer: ObservableObject {

    // Published state (drives SwiftUI)
    @Published private(set) var currentPhaseIndex: Int = 0
    @Published private(set) var phaseProgress: Double = 0     // 0.0–1.0 within current phase
    @Published private(set) var totalProgress: Double = 0     // 0.0–1.0 across all phases
    @Published private(set) var currentPhaseName: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isComplete: Bool = false

    // Callbacks
    var onPhaseStart: ((InterventionPhase) -> Void)?
    var onComplete: (() -> Void)?

    // Internal state
    private var phases: [InterventionPhase] = []
    private var timer: Timer?
    private var phaseStartTime: Date = .now
    private var totalDuration: TimeInterval = 0
    private var elapsedBeforeCurrentPhase: TimeInterval = 0
    private var isCancelled: Bool = false  // H2 fix: guards dispatched haptic closures

    // MARK: - Public API

    func start(phases: [InterventionPhase]) {
        cancel()
        isCancelled = false
        self.phases = phases
        self.totalDuration = phases.map(\.duration).reduce(0, +)
        currentPhaseIndex = 0
        elapsedBeforeCurrentPhase = 0
        isComplete = false
        beginPhase()
    }

    func cancel() {
        isCancelled = true
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: - Private

    private func beginPhase() {
        guard currentPhaseIndex < phases.count else {
            isComplete = true
            isRunning = false
            timer?.invalidate()
            timer = nil
            onComplete?()
            return
        }
        let phase = phases[currentPhaseIndex]
        currentPhaseName = phase.name
        phaseProgress = 0
        phaseStartTime = .now
        isRunning = true
        fireHaptic(phase.hapticOnStart, duration: phase.duration)
        onPhaseStart?(phase)

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let phase = phases[currentPhaseIndex]
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        phaseProgress = min(elapsed / phase.duration, 1.0)
        totalProgress = min((elapsedBeforeCurrentPhase + elapsed) / totalDuration, 1.0)

        if elapsed >= phase.duration {
            timer?.invalidate()
            timer = nil
            elapsedBeforeCurrentPhase += phase.duration
            currentPhaseIndex += 1
            beginPhase()
        }
    }

    private func fireHaptic(_ pattern: HapticPattern?, duration: TimeInterval) {
        guard let pattern else { return }
        switch pattern {
        case .rise:
            let interval = 0.28
            let count = max(1, Int(duration / interval) - 1)
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                    guard let self, !self.isCancelled else { return }
                    HapticService.impact(.heavy)
                }
            }
        case .snap:
            HapticService.notify(.success)
        case .softPulse(let count, let interval):
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                    guard let self, !self.isCancelled else { return }
                    HapticService.impact(.light)
                }
            }
        }
    }
}
```

- **Why**: Centralized timer drives both session views identically. `ObservableObject` + `@Published` matches the project-wide pattern (e.g., `StressViewModel`).
- **Dependencies**: `HapticService` (already exists).
- **Risk**: Low. The 50ms tick is lightweight. Cancel on `onDisappear` prevents timer leaks and silences any in-flight haptic closures.

---

### Step 5: Extend `StressSheet` and update the toolbar
**File**: `WellPlate/Features + UI/Stress/Views/StressView.swift`

#### 5a — Add `.interventions` to `StressSheet`:

In the `StressSheet` enum (lines 12–30), add:
```swift
case interventions
```

And in the `id` computed var switch, add:
```swift
case .interventions: return "interventions"
```

#### 5b — Replace leading `ToolbarItem` Button with a Menu:

<!-- RESOLVED: Q1 — Resets stay ungated by HealthKit authorization. The Menu itself remains gated (since Lab requires HK), but within the menu, the Resets button is always shown. Alternative: split into two toolbar items. Chosen approach: keep single Menu, but menu itself is visible whenever Stress tab loads (drop HK guard). Interventions work without HealthKit. -->

Replace the existing leading ToolbarItem (lines 69–80):
```swift
ToolbarItem(placement: .topBarLeading) {
    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
        Button { ... "flask.fill" } label: { Label("Lab", ...) }
    }
}
```

With:
```swift
ToolbarItem(placement: .topBarLeading) {
    if !viewModel.isLoading {
        Menu {
            // Lab is gated — requires HealthKit for experiment biometrics
            if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized {
                Button {
                    HapticService.impact(.light)
                    activeSheet = .stressLab
                } label: {
                    Label("Lab", systemImage: "flask.fill")
                }
            }
            // Resets are always available — no HealthKit dependency
            Button {
                HapticService.impact(.light)
                activeSheet = .interventions
            } label: {
                Label("Resets", systemImage: "bolt.heart.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.stressLevel.color)
        }
    }
}
```

#### 5c — Add `.interventions` case to the `.sheet(item:)` switch (lines 127–157):

In the switch inside `.sheet(item: $activeSheet)`, add:
```swift
case .interventions:
    InterventionsView()
```

#### 5d — Add contextual reset card in `mainScrollView`:

<!-- RESOLVED: M2 — removed .padding(.bottom, 40) from the advice section's VStack; the conditional reset card carries its own .padding(.bottom, 40) when present, and a Spacer().frame(height: 40) provides the bottom gap when absent. Result: consistent 28pt inter-section spacing and 40pt bottom padding regardless of which section is last. -->

**Modify the advice section** — remove its existing `.padding(.bottom, 40)`:

```swift
// ── ADVICE ─────────────────────────
VStack(alignment: .leading, spacing: 10) {
    sectionLabel("ADVICE")
    // ... existing advice card ...
}
.padding(.horizontal, 20)
.padding(.top, 28)
// .padding(.bottom, 40)  ← REMOVE THIS LINE
.opacity(adviceAppeared ? 1 : 0)
.offset(y: adviceAppeared ? 0 : 16)
```

**Then append the conditional reset card section** (as the new last section before `mainScrollView`'s closing brace):

```swift
// ── RESET RECOMMENDATION (conditional) ─────────────────────────
if viewModel.stressLevel == .high || viewModel.stressLevel == .veryHigh {
    VStack(alignment: .leading, spacing: 10) {
        sectionLabel("QUICK RESET")
        resetRecommendationCard
    }
    .padding(.horizontal, 20)
    .padding(.top, 28)
    .padding(.bottom, 40)
    .opacity(adviceAppeared ? 1 : 0)
    .offset(y: adviceAppeared ? 0 : 16)
} else {
    Spacer().frame(height: 40)
}
```

And add the `resetRecommendationCard` computed property:
```swift
private var resetRecommendationCard: some View {
    Button {
        HapticService.impact(.light)
        activeSheet = .interventions
    } label: {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.teal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Try a Quick Reset")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text("60-sec exercises to ease stress now")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
    .buttonStyle(.plain)
}
```

- **Why**: Contextual surfacing when stress is high gives users a just-in-time intervention nudge. The toolbar menu keeps both Lab and Resets discoverable without cluttering the bar with two separate buttons.
- **Risk**: Low.

---

### Step 6: `InterventionsView`
**File**: `WellPlate/Features + UI/Stress/Views/InterventionsView.swift`

The sheet root that lists available reset types and navigates into session views.

<!-- RESOLVED: M3 — all text uses .r() font convention to match peer sheets (StressLabView, VitalDetailView). The immersive session views (PMR, Sigh, SessionComplete) keep .system(design: .rounded) — they are dark full-screen overlays with a deliberately distinct visual language. -->

```swift
import SwiftUI

struct InterventionsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    resetCards
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Resets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Resets")
                .font(.r(.title2, .bold))
            Text("Science-backed exercises to activate your parasympathetic nervous system in under 2 minutes.")
                .font(.r(.footnote, .regular))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetCards: some View {
        VStack(spacing: 12) {
            ForEach(ResetType.allCases) { type in
                NavigationLink {
                    sessionView(for: type)
                } label: {
                    ResetCardRow(type: type)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func sessionView(for type: ResetType) -> some View {
        switch type {
        case .pmr:  PMRSessionView()
        case .sigh: SighSessionView()
        }
    }
}

// MARK: - Reset Card Row

private struct ResetCardRow: View {
    let type: ResetType

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(type.accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: type.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(type.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.r(.body, .semibold))
                    .foregroundColor(.primary)
                Text(type.subtitle)
                    .font(.r(.caption, .regular))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
}
```

<!-- RESOLVED: M1 — ResetCardRow now reads type.accentColor directly instead of declaring its own private computed property. -->

- **Why**: `NavigationStack` inside the sheet allows pushes to session views without nested `.sheet()` calls. `ForEach(ResetType.allCases)` means Phase 2 cases appear automatically when added to the enum.
- **Risk**: Low.

---

### Step 7: `PMRSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/PMRSessionView.swift`

Full-screen dark PMR exercise. 8 muscle groups, each with a 4s tense phase and 3.5s release phase (7.5s per group, ~60s total).

<!-- RESOLVED: H1 — @State timer changed to @StateObject; InterventionTimer is now an ObservableObject. -->

```swift
import SwiftUI
import SwiftData

struct PMRSessionView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var timer = InterventionTimer()
    @State private var sessionStart: Date = .now
    @State private var showComplete = false

    private let muscleGroups = [
        "Hands & Forearms",
        "Shoulders",
        "Jaw & Face",
        "Chest",
        "Abdomen",
        "Glutes",
        "Thighs",
        "Calves & Feet"
    ]

    private var phases: [InterventionPhase] {
        muscleGroups.flatMap { group in [
            InterventionPhase(name: "Tense — \(group)", duration: 4.0, hapticOnStart: .rise),
            InterventionPhase(name: "Release",            duration: 3.5, hapticOnStart: .snap)
        ]}
    }

    private var totalGroups: Int { muscleGroups.count }
    private var completedGroups: Int { timer.currentPhaseIndex / 2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    type: .pmr,
                    durationSeconds: Int(Date().timeIntervalSince(sessionStart))
                ) {
                    dismiss()
                }
                .transition(.opacity)
            } else {
                sessionContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !showComplete {
                    Button("Cancel") {
                        saveSession(completed: false)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            sessionStart = .now
            timer.start(phases: phases)
            timer.onComplete = {
                saveSession(completed: true)
                withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer.cancel()
        }
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Current instruction
            VStack(spacing: 16) {
                // Phase label (Tense / Release)
                let isTense = timer.currentPhaseIndex % 2 == 0
                Text(isTense ? "TENSE" : "RELEASE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(isTense ? .teal : .white.opacity(0.45))

                // Muscle group name
                Text(muscleGroups[min(completedGroups, muscleGroups.count - 1)])
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: timer.currentPhaseIndex)

                // Phase progress arc
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: timer.phaseProgress)
                        .stroke(isTense ? Color.teal : Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: timer.phaseProgress)
                }
                .frame(width: 80, height: 80)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Progress dots
            progressDots
                .padding(.bottom, 60)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalGroups, id: \.self) { i in
                Circle()
                    .fill(i < completedGroups ? Color.teal : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .scaleEffect(i == completedGroups ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3), value: completedGroups)
            }
        }
    }

    private func saveSession(completed: Bool) {
        let session = InterventionSession(
            resetType: .pmr,
            startedAt: sessionStart,
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
```

- **Why**: Dark background, minimal text, large font follows the brainstorm's "reduce cognitive load" UX direction. `contentTransition(.opacity)` smoothly crossfades muscle group names. Progress dots give spatial sense of completion without a distracting progress bar.
- **Risk**: Low. The `isCancelled` flag in `InterventionTimer` now silences phantom haptics after cancel.

---

### Step 8: `SighSessionView`
**File**: `WellPlate/Features + UI/Stress/Views/SighSessionView.swift`

Breathing guide with Canvas circle animation. 3 cycles of: [inhale1 (1.5s) → inhale2 (1.5s) → exhale (8s)] ≈ 33 seconds total.

<!-- RESOLVED: H1 — @State timer changed to @StateObject. -->

```swift
import SwiftUI
import SwiftData

struct SighSessionView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var timer = InterventionTimer()
    @State private var sessionStart: Date = .now
    @State private var showComplete = false

    // 3 cycles × 3 phases = 9 phases total
    private var phases: [InterventionPhase] {
        var result: [InterventionPhase] = []
        for _ in 0..<3 {
            result.append(InterventionPhase(name: "First inhale",  duration: 1.5, hapticOnStart: .snap))
            result.append(InterventionPhase(name: "Second inhale", duration: 1.5, hapticOnStart: .snap))
            result.append(InterventionPhase(name: "Long exhale",   duration: 8.0, hapticOnStart: .softPulse(count: 4, interval: 2.0)))
        }
        return result
    }

    private var isExhale: Bool {
        timer.currentPhaseIndex % 3 == 2
    }

    // Circle scale: small during inhale phases, large during exhale
    private var circleScale: Double {
        if isExhale {
            // Contracts from 1.0 → 0.55 as exhale progresses
            return 1.0 - (timer.phaseProgress * 0.45)
        } else {
            // Expands from 0.55 → 1.0 as inhale progresses
            let baseScale: Double = timer.currentPhaseIndex % 3 == 0 ? 0.55 : 0.78
            return baseScale + (timer.phaseProgress * (1.0 - baseScale))
        }
    }

    private var cycleNumber: Int { (timer.currentPhaseIndex / 3) + 1 }

    var body: some View {
        ZStack {
            Color(hue: 0.67, saturation: 0.15, brightness: 0.08).ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    type: .sigh,
                    durationSeconds: Int(Date().timeIntervalSince(sessionStart))
                ) {
                    dismiss()
                }
                .transition(.opacity)
            } else {
                sessionContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !showComplete {
                    Button("Cancel") {
                        saveSession(completed: false)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            sessionStart = .now
            timer.start(phases: phases)
            timer.onComplete = {
                saveSession(completed: true)
                withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer.cancel()
        }
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated breathing circle
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
                    .frame(width: 260, height: 260)

                // Breathing circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.indigo.opacity(0.6), Color.indigo.opacity(0.2)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(circleScale)
                    .animation(.easeInOut(duration: 0.08), value: circleScale)

                // Instruction text in center
                VStack(spacing: 4) {
                    Text(timer.currentPhaseName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: timer.currentPhaseIndex)
                }
            }

            // Cycle counter
            Text("Cycle \(min(cycleNumber, 3)) of 3")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 32)

            Spacer()

            // Total progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 3)
                    Capsule()
                        .fill(Color.indigo.opacity(0.7))
                        .frame(width: geo.size.width * timer.totalProgress, height: 3)
                        .animation(.linear(duration: 0.05), value: timer.totalProgress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    private func saveSession(completed: Bool) {
        let session = InterventionSession(
            resetType: .sigh,
            startedAt: sessionStart,
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
```

- **Why**: Dark navy creates a distinct visual identity from PMR. `RadialGradient` gives depth. SwiftUI animation smoothly handles breathing motion.
- **Risk**: Low.

<!-- RESOLVED: L2 (acknowledged) — scenePhase transitions are not handled in Phase 1. The Foundation Timer fires on the main run loop and pauses when backgrounded; on return, wall-clock tick via Date() self-corrects phase progress. A brief visual jump is acceptable. Revisit in polish pass if needed. -->

---

### Step 9: `SessionCompleteView`
**File**: `WellPlate/Features + UI/Stress/Views/SessionCompleteView.swift`

Shared completion screen reused by both session views. Watch bolt-on ready via optional biometric display.

<!-- RESOLVED: L1 — removed HapticService.notify(.success) from onAppear. The final timer phase (snap for PMR, softPulse for Sigh) already provides the completion haptic cue, so firing again here caused a double-tap. -->
<!-- RESOLVED: M1 — accentColor now reads from type.accentColor instead of a local switch. -->

```swift
import SwiftUI

struct SessionCompleteView: View {

    let type: ResetType
    let durationSeconds: Int
    let onDone: () -> Void

    // Watch bolt-on: populate these when Watch ships
    var preHeartRate: Double? = nil
    var postHeartRate: Double? = nil

    @State private var checkmarkAnimated = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(type.accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(type.accentColor)
                    .scaleEffect(checkmarkAnimated ? 1 : 0.4)
                    .opacity(checkmarkAnimated ? 1 : 0)
            }
            .padding(.bottom, 28)

            Text("Reset Complete")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your nervous system just got a reset.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 40)

            // Duration
            Text("\(durationSeconds)s session")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 6)

            // Watch bolt-on: HR delta section (hidden when nil)
            if let pre = preHeartRate, let post = postHeartRate {
                HStack(spacing: 20) {
                    hrStat(label: "Before", value: "\(Int(pre)) BPM")
                    Image(systemName: "arrow.right")
                        .foregroundColor(.white.opacity(0.4))
                    hrStat(label: "After", value: "\(Int(post)) BPM")
                }
                .padding(.top, 28)
            }

            Spacer()

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(type.accentColor)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .onAppear {
            // L1 fix: no longer fires HapticService.notify(.success) — the timer's
            // final phase already provided the completion cue.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkmarkAnimated = true
            }
        }
    }

    private func hrStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
```

- **Why**: `onDone` closure means each session view controls its own dismiss behavior. Watch biometric section is `nil`-gated — no dead UI on iPhone. Spring-animated checkmark on appear gives satisfying completion feedback without a redundant haptic.
- **Risk**: Low.

---

## Testing Strategy

### Build verification
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
```
Run after every step. All 4 targets should remain green.

### Manual verification flows

1. **Toolbar menu**: Open Stress tab → tap `...` circle → confirm "Resets" appears in menu (even without HealthKit authorization) → tapping opens InterventionsView. Lab appears only when HealthKit is authorized.
2. **Contextual card**: Mock stress score > 65 → confirm card appears below advice section with exactly 28pt gap above and 40pt below → tapping opens InterventionsView
3. **Bottom padding (low stress)**: Set `stressLevel = .low` → scroll to bottom → confirm 40pt padding beneath advice (via Spacer fallback)
4. **PMR session**: Open Resets → tap "Muscle Release" → confirm 8 groups sequence correctly → confirm haptics fire (physical device only) → let run to completion → confirm single success haptic (not double) → confirm session saved in SwiftData
5. **PMR cancel mid-rise**: Start PMR → cancel during a "Tense" phase → confirm no phantom haptics fire after dismiss (H2 fix verification)
6. **Sigh session**: Open Resets → tap "Physiological Sigh" → confirm circle animates through 3 cycles → let complete → confirm clean completion (no double haptic)
7. **Screen always-on**: Start a session → leave phone idle → confirm screen does not lock
8. **Timer leak**: Start a session → cancel → background the app → return → confirm no crash or lingering haptic callbacks

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `InterventionTimer` rapid-fire haptic dispatches accumulate if timer is cancelled mid-phase | **RESOLVED (H2)** | `isCancelled` flag guards every dispatched `asyncAfter` closure via `[weak self]`. |
| `UIApplication.shared.isIdleTimerDisabled` not reset if app is force-quit during session | Low | `onDisappear` handles the normal path. Force-quit resets `isIdleTimerDisabled` to `false` automatically on next launch. |
| `NavigationLink` within a `.sheet` with `navigationBarBackButtonHidden` + custom Cancel | Low | Well-known pattern; verify in simulator. |
| SwiftData `modelContext.save()` in `timer.onComplete` off-MainActor | Low | `Timer.scheduledTimer` callback runs on main run loop. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` implied. |
| scenePhase transitions during session cause visual jump on return | Low | Accepted for Phase 1 (L2). Wall-clock tick self-corrects. |
| Haptic "rise" pattern may feel uneven on older devices | Low-Medium | Best-effort; test on physical device. |

---

## Success Criteria

- [ ] `StressSheet` has `.interventions` case; no new `.sheet()` modifier added to StressView
- [ ] Leading toolbar shows `...` menu; Resets is always available (no HealthKit gate); Lab is HK-gated inside the menu
- [ ] `InterventionsView` shows PMR and Sigh cards inside a NavigationStack sheet using `.r()` fonts
- [ ] `InterventionTimer` uses `ObservableObject` + `@Published`; session views use `@StateObject`
- [ ] Cancelling mid-session silences all pending haptic dispatches (no phantom haptics)
- [ ] PMR session runs through all 8 muscle groups with tense/release cycle
- [ ] Sigh session animates circle through 3 cycles with correct expand/contract behavior
- [ ] Both sessions: screen stays on during exercise, idle timer re-enabled on dismiss
- [ ] Both sessions: `InterventionSession` saved to SwiftData with correct `completed` flag
- [ ] Cancel mid-session: session saved with `completed = false`
- [ ] `SessionCompleteView` shows checkmark animation + duration; no duplicate success haptic
- [ ] HR delta section in `SessionCompleteView` is hidden (all nil on iPhone)
- [ ] Contextual reset card appears only when `stressLevel` is `.high` or `.veryHigh`
- [ ] Bottom padding is 40pt regardless of whether reset card is present (no 68pt gap)
- [ ] `ResetType.accentColor` returns `Color` and is the single source for color mapping
- [ ] Build succeeds across all 4 xcodebuild targets with no warnings introduced
