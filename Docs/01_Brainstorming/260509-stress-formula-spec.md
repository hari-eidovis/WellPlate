# Stress Level Formula — Mathematical Specification

**Date:** 2026-05-09
**Status:** Brainstorm — formula reference for plan stage
**Companion to:** [260509-stress-algorithm-v3-brainstorm.md](./260509-stress-algorithm-v3-brainstorm.md)
**Purpose:** Closed-form, reactive formula for stress score `S(I, t)`. Every input change recomputes deterministically.

---

## 1. Master equation

```
S(I, t) = clamp(  max(0, D(I) + R(I) + E(I, t) + P(I))  ·  C(I),  0, 100  )
```

| Term | Meaning | Range |
|---|---|---|
| `D(I)` | Driver sum (Tier A–C) | −15 … +100 |
| `R(I)` | Recovery bonuses | −10 … 0 |
| `E(I, t)` | Engagement penalty (Tier D, time-ramped) | 0 … +18 |
| `P(I)` | Pattern penalty (Tier E) | 0 … +12 |
| `C(I)` | Multiplicative calibrator (HRV/RHR) | 0.90 … 1.15 |

The `max(0, ·)` floor prevents recovery + good-driver days from going negative before calibration. Final `clamp` to `[0, 100]` is the displayed stress level.

---

## 2. Driver sum `D(I)`

```
D(I) = Σ over f in F_drivers   p_f(I) · H_f(I)
```

- `F_drivers` = {sleep, exercise, caffeine, screen, diet, hydration, circadian, daylight, mealTiming, fasting, eatingTriggers, mood, symptoms}
- `p_f(I)` = signed factor points (negative when factor is *recovering*, positive when stressing)
- `H_f(I) ∈ {0, 1}` = has-data indicator (1 if HK or manual or self-log present, 0 otherwise)

When `H_f = 0`, the factor contributes nothing — neither stress nor recovery. The engagement tier picks up the slack for user-controllable factors.

---

## 3. Per-factor formulas

Each `p_f` is a piecewise function. Helper:

```
lerp(a, b, x, x_lo, x_hi) = a + (b − a) · clamp((x − x_lo)/(x_hi − x_lo), 0, 1)
```

### 3.1 Sleep (max 20)

```
p_sleep = min(20, hours_term + deep_term)

hours_term =
   18                              if h < 4
   lerp(18, 14, h, 4, 5)           if 4 ≤ h < 5
   lerp(14,  9, h, 5, 6)           if 5 ≤ h < 6
   lerp( 9,  4, h, 6, 7)           if 6 ≤ h < 7
   lerp( 4,  0, h, 7, 9)           if 7 ≤ h < 9
   lerp( 0,  3, h, 9, 10)          if 9 ≤ h < 10
   5                               if h ≥ 10

deep_term =
   4   if deepMin < 30
   2   if 30 ≤ deepMin < 45
   1   if 45 ≤ deepMin < 60
   0   if deepMin ≥ 60
```

### 3.2 Exercise (range −3 … +12)

```
a = max(steps / 7000, energy / 400)         // activity ratio
p_exercise =
   12                              if a < 0.1
   lerp(12, 6, a, 0.1, 0.5)        if 0.1 ≤ a < 0.5
   lerp( 6, 0, a, 0.5, 1.0)        if 0.5 ≤ a < 1.0
   lerp( 0, −3, a, 1.0, 1.5)       if 1.0 ≤ a < 1.5
   −3                              if a ≥ 1.5
```

### 3.3 Caffeine (max 10)

```
mg = cups · CoffeeType.caffeineMg(type, default 80)
late_bonus = 3 if any cup logged after 14:00 else 0     // (deferred — needs cup timestamps)

p_caffeine = min(10, base + late_bonus)
base =
   0                               if mg < 100
   2                               if 100 ≤ mg < 200
   5                               if 200 ≤ mg < 300
   7                               if 300 ≤ mg < 400
   10                              if mg ≥ 400
```

### 3.4 Screen time (max 10)

```
base =
   0                               if h < 2
   lerp(0, 3, h, 2, 4)             if 2 ≤ h < 4
   lerp(3, 6, h, 4, 6)             if 4 ≤ h < 6
   lerp(6, 9, h, 6, 8)             if 6 ≤ h < 8
   10                              if h ≥ 8

evening_mult = 1 + min(0.5, eveningHours / 4)    // = 1.0 if eveningHours = nil

p_screen = min(10, base · evening_mult)
```

### 3.5 Diet (max 8)

```
sugar_ratio   = sugar_g / sugarGoal
protein_ratio = protein_g / proteinGoal

sugar_term =
   0                                       if sugar_ratio < 0.8
   1                                       if 0.8 ≤ sugar_ratio < 1.0
   lerp(1, 4, sugar_ratio, 1.0, 1.5)       if 1.0 ≤ sugar_ratio < 1.5
   5                                       if sugar_ratio ≥ 1.5

protein_term = 3 if protein_ratio < 0.5 else 0

p_diet = min(8, sugar_term + protein_term)
```

### 3.6 Hydration (max 5)

```
r = waterGlasses / waterDailyCups
p_hydration =
   5    if r < 0.3
   3    if 0.3 ≤ r < 0.5
   1    if 0.5 ≤ r < 0.8
   0    if r ≥ 0.8
```

### 3.7 Circadian regularity (max 5)

```
p_circadian = (1 − regularityScore/100) · 5    // regularityScore from CircadianService
H_circadian = 1 only if hasEnoughData (≥ 5 sleep nights)
```

### 3.8 Daylight (max 3)

```
p_daylight =
   3    if minutes < 15
   2    if 15 ≤ minutes < 30
   1    if 30 ≤ minutes < 60
   0    if minutes ≥ 60
```

### 3.9 Meal timing (max 4)

```
late_pen   = 2 if any meal createdAt.hour ≥ 21:30 else 0
gap_pen    = 2 if exists pair (m_i, m_{i+1}) with gap > 5h AND m_{i+1}.calories > 600 else 0
p_mealTiming = late_pen + gap_pen
```

### 3.10 Fasting (max 3)

```
p_fasting =
   0    if h < 16
   1    if 16 ≤ h < 20
   2    if 20 ≤ h < 24
   3    if h ≥ 24
```

### 3.11 Eating triggers (max 5)

```
n = count of FoodLogEntry.eatingTriggers ∩ {.stressed, .rushed, .poorSleep, .bored}
p_triggers =
   0    if n = 0
   2    if n = 1
   3    if n = 2
   5    if n ≥ 3
```

### 3.12 Mood (range −2 … +8)

```
p_mood = lookup[mood]:
   awful → +8
   bad   → +5
   okay  → +2
   good  →  0
   great → −2
```

### 3.13 Symptoms (max 7)

```
W(category) =
   1.0  if category ∈ {cognitive, pain}
   0.7  if category = energy
   0.5  if category = digestive

For each unique symptom name, take max severity:
   weightedSum = Σ over unique names n   max_severity(n) · W(category(n))

p_symptoms = min(7, weightedSum / 30 · 7)
```

---

## 4. Recovery `R(I)` (≤ 0, capped −10)

```
b_intervention = max(−6, completedSessionsToday · −3)
b_journal      = −2 if JournalEntry.day == today else 0
b_mindful      = −2 if (mood logged today OR mindful session today) else 0

R(I) = max(−10, b_intervention + b_journal + b_mindful)
```

---

## 5. Engagement penalty `E(I, t)` (0 … +18)

Time-ramped, activated only when at least one driver has data:

```
ramp(t, t_start, t_end) = clamp((t − t_start) / (t_end − t_start), 0, 1)

For each gap g ∈ G_engagement:
   e_g(I, t) = g.max · g.cond(I) · ramp(t, g.t_start, g.t_end)

E(I, t) = 𝟙[Σ H_f ≥ 1] · min(18, Σ e_g)
```

| Gap `g` | `g.max` | `g.t_start` | `g.t_end` | `g.cond(I)` |
|---|---|---|---|---|
| no_mood | 5 | 17:00 | 21:00 | mood today is nil |
| no_food | 4 | 17:00 | 20:00 | no FoodLogEntry today |
| no_water | 4 | 14:00 | 18:00 | waterGlasses == 0 |
| low_steps | 3 | 16:00 | 20:00 | steps < 2000 |
| no_reflection | 2 | 18:00 | 21:00 | no journal AND no mood AND no mindful today |

---

## 6. Pattern penalty `P(I)` (0 … +12)

Discrete thresholds — discontinuous by design (crossing a pattern is a meaningful event):

```
P(I) = min(12,
           4 · 𝟙[no_food_3d]
         + 3 · 𝟙[low_mood_3d]
         + 3 · 𝟙[high_coffee_3d]
         + 2 · 𝟙[no_fast_14d])

Predicates:
   no_food_3d      = ∀ d ∈ {today, yesterday, 2-days-ago}: zero FoodLogEntry on d
   low_mood_3d     = ∀ d ∈ same window: WellnessDayLog.moodRaw ≤ 1
   high_coffee_3d  = ∀ d ∈ same window: coffeeCups ≥ 4
   no_fast_14d     = max(FastingSession.actualEndAt where completed) < now − 14 days
```

---

## 7. Calibrator `C(I)`

```
hrv_b = baseline14Day(hrvHistory)         // nil if < 5 valid days
rhr_b = baseline14Day(restingHRHistory)

δ_HRV = (hrv_b − hrv_today) / hrv_b       if both present, else 0
δ_RHR = (rhr_today − rhr_b) / rhr_b       if both present, else 0

Δ = 0.5 · δ_HRV + 0.3 · δ_RHR
C(I) = clamp(1 + Δ, 0.90, 1.15)           // collapses to 1.0 if no baseline at all
```

`baseline14Day(samples)` = mean over last 14 days excluding today, with `value > 0`, requiring ≥ 5 valid days.

---

## 8. Confidence (display gate, not a score input)

```
totalPossible = Σ_f∈F_drivers  M_f               = 100
covered       = Σ_f∈F_drivers  M_f · H_f
coverage      = covered / 100

confidence =
   high     if coverage ≥ 0.70
   medium   if 0.40 ≤ coverage < 0.70
   low      if coverage < 0.40    → hide score
```

---

## 9. Reactivity — what recomputes when an input changes

The score is a pure function of `(I, t)`. SwiftUI just needs `I` and `t` published. Dependency graph:

```
INPUT CHANGE           →  AFFECTS
─────────────────────────────────────────────────────────
food log added         →  p_diet, p_mealTiming, p_triggers, no_food gap, no_food_3d
mood logged            →  p_mood, no_mood gap, no_reflection gap, low_mood_3d, b_mindful
water glass added      →  p_hydration, no_water gap
coffee cup added       →  p_caffeine, high_coffee_3d
symptom logged         →  p_symptoms
intervention completed →  b_intervention, no_reflection gap (indirectly)
journal saved          →  b_journal, no_reflection gap
manual sleep entered   →  p_sleep, p_circadian (indirectly)
manual screen entered  →  p_screen
HK sleep arrived       →  p_sleep, p_circadian
HK steps changed       →  p_exercise, low_steps gap
HK HRV arrived         →  C (recompute baseline + today)
HK RHR arrived         →  C
fasting toggled        →  p_fasting, no_fast_14d (when ended)
time advances (5min)   →  E (engagement ramps update)
```

In code: each `@Published` change in `StressViewModel` triggers `recompute()`. Recompute is O(13) factor evaluations + O(1) calibrator + O(1) sum — sub-millisecond, run synchronously on main actor.

---

## 10. Reactivity examples — how `S` moves on a single input

Setup: today is 21:00, user has logged sleep (5h, 30min deep), water 0, no other inputs. HK has all vitals, baseline normal.

**State 0 (nothing else logged):**
```
D = p_sleep(5h, 30min) = 14 + 4 = 18                  (only sleep has H = 1)
R = 0
E = e_no_mood(5) + e_no_food(4) + e_no_water(4) + e_low_steps(3) + e_no_reflection(2) = 18
P = 0
C = 1.0
raw = max(0, 18 + 0 + 18 + 0) = 36
S = clamp(36 · 1.0, 0, 100) = 36 → "Good"
```

**Input event A — user logs mood = `awful`:**
```
ΔD = +8 (mood factor activates)
ΔE = −5 (no_mood gap closes) − 2 (no_reflection closes, mood counts as reflection) = −7
ΔR = −2 (b_mindful kicks in via mood proxy)
S' = clamp((36 − 7 − 2 + 8) · 1.0) = 35
```
**Net: −1 point.** Logging "awful" is honest; the system rewards engagement (−7 + −2 = −9) more than the mood factor's +8.

**Input event B (alternative) — user logs mood = `great`:**
```
ΔD = −2
ΔE = −7  (same gaps close)
ΔR = −2
S'' = clamp((36 − 7 − 2 − 2) · 1.0) = 25 → "Good"
```
**Net: −11 points.** Honest "great" drops the score visibly.

**Input event C — user logs water = 1 glass:**
```
ΔD = +5 (p_hydration activates: ratio 0.125 < 0.3 → +5)
ΔE = −4 (no_water gap closes)
S''' = clamp((36 + 5 − 4) · 1.0) = 37
```
**Net: +1 point.** Telling truth that hydration is bad raises by 1, because the worst-case driver (+5) slightly exceeds the engagement gap (+4). This is the "honest mode is *almost* free" margin.

**Input event D — HK HRV arrives, today's HRV is 25% below 14-day baseline:**
```
δ_HRV = 0.25, δ_RHR = 0
Δ = 0.5 · 0.25 = 0.125
C = clamp(1.125, 0.90, 1.15) = 1.125
S'''' = clamp(36 · 1.125, 0, 100) = 41 → bumps up into "Moderate"
```
**Net: +5.** Calibrator amplifies the score because vitals confirm stress.

---

## 11. Continuity properties

| Property | Holds? | Why |
|---|---|---|
| `S` continuous in time `t` | ✅ | Engagement ramps are linear in `t`; pattern penalties are time-of-day independent |
| `S` continuous in continuous inputs (steps, hours, mg) | ✅ | All piecewise functions use `lerp` at boundaries; no jumps inside ranges |
| `S` discontinuous at category transitions (mood values, symptom severity 5→6, fasting threshold 16h) | ✅ (intentional) | Category changes are meaningful events; users perceive them as deserved score changes |
| Score bounded `[0, 100]` always | ✅ | Final `clamp` |
| `S` deterministic given `(I, t)` | ✅ | Pure functions, no randomness |
| `S` monotone in adverse changes | ⚠️ Mostly | Logging truthful "bad water" can raise score by 1 (honesty cost); acceptable trade-off |

---

## 12. Time-driven recomputation (the only ticker the system needs)

`E(I, t)` is the only term that changes without input. So:

```
On (.scenePhase = .active) → recompute()
On Timer.publish(every: 300s) while foreground → recompute()
On any @Published input change → recompute()
```

5-minute granularity means the score creeps up smoothly through the engagement window. No need for finer than that — the user won't perceive the difference.

---

## 13. Single source-of-truth implementation shape

```swift
struct StressInputs {                      // The full bag I
    var sleep: SleepInput?
    var exercise: ExerciseInput?
    var caffeine: CaffeineInput?
    var screen: ScreenInput?
    var diet: DietInput?
    var hydration: HydrationInput?
    var circadian: CircadianInput?
    var daylight: DaylightInput?
    var mealTiming: [FoodLogEntry]
    var fasting: FastingInput?
    var triggers: [FoodLogEntry]
    var mood: MoodOption?
    var symptoms: [SymptomEntry]
    var recovery: RecoveryInput
    var history: HistoryInput
    var vitals: VitalsInput
    var goals: UserGoals
}

func computeStress(inputs: StressInputs, now: Date) -> StressResult {
    let factors = StressScoring.allFactors(inputs: inputs)        // [FactorPoints]
    let D = factors.filter(\.hasData).reduce(0) { $0 + $1.points }
    let R = StressScoring.recovery(inputs.recovery)
    let hasAnyDriver = factors.contains(where: \.hasData)
    let E = hasAnyDriver ? StressScoring.engagement(inputs, now: now) : 0
    let P = StressScoring.patterns(inputs.history)
    let C = StressScoring.calibrator(inputs.vitals)
    let raw = max(0, D + R + E + P)
    let S = min(100, max(0, raw * C))
    return StressResult(score: S, factors: factors, calibrator: C, ...)
}
```

`computeStress` is pure. The ViewModel's job shrinks to building `StressInputs` from HK + SwiftData and calling this on every change. UI bindings re-render automatically.

---

## 14. Validation checklist

Unit tests should hold:

- [ ] `S(zero_input, t) = 0` and confidence = low (score hidden)
- [ ] `S(perfect_day, t) = 0` (drivers good, recovery max, calibrator ≤ 1)
- [ ] `S(worst_logged_day, t) ≤ 100` (clamping works)
- [ ] Logging mood `great` strictly reduces `S` vs not logged after 21:00
- [ ] Logging water 8 strictly reduces `S` vs not logged after 18:00
- [ ] Manual sleep entry produces same `p_sleep` as HK with equivalent values
- [ ] Calibrator collapses to 1.0 when HK absent
- [ ] Engagement penalty = 0 before its `t_start`
- [ ] Pattern penalty stable across recompute cycles within same day

---

## 15. Symbol glossary

| Symbol | Meaning |
|---|---|
| `I` | Input bag (all of today's data + relevant history) |
| `t` | Current time (used only by `E`) |
| `S` | Final stress score, ∈ [0, 100] |
| `D` | Driver sum |
| `R` | Recovery bonus (≤ 0) |
| `E` | Engagement penalty (≥ 0) |
| `P` | Pattern penalty (≥ 0) |
| `C` | Calibrator multiplier |
| `p_f` | Signed points for factor `f` |
| `M_f` | Maximum points for factor `f` (factor weight) |
| `H_f` | Has-data indicator for factor `f`, ∈ {0, 1} |
| `δ_HRV`, `δ_RHR` | Normalized deltas vs 14-day baseline |
| `lerp` | Linear interpolation with clamping |
| `𝟙[·]` | Indicator function (1 if predicate true, else 0) |

---

## Summary

`S = clamp( max(0, D + R + E + P) · C, 0, 100 )` with 13 driver factors (`p_f`), 3 recovery bonuses, 5 time-ramped engagement gaps, 4 historical patterns, and a 2-vital multiplicative calibrator. Every input change recomputes the whole formula in microseconds. Engagement ramps make the score evolve smoothly through the day; pattern thresholds and category changes produce intentional, explainable jumps. Honesty is rewarded — closing an engagement gap usually outweighs the truthful driver penalty.
