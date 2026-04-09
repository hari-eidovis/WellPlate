# Brainstorm: Mock Data Injection System

**Date**: 2026-04-10
**Status**: Ready for Planning

## Problem Statement

WellPlate currently has a `mockMode` toggle in Profile (DEBUG only) that routes the Groq nutrition API through a `MockAPIClient` serving JSON fixtures. This covers only one surface: the food AI response. It does **not** cover:

- SwiftData records: `FoodLogEntry`, `WellnessDayLog`, `StressReading`, etc.
- HealthKit data: steps, active energy, heart rate, HRV, blood pressure, sleep, respiratory rate
- Any screen populated purely from HealthKit (Burn, Sleep, Stress vitals, Home rings)

For testing and demo purposes, developers/testers need a single gesture from Profile to fill the entire app with realistic data and a second gesture to wipe it all clean.

## Core Requirements

- **Inject**: populate 30 days of realistic data across all major domains
  - SwiftData: `FoodLogEntry` (per-meal), `WellnessDayLog` (per-day), `StressReading`
  - HealthKit-backed screens: steps, active calories, heart rate, HRV, blood pressure, respiratory rate, sleep
- **Delete**: remove only injected mock data without touching real user data
- **Profile control**: two actions accessible from the Profile screen (inject + delete)
- **App-wide visibility**: all screens (Home, Burn, Stress, Sleep, History) should show data after injection
- **No schema disruption**: should not force SwiftData migration on real user devices
- Works in DEBUG builds; ideally gated behind `#if DEBUG`

## Constraints

- HealthKit writes on a real device require write permissions and a signed entitlement. This works on Simulator but is fragile on a real device running against a personal Health store.
- SwiftData migrations require careful versioning — adding columns risks breaking user data.
- Any approach must keep real user data completely safe (no accidental deletes).
- The existing `HealthKitServiceProtocol` already provides a clean seam for mocking.

---

## Approach 1: Mock HealthKit Service + SwiftData Injection (Tagged IDs)

**Summary**: Inject mock SwiftData records tagged by UUID (tracked in UserDefaults), and swap the real `HealthKitService` for a `MockHealthKitService` when mock mode is on.

**How it works**:
1. A `MockDataInjector` service injects `FoodLogEntry`, `WellnessDayLog`, `StressReading` into SwiftData and records their UUIDs in `UserDefaults` under a known key.
2. A `MockHealthKitService: HealthKitServiceProtocol` is implemented that returns hard-coded daily metric samples (steps, HRV, sleep, etc.) for the past 30 days.
3. `APIClientFactory` already conditionally returns mock/real API client. A parallel `HealthKitServiceFactory` is introduced that returns the appropriate implementation based on `AppConfig.mockDataInjected`.
4. ViewModels receive the service via DI (or access it via a shared factory).
5. Delete: fetch and delete all SwiftData records whose UUIDs are in UserDefaults, then clear the flag.

**Pros**:
- No SwiftData schema change needed (UUIDs tracked externally)
- Zero HealthKit write entitlement needed — mock service never talks to HKHealthStore
- Clean separation — toggle is independent of real data
- Can be enabled on real device and Simulator equally
- Cleanly testable

**Cons**:
- Requires `HealthKitServiceFactory` or environment injection to be plumbed through all ViewModels
- If a ViewModel holds a hard reference to `HealthKitService.shared`, swap is non-trivial
- UUID tracking in UserDefaults adds a small deletion complexity

**Complexity**: Medium
**Risk**: Medium (requires ViewModel DI audit)

---

## Approach 2: Separate Mock SwiftData Store + Mock HealthKit Service

**Summary**: Use a second, ephemeral `ModelContainer` (in-memory or on a separate SQLite file) for mock data, and toggle which container views read from.

**How it works**:
1. A `MockModelContainer` is initialized with an in-memory configuration.
2. Injecting mock data populates this secondary container.
3. A global `@Environment(\.modelContext)` override swaps in the mock context when mock mode is active.
4. Views see mock data without any pollution of the real SwiftData store.
5. Delete: re-create the in-memory container (or delete the mock SQLite file).

**Pros**:
- Perfect data isolation — real data is 100% safe
- Deletion is trivial (just drop the mock store)
- No UUID tracking needed

**Cons**:
- `@Environment(\.modelContext)` is injected at `WellPlateApp.swift` level — swapping it at runtime requires rebuilding the view hierarchy (effectively an app restart).
- In-memory containers don't survive app restart — data is lost if app terminates.
- Persistent mock SQLite requires additional app infra (separate URL, migration).
- Considerable SwiftUI environment plumbing.

**Complexity**: High
**Risk**: High (SwiftUI environment mutation at runtime is fragile)

---

## Approach 3: In-Memory Mock Data Overlay (ViewModel Layer)

**Summary**: A `MockDataStore` singleton holds in-memory mock values. ViewModels check this store first before querying SwiftData/HealthKit. No persistence writes happen.

**How it works**:
1. `MockDataStore.shared` is populated with 30 days of pre-built data (generated in-process, not from JSON).
2. Each ViewModel has a small adapter: `if mockDataStore.isActive { return mockDataStore.stressData } else { ... real fetch ... }`.
3. Deleting mock data just calls `MockDataStore.shared.clear()` — no persistence involved.
4. This is purely a runtime overlay.

**Pros**:
- No SwiftData schema changes, no HK write permissions, no DI refactor
- Cleanest from a data safety perspective
- Instant inject/delete (in-memory)
- Easiest to generate realistic, coherent data

**Cons**:
- Mock data evaporates on app restart — not useful for testing background refresh or widget updates
- Requires modifying every ViewModel (adding the guard check) — touches many files
- Doesn't test the actual data persistence path

**Complexity**: Medium
**Risk**: Low (but touches many VMs)

---

## Approach 4: HealthKit Simulator Write + SwiftData Direct Injection (No Tagging)

**Summary**: Write actual HealthKit samples using `HKHealthStore` (Simulator only), inject real SwiftData records, and use a distinct date range (e.g., Jan 2025) to isolate mock data for cleanup.

**How it works**:
1. Mock data uses a dedicated historical date range (not recent dates) — say 60–90 days ago.
2. Inject HK samples via `HKHealthStore.save()` for that range; inject SwiftData records for the same range.
3. Delete: fetch HK objects with a date range predicate and delete them; fetch SwiftData records with the same date range.
4. No tagging, no HealthKit entitlement special cases (Simulator allows HK writes freely).

**Pros**:
- Data goes through the real pipeline — tests actual HealthKit and SwiftData code paths
- No schema change needed (date range is the identifier)
- Clean deletion strategy

**Cons**:
- Only works in Simulator — HK write entitlement is needed on real device
- Date range trick means Home/dashboard might show data "30 days ago" rather than today — UI shows empty today
- Mock data for "today" would require choosing current dates, which conflicts with real data
- Simulator-only significantly limits usefulness for on-device demos

**Complexity**: Medium
**Risk**: Medium (Simulator-only + date range confusion)

---

## Recommended Hybrid: Approach 1 + Approach 3

**Use Approach 1 for SwiftData** (real persistence, tagged UUIDs) **and Approach 3 for HealthKit** (in-memory mock service). This gives:

- SwiftData injection persists across app restarts (good for demo)
- HealthKit data is served from a mock service (no entitlement issues, works on any device)
- Deletion is simple: delete tagged SwiftData records + set `AppConfig.mockDataInjected = false`
- The existing `HealthKitServiceProtocol` seam means the HealthKit swap is surgical

**Key implementation pieces**:
1. `AppConfig.mockDataInjected: Bool` — new UserDefaults-backed flag
2. `MockDataInjector` — generates and inserts SwiftData records, saves their UUIDs
3. `MockHealthKitService: HealthKitServiceProtocol` — returns canned 30-day metric samples
4. `HealthKitServiceFactory` — returns real or mock service based on flag
5. Plumb `HealthKitServiceFactory` into affected ViewModels (HomeViewModel, StressViewModel, BurnViewModel, SleepViewModel)
6. Profile screen: "Inject Mock Data" / "Clear Mock Data" buttons (DEBUG only)

---

## Edge Cases to Consider

- [ ] User has real data today — mock data for today would double-count (collision)
- [ ] App restart clears in-memory HealthKit mock → screens go empty → confusing
  - Mitigation: `AppConfig.mockDataInjected` flag persists → services know to serve mock on next launch
- [ ] Partial injection failure (e.g., SwiftData write fails mid-inject) → inconsistent state
  - Mitigation: wrap injection in a transaction; rollback on failure
- [ ] User accidentally taps "Inject" multiple times → duplicate SwiftData records
  - Mitigation: guard with `AppConfig.mockDataInjected` check; disable button if already injected
- [ ] Mock HK service called before injection flag is set (race condition on launch)
  - Mitigation: factory reads flag from UserDefaults synchronously
- [ ] HealthKit service is held as `let` constant in ViewModels → swap requires re-init
  - Audit needed: check if VMs use `.shared` or accept protocol via init
- [ ] Widget and ScreenTime extensions don't share the mock flag
  - Mitigation: store flag in a shared App Group UserDefaults if needed

## Open Questions

- [ ] Should mock data inject data for today or only historical days? (Impacts Home rings display)
- [ ] How should StressReading mock data interact with the StressLab feature?
- [ ] Should mock injection be available in RELEASE builds for App Store demo mode?
- [ ] Which ViewModels currently hard-reference `HealthKitService.shared` vs accept the protocol?
- [ ] Should the mock HealthKit service use fixed values or randomized-within-range for realism?

## Research References

- Existing `HealthKitServiceProtocol` seam: `WellPlate/Core/Services/HealthKitServiceProtocol.swift`
- Existing `APIClientFactory` pattern: `WellPlate/Networking/`
- Existing `AppConfig.mockMode`: `WellPlate/Core/AppConfig.swift`
- Existing `NutritionSourceDebugCard` in ProfileView: `WellPlate/Features + UI/Tab/ProfileView.swift`
- SwiftData models: `WellPlate/Models/` (FoodLogEntry, WellnessDayLog, StressReading)
