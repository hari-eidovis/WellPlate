# Brainstorm: Comprehensive Mock Mode Toggle

**Date**: 2026-04-10
**Status**: Ready for Planning

## Problem Statement

WellPlate has two separate mock-related mechanisms that are partially connected:

1. **`AppConfig.mockMode`** — toggles the nutrition API client (Groq → MockAPIClient). Also triggers `InsightEngine.mockInsights()` which returns 6 hard-coded InsightCards. Controlled by a Profile toggle.
2. **`AppConfig.mockDataInjected`** — injects SwiftData records (FoodLogEntry, WellnessDayLog, StressReading) and swaps `HealthKitService()` → `MockHealthKitService()` in *some* ViewModels. Controlled by a separate "Inject Mock Data" button in Profile.

The user's ask: **a single toggle** in Profile that turns on mock mode for **every feature** in the app — wellness calendar, AI insights, burn, sleep, stress, food logging — so the entire app runs with realistic fake data without needing real HealthKit access or API keys.

### Current Coverage Audit

| Feature | `mockMode` coverage | `mockDataInjected` coverage | Gap |
|---|---|---|---|
| **Food Logging (Nutrition API)** | Yes — MockAPIClient | N/A | None |
| **Stress View** | Yes — StressView passes MockHealthKitService when `mockMode \|\| mockDataInjected` | Yes — SwiftData StressReadings injected | None |
| **Burn View** | No | Yes — BurnViewModel uses MockHealthKitService when `mockDataInjected` | Doesn't respond to `mockMode` alone |
| **Sleep View** | No | **NO** — `SleepViewModel()` always gets `HealthKitService()`. No mock-aware init. | **Full gap** |
| **Wellness Calendar** | No | Yes — WellnessCalendarViewModel checks `mockDataInjected` for MockHealthKitService | Doesn't respond to `mockMode` alone |
| **AI Insights (InsightEngine)** | Partially — returns hard-coded mock cards when `mockMode` is on | **NO** — InsightEngine always does `init(healthService: HealthKitService())`. Doesn't check `mockDataInjected`. | **When `mockDataInjected` is on, InsightEngine still tries to use real HK** |
| **Home View (Activity Rings)** | No | Partial — HomeView skips HK auth when `mockDataInjected`, but `loadActivityData()` still uses raw `HealthKitService()` | Activity rings don't read from MockHealthKitService |
| **Home View (Mood write)** | No | Partial — gates HK write behind `!mockDataInjected` | OK but mood read returns nil |
| **InsightsHubView (preview)** | No | No — creates `InsightEngine()` with default init | Always uses real HealthKit |
| **InsightDetailSheet (preview)** | No | No — same as above | Same |

### Core Problem

There are **two flags** and **two toggle gestures** where users expect **one**. Some ViewModels check `mockMode`, some check `mockDataInjected`, some check both with `||`, some check neither. The result is inconsistent behaviour depending on which toggle was flipped.

## Core Requirements

- **Single toggle** in Profile that activates comprehensive mock mode
- All features must show realistic data when mock mode is on
- No HealthKit authorization required when mock is active
- No API keys required when mock is active (Groq, etc.)
- Data should persist across app restarts (SwiftData injection)
- Must be safe — zero risk to real user data
- DEBUG builds only

## Constraints

- `SleepViewModel` has no mock-aware init today — needs the same pattern as BurnViewModel/WellnessCalendarViewModel
- `InsightEngine` needs to use `MockHealthKitService` when `mockDataInjected` so it can run the real insight detection pipeline on mock data (instead of returning hard-coded cards)
- HomeView creates raw `HealthKitService()` for activity rings — needs to go through factory or check mock flag
- The existing `StressMockSnapshot.default` generates 30-day HealthKit data — this is the canonical source for MockHealthKitService
- The existing `MockDataInjector` generates 30-day SwiftData data — this covers FoodLogEntry, WellnessDayLog, StressReading
- Missing SwiftData mock data: `SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry` — InsightEngine queries these

---

## Approach 1: Unify Flags + Fix All Gaps (Minimal)

**Summary**: Merge `mockMode` and `mockDataInjected` into a single `mockMode` flag. Fix all ViewModels that don't check this flag. Add missing mock data.

**How it works**:

1. **Single toggle**: Profile shows one "Mock Mode" toggle that:
   - Sets `AppConfig.shared.mockMode = true`
   - Calls `MockDataInjector.inject(into: context)` (injects SwiftData records)
   - Removes `mockDataInjected` as a separate concept
2. **Fix ViewModel gaps**:
   - `SleepViewModel`: add same pattern as BurnViewModel (`if AppConfig.shared.mockMode { MockHealthKitService(snapshot: .default) }`)
   - `InsightEngine`: pass `MockHealthKitService` when `mockMode` is on. Remove the hard-coded `mockInsights()` shortcut so the real detection pipeline runs on mock data.
   - `HomeView.loadActivityData()`: use mock service when `mockMode`
   - `InsightsHubView` + `InsightDetailSheet`: pass mock-aware InsightEngine
3. **Expand MockDataInjector**: add `SymptomEntry`, `FastingSession`, `AdherenceLog`, `JournalEntry` mock records so InsightEngine's multi-domain detection has data to work with
4. **Toggle off**: Clear SwiftData mock records + set flag false. Show restart alert.

**Pros**:
- Simplest mental model — one flag, one toggle
- Fixes all known gaps without architectural change
- MockDataInjector already handles inject/delete safely
- Builds on existing `HealthKitServiceProtocol` seam

**Cons**:
- Every ViewModel that creates `HealthKitService()` needs a guard clause — pattern is scattered
- Turning mock mode off requires app restart (SwiftData + HealthKit service swap)
- `InsightEngine.mockInsights()` becomes dead code (or fallback for when SwiftData is empty)

**Complexity**: Low-Medium
**Risk**: Low

---

## Approach 2: Service Factory Pattern (Centralized)

**Summary**: Introduce a `HealthKitServiceFactory` that all ViewModels use. The factory checks `mockMode` once and returns the appropriate implementation. No per-ViewModel checks.

**How it works**:

1. **`HealthKitServiceFactory.shared.service`**: returns `MockHealthKitService(snapshot: .default)` when mock mode is on, `HealthKitService()` when off
2. All ViewModels change their default init from `HealthKitService()` → `HealthKitServiceFactory.shared.service`
3. **`APIClientFactory`** already does this for the API layer — same pattern
4. Single profile toggle sets the flag + calls inject; factory picks up the change
5. InsightEngine, SleepViewModel, BurnViewModel, WellnessCalendarViewModel, HomeView all just ask the factory

**Pros**:
- Single point of control — adding new ViewModels requires no mock awareness, they just use the factory
- Matches existing `APIClientFactory` pattern — consistent architecture
- Easy to test — swap factory for tests
- No scattered `if mockMode` checks in every ViewModel

**Cons**:
- Factory returns a singleton-ish service — need to handle "service was created before flag changed" (stale reference)
- Slight refactor of all ViewModel inits (medium churn)
- Need to decide: does factory cache the service or recreate each call?

**Complexity**: Medium
**Risk**: Low

---

## Approach 3: Environment Injection (SwiftUI-Native)

**Summary**: Create a SwiftUI Environment key for the HealthKit service. Inject `MockHealthKitService` or `HealthKitService` at the app root based on mock mode. ViewModels read from environment.

**How it works**:

1. `HealthKitServiceKey: EnvironmentKey` with default value `HealthKitService()`
2. `WellPlateApp.swift` injects `.environment(\.healthKitService, mockMode ? MockHealthKitService() : HealthKitService())`
3. Views pass environment service to their ViewModels
4. Toggle in Profile sets flag → app restarts → correct service is injected

**Pros**:
- Most "SwiftUI" approach — uses the framework's DI system
- Clean separation
- Works well with previews

**Cons**:
- Changing the environment value at runtime requires rebuilding the view hierarchy (needs app restart or `@State`-driven conditional)
- ViewModels don't have direct access to `@Environment` — views must bridge the value
- Significantly more plumbing than the factory approach
- Most ViewModels are already created as `@StateObject` in views — timing matters

**Complexity**: High
**Risk**: Medium

---

## Approach 4: Unified Mock Mode + Real Data Pipeline (Best of Both Worlds)

**Summary**: Combine Approach 1 (fix gaps) + Approach 2 (factory) + enhance InsightEngine to run its real detection pipeline on mock data.

**How it works**:

1. **HealthKitServiceFactory** (Approach 2): single source of truth for HK service
2. **Single `mockMode` flag** (Approach 1): replaces both `mockMode` and `mockDataInjected`
3. **InsightEngine runs real pipeline on mock data**: instead of hard-coded `mockInsights()`, the engine fetches from SwiftData (mock-injected records) + MockHealthKitService (via factory). This means mock mode produces *realistic, dynamically-generated insights* — not canned cards.
4. **Expanded MockDataInjector**: add Symptom, Fasting, Adherence, Journal entries so InsightEngine has full multi-domain data
5. **Profile toggle**:
   - Turn ON: inject SwiftData mock data + set flag → restart alert
   - Turn OFF: clear mock SwiftData records + set flag → restart alert
6. **All ViewModels use factory**: `HealthKitServiceFactory.shared.service`

**Key benefit**: Mock mode isn't "fake UI" — it's "real logic, fake data". This catches bugs that hard-coded mock insights never would.

**Detailed gaps to fix**:

| File | Change |
|---|---|
| `SleepViewModel.swift` | Change default init to use `HealthKitServiceFactory.shared.service` |
| `BurnViewModel.swift` | Replace inline mock check with `HealthKitServiceFactory.shared.service` |
| `WellnessCalendarViewModel.swift` | Replace inline mock check with factory |
| `StressViewModel.swift` | Already accepts protocol param — wire factory at call site |
| `InsightEngine.swift` | Default init uses factory; remove `mockInsights()` shortcut (or keep as fallback when SwiftData is empty) |
| `HomeView.swift` | `loadActivityData()` uses factory; mood write gated |
| `InsightsHubView.swift` | `InsightEngine()` call uses factory |
| `InsightDetailSheet.swift` | Same |
| `MockDataInjector.swift` | Add SymptomEntry, FastingSession, AdherenceLog, JournalEntry injection |
| `AppConfig.swift` | Deprecate `mockDataInjected` → fold into `mockMode` |
| `ProfileView.swift` | Single toggle replaces two controls |
| `StressView.swift` | Use factory instead of inline `MockHealthKitService(snapshot:)` |
| `MainTabView.swift` | Use factory instead of inline mock check |
| New: `HealthKitServiceFactory.swift` | Factory class in `Core/Services/` |

**Pros**:
- Comprehensive — every feature, one toggle
- Factory pattern eliminates scattered mock checks
- InsightEngine produces *real* insights from mock data — tests the actual pipeline
- Expanded mock data covers all SwiftData domains
- Consistent with existing `APIClientFactory` pattern
- Progressive — can ship factory + flag merge first, then expand InsightEngine data

**Cons**:
- Moderate churn across ~12 files (but all changes are small)
- Restart required on toggle (can't hot-swap HealthKit service after ViewModels are created)
- Need to generate realistic symptom/fasting/journal mock data

**Complexity**: Medium
**Risk**: Low

---

## Edge Cases to Consider

- [ ] **Toggle on → restart → toggle off → restart**: Must cleanly round-trip. MockDataInjector.deleteAll must handle all new model types (Symptom, Fasting, etc.)
- [ ] **User has real data + enables mock**: Mock SwiftData records coexist with real ones (tagged with `logSource: "mock"` / `source: "mock"`). Real data is never touched. BUT: InsightEngine will aggregate both → potentially confusing mixed insights. Mitigation: when mock mode on, InsightEngine could filter to mock-only records? Or accept that it's a demo tool and mixed data is fine.
- [ ] **SleepViewModel mock data**: `MockHealthKitService.fetchDailySleepSummaries()` returns from `StressMockSnapshot.default.sleepHistory` which has 30 days of data. Good.
- [ ] **InsightEngine minimum data gate**: requires >= 2 domains with >= 2 days of data. Mock data provides 30 days across all domains — easily passes.
- [ ] **HomeView activity rings**: currently loads steps/energy/exercise directly from `HealthKitService()` — must use factory
- [ ] **Widget extension**: reads from App Group, not from mock service. Mock mode won't affect widget unless we store mock flag in shared container. Acceptable limitation for V1.
- [ ] **Foundation Models availability**: InsightEngine's narrative generation uses on-device Foundation Models. In mock mode, this still runs (generates narratives from mock data). If Foundation Models is unavailable, template fallback works. No issue.
- [ ] **Double-inject guard**: `MockDataInjector.inject()` already checks `mockDataInjected` flag. When merged into `mockMode`, this guard should check whether SwiftData mock records exist (e.g., count of `logSource == "mock"` FoodLogEntries > 0) rather than just the flag.
- [ ] **Flag rename**: if `mockDataInjected` is removed, old UserDefaults key may linger. Clear it in migration or just leave it harmless.

## Open Questions

- [ ] Should mock mode filter InsightEngine to mock-only SwiftData records, or let it see everything?
- [ ] Should we keep `mockInsights()` as a fast-path fallback when SwiftData has no mock records yet (before injection completes)?
- [ ] Is an app restart acceptable UX, or should we try to hot-swap services via `@Published`/`@StateObject` recreation?
- [ ] Should the mock toggle be a toggle (instant) or a button pair (inject/clear) with confirmation?
- [ ] Do we need mock ScreenTime data? `ScreenTimeManager` doesn't conform to a protocol — harder to mock.
- [ ] Should mock Journal entries include `sentiment` values for Foundation Models-based analysis?

## Recommendation

**Approach 4: Unified Mock Mode + Real Data Pipeline**

This gives the best outcome:

1. **One toggle** — simplest UX
2. **Factory pattern** — eliminates scattered checks, matches `APIClientFactory`
3. **Real pipeline on mock data** — catches bugs, produces realistic insights
4. **Expanded mock data** — all SwiftData domains covered

### Suggested Implementation Order

**Phase 1 (Core)**:
1. Create `HealthKitServiceFactory` in `Core/Services/`
2. Merge `mockDataInjected` into `mockMode` in `AppConfig`
3. Wire factory into all ViewModels (SleepVM, BurnVM, WellnessCalendarVM, InsightEngine, HomeView)
4. Update Profile toggle to single control

**Phase 2 (Data Expansion)**:
5. Expand `MockDataInjector` with SymptomEntry, FastingSession, AdherenceLog, JournalEntry
6. Remove `InsightEngine.mockInsights()` hard-coded shortcut
7. Verify InsightEngine generates real insights from mock data

**Phase 3 (Polish)**:
8. Add mock ScreenTime data (if protocol extraction is feasible)
9. Add "Mock Mode" banner/badge in tab bar for visual confirmation
10. Test full flow: toggle on → restart → browse all features → toggle off → restart → verify clean

## Research References

- Existing `MockHealthKitService`: `WellPlate/Core/Services/MockHealthKitService.swift`
- Existing `MockDataInjector`: `WellPlate/Core/Services/MockDataInjector.swift`
- Existing `StressMockSnapshot`: `WellPlate/Features + UI/Stress/Support/StressMockSnapshot.swift`
- Existing `APIClientFactory`: `WellPlate/Networking/` (pattern to mirror)
- `InsightEngine`: `WellPlate/Core/Services/InsightEngine.swift` (lines 34, 56-61)
- `SleepViewModel`: `WellPlate/Features + UI/Sleep/ViewModels/SleepViewModel.swift` (line 25 — no mock awareness)
- `HomeView`: `WellPlate/Features + UI/Home/Views/HomeView.swift` (lines 713-742 — partial mock, raw HK)
- `AppConfig`: `WellPlate/Core/AppConfig.swift` (two separate flags: mockMode + mockDataInjected)
- Prior brainstorm: `Docs/01_Brainstorming/260410-mock-data-injection-brainstorm.md`
