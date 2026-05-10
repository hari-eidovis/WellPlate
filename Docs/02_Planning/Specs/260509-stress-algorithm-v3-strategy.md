# Strategy: Stress Algorithm v3 — Driver/Calibrator Split with Engagement Penalties and Manual Fallbacks

**Date:** 2026-05-09
**Source brainstorm:** [260509-stress-algorithm-v3-brainstorm.md](../../01_Brainstorming/260509-stress-algorithm-v3-brainstorm.md)
**Formula reference:** [260509-stress-formula-spec.md](../../01_Brainstorming/260509-stress-formula-spec.md)
**Prior work:** [260420-stress-algorithm-improvements-strategy.md](./260420-stress-algorithm-improvements-strategy.md) (v2 — scaffolding removed in commit `dbf08c0`; v3 supersedes it)
**Status:** Ready for Planning

---

## 1. Chosen Approach — "Direct v3 Replacement, No Flag, Three Sequential Phases"

Rewrite `StressScoring` as a pure-function module returning `FactorPoints` per signal, refactor `StressViewModel` to build a single `StressInputs` struct and call the new pure `computeStress(inputs:now:)`, and add a `ManualDailyInput` SwiftData model with a global `DailyPromptCoordinator` that surfaces two daily overlays (morning/evening) when HealthKit is silent.

Ship in **three sequential phases**, each independently buildable but landing as a single feature branch — no `AppConfig` flag, no parallel `StressScoringV2` shadow service.

### Why direct replacement (no flag)

1. **No history migration needed.** `StressReading` only persists `score` and `levelLabel`. v1 numbers and v3 numbers coexist in history without schema change.
2. **The prior v2 flag-gated attempt was unwound** (`dbf08c0` "remove StressExperiment model and report plumbing"). The dual-implementation overhead proved heavy for a single-developer project. Don't repeat it.
3. **The formula is fully specified** (see formula spec §1–§7). There's no exploratory uncertainty that justifies shadow logging.
4. **Solo dev → feature branch is the rollback mechanism.** If v3 misbehaves on real device testing, revert the branch.
5. **Clean cut clarifies UX.** Users stop comparing v1 numbers to v3 numbers; we surface a one-time "Algorithm updated" banner instead.

### Why three phases (vs. one big bang)

| Phase | What ships | Verifiable | Independently shippable? |
|---|---|---|---|
| **P1 — Scoring core** | New `StressScoring.swift` shape + `StressViewModel` calling `computeStress`; existing UI reads new factors via the same `StressFactorResult` surface | Build green; same `StressView` renders; numbers move correctly | Yes — UI looks like v1 but math is v3 |
| **P2 — Manual fallback + overlays** | `ManualDailyInput` model, `DailyPromptCoordinator`, `QuickCheckInSheet`, `RootView` integration | Overlay fires at 11:00 / 19:00 if HK silent; manual values flow into `computeStress` via priority chain | Yes — v3 with optional manual entry |
| **P3 — UI surfacing** | Top-N driver cards, engagement-gap card, calibrator chip, recovery section | StressView reflects v3's richer signal set | Yes — v3 with the proper presentation |

Each phase is a buildable, mergeable unit. If we stop after P1, the math is correct but UI under-utilizes the data. If we stop after P2, all data flows but UI still shows fixed cards. P3 unlocks full value.

### Trade-offs accepted

- **Existing v1 `StressReading` rows look like step-change at v3 launch.** Mitigated by a one-time banner; not corrected.
- **No A/B test infra.** Single-dev project, ship to own device first.
- **Phase 1 ships with old UI shape** — meaning fixed 4-factor cards on `StressView` while the model has 13 drivers. Acceptable for a few days; P3 fixes it.
- **Hour-bucketed screen time deferred.** `eveningHours = nil` means the evening multiplier no-ops in v3; tracked as future work, not blocker.

---

## 2. Phase Map

### Phase 1 — Scoring Core (3–4 days)

**Goal:** New math runs end-to-end. UI is unchanged shape; only the numbers it displays change.

**Scope:**
- Rewrite `WellPlate/Core/Services/StressScoring.swift`:
  - Replace `Weights.sleep/exercise/diet/screenTime` constants with the v3 weight table (Tier A 60 / B 25 / C 15)
  - Replace 4 scoring functions with 13 driver factor functions, all returning `FactorPoints { points, maxPoints, hasData, detail }`
  - Add recovery functions (`interventionBonus`, `journalBonus`, `mindfulBonus`)
  - Add `engagementPenalty(inputs:now:)` and `patternPenalty(history:)`
  - Add `baseline14Day(samples:excludingToday:)` and `calibrator(inputs:)`
  - Add pure `computeStress(inputs:now:) -> StressResult`
- Define `StressInputs` (input bag) and `StressResult` (output) structs in `StressScoring.swift`
- Refactor `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`:
  - `loadData()` builds `StressInputs` from HK fetches + SwiftData fetches
  - Add fetches for: today's `[SymptomEntry]`, today's `JournalEntry`, today's completed `[InterventionSession]`, recent (last 3 days) `[FoodLogEntry]`, recent `[WellnessDayLog]`, recent `[FastingSession]`
  - `totalScore` becomes a stored `@Published var` (set from `computeStress` result)
  - Add `@Published var calibratorMultiplier: Double`, `@Published var engagementPenalty: Double`, `@Published var patternPenalty: Double`
  - Add `recompute()` — pure call to `computeStress` reusing already-fetched inputs (used on input change without re-hitting HK)
  - Add 5-minute `Timer.publish` ticker while `.scenePhase = .active` to advance `E(t)`
  - Update `factorCoverage` and `stressConfidence` to weight-weighted formula (formula spec §8)
  - Stop feeding `heartRateHistory`/`bp*History`/`respiratoryRateHistory` into scoring; keep them published for vitals card
- Update `WellPlate/Models/StressModels.swift`:
  - `StressFactorResult` builder consumes `FactorPoints`; default `maxScore = 25` removed in `.neutral(...)` factory
  - `stressContribution` simplifies (no more `higherIsBetter` flip — `FactorPoints.points` is already signed)
- Update `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`:
  - Add fields for symptoms, mood, journal flag, intervention sessions, history bags, vitals baselines
  - Add a "fully-logged-bad-day" mock variant and "disengaged-day" mock variant for the validation checklist

**Affected files:**
- `WellPlate/Core/Services/StressScoring.swift` — full rewrite
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — pipeline refactor
- `WellPlate/Models/StressModels.swift` — `StressFactorResult` builder
- `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift` — extend mock surface

**Exit gate:**
- Build green on all 4 targets (WellPlate, ScreenTimeMonitor, ScreenTimeReport, WellPlateWidget)
- Logging mood `awful` increases the score; logging mood `great` decreases it (manual smoke test)
- Logging water from 0 → 8 glasses decreases the score (smoke test)
- A day with zero data still hides the score (`coverage < 0.40`)
- Validation checklist from formula spec §14 passes via mock snapshots
- Existing `StressReading` rows still load correctly (no SwiftData migration error)

**Non-goals for P1:**
- New UI cards
- Manual input
- Overlays
- Caffeine cup timestamps (defer late_bonus)

---

### Phase 2 — Manual Fallback + Daily Overlays (3–4 days)

**Goal:** Watch-less and HK-denied users can fully populate the model via manual entry, prompted by two unobtrusive daily overlays.

**Scope:**
- New file `WellPlate/Models/ManualDailyInput.swift`:
  - `@Model` with fields: `sleepHours`, `sleepQuality`, `bedtime`, `wakeTime`, `screenTimeHours`, `heavyEveningScreens`, `exerciseMinutes`, `amDaylightOutside`, `morningAskedAt`, `eveningAskedAt`
  - `@Attribute(.unique) day: Date`
- Register `ManualDailyInput.self` in `WellPlate/App/WellPlateApp.swift` ModelContainer
- New file `WellPlate/Core/Services/DailyPromptCoordinator.swift`:
  - `@MainActor final class DailyPromptCoordinator: ObservableObject`
  - `@Published var pendingPrompt: PromptKind?` where `PromptKind = .morning(MorningGaps) | .evening(EveningGaps)`
  - `evaluateOnAppForeground(now:hk:manual:) async`
  - Reads `morningAskedAt`/`eveningAskedAt` to dedupe; reads `UserDefaults` flag for "Don't ask again"
- New file `WellPlate/Shared/Components/QuickCheckInSheet.swift`:
  - Bottom sheet view bound to `pendingPrompt`
  - Three actions: Save / Skip for today / Don't ask again
  - Morning form: hours slider, quality 1–5 segmented, optional bedtime/wake `DatePicker`
  - Evening form: screen time hours, heavy-evening toggle, exercise minutes, AM daylight toggle — fields hidden if HK already populated them
- Update `WellPlate/App/RootView.swift`:
  - Inject `DailyPromptCoordinator` as `@StateObject`
  - On `.scenePhase = .active`, call `evaluateOnAppForeground`
  - Present `QuickCheckInSheet` via `.sheet(item:)` bound to `coordinator.pendingPrompt`
- Update `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`:
  - In `loadData()`, fetch today's `ManualDailyInput`
  - Resolution priority for sleep/screen/exercise/daylight/circadian per brainstorm §8
  - When manual data is saved, observe and trigger `recompute()`
- Add Settings toggle in `WellPlate/Features + UI/Tab/ProfileView.swift`:
  - Reset "Don't ask again" flags

**Affected files:**
- `WellPlate/Models/ManualDailyInput.swift` — NEW
- `WellPlate/App/WellPlateApp.swift` — register model
- `WellPlate/Core/Services/DailyPromptCoordinator.swift` — NEW
- `WellPlate/Shared/Components/QuickCheckInSheet.swift` — NEW
- `WellPlate/App/RootView.swift` — host coordinator + sheet
- `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` — manual resolution priority
- `WellPlate/Features + UI/Tab/ProfileView.swift` — settings toggle

**Exit gate:**
- On simulator with HK denied, opening the app at 11:30 shows morning prompt; saving sleep populates `p_sleep` in the score
- On simulator at 19:30 with no manual data, evening prompt fires showing only fields HK is silent on
- "Skip for today" prevents re-prompt until next day (verified by changing system time)
- "Don't ask again" persists across app restart
- Watch-equipped user (HK populated) sees no overlay
- First launch (within 24h of onboarding) suppresses prompts

**Non-goals for P2:**
- Engagement-gap UI card (P3)
- Settings UI for editing manual values after submission (use re-prompt flow)

---

### Phase 3 — UI Surfacing (3–4 days)

**Goal:** `StressView` reflects v3's richer signal set — top contributors, engagement gaps, recovery actions, calibrator state.

**Scope:**
- Refactor `WellPlate/Features + UI/Stress/Views/StressView.swift`:
  - **Header:** total score + level + new calibrator chip (e.g., "HRV +8% vs baseline" / "Vitals normal" / "Watch-less")
  - **"What's driving it" section:** sort `viewModel.allFactors` by `points` desc, render top 5 cards. Replaces hardcoded 4-card grid.
  - **"Recovery" sub-section:** intervention/journal/mindful with "−X stress avoided" framing
  - **"Engagement gaps" card** (visible only when `engagementPenalty > 0`): list active gaps and their current penalty; CTA buttons to log mood/water/food inline
  - **"All factors" disclosure:** full 13-driver list with `points / maxPoints` bars, sorted by tier
  - **Persistent "Quick log" button:** opens `QuickCheckInSheet` even outside the auto-prompt windows (for users who dismissed)
- Update existing `StressFactorCard` component to show signed `points` (e.g., "−3 pts", "+8 pts") and tier label
- Update `WellPlate/Features + UI/Stress/Support/StressSheet.swift`:
  - Add `.allFactors` case for the disclosure sheet
  - Confirm vital-detail sheets continue to read from existing `vitalHistory(for:)` (calibrator inputs, not score factors)
- One-time "Algorithm updated" banner on first app open after v3 lands:
  - Stored as `UserDefaults` flag `wp.stress.v3AnnouncementShown`
  - Dismissible; explains the new factor set in 2 sentences

**Affected files:**
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — major rebuild
- `WellPlate/Features + UI/Stress/Components/StressFactorCard.swift` — show signed points + tier
- `WellPlate/Features + UI/Stress/Support/StressSheet.swift` — add `.allFactors` sheet case
- `WellPlate/Features + UI/Stress/Components/EngagementGapsCard.swift` — NEW
- `WellPlate/Features + UI/Stress/Components/CalibratorChip.swift` — NEW
- `WellPlate/Features + UI/Home/Components/StressSparklineStrip.swift` — verify it reads `viewModel.totalScore` correctly (no shape change expected)

**Exit gate:**
- Top 5 driver cards reorder when inputs change (verified by mock snapshot toggle)
- Engagement-gaps card disappears when all gaps closed
- Calibrator chip shows correct delta from baseline (mock with HRV 25% below baseline → "+12% calibration")
- Quick Log button opens the sheet outside auto-prompt times
- Build green on all 4 targets
- Visual regression check on Home tab's `StressSparklineStrip`

**Non-goals for P3:**
- New chart designs for vitals detail views
- Widget updates (covered separately if needed — `WidgetRefreshHelper.refreshStress` already plumbed)
- AI report narrative changes (out of scope; report still consumes `totalScore`)

---

## 3. Architectural Direction

### 3.1 Pure scoring core

`StressScoring.computeStress(inputs:now:)` is **pure**. It takes a fully-populated `StressInputs` struct and returns a `StressResult`. No side effects, no SwiftData reads, no HK reads, no file I/O. This is the single source of truth for the formula.

The ViewModel's job is reduced to:
1. Build `StressInputs` (the only "wiring" layer)
2. Call `computeStress`
3. Publish the result fields

This is the same pattern `CircadianService.compute(...)` already follows. Mirror it.

### 3.2 Reactive recompute path

```
@Published input change  →  recompute()  →  computeStress  →  publish results
HK fetch completes       →  loadData() updates inputs cache  →  recompute()
Timer ticks (5min)       →  recompute() with current Date
.scenePhase = .active    →  loadData() (fresh fetch) + recompute()
```

`recompute()` is cheap (microseconds). Don't gate it. Don't debounce.

### 3.3 Single sheet authority

`RootView` owns the only `.sheet(item:)` for the daily prompt. Do **not** add prompt presentation in `StressView` or any other tab. Per CLAUDE.md convention: "Feature sheets use a single enum driving one `.sheet(item:)`". The coordinator's `pendingPrompt` enum is that single source.

### 3.4 Source priority for device-data factors

Implement as a small resolver in `StressViewModel`:

```swift
private func resolveSleep(hk: DailySleepSummary?, manual: ManualDailyInput?) -> SleepInput? {
    if let hk { return SleepInput(from: hk, source: .healthKit) }
    if let m = manual, let h = m.sleepHours {
        return SleepInput(hours: h, deepHours: derivedDeepHours(quality: m.sleepQuality), source: .manual)
    }
    return nil
}
```

Same shape for screen, exercise, daylight, circadian. HK always wins; manual fallback when HK is `nil`.

### 3.5 Engagement penalty activation guard

Implement in `StressScoring.engagementPenalty`:

```swift
guard inputs.factors.contains(where: \.hasData) else { return 0 }
```

This is the single critical guard for first-day users. Must be unit-tested.

### 3.6 Calibrator baseline collapse

`baseline14Day` returns `nil` when fewer than 5 valid days exist. `calibrator` returns `1.0` when both baselines are `nil`. This means:

- New user (day 1): C = 1.0, score uncalibrated, no harm done
- Watch-less user: C = 1.0, score uncalibrated, no penalty
- HK-denied: same as Watch-less

No special-case branches in the consumer. The calibrator just behaves identically to "no signal."

---

## 4. Design Constraints (planner must respect)

1. **`computeStress` stays pure.** No SwiftData, no HK, no `Date()` calls — `now` is passed in.
2. **`StressInputs` is the only struct that crosses the wiring/math boundary.** All sub-types (`SleepInput`, `ExerciseInput`, etc.) live in `StressScoring.swift`.
3. **Engagement penalty must use linear ramps**, not hard cutoffs (formula spec §5). UX continuity matters more than implementation simplicity.
4. **Pattern penalty thresholds are intentionally discrete** (formula spec §6). Do not smooth them with sigmoids — discrete events are easier to explain.
5. **HK is always source-of-truth.** When HK populates after manual entry, HK silently overrides on next recompute. Don't require the user to dismiss a "data conflict" dialog.
6. **Manual entry never reduces confidence.** `H_f = 1` whether the source is HK or manual.
7. **`StressReading` schema unchanged.** Continue persisting only `score` + `levelLabel` + `source` + `timestamp`. No new columns.
8. **Existing `WPLogger.stress.debug` log lines stay.** They are the primary debugging surface; extend them, don't remove.
9. **Mock data must populate every `StressInputs` field.** A `StressMockSnapshot` that omits new fields is a P1 exit-gate failure.
10. **Use existing `.r(.headline, .semibold)` font and `.appShadow(...)` modifier** for any new UI in P3. No raw `.font(.system(...))` calls.

---

## 5. Non-Goals (explicitly out of scope)

- **Hour-bucketed screen time** with evening multiplier wired to real data — `ScreenTimeManager` extension deferred. P1 passes `eveningHours = nil`; P2 captures it via the manual `heavyEveningScreens` toggle as a binary; full HK-side implementation is a separate brainstorm.
- **True mindful-minutes count** from `HKCategoryTypeIdentifier.mindfulSession` — out of scope. Use `mood logged today OR journal today` as a stand-in for `b_mindful`.
- **Caffeine cup timestamps** for `late_bonus` — `WellnessDayLog` only stores `coffeeCups: Int`. Adding per-cup timestamps is a separate data model change.
- **Gender-aware modulation** (sleep ×1.3, caffeine half-life × OCP) — explicitly deferred per 260420 strategy §S1–S2.
- **Cycle-phase awareness** — would require menstrual flow read permission; out of scope.
- **Backfilling historical `StressReading` rows** with v3 numbers — accepted as a step change.
- **Widget redesign** — widget continues to read `viewModel.totalScore` as before.
- **AI report narrative tuning** for the new factor set — `ReportNarrativeGenerator` already consumes structured `WellnessDaySummary`; no immediate changes needed, but copy may need refresh in a follow-up.
- **A/B testing infrastructure** — single-developer project.
- **Migration UI for the v1→v3 step change** — a single one-time banner is sufficient.

---

## 6. Open Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Step-change in stress numbers when v3 ships** breaks user mental model | Medium | One-time "Algorithm updated" banner explaining new factors; dismissible |
| **Engagement penalties feel punitive** to users who haven't grokked the system | Medium | Activation guard (≥1 driver must have data); engagement-gaps card explains exactly what's costing points and how to fix |
| **5-minute timer drains battery** in foreground | Low | `Timer.publish(every: 300)` is cheap; only fires while `.active`; cancel on background |
| **HK auth denied → no calibrator and no auto sleep/exercise** silently degrades score quality | Medium | Manual fallback (P2) covers sleep/exercise/screen/daylight; calibrator gracefully collapses to 1.0 |
| **Manual sleep quality → derived deep hours is wrong-by-design** for users who actually have low sleep efficiency | Low | Acceptable approximation; HK overrides as soon as available; document in code comment |
| **Pattern penalty triggers off historical data not yet populated** in fresh installs | Low | All pattern predicates require ≥3 days of history; on day 1, they are all `false` |
| **`StressMockSnapshot` underspecified for new fields** breaks dev/preview builds | Medium | P1 exit gate explicitly requires mock parity |
| **`StressView` rebuild in P3 collides with recent UI commits** (e.g., `3ec2f98 polish UI components`) | Low | Sequence P3 last; merge P1+P2 first; rebase P3 on latest main |
| **Onboarding gates manual prompts** but coordinator runs from `RootView` regardless | Medium | Coordinator's `evaluateOnAppForeground` checks `RootView`'s phase enum (`splash/onboarding/main`); only fires in `.main` |

---

## 7. Prerequisites

None. All required APIs are already in the codebase:

- HealthKit fetches (sleep, steps, energy, HRV, RHR, daylight) — `HealthKitService` ✓
- ScreenTime — `ScreenTimeManager` ✓
- SwiftData models — `WellnessDayLog`, `FoodLogEntry`, `SymptomEntry`, `JournalEntry`, `InterventionSession`, `FastingSession`, `UserGoals` ✓
- Circadian — `CircadianService.compute(...)` ✓
- Mood — `WellnessDayLog.moodRaw` + `MoodOption` ✓
- Coffee mg — `CoffeeType.caffeineMg` ✓

---

## 8. Success Criteria (cumulative across phases)

- [ ] User logging mood `awful` after 21:00 strictly raises stress vs not logging
- [ ] User logging water 8/8 strictly lowers stress vs not logging
- [ ] User with 5 logged symptoms (severity 6+) sees stress in "High" or "Very High" range
- [ ] HK-denied user can fully populate the model via 2 daily overlays
- [ ] Watch-less user sees calibrator collapse to 1.0, no error state
- [ ] Day-1 user (no data, no history) does not see a stress score (low confidence)
- [ ] Engagement-gaps card shows actionable CTAs and disappears as gaps close
- [ ] Build green on all 4 targets at every phase boundary
- [ ] No existing `StressReading` rows fail to load (no migration bug)

---

## Next step

→ `/develop plan stress-algorithm-v3` — produce file-by-file implementation plan in `Docs/02_Planning/Specs/260509-stress-algorithm-v3-plan.md`.
