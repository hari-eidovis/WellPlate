# Implementation Checklist: Fasting v1 Blueprint — RESOLVED

**Source Plan:** `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan-RESOLVED.md`
**Source Checklist:** `Docs/04_Checklist/260527-fasting-v1-blueprint-checklist.md`
**Source Audit:** `Docs/03_Audits/260527-fasting-v1-blueprint-checklist-audit.md`
**Date:** 2026-05-27
**Sequencing:** Phase −1 ships first (entitlements PR). Phases 0+1+2+3 → v1.0.0. Phase 4 → v1.0.1. Phase 5 → v1.1.0. Phase 6 → v1.2.0. Phases 7+8 → v1.3.0.

---

## Audit Resolution Summary

| ID | Severity | Verdict | Resolution |
|---|---|---|---|
| **CC1** | CRITICAL | ✅ Resolved | Phase 1.4 Home routing **removed**. v1.0.0 ships with FastingView empty-state CTA + Stress factor sheet as the only entry points. Home access-state routing is built fresh inside `DigestiveStateCard` in Phase 7. Eliminates duplicate work + merge risk. |
| **CH1** | HIGH | ✅ Resolved | New `SleepQuality → Int` mapping helper on `SharedHealthMetrics` (excellent→95, good→80, fair→60, poor→35). Used consistently in 5.1, 5.2, 5.3, 5.4. Insight banner threshold: `score < 70` (= fair or poor). |
| **CH2** | HIGH | ✅ Resolved | All references to `summary.startTime` corrected to `summary.bedtime` (verified field in `DailySleepSummary` at `HealthModels.swift:99`). |
| **CH3** | HIGH | ✅ Resolved | All `HealthKitService.shared` references corrected to `HealthKitServiceFactory.shared` (returns `HealthKitServiceProtocol`). `FastingContextProvider` and `FastingBedtimeHeuristic` take the protocol type, not the concrete class. |
| **CH4** | HIGH | ✅ Resolved | Phase 2.5 specifies elapsed-time computation: `let elapsed = Date().timeIntervalSince(state.fastStartDate)`. `updateFastingActivity(progress:)` signature unchanged. |
| **CH5** | HIGH | ✅ Resolved | Phase 4.3 placeholder `FastingCompletionEvent(...)` replaced with explicit `FastingCompletionEvent(durationHours: session.actualDurationHours, scheduleLabel: schedule.displayLabel)`. |
| **CM1** | MEDIUM | ✅ Resolved | New AppConfig debug-only `fastingAccessOverride: FastingAccessOverride` (`.none | .blocked | .granted | .live`). Routing helper consults override first. Pre-Phase 0 step added to AppConfig.swift. |
| **CM2** | MEDIUM | ✅ Resolved | Post-Implementation success-criteria walkthrough expanded to 1:1 with plan (23 items, including 3 access-state branches separately + 4 accessibility sub-checks). |
| **CM3** | MEDIUM | ✅ Resolved | Phase 6.5 explicitly framed as "NEW vs Phase −1.4" — −1.4 proves App Group reads/writes work in Release; 6.5 proves the intent runs in the widget process and the app reconciles correctly. |
| **CM4** | MEDIUM | ✅ Resolved | Phase 7.3 verify step converted to manual: launch app with pre-existing layout; `.fasting` appears at end without reset. Points at likely failure mode (decoder not calling `reconcileWithCurrentCards()`). |
| **CM5** | MEDIUM | ✅ Resolved | Phase 3.4 deleted as a separate step; the work was already covered in Phase 0.5. Phase 3 build now skips directly from 3.3 (notification copy) to 3.5 (build + walkthrough). |
| **CM6** | MEDIUM | ✅ Resolved | New step 1.2.0 added: add `var embedded: Bool = false` to `FastingScheduleEditor.swift`. When true, omit NavigationStack/toolbar; surface Save via parent flow's button. |
| **CM7** | MEDIUM | ✅ Resolved | Phase 7.4 `DigestiveStateCard` snippet now includes `.onAppear { fastingService.configure(...) }` + `.onChange(of: scenePhase)` re-configuration. |
| **CL1** | LOW | ✅ Resolved (by CH1–CH3) | All `...` placeholders for sleep score / field names / DI eliminated. |
| **CL2** | LOW | ✅ Acknowledged | Suggested commit messages kept; no project convention to enforce. |
| **CL3** | LOW | ✅ Resolved | New pre-check at start of Phase 6.1: grep pbxproj for `Cadence/Widgets/` sync-group inclusion in CadenceWidget target. If missing, add file to both targets via Xcode UI before writing intent. |

**Verdict: ALL RESOLVED.** Checklist is ready for `/develop implement`.

---

## Pre-Implementation

- [ ] Read `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan-RESOLVED.md` end-to-end
- [ ] Read this RESOLVED checklist's Audit Resolution Summary above
- [ ] Verify branch state — `git status` clean, branched off `main`
- [ ] Confirm Xcode + iOS SDK versions match repo (iOS 26.1, Xcode 26)
- [ ] Run baseline build (all 4 targets):
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`

---

## Phase −1: App Group entitlement alignment (Pre-flight)

> **REQUIRES USER APPROVAL** per `MEMORY.md` `feedback-signing-entitlements` rule.

### −1.1 — User approval gate

- [ ] **STOP and ask user**: "About to edit `Cadence/Cadence.entitlements` to change App Group from `group.com.hariom.cadence.dev` to `group.com.hariom.cadence`. Approve?"
  - Verify: explicit user "yes" recorded

### −1.2 — Provisioning profile verification

- [ ] Open Apple Developer console; confirm Release distribution provisioning profile includes the `group.com.hariom.cadence` App Group capability
- [ ] If missing: add it, regenerate profile, install in Xcode
  - Verify: `security cms -D -i <profile>.mobileprovision | grep group.com.hariom.cadence` returns match

### −1.3 — Entitlement edit

- [ ] Edit `Cadence/Cadence.entitlements` line 15: `<string>group.com.hariom.cadence.dev</string>` → `<string>group.com.hariom.cadence</string>`
  - Verify: `grep "group.com.hariom.cadence" Cadence/Cadence.entitlements Cadence/CadenceDebug.entitlements CadenceWidget/CadenceWidget.entitlements` shows the same non-`.dev` ID in all three

### −1.4 — Build + TestFlight verification

- [ ] Archive for Release in Xcode (Product → Archive)
  - Verify: archive succeeds without signing errors
- [ ] Upload to TestFlight
  - Verify: TestFlight build processed without entitlement warnings
- [ ] Install on device; open Stress widget; confirm live data displays (not placeholder)
  - Verify: widget shows current stress score — proves App Group UserDefaults works end-to-end in Release

### −1.5 — Commit + ship

- [ ] `git add Cadence/Cadence.entitlements`
- [ ] `git commit -m "Align Release App Group to group.com.hariom.cadence (fixes silent SharedStressData breakage)"`
- [ ] Open PR; merge after approval

---

## Phase 0: Schema & preset foundation

### 0.1 — FastingCompletionStatus enum

- [ ] Create `Cadence/Models/FastingCompletionStatus.swift`:
  ```swift
  enum FastingCompletionStatus: String, Codable {
      case completed, endedEarly, overachieved, autoCappedAt24h
  }
  
  extension FastingSession {
      var resolvedStatus: FastingCompletionStatus {
          if let raw = completionStatus, let s = FastingCompletionStatus(rawValue: raw) {
              return s
          }
          return completed ? .completed : .endedEarly
      }
  }
  ```
  - Verify: file compiles in isolation

### 0.2 — FastingSession additive fields

- [ ] Edit `Cadence/Models/FastingSession.swift`: add stored properties after `var createdAt: Date` (line 11):
  - `var completionStatus: String? = nil`
  - `var contextualHRV: Double? = nil`
  - `var contextualSleepScore: Int? = nil`
  - Verify: existing `init` callers still compile
- [ ] Launch app with existing seed data
  - Verify: FastingView loads without crash; existing FastingSession rows display

### 0.3 — FastingEligibility model with 5 separate SCOFF Bool fields

- [ ] Create `Cadence/Models/FastingEligibility.swift`:
  ```swift
  import SwiftData
  import Foundation
  
  @Model final class FastingEligibility {
      var cleared: Bool = false
      var clearedAt: Date?
      var age18Plus: Bool = false
      var notPregnant: Bool = false
      var notLactating: Bool = false
      var scoffCleared: Bool = false
      var scoffSick: Bool = false
      var scoffControl: Bool = false
      var scoffOneStone: Bool = false
      var scoffFat: Bool = false
      var scoffFood: Bool = false
      var lastScreenedAt: Date?
      
      init() {}
      
      var scoffPositiveCount: Int {
          [scoffSick, scoffControl, scoffOneStone, scoffFat, scoffFood].filter { $0 }.count
      }
      
      var canInitiate: Bool {
          cleared && age18Plus && notPregnant && notLactating && scoffCleared
      }
  }
  ```
  - Verify: compiles; only one row expected per user — singleton pattern enforced by app logic, not schema
- [ ] Edit `Cadence/App/CadenceApp.swift:43`: add `FastingEligibility.self` to modelContainer `for:` array
  - Verify: app launches without SwiftData container error

### 0.4 — FastingAccessState helper

- [ ] Create `Cadence/Models/FastingAccessState.swift`:
  ```swift
  enum FastingAccessState { case onboarding, careBlocked, granted }
  
  extension FastingEligibility {
      static func accessState(from rows: [FastingEligibility]) -> FastingAccessState {
          // Consult debug override first (DEBUG-only — see AppConfig.fastingAccessOverride)
          #if DEBUG
          if let forced = AppConfig.shared.fastingAccessOverride.resolved() { return forced }
          #endif
          guard let row = rows.first else { return .onboarding }
          return row.canInitiate ? .granted : .careBlocked
      }
  }
  ```
  - Verify: compiles; `FastingEligibility.accessState(from: [])` returns `.onboarding` in Release builds

### 0.5 — AppConfig debug override for access state <!-- RESOLVED: CM1 -->

- [ ] Edit `Cadence/Core/AppConfig.swift`: add inside `#if DEBUG` block:
  ```swift
  enum FastingAccessOverride: String, CaseIterable {
      case live           // No override — use real state
      case forceOnboarding
      case forceCareBlocked
      case forceGranted
      
      func resolved() -> FastingAccessState? {
          switch self {
          case .live:             return nil
          case .forceOnboarding:  return .onboarding
          case .forceCareBlocked: return .careBlocked
          case .forceGranted:     return .granted
          }
      }
  }
  ```
  And on `AppConfig` itself:
  ```swift
  #if DEBUG
  @Published var fastingAccessOverride: FastingAccessOverride = .live
  #endif
  ```
  - Verify: compiles in Debug; not present in Release archive
- [ ] (Optional, recommended) Add a debug-only Picker for this override to the existing debug surface (e.g. `MockDataDebugCard.swift` if present, or a new section)
  - Verify: in Debug builds, can toggle override and see immediate routing change

### 0.6 — Preset reshuffle in FastingScheduleType

- [ ] Edit `Cadence/Models/FastingSchedule.swift`:
  - Remove `case ratio20_4 = "20:4"` entirely (line 9)
  - Add `case ratio12_12 = "12:12"` as the FIRST enum case
  - Reorder remaining: `ratio12_12, ratio14_10, ratio16_8, ratio18_6, custom`
  - In `setupSubtitle` switch: 
    - `.ratio12_12: return "Beginner-friendly 12h eating window"`
    - `.ratio14_10: return "Gentle plan with a 10h eating window"`
    - `.ratio16_8: return "Common plan with an 8h eating window"` (drop "most")
    - `.ratio18_6: return "Focused plan with a 6h eating window"` (keep)
    - `.custom: return "Choose your own eating window"`
  - In `defaultEatHours`: add `.ratio12_12: return 12`
  - In `defaultEatStartHour`: add `.ratio12_12: return 8`
  - In `icon`: add `.ratio12_12: return "sunrise"`
  - Verify: `FastingScheduleType.allCases` returns `[.ratio12_12, .ratio14_10, .ratio16_8, .ratio18_6, .custom]`
- [ ] In `FastingSchedule` init (line 105): change defaults:
  - `scheduleType: FastingScheduleType = .ratio16_8` → `.ratio12_12`
  - `eatWindowStartHour: Int = 12` → `8`
  - `eatWindowDurationHours: Double = 8` → `12`
  - Verify: `FastingSchedule()` creates a 12:12 schedule

### 0.7 — Legacy `"20:4"` data verification

- [ ] In simulator: manually seed a legacy schedule by setting `scheduleType = "20:4"` raw string + `eatWindowDurationHours = 4` on a `FastingSchedule` (or import a saved store from before the migration)
- [ ] Open FastingView; confirm:
  - [ ] Display reads "20h fast" (Custom)
  - [ ] No crash on `resolvedScheduleType`
  - [ ] `applyFastDuration(20)` from editor returns `.custom`

### 0.8 — Phase 0 build + commit

- [ ] Build all 4 targets (see Post-Implementation block)
- [ ] `git commit -m "Phase 0: fasting v1 schema foundation (eligibility model, completion status, 12:12 preset, debug override)"`

---

## Phase 1: Safety core (SCOFF + eligibility + soft block)

### 1.1 — Care Intervention view (US-only with caveat)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift`:
  - Non-clinical heading: "Fasting may not be the best fit for your current wellness journey right now"
  - Supporting body paragraph
  - Three resource link buttons:
    - **National Alliance for Eating Disorders** → `https://allianceforeatingdisorders.com/find-help`
    - **988 Suicide & Crisis Lifeline** → `https://988lifeline.org`
    - "Talk to a healthcare provider" reminder (no link)
  - Footer (small print): *"Resources listed are US-based. If you're outside the US, please contact your local mental health services or healthcare provider."*
  - "Re-take screening" CTA button
  - Use `AppColors.brand`, `.appShadow(radius:y:)`, `.r()` font helpers
  - Verify: opens in SwiftUI preview without crashing
- [ ] Accessibility: each resource link has `.accessibilityLabel("Opens [Name] website")`
- [ ] Footer text has `.accessibilityLabel` matching visible text
  - Verify: VoiceOver reads link destinations clearly

### 1.2.0 — FastingScheduleEditor `embedded` flag <!-- RESOLVED: CM6 -->

- [ ] Edit `Cadence/Features + UI/Stress/Views/FastingScheduleEditor.swift`: add `var embedded: Bool = false`
- [ ] In `body`, conditionally render:
  ```swift
  var body: some View {
      if embedded {
          formContent
              .padding(.horizontal, 4)
      } else {
          NavigationStack {
              formContent
                  .navigationTitle(existingSchedule == nil ? "Fast Setup" : "Edit Fast")
                  .navigationBarTitleDisplayMode(.inline)
                  .toolbar { /* existing toolbar */ }
                  // existing alert
          }
          .presentationDetents([.large])
          .onAppear { loadExisting() }
      }
  }
  
  @ViewBuilder private var formContent: some View {
      Form { scheduleSection; eatWindowSection; caffeineCutoffSection; infoSection }
  }
  ```
- [ ] When embedded, the parent (`FastingOnboardingFlow`) is responsible for Save action and dismissal — expose `func performSave()` as `public` (already private) or add a callback `onSave: () -> Void`
  - Verify: no double nav bar when embedded inside onboarding flow

### 1.2 — FastingOnboardingFlow (4-step paged flow)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` with `TabView(selection:)`:
  - **Step 1 — Disclaimer:** full-screen text "Cadence is for general wellness, not medical advice. Talk to a licensed provider before changing dietary habits." Un-skippable "I understand" button
  - **Step 2 — Demographics:** three `Toggle`s ("Are you 18 or older?" / "Are you currently pregnant?" / "Are you currently lactating?"). Next button enables when all answered
  - **Step 3 — SCOFF:** five `Toggle`s with blueprint phrasing. Submit button computes `scoffPositiveCount`
  - **Step 4 — Schedule:** `FastingScheduleEditor(embedded: true)`; Save action triggered by flow's bottom button
  - Verify: navigation order works; Next/Submit/Save enable only when valid
- [ ] On demographic disqualification: persist `FastingEligibility` row with disqualifying flag, present `FastingCareInterventionView`, abort
  - Verify: setting `age18Plus = false` routes to Care
- [ ] On SCOFF ≥2 positives: persist all 5 answers + `scoffCleared = false` + `lastScreenedAt = .now`, present Care view, abort
  - Verify: 2 yes answers → Care view; FastingEligibility row exists with `scoffCleared = false`
- [ ] On SCOFF <2: persist 5 answers + `scoffCleared = true`, advance to step 4
  - Verify: 1 yes answer → advances; row has `scoffCleared = true`
- [ ] On schedule save: set `eligibility.cleared = true`, `clearedAt = .now`, insert `FastingSchedule`
  - Verify: post-onboarding, `FastingEligibility.canInitiate == true`
- [ ] Back-nav policy: SCOFF Toggles freely editable BEFORE Submit. After Care view, "Re-take screening" returns to step 3 with **fresh blank state** (no pre-fill)
  - Verify: re-take from Care does not preserve previous answers
- [ ] Mid-flow abandonment: app backgrounding → state not persisted; reopening returns to FastingView empty state
  - Verify: background mid-SCOFF, reopen → FastingView shows empty state
- [ ] Accessibility: each SCOFF Toggle has `.accessibilityLabel` matching question; Submit button has `.accessibilityHint("Submit your answers and continue.")`
  - Verify: VoiceOver reads question, then switch state

### 1.3 — Replace FastingView Get Started CTA

- [ ] Edit `Cadence/Features + UI/Stress/Views/FastingView.swift` lines 203-228: Get Started button presents `FastingOnboardingFlow` as a sheet (NOT `FastingScheduleEditor`)
  - However: if `FastingEligibility.accessState(from: [eligibility])` == `.granted`, skip onboarding and go straight to `FastingScheduleEditor` (avoid re-onboarding an already-cleared user)
- [ ] Keep gear icon (lines 78-87) as post-onboarding "Edit Fast" path (presents `FastingScheduleEditor`)
  - Verify: first-time tap → onboarding; granted user gear → schedule editor

### 1.4 — Access-state-gated routing on Stress factor sheet <!-- RESOLVED: CC1 — Home routing removed; deferred to Phase 7 -->

> **Note:** Home dashboard routing (the existing `headerAssetIcon("fasting_icon")` launcher button) is intentionally **left unchanged** in this phase. It will be replaced entirely by `DigestiveStateCard` in Phase 7.5, which builds the access-state routing from scratch. v1.0.0 ships with the launcher button still opening `FastingView` directly; the empty-state CTA inside FastingView (step 1.3) is the access-state gate for first-time users.

- [ ] Edit `Cadence/Features + UI/Stress/Views/StressView.swift` line 198 (`.fasting` factor sheet case): add `@Query private var eligibility: [FastingEligibility]` (or fetch via modelContext) and route via `FastingEligibility.accessState(from: eligibility)`:
  - `.onboarding` → present `FastingOnboardingFlow`
  - `.careBlocked` → present `FastingCareInterventionView`
  - `.granted` → present `FastingView`
  - Verify: each access state routes correctly. **Test all 3 via AppConfig debug override** (step 0.5): set to `.forceOnboarding`, `.forceCareBlocked`, `.forceGranted` in turn.

### 1.5 — Settings entry for re-screening

- [ ] Edit `FastingView.swift` toolbar (lines 78-87): replace gear icon with `Menu` containing two items: "Edit schedule" (current behavior — `activeFastingSheet = .scheduleEditor`) and "Re-take wellness screening" (presents `FastingOnboardingFlow` starting at step 3)
- [ ] Re-take updates the existing `FastingEligibility` row (no new row created); `lastScreenedAt` advances
  - Verify: re-taking with different answers updates the same row

### 1.6 — Phase 1 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test 4 branches via AppConfig debug override + actual flow:
  - [ ] Never-screened user (override=`.forceOnboarding` OR no FastingEligibility row exists) → onboarding flow appears
  - [ ] Demographic fail (age <18) → Care view, no fast can be started
  - [ ] SCOFF fail (≥2 yes) → Care view, no fast can be started
  - [ ] All pass → schedule editor → fast can be started
- [ ] VoiceOver pass through entire onboarding flow
- [ ] `git commit -m "Phase 1: SCOFF + eligibility gate + Care soft block (Stress factor sheet routing only; Home deferred to Phase 7)"`

---

## Phase 2: 24h cap + forgotten-stop guard

### 2.1 — Consolidated Live Activity ContentState schema (single update)

- [ ] Edit `Cadence/Widgets/FastingActivityAttributes.swift` `ContentState`: add three Bools with defaults:
  ```swift
  var isCapped24h: Bool = false
  var isOverachieving: Bool = false
  var acceptsEndIntent: Bool = false
  ```
  - Verify: existing call sites compile unchanged (defaults safe); both Cadence and CadenceWidget build

### 2.2 — 24h cap notification method

- [ ] Edit `Cadence/Core/Services/FastingService.swift`: add identifier `private static let notifCap24h = "wp.fasting.cap24h"` (next to existing identifiers, lines 52-55)
- [ ] Add `wp.fasting.cap24h` to `clearNotifications()` removal list (line 266-273)
- [ ] Add new methods:
  ```swift
  func schedule24hCapNotification(for session: FastingSession) {
      let center = UNUserNotificationCenter.current()
      guard !notificationsBlocked else { return }
      let secondsUntilCap = session.startedAt.addingTimeInterval(24*3600).timeIntervalSinceNow
      guard secondsUntilCap > 0 else { return }
      let content = UNMutableNotificationContent()
      content.title = "Fast paused at 24h"
      content.body = "You've been fasting for 24h. Did you forget to end your fast? Tap to adjust the end time."
      content.sound = .default
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secondsUntilCap, repeats: false)
      center.add(UNNotificationRequest(identifier: Self.notifCap24h, content: content, trigger: trigger))
  }
  
  func cancel24hCapNotification() {
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifCap24h])
  }
  ```
  - Verify: file compiles

### 2.3 — Wire cap notification into session lifecycle

- [ ] In `FastingView.swift` `handleStateTransition` (line 615 block, after `modelContext.insert(session)` ~line 620): add `fastingService.schedule24hCapNotification(for: session)`
  - Verify: new session via eat→fast transition schedules cap notification
- [ ] In `FastingView.swift` `startFastNow` (after `modelContext.insert(session)` ~line 655): same call
  - Verify: manually started fast schedules cap
- [ ] In `FastingView.swift` `breakCurrentFast` (line 682): add `fastingService.cancel24hCapNotification()`
  - Verify: ending fast cancels the pending cap notification

### 2.4 — Cap-state on FastingService

- [ ] In `FastingService.swift`: add `@Published private(set) var isCapped24h: Bool = false` (next to other @Published, lines 39-43)
- [ ] In `updateState(...)` (lines 93-143): after computing elapsed, add:
  ```swift
  if let session = activeSession, session.actualDurationSeconds > 24*3600 {
      isCapped24h = true
      progress = 1.0
      timeRemaining = 0
  } else {
      isCapped24h = false
  }
  ```
  - Verify: seeded 25h session → `isCapped24h = true`

### 2.5 — Live Activity capped-state rendering <!-- RESOLVED: CH4 — explicit elapsed computation -->

- [ ] Edit `ActivityManager.updateFastingActivity(progress:)` (lines 85-98): compute elapsed from existing state, do NOT add parameters:
  ```swift
  func updateFastingActivity(progress: Double) {
      reconnectIfNeeded()
      guard let activity = fastingActivity else { return }
      let clamped = max(0, min(progress, 1.0))
      var state = activity.content.state
      
      // Compute elapsed from the activity's stored fastStartDate — no caller changes needed
      let elapsed = Date().timeIntervalSince(state.fastStartDate)
      let cappedNow = elapsed > 24*3600
      state.isCapped24h = cappedNow
      state.progress = cappedNow ? 1.0 : clamped
      
      guard abs(state.progress - activity.content.state.progress) > 0.001 || state.isCapped24h != activity.content.state.isCapped24h else { return }
      let stale = state.targetEndDate.addingTimeInterval(60)
      let content = ActivityContent(state: state, staleDate: stale)
      Task { await activity.update(content) }
  }
  ```
  - Verify: with a session >24h old, Live Activity ContentState shows `isCapped24h = true`
- [ ] In `FastingLiveActivityView.swift`: in Lock Screen `phoneView` (lines 109-146), Dynamic Island center (lines 35-59), and Watch view (lines 150-186): when `context.state.isCapped24h`, replace the timer block with text "Paused at 24h"
  - Verify: capped state shows "Paused at 24h" on all three surfaces

### 2.6 — FastingView 24h-cap banner

- [ ] In `FastingView.swift`: when `fastingService.isCapped24h`, render banner above `todayInfoCard` with "Fast paused at 24h" copy and two buttons:
  - "End Fast" → calls existing break flow
  - "Edit" → presents `FastingEditSessionSheet` (step 2.7) pre-targeting active session
  - Verify: capped state shows banner; both buttons work

### 2.7 — FastingEditSessionSheet (retroactive correction)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift`:
  - Two `DatePicker`s for `startedAt` and `actualEndAt`
  - Validation: `end > start`, `end <= .now`, `(end - start) <= 24*3600`
  - Inline error message when invalid
  - On save:
    - Persist dates
    - Compute `completionStatus`:
      - `actualEndAt < targetEndAt` → `.endedEarly`
      - `actualEndAt >= targetEndAt && (actualEndAt - startedAt) < 24h` → `.completed`
      - `(actualEndAt - startedAt) >= 24h` → `.autoCappedAt24h`
    - Set legacy `completed` (true for completed/overachieved/autoCappedAt24h; false for endedEarly)
    - `fastingService.cancel24hCapNotification()` if applicable
  - Verify: invalid ranges rejected; valid edits save with correct status

### 2.8 — Wire history rows to edit sheet

- [ ] In `FastingView.swift` lines 553-587: wrap each `fastHistoryRow(session)` in `Button { editingSession = session }`
- [ ] Add `@State private var editingSession: FastingSession?` + `.sheet(item: $editingSession) { FastingEditSessionSheet(session: $0) }`
  - Verify: tapping history row opens edit sheet pre-populated

### 2.9 — Phase 2 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test: seed a session with `startedAt = now - 25h`. Open FastingView:
  - [ ] Capped banner appears
  - [ ] Live Activity shows "Paused at 24h"
  - [ ] Edit button opens sheet pre-targeting the session
  - [ ] Setting end to `now + 1h` rejected (>now)
  - [ ] Setting end to `start + 30h` rejected (>24h)
  - [ ] Valid edit saves with correct status
- [ ] `git commit -m "Phase 2: 24h cap + edit previous fast + Live Activity attribute consolidation"`

---

## Phase 3: Copy / color / lexicon pass

### 3.1 — FastingView copy + colors

- [ ] In `FastingView.swift` `stateLabel` (lines 692-698): `"FASTING"` → `"RESTING"`, `"EATING"` → `"EATING WINDOW"`
- [ ] In `idleHeaderLabel` (lines 702-704): `"READY TO FAST"` → `"READY WHEN YOU ARE"`
- [ ] In `ringColor` (lines 706-712): return `heroAccent` for `.fasting`, existing green for `.eating`. **Remove `.orange` case entirely**
  - Verify: grep `FastingView.swift` for `.orange` returns no matches in `ringColor`
- [ ] In `breakFastAlertMessage` (lines 131-137): replace body with *"Listening to your body is always the right choice. You've fasted for \(formattedDuration(elapsed)) so far."*
- [ ] Alert title (line 99): `"Break Fast Early?"` → `"End your fast?"`
- [ ] Break Fast button label (line 423): `"Break Fast"` → `"End Fast"`
- [ ] `fastHistoryRow` (line 574): `"Broken"` → `"Ended early"`
- [ ] Empty state subtitle (lines 196-200): *"Rest your digestive system and align eating with your body clock."*
  - Verify: grep `FastingView.swift` for `"BROKEN"`, `"FASTING"`, `"Break Fast"`, `"Broken"` returns no matches

### 3.2 — Live Activity color + copy + Watch verification

- [ ] In `FastingLiveActivityView.swift` `ringColor(for:)` (lines 277-281): broken-state `.red` → `.white.opacity(0.55)`. Active stays `.orange`
- [ ] Lock Screen broken-state text colors (lines 128, 167, 46): `.red` → `.white.opacity(0.7)`
- [ ] Dynamic Island expanded center (line 42): `"Fast complete"` → `"Rest complete"`
- [ ] Verify on Apple Watch:
  - [ ] Start a fast → Live Activity appears on Watch
  - [ ] `WatchLogoRing` renders (line 244-273)
  - [ ] Text labels render at correct size, no truncation

### 3.3 — Notification copy

- [ ] Edit `FastingService.scheduleNotifications` (lines 209-263):
  - "Eating Window Closed" body → *"Your \(scheduleLabel) rest has begun. Hydrate well."*
  - "1 Hour Left" body → *"Eating window opens in 1 hour. Plan something nourishing."*
  - "Fast Complete" body → *"Rest complete. Break your fast whenever you feel ready."*
  - Caffeine cutoff: unchanged
  - Verify: trigger notification in simulator, copy reads as updated

<!-- RESOLVED: CM5 — original step 3.4 (preset subtitles) removed; that work is already in Phase 0.6 -->

### 3.5 — Phase 3 build + walkthrough

- [ ] Build all 4 targets
- [ ] Manual UI walkthrough on iPhone + Apple Watch:
  - [ ] No "FASTING", "BROKEN", "Break Fast", "Fast complete" anywhere
  - [ ] No neon red on ring; no warning orange on broken state
  - [ ] Watch Live Activity renders correctly
- [ ] `git commit -m "Phase 3: calm-tone copy and color pass across fasting surfaces"`

---

## Phase 4: Soft completion + bonus time

### 4.1 — isOverachieving state

- [ ] In `FastingService.swift`: add `@Published private(set) var isOverachieving: Bool = false` and `@Published private(set) var bonusElapsed: TimeInterval = 0` (next to other @Published, lines 39-43)
- [ ] In `updateState(...)`: add overachieving branch (must be ordered AFTER `isCapped24h` from step 2.4 — capped takes precedence):
  ```swift
  if !isCapped24h, let session = activeSession,
     session.actualDurationSeconds > session.targetDurationSeconds {
      isOverachieving = true
      progress = 1.0
      bonusElapsed = session.actualDurationSeconds - session.targetDurationSeconds
  } else {
      isOverachieving = false
      bonusElapsed = 0
  }
  ```
  - Verify: seed session with `targetEndAt = now - 5min` → `isOverachieving = true`, `bonusElapsed ≈ 300`; 25h session → `isCapped24h = true`, `isOverachieving = false`

### 4.2 — Timer ring pulse + bonus label

- [ ] In `FastingView.swift` `activeTimerCard` (lines 246-353): when `fastingService.isOverachieving`:
  - Ring stays at full, opacity pulses 0.85 ↔ 1.0 via `.animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true))`
  - Replace `formattedTimeRemaining` label with `"+\(formattedDuration(fastingService.bonusElapsed))"`
  - Replace `"REMAINING"` subtitle with `"BONUS TIME"`
  - Hide percentage line
  - Fire one soft `HapticService.impact(.light)` at first transition (use `@State private var previousIsOverachieving: Bool = false`)
  - Verify: visual confirmation pulse + bonus label
- [ ] Respect `@Environment(\.accessibilityReduceMotion)`: when reduced, hold at full opacity (no pulse)
  - Verify: Reduce Motion enabled → no pulse
- [ ] Time label `.accessibilityLabel("Bonus time: \(spokenDuration)")` for VoiceOver
  - Verify: VoiceOver reads "Bonus time: 5 minutes"

### 4.3 — Decouple celebration from auto-transition <!-- RESOLVED: CH5 — explicit FastingCompletionEvent init -->

- [ ] Add `@State private var didUserExplicitlyEnd: Bool = false` to `FastingView`
- [ ] In `handleStateTransition` (lines 611-644), split the `fasting → eating` block:
  ```swift
  if oldState.isFasting && newState.isEating, let session = activeSession {
      session.actualEndAt = .now
      
      if didUserExplicitlyEnd {
          session.completionStatus = FastingCompletionStatus.completed.rawValue
          session.completed = true
          HapticService.notify(.success)
          ActivityManager.shared.endFastingActivity(completed: true)
          withAnimation(.easeOut(duration: 0.3)) {
              celebration = FastingCompletionEvent(
                  durationHours: session.actualDurationHours,
                  scheduleLabel: schedule.displayLabel
              )
          }
      } else {
          // Silent overachieve close — no celebration
          session.completionStatus = FastingCompletionStatus.overachieved.rawValue
          session.completed = true
          ActivityManager.shared.endFastingActivity(completed: true)
      }
      didUserExplicitlyEnd = false
  }
  ```
- [ ] In `breakCurrentFast()` (line 682): set `didUserExplicitlyEnd = true` AT THE START. Then:
  - If `fastingService.isOverachieving`: `session.completionStatus = .completed.rawValue`, fire celebration (same withAnimation block as above)
  - If NOT overachieving: `session.completionStatus = .endedEarly.rawValue`, no celebration
  - In both: `session.actualEndAt = .now`, `ActivityManager.shared.endFastingActivity(completed: ...)`, `cancel24hCapNotification()`
  - Verify: four scenarios all work correctly (see step 4.4)
- [ ] Reset `didUserExplicitlyEnd = false` on new session start (in `handleStateTransition` eating → fasting block and `startFastNow`)

### 4.4 — Phase 4 four-scenario QA

- [ ] **Scenario A:** Start fast, end BEFORE target (1h into 12h). Tap End Fast
  - Verify: `completionStatus = .endedEarly`, no celebration
- [ ] **Scenario B:** Start fast, let target pass, see bonus time, then tap End Fast
  - Verify: `completionStatus = .completed`, celebration confetti fires
- [ ] **Scenario C:** Start fast, let target pass, do NOT tap End Fast, wait for next eating window auto-transition
  - Verify: `completionStatus = .overachieved`, NO celebration, history shows session silently
- [ ] **Scenario D:** Start fast, let 24h elapse
  - Verify: `isCapped24h = true` precedes overachieving; banner appears; no celebration

### 4.5 — Phase 4 build + commit

- [ ] Build all 4 targets
- [ ] `git commit -m "Phase 4: soft completion + bonus time + explicit-end celebration"`

---

## Phase 5: Contextual intelligence

### 5.1 — SharedHealthMetrics App-Group cache + SleepQuality→Int mapping <!-- RESOLVED: CH1 — explicit sleep-score helper -->

- [ ] Create `Cadence/Widgets/SharedHealthMetrics.swift`:
  ```swift
  import Foundation
  
  struct SharedHealthMetrics: Codable {
      var date: Date
      var hrvMs: Double?
      var sleepScore: Int?
      var lastUpdated: Date
      
      static let appGroupID = "group.com.hariom.cadence"
      static let defaultsKey = "sharedHealthMetrics"
      
      static func loadForToday() -> SharedHealthMetrics? {
          guard let d = UserDefaults(suiteName: appGroupID),
                let raw = d.data(forKey: defaultsKey),
                let decoded = try? JSONDecoder().decode(SharedHealthMetrics.self, from: raw),
                Calendar.current.isDate(decoded.date, inSameDayAs: Date())
          else { return nil }
          return decoded
      }
      
      func save() {
          guard let d = UserDefaults(suiteName: Self.appGroupID),
                let data = try? JSONEncoder().encode(self) else { return }
          d.set(data, forKey: Self.defaultsKey)
      }
      
      /// Maps SleepQuality enum to a stable 0-100 score for cross-feature use.
      /// Single source of truth for sleep-score derivation in v1.
      static func sleepScore(from quality: SleepQuality) -> Int {
          switch quality {
          case .excellent: return 95
          case .good:      return 80
          case .fair:      return 60
          case .poor:      return 35
          }
      }
  }
  ```
  - Verify: compiles in both Cadence and CadenceWidget targets

### 5.2 — StressViewModel writes to cache <!-- RESOLVED: CH1 — uses SleepQuality mapping -->

- [ ] Locate the HealthKit fetch completion in `StressViewModel.loadData()` (`Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift`)
- [ ] After `todayHRV` and `sleepHistory` are populated, write a cache row using `sleepHistory.last?.quality`:
  ```swift
  let sleepScore = sleepHistory.last.map { SharedHealthMetrics.sleepScore(from: $0.quality) }
  let metrics = SharedHealthMetrics(
      date: Calendar.current.startOfDay(for: Date()),
      hrvMs: todayHRV,
      sleepScore: sleepScore,
      lastUpdated: .now
  )
  metrics.save()
  ```
  - Verify: open Stress view → inspect App Group UserDefaults via debug console → `sharedHealthMetrics` key exists with today's date and non-nil hrvMs/sleepScore

### 5.3 — FastingContextProvider <!-- RESOLVED: CH2, CH3 — bedtime field, factory injection -->

- [ ] Create `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift`:
  ```swift
  import SwiftData
  import Foundation
  
  @MainActor final class FastingContextProvider: ObservableObject {
      @Published var todayHRV: Double?
      @Published var lastNightSleepScore: Int?
      @Published var sevenDayStressAvg: Double?
      
      func loadContext(healthKit: HealthKitServiceProtocol, modelContext: ModelContext) async {
          // 1. Try cache
          if let cached = SharedHealthMetrics.loadForToday() {
              todayHRV = cached.hrvMs
              lastNightSleepScore = cached.sleepScore
          } else {
              // 2. Cold start: fetch directly
              let today = Calendar.current.startOfDay(for: Date())
              let range = DateInterval(start: today, duration: 86400)
              if let hrv = try? await healthKit.fetchHRV(for: range).last?.value {
                  todayHRV = hrv
              }
              if let summary = try? await healthKit.fetchDailySleepSummaries(for: range).last {
                  lastNightSleepScore = SharedHealthMetrics.sleepScore(from: summary.quality)
              }
              // 3. Write back to cache
              SharedHealthMetrics(
                  date: today,
                  hrvMs: todayHRV,
                  sleepScore: lastNightSleepScore,
                  lastUpdated: .now
              ).save()
          }
          // 4. 7-day stress avg from SwiftData (StressAnalyticsHelper or direct fetch)
          sevenDayStressAvg = computeSevenDayStressAvg(modelContext: modelContext)
      }
      
      private func computeSevenDayStressAvg(modelContext: ModelContext) -> Double? {
          let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
          let descriptor = FetchDescriptor<StressReading>(
              predicate: #Predicate { $0.timestamp >= cutoff },
              sortBy: [SortDescriptor(\.timestamp, order: .forward)]
          )
          guard let readings = try? modelContext.fetch(descriptor), !readings.isEmpty else { return nil }
          // Reuse existing helper if available
          let avgs = StressAnalyticsHelper.dailyAveragesByDate(from: readings).values
          guard !avgs.isEmpty else { return nil }
          return avgs.reduce(0, +) / Double(avgs.count)
      }
  }
  ```
  - Verify: compiles; first call fetches, second call within same day uses cache (no duplicate HealthKit query in Console.app log)

### 5.4 — Insight banner under timer

- [ ] In `FastingView.swift`: add `@StateObject private var contextProvider = FastingContextProvider()`
- [ ] In `configureService()`: call `Task { await contextProvider.loadContext(healthKit: HealthKitServiceFactory.shared, modelContext: modelContext) }`
- [ ] Add private view `insightBanner` between `activeTimerCard` and `todayInfoCard` rendering one of (using thresholds from constants):
  - **HRV high** (today > hrvBaseline + 5ms): *"Your HRV is strong today. A \(scheduleHours)h rest aligns well with your recovery."*
  - **HRV low** (today < hrvBaseline - 5ms): *"Your autonomic nervous system shows elevated stress today. Consider a shorter rest (12h) to support recovery."*
  - **Sleep score low** (score < 70 — i.e. .fair or .poor): *"Sleep was light last night. Listen to your body — it's okay to end your fast early today."*
  - **No data**: return `EmptyView()` (hide banner)
- [ ] Add thresholds as `private static let` constants at top of file (e.g. `hrvBaselineMs: Double = 40`, `lowSleepScoreThreshold: Int = 70`)
- [ ] Banner `.accessibilityLabel` matches visible text + `.accessibilityHint("Personal recommendation based on your recent recovery metrics.")`
  - Verify: with seeded HRV high → recovery message; HRV low → shorter-rest message; SleepQuality.fair/.poor → light-sleep message; no data → no banner

### 5.5 — Bind context to session on end

- [ ] In `FastingView.handleStateTransition` and `breakCurrentFast`: before save, write:
  ```swift
  session.contextualHRV = contextProvider.todayHRV
  session.contextualSleepScore = contextProvider.lastNightSleepScore
  ```
  - Verify: end a fast → `FastingSession` row has non-nil contextual fields

### 5.6 — Phase 5 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test with HealthKit auth + real HRV/sleep data:
  - [ ] Open FastingView → banner appears with appropriate copy
  - [ ] End a fast → row shows non-nil contextual fields
  - [ ] Open Stress view first, then Fasting view → only one HRV/sleep fetch in Console.app log (cache hit)
- [ ] `git commit -m "Phase 5: contextual HRV/sleep insight + SharedHealthMetrics cache + SleepQuality score mapping"`

---

## Phase 6: LiveActivityIntent End Fast

> **Depends on Phase −1 having shipped.** Cannot verify in Release without aligned App Group.

### 6.1 — BreakFastIntent target-membership pre-check + creation <!-- RESOLVED: CL3, H3 (from plan audit) — explicit cross-process pattern -->

- [ ] **Pre-check** target membership for `Cadence/Widgets/`:
  ```bash
  grep -B2 -A5 "CadenceWidget" Cadence.xcodeproj/project.pbxproj | grep -i "synchroniz\|Cadence/Widgets" | head -20
  ```
  - Verify: output shows CadenceWidget target includes the Cadence/Widgets sync group. If NOT, add the new BreakFastIntent.swift to both targets via Xcode UI when creating it (do not rely on auto-inclusion).
- [ ] Create `Cadence/Widgets/BreakFastIntent.swift`:
  ```swift
  import AppIntents
  import ActivityKit
  import Foundation
  
  struct PendingBreakPayload: Codable {
      let timestamp: Date
      let reason: String  // "userExplicit"
  }
  
  struct BreakFastIntent: LiveActivityIntent {
      static let title: LocalizedStringResource = "End Fast"
      
      func perform() async throws -> some IntentResult {
          // 1. Persist pending-break payload to App Group UserDefaults.
          //    Widget process cannot mutate SwiftData reliably; app reconciles on foreground.
          let payload = PendingBreakPayload(timestamp: .now, reason: "userExplicit")
          if let d = UserDefaults(suiteName: "group.com.hariom.cadence"),
             let data = try? JSONEncoder().encode(payload) {
              d.set(data, forKey: "pendingBreakFast")
          }
          // 2. End the Live Activity directly. This IS safe cross-process —
          //    ActivityKit owns its own shared state. Do NOT call ActivityManager.shared.
          if let activity = Activity<FastingActivityAttributes>.activities.first {
              var finalState = activity.content.state
              finalState.acceptsEndIntent = false
              await activity.end(
                  ActivityContent(state: finalState, staleDate: .now),
                  dismissalPolicy: .default
              )
          }
          return .result()
      }
  }
  ```
  - Verify: both `xcodebuild ... -scheme Cadence build` and `xcodebuild ... -target CadenceWidget build` succeed

### 6.2 — Set acceptsEndIntent over lifecycle

- [ ] In `ActivityManager.startFastingActivity` (lines 34-80): in initial `ContentState`, set `acceptsEndIntent: true`
- [ ] In `ActivityManager.endFastingActivityInternal` (lines 108-121): set `acceptsEndIntent: false` in finalState
  - Verify: Live Activity state toggles `acceptsEndIntent` correctly over lifecycle

### 6.3 — Wire intent button into Live Activity

- [ ] In `FastingLiveActivityView.swift` Lock Screen `phoneView` (lines 109-146): when `context.state.acceptsEndIntent && !context.state.isCompleted && !context.state.isBroken && !context.state.isCapped24h`, render:
  ```swift
  Button(intent: BreakFastIntent()) {
      Text("End")
          .font(.system(size: 13, weight: .semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Capsule().fill(.white.opacity(0.2)))
          .foregroundStyle(.white)
  }
  .accessibilityLabel("End Fast")
  .accessibilityHint("Ends your current fast and opens the eating window.")
  ```
  inline at bottom-right
  - Verify: button appears on Lock Screen during active fast
- [ ] In Dynamic Island `.bottom` region (lines 60-71): same button on the right alongside "Eat window opens" caption (gated by same condition)
  - Verify: button appears in expanded Dynamic Island
- [ ] Skip compact/minimal/Watch families (out of scope for v1)

### 6.4 — App reconciles pending-break on foreground

- [ ] In `FastingView.configureService()` (lines 591-609), at the top, add:
  ```swift
  if let d = UserDefaults(suiteName: "group.com.hariom.cadence"),
     let data = d.data(forKey: "pendingBreakFast"),
     let payload = try? JSONDecoder().decode(PendingBreakPayload.self, from: data) {
      if let session = activeSession {
          session.actualEndAt = payload.timestamp
          let wasAtOrPastTarget = session.actualDurationSeconds >= session.targetDurationSeconds
          session.completionStatus = (wasAtOrPastTarget ? FastingCompletionStatus.completed : .endedEarly).rawValue
          session.completed = wasAtOrPastTarget
          session.contextualHRV = contextProvider.todayHRV
          session.contextualSleepScore = contextProvider.lastNightSleepScore
          fastingService.cancel24hCapNotification()
          ActivityManager.shared.endFastingActivity(completed: wasAtOrPastTarget)
      }
      d.removeObject(forKey: "pendingBreakFast")
  }
  ```
  - Verify: idempotent — running twice with no active session is safe; running once correctly closes the session

### 6.5 — Phase 6 verification (REQUIRES TESTFLIGHT) <!-- RESOLVED: CM3 — NEW vs Phase −1.4 -->

> **What's NEW in Phase 6.5 vs Phase −1.4:** Phase −1.4 proved App Group reads/writes work in Release builds. Phase 6.5 additionally verifies that (a) the `LiveActivityIntent` runs in the widget process and (b) the pending-break payload is correctly reconciled by the app on foreground (a SwiftData write that the intent process could not perform itself).

- [ ] Build for Release, upload to TestFlight, install on device
- [ ] Start a fast in the app, lock device, swipe to Lock Screen Live Activity, tap End
  - Verify: unlock app → fast shows as ended in history; payload UserDefaults key cleared
- [ ] Repeat with Dynamic Island long-press → tap End
  - Verify: same result from expanded island
- [ ] Repeat with app foregrounded → tap End on Live Activity
  - Verify: app immediately reflects ended state via the reconciliation in `configureService()`
- [ ] `git commit -m "Phase 6: LiveActivityIntent End Fast button (Lock Screen + Dynamic Island)"`

---

## Phase 7: Weekly grid + Home Digestive State card

### 7.1 — FastingWeeklyGridView

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift`:
  - Takes `sessions: [FastingSession]`
  - Horizontal 7-column grid using `Calendar.current.firstWeekday`
  - Each cell: day-of-week abbreviation (top), colored square (middle), small duration label (bottom)
  - Color by `resolvedStatus`:
    - `.completed`/`.overachieved` → filled `heroAccent`
    - `.endedEarly` → hatched (diagonal stripe)
    - `.autoCappedAt24h` → filled muted gray
    - No fast → empty outline
  - Highlight today with ring
  - Each cell: `.accessibilityElement(children: .combine)` with label like "Tuesday, 14h fast, completed"
  - Verify: SwiftUI preview with sample data

### 7.2 — Integrate grid into FastingView

- [ ] In `FastingView.swift` `historySection` (lines 510-551): replace the `ForEach(completedSessions, id: \.persistentModelID) { fastHistoryRow($0) }` (lines 538-542) with `FastingWeeklyGridView(sessions: sessions)`
- [ ] Below the grid, render a separate "Recent" section keeping tappable history rows (preserves edit capability from 2.8)
  - Verify: FastingView shows grid as primary, list as secondary

### 7.3 — HomeCardID.fasting case <!-- RESOLVED: CM4 — manual verify -->

- [ ] Edit `Cadence/Models/HomeLayoutConfig.swift` `HomeCardID` enum (lines 8-15): add `case fasting` after `case wellnessRings` (position 2c)
- [ ] In `displayName` switch (lines 18-27): add `case .fasting: return "Fasting"`
- [ ] In `iconName` switch (lines 29-38): add `case .fasting: return "fork.knife.circle"`
- [ ] `hasSubElements` default `false` (no change needed)
- [ ] `subElements` default `[]` (no change needed)
  - Verify: `HomeCardID.allCases.count == 7` (was 6); `HomeCardID.fasting.displayName == "Fasting"`
- [ ] **Existing-user auto-migration verification (manual):** Launch the app in simulator with a pre-existing `HomeLayoutConfig` (e.g. a layout saved before this build). The `.fasting` card should appear at the end of the Home layout (visible cards section) WITHOUT requiring a layout reset.
  - If it does NOT appear, `reconcileWithCurrentCards()` is not being called during decode — verify the config loader (likely in `UserGoals` or the persistence layer) invokes `reconcile()` after `decode`.
  - Verify: card visible in pre-existing layout without reset

### 7.4 — DigestiveStateCard with access-state routing <!-- RESOLVED: CC1 (Home routing built here), CM7 (configure-on-appear) -->

- [ ] Create `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift`:
  ```swift
  import SwiftUI
  import SwiftData
  
  struct DigestiveStateCard: View {
      @Environment(\.modelContext) private var modelContext
      @Environment(\.scenePhase) private var scenePhase
      @Query(sort: \FastingSchedule.createdAt, order: .reverse) private var schedules: [FastingSchedule]
      @Query(sort: \FastingSession.startedAt, order: .reverse) private var sessions: [FastingSession]
      @Query private var eligibility: [FastingEligibility]
      
      @StateObject private var fastingService = FastingService()
      @State private var presentedSheet: PresentedSheet?
      
      private enum PresentedSheet: Identifiable {
          case onboarding, care, fasting
          var id: String { String(describing: self) }
      }
      
      var body: some View {
          Button { handleTap() } label: {
              cardContent
          }
          .buttonStyle(.plain)
          .onAppear { configureIfNeeded() }
          .onChange(of: scenePhase) { _, phase in
              if phase == .active { configureIfNeeded() }
          }
          .sheet(item: $presentedSheet) { sheet in
              switch sheet {
              case .onboarding: FastingOnboardingFlow()
              case .care:       FastingCareInterventionView()
              case .fasting:    FastingView()
              }
          }
      }
      
      private func configureIfNeeded() {
          guard let schedule = schedules.first else {
              fastingService.stop()
              return
          }
          let active = sessions.first(where: \.isActive)
          fastingService.configure(schedule: schedule, activeSession: active)
      }
      
      private func handleTap() {
          switch FastingEligibility.accessState(from: eligibility) {
          case .onboarding:  presentedSheet = .onboarding
          case .careBlocked: presentedSheet = .care
          case .granted:     presentedSheet = .fasting
          }
      }
      
      @ViewBuilder
      private var cardContent: some View {
          // Compact card: current state label + mini progress + last fast + readiness summary
          // Style: RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)
          // ... (build out the card UI per design — keep similar styling to other Home cards)
          EmptyView() // placeholder — replace with full layout during implementation
      }
  }
  ```
  - Verify: compiles; SwiftUI preview renders; tap routes correctly per access state (test via AppConfig debug override from step 0.5)

### 7.5 — Integrate DigestiveStateCard into HomeView

- [ ] Edit `Cadence/Features + UI/Home/Views/HomeView.swift` `cardView(for:)` (line 130): add branch:
  ```swift
  case .fasting:
      DigestiveStateCard()
  ```
- [ ] Remove the old `headerAssetIcon("fasting_icon")` launcher button (lines 593-601) — the card replaces it
  - Verify: Home shows DigestiveStateCard in correct slot; old launcher gone

### 7.6 — Phase 7 build + verification

- [ ] Build all 4 targets
- [ ] Manual test:
  - [ ] Seed varied session history (completed, ended early, no-fast, autoCappedAt24h)
  - [ ] FastingView shows weekly grid with right colors
  - [ ] Home shows DigestiveStateCard in layout for both new users (`.fasting` first-class in `cardOrder.default`) and existing users (auto-added at end via reconcile)
  - [ ] DigestiveStateCard tap routes correctly for each access state — verify all 3 via AppConfig debug override
- [ ] VoiceOver pass on weekly grid cells + DigestiveStateCard
- [ ] `git commit -m "Phase 7: weekly grid + Home DigestiveStateCard with access-state routing"`

---

## Phase 8: Bedtime-derived start reminder

### 8.1 — Bedtime heuristic <!-- RESOLVED: CH2 (bedtime field), CH3 (factory injection) -->

- [ ] Create `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift`:
  ```swift
  import Foundation
  
  struct FastingBedtimeHeuristic {
      let healthKit: HealthKitServiceProtocol
      
      func computeAverageBedtime(over days: Int = 14) async -> DateComponents? {
          let end = Date()
          guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return nil }
          let range = DateInterval(start: start, end: end)
          guard let summaries = try? await healthKit.fetchDailySleepSummaries(for: range),
                summaries.count >= 3 else { return nil }
          // Use the bedtime field — sleep onset for each daily summary
          let bedtimes = summaries.compactMap { $0.bedtime }
          guard !bedtimes.isEmpty else { return nil }
          // Convert to minutes-since-midnight, take median
          let minutes = bedtimes.map { date -> Int in
              let comp = Calendar.current.dateComponents([.hour, .minute], from: date)
              return (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
          }.sorted()
          let median = minutes[minutes.count / 2]
          return DateComponents(hour: median / 60, minute: median % 60)
      }
  }
  ```
  - Verify: with seeded sleep data and ≥3 bedtimes, returns sensible DateComponents; with <3, returns nil

### 8.2 — Schedule start-reminder <!-- RESOLVED: CH3 — HealthKitServiceFactory.shared -->

- [ ] In `FastingService.swift`: add identifier `private static let notifStartReminder = "wp.fasting.startReminder"`
- [ ] Add to `clearNotifications()` removal list
- [ ] In `scheduleNotifications(for:)` (lines 209-263): at the end, add:
  ```swift
  Task {
      let heuristic = FastingBedtimeHeuristic(healthKit: HealthKitServiceFactory.shared)
      guard let bedtime = await heuristic.computeAverageBedtime(),
            let bedtimeHour = bedtime.hour, let bedtimeMin = bedtime.minute else { return }
      // Subtract 3h (with day-wrap)
      var startHour = bedtimeHour - 3
      let startMin = bedtimeMin
      if startHour < 0 { startHour += 24 }
      let displayHour = bedtimeHour > 12 ? bedtimeHour - 12 : bedtimeHour
      let formattedTime = String(format: "%d:%02d", displayHour, bedtimeMin)
      let content = UNMutableNotificationContent()
      content.title = "Start your rest"
      content.body = "Your usual bedtime is around \(formattedTime). A great time to start your rest is now."
      content.sound = .default
      var comps = DateComponents()
      comps.hour = startHour
      comps.minute = startMin
      let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
      UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notifStartReminder, content: content, trigger: trigger))
  }
  ```
  - Verify: with seeded sleep data, notification in pending list at bedtime-3h
- [ ] When `notificationsBlocked == true`: skip (existing guard at top of `scheduleNotifications`)
- [ ] Heuristic nil: silent fallback, no notification scheduled
  - Verify: simulator with <3 nights → `getPendingNotificationRequests` shows no `wp.fasting.startReminder`

### 8.3 — Phase 8 build + verification

- [ ] Build all 4 targets
- [ ] Manual test:
  - [ ] With ≥3 nights of HealthKit sleep data: force re-schedule → confirm reminder fires at bedtime-3h
  - [ ] With insufficient data: no notification scheduled
- [ ] `git commit -m "Phase 8: bedtime-derived circadian start reminder (no CLLocation)"`

---

## Post-Implementation

### Final build verification (all targets)

- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`

### Success criteria walkthrough (1:1 with plan §Success Criteria) <!-- RESOLVED: CM2 — expanded to 23 items -->

- [ ] All 4 targets build clean
- [ ] Phase −1 verified in TestFlight: Stress widget displays live data in Release build (App Group fix proven)
- [ ] First-time user routed to `FastingOnboardingFlow` (NOT Care view) on first Get Started tap
- [ ] **Three access state branches verified separately:**
  - [ ] `.onboarding` (no eligibility row) → onboarding flow
  - [ ] `.careBlocked` (row exists, `canInitiate == false`) → Care view
  - [ ] `.granted` (row exists, `canInitiate == true`) → FastingView
- [ ] SCOFF ≥2 positives routes to Care; individual answers persisted in 5 Bool fields
- [ ] Underage / pregnant / lactating users routed to Care
- [ ] No fasting session displays >24h elapsed; cap notification fires for session at noon when device reaches noon+24h
- [ ] Live Activity displays paused-at-24h state and offers interactive End button (tested in Release/TestFlight build)
- [ ] No "FASTING", "BROKEN", "Break Fast", neon red, or warning orange in any fasting surface
- [ ] Live Activity color/copy renders correctly on Apple Watch
- [ ] Schedule presets: 12:12 (default), 14:10, 16:8, 18:6, Custom. No 20:4
- [ ] Target hit triggers soft pulse + bonus-time counter; celebration only fires on explicit End. **Four scenarios verified separately:**
  - [ ] (A) End before target → `.endedEarly`, no celebration
  - [ ] (B) End during bonus → `.completed`, celebration fires
  - [ ] (C) Auto-rollover into eat window → `.overachieved`, silent close
  - [ ] (D) 24h cap → `.autoCappedAt24h`, banner appears, no celebration
- [ ] HRV/sleep insight banner shows contextually-relevant copy when data exists
- [ ] Ended sessions persist `contextualHRV` and `contextualSleepScore`
- [ ] HRV/sleep data shared via `SharedHealthMetrics` cache; **no duplicate HealthKit queries** when opening Stress then Fasting (Console.app log shows one fetch, not two)
- [ ] Weekly grid replaces flat list as primary history visualization
- [ ] Home `DigestiveStateCard` auto-appears in existing users' layouts via `reconcileWithCurrentCards`
- [ ] Bedtime-derived start reminder schedules when ≥3 nights HealthKit sleep data; silently no-ops otherwise
- [ ] No CLLocation permission in Info.plist
- [ ] No HealthKit `HKCategoryTypeIdentifier.mindfulSession` writes
- [ ] First-time user with existing data sees no SwiftData crash
- [ ] **Accessibility verified separately:**
  - [ ] VoiceOver pass through SCOFF questionnaire reads each question + Toggle state
  - [ ] Weekly grid cells have combined labels ("Tuesday, 14h fast, completed")
  - [ ] Live Activity End button has clear label + hint
  - [ ] Soft pulse animation respects `accessibilityReduceMotion` (no pulse when reduced)
- [ ] Care Intervention view footer notes US-only resources

### PR / merge

- [ ] Open PR per phase per plan §Suggested implementation sequencing (Phase −1 standalone; Phases 0+1+2+3 as v1.0.0; etc.)
- [ ] Each PR description references this checklist + plan + audit
- [ ] After merge of last PR for v1.0.0: tag release in Xcode, archive, submit to App Store Connect
