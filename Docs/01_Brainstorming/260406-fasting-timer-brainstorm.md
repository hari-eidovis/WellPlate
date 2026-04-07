# Brainstorm: Fasting Timer / Intermittent Fasting Tracker

**Date**: 2026-04-06
**Status**: Ready for Planning

---

## Problem Statement

WellPlate already tracks nutrition (calories, macros), caffeine, hydration, sleep, and stress. Intermittent fasting is one of the most searched nutrition behaviors in the App Store — top competitors market it as a core feature. But the WellPlate differentiator isn't "track calories in a fasting window" — it's **"what does fasting do to your stress score, sleep quality, and energy?"** 

The goal is: build a fasting timer that feels native to WellPlate's multi-signal stress identity, not a clone of MyFitnessPal's fasting add-on.

---

## Core Requirements

- Define an eat window (start + end time) or a fast duration (e.g., 16h)
- Display the current fasting state (fasting vs. eating) with time remaining
- Notify the user when the fast ends and when the eat window closes
- Log each fasting session for retrospective analysis
- Surface a "fasting vs. stress score" correlation — the differentiating insight
- Optionally pair caffeine cutoff time with fasting window boundaries

---

## Constraints

- Local-only (SwiftData); no backend
- No new framework entitlements needed for MVP (Phase 3 adds ActivityKit for Live Activities)
- Must fit WellPlate's visual language: dark card backgrounds, `appShadow`, `.r()` fonts, semantic colors
- `WellPlateApp.swift` model container must be updated to include new `@Model` types
- `InterventionTimer` exists but is phase-array-based (breath cycles, muscle groups) — reuse shape only, not the same class
- Notifications: `UNUserNotificationCenter` — already used by the app? Need to verify
- MVP should not require Watch (planned in Phase 3 as F8)

---

## Approach 1: Home Tab Card (Inline)

**Summary**: A fasting status card lives directly in the Home tab scroll view, between the meal log and daily summary, updating in real time.

**How it works**:
- Card shows: current state ("Fasting" / "Eating"), ring or linear progress, time remaining
- Tap card → sheet to configure schedule and view history
- Entry point: `HomeView` main scroll — add `FastingStatusCard` between existing cards

**Pros**:
- Highest discoverability — Home tab is the daily loop entry
- Natural placement: next to food logging and calorie ring
- Doesn't compete with Stress tab real estate (already content-dense)
- Consistent with how `MoodCheckInCard` and `WaterTrackingCard` live in Home

**Cons**:
- Home tab scroll is already dense (meal log, activity rings, wellness calendar)
- Fasting insight (stress correlation) is disconnected from the Stress tab where it would be most meaningful
- Card is always visible even when user hasn't enabled fasting

**Complexity**: Low | **Risk**: Low

---

## Approach 2: Stress Tab Integration (Factor Card)

**Summary**: Fasting state becomes a 5th factor card in the Stress tab, alongside Sleep, Diet, Exercise, and Screen Time.

**How it works**:
- "Fasting" factor card shows: current window adherence score, tap → opens fasting detail sheet
- Stress score algorithm gains a `fastingFactor` input: adherence to chosen schedule → 0–100 sub-score
- Fasting sheet: configure schedule, view current timer, see "fasting vs. stress" chart

**Pros**:
- Deep integration — fasting becomes a first-class stress factor, not a standalone tracker
- Surfaces the unique WellPlate angle: "fasting's effect on stress score"
- Reuses the established `StressFactorCardView` pattern

**Cons**:
- StressView main scroll already has 4 factor cards + vitals grid + Stress Lab card — adding a 5th card increases scroll depth
- Changing the stress score formula mid-product adds regression risk to a feature users already trust
- Fasting is opt-in; a permanent card for an unconfigured feature creates empty-state noise

**Complexity**: Medium | **Risk**: Medium (stress score formula change)

---

## Approach 3: Dedicated Sheet from Stress Toolbar Menu

**Summary**: Fasting timer lives in a full-screen sheet, accessed from the Stress tab toolbar menu (same pattern as "Lab" and "Interventions").

**How it works**:
- Toolbar `Menu` gains a third item: "Fast" (icon: `fork.knife.circle`)
- Sheet: `FastingView` with 3 sub-sections: timer ring, schedule configurator, history + insight chart
- New `StressSheet` case: `.fasting`
- Standalone model: `FastingSchedule` (SwiftData) + `FastingSession` (SwiftData)

**Pros**:
- Precedent established by Stress Lab and Interventions — toolbar menu pattern is well-tested
- Keeps StressView scroll uncluttered
- Full-screen sheet allows rich timer UI without space constraints
- Fasting insight chart naturally lives here next to the stress score context

**Cons**:
- Less discoverable than a Home tab card — users must know to look in the Stress toolbar
- Fasting is conceptually related to food (Home tab) not stress, which could be confusing

**Complexity**: Low | **Risk**: Low

---

## Approach 4: Hybrid — Home Glance Card + Stress Sheet

**Summary**: A compact glance card in Home tab shows the live fasting state (read-only, 1 line of text + color dot). Tapping it deep-links into the full `FastingView` sheet accessible from the Stress toolbar.

**How it works**:
- `FastingGlanceCard` in Home: "Fasting · 11h 22m remaining" with a thin progress bar. Only visible if user has configured a schedule. Hidden by default (zero height) until first configuration.
- Full UI lives in Stress tab sheet (Approach 3)
- Deep link: tap Home glance card → opens Stress tab → triggers `.fasting` sheet

**Pros**:
- Best of both: discoverability in Home + rich detail in Stress context
- Glance card is opt-in (hidden until configured) — no empty-state clutter
- Deep link feels seamless and native
- Aligns fasting insight with stress score context (most meaningful placement)

**Cons**:
- Cross-tab deep link adds navigation complexity (need to communicate between TabView and sheets)
- More surface area than Approach 3 alone — 2 things to maintain instead of 1

**Complexity**: Medium | **Risk**: Low–Medium

---

## Approach 5: Profile Tab Configuration + Notification-Only

**Summary**: Fasting is purely a background tracker — user sets a schedule in Profile settings, receives push notifications at fast start/end, and fasting data shows up silently in weekly reports.

**How it works**:
- `ProfileView` → "Fasting Schedule" section → configure window
- `UNUserNotificationCenter` fires at fast start and end
- `WellnessReportGenerator` includes fasting adherence in weekly report
- No dedicated UI beyond settings and reports

**Pros**:
- Minimal UI surface — lowest implementation cost
- Notifications are the main value touchpoint (when to eat, when to fast)
- Zero clutter in any primary view

**Cons**:
- No live timer → users who open the app can't see fasting state at a glance
- Very low perceived value — feels incomplete vs. competitors' fasting features
- No direct "fasting vs. stress" visual correlation

**Complexity**: Low | **Risk**: Low (but low value)

---

## Data Model Considerations

### Option A: New SwiftData models (recommended)
```swift
@Model final class FastingSchedule {
    var scheduleType: String    // "16:8", "14:10", "18:6", "custom"
    var eatWindowStart: Date    // time-of-day reference (only H:mm matters)
    var eatWindowDuration: TimeInterval  // hours
    var isActive: Bool
    var caffeineCutoffEnabled: Bool
    var caffeineCutoffMinutesBeforeWindowEnd: Int  // e.g. 120 = 2h before eating ends
}

@Model final class FastingSession {
    var startedAt: Date
    var targetEndAt: Date
    var actualEndAt: Date?      // nil = in progress
    var completed: Bool         // false if user broke early
    var scheduleType: String
}
```

### Option B: Extend WellnessDayLog
Add `fastingAdherenceMinutes: Int` and `fastingScheduleType: String?` to the existing daily model.

**Trade-off**: Option A is cleaner (sessions need start/end timestamps that don't fit the one-row-per-day model), but adds 2 new SwiftData types to the model container. Option B is simpler but lossy (can't reconstruct exact session history).

**Recommendation**: Option A — the session granularity is needed for the stress correlation chart.

---

## Notification Strategy

- **Fast start notification**: "Your eating window is now closed. 16-hour fast begins." (scheduled at `eatWindowEnd`)
- **Approaching fast end**: "1 hour left in your fast." (scheduled at `fastEnd - 1h`)
- **Fast complete**: "Fast complete ✓ Your eating window is open." (scheduled at `fastEnd`)
- **Caffeine cutoff**: "Last call for caffeine — cutoff in 30 min." (if enabled)
- All via `UNCalendarNotificationTrigger` repeating daily

---

## Fasting × Stress Insight

The key differentiator. Two visualization options:
1. **Scatter plot**: each day = a point, X = fasting duration, Y = that day's stress score (7-day window)
2. **Split bar**: "Fast days" avg stress vs "Non-fast days" avg stress — simple, honest, no implied causality

Recommendation: split bar with "n = X days" label and "correlation ≠ causation" footnote (consistent with Stress Lab tone).

---

## Edge Cases to Consider

- [ ] User hasn't configured a schedule yet → zero-state UI (configure CTA, not empty card)
- [ ] User changes schedule mid-fast → prompt: "You have an active fast. Apply to next day?"
- [ ] Midnight-spanning fasts (e.g., 8pm fast start → 12pm next day end) → `FastingSession.startedAt` / `targetEndAt` must be full `Date`, not time-of-day
- [ ] Multiple schedule changes in the same day → keep only one active `FastingSchedule` at a time
- [ ] App killed during active fast → timer rebuilds from `FastingSession.startedAt` on next launch
- [ ] Stress data unavailable for correlation (new user) → hide correlation card, show "Log 7 days to see pattern"
- [ ] No HealthKit permission → fasting timer still works (doesn't require HK); correlation may use SwiftData stress scores only
- [ ] Caffeine cutoff after eat window end → validate: cutoff must be within eat window
- [ ] iOS background refresh limits → use `UNUserNotificationCenter` scheduled notifications (not background tasks) for reliable timer end alerts

---

## Open Questions

- [ ] Should the fasting schedule be per-day (custom Mon–Fri vs. weekend) or one fixed schedule?
- [ ] Should breaking a fast early (tapping "End fast now") be explicitly tracked with a reason?
- [ ] Is the caffeine cutoff tie-in a Phase 1 MVP item or a Phase 2 polish?
- [ ] Does the stress correlation chart belong in the `FastingView` sheet or as a new `StressSheet` case?
- [ ] Should `FastingSession` be included in `WellnessReportGenerator` CSV export in Phase 1?

---

## Recommendation

**Approach 4 (Hybrid) scoped down to Approach 3 for MVP, with Approach 4 as a fast follow.**

Rationale:
- Approach 3 (Stress toolbar sheet) is the correct first ship — lowest risk, established pattern, allows rich UI
- The Home glance card (Approach 4 addition) ships in Phase 1 polish once the core timer is stable
- Cross-tab deep link is unnecessary complexity for MVP — just two entry points (Stress toolbar + Home card tap → same sheet)
- Stress score formula stays unchanged in Phase 1 — fasting is correlation insight only, not a new factor input

**MVP scope** (Phase 1):
1. `FastingSchedule` + `FastingSession` SwiftData models
2. `FastingView` full-screen sheet: live timer ring, schedule configurator, 7-day history
3. `StressSheet.fasting` case in StressView toolbar menu
4. Scheduled notifications: fast start, fast end, 1h warning
5. Fasting × stress split-bar chart (requires ≥7 days of data)
6. Caffeine cutoff integration with existing `coffeeCups` tracking

**Phase 1 polish** (after MVP is stable):
- `FastingGlanceCard` in Home tab (opt-in, hidden until configured)
- `WellnessReportGenerator` fasting adherence row in CSV

---

## Research References

- Deep research report: `Docs/06_Miscellaneous/deep-research-report-2.md` (Fasting Timer section, p.4)
- Roadmap: `Docs/02_Planning/260406-10-feature-roadmap.md` (F1)
- `InterventionTimer.swift` — phase-array timer pattern (reuse shape, not class)
- `StressLabView.swift` — toolbar sheet entry point pattern to replicate
- `WellnessDayLog.swift` — existing daily model (Option B anchor)
- `WellPlateApp.swift` — model container (must add new @Model types here)
