# Brainstorm: Apple Watch Activity & Health Data in Stress Insights

**Date**: 2026-05-05 (pruned 2026-05-09)  
**Status**: 🟢 Pruned — Ready for Strategize  
**Scope**: Add an "Activity & Body Signals" section to the Stress tab's Insights sheet, surfacing workout history + Watch-exclusive health stats from HealthKit  
**Depends on**: Existing `HealthKitService`, `StressView.insightsSheet`, `StressViewModel`

> **2026-05-09 prune**: Cross-checked every signal against the current `HealthKitService` fetch surface and stress-relevance bar. Trimmed from ~53 candidate items to 29 keepers. Dropped items moved to a §13 "Deprioritized" appendix with one-line reasons so rationale is preserved without bloating the in-scope plan. Headline correction: **sleep stages are already fetched** (`DailySleepSummary.coreHours/remHours/deepHours`) — reframed from "new fetch" to "surface existing data."

---

## 1. The Problem

The Insights sheet in the Stress tab currently shows:
- Vitals Grid (HR, HRV, Sleep, Activity summary)
- Stress Factors (Exercise, Sleep, Diet, Screen Time)
- Circadian Health
- 7-Day Trend + Day Chart

**What's missing**: Any visibility into *specific workouts* the user did — type, duration, calories, timing — and Watch-exclusive physiological signals that are stress-relevant. Users with Apple Watch have a goldmine of data sitting in HealthKit that we never surface.

---

## 2. What Can We Fetch? — Complete HealthKit Data Inventory

### 2A. Workout Data (HKWorkout)

HealthKit stores **every recorded workout** (Apple Watch, third-party apps like Strava, Nike Run Club, etc.) as `HKWorkout` objects. These are queryable from iPhone via the shared HealthKit store — **no Watch companion app needed**.

| Property | Type | What it gives us |
|----------|------|------------------|
| `workoutActivityType` | `HKWorkoutActivityType` | 80+ types: `.running`, `.walking`, `.cycling`, `.yoga`, `.highIntensityIntervalTraining`, `.swimming`, `.functionalStrengthTraining`, etc. |
| `startDate` / `endDate` | `Date` | Exact workout window — crucial for correlating "did they exercise before/after stress spike" |
| `duration` | `TimeInterval` | Seconds of actual workout time |
| `totalEnergyBurned` | `HKQuantity` | Active calories (kcal) |
| `totalDistance` | `HKQuantity` | For distance-based workouts (run, walk, cycle, swim) |
| `metadata` | `[String: Any]` | Indoor/outdoor flag, elevation gain, weather, etc. |
| `sourceRevision` | `HKSourceRevision` | Which app recorded it (Apple Watch Workout app, Strava, etc.) |
| `workoutActivities` | `[HKWorkoutActivity]` | Multi-activity workouts (triathlon, pool+open water) — individual segments |

**Associated data we can query per-workout:**

| Associated Query | Data | Stress Relevance |
|-----------------|------|-------------------|
| `HKQuantityType(.heartRate)` within workout interval | Intra-workout HR samples | See HR zone distribution, recovery rate |
| `HKWorkoutRoute` | GPS coordinates + altitude | Outdoor vs. indoor, elevation gain |
| `HKQuantityType(.activeEnergyBurned)` | Granular energy burn | More precise than the workout summary |

### 2B. Watch-Exclusive Health Stats (Queryable from iPhone)

These are Apple Watch sensor data types that are **written by watchOS** but stored in the **shared HealthKit store** and fully readable from iPhone. Pruned to stress-relevant signals only — see §13 for items dropped from this section.

| HKQuantityTypeIdentifier | What | Unit | Stress Relevance | Currently Fetched? |
|--------------------------|------|------|-------------------|-------------------|
| `.vo2Max` | Cardiorespiratory fitness | mL/(kg·min) | **HIGH** — strong predictor of stress resilience; declining VO2Max correlates with increased allostatic load | ❌ No |
| `.walkingHeartRateAverage` | Avg HR during walks | count/min | **HIGH** — elevated walking HR (above personal baseline) is an early sign of autonomic stress, overtraining, or illness | ❌ No |
| `.physicalEffort` (iOS 17+) | Estimated effort rating | `HKUnit.appleEffortScore()` | **HIGH** — Apple's own perceived exertion metric; required for ACWR (§11C) | ❌ No |
| `.appleSleepingWristTemperature` | Overnight wrist temp deviation | °C | **MEDIUM-HIGH** — temp elevations can signal illness, cycle phase, or physiological stress (gate via §11B) | ❌ No |
| `.environmentalAudioExposure` | Ambient noise level | dBASPL | **MEDIUM** — sustained noise (>80 dB) is a documented cortisol trigger | ❌ No |
| `.appleStandTime` | Hours with ≥1 min standing | hrs | **LITE** — cheap to add; sedentary behavior is a stress amplifier | ❌ No |

### 2D. Additional Signals (added 2026-05-08, pruned 2026-05-09)

These were not in the original inventory but are equally Watch/HealthKit-readable and stress-relevant. Pruned to keepers only — see §13 for items dropped from this section.

| HK Identifier | What | Stress Relevance | Currently Fetched? |
|---|---|---|---|
| `.heartRateRecoveryOneMinute` (iOS 16+) | HR drop 1 min after peak workout | **HIGH** — gold-standard parasympathetic/autonomic recovery indicator. Drops when chronically stressed or overtrained | ❌ No |
| `HKCategoryType(.mindfulSession)` | Logged meditation / breathwork sessions (Apple Mindfulness + 3rd party) | **HIGH** — closes the loop: lets us correlate intervention vs. stress score | ❌ No |
| Symptom categories: `.anxiety`, `.fatigue`, `.moodChanges`, `.headache` | User self-logs from Health app | **HIGH** — most direct stress signal of all (the user is literally telling us their state). Trim to these 4 high-signal symptoms; defer `.rapidPoundingOrFluttering`, `.shortnessOfBreath`, `.sleepChanges` to phase 2 | ❌ No |
| `.menstrualFlow` | Cycle phase tracking | **HIGH (interpretive)** — luteal phase naturally raises wrist temp ~0.3°C and lowers HRV. Without cycle gating, Tier 2 wrist-temp/HRV cards false-positive ~50% of users monthly. Single signal sufficient for phase inference; skip `.basalBodyTemperature`, `.cervicalMucusQuality`, `.ovulationTestResult` (redundant for our use case) | ❌ No |
| Sleep **stages** (REM / Deep / Core) | Stage breakdown per night | **HIGH** — low REM% is a stronger recovery/stress signal than total hours | ✅ **Already fetched** — `DailySleepSummary.coreHours/remHours/deepHours` exists. **Reclassify**: not a new fetch, just a display/surface task in StressView |
| Cardiac event flags: `.lowHeartRateEvent`, `.highHeartRateEvent`, `.irregularHeartRhythmEvent` | Watch-generated cardiac event flags | **LITE** — high signal when present but rare; small implementation cost, worth including | ❌ No |

> **Implementation note for sleep stages**: To unlock §11F (sleep onset latency), `fetchSleep` needs one extension — its `stageMap` currently filters out `HKCategoryValueSleepAnalysis.inBed` samples. Adding `.inBed` as a parsed stage is a 2-line change. Sleep efficiency falls out of existing data once `inBed` duration is captured.

### 2C. Data We Already Fetch (for reference)

| Identifier | Currently Used For |
|-----------|-------------------|
| `.stepCount` | Exercise factor scoring |
| `.activeEnergyBurned` | Exercise factor scoring |
| `.appleExerciseTime` | Exercise minutes display |
| `.heartRate` | Vitals grid, 30-day trend |
| `.restingHeartRate` | Vitals grid, 30-day trend |
| `.heartRateVariabilitySDNN` | Vitals grid, stress research anchor |
| `.bloodPressureSystolic/Diastolic` | Vitals grid |
| `.respiratoryRate` | Vitals grid |
| `.dietaryWater` | Hydration tracking |
| `.timeInDaylight` | Circadian health score |
| `HKCategoryType.sleepAnalysis` | Sleep factor scoring |
| `HKStateOfMind` | Mood sync |

---

## 3. HealthKit vs. Alternatives — Should We Use Something Else?

### Option A: **HealthKit Only (iPhone)** ← RECOMMENDED

| Pros | Cons |
|------|------|
| **No Watch target needed** — query from iPhone | Need to add `HKWorkoutType` to `readTypes` set + add Info.plist reason strings |
| **Latency is fine** — user said latency is not an issue | Historical queries can return large data sets (need pagination / date filtering) |
| Unified API — workouts + vitals in one framework | Can't subscribe to real-time Watch sensor streams |
| Covers 100% of what Apple Watch records | Some data types require Watch to be worn (can't fallback gracefully) |
| Battle-tested in our codebase — existing `HealthKitService` pattern | Additional permission prompt wording may confuse users |

### Option B: WorkoutKit (iOS 17+)

WorkoutKit is for **building** custom workouts and scheduling them, NOT for querying historical workout data. It's the wrong tool for reading workout history. **Skip this for the Insights use case.**

### Option C: WatchConnectivity (WCSession)

Requires a Watch companion target. Adds deployment complexity. Only useful if we need *real-time streaming* (e.g., live HR during a session). For historical data surfacing — completely unnecessary. **Skip this.**

### Option D: HealthConnect (Android)

Not applicable — iOS only project.

### Verdict: **HealthKit is the only correct answer.** It's the single source of truth for all workout + health data on Apple platforms. Since latency is not an issue, batch queries via `HKSampleQuery` / `HKStatisticsCollectionQuery` are perfect.

---

## 4. What to Surface in the Insights Section

### Tier 1 — High-value, low-effort (MVP)

These give the most stress-relevant value with the least implementation work:

#### 4A. **Workout History Card** (new section in Insights sheet)
- Fetch today's + last 7 days of `HKWorkout` objects
- Display: workout type icon + name, duration, calories, time of day
- Show "X workouts this week" summary badge
- Tap → detail view with all workouts
- **Stress correlation**: "On days you exercised, your average stress was X vs. Y on rest days"

#### 4B. **VO2 Max Trend** (new vital card)
- Fetch `.vo2Max` samples (Apple Watch auto-estimates these during outdoor walk/run)
- Show current value + 30-day trend sparkline
- Classification: Poor → Fair → Good → Excellent (based on age/gender norms)
- **Stress angle**: "Your cardio fitness is [trending up] — higher VO2Max is linked to better stress resilience"

#### 4C. **Walking Heart Rate** (new vital card)
- Fetch `.walkingHeartRateAverage` daily samples
- Show current value + baseline deviation
- **Stress angle**: "Your walking HR is [8 bpm above your baseline] — this may indicate elevated physiological stress or incomplete recovery"

### Tier 2 — Medium-value, medium-effort

#### 4D. **Wrist Temperature Deviation** (if data available)
- `.appleSleepingWristTemperature` — Watch logs baseline deviations during sleep
- Show as a subtle indicator: "Your overnight temp was +0.3°C above baseline"
- **Stress angle**: Elevated wrist temp → immune activation, cycle-related, or stress

#### 4E. **Noise Exposure Summary**
- `.environmentalAudioExposure` — daily max/avg noise level
- Show warning if >80 dB sustained
- **Stress angle**: Sustained noise is a documented cortisol trigger

#### 4F. **Physical Effort Score** (iOS 17+)
- `.physicalEffort` — Apple's own perceived exertion metric
- Show per-workout or daily aggregate
- **Stress angle**: High effort scores without adequate recovery → overtraining stress

### Tier 3 — Nice-to-have, for later phases

- SpO2 overnight trends (`.oxygenSaturation`)
- Stand hours tracking (`.appleStandTime`)  
- Walking steadiness changes
- Workout route maps (HKWorkoutRoute → MapKit)
- Per-workout HR zone analysis

---

## 5. Proposed Architecture

### 5A. Where it lives in the Insights Sheet

Current structure of `insightsSheet` in `StressView.swift`:

```
1. VITALS & ACTIVITY          (existing grid)
2. STRESS FACTORS             (existing cards)
3. CIRCADIAN HEALTH           (existing card)
4. 7-DAY TREND                (existing chart)
5. STRESS THROUGH THE DAY     (existing chart)
```

**Proposed addition** — insert between VITALS and FACTORS:

```
1. VITALS & ACTIVITY          (existing — add VO2Max + Walking HR cards)
2. ★ RECENT WORKOUTS          (NEW section — workout list)
3. ★ BODY SIGNALS             (NEW section — wrist temp, noise, effort)
4. STRESS FACTORS             (existing cards)
5. CIRCADIAN HEALTH           (existing card)
6. 7-DAY TREND                (existing chart)
7. STRESS THROUGH THE DAY     (existing chart)
```

### 5B. Data Flow

```
HealthKitService                          StressViewModel
  + fetchWorkouts(for:)        →          + workoutHistory: [WorkoutSummary]
  + fetchVO2Max(for:)          →          + vo2MaxHistory: [DailyMetricSample]
  + fetchWalkingHR(for:)       →          + walkingHRHistory: [DailyMetricSample]
  + fetchWristTemp(for:)       →          + wristTempHistory: [DailyMetricSample]
  + fetchNoiseExposure(for:)   →          + noiseHistory: [DailyMetricSample]
                                              ↓
                                          StressView.insightsSheet
                                            → WorkoutHistorySection
                                            → BodySignalsSection
```

### 5C. New Model

```swift
struct WorkoutSummary: Identifiable {
    let id: UUID
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let duration: TimeInterval      // seconds
    let totalEnergyBurned: Double?  // kcal
    let totalDistance: Double?       // meters
    let sourceName: String          // "Apple Watch", "Strava", etc.
    
    var displayName: String { ... }  // "Outdoor Run", "Yoga", etc.
    var displayIcon: String { ... }  // SF Symbol mapping
    var durationFormatted: String { ... }
}
```

### 5D. HealthKit Permission Changes (updated 2026-05-09)

Current `readTypes` set needs these additions, organized by source section:
```swift
// §2A Workouts
HKWorkoutType.workoutType()

// §2B Watch-exclusive vitals (kept after prune)
.vo2Max
.walkingHeartRateAverage
.physicalEffort                          // iOS 17+
.appleSleepingWristTemperature
.environmentalAudioExposure
.appleStandTime                          // lite

// §2D Added signals (kept after prune)
.heartRateRecoveryOneMinute              // iOS 16+
HKCategoryType(forIdentifier: .mindfulSession)
HKCategoryType(forIdentifier: .anxiety)
HKCategoryType(forIdentifier: .fatigue)
HKCategoryType(forIdentifier: .moodChanges)
HKCategoryType(forIdentifier: .headache)
HKCategoryType(forIdentifier: .menstrualFlow)
HKCategoryType(forIdentifier: .lowHeartRateEvent)
HKCategoryType(forIdentifier: .highHeartRateEvent)
HKCategoryType(forIdentifier: .irregularHeartRhythmEvent)

// Sleep stages — NO new permission needed
// .sleepAnalysis is already in readTypes; we just need to extend
// fetchSleep's stageMap to include HKCategoryValueSleepAnalysis.inBed
```

> ⚠️ Adding types to `readTypes` will trigger a **new permission prompt** the first time after update. The prompt shows all requested types — existing ones show as already granted, new ones as toggleable. This is non-disruptive.

> ⚠️ **App Store risk** (see §11K): symptom and menstrual reads tighten reviewer scrutiny on `NSHealthShareUsageDescription`. Vague rationales get rejected. Need explicit per-feature purpose copy ready before submission.

---

## 6. Stress Correlation Opportunities

The real value isn't just showing workouts — it's connecting them to stress patterns:

| Correlation | Data Sources | Insight Example |
|------------|--------------|-----------------|
| **Workout ↔ Stress Score** | Workouts + StressReading | "On workout days, your stress averages 38 vs. 62 on rest days" |
| **Workout Timing ↔ Sleep** | Workout startDate + Sleep | "Evening workouts (after 7 PM) correlate with 45 min less sleep" |
| **VO2Max Trend ↔ Stress Trend** | VO2Max + StressReading | "As your cardio fitness improved, your average stress dropped 12%" |
| **Walking HR ↔ Recovery** | Walking HR baseline vs. current | "Walking HR is elevated — you may benefit from a recovery day" |
| **Workout Frequency ↔ HRV** | Workout count + HRV | "Your HRV improves after 3+ workout days per week" |

These can be added to `InsightEngine`'s `detectCorrelations()` method using the existing `Pair` pattern — just add new extractors for workout-related metrics in `WellnessDaySummary`.

---

## 7. Data Availability Expectations

| Signal | Requires Apple Watch? | Requires specific activity? | Update frequency |
|--------|----------------------|---------------------------|-----------------|
| HKWorkout | No (any source can record) | User must record a workout | Per-workout |
| VO2Max | **Yes** (Watch estimates it) | Outdoor walk/run ≥20 min | ~Weekly estimate |
| Walking HR Average | **Yes** | User must walk with Watch | Daily when walking occurs |
| Wrist Temperature | **Yes** (Series 8+, Ultra) | Wearing Watch to sleep | Nightly |
| Noise Exposure | **Yes** | Passive (always-on) | Every ~15 min |
| Physical Effort | **Yes** (watchOS 10+) | During workouts only | Per-workout |

**Graceful degradation**: If user doesn't have Apple Watch, workout data may still exist from third-party apps (Strava, Nike). VO2Max and Watch-exclusive signals will simply return empty arrays — we already handle this pattern with `.timeInDaylight`.

---

## 8. Implementation Effort Estimate

| Component | Files | Effort |
|-----------|-------|--------|
| Add workout fetch to `HealthKitServiceProtocol` + `HealthKitService` | 2 | Small |
| Add Watch vitals fetch (VO2Max, Walking HR, etc.) | 2 | Small |
| `WorkoutSummary` model | 1 | Trivial |
| Update `readTypes` + permission strings | 2 | Trivial |
| Add workout data to `StressViewModel` | 1 | Medium |
| `WorkoutHistorySection` view component | 1 | Medium |
| `WorkoutDetailView` (optional, tap-through) | 1 | Medium |
| Extend `WellnessDaySummary` for correlations | 1 | Small |
| Update `InsightEngine` correlation pairs | 1 | Small |
| Add to `MockHealthKitService` + snapshots | 2 | Small |
| **Total** | **~12 files** | **~3-4 days** |

---

## 9. Key Decisions Needed

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| D1 | Should workouts appear on the main StressView scroll or only in Insights sheet? | Main view / Insights only / Both | **Insights only** for MVP — keep main view focused on the score |
| D2 | Should we add workout data as a 5th stress factor? | Yes (weighted) / No (display only) | **No for MVP** — display first, validate correlation, then consider factoring in Phase 2 |
| D3 | How many days of workout history? | 7 / 14 / 30 | **7 days** for the Insights section, **30 days** for detail view |
| D4 | Should VO2Max/Walking HR go in the existing Vitals grid or a new "Body Signals" section? | Vitals grid / New section | **Vitals grid** — they're vitals, keep them together. Add a 3rd row |
| D5 | Filter workouts by source? | All sources / Apple Watch only | **All sources** — Strava/Nike workouts are equally valid |

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| User denies new HK permissions | Workout section shows empty | Graceful empty state: "Allow workout access in Settings to see your activity" |
| No Apple Watch → no VO2Max/Walking HR | Cards show "—" | Same pattern as daylight: card only appears if data exists |
| Large workout history (marathon runner, 1000+ workouts) | Memory spike | Date-filter to 30 days max, use `limit` parameter |
| Workout type mapping (80+ types → icons) | Maintenance burden | Start with top 15 activity types, fallback to generic `.figure.mixed.cardio` |
| HKWorkout changes in future iOS | API stability | `HKWorkout` has been stable since iOS 8, very low risk |

---

## 11. Interpretation Edge Cases (added 2026-05-08)

The data inventory is only half the problem — interpreting it correctly is the other half. These edge cases will silently corrupt insights if unhandled.

### 11A. Off-wrist gaps vs. real zeros
VO2Max, Walking HR, HRV, and sleep all return empty arrays when the Watch wasn't worn (charging, overnight off, in pocket). The current "graceful empty state" pattern conflates this with "permission denied" and "user has no Apple Watch." We need a distinct affordance: *"Watch wasn't worn — no data for this period"* — otherwise dips will be misread as stress spikes.

**Detection heuristic**: presence of *any* HR sample in a window confirms wear; total absence across HR + step + activeEnergy suggests off-wrist.

### 11B. Cycle-phase-aware baselines
Wrist temp +0.3°C and HRV −15% in the luteal phase is **physiologically normal**. Without cycle gating, Tier 2 wrist-temp and HRV cards will false-alarm for ~50% of users every month. Either:
- Suppress luteal-phase deltas from "stress" interpretation, OR
- Show two baselines (follicular vs. luteal) for those users.

Requires reading `.menstrualFlow` to infer cycle day.

### 11C. Acute:Chronic Workload Ratio (ACWR)
Derivable from existing workout data with **no new fetch**:
```
ACWR = (7-day load) / (28-day load)
```
where *load* = `duration × physicalEffort` (or `duration × avg HR` fallback). Ratio >1.5 is a documented overtraining/injury risk window. Cheap, high-value insight.

### 11D. Workout-to-bedtime gap
The doc's correlation table mentions "evening workouts ↔ less sleep" but doesn't define the cutoff. Literature uses **≤3 hours before sleep onset** as the disruptive threshold — codify this rather than "after 7 PM."

### 11F. Sleep onset latency & sleep efficiency
Both derivable from existing `.sleepAnalysis` data, neither currently surfaced. **Caveat**: the current `fetchSleep` `stageMap` filters out `HKCategoryValueSleepAnalysis.inBed` samples — onset latency requires extending the map to capture `.inBed`. Efficiency falls out for free once that's done.
- **Onset latency** = (first `.asleep*` sample) − (`.inBed` start). >30 min is an anxiety/stress signature.
- **Efficiency** = (time asleep) / (time in bed). <85% suggests fragmented sleep.

### 11I. Recovery days between high-intensity sessions
Back-to-back HIIT or strength days raise allostatic load. Flagging consecutive `.physicalEffort` ≥7 days (or HR-derived equivalent) without a recovery day would be a useful "your body needs a break" insight.

### 11J. Workout HR zones (Z1–Z5)
The doc lists intra-workout HR samples but not the zone split. **Time in Zone 5 vs. Zone 2 has very different recovery costs** — a 60-min Z2 walk is restorative, a 60-min Z5 effort is stressful. Bin HR samples against `(220 − age) × {0.5, 0.6, 0.7, 0.8, 0.9}`.

### 11K. Permission rationale strings (App Store risk)
Doc §5D notes the new permission sheet is "non-disruptive" but doesn't propose copy. iOS uses a single `NSHealthShareUsageDescription` string for *all* read types — App Store reviewers reject vague strings when symptom or menstrual data is requested. Need explicit per-feature justification language ready before submission.

### 11L. Symptom + StateOfMind double-log dedup
If a user logs both an `.anxiety` symptom AND a low-valence `HKStateOfMind` within the same hour, they shouldn't count twice in the stress signal. Need a dedup window (suggest 1 hr).

### 11M. Third-party workout double-counting
Strava + Apple Watch can both record the same run as separate `HKWorkout` entries. Need source-deduplication by overlapping time window (>50% time overlap = same workout, prefer Apple Watch source for HR fidelity, prefer Strava for GPS).

### 11N. VO2Max age/sex normalization
The "Poor → Excellent" classification in Tier 1 §4B requires Cooper Clinic normative tables, which need **DOB + biological sex** from `HKCharacteristicType`. Missing characteristic data → fall back to absolute trend without classification.

---

## 12. Top-5 Priorities (added 2026-05-08)

If we only add 5 things from §2D + §11 to MVP, in priority order:

1. **Symptom logging** (`.anxiety`, `.fatigue`, `.headache`, `.moodChanges`) — highest signal-per-line-of-code, user-authored ground truth.
2. **Mindful sessions** (`HKCategoryType(.mindfulSession)`) — closes the loop between intervention and stress score; enables "did meditating help" causal questions.
3. **Heart Rate Recovery 1-min** (`.heartRateRecoveryOneMinute`) — best autonomic recovery indicator the Watch produces.
4. **Sleep stages + onset latency** — already have raw data via `.sleepAnalysis`, just need parsing. Highest leverage from existing fetch.
5. **Cycle-phase awareness** — not a new card, but a *gate* on wrist-temp/HRV interpretation so Tier 2 doesn't false-alarm for half the user base.

---

## 13. Deprioritized — Considered but Dropped (2026-05-09)

These items were in earlier drafts but cut after cross-checking against the current `HealthKitService` fetch surface and our stress-relevance bar. Preserved here so future contributors don't re-propose them without seeing the rationale.

### Dropped from §2B (mobility / niche metrics — fall risk, not stress)

| Item | Reason cut |
|---|---|
| `.appleMoveTime` | Overlaps with `.appleExerciseTime` (already fetched) |
| `.walkingDoubleSupportPercentage` | Fall-risk metric, not stress |
| `.walkingSpeed` | Low signal; drift takes weeks to register |
| `.walkingStepLength` | Low signal |
| `.walkingAsymmetryPercentage` | Fall risk |
| `.stairAscentSpeed` / `.stairDescentSpeed` | Low signal for stress |
| `.sixMinuteWalkTestDistance` | Niche clinical metric; ~0% organic user data |
| `.appleWalkingSteadiness` | Fall risk |
| `.oxygenSaturation` (SpO2) | Mostly redundant with HRV/RR for stress purposes |
| `.headphoneAudioExposure` | Marginal value over `.environmentalAudioExposure` |
| `.numberOfAlcoholicBeverages` | Self-logged, near-zero user adoption in practice |

### Dropped from §2D (added signals — niche, redundant, or out-of-scope)

| Item | Reason cut |
|---|---|
| `HKElectrocardiogramType` (ECG) | User-initiated only; very sparse data |
| `.atrialFibrillationBurden` | Niche; requires AFib history flag enabled in Health app |
| `.audioExposureEvent`, `.headphoneAudioExposureEvent` | Continuous `.environmentalAudioExposure` already covers it |
| Running form (`.runningPower`, `.runningStrideLength`, `.runningVerticalOscillation`, `.runningGroundContactTime`) | Runner-only audience; weak stress signal |
| `.basalEnergyBurned` (BMR) | Slow-moving baseline; weak stress link |
| `.bodyMass`, `.bodyFatPercentage`, `.leanBodyMass` | Slow drift; weak stress link |
| `HKWorkoutRoute` (standalone) | Already covered as an associated query in §2A; map UI is Tier 3 polish |
| `.cyclingFunctionalThresholdPower` (FTP) | Cyclist-only; narrow audience |
| Symptoms: `.rapidPoundingOrFlutteringHeartbeat`, `.shortnessOfBreath`, `.sleepChanges` | Trimmed from initial scope; the 4 retained symptoms (`.anxiety`, `.fatigue`, `.moodChanges`, `.headache`) capture the bulk of stress signal. Add later if needed |
| Menstrual cycle: `.basalBodyTemperature`, `.cervicalMucusQuality`, `.ovulationTestResult` | `.menstrualFlow` alone is sufficient for phase inference (luteal vs. follicular gating) |

### Dropped from §11 (edge cases — speculative or marginal)

| Item | Reason cut |
|---|---|
| 11E. First-morning HR vs. resting HR | `.restingHeartRate` (24-hr aggregate, already fetched) is a sufficient proxy; marginal lift for the implementation cost |
| 11G. HRV overnight vs. daytime split | Watch already biases HRV samples to sleep; Apple's own display averages similarly. Refinement, not a fix |
| 11H. Time-zone / travel jet-lag detection | Speculative; computable post-MVP if signal proves out |

### Pruning summary

| Section | Original | Kept | Dropped | Reclassified |
|---|---|---|---|---|
| §2A Workouts | 7 | 7 | 0 | 0 |
| §2B Watch vitals | 18 | 6 | 12 | 0 |
| §2D Added signals | 14 | 5 | 8 | 1 (sleep stages → "surface existing") |
| §11 Edge cases | 14 | 11 | 3 | 0 |
| **Total** | **53** | **29** | **23** | **1** |

---

## Appendix: SF Symbol Mapping for Common Workout Types

```
.running                  → "figure.run"
.walking                  → "figure.walk"  
.cycling                  → "figure.outdoor.cycle"
.swimming                 → "figure.pool.swim"
.yoga                     → "figure.yoga"
.highIntensityIntervalTraining → "figure.hiit"
.functionalStrengthTraining    → "figure.strengthtraining.functional"
.traditionalStrengthTraining   → "figure.strengthtraining.traditional"
.coreTraining             → "figure.core.training"
.dance                    → "figure.dance"
.hiking                   → "figure.hiking"
.elliptical               → "figure.elliptical"
.rowing                   → "figure.rower"
.stairClimbing            → "figure.stairs"
.pilates                  → "figure.pilates"
.mindAndBody              → "figure.mind.and.body"
.cooldown                 → "figure.cooldown"
(default)                 → "figure.mixed.cardio"
```
