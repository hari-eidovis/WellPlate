# Strategy: F3. Circadian Stack

**Date**: 2026-04-07
**Source**: `Docs/01_Brainstorming/260407-circadian-stack-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Two-Signal Circadian Score Card** — Compute a Circadian Score (0–100) from sleep timing regularity (SRI over 7 nights) + daylight exposure (`timeInDaylight`). Show as a dedicated card in the insights sheet alongside the existing stress factors. Degrade gracefully to a regularity-only score when Apple Watch daylight data is absent.

---

## Rationale

- **Approach 1 (Two-Signal) over Approach 2 (Three-Signal)**: The third signal (nighttime screen time) can't be directly measured from ScreenTimeManager — only total daily hours exist, not per-hour data. Using sleep onset deviation as a proxy is an assumption, not a measurement. Approach 1 is honest and self-contained.

- **Over Approach 3 (Separate Tab/View)**: A new tab or full-screen view is premature for a metric whose user value isn't proven. A card in the existing insights sheet validates the concept before investing in a full surface.

- **Over Approach 4 (Augment Sleep Factor)**: Folding circadian into the sleep stress factor hides the concept entirely and loses the daylight exposure signal. A separate card lets users see and understand circadian health as a distinct axis.

- **Placement in insights sheet** (not main scroll): The main StressView scroll shows score → today's pattern → week bar → suggestion → quick reset. These are action-oriented. Circadian Score is an insight — it fits alongside vitals grid and stress factors in the insights sheet. This also means minimal disruption to the primary UX.

---

## Affected Files & Components

### New Files (3)

| File | Purpose |
|---|---|
| `WellPlate/Core/Services/CircadianService.swift` | Stateless scoring: compute SRI from `[DailySleepSummary]`, daylight score from `[DailyMetricSample]`, composite score, and pick actionable tip |
| `WellPlate/Features + UI/Stress/Views/CircadianCardView.swift` | Card UI: composite score ring/badge + sub-component breakdown + tip string |
| `WellPlate/Features + UI/Stress/Views/CircadianDetailView.swift` | Tappable detail sheet: 7-day regularity chart (bed/wake bars), daylight trend, tips |

### Modified Files (6)

| File | Change |
|---|---|
| `WellPlate/Models/HealthModels.swift` | Add `bedtime: Date?` and `wakeTime: Date?` to `DailySleepSummary` |
| `WellPlate/Core/Services/HealthKitService.swift` | Track min(startDate) / max(endDate) in `fetchDailySleepSummaries`; add `fetchDaylight(for:)` method; add `.timeInDaylight` to `readTypes` |
| `WellPlate/Core/Services/HealthKitServiceProtocol.swift` | Add `fetchDaylight(for:)` to protocol |
| `WellPlate/Core/Services/MockHealthKitService.swift` | Implement `fetchDaylight(for:)` with mock data; update mock sleep summaries to include bedtime/wakeTime |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | Add `circadianScore`, `circadianTip`, `daylightHistory` published properties; call `CircadianService` in `loadData()` |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Add `.circadian` case to `StressSheet`; add `CircadianCardView` to insights sheet; wire detail sheet |

### Possibly Affected (verify at plan stage)

| File | Risk |
|---|---|
| `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift` | Uses `DailySleepSummary` — new optional fields won't break it, but verify |
| `WellPlate/Features + UI/Stress/Views/StressImmersiveView.swift` | If immersive view mirrors the insights sheet, may need Circadian card too |
| `WellPlate/Resources/MockData/StressMockSnapshot.swift` (or similar) | Mock sleep data needs bedtime/wakeTime values |

---

## Architectural Direction

### Follows existing patterns exactly

- **`CircadianService`** mirrors `StressScoring` — pure, stateless `enum` with `static func` methods. No side effects, no HealthKit/SwiftData dependencies. Takes pre-fetched data as arguments.

- **`CircadianCardView`** is a self-contained SwiftUI view, like `StressFactorCardView`. Takes a score, sub-scores, and a tip string — no view model reference, no service calls.

- **`CircadianDetailView`** follows the established pattern of `ExerciseDetailView`, `SleepDetailView`, etc. — receives data arrays from the view model, renders charts. Presented via `StressSheet.circadian`.

- **HealthKit fetch** follows the `fetchDailyAvg` pattern already in `HealthKitService` for `timeInDaylight`. Returns `[DailyMetricSample]` — reuses the existing model.

- **StressViewModel integration** — add published properties and a private helper method called from `loadData()` (matching the `async let` pattern with private helpers). Circadian score does NOT feed into `totalScore` — it's informational only.

### Key architectural decision: Circadian is NOT a stress factor

The 4 stress factors (exercise, sleep, diet, screen time) each contribute 0–25 to the 100-point composite stress score. **Circadian Score is a separate axis** — it appears alongside factors in the insights sheet but does not alter the stress total. Reasons:

1. Adding a 5th factor to the 0–100 scale changes the scoring semantics for all existing users
2. Circadian overlaps conceptually with sleep (regularity) — double-counting risk
3. Informational-only positioning lets us validate the feature before committing to scoring integration

---

## Design Constraints

1. **`DailySleepSummary` changes must be additive** — new properties are optional (`Date?`). No existing call sites break.
2. **SRI requires ≥ 5 nights in 7 days** — if insufficient data, show an explicit "Not enough data" state, never a misleading score.
3. **Daylight component is fully optional** — if `timeInDaylight` returns zero samples (no Watch, denied auth), score uses SRI alone. UI shows "Add Apple Watch for daylight data" note.
4. **No new HealthKit authorization prompt** — add `.timeInDaylight` to the existing `readTypes` set. Authorization is requested once at StressView entry. If the user previously denied daylight, we get zero samples and degrade gracefully.
5. **One `.sheet(item:)` rule** — add `.circadian` to `StressSheet` enum. Do not add a second `.sheet()` modifier.
6. **Mock mode** — `MockHealthKitService.fetchDaylight(for:)` must return deterministic data. Mock sleep summaries need realistic bedtime/wakeTime values.
7. **Tip selection is deterministic** — `CircadianService` picks the tip based on the lowest sub-score. No LLM or Foundation Models call.

---

## Non-Goals

- **Circadian Score in the main scroll view** — insights sheet only for MVP
- **Circadian Score feeding into composite stress score** — informational only
- **Nighttime screen time signal** — not measurable from current ScreenTimeManager; omitted
- **Night shift / irregular schedule override** — acknowledged edge case, but no special handling in MVP
- **7-day trend chart in CircadianDetailView** — if it pushes scope beyond 1.5 weeks, ship card-only first and add detail view in a follow-up

---

## Open Risks

1. **`timeInDaylight` data sparsity** — Most users without Apple Watch get zero data. The 1-signal fallback (SRI only) must feel complete, not broken. *Mitigation*: Design the card so the daylight component is a "bonus" row, not a missing half.

2. **Sleep sample timestamp noise** — If a user takes off their Watch mid-sleep, samples may have gaps that skew bedtime/wakeTime inference. *Mitigation*: Use min(startDate) of samples ≥ 3 hours total for a given night session (ignore short naps).

3. **Model change ripple effects** — Adding `bedtime`/`wakeTime` to `DailySleepSummary` touches a shared model used by SleepViewModel, SleepView, SleepDetailView, SleepChartView. *Mitigation*: Properties are optional with nil defaults; no existing code uses them. Verify at plan stage.
