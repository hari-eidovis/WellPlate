# Stress Algorithm v3 — Drivers vs. Indicators, Engagement Penalties, Manual Fallbacks

**Date:** 2026-05-09
**Status:** Brainstorm — ready for plan
**Builds on:**
- [260410-stress-algorithm-v2-brainstorm.md](./260410-stress-algorithm-v2-brainstorm.md) (architecture)
- [260420-stress-algorithm-improvements-brainstorm.md](./260420-stress-algorithm-improvements-brainstorm.md) (gap analysis)
- [260421-stress-params-deep-research.md](./260421-stress-params-deep-research.md) (evidence base)
- Current implementation: `WellPlate/Core/Services/StressScoring.swift`, `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift`

---

## 1. Problem statement

The shipped v1 algorithm uses only 4 factors (Sleep 35 / Exercise 25 / Diet 20 / Screen Time 20) and ignores everything else the user logs. Reported symptoms:

- Logged mood doesn't change the stress number.
- Symptom entries don't change it either.
- Water glasses, coffee cups don't move the needle.
- Score feels static even on visibly bad days.

Root cause: **most user-logged signals never reach `StressScoring.totalScore`**. Vitals (HRV, RHR, BP, RR) are fetched and displayed but never scored. Engagement gaps (no log) are silently ignored.

---

## 2. Conceptual model: drivers vs. indicators

The single most important architectural distinction.

| Role | Effect on score | Examples |
|---|---|---|
| **Driver** ("wood in the fire") | Adds points when worse, subtracts when better | Sleep, caffeine, hydration, sugar, screen time, mood, symptoms, daylight, fasting, eating triggers |
| **Calibrator** ("smoke from the fire") | Doesn't add raw points — multiplies the score against personal baseline | HRV, RHR |
| **Display only** | Not in the algorithm — shown for context | Live HR, BP, Respiratory Rate, hunger/presence levels, supplement adherence |

Mixing drivers and indicators in one weighted sum double-counts and makes the score lag a day behind inputs.

### Dropped from scoring

| Drop | Reason | Kept for |
|---|---|---|
| Live Heart Rate | Pure indicator, noisy minute-to-minute | Vitals card |
| Blood Pressure (sys/dias) | Sparse data (most users lack a cuff), pure indicator | Vitals card when present |
| Respiratory Rate | Sparse, noisy, indicator only | Vitals card |
| Hunger / Presence levels | Inconsistently logged, weak signal | Field retained on `FoodLogEntry` |
| Supplement adherence | Effects are weeks-long, not daily | Streak display only |

---

## 3. Factor budget (0–100 driver sum)

### Tier A — foundational (60 pts)

| Factor | Max pts | Logic |
|---|---|---|
| Sleep | 20 | Hours curve: <4→+18, 4–5→18→14, 5–6→14→9, 6–7→9→4, 7–9→4→0, 9–10→0→3, >10→+5. Plus deep-sleep penalty: <30min +4, <45 +2, <60 +1. Cap 20 |
| Exercise | −3..+12 | activity = max(steps/7000, energy/400). 0–0.1→+12, 0.1–0.5→12→6, 0.5–1.0→6→0, 1.0–1.5→0→−3, ≥1.5→−3 |
| Caffeine | 10 | mg = cups × `CoffeeType.caffeineMg`. <100→0, 100–200→+2, 200–300→+5, 300–400→+7, ≥400→+10 |
| Screen time | 10 | base by total: <2→0, 2–4→0→3, 4–6→3→6, 6–8→6→9, ≥8→10. × `1 + min(0.5, eveningHours/4)` when evening data present |
| Diet | 8 | sugar excess (vs `UserGoals.sugarGoalGrams`): <80%→0, 80–100→+1, 100–150→+1→+4, >150→+5. Plus protein <50% goal → +3. Cap 8 |

### Tier B — modulators (25 pts)

| Factor | Max pts | Logic |
|---|---|---|
| Hydration | 5 | ratio = glasses/goal: <0.3→+5, 0.3–0.5→+3, 0.5–0.8→+1, ≥0.8→0 |
| Circadian regularity | 5 | `(1 − regularityScore/100) × 5` from `CircadianService` |
| Daylight | 3 | <15 min→+3, 15–30→+2, 30–60→+1, ≥60→0 |
| Meal timing | 4 | Any meal ≥21:30 → +2. >5h gap then meal >600 kcal → +2 |
| Fasting | 3 | <16h→0, 16–20→+1, 20–24→+2, ≥24→+3 |
| Eating triggers | 5 | count of `.stressed/.rushed/.poorSleep/.bored`: 0→0, 1→+2, 2→+3, ≥3→+5 |

### Tier C — subjective (15 pts)

| Factor | Max pts | Logic |
|---|---|---|
| Mood | −2..+8 | awful +8, bad +5, okay +2, good 0, great −2 |
| Symptoms | 7 | per unique name take max severity. Weights: cognitive/pain ×1.0, energy ×0.7, digestive ×0.5. Sum, map 0→0, ≥30→+7 |

### Recovery bonuses (≤ 0, capped −10)

| Action | Bonus |
|---|---|
| Completed `InterventionSession` (PMR / sigh) | −3 each, cap −6 |
| `JournalEntry` written today | −2 |
| Mindful minutes / Apple State of Mind logged | −2 |

---

## 4. Calibrator (multiplicative, HRV/RHR vs personal baseline)

Confirmed: **multiplicative, 14-day baseline window, ≥5 valid days required.**

```
hrvDelta = (hrvBaseline − todayHRV) / hrvBaseline    // +ve when HRV dropped
rhrDelta = (todayRHR − rhrBaseline) / rhrBaseline    // +ve when RHR up
combined = hrvDelta × 0.5 + rhrDelta × 0.3
calibrator = clamp(1.0 + combined, 0.90, 1.15)
```

Effect: −10% (recovered, vitals look great) up to +15% (HRV crashed, RHR elevated).
Collapses to 1.0 when no baseline available — Watch-less users see no calibration but no penalty either.

---

## 5. Engagement penalty (Tier D, +18 pts)

User-controllable signals don't go silent when missing — they actively raise stress past a time-of-day cutoff. This fixes the "I logged nothing today and the score said 'low stress'" bug.

| Gap | Cutoff | Penalty |
|---|---|---|
| No mood logged | after 20:00 | +5 |
| No food logged | after 20:00 | +4 |
| No water logged | after 18:00 | +4 |
| Steps < 2000 | after 18:00 | +3 |
| No reflection (journal/mood/mindful) | after 21:00 | +2 |

**Activation guard:** engagement penalties only apply when at least one Tier A–C factor has data. Protects new users on day 1 from a confusing high-stress score.

---

## 6. Pattern penalty (Tier E, +12 pts)

Multi-day patterns from history. Catches chronic disengagement, not one-off bad days.

| Pattern | Detection | Penalty |
|---|---|---|
| 3+ consecutive days no food log | `FoodLogEntry.day` last 3 days empty | +4 |
| 3+ consecutive days mood `awful`/`bad` | `WellnessDayLog.moodRaw ≤ 1` for 3 days | +3 |
| Sustained high caffeine | ≥4 cups for 3+ consecutive days | +3 |
| No fast in 14+ days | last `FastingSession.completed` >14d ago | +2 |

---

## 7. Pipeline

```
factors  (Tier A–C)   → driver sum   (0..100)
         + recovery   (−10 cap)
         + engagement (Tier D, +18 cap)
         + patterns   (Tier E, +12 cap)
         = raw  (clamp ≥ 0)
         × calibrator (HRV/RHR, ×0.90..1.15)
         = final, clamp [0, 100]
```

Total possible pre-clamp: 100 + 18 + 12 − 10 = **120**. Intentional — heavy disengagement should beat "good sleep + good exercise" alone. Final clamp to 100.

---

## 8. Missing-data lanes

Three sources, three behaviors:

| Signal class | Lane |
|---|---|
| Device data (sleep, screen, daylight, exercise minutes) | HK → overlay → manual (`ManualDailyInput`) → factor `hasData: false` |
| User-controllable (mood, water, food, coffee, symptoms, journal) | always self-logged → engagement penalty after cutoff |
| Calibrators (HRV, RHR) | HK only → calibrator collapses to 1.0 |

### Manual fallback model

```swift
@Model final class ManualDailyInput {
    @Attribute(.unique) var day: Date
    var sleepHours: Double?
    var sleepQuality: Int?            // 1–5
    var bedtime: Date?
    var wakeTime: Date?
    var screenTimeHours: Double?
    var heavyEveningScreens: Bool?
    var exerciseMinutes: Int?
    var amDaylightOutside: Bool?
    var morningAskedAt: Date?
    var eveningAskedAt: Date?
}
```

### Source priority per device factor

| Factor | 1st | 2nd | 3rd |
|---|---|---|---|
| Sleep | HK `DailySleepSummary` | `manual.sleepHours` (deep derived from quality: 1→15min, 3→45, 5→80) | `hasData: false` |
| Exercise | HK steps/energy | `manual.exerciseMinutes × 100 steps/min` | `hasData: false` |
| Screen time | `ScreenTimeManager` | `manual.screenTimeHours` | `hasData: false` |
| Daylight | HK `timeInDaylight` | `manual.amDaylightOutside` (true→30min, false→5min) | `hasData: false` |
| Circadian regularity | HK 7-day sleep history | `manual.bedtime/wakeTime` last 7 nights | `hasData: false` |

HK is always source-of-truth — if HK data appears after manual entry, HK overrides silently.

---

## 9. Daily overlays — global, two prompts

**Confirmed: two overlays, fired globally from `RootView` on `.scenePhase = .active`.**

| Prompt | First open after | Asks (if HK silent) | Skip storage |
|---|---|---|---|
| Morning check-in | 11:00 local | Sleep hours (slider), quality (1–5), bedtime/wake (optional) | `manual.morningAskedAt` |
| Evening recap | 19:00 local | Screen time hours, "heavy after 8pm?", exercise minutes, "AM sun?" | `manual.eveningAskedAt` |

Render conditions:

```
showMorning = firstOpenAfter11 && !morningAskedToday
            && hkSleepSummary == nil && manual.sleepHours == nil

showEvening = firstOpenAfter19 && !eveningAskedToday
            && (anyDeviceFactorMissing && correspondingManualFieldNil)
```

The evening overlay only renders fields where HK is silent **and** manual is empty. Watch users with full HK never see it; iPhone-only users see a 2–4 field form.

### Three dismiss buttons

| Button | Effect |
|---|---|
| Save | Writes to `ManualDailyInput`, sets askedToday |
| Skip for today | Sets askedToday flag; no save; no engagement penalty (device-data gap, not user choice) |
| Don't ask again | UserDefaults flag; no future prompts; settings toggle to re-enable |

### Edge cases

| Case | Behavior |
|---|---|
| HK populates after dismissal | HK wins silently on next recompute |
| User opens app at 6am | Wait until 11:00 — no early-morning prompts |
| First app open is at 23:00 | Show evening prompt only; morning is missed (don't backfill) |
| First launch ever | Suppress prompts for 24h post-onboarding (let HK sync) |
| Both prompts pending evening (rare) | Stack as 2-page sheet with "Next →" |

---

## 10. Confidence rule (replaces v1's `factorCoverage < 2`)

Coverage is **weight-weighted** across drivers only:

```
totalPossible = Σ(maxPoints of all drivers)         // = 100
covered       = Σ(maxPoints of drivers with hasData)
coverage      = covered / totalPossible

≥ 0.70 → high
0.40–0.70 → medium
< 0.40 → low (hide score)
```

Engagement and pattern penalties don't count toward coverage — they replace silence with active signal, but don't substitute for actual driver data.

---

## 11. UI impact

| Area | Change |
|---|---|
| StressView header | Total score + level + calibrator chip ("HRV +8% from baseline") |
| "What's driving it" section | Sort drivers by `points` desc, show top 5 cards (vs. fixed 4) |
| Recovery section | Display intervention/journal/mindful as "−X stress avoided" framing |
| All factors disclosure | Full list with `points / maxPoints` bars |
| Engagement gaps card | Shows which logs are missing today and the penalty incurred — direct call to action |
| Manual log entry point | Persistent "Quick log" button on StressView for users who dismissed overlays |
| Onboarding/Settings | Toggle for "Don't ask again" reversal |

---

## 12. Sanity checks

### Bad day, fully logged (a real cortisol-bad day)

- Slept 4.5h, 25min deep → +18
- 1,200 steps, 80 kcal → +11
- 4 cups Cold Brew (~700mg) → +10
- 7.5h screen, 4h after 19:00 → +10
- Sugar 180% goal, low protein → +6
- Water 25% → +5
- Irregular sleep, 8 min daylight → +3
- Last meal 22:30 → +2
- Eating triggers: stressed + rushed → +3
- Mood: bad → +5
- Symptoms: anxiety 7, headache 6, brain fog 5 → +6
- No interventions, no journal → 0 bonus

**Raw ≈ 79**, calibrator 1.12 (HRV crashed) → **88 → "Very High"** ✅

### Disengaged bad day, half logged at 21:30

- Slept 5.5h, 35min deep → +12
- 800 steps → +12
- 5 cups → +10
- Screen 7h evening-heavy → +10
- No food log → diet missing
- Water 0 → +5 (hydration)
- Mood not logged → factor missing
- Symptoms: anxiety 8 → +2
- **Engagement: no mood +5, no food +4, no water +4, low steps +3, no reflection +2 → +18**
- **Pattern: high coffee 3d → +3**
- Calibrator 1.10

**Raw ≈ 72**, × 1.10 → **79 → "High"** ✅

### Fully logged honest bad day (same user)

- Mood awful → +8 (driver, not engagement)
- Water 1 → +5 (hydration)
- Food logged → diet driver +6
- Engagement gaps disappear
- Calibrator 1.10

**Raw ≈ 68**, × 1.10 → **75** ✅

**Logging your bad day is *less* stressful than hiding from it.** Algorithm rewards engagement even when the truth is ugly.

### Balanced day

- 7.8h sleep, 70 min deep → 0
- 9k steps + 450 kcal → −3
- 1 latte at 09:00 → 0
- 2.5h screen, none after 19:00 → 0
- Macros on goal → 0
- Water 6/8 → 0
- 1 PMR session → −3
- Journal written → −2
- Mood good → 0
- No symptoms → 0

**Raw = −8 → clamped 0**, calibrator 1.0 → **"Excellent"** ✅

---

## 13. Code artifacts to add/change

| Path | Action |
|---|---|
| `WellPlate/Models/ManualDailyInput.swift` | NEW `@Model` |
| `WellPlate/App/WellPlateApp.swift` | Register `ManualDailyInput` in ModelContainer |
| `WellPlate/Core/Services/StressScoring.swift` | Refactor — `FactorPoints` return shape, new factor functions, calibrator, engagement, patterns, baseline14Day, confidence |
| `WellPlate/Core/Services/DailyPromptCoordinator.swift` | NEW `@MainActor ObservableObject` |
| `WellPlate/Shared/Components/QuickCheckInSheet.swift` | NEW bottom sheet view |
| `WellPlate/App/RootView.swift` | Host coordinator + present sheet via `.sheet(item:)` |
| `WellPlate/Features + UI/Stress/ViewModels/StressViewModel.swift` | New pipeline: resolve all factors via priority chain, sum drivers + engagement + patterns, apply calibrator, store `totalScore` as `@Published var` (no longer pure computed) |
| `WellPlate/Features + UI/Stress/Views/StressView.swift` | Top-N driver cards (vs fixed 4), engagement-gap card, calibrator chip, manual log button |
| `WellPlate/Models/StressModels.swift` | Update `StressFactorResult` builder to consume `FactorPoints` |

---

## 14. Migration

- Old `StressScoring.Weights` constants (sleep 35 / exercise 25 / diet 20 / screen 20) become per-factor (sleep 20 / exercise 12 / etc.). Audit all `Weights.` references — detail labels showing "/35" need updating.
- Existing `StressReading` rows persisted under v1: only `score` and `levelLabel` are stored, both still meaningful — **no SwiftData migration needed**.
- v1 `factorCoverage < 2` rule → replaced by weighted coverage. UI strings referring to "factor" count need updating.
- Existing `StressFactorResult.maxScore == 25` defaults in `.neutral(...)` factory → use per-factor `Weights.x`.

---

## 15. Open items deferred

| Item | Status |
|---|---|
| Hour-bucket screen time (for evening multiplier) | `ScreenTimeManager` extension — Phase 2; v3 passes `nil`, multiplier no-ops |
| Mindful minutes count (`mindfulSession`) | Not yet read from HK; use `hasMoodLog || hasJournal` as stand-in for v3 |
| Gender-aware modulation (sleep ×1.3, caffeine half-life ×2 on OCP) | Out of scope — see 260420 brainstorm §A6 |
| Cycle-phase awareness | Out of scope — would need menstrual flow read permission |

---

## 16. Decisions locked

1. ✅ Multiplicative calibrator
2. ✅ 14-day baseline window, ≥5 valid days required
3. ✅ Two overlays (morning + evening)
4. ✅ Overlay fired globally from `RootView`, not inside `StressView`
5. ✅ Engagement penalty does **not** apply to device-data gaps (sleep, screen, etc.) — only to user-controllable inputs (mood, water, food, etc.)
6. ✅ Indicators (HRV, RHR) act as multiplicative calibrator only — no point contribution
7. ✅ Live HR, BP, RR dropped from scoring; remain on vitals card
8. ✅ Engagement/pattern penalties activate only when ≥1 driver has data (day-1 protection)

---

## Next step

→ `/develop plan stress-algorithm-v3` — turn this into the implementation plan in `Docs/02_Planning/Specs/`.
