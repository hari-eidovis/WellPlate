# Fasting Blueprint v1 — Gap Audit vs Current Code

**Date:** 2026-05-27
**Branch:** `rename-to-cadence`
**Treatment:** Blueprint v1 boundary is **binding** (per user). Items the blueprint excludes from v1 must be removed/hidden from current code even if implemented today.
**Scope:** Existing fasting feature (`Cadence/Models/Fasting*.swift`, `Cadence/Core/Services/FastingService.swift`, `Cadence/Features + UI/Stress/Views/Fasting*.swift`, `Cadence/Features + UI/Stress/Components/FastingCelebrationOverlay.swift`, `Cadence/Core/Services/ActivityManager.swift`, `Cadence/Widgets/FastingActivityAttributes.swift`, `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`) vs the v1 blueprint.

---

## Verdict at a glance

| Area | Status | Note |
|---|---|---|
| Core data models (`FastingSession`, `FastingSchedule`) | ✅ Mostly aligned | Missing `completionStatus` enum, `contextualHRV`, `contextualSleepScore` |
| Fasting state machine | ✅ Solid | Three-state machine matches blueprint intent |
| Live Activity / Dynamic Island | 🟡 Foundation strong, **no interactivity** | Blueprint demands `LiveActivityIntent` "Break Fast" button — currently absent |
| Schedule presets | 🟠 **Violates v1 boundary** | `20:4` (and arguably `18:6`) push beyond the v1 "Anxious Beginner" persona |
| Manual Start/Stop + Edit | 🟡 Partial | Start/Break exist; retroactive *edit-previous-fast* UI does not |
| SCOFF safety screening | ❌ **Missing entirely** | Blueprint marks as non-negotiable |
| Hard 24h cap + forgotten-stop guard | ❌ Missing | Blueprint explicit risk-mitigation requirement |
| Wellness disclaimer / age gate / pregnancy gate | ❌ Missing | Regulatory exposure |
| Contextual HRV/Sleep insight under timer | ❌ Missing | Blueprint's core differentiator vs Zero/Fastic |
| Circadian-aware ("close window 2–3h before sleep") nudges | ❌ Missing | eTRF positioning is unrealized |
| Copy / lexicon | 🟠 Punitive vocabulary present | "BROKEN", red ring, red Live Activity color violate calm-tone mandate |
| Weekly grid consistency view | 🟡 Have list, not 7-day grid | Blueprint specifies grid for habit-formation framing |
| HealthKit misuse (e.g. `mindfulSession`) | ✅ Not done — good | Current code correctly stays out of HK fasting taxonomy |
| Community / leaderboards | ✅ Not built — good | Blueprint excludes from v1 |
| Biological-phase tracking ("autophagy", "ketosis") | ✅ Not built — good | Blueprint excludes from v1 |
| Weight-loss projections | ✅ Not built — good | Blueprint excludes from v1 |
| AI food scanning | ✅ Not built (in fasting scope) — good | Blueprint excludes from v1 |

---

## 1. What's already aligned

These do not require change. Listing them so they don't get accidentally regressed by future work.

- **SwiftData model shape** (`Models/FastingSession.swift:1-63`) — `startedAt`, `targetEndAt`, `actualEndAt`, `completed`, `scheduleType`, `createdAt` map cleanly to the blueprint's proposed entity. Computed `isActive`, `progress`, `actualDurationSeconds` are clean.
- **State machine** (`Core/Services/FastingService.swift:7-30`) — `FastingState.fasting | eating | notConfigured` directly mirrors blueprint's IA.
- **No HealthKit `mindfulSession` abuse** — blueprint explicitly warns against this (page 9–10 equivalent). Current code writes nothing to HealthKit, which is the correct posture given Apple's lack of a native fasting identifier.
- **Live Activity foundation** (`Core/Services/ActivityManager.swift:34-139`, `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`) — race-safe restart, reconnection after app kill, throttled updates (0.5% delta), 60s staleDate buffer. Engineering quality is high.
- **Insight chart already does the differentiator math** (`Features + UI/Stress/Views/FastingInsightChart.swift`) — fast vs non-fast day stress average + "correlation ≠ causation" caveat. This is precisely the "Contextual Interaction Rate" KPI the blueprint defines.
- **Cross-feature integration exists** — Home opens FastingView (`HomeView.swift:443, 593-601`); StressView treats fasting as a factor sheet (`StressView.swift:19, 198`); reports surface fasting × stress (`ReportSections/FastingSection.swift:32-44`).
- **Caffeine cutoff** (`Models/FastingSchedule.swift:100-101, 117-119`) — not in the blueprint but compatible with its autonomic-regulation angle. Keep.
- **Mid-fast schedule change is handled** (`FastingScheduleEditor.swift:43-48, 184-197`) with an explicit "End fast and apply new schedule" alert — better than the blueprint specifies.
- **Live Activity reconnect on relaunch** (`ActivityManager.swift:124-139`) — correctly ends a stale activity if its target end date has passed.

---

## 2. CRITICAL gaps — must close for v1

### 2.1 SCOFF screening + Care Intervention routing — **absent**
**Blueprint mandate:** Mandatory 5-question SCOFF gate in onboarding; ≥2 positive answers ⇒ soft-block fasting, route to wellness resources (e.g. National Alliance for Eating Disorders).
**Current state:** No onboarding flow exists for fasting at all. First-time setup goes straight from "Get Started" button (`FastingView.swift:203`) to the schedule editor.
**Required fields on `FastingSchedule` or new model:** `scoffCleared: Bool` (irreversible flag per blueprint Table 6).
**Risk if unaddressed:** Highest single regulatory/ethical liability in the feature.

### 2.2 Hard 24h cap + forgotten-stop guard — **absent**
**Blueprint mandate:** "Hardcoded maximum duration limit prevents the platform from implicitly endorsing medically risky multi-day starvation protocols." Auto-pause notification at 24h: *"Did you forget to log your meal? Tap here to adjust your end time."*
**Current state:** `FastingSession.actualDurationSeconds` (line 40-43) keeps counting indefinitely; nothing stops a runaway fast or warns the user.
**Where to implement:** New scheduled local notification in `FastingService.scheduleNotifications` + a sentinel check in `configureService()` / `handleStateTransition`.

### 2.3 Wellness disclaimer + age/pregnancy gate — **absent**
**Blueprint mandate:** Un-skippable disclaimer ("not medical advice, consult a provider"); fasting fully blocked for users <18 or pregnant/lactating.
**Current state:** No disclaimer, no demographic check. The app's onboarding (RootView → Onboarding) does not collect age or pregnancy status in a form usable here.
**Coordination needed:** Either reuse demographic data from main onboarding (verify it exists), or add a one-time fasting-specific gate.

### 2.4 Contextual HRV / Sleep insight under timer — **absent**
**Blueprint mandate:** *"Show me how my daily eating windows correlate with my overnight HRV and sleep architecture."* Dynamic text under timer: *"Your HRV is optimal today. A 14-hour rest aligns well with your recovery."*
**Current state:** `FastingView` does not query `HealthKitService` for HRV or sleep. The data exists elsewhere (`StressViewModel` already fetches HRV histories per memory), but isn't surfaced in the fasting timer card.
**Architecture note:** Avoid duplicating fetches — funnel through the existing `HealthKitService` and inject results into `FastingView` (likely via a small `FastingContextProvider`).

### 2.5 Stress-responsive recommendation — **absent**
**Blueprint mandate:** *"Your autonomic nervous system is showing signs of elevated stress today. Consider a shorter resting window (12 hours)…"*
**Current state:** No coupling between `StressReading` data and fasting recommendations.
**Where to implement:** Could be a banner above `todayInfoCard` in `FastingView`, computed from recent `StressReading` deltas (which the view already loads at `FastingView.swift:25, 35-41`).

### 2.6 LiveActivityIntent for "Break Fast" — **absent**
**Blueprint mandate:** *"Using standard AppIntent protocols will cause execution delays or compilation failures in the Live Activity context. LiveActivityIntent is mandatory."* Embed functional Break Fast / End button on Lock Screen.
**Current state:** `FastingLiveActivityView.swift` has zero interactive buttons. Users must unlock and open the app to break a fast.
**Implementation impact:** New `BreakFastIntent: LiveActivityIntent` in a shared module readable by both app and widget targets. State mutation will require an App Group write path so the intent (running in the widget process) can persist the break.

### 2.7 Edit previous fast (retroactive correction) — **absent**
**Blueprint mandate:** *"If a user forgets to interact, they must be able to tap 'Edit previous fast' seamlessly."*
**Current state:** History rows in `FastingView.swift:539-587` are display-only. No tap target, no edit sheet.

---

## 3. v1 boundary violations — code that must be REMOVED or HIDDEN

### 3.1 `ratio20_4` preset — **REMOVE**
**Location:** `Models/FastingSchedule.swift:9, 33, 47, 58, 67`
**Why:** A 20-hour fast is OMAD-adjacent. Blueprint v1 actively de-prioritizes the Endurance Faster persona because "catering to this persona requires complex medical approximations and risks alienating the primary user base." 20:4 specifically nudges Anxious Beginners toward extreme territory.
**Caveat — `.custom` still allows up to 23h** (`FastingSchedule.eatingWindowHours` clamps to `max(1, min(23, …))`, line 81). With the 24h hard cap (item 2.2), this is acceptable, but the preset itself is an editorial endorsement.

### 3.2 `ratio18_6` preset — **DECISION NEEDED**
Blueprint Table 3 explicitly approves only 12:12, 14:10, 16:8 as "pre-configured, evidence-based schedules." 18:6 sits in the gray zone — not endurance, but past beginner-friendly. Open question (see §7).

### 3.3 Punitive / urgent visual language in main UI
**Locations:**
- `FastingView.swift:554, 575` — fast-history row labels "Broken" in red (`Color.red`) when user ended early.
- `FastingView.swift:708` — `ringColor` returns `.orange` for fasting, `.green` for eating. Blueprint forbids "neon red or warning orange" associated with the elapsing timer.
- `FastingView.swift:425-436` — "Break Fast" button uses `.red` foreground + red-tinted background.
- `FastingView.swift:131-137` — alert copy: *"Ending now means this won't count as a completed fast."* This is the literal "punitive" phrasing the blueprint calls out as triggering for the Anxious Beginner.

**Blueprint replacement vocabulary:**
- "BROKEN" → "Ended early" (neutral, already used in some places)
- "Break Fast" CTA → "End Fast" or "I'm done" (less destructive verb)
- Alert body → *"Listening to your body is always the right choice. You've fasted for 11h 24m so far."*
- Ring color: drop red entirely; use the existing `heroAccent` palette only.

### 3.4 Punitive / urgent colors in Live Activity
**Locations:**
- `FastingLiveActivityView.swift:128, 167, 278-281` — `.red` for broken state in Lock Screen, Watch, Dynamic Island.
- `FastingLiveActivityView.swift:43, 167` — *"Fast ended early"* in red.

**Blueprint mandate:** *"Designers must avoid using urgent or alarm-state colors (e.g., neon red or warning orange) as the timer elapses."*
**Fix:** Use a muted neutral (e.g. `.white.opacity(0.55)`) for the broken state. The factual label is fine; the color is the violation.

### 3.5 State-pill copy: `"FASTING"` / `"EATING"`
**Location:** `FastingView.swift:692-698`
**Blueprint mandate:** Frame as "Digestive Rest" / "Eating Window" — biological/calm, not state-machine output.
**Suggested mapping:**
- `FASTING` → `RESTING` or `DIGESTIVE REST`
- `EATING` → `EATING WINDOW` (already used in `todayInfoCard` — be consistent)
- The pill label `"READY TO FAST"` (line 703) → `"READY TO REST"` or `"READY WHEN YOU ARE"`.

### 3.6 Notification copy lacks circadian framing
**Location:** `FastingService.scheduleNotifications` (`FastingService.swift:209-263`)
- `"Eating Window Closed"` body `"Your 16:8 fast has begun"` — neutral, acceptable but missable.
- `"Fast Complete"` body `"Your eating window is open."` — fine.
**Blueprint preferred copy** (Table 7):
- Start reminder → *"The sun is setting. It's a great time to give your digestion a rest before bed."* (tied to sunset API or N hours before tracked sleep)
- Milestone reached → *"You've reached your 12-hour goal. Break your fast whenever you feel ready."*
- Contextual intervention → *"Your sleep score was unusually low last night. Listen to your body — it's okay to end your fast early today."*

The current notifications fire on a `UNCalendarNotificationTrigger` based on the fixed schedule. The blueprint's sunset-aware reminders need a different scheduling pass that runs daily (e.g. on app open) and re-targets the trigger using `CLLocation` + sunset.

---

## 4. Data model gaps

`FastingSession` currently exposes a binary `completed: Bool`. Blueprint Table 5 specifies a 3-state `completionStatus: Enum (completed | endedEarly | overachieved)`. Today the schema cannot distinguish "user ran past target end" (overachieved) from "user broke early" — both end up with `completed = false` if the fast was ended manually pre-target, or `completed = true` if reached the schedule's eating window. There is no representation of "kept fasting past target."

**Additional fields blueprint calls for:**
- `contextualHRV: Double?` — bind morning HRV to the fast.
- `contextualSleepScore: Int?` — bind prior night sleep quality.

**`UserPreferences` entity:**
- `targetSchedule: Enum` — already stored as `FastingSchedule.scheduleType`. ✓
- `scoffCleared: Bool` — see §2.1.

**Recommendation:** Schema migration is required for v1. Plan it carefully — `FastingSession` is `@Model` with no migration plan in the codebase right now.

---

## 5. UX flow gaps

| Blueprint flow | Current state |
|---|---|
| Onboarding screen 1: "Resting your digestion / aligning with body clock" | None — straight into schedule editor |
| Onboarding screen 2: SCOFF gate | None |
| Onboarding screen 3: schedule selection **defaulting to 12:12** | Defaults to 16:8 (`FastingSchedule.swift:105`) |
| "Empty state" inside Fasting view shows next optimal start time | Partial — `activeTimerCard` shows time remaining but no "aim to start your rest at 7:00 PM" |
| Active state — calm colors, contextual data layers under timer | Calm gradient ✓; contextual data layers ✗ |
| Completion — soft "continues counting bonus time", no hard cutoff | Hard cutoff to celebration overlay; no bonus-time concept |
| Re-entry after abandonment — no guilt | ✓ Empty state is neutral |
| Weekly 7-day consistency grid | Have flat list of 7 most recent (`FastingView.swift:46, 510-551`), not a calendar grid |

**Default-to-12:12 is meaningful** — blueprint says: *"defaulting to a highly achievable 12-hour cycle to guarantee early psychological success."* 16:8 default is a real beginner trap.

**12:12 preset is missing entirely** from `FastingScheduleType` (`Models/FastingSchedule.swift:5-91`). Must be added.

---

## 6. Integration gaps

### 6.1 Home dashboard "Digestive State" card — missing
**Current:** Home has a `headerAssetIcon("fasting_icon")` button (HomeView.swift:593-601) that opens FastingView as a sheet — just a launcher.
**Blueprint:** A persistent dashboard card showing "Active / Inactive" digestive state and a daily readiness layer (Sleep + Stress + Nutrition).
**Implication:** New Home card component. Likely belongs with the existing `WellnessRingsCard` / `DailyInsightCard` family in `Features + UI/Home/Components/`.

### 6.2 Stress factor card → Fasting sheet
Already wired (`StressView.swift:19, 198`, `StressV3Sheets.swift:96`). ✓

### 6.3 Reports → fasting summary
Already wired (`ReportSections/FastingSection.swift`). ✓ Worth verifying the report uses neutral copy after §3 changes — currently it says "Fasting" / "Non-fasting" which is fine, no "broken" or "failed" in this view.

### 6.4 Live Activity / App Intents file location
Currently `Cadence/Widgets/FastingActivityAttributes.swift` is in the main app target. For the new `LiveActivityIntent` to be callable from the widget extension, it must live in a target both can see (App Group + framework or membership in both). Worth verifying current target membership of `FastingActivityAttributes.swift` — if it's app-only, the widget shouldn't be compiling against it, which means there's already a shared-membership setup that the new intent can piggyback on.

---

## 7. Open questions blocking implementation

These need user/PM resolution before a plan can be written:

1. **Drop `ratio18_6`?** Blueprint Table 3 only blesses 12:12, 14:10, 16:8. The current code ships 16:8, 14:10, 18:6, 20:4, Custom. Decision needed: drop 18:6, keep 18:6, keep but de-emphasize?
2. **Schema migration approach.** Adding `completionStatus` enum + `contextualHRV` + `contextualSleepScore` to `FastingSession` requires a SwiftData migration plan. No `SchemaMigrationPlan` exists in this repo today. Are we OK with a heavyweight migration, or do we keep the binary flag and add new optional fields only?
3. **Age / pregnancy data source.** Does existing onboarding already collect DOB and pregnancy status? If yes, reuse. If no, add a one-time fasting gate.
4. **Sunset-aware start reminder feasibility.** Requires `CLLocation` (coarse) permission — the app may not already request location. Acceptable to add a new permission for this v1 feature, or defer the circadian notification to v1.1?
5. **Bonus-time UI on completion.** Blueprint wants the timer to "continue counting bonus time softly" rather than fire a hard celebration. Current overlay is a strong celebration with confetti and haptics. Soften, replace, or keep both (soft pulse → user explicitly ends fast → celebration)?
6. **SCOFF positive — soft block scope.** Does a positive SCOFF prevent only future fasts, also hide all fasting UI from Home/Stress/Reports, or just warn? Blueprint says "soft block fasting" — interpretation has UX implications across multiple surfaces.
7. **24h cap behavior.** Auto-end at exactly 24h, or auto-pause + notify and let user adjust the end time? Blueprint suggests the latter ("Tap here to adjust your end time"), but auto-end is simpler and safer.

---

## 8. Suggested next step

This audit is intentionally a finding document, not a plan. Likely next moves (your call):

- Run `/develop plan fasting-v1-blueprint` feeding this audit + the blueprint as inputs to produce a structured implementation plan, OR
- Resolve §7 open questions first, then plan, OR
- Pick a single high-leverage slice (SCOFF gate, or LiveActivityIntent, or copy pass + 20:4 removal) and implement directly.

The lowest-risk high-impact slice is the **copy/lexicon + 20:4 removal + ring-color** pass (§3.1, §3.3, §3.4, §3.5) — pure UI/string work, no schema or new dependencies, immediately closes most of the "Anxious Beginner" violations.

The highest-impact slice is **SCOFF + 24h cap + age gate** (§2.1, §2.2, §2.3) — the regulatory/safety core.
