# Strategy: HealthKit Mental Wellbeing Integration (F2)

**Date**: 2026-04-07
**Source**: `Docs/01_Brainstorming/260407-mental-wellbeing-healthkit-brainstorm.md`
**Status**: Ready for Planning

---

## Chosen Approach

**Approach 2: Bidirectional Sync with Prefill** — Write the user's daily mood check-in to HealthKit as an `HKStateOfMind` sample on confirmation, and on page load, prefill the mood picker from the latest State of Mind sample in Health if today's mood hasn't been logged yet in SwiftData. Show a subtle "From Health" badge on the `MoodCheckInCard` when the mood was prefilled from an external source.

---

## Rationale

- **Approach 1 (write-only) rejected**: Too invisible — no user benefit beyond Apple Health interop. No feedback that anything happened, no value from other apps' data.
- **Approach 2 chosen**: Adds real value (cross-app prefill, sync indicator) at very low cost. Only 5 files touched, zero new files, ~1–2 days effort. Matches the roadmap's "thin integration layer" intent.
- **Approach 3 (full hub + PHQ-9/GAD-7) deferred**: The `healthRecords` App Store entitlement for clinical FHIR data is hard to get approved for a wellness app. PHQ-9/GAD-7 display is valuable but requires design and compliance work that pushes this beyond F2's scope. The 30-day mood chart can be added as a natural extension later.
- **Approach 4 (mood as stress factor) deferred**: Changing the composite stress formula is a product decision with regression implications. Out of scope for F2.

**Key trade-off accepted**: Valence → MoodOption reverse-mapping is lossy (continuous → 5-step). We snap to nearest and this is good enough — users logging in Apple Mindfulness get a reasonable prefill, not a guarantee of exact fidelity.

---

## Affected Files & Components

### Modified (5 files)

| File | Changes |
|------|---------|
| `WellPlate/Core/Services/HealthKitServiceProtocol.swift` | Add `writeMood(_ mood: MoodOption) async throws` and `fetchTodayMood() async throws -> MoodOption?` to the protocol |
| `WellPlate/Core/Services/HealthKitService.swift` | 1. Add `HKStateOfMind` to `readTypes` (as `HKSampleType`). 2. Create new `shareTypes` property with `HKStateOfMind`. 3. Update `requestAuthorization(toShare: shareTypes, read: readTypes)`. 4. Implement `writeMood` — map `MoodOption` → valence, create `HKStateOfMind` sample with `kind: .dailyMood`, save via `store.save()`. 5. Implement `fetchTodayMood` — query today's `HKStateOfMind` samples, take most recent, reverse-map valence → nearest `MoodOption`. |
| `WellPlate/Core/Services/MockHealthKitService.swift` | Add `writeMood` (no-op) and `fetchTodayMood` (returns `nil`) stubs |
| `WellPlate/Features + UI/Home/Views/HomeView.swift` | 1. In `logMoodForTodayIfNeeded`: after SwiftData save succeeds, fire-and-forget `Task { try? await HealthKitService().writeMood(mood) }` (guarded by `HealthKitService.isAvailable`). 2. In `refreshTodayMoodState`: if `moodRaw == nil`, try `HealthKitService().fetchTodayMood()` → if non-nil, set `selectedMood` and add "from Health" flag. |
| `WellPlate/Shared/Components/MoodCheckInCard.swift` | Add optional `isFromHealth: Bool = false` parameter. When `true`, show a small "From Health" caption badge below the header. |

### Not modified

- `WellnessDayLog.swift` — no schema changes. The SwiftData model stores `moodRaw` as before; Health sync is a side-effect, not a data model change.
- `HomeViewModel.swift` — mood logic stays in HomeView (matches existing pattern where mood, hydration, and coffee are all managed directly in the view).
- `WellPlateApp.swift` — no new ModelContainer schemas.

---

## Architectural Direction

### Data Flow

```
User taps mood → MoodCheckInCard.onChange → HomeView.logMoodForTodayIfNeeded
                                                │
                                                ├── SwiftData: todayLog.moodRaw = mood.rawValue (primary)
                                                └── HealthKit: writeMood(mood) (fire-and-forget side-effect)

App load → HomeView.refreshTodayMoodState
              │
              ├── SwiftData: check moodRaw (authoritative)
              │     ├── non-nil → use it, done
              │     └── nil → fall through to HealthKit
              │
              └── HealthKit: fetchTodayMood()
                    ├── non-nil → prefill selectedMood, set isFromHealth = true
                    └── nil → no mood today
```

**SwiftData is always authoritative.** HealthKit is a write-through side-effect on save, and a fallback prefill source on load. If HealthKit fails, nothing breaks — mood logging continues via SwiftData alone.

### MoodOption ↔ Valence Mapping

| MoodOption | rawValue | HK Valence |
|------------|----------|------------|
| `.awful`   | 0        | -1.0       |
| `.bad`     | 1        | -0.5       |
| `.okay`    | 2        |  0.0       |
| `.good`    | 3        |  0.5       |
| `.great`   | 4        |  1.0       |

**Reverse mapping** (valence → MoodOption): snap to nearest using `round((valence + 1.0) * 2.0)` clamped to 0...4.

### HealthKit Authorization

Current: `store.requestAuthorization(toShare: [], read: readTypes)`
After: `store.requestAuthorization(toShare: shareTypes, read: readTypes)`

Where `shareTypes` = `Set([HKStateOfMind.sampleType()])` (or the appropriate type method).

This changes the authorization dialog to include "State of Mind" under both read and write. This happens at the existing onboarding authorization point — no new permission timing.

---

## Design Constraints

1. **SwiftData stays authoritative** — never overwrite a SwiftData mood from HealthKit. HealthKit is only used for prefill when SwiftData has no mood for today.
2. **Fire-and-forget writes** — `writeMood` failures are silently logged, never surfaced to the user. The `try?` pattern ensures HK write errors don't affect the mood logging UX.
3. **Guard on availability** — all HealthKit calls gated behind `HealthKitService.isAvailable` (returns `false` on Simulator).
4. **No new files** — everything fits in existing service/view files. The integration is thin enough that a new `MoodSyncService` would be overengineering.
5. **"From Health" badge is informational only** — it shows when prefilled, disappears once user confirms (at which point we write to both SwiftData and HK, and it's "their" mood now).
6. **Mock mode** — `MockHealthKitService` returns `nil` from `fetchTodayMood` and no-ops on `writeMood`. No mock mood data needed.

---

## Non-Goals

- **PHQ-9/GAD-7 assessment display** — requires `healthRecords` entitlement, significant compliance design; deferred to a future feature
- **30-day mood trend chart from HealthKit** — useful but adds new UI surface; can be added alongside F3 (Circadian Stack) as a mood history card
- **Mood as stress factor** — changing the stress score formula is a separate product decision
- **Multiple-mood-per-day support** — each confirmation overwrites (consistent with current single-mood-per-day model)
- **Mood editing/deletion from WellPlate synced to HealthKit** — only forward writes, no delete sync
- **HKStateOfMind labels/associations/arousal** — only map `valence` and `kind` (.dailyMood). Labels would require a richer mood vocabulary than our 5 emojis provide.

---

## Open Risks

| Risk | Mitigation |
|------|------------|
| Authorization dialog now mentions "State of Mind" — users might be surprised or decline | Add a brief explanation in onboarding copy: "WellPlate syncs your mood with Apple Health" |
| `HKStateOfMind` API surface may differ from expectations (iOS 18 was v1) | Verify exact API signature during implementation — use Xcode autocomplete, not assumptions |
| Prefill from other apps may show unexpected mood (user logged "sad" in Mindfulness 4 hours ago, but is feeling better now) | Badge says "From Health" — the user taps to override. The prefill is a suggestion, not a commitment. |
| HealthKit write throttling / background restrictions | Writes happen in foreground (user just tapped) — no throttling concern |
