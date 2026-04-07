# Strategy: Stress Lab (n-of-1 Experiments)

**Date**: 2026-04-02
**Source**: `Docs/01_Brainstorming/260402-feature-prioritization-from-deep-research-brainstorm.md` (Feature 1A)
**Status**: Ready for Planning

---

## Chosen Approach

**SwiftData-persisted experiment model + on-device paired comparison analysis, surfaced as a new "Lab" section inside `StressView`.**

The user creates a micro-intervention experiment (e.g. "No caffeine after 2pm") with a start date and a 7 or 14-day duration. The app silently tracks `StressReading` averages across the experiment window and compares them against the 7-day baseline *before* the experiment began. Results are presented as an average score delta, a simple bootstrap confidence interval (non-parametric, on-device), and a plain-language summary card. Entry is via a new `StressLabView` sheet accessible from a "Lab" button in `StressView`'s toolbar.

---

## Rationale

- **Why SwiftData persistence over ephemeral state**: Experiments run for 7–14 days, spanning many app sessions. The model must survive app restarts, background kills, and iOS updates. A `@Model` class for `StressExperiment` is the natural fit with the existing stack.
- **Why `StressReading` as the metric source**: It is already the canonical stress persistence layer — saved automatically every time the score refreshes, covering every day the user opens the app. No new data collection pipeline needed.
- **Why a toolbar "Lab" button in `StressView` over a new tab**: Adding a 5th tab breaks the existing 4-tab layout and `MainTabView`'s `Tab(value:)` structure. A sheet/full-screen cover from the Stress tab is consistent with how `StressInsightService` results are already shown (`showInsights` sheet). The Lab stays contextually anchored to stress, which is correct since the output metric is always the stress score.
- **Why paired comparison (before vs. during) over correlation**: The brainstorm explicitly flags that Bearable gets criticised for "misleading correlations." A paired before/after design is honest — it says "your stress was X before, Y during" without implying causation. The statistical framing (delta + confidence interval + "this doesn't prove causation") is the product's trust differentiator.
- **Why bootstrap CI over t-test**: `StressReading` values are bounded (0–100), often non-normally distributed, and sample sizes are small (7–14 daily averages). Bootstrap is assumption-free, explainable, and trivial to implement without any math library dependency.

---

## Affected Files & Components

**New files:**
- `WellPlate/Models/StressExperiment.swift` — `@Model` class persisting the experiment definition and result cache
- `WellPlate/Features + UI/Stress/Views/StressLabView.swift` — main Lab screen: active experiment card + past experiments list + create button
- `WellPlate/Features + UI/Stress/Views/StressLabCreateView.swift` — sheet for creating a new experiment (name, hypothesis, intervention type, duration)
- `WellPlate/Features + UI/Stress/Views/StressLabResultView.swift` — result detail: score delta, confidence band, day-by-day sparkline, plain-language summary
- `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` — pure `struct` computing baseline avg, experiment avg, delta, and 1000-iteration bootstrap CI from `[StressReading]`

**Edited files:**
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add `@State private var showStressLab = false` and a "Lab" toolbar button (beaker SF Symbol) that sets it; add `.sheet(isPresented: $showStressLab)` presenting `StressLabView`
- `WellPlate/WellPlateApp.swift` — add `StressExperiment` to the `ModelContainer` schema

---

## Architectural Direction

```
StressView
  └── toolbar "Lab" button → showStressLab = true
        └── .sheet → StressLabView
              ├── Active experiment card (in-progress status, days remaining)
              ├── Past experiments list (tappable → StressLabResultView)
              └── "New Experiment" button → StressLabCreateView (sheet)
                    └── on save → insert StressExperiment into modelContext

StressLabAnalyzer (pure struct, no SwiftData)
  ├── input: baseline [StressReading] (7 days before start)
  ├── input: experiment [StressReading] (start...end window)
  └── output: StressLabResult { baselineAvg, experimentAvg, delta, ciLow, ciHigh, confidence }

StressExperiment (@Model)
  ├── name: String
  ├── hypothesis: String?
  ├── interventionType: String  (raw value of InterventionType enum)
  ├── startDate: Date
  ├── durationDays: Int  (7 or 14)
  ├── cachedDelta: Double?       (computed lazily, stored for list display)
  ├── cachedCILow: Double?
  ├── cachedCIHigh: Double?
  └── completedAt: Date?         (nil = in progress)
```

`StressLabAnalyzer` is called from `StressLabResultView.onAppear` and from `StressLabView` (to populate the active card). It reads `StressReading` directly from the passed arrays — it never touches SwiftData itself. The caller fetches the readings and passes them in, keeping the analyzer pure and testable.

`InterventionType` is a `String`-backed enum defining preset categories: `.caffeine`, `.screenCurfew`, `.sleep`, `.exercise`, `.diet`, `.custom`. This drives the icon and suggested hypothesis text in `StressLabCreateView`.

---

## Data Model: `StressExperiment`

```swift
@Model final class StressExperiment {
    var name: String
    var hypothesis: String?
    var interventionType: String   // InterventionType.rawValue
    var startDate: Date
    var durationDays: Int          // 7 or 14
    var cachedDelta: Double?
    var cachedCILow: Double?
    var cachedCIHigh: Double?
    var completedAt: Date?
    var createdAt: Date
}
```

Adding `StressExperiment` to the `ModelContainer` schema is a **non-destructive migration** — SwiftData adds the new table without touching existing data.

---

## Design Constraints

- Follow `StressView` color scheme: stress-level-adaptive background (`levelBackground`), `AppColors.brand` for interactive elements
- Use `.r()` font extension and `.appShadow(radius:y:)` — no system fonts or manual shadows
- `StressLabView` presented as `.sheet` with `.presentationDetents([.large])` — consistent with existing `showInsights` sheet pattern
- `StressLabCreateView` is a sub-sheet from within `StressLabView` — use a secondary `.sheet(isPresented:)` on the `StressLabView` body
- `StressLabAnalyzer` must be a `@MainActor`-free pure `struct` callable from any context
- Bootstrap loop (1000 iterations) runs on a background `Task` in `StressLabResultView` to avoid blocking the main thread — results published via `@State`
- Minimum data requirement: at least 3 daily readings in the baseline window AND 3 in the experiment window — show "Not enough data yet" otherwise
- Strictly avoid causal language: use "your stress was X on average" not "the intervention reduced stress"
- `StressExperiment` added to `ModelContainer` in `WellPlateApp.swift` — **no** schema version bump needed (SwiftData handles additive migrations automatically)

---

## Non-Goals

- No push notifications when an experiment completes
- No experiment suggestions based on the data (user always chooses their own intervention)
- No multi-metric experiments (stress score only — no calories, steps, or sleep as primary outcome)
- No sharing or export of experiment results in this iteration (that's a Pro-tier extension)
- No confound detection or multi-factor regression (the UI acknowledges confounders exist, but doesn't model them)
- No HealthKit write-back of experiment results
- No iCloud sync of `StressExperiment` data (local SwiftData only)

---

## Open Risks

- **Risk**: Bootstrap on the main thread blocks UI — **Mitigation**: run bootstrap in a detached `Task` from `StressLabResultView.task { }`, publish result back to `@State`
- **Risk**: `StressReading` gaps (user doesn't open app for days) produces sparse baseline — **Mitigation**: display "X of 7 days have data" alongside the result; enforce minimum 3-reading floor
- **Risk**: Schema migration on `WellPlateApp.swift` if `StressExperiment` model is malformed — **Mitigation**: full build test on first insertion into schema; SwiftData additive migrations are reliable for new tables
- **Risk**: UX complexity — creating an experiment, waiting 7 days, reading a result card is a long loop — **Mitigation**: "Days remaining" countdown on the active experiment card makes progress tangible; past experiments are always visible in the list
