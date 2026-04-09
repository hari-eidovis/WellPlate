# Implementation Plan: Stress View Feature

## Overview
Replace the current `StressPlaceholderView` with a fully functional Stress tab that computes a 0–100 stress score from four data sources: exercise (HealthKit), sleep (HealthKit), healthy diet (SwiftData food logs), and screen time (manual input via UserDefaults for MVP). Each factor contributes 0–25 points; missing data defaults to 12.5 (neutral). The view shows the overall score, a per-factor breakdown, and smart wellness tips.

---

## Requirements

- Display a stress score out of 100 (0 = no stress, 100 = max stress)
- Four equal-weight factors (25 pts each):
  - **Exercise**: steps + active energy from HealthKit today
  - **Sleep**: last night's sleep hours + deep sleep ratio from HealthKit
  - **Diet**: macro balance ratio from SwiftData today (protein & fiber vs. excess fat & carbs)
  - **Screen Time**: daily phone usage hours — manual input for MVP
- No minimum data required; missing data → 12.5 (neutral) per factor
- Full dark/light mode support
- Follows existing MVVM + `@MainActor` + `ObservableObject` pattern
- Reuses existing `HealthKitService`, `FoodLogEntry`, `AppColors`, card/font system

---

## Architecture Changes

| Type           | Path                                                    | Action                                          |
| -------------- | ------------------------------------------------------- | ----------------------------------------------- |
| New model file | `Models/StressModels.swift`                             | `StressLevel` enum, `StressFactorResult` struct |
| New ViewModel  | `Features + UI/Stress/ViewModels/StressViewModel.swift` | Score engine + state                            |
| New View       | `Features + UI/Stress/Views/StressView.swift`           | Main tab view                                   |
| New View       | `Features + UI/Stress/Views/StressScoreGaugeView.swift` | Animated arc gauge                              |
| New View       | `Features + UI/Stress/Views/StressFactorCardView.swift` | Reusable factor card                            |
| New View       | `Features + UI/Stress/Views/ScreenTimeInputSheet.swift` | Bottom sheet for screen time                    |
| Modify         | `Features + UI/Tab/MainTabView.swift`                   | Swap `StressPlaceholderView` → `StressView`     |
| Delete         | `Features + UI/Tab/StressPlaceholderView.swift`         | No longer needed                                |

---

## Scoring Algorithm (Detailed)

### Neutral fallback
Any factor with **no data** → **12.5 pts** (exactly half of 25)

---

### Factor 1 — Exercise Score (0–25)

Measures how active the user was today. More activity = less stress.

**Data extraction**: Call `fetchSteps(for: todayInterval)` and `fetchActiveEnergy(for: todayInterval)` which return `[DailyMetricSample]`. Extract today's value via `.first?.value`.

```
todayInterval = DateInterval(start: Calendar.current.startOfDay(for: Date()), end: Date())

stepsValue    = try await healthService.fetchSteps(for: todayInterval).first?.value
energyValue   = try await healthService.fetchActiveEnergy(for: todayInterval).first?.value

stepsScore    = 25.0 * (1.0 - clamp(steps / 10_000.0, 0, 1))
energyScore   = 25.0 * (1.0 - clamp(energy / 600.0,   0, 1))

If both available:  exerciseScore = (stepsScore + energyScore) / 2.0
If only steps:      exerciseScore = stepsScore
If only energy:     exerciseScore = energyScore
If neither:         exerciseScore = 12.5
```

| Steps today | Score |
| ----------- | ----- |
| 0           | 25.0  |
| 5,000       | 12.5  |
| 10,000+     | 0.0   |

---

### Factor 2 — Sleep Score (0–25)

Based on last night's `DailySleepSummary`. Optimal is 7.5–9h with good deep sleep.

**Data extraction**: Call `fetchDailySleepSummaries(for: lastDayInterval)` which returns `[DailySleepSummary]`. Use `.last` for the most recent night.

```
lastDayInterval = DateInterval(
    start: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!,
    end: Date()
)
summary = try await healthService.fetchDailySleepSummaries(for: lastDayInterval).last

Base score from total hours (0–20 pts):
  < 4h            → 20 pts
  4–5h            → linear 20→18
  5–6h            → linear 18→12
  6–7h            → linear 12→5
  7–9h            → linear 5→0   (sweet spot)
  9–10h           → linear 0→4   (too much sleep)
  > 10h           → 6 pts

Deep sleep penalty (0–5 pts):
  guard totalHours > 0 else { deepPenalty = 2.5 }   // neutral if no total
  deepRatio = deepHours / totalHours
  deepPenalty = clamp((0.18 - deepRatio) / 0.18, 0, 1) * 5
  (0 penalty if deepRatio ≥ 18%; up to 5 pts if deep sleep = 0)

sleepScore = min(25, baseScore + deepPenalty)
If no data → 12.5
```

---

### Factor 3 — Diet Score (0–25)

Queries today's `FoodLogEntry` records from SwiftData. No logs → 12.5.

```
Aggregate today's totals: protein, carbs, fat, fiber

Balance score (0–1, higher = better balance):
  proteinRatio  = clamp(totalProtein / 60.0, 0, 1)   // 60g daily target
  fiberRatio    = clamp(totalFiber   / 25.0, 0, 1)   // 25g daily target
  balancedScore = proteinRatio * 0.55 + fiberRatio * 0.45

Excess score (0–1, higher = more excess):
  fatRatio      = clamp(totalFat   / 65.0,  0, 1)    // 65g threshold
  carbRatio     = clamp(totalCarbs / 225.0, 0, 1)    // 225g threshold
  excessScore   = fatRatio * 0.45 + carbRatio * 0.55

Net balance index (0–1, higher = better):
  netBalance = clamp((balancedScore - excessScore * 0.6 + 0.5) / 1.0, 0, 1)

dietScore = 25.0 * (1.0 - netBalance)
```

---

### Factor 4 — Screen Time Score (0–25)

MVP: User manually inputs today's screen time via a bottom sheet slider. Value stored in `UserDefaults` with key `"screenTimeHours_yyyy-MM-dd"` (e.g. `"screenTimeHours_2026-02-21"`).

```
Key generation:
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  let key = "screenTimeHours_\(formatter.string(from: Date()))"

Thresholds:
  0–1h   → 2 pts
  1–2h   → linear 2→6
  2–4h   → linear 6→14
  4–6h   → linear 14→20
  6–8h   → linear 20→24
  8h+    → 25 pts

No entry today → 12.5 (neutral)
```

**Future DeviceActivity path** (Phase 2 / post-MVP):
- Add `com.apple.developer.family-controls` entitlement
- Use `DeviceActivity.DeviceActivityReport` to read phone usage
- Replace `UserDefaults` store with live SDK data; keep same scoring formula

---

### Total Score

```
stressScore = exerciseScore + sleepScore + dietScore + screenTimeScore
// Range: 0–100
```

### Stress Levels

```swift
enum StressLevel {
    case excellent   // 0–20   → teal/mint
    case good        // 21–40  → green
    case moderate    // 41–60  → yellow
    case high        // 61–80  → orange
    case veryHigh    // 81–100 → red

    var label: String
    var color: Color
    var encouragementText: String  // e.g. "You're doing great today!"
}
```

---

## Implementation Checklist

### Phase 1 — Data Models

- [ ] **Step 1.1** · Create `Models/StressModels.swift`
  - [ ] `StressLevel` enum with `label`, `color`, `encouragementText`
  - [ ] `StressLevel` init from score — handle all 5 ranges
  - [ ] `StressFactorResult` struct: `id`, `title`, `score` (0–25), `maxScore` (25), `icon`, `accentColor`, `statusText`, `detailText`
  - [ ] `StressFactorResult.neutral(title:icon:)` factory → score = 12.5
  - [ ] Use SwiftUI `.teal`, `.green`, `.yellow`, `.orange`, `.red` for level colors (no `Color(hex:)` dependency)

---

### Phase 2 — ViewModel

- [ ] **Step 2.1** · Create `Features + UI/Stress/ViewModels/StressViewModel.swift`
  - [ ] `@MainActor final class StressViewModel: ObservableObject`
  - [ ] Published state: `exerciseFactor`, `sleepFactor`, `dietFactor`, `screenTimeFactor`, `isLoading`, `isAuthorized`, `errorMessage`, `screenTimeHours`
  - [ ] Computed: `totalScore`, `stressLevel`, `allFactors`
  - [ ] Dependencies: `healthService: HealthKitServiceProtocol`, `modelContext: ModelContext`
  - [ ] `init(healthService:modelContext:)` — default `HealthKitService()`
  - [ ] `requestPermissionAndLoad()` — mirrors `SleepViewModel` pattern
  - [ ] `loadData()` — parallel fetch steps + energy + sleep using `DateInterval`:
    - [ ] Create `todayInterval` from `startOfDay(for: Date())` to `Date()`
    - [ ] Extract `steps = fetchSteps(for:).first?.value`
    - [ ] Extract `energy = fetchActiveEnergy(for:).first?.value`
    - [ ] Create sleep interval (past 1 day) and extract `.last` summary
    - [ ] Refresh diet factor synchronously from SwiftData
  - [ ] `updateScreenTime(_:)` — write to `UserDefaults` with key `"screenTimeHours_yyyy-MM-dd"` + recompute
  - [ ] `refreshDietFactor()` — query `FoodLogEntry` where `day == startOfDay(for: Date())` via `ModelContext`
  - [ ] Score engines (private):
    - [ ] `computeExerciseScore(steps: Double?, energy: Double?) -> Double`
    - [ ] `computeSleepScore(summary: DailySleepSummary?) -> Double` — guard `totalHours > 0` before deep ratio
    - [ ] `computeDietScore(logs: [FoodLogEntry]) -> Double`
    - [ ] `computeScreenTimeScore(hours: Double?) -> Double`
  - [ ] `screenTimeKey()` — use `DateFormatter` with `"yyyy-MM-dd"`, **not** `ISO8601DateFormatter`

---

### Phase 3 — Sub-views

- [ ] **Step 3.1** · Create `Features + UI/Stress/Views/StressScoreGaugeView.swift`
  - [ ] 270° arc gauge with colored fill animated to `score/100`
  - [ ] Center text: large score number + "/100"
  - [ ] Below center: stress level label badge (colored pill)
  - [ ] Color interpolation: teal(0) → green(25) → yellow(50) → orange(75) → red(100)
  - [ ] Parameters: `score: Double`, `level: StressLevel`, `size: CGFloat = 220`
  - [ ] Spring animation on score change

- [ ] **Step 3.2** · Create `Features + UI/Stress/Views/StressFactorCardView.swift`
  - [ ] Layout: icon + title + "X / 25" score + thin progress bar + status/detail text
  - [ ] Parameters: `factor: StressFactorResult`, `onTap: (() -> Void)? = nil`
  - [ ] Use `cardBackground` pattern: `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)`
  - [ ] `onTap` used for Screen Time card to open input sheet

- [ ] **Step 3.3** · Create `Features + UI/Stress/Views/ScreenTimeInputSheet.swift`
  - [ ] Title: "Today's Screen Time"
  - [ ] Large display: "X.X hrs"
  - [ ] Slider: 0 to 12 hours, step 0.5
  - [ ] Quick-pick pills: 1h 2h 3h 4h 6h
  - [ ] [Save] button (primary style)
  - [ ] `@Binding var hours: Double` from parent
  - [ ] On save: calls `viewModel.updateScreenTime(hours)` + dismiss

---

### Phase 4 — Main View

- [ ] **Step 4.1** · Create `Features + UI/Stress/Views/StressView.swift`
  - [ ] Use call-site injection pattern (matching `HomeView`):
    ```swift
    @StateObject var viewModel: StressViewModel
    ```
    ViewModel is created in `MainTabView` where `modelContext` is available
  - [ ] State logic: `if !HealthKitService.isAvailable → unavailableView; else if isLoading → loadingView; else if !isAuthorized → permissionView; else → mainContent`
  - [ ] Main content scroll layout:
    - [ ] `StressScoreGaugeView` card with score, level, encouragement
    - [ ] "Stress Factors" section header
    - [ ] `LazyVGrid(2 columns)` of 4 `StressFactorCardView`s
    - [ ] Screen Time card gets `onTap` to show sheet
    - [ ] "What's Affecting You?" insights card (top 2 factors by score)
  - [ ] `.sheet` for `ScreenTimeInputSheet`
  - [ ] `.task { await viewModel.requestPermissionAndLoad() }`
  - [ ] `.onAppear { viewModel.refreshDietFactor() }` — ensures diet is fresh on tab switch

---

### Phase 5 — Integration

- [ ] **Step 5.1** · Modify `Features + UI/Tab/MainTabView.swift`
  - [ ] Replace `StressPlaceholderView()` with:
    ```swift
    StressView(viewModel: StressViewModel(modelContext: modelContext))
    ```
    (`modelContext` is already available via `@Environment(\.modelContext)` in `MainTabView`)

- [ ] **Step 5.2** · Delete `Features + UI/Tab/StressPlaceholderView.swift`

---

### Phase 6 — Verification

- [ ] Build succeeds without warnings
- [ ] All 4 factor cards display with correct scores
- [ ] Missing HealthKit data → each factor shows 12.5 (neutral)
- [ ] Screen Time slider saves and persists across app relaunches (same day)
- [ ] Dark mode and light mode render correctly
- [ ] Score recalculates when screen time is updated (no app restart needed)
- [ ] No crashes when HealthKit is unavailable (Simulator)
- [ ] View matches card style, typography, and shadow conventions of Sleep/Burn tabs
- [ ] Diet score updates when switching tabs after logging food

---

## File Tree Summary

```
WellPlate/
├── Models/
│   └── StressModels.swift                              ← NEW
├── Features + UI/
│   ├── Stress/
│   │   ├── ViewModels/
│   │   │   └── StressViewModel.swift                   ← NEW
│   │   └── Views/
│   │       ├── StressView.swift                        ← NEW
│   │       ├── StressScoreGaugeView.swift              ← NEW
│   │       ├── StressFactorCardView.swift              ← NEW
│   │       └── ScreenTimeInputSheet.swift              ← NEW
│   └── Tab/
│       └── MainTabView.swift                           ← MODIFY (swap placeholder + inject VM)
└── Features + UI/Tab/
    └── StressPlaceholderView.swift                     ← DELETE
```

No changes required to:
- `HealthKitService.swift` / `HealthKitServiceProtocol.swift` (already fetches all needed data)
- `HealthModels.swift` (all needed models exist: `DailyMetricSample`, `DailySleepSummary`)
- `FoodLogEntry.swift` (has protein, carbs, fat, fiber)
- `AppColor.swift` / Font system (used as-is)

---

## Color Palette for Stress

| Level     | Score Range | Color     |
| --------- | ----------- | --------- |
| Excellent | 0–20        | `.teal`   |
| Good      | 21–40       | `.green`  |
| Moderate  | 41–60       | `.yellow` |
| High      | 61–80       | `.orange` |
| Very High | 81–100      | `.red`    |

Factor accent colors:
- Exercise: `.orange`
- Sleep: `.indigo`
- Diet: `.green`
- Screen Time: `.cyan`

---

## Key State & Data Flow

```
MainTabView
  └── @Environment(\.modelContext)
      └── StressView(viewModel: StressViewModel(modelContext: modelContext))
            └── @StateObject StressViewModel
                  ├── HealthKitServiceProtocol
                  │    ├── fetchSteps(for: todayInterval)       → [DailyMetricSample] → .first?.value
                  │    ├── fetchActiveEnergy(for: todayInterval) → [DailyMetricSample] → .first?.value
                  │    └── fetchDailySleepSummaries(for: 1-day)  → [DailySleepSummary] → .last
                  ├── ModelContext
                  │    └── FoodLogEntry.fetchRequest(day == today)
                  └── UserDefaults
                       └── "screenTimeHours_yyyy-MM-dd"

                  Outputs:
                  ├── totalScore: Double (0–100)
                  ├── stressLevel: StressLevel
                  ├── [exerciseFactor, sleepFactor, dietFactor, screenTimeFactor]
                  └── screenTimeHours: Double (bound to slider)
```

---

## Risks & Mitigations

| Risk                                                   | Likelihood        | Mitigation                                                                   |
| ------------------------------------------------------ | ----------------- | ---------------------------------------------------------------------------- |
| No HealthKit data (Simulator)                          | High (during dev) | Each score defaults to 12.5; show "using estimated data" note in factor card |
| Screen Time slider reset on app relaunch               | Low               | Persisted in `UserDefaults` with date key; reloads on `.task`                |
| Score feels arbitrary / not meaningful                 | Medium            | Add "?" info button on each card explaining the formula                      |
| HealthKit authorization already granted (no re-prompt) | Low               | `isAuthorized` check from existing service handles this correctly            |
| Diet factor stale after logging food                   | Medium            | Call `refreshDietFactor()` in `.onAppear` so it refreshes on tab switch      |

---

## Implementation Order (Recommended)

1. `StressModels.swift` — foundation, no dependencies
2. `StressViewModel.swift` — score engine, test logic in isolation
3. `StressFactorCardView.swift` — simple reusable component
4. `StressScoreGaugeView.swift` — visual, can be developed independently
5. `ScreenTimeInputSheet.swift` — simple sheet, no dependencies
6. `StressView.swift` — assembles everything
7. `MainTabView.swift` — final integration + delete placeholder

Each step is independently compilable and previewable.
