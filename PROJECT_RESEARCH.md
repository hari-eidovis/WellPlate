# WellPlate — Project Research Document

> A comprehensive iOS wellness intelligence application that quantifies and reduces stress using multi-modal physiological, behavioral, and lifestyle signals.

**Author:** Hariom
**Platform:** iOS 18+ (Xcode 26, Swift 5)
**Repository:** Local — `/Users/hariom/Desktop/WellPlate`
**Status:** Active development (Cadence rebrand branch)
**Document date:** 2026-05-25

---

## 1. Abstract

WellPlate is a native iOS wellness application that goes beyond conventional fitness trackers by computing a personalised **daily stress score (0–100)** using a transparent, deterministic 13-factor algorithm. Where most consumer apps rely on a single HRV reading, WellPlate fuses *sleep, exercise, caffeine, screen time, diet, hydration, circadian regularity, daylight exposure, meal timing, fasting state, eating triggers, mood, and self-reported symptoms* into a single explainable score with confidence weighting.

The app integrates **Apple HealthKit**, **DeviceActivity (Screen Time)**, **ActivityKit (Live Activities)**, and a **Groq LLM (llama-3.3-70b-versatile)** backend for natural-language nutrition parsing. All persistence uses **SwiftData**, and the entire UI is built with **SwiftUI** using Apple's iOS 18+ `Tab` API.

The flagship contribution is the **Stress Scoring v3 engine** — a pure, stateless, deterministic algorithm with tier-weighted drivers, a recovery bonus system, time-ramped engagement penalties, multi-day pattern detection, and an HRV/RHR-based physiological calibrator. Every score is fully decomposable, enabling the UI to surface *why* a user's stress changed, not just *that* it changed.

---

## 2. Problem Statement

### 2.1 Motivation

- **Conventional wellness apps** silo data — calories in MyFitnessPal, sleep in Apple Health, mood in journaling apps. The user is left to mentally correlate them.
- **HRV-only stress scores** (Whoop, Oura, Garmin) ignore behaviour: a 4-hour TikTok binge does not register in HRV until *after* sleep is impacted, by which point the intervention window is closed.
- **No transparency:** commercial wellness scores are black boxes. Users cannot tell whether their score is driven by caffeine, screen time, or poor sleep, so they cannot act on it.
- **No prospective interventions:** existing apps describe stress *after* it happens; they do not surface eating triggers, fasting windows, or circadian drift as *modifiable* inputs.

### 2.2 Goals

1. Compute a single, **explainable** daily stress score from heterogeneous inputs.
2. Give users **modifiable factor cards** — every input that affects the score is also an action surface.
3. Persist a **complete daily record** locally on device (no required backend).
4. Provide **prospective interventions** — guided breathing, fasting protocols, journaling, and AI-generated narratives.
5. Maintain **medical-data privacy** — HealthKit data never leaves the device.

---

## 3. Key Features (User-Facing)

### 3.1 Daily Stress Score
A 0–100 score (lower = better) updated continuously throughout the day. Backed by a 13-driver algorithm (see §6). Color-coded by `StressLevel`:

| Score | Level | UI accent |
|-------|-------|-----------|
| 0–20 | Excellent | Calm blue, 0.45 opacity |
| 21–40 | Good | Blue 0.58 |
| 41–60 | Moderate | Blue 0.72 |
| 61–80 | High | Blue 0.86 |
| 81–100 | Very High | Solid blue 1.0 |

Confidence (high / medium / low) is computed from input coverage — partial data is honestly surfaced rather than silently extrapolated.

### 3.2 Food Logging with LLM Nutrition Parsing
Users describe a meal in natural language ("two parathas with curd and a small mango") or scan a barcode. A **Groq LLM** (`llama-3.3-70b-versatile`) returns structured `NutritionalInfo` (calories, protein, carbs, fat, fiber, sodium, sugar). Results are cached in `FoodCache` to avoid duplicate API calls.

### 3.3 Fasting Tracker with Live Activity
Five presets — **16:8, 14:10, 18:6, 20:4, custom** — managed by `FastingService`. While fasting, a **Dynamic Island Live Activity** shows the app logo, a progress ring, elapsed/remaining time, and the eat-window endpoint. Notifications fire on window close, one-hour-remaining, completion, and optional caffeine-cutoff. Fasting state contributes directly to the stress score (factor 10).

### 3.4 Sleep Analytics
30-day history of total, deep, REM, and core sleep, plus a quality assessment (Poor / Fair / Good / Excellent). Read from HealthKit via `HKCategoryTypeIdentifier.sleepAnalysis`. Visualised as stacked bars with stage breakdown.

### 3.5 Burn / Activity
Daily active energy and steps over 30 days, rendered as bar charts. Steps and active energy independently feed the stress *Exercise* driver.

### 3.6 Screen Time Tracking
Uses Apple's **DeviceActivity** framework (Family Controls entitlement). A `ScreenTimeMonitor` extension fires on hourly thresholds and writes total + evening (7pm–midnight) usage to the shared App Group. Evening screen time is weighted heavier in the stress calculation because of its known impact on melatonin.

### 3.7 Vitals (Heart Rate, HRV, RHR, BP, Respiratory Rate)
All read via `HealthKitService.fetchDailyAvg()`. HRV uses `HKUnit(from: "ms")`; blood pressure uses `.millimeterOfMercury()`. HRV and Resting HR feed the **physiological calibrator** that scales the behavioural stress score.

### 3.8 Symptoms & Supplements Logging
Free-form `SymptomEntry` and `SupplementEntry` SwiftData models. A `SymptomCorrelationEngine` runs lightweight statistical correlation between logged symptoms and the stress score over rolling windows, surfacing patterns like "stress spikes 18% on days you take supplement X."

### 3.9 Journaling & Mood
`JournalEntry` model with daily prompts surfaced by `JournalPromptService`. Mood is captured on a positive/negative scale — negative mood adds to stress, positive mood applies a **recovery bonus** (capped at −10 points).

### 3.10 Guided Interventions
- **PMR (Progressive Muscle Relaxation) sessions** with a Live Activity.
- **Breathing exercises** via `BreathingLiveActivity`.
- All logged as `InterventionSession` and contribute to the recovery bonus.

### 3.11 Home Screen Widgets
Small / Medium / Large `StressWidget` displays current score, 7-day sparkline, and top stressors. Refreshed via `WidgetRefreshHelper`.

### 3.12 Goals
`UserGoals` (SwiftData @Model) stores per-day-of-week targets for calories, macros, water (cups + mL), steps, sleep hours, and weekly workout minutes. Adherence is logged via `AdherenceLog`.

### 3.13 Stress-Drop Celebration
When the user's score drops below a threshold, a `CelebrationCoordinator` shows a full-screen overlay (via a dedicated `UIWindow`) regardless of which tab the user is on.

### 3.14 Customisable Home Layout
Card visibility and ordering on the Home tab are user-configurable. The config is serialised as JSON inside `UserGoals.homeLayoutJSON` via `HomeLayoutConfig`.

---

## 4. Technology Stack

| Layer | Technology | Notes |
|---|---|---|
| Language | **Swift 5** | `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| UI | **SwiftUI** | iOS 18+ `Tab` API, custom font system `.r(...)`, `.appShadow(...)` |
| Charts | **Swift Charts** | Stress trends, sleep stages, burn bars |
| Persistence | **SwiftData** | 13 `@Model` classes, no Core Data |
| Health data | **HealthKit (HKHealthStore)** | Steps, HR, HRV, sleep, BP, respiratory rate, active energy |
| Screen time | **DeviceActivity / FamilyControls** | Extension target writes thresholds to shared App Group |
| Live Activities | **ActivityKit** | Fasting + breathing Dynamic Island |
| LLM / API | **Groq Cloud** | `llama-3.3-70b-versatile` for nutrition NLP |
| Concurrency | `async/await`, `@MainActor`, structured tasks | Private helper methods for `async let` (protocol-existential workaround) |
| Build system | `xcodebuild` + `PBXFileSystemSynchronizedRootGroup` | Files added by drop — no pbxproj edits |
| Distribution | iOS App (main) + 3 extensions | `ScreenTimeMonitor.appex`, `ScreenTimeReport.appex`, `WellPlateWidget.appex` |

---

## 5. System Architecture

### 5.1 High-Level Diagram

```
                ┌─────────────────────────────────────────────────────┐
                │                  WellPlateApp                       │
                │  (ModelContainer, Splash → Onboarding → MainTab)    │
                └───────────────┬─────────────────────────────────────┘
                                │
            ┌───────────────────┼──────────────────────────────┐
            ▼                   ▼                              ▼
  ┌──────────────────┐ ┌────────────────────┐ ┌─────────────────────────┐
  │  Feature Modules │ │   Service Layer    │ │   Models (SwiftData)    │
  │  (MVVM)          │ │   (35 services)    │ │   13 @Model classes     │
  │                  │ │                    │ │                         │
  │ Home / Stress /  │ │ HealthKitService   │ │ StressReading,          │
  │ Burn / Sleep /   │ │ StressScoring(v3)  │ │ FoodLogEntry,           │
  │ Goals / Fasting /│ │ FastingService     │ │ WellnessDayLog,         │
  │ Profile / Hist./ │ │ NutritionService   │ │ FastingSession,         │
  │ Onboarding /     │ │ ScreenTimeManager  │ │ JournalEntry,           │
  │ FoodScanner /    │ │ InsightEngine      │ │ SymptomEntry, ...       │
  │ Progress /       │ │ CircadianService   │ │                         │
  │ Symptoms /       │ │ CelebrationCoord.  │ │                         │
  │ Supplements      │ │ ...                │ │                         │
  └────────┬─────────┘ └─────────┬──────────┘ └─────────────────────────┘
           │                     │
           │                     ├──→ HealthKit (HKHealthStore)
           │                     ├──→ DeviceActivity (Screen Time)
           │                     ├──→ ActivityKit (Live Activities)
           │                     └──→ Groq LLM (URLSession + JSON)
           │
           └────→ App Group (group.com.hariom.wellplate.dev)
                    │
                    ▼
              ┌───────────────────────────────────────────────┐
              │  Extensions (separate processes)              │
              │  • ScreenTimeMonitor (DeviceActivityMonitor)  │
              │  • ScreenTimeReport (DeviceActivityReport)    │
              │  • WellPlateWidget (StressWidget +            │
              │    FastingLiveActivity + BreathingLA)         │
              └───────────────────────────────────────────────┘
```

### 5.2 Patterns

- **MVVM + Service Layer + Feature Modules.** Each feature has `Views/`, `ViewModels/`, optionally `Components/` and `Services/` subfolders.
- **All ViewModels are `@MainActor final class` with `@Published` properties.**
- **Service factory pattern:** `APIClientFactory.shared` and `HealthKitServiceFactory` return real or mock implementations based on `AppConfig.mockMode`.
- **Single source of truth for sheets:** each feature defines one enum (e.g. `StressSheet`) and drives a single `.sheet(item:)` — no cascading sheet stacks.
- **Pure scoring core:** `StressScoring.swift` is stateless and free of side effects. ViewModels gather inputs and feed them in; the engine returns a `StressFactorResult` array. Unit-testable without HealthKit.

### 5.3 Navigation

`RootView` owns the high-level state machine:

```
SplashScreenView (3s) ──→ (firstLaunch?) ──→ OnboardingView ──→ MainTabView
                                            │                  ▲
                                            └──────────────────┘
                                              UserProfileManager.hasCompletedOnboarding
```

`MainTabView` uses the iOS 18 `Tab` API with four tabs: **Home, Burn, Stress, Profile**. Tab selection is centralised in a `TabSelector` `ObservableObject` so deep links (e.g. "open Stress > Fasting") work across the app.

---

## 6. The Stress Scoring v3 Algorithm (Flagship Contribution)

**File:** `WellPlate/Core/Services/StressScoring.swift` (~31 KB, pure & stateless)

### 6.1 Driver Tiers

13 drivers split across three tiers, summing to a 100-point base score.

| Tier | Weight | Drivers |
|---|---|---|
| **A — Foundational** | **60 pts** | Sleep (20), Exercise (12), Caffeine (10), Screen Time (10), Diet (8) |
| **B — Modulators**   | **25 pts** | Hydration (5), Circadian (5), Daylight (3), Meal Timing (4), Fasting (3), Eating Triggers (5) |
| **C — Subjective**   | **15 pts** | Mood (8), Symptoms (7) |

Each driver returns a 0..N point contribution where N is its weight. The driver sum is a 0–100 *behavioural* score.

### 6.2 Modifiers

After the driver sum, four modifiers are applied:

1. **Recovery Bonus** (cap −10) — guided breathing, PMR, journaling, mindful mood entries.
2. **Engagement Penalty** (cap +18) — time-ramped: small after one missed day, escalates after several days of no input.
3. **Multi-Day Pattern Penalty** (cap +12) — rising trend over rolling 3–7 day windows.
4. **HRV / RHR Calibrator** (multiplier ≥ 1.0) — if Apple Watch data is present, divergence from the user's personal baseline scales the behavioural score upward. If no Watch data, the multiplier is 1.0 — the algorithm degrades gracefully.

### 6.3 Final Formula

```
finalScore = clamp( (driverSum + recoveryBonus) × calibrator
                   - engagementPenalty
                   - patternPenalty,
                   0, 100 )
```

### 6.4 Confidence

Coverage is computed per driver (did we have inputs for it today?). Aggregate coverage maps to:
- **High** ≥ 70% drivers covered
- **Medium** 40–70%
- **Low** < 40%

This is surfaced verbatim in the UI — a "Low confidence" score is never hidden.

### 6.5 Why Tier-Weighted (vs. averaged)?

Averaging treats a missed sleep night the same as a missed daylight log, even though sleep has an order of magnitude more impact on next-day stress. Tier weighting encodes a physiological prior: foundational lifestyle drivers dominate, subjective signals refine.

### 6.6 Determinism

The same inputs always produce the same score. No ML black box. This makes the algorithm **auditable** — both for users ("why did my score jump?") and for any future clinical review.

---

## 7. Data Model (SwiftData)

13 `@Model` classes registered in the `ModelContainer`:

| Model | Purpose |
|---|---|
| `FoodLogEntry` | One meal — name, NutritionalInfo, timestamp, mealType, mealContext |
| `FoodCache` | Cached LLM nutrition responses to avoid duplicate Groq calls |
| `WellnessDayLog` | Daily aggregate — water cups, coffee cups, manual notes, mood |
| `UserGoals` | Per-DOW targets + macros + home layout JSON |
| `StressReading` | Intraday score samples (timestamp, score, confidence) |
| `InterventionSession` | Breathing / PMR / journaling session record |
| `FastingSchedule` | Active schedule (preset enum + custom hours + active flag) |
| `FastingSession` | One fast — start, end, broken-early flag |
| `JournalEntry` | Text + timestamp + prompt id |
| `SymptomEntry` | Symptom code + severity 1–5 + timestamp |
| `SupplementEntry` | Supplement + dosage + timestamp |
| `AdherenceLog` | Did the user hit goal X on day Y |
| `ManualDailyInput` | Manually-entered values (e.g. screen time when DeviceActivity is unavailable) |

Plus ~14 non-persisted value types: `StressLevel`, `StressFactorResult`, `DailyMetricSample`, `DailySleepSummary`, `SleepStage`, `BurnMetric`, `VitalMetric`, `EatingTrigger`, `MealType`, `MealContext`, `CoffeeType`, `NutritionalInfo`, `HomeLayoutConfig`, and Groq DTOs.

---

## 8. External Integrations

### 8.1 HealthKit
- **Read:** steps, active energy, heart rate, resting HR, HRV (SDNN, ms), systolic BP, diastolic BP, respiratory rate, sleep analysis, daylight exposure.
- **Background delivery** enabled via entitlement so the app can refresh in the background.
- All new vitals use `HealthKitService.fetchDailyAvg()` rather than sum.

### 8.2 DeviceActivity (Screen Time)
- **`ScreenTimeMonitor.appex`** subclasses `DeviceActivityMonitor` and registers hourly thresholds (`threshold_60m`, `threshold_120m`, …). On firing, it writes to App Group UserDefaults.
- **`ScreenTimeReport.appex`** is a `DeviceActivityReportExtension` for showing category breakdown inside the app (Apple sandboxes the report so it cannot write back).

### 8.3 Groq LLM
- Endpoint: `https://api.groq.com/openai/v1/chat/completions`
- Model: `llama-3.3-70b-versatile` (configurable via `AppConfig.groqModel`)
- Prompt: system role primes JSON-only nutritional response; user role contains the meal description.
- Timeouts: 30 s request, 60 s resource.
- Errors typed via `NutritionProviderError`: `.missingKey`, `.invalidURL`, `.timeout`, `.network(Error)`, `.decoding`.
- Mock mode toggles in DEBUG via `AppConfig.mockMode` → `MockAPIClient` returns bundled JSON.

### 8.4 ActivityKit (Live Activities)
- **`FastingLiveActivity`** — Dynamic Island and Lock Screen UI for active fast. Watch family `.small` variant included.
- **`BreathingLiveActivity`** — Active during a guided session.
- State transitions only — no per-second timer pushes (ActivityKit budget conscious).

---

## 9. Project Structure

```
WellPlate/
├── App/                          # Entry point + RootView state machine
│   ├── WellPlateApp.swift        # @main; ModelContainer with 13 @Model classes
│   ├── RootView.swift            # Splash → Onboarding → MainTab transitions
│   └── SplashScreenView.swift
│
├── Core/
│   ├── AppConfig.swift           # DEBUG toggles, mockMode, groqModel, timeouts
│   └── Services/                 # 35 services (HealthKit, StressScoring, …)
│
├── Features + UI/
│   ├── Home/                     # Dashboard, quick log, wellness rings
│   ├── Stress/                   # Flagship — score, vitals, interventions
│   ├── Burn/                     # Active energy + steps
│   ├── Sleep/                    # Stage breakdown + quality
│   ├── Goals/                    # Per-DOW targets editor
│   ├── Fasting/                  # Schedule picker + live timer
│   ├── Onboarding/               # 4-page setup flow
│   ├── FoodScanner/              # Barcode + LLM nutrition
│   ├── History/                  # Past entries calendar
│   ├── Symptoms/                 # Logging + correlation
│   ├── Supplements/              # Logging
│   ├── Progress/                 # Long-term trends
│   ├── Profile/                  # User settings, goals, account
│   └── Tab/MainTabView.swift     # 4-tab navigation container
│
├── Models/                       # SwiftData @Model + value types (~27 files)
│
├── Networking/
│   ├── Real/                     # APIClient + APIClientFactory
│   └── Mock/                     # MockAPIClient + JSON loader
│
├── Resources/
│   └── MockData/                 # mock_nutrition_*.json, mock_health_*.json
│
├── Shared/
│   ├── Color/AppColor.swift      # Design tokens, .appShadow, semantic palette
│   ├── Components/               # Reusable cards, charts, sliders
│   └── Extensions/               # Font (.r), Date, Text helpers
│
├── Widgets/                      # Live Activity attribute types (shared)
│
├── WellPlate.entitlements        # HealthKit, FamilyControls, App Group
└── WellPlateDebug.entitlements
```

**Extension targets (separate dirs):** `ScreenTimeMonitor/`, `ScreenTimeReport/`, `WellPlateWidget/`.

---

## 10. Entitlements & Privacy

| Capability | Purpose |
|---|---|
| `com.apple.developer.healthkit` | Read vitals, sleep, activity |
| `com.apple.developer.healthkit.access` | Required for background delivery |
| `com.apple.developer.family-controls` | DeviceActivity (screen time) — Apple-restricted entitlement |
| `com.apple.security.application-groups` (`group.com.hariom.wellplate.dev`) | Share data between main app and extensions |

**Privacy posture:**
- All HealthKit data stays on device.
- The only external network call is the Groq LLM endpoint for meal text. The body contains only the meal description the user typed (no PHI, no device IDs).
- API keys live in `Secrets.plist` (gitignored), loaded by `SecretsLoader`.

---

## 11. Development Workflow

The project ships with a structured `/develop` orchestrator (under `.claude/skills/`) that gates feature work through eight stages:

```
brainstorm → strategize → plan → audit → resolve → checklist → implement → fix
```

Each stage writes a dated artifact to `Docs/` under a `YYMMDD-[slug]-[stage].md` naming convention, enforcing a paper-trail for every non-trivial change. The `resolve` step is a hard stop requiring user approval — no skipping from planning to implementation.

Build verification is via `xcodebuild` against four schemes:
```bash
xcodebuild -scheme WellPlate         -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme ScreenTimeReport  -destination 'generic/platform=iOS Simulator' build
xcodebuild -target  WellPlateWidget  -destination 'generic/platform=iOS Simulator' build
```

Files added under `WellPlate/` are auto-discovered by Xcode's `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits required.

---

## 12. Testing

Unit tests cover the deterministic core:

- `StressScoringTests.swift` — pinned scenarios for each driver and modifier
- `NutritionServiceTests.swift` — orchestration over real/mock providers
- `GeminiNutritionProviderTests.swift` — request building + response decoding
- `MockNutritionProviderTests.swift` — bundled JSON parsing
- `MealLogViewModelTranscriptionTests.swift` — Apple Speech transcription path

Integration is verified by build-only — automated UI tests are not yet wired into shared schemes.

---

## 13. UI / Design System

- **Typography:** Custom `Text.r(_:_)` modifier — e.g. `.r(.headline, .semibold)` — wraps a single dynamic-type font ramp so weight and size are controlled in one place.
- **Cards:** `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)` — repeated visual idiom.
- **Shadows:** `.appShadow(radius:y:)` — dark-mode aware (drops alpha in dark mode to avoid bloom).
- **Colors:** semantic enums — `StressLevel`, `VitalMetric`, `BurnMetric` — each exposes its own accent color. No raw hex codes in views.
- **Haptics & Sound:** `HapticService` + `SoundService` for confirmations, achievements, and the stress-drop celebration.

---

## 14. Notable Engineering Decisions

1. **Pure deterministic stress engine** instead of a learned model. Cost: cannot personalise weights automatically. Benefit: 100% auditable, no training data required, debuggable from a single input table.
2. **SwiftData over Core Data.** Cost: iOS 17+ only. Benefit: dramatically less boilerplate, native to Swift concurrency.
3. **`PBXFileSystemSynchronizedRootGroup`.** Cost: less granular control over membership. Benefit: zero merge conflicts in `project.pbxproj`.
4. **`@MainActor` by default for the whole module.** Cost: must explicitly opt out for background work. Benefit: no concurrent-mutation bugs in ViewModels — caught at compile time.
5. **Groq over OpenAI/Gemini for nutrition NLP.** Groq's `llama-3.3-70b-versatile` runs at ~500 tok/s, so a meal parse completes in well under a second — important for a logging UX where the user is waiting.
6. **Single `.sheet(item:)` per feature, driven by an enum.** Prevents the "stacked sheets" bug pattern where two `.sheet()` modifiers race for presentation.
7. **App Group bridging** rather than passing data through HealthKit — DeviceActivity threshold events must be persisted instantly from the extension process, and `UserDefaults(suiteName:)` is the lowest-latency channel available.

---

## 15. Potential Future Work

- **Apple Watch companion app** to surface intraday stress and feed back PMR session completions.
- **iCloud sync** for SwiftData (currently local-only).
- **HealthKit write-back** for guided breathing sessions (`HKWorkoutType.mindAndBody`).
- **On-device CoreML calibration** of personal driver weights from logged history.
- **Multi-user support** for households / clinicians (would require backend introduction).
- **Server-side aggregation** (opt-in) for population studies on stress driver impact.

---

## 16. Repository Map (for citation)

| Asset | Path |
|---|---|
| App entry point | `WellPlate/App/WellPlateApp.swift` |
| Root state machine | `WellPlate/App/RootView.swift` |
| Stress algorithm | `WellPlate/Core/Services/StressScoring.swift` |
| Stress ViewModel | `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` |
| HealthKit | `WellPlate/Core/Services/HealthKitService.swift` |
| Nutrition LLM | `WellPlate/Core/Services/GeminiNutritionProvider.swift` (Groq, despite filename) |
| Fasting | `WellPlate/Core/Services/FastingService.swift` |
| Live Activity (fast) | `WellPlateWidget/LiveActivities/FastingLiveActivityView.swift` |
| Screen time monitor | `ScreenTimeMonitor/ScreenTimeMonitorExtension.swift` |
| Tab container | `WellPlate/Features + UI/Tab/MainTabView.swift` |
| Onboarding | `WellPlate/Features + UI/Onboarding/OnboardingView.swift` |
| Goals model | `WellPlate/Models/UserGoals.swift` |
| Fasting schedule | `WellPlate/Models/FastingSchedule.swift` |
| Design tokens | `WellPlate/Shared/Color/AppColor.swift` |
| API factory | `WellPlate/Networking/Real/APIClientFactory.swift` |
| Entitlements | `WellPlate/WellPlate.entitlements` |
| Build config | `WellPlate/Core/AppConfig.swift` |

---

## 17. Glossary

- **Driver** — one of 13 inputs to the stress score (e.g. Sleep, Caffeine).
- **Calibrator** — physiological multiplier derived from HRV / RHR baselines.
- **Engagement penalty** — points added when the user has not logged in recent days.
- **Recovery bonus** — points subtracted for completed interventions / positive mood.
- **Confidence** — share of drivers with usable inputs today (High / Medium / Low).
- **Live Activity** — Apple ActivityKit feature for Lock Screen + Dynamic Island.
- **App Group** — shared UserDefaults / file container between the app and its extensions.
- **DeviceActivity** — Apple framework requiring Family Controls entitlement to monitor Screen Time usage.

---

*End of document. ~3,200 words. Suitable as the foundation chapter of a major-project research report.*
