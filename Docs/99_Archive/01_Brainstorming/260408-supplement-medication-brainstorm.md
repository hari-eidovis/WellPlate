# Brainstorm: Supplement / Medication Reminders

**Date**: 2026-04-08
**Status**: Ready for Planning
**Roadmap**: F6 — Phase 2 (Engagement Layer), pairs with F5

## Problem Statement

Users of wellness and nutrition apps explicitly ask for supplement tracking but almost no app does it well. The common failure modes are: too complex (requires a medication database), too simple (just a checklist with no insight), or too clinical (feels like a medical app, not a wellness companion). WellPlate's opportunity is different: we already have symptom tracking (F5), stress signals, and a daily log infrastructure. A supplement/medication feature that connects adherence to outcomes — "did taking your magnesium correlate with fewer headaches?" — is a genuinely differentiated value proposition. HealthKit's new Medications API means we don't need to own the medication database; we can read from what users already have in the Health app.

## Core Requirements

- R1: Add supplements/medications with name, dose, frequency, and scheduled times
- R2: Daily reminder notifications at scheduled times
- R3: Adherence log — mark doses as taken, skipped, or late
- R4: Adherence streak + calendar view
- R5: Correlation with F5 symptom data (does taking X correlate with fewer Y?)
- R6: HealthKit Medications API read (display existing Health app medications — no need to sync back)
- R7: Export integration — add adherence to existing CSV pipeline
- R8: All data on-device (SwiftData)

## Constraints

- **No medication database**: Don't build a drug interaction database or dosing lookup. User types their own supplement/medication names.
- **Non-diagnostic**: Never suggest what to take, how much, or interpret clinical significance. Pure tracking and correlation.
- **Notification permission**: Already established in `FastingService.swift` — reuse the exact same pattern (`UNCalendarNotificationTrigger`, on-demand permission request).
- **HealthKit Medications API**: Read-only. Display what's in Health app as a convenience; don't write back.
- **Profile tab is home**: Medications/supplements live in the Profile tab alongside symptom tracking, not as a new tab.
- **SwiftData**: New models must register in `WellPlateApp.swift`. Currently 11 models in the container.

## Existing Infrastructure Ready to Use

| Asset | What it provides |
|-------|-----------------|
| `FastingService.swift` — `UNCalendarNotificationTrigger` pattern | Exact notification scheduling code to copy |
| `FastingSchedule.swift` — time-window scheduling model | Template for `MedicationSchedule` (scheduled times, repeat days, active flag) |
| `SymptomEntry.swift` + `SymptomCorrelationEngine.swift` | F5 correlation engine can be extended for symptom ↔ adherence correlation |
| `ProfileSheet` enum + profile card pattern | Adding a medication card follows exact same pattern as symptom card added in F5 |
| `WellnessReportGenerator.swift` — extended CSV pipeline | Add adherence columns the same way symptom columns were added |
| `SymptomHistoryView.swift` — grouped chronological list | Adherence history can follow identical grouped-by-date pattern |
| HealthKit Medications API (iOS 2025+) | Read existing Health app medications without building a drug database |

---

## Approach 1: Supplement-First, Medications Optional

**Summary**: Build around supplements (vitamins, minerals, protein powder, etc.) as the primary use case since that's where user demand is highest and the stakes are lowest. Medications can be added with the same model but flagged differently. HealthKit medication read is a "nice to have" import, not the core flow.

### Architecture
- `SupplementEntry` @Model: name, dosage string, category (vitamin, mineral, probiotic, custom), schedule times array, active, notes
- `SupplementAdherenceLog` @Model: date, supplementEntryID, status (taken/skipped), takenAt timestamp
- `SupplementService`: notification scheduling, adherence tracking
- UI: `SupplementListView` (profile card), `SupplementDetailView`, `AdherenceCalendarView`
- Adherence log: swipe or tap to mark doses

**Pros:**
- Lower stakes — supplements aren't prescription medications; no clinical risk
- Higher user adoption — more people take supplements than have prescribed medications
- Natural fit with nutrition tracking (protein, creatine, omega-3 all relate to diet)
- Simpler HealthKit integration — supplement info is less structured in HealthKit

**Cons:**
- "Medications" in the feature name suggests clinical use; disappoints those expecting medication reminders
- Misses the HealthKit Medications API value proposition

**Complexity**: Low–Medium
**Risk**: Low

---

## Approach 2: HealthKit-First — Read Medications, Add Supplements

**Summary**: Primary entry point is reading from the Health app's Medications list. User authorizes HealthKit medication access; WellPlate imports their medications as reminders and adds a manual supplement layer on top.

### Architecture
- `MedicationService`: reads `HKClinicalType.medicationRecord` from HealthKit
- Maps HealthKit medication records to local `MedicationEntry` model
- User can add supplements manually (not from HealthKit)
- Separate log: `AdherenceLog` tracks both HealthKit-imported meds and manual supplements
- Notifications for all items

**Pros:**
- Zero medication data entry for users with medications already in Health app
- HealthKit is the authoritative source — no conflicting databases
- Clinician-export story is strong ("my Health app medications + adherence")

**Cons:**
- HealthKit Medications API availability varies (requires user to have medications in Health)
- Clinical record authorization is more sensitive — users may be wary
- Adds complexity: need to handle imported vs. manual entries separately
- Many users don't have medications in Health app yet — feature feels empty on first launch

**Complexity**: Medium
**Risk**: Medium (HealthKit authorization UX is more complex for clinical data)

---

## Approach 3: Unified Tracker — Supplements + Medications, Same Model

**Summary**: One unified "Health Regimen" tracker that treats supplements and medications identically. User adds items manually (name, dose, time). HealthKit import is an optional enhancement (import button, not required). F5 correlation engine extended to show "adherence ↔ symptom" patterns.

### Architecture
- `SupplementEntry` @Model (name "supplement" avoids clinical connotations):
  - `name`, `dosage`, `category` (vitamin/mineral/omega/probiotic/medication/custom)
  - `scheduledTimes: [Int]` (array of minutes-from-midnight, e.g. [480, 1200] = 8am + 8pm)
  - `activeDays: [Int]` (0=Sun…6=Sat, empty = every day)
  - `isActive: Bool`
  - `notes: String?`
  - `startDate: Date`
- `AdherenceLog` @Model: `day`, `supplementID`, `scheduledTime`, `status` (taken/skipped/pending), `takenAt`
- `SupplementService`: schedule notifications, update adherence, cancel on deactivate
- HealthKit import: optional "Import from Health" button that calls Medications API and pre-populates entries
- Correlation: extend `SymptomCorrelationEngine` to accept adherence data as a factor

**Pros:**
- Unified model simplifies code — no need to distinguish between supplement and medication types
- "Category: medication" handles clinical use without clinical risk
- HealthKit import is discoverable but not required
- Direct F5 synergy: adherence % per day becomes a new correlation factor
- Follows FastingSchedule pattern exactly (scheduledTimes, activeDays, isActive)

**Cons:**
- "Supplement" framing may feel wrong to users tracking prescription medications
- Adherence log needs careful design to avoid notification fatigue (too many reminders)
- scheduledTimes as `[Int]` (minutes from midnight) requires conversion UI

**Complexity**: Medium
**Risk**: Low–Medium

---

## Approach 4: Minimal MVP — Reminder Checklist Only

**Summary**: Strip the feature to its simplest form: a daily checklist of supplements/medications with reminder notifications and a streak counter. No correlation, no HealthKit, no adherence calendar. Ship fast, add depth in v2.

### Architecture
- `SupplementEntry` @Model: name, dosage, time, active (just 4 fields)
- Daily notifications
- Home or Profile shows today's checklist with tap-to-check
- Streak counter (consecutive days of full adherence)
- No correlation, no export, no HealthKit

**Pros:**
- Fastest to ship (2–3 new files)
- Zero risk of over-engineering
- Users can start tracking immediately

**Cons:**
- No differentiation from a basic reminder app
- Misses the key WellPlate value: "connect everything"
- Won't justify subscription value
- Frustrating to use after F5 adds rich correlations — feels like a step backward

**Complexity**: Low
**Risk**: Low

---

## Edge Cases to Consider

- [ ] **Notification fatigue**: User has 5 supplements × 2 times/day = 10 notifications. Need per-supplement toggle + a "quiet mode" option
- [ ] **Missed dose**: What happens when user misses a dose? Auto-mark as skipped at end of day? Or leave pending forever?
- [ ] **Dose tracking vs. adherence**: Some supplements taken "as needed" (e.g., pain relief). Model needs an optional schedule
- [ ] **Multiple doses same supplement per day**: e.g., Vitamin C 3x/day — schedule times array handles this
- [ ] **HealthKit authorization**: Clinical record access requires explicit user authorization; some users may be uncomfortable. Always explain why.
- [ ] **Supplement name normalization**: "Vit D", "Vitamin D", "D3" are all the same — no auto-normalization, just display as entered
- [ ] **Start/end date**: Some medications are temporary (e.g., antibiotics for 10 days). Need optional end date.
- [ ] **Correlation with no variance**: If user takes supplement every single day, there's no variance in adherence to correlate against. Need to handle and explain.
- [ ] **SwiftData migration**: Adding 2 new models is additive — no migration needed
- [ ] **Notification ID uniqueness**: Multiple supplements with overlapping times need distinct notification IDs. Use `"supplement_\(id)_\(time)"` pattern.
- [ ] **Export sensitivity**: Medication names are personal health data. Export should be clearly opt-in, labeled.

## Open Questions

- [ ] Should the feature be called "Supplements" or "Health Regimen" or "Medications & Supplements"?
- [ ] Should adherence correlation use the existing `SymptomCorrelationEngine` (extend it) or a simpler, separate engine?
- [ ] How many reminders is too many? Should there be a daily cap?
- [ ] Should HealthKit medication import require a separate onboarding step or be discoverable in the UI?
- [ ] Should unscheduled (as-needed) supplements be supported in MVP?

## Recommendation

**Approach 3 (Unified Tracker)** with Approach 1's supplement-first framing.

### Rationale
1. **Unified model wins**: `SupplementEntry` with a `category` field handles both supplements and medications without code duplication. Category `.medication` covers clinical use; no separate database or model needed.
2. **F5 synergy is the key differentiator**: Extending `SymptomCorrelationEngine` to include adherence as a factor creates the "did my magnesium help my headaches?" insight that no basic reminder app offers. This is WellPlate's unique value.
3. **FastingSchedule pattern is battle-tested**: The `scheduledTimes + activeDays + isActive` pattern from FastingSchedule.swift is exactly what medication scheduling needs. Reuse aggressively.
4. **Notification pattern proven**: `FastingService.swift` already has the full notification scheduling pattern. Copy-adapt, don't reinvent.
5. **HealthKit import = optional delight**: Available as an "Import from Health" CTA, not a required first step. Users without medications in Health still get full value.
6. **Profile tab fits naturally**: Medication card follows the same pattern as symptom card (F5) — insert between symptom insights and widget setup.

### Key design decisions for planning
- **`SupplementEntry` not `MedicationEntry`** — "supplement" is less clinical, matches broader user base
- **`scheduledTimes: [Int]` as minutes from midnight** — matches iOS calendar notification trigger pattern
- **`AdherenceLog` @Model** — separate from `SupplementEntry` to avoid bloating; one record per scheduled dose per day
- **Notification IDs**: `"supplement_\(entry.id.uuidString)_\(timeMinutes)"` pattern for uniqueness
- **Correlation extension**: Add `adherenceByDay: [Date: Double]` (0.0–1.0 = percent of doses taken) as a new factor in the existing engine
- **HealthKit import**: Optional; button in supplement list to read `HKClinicalType.medicationRecord` if available
- **CSV export**: Add `supplement_adherence_pct` column (0–100%) to existing report

## Research References

- Deep research report: "HealthKit now has a Medications API" + "Good if you connect it to symptom tracking" (lines 458–474)
- `FastingService.swift` — proven notification scheduling pattern (lines 186–273)
- `FastingSchedule.swift` — time-window model pattern directly reusable
- `SymptomCorrelationEngine.swift` (F5) — 7-factor Spearman engine extensible to adherence
- `ProfileSheet` enum (F5) — profile card insertion pattern
- `WellnessReportGenerator.swift` (F5) — CSV extension pattern
