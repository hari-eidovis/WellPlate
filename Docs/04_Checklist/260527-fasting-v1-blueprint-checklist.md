# Implementation Checklist: Fasting v1 Blueprint

**Source Plan:** `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan-RESOLVED.md`
**Source Audit:** `Docs/03_Audits/260527-fasting-v1-blueprint-plan-audit.md`
**Date:** 2026-05-27
**Sequencing:** Phase −1 ships first (entitlements PR). Phases 0+1+2+3 → v1.0.0. Phase 4 → v1.0.1. Phase 5 → v1.1.0. Phase 6 → v1.2.0. Phases 7+8 → v1.3.0.

---

## Pre-Implementation

- [ ] Read `Docs/02_Planning/Specs/260527-fasting-v1-blueprint-plan-RESOLVED.md` end-to-end
- [ ] Read the Audit Resolution Summary table at top of plan to understand the 16 resolved findings
- [ ] Verify branch state — `git status` clean, branched off `main`
- [ ] Confirm Xcode + iOS SDK versions match repo expectations (iOS 26.1, Xcode 26)
- [ ] Run baseline build (all 4 targets) to confirm starting state is clean:
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
  - [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`
- [ ] Verify all files referenced below exist (see Architecture Changes table in plan §Modified files)

---

## Phase −1: App Group entitlement alignment (Pre-flight)

> **REQUIRES USER APPROVAL** before any entitlement edit per `MEMORY.md` `feedback-signing-entitlements` rule.

### −1.1 — User approval gate

- [ ] **STOP and ask user**: "About to edit `Cadence/Cadence.entitlements` to change App Group from `group.com.hariom.cadence.dev` to `group.com.hariom.cadence`. Approve?"
  - Verify: explicit user "yes" recorded before proceeding

### −1.2 — Provisioning profile verification

- [ ] Open Apple Developer console; confirm Release distribution provisioning profile includes the `group.com.hariom.cadence` App Group capability
  - Verify: capability listed under the profile's enabled capabilities
- [ ] If capability missing: add it, regenerate profile, install in Xcode before continuing
  - Verify: `security cms -D -i <profile>.mobileprovision | grep group.com.hariom.cadence` returns the App Group

### −1.3 — Entitlement edit

- [ ] Edit `Cadence/Cadence.entitlements` line 15: change `<string>group.com.hariom.cadence.dev</string>` → `<string>group.com.hariom.cadence</string>`
  - Verify: `grep "group.com.hariom.cadence" Cadence/Cadence.entitlements Cadence/CadenceDebug.entitlements CadenceWidget/CadenceWidget.entitlements` shows the same non-`.dev` ID in all three files

### −1.4 — Build + TestFlight verification

- [ ] Archive for Release: Product → Archive in Xcode
  - Verify: archive succeeds without signing errors
- [ ] Upload to TestFlight
  - Verify: TestFlight build processed without entitlement-mismatch warnings
- [ ] Install on device; open Stress widget; confirm it displays live data (not the empty/placeholder state)
  - Verify: widget shows current stress score from main app — proves App Group UserDefaults works end-to-end in Release

### −1.5 — Commit + ship

- [ ] `git add Cadence/Cadence.entitlements`
- [ ] `git commit -m "Align Release App Group to group.com.hariom.cadence (fixes silent SharedStressData breakage)"`
- [ ] Open PR; merge after approval

---

## Phase 0: Schema & preset foundation

### 0.1 — FastingCompletionStatus enum

- [ ] Create `Cadence/Models/FastingCompletionStatus.swift` with:
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
  - Verify: file compiles in isolation (`xcodebuild build` succeeds)

### 0.2 — FastingSession additive fields

- [ ] Edit `Cadence/Models/FastingSession.swift`: add three stored properties after `var createdAt: Date` (line 11):
  - `var completionStatus: String? = nil`
  - `var contextualHRV: Double? = nil`
  - `var contextualSleepScore: Int? = nil`
  - Verify: existing `init` callers still compile (defaults are optional, no breakage)
- [ ] Confirm app launches with existing seed data, no SwiftData crash
  - Verify: run app in simulator with pre-existing FastingSession rows; FastingView loads without error

### 0.3 — FastingEligibility model (5 separate SCOFF Bool fields)

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
  - Verify: file compiles
- [ ] Edit `Cadence/App/CadenceApp.swift:43`: add `FastingEligibility.self` to the modelContainer `for:` array
  - Verify: app launches, no SwiftData container error in console

### 0.4 — FastingAccessState helper

- [ ] Create `Cadence/Models/FastingAccessState.swift`:
  ```swift
  enum FastingAccessState { case onboarding, careBlocked, granted }
  
  extension FastingEligibility {
      static func accessState(from rows: [FastingEligibility]) -> FastingAccessState {
          guard let row = rows.first else { return .onboarding }
          return row.canInitiate ? .granted : .careBlocked
      }
  }
  ```
  - Verify: compiles; `FastingEligibility.accessState(from: [])` returns `.onboarding`

### 0.5 — Preset reshuffle in FastingScheduleType

- [ ] Edit `Cadence/Models/FastingSchedule.swift`:
  - Remove `case ratio20_4 = "20:4"` entirely
  - Add `case ratio12_12 = "12:12"` as the FIRST case in the enum (line ~6)
  - Reorder remaining cases to: `ratio12_12, ratio14_10, ratio16_8, ratio18_6, custom`
  - In `setupSubtitle` switch: add `.ratio12_12: return "Beginner-friendly 12h eating window"` and update others per Phase 3 step 20 (do now to avoid touching file twice)
  - In `defaultEatHours`: add `.ratio12_12: return 12`
  - In `defaultEatStartHour`: add `.ratio12_12: return 8`
  - In `icon`: add `.ratio12_12: return "sunrise"`
  - Verify: `FastingScheduleType.allCases` returns `[.ratio12_12, .ratio14_10, .ratio16_8, .ratio18_6, .custom]`
- [ ] In `FastingSchedule` init (line 105): change default `scheduleType: FastingScheduleType = .ratio16_8` → `.ratio12_12`; also change default `eatWindowStartHour: Int = 12` → `8` and `eatWindowDurationHours: Double = 8` → `12`
  - Verify: creating `FastingSchedule()` with no args produces a 12:12 schedule

### 0.6 — Legacy `"20:4"` data verification

- [ ] In simulator, manually seed a `FastingSchedule(scheduleType: .custom, eatWindowDurationHours: 4)` to simulate a pre-upgrade 20:4 user (or set raw `scheduleType = "20:4"` directly in SwiftData store)
- [ ] Open FastingView, confirm:
  - Display shows "20h fast" (Custom)
  - No crash on `resolvedScheduleType`
  - `applyFastDuration(20)` from editor returns `.custom`
  - Verify: all three above produce expected behavior

### 0.7 — Phase 0 build + commit

- [ ] Build all 4 targets (see Post-Implementation block at end)
- [ ] `git commit -m "Phase 0: fasting v1 schema foundation (eligibility model, completion status, 12:12 preset)"`

---

## Phase 1: Safety core (SCOFF + eligibility + soft block)

### 1.1 — Care Intervention view (US-only with caveat)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingCareInterventionView.swift` with:
  - Non-clinical heading: "Fasting may not be the best fit for your current wellness journey right now"
  - Supporting body paragraph
  - Three resource link buttons:
    - **National Alliance for Eating Disorders** → `https://allianceforeatingdisorders.com/find-help`
    - **988 Suicide & Crisis Lifeline** → `https://988lifeline.org`
    - "Talk to a healthcare provider" reminder (no link, just text)
  - Footer (small print): *"Resources listed are US-based. If you're outside the US, please contact your local mental health services or healthcare provider."*
  - "Re-take screening" CTA button
  - Use `AppColors.brand`, `.appShadow(radius:y:)`, `.r()` font helpers
  - Verify: opens in SwiftUI preview without crashing
- [ ] Each resource link has explicit `.accessibilityLabel("Opens [Name] website")`
- [ ] Footer text has `.accessibilityLabel` matching visible text
  - Verify: VoiceOver reads link destinations clearly

### 1.2 — FastingOnboardingFlow (4-step paged flow)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingOnboardingFlow.swift` with `TabView(selection:)`:
  - **Step 1 — Disclaimer:** full-screen text "Cadence is for general wellness, not medical advice. Talk to a licensed provider before changing dietary habits." Un-skippable "I understand" button
  - **Step 2 — Demographics:** three `Toggle`s ("Are you 18 or older?" / "Are you currently pregnant?" / "Are you currently lactating?"). Next button enables when all answered
  - **Step 3 — SCOFF:** five `Toggle`s (blueprint phrasing). Submit button computes `scoffPositiveCount`
  - **Step 4 — Schedule:** inline `FastingScheduleEditor`
  - Verify: navigation order works; Next/Submit buttons enable only when valid
- [ ] On demographic disqualification: persist `FastingEligibility` row with disqualifying flag, present `FastingCareInterventionView`, abort
  - Verify: setting age18Plus=false routes to Care
- [ ] On SCOFF ≥2 positives: persist all 5 answers + `scoffCleared = false` + `lastScreenedAt = .now`, present Care view, abort
  - Verify: answering 2 yes → Care view appears; FastingEligibility row exists with `scoffCleared = false`
- [ ] On SCOFF <2: persist 5 answers + `scoffCleared = true`, advance to step 4
  - Verify: 1 yes answer → advances; FastingEligibility row has `scoffCleared = true`
- [ ] On schedule save: set `eligibility.cleared = true`, `clearedAt = .now`, insert new `FastingSchedule`
  - Verify: post-onboarding, `FastingEligibility.canInitiate == true`
- [ ] Back-nav policy: SCOFF Toggles freely editable BEFORE Submit. After Care view, "Re-take screening" returns to step 3 with **fresh blank state** (no pre-fill)
  - Verify: re-take from Care does not preserve previous answers
- [ ] Mid-flow abandonment: app backgrounding → state not persisted; reopening returns to FastingView empty state
  - Verify: background app mid-SCOFF, reopen → FastingView shows empty state, not mid-flow
- [ ] Accessibility: each SCOFF Toggle has `.accessibilityLabel` matching the question; Submit button has `.accessibilityHint("Submit your answers and continue.")`
  - Verify: VoiceOver pass reads question, then "switch" state

### 1.3 — Replace FastingView Get Started CTA

- [ ] Edit `Cadence/Features + UI/Stress/Views/FastingView.swift` lines 203-228: the Get Started button now presents `FastingOnboardingFlow` as a sheet (NOT `FastingScheduleEditor` directly)
- [ ] Keep the gear icon (lines 78-87) as the post-onboarding "Edit Fast" path → still presents `FastingScheduleEditor`
  - Verify: first-time user tap → onboarding flow; existing user gear icon → schedule editor

### 1.4 — Access-state-gated routing across surfaces

- [ ] Edit `Cadence/Features + UI/Home/Views/HomeView.swift` lines 593-601 (fasting launcher button — about to be replaced in Phase 7, but for now): add `@Query private var eligibility: [FastingEligibility]` and route via `FastingEligibility.accessState(from: eligibility)`:
  - `.onboarding` → present `FastingOnboardingFlow`
  - `.careBlocked` → present `FastingCareInterventionView`
  - `.granted` → present `FastingView`
  - Verify: each of the 3 states routes correctly
- [ ] Edit `Cadence/Features + UI/Stress/Views/StressView.swift` line 198 (`.fasting` factor sheet case): same access-state-gated routing
  - Verify: tapping fasting factor in StressView routes correctly for each access state
- [ ] In `FastingView` itself: Get Started button (step 1.3) should skip onboarding flow if user is `.granted` (avoid re-onboarding)
  - Verify: a granted user accidentally on the empty state never sees the onboarding sheet

### 1.5 — Settings entry for re-screening

- [ ] Edit `FastingView.swift` toolbar (next to gear icon, line 78-87): add a `Menu` with two items: "Edit schedule" (current gear behavior) and "Re-take wellness screening"
- [ ] Re-take action presents `FastingOnboardingFlow` starting at step 3 (SCOFF), updates the existing `FastingEligibility` row (no new row created)
  - Verify: re-taking with different answers updates the same row; `lastScreenedAt` advances

### 1.6 — Phase 1 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test 4 branches:
  - [ ] Never-screened user → onboarding flow appears
  - [ ] Demographic fail (e.g. age <18) → Care view, no fast can be started
  - [ ] SCOFF fail (≥2 yes) → Care view, no fast can be started
  - [ ] All pass → schedule editor → fast can be started
- [ ] VoiceOver pass through entire onboarding flow
- [ ] `git commit -m "Phase 1: SCOFF + eligibility gate + Care Intervention soft block"`

---

## Phase 2: 24h cap + forgotten-stop guard

### 2.1 — Consolidated Live Activity ContentState schema (single update)

- [ ] Edit `Cadence/Widgets/FastingActivityAttributes.swift`: in `ContentState` add three Bools with defaults:
  ```swift
  var isCapped24h: Bool = false
  var isOverachieving: Bool = false
  var acceptsEndIntent: Bool = false
  ```
  - Verify: existing call sites compile unchanged (defaults are safe); both Cadence and CadenceWidget targets build

### 2.2 — 24h cap notification method

- [ ] Edit `Cadence/Core/Services/FastingService.swift`: add identifier `private static let notifCap24h = "wp.fasting.cap24h"` next to existing identifiers (lines 52-55)
- [ ] Add `wp.fasting.cap24h` to the `clearNotifications()` removal list (lines 266-273)
- [ ] Add new methods:
  ```swift
  func schedule24hCapNotification(for session: FastingSession) {
      let center = UNUserNotificationCenter.current()
      guard !notificationsBlocked else { return }
      let secondsUntilCap = (session.startedAt.addingTimeInterval(24*3600)).timeIntervalSinceNow
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

- [ ] Edit `FastingView.swift` `handleStateTransition` (line 615 block, after `modelContext.insert(session)` ~line 620): add `fastingService.schedule24hCapNotification(for: session)`
  - Verify: when a new session is created via eat→fast transition, cap notification is scheduled
- [ ] Edit `FastingView.swift` `startFastNow` (after `modelContext.insert(session)` ~line 655): add same call
  - Verify: manually started fast also schedules cap
- [ ] Edit `FastingView.swift` `breakCurrentFast` (line 682): add `fastingService.cancel24hCapNotification()`
  - Verify: ending fast cancels the pending cap notification

### 2.4 — Cap-state on FastingService

- [ ] In `FastingService.swift`: add `@Published private(set) var isCapped24h: Bool = false` next to other @Published properties (line 39-43)
- [ ] In `updateState(...)` method (line 93-143): after computing elapsed, add:
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

### 2.5 — Live Activity capped-state rendering

- [ ] Edit `ActivityManager.updateFastingActivity(progress:)` (line 85-98): when elapsed > 24h, set `state.isCapped24h = true`, clamp `state.progress = 1.0`
  - Verify: Live Activity ContentState reflects `isCapped24h = true` for old sessions
- [ ] Edit `CadenceWidget/LiveActivities/FastingLiveActivityView.swift`: in Lock Screen `phoneView` (line 109-146), Dynamic Island center (line 35-59), and Watch view (line 150-186): when `context.state.isCapped24h`, replace the timer block with text "Paused at 24h"
  - Verify: with capped state, Live Activity shows "Paused at 24h" on all three surfaces

### 2.6 — FastingView 24h-cap banner

- [ ] In `FastingView.swift`: when `fastingService.isCapped24h`, render a banner above `todayInfoCard` with copy "Fast paused at 24h" and two buttons:
  - "End Fast" → calls existing break flow
  - "Edit" → presents `FastingEditSessionSheet` (step 2.7) pre-targeting the active session
  - Verify: capped state shows banner; both buttons work

### 2.7 — FastingEditSessionSheet (retroactive correction)

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingEditSessionSheet.swift`:
  - Two `DatePicker`s for `startedAt` and `actualEndAt`
  - Validation: `end > start`, `end <= .now`, `(end - start) <= 24*3600`
  - Show inline error when validation fails
  - On save:
    - Persist new dates
    - Compute `completionStatus`:
      - `actualEndAt < targetEndAt` → `.endedEarly`
      - `actualEndAt >= targetEndAt && (actualEndAt - startedAt) < 24h` → `.completed`
      - `(actualEndAt - startedAt) >= 24h` → `.autoCappedAt24h`
    - Set legacy `completed` for compatibility (true for `.completed`/`.overachieved`/`.autoCappedAt24h`, false for `.endedEarly`)
    - Call `fastingService.cancel24hCapNotification()` if applicable
  - Verify: invalid date ranges blocked; valid ranges save with correct status

### 2.8 — Wire history rows to edit sheet

- [ ] Edit `FastingView.swift` lines 553-587: wrap each `fastHistoryRow(session)` in a `Button { editingSession = session }`
- [ ] Add `@State private var editingSession: FastingSession?` and `.sheet(item: $editingSession) { session in FastingEditSessionSheet(session: session) }`
  - Verify: tapping a history row opens the edit sheet pre-populated with that session's dates

### 2.9 — Phase 2 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test: seed a session with `startedAt = now - 25h` (debug seed). Open FastingView:
  - [ ] Capped banner appears
  - [ ] Live Activity shows "Paused at 24h"
  - [ ] Tapping Edit opens sheet with this session pre-targeted
  - [ ] Setting end to now+1h is rejected (>now)
  - [ ] Setting end to start+30h is rejected (>24h)
  - [ ] Valid edit saves and resolves status correctly
- [ ] `git commit -m "Phase 2: 24h cap + edit previous fast + Live Activity attribute consolidation"`

---

## Phase 3: Copy / color / lexicon pass

### 3.1 — FastingView copy + colors

- [ ] In `FastingView.swift` `stateLabel` (lines 692-698): change `"FASTING"` → `"RESTING"` and `"EATING"` → `"EATING WINDOW"`
- [ ] In `idleHeaderLabel` (line 702-704): change `"READY TO FAST"` → `"READY WHEN YOU ARE"`
- [ ] In `ringColor` (lines 706-712): return `heroAccent` for `.fasting`, existing green for `.eating`. **Remove `.orange` case entirely**
  - Verify: grep `FastingView.swift` for `.orange` returns no matches in `ringColor`
- [ ] In `breakFastAlertMessage` (lines 131-137): replace body with *"Listening to your body is always the right choice. You've fasted for \(formattedDuration(elapsed)) so far."*
- [ ] In alert title (line 99): change `"Break Fast Early?"` → `"End your fast?"`
- [ ] In Break Fast button label (line 423): change `"Break Fast"` → `"End Fast"`
- [ ] In `fastHistoryRow` (line 574): change `"Broken"` → `"Ended early"`
- [ ] In empty state subtitle (lines 196-200): replace with *"Rest your digestive system and align eating with your body clock."*
  - Verify: grep `FastingView.swift` for `"BROKEN"`, `"FASTING"`, `"Break Fast"`, `"Broken"` returns no matches

### 3.2 — Live Activity color + copy + Watch verification

- [ ] In `FastingLiveActivityView.swift` `ringColor(for:)` (lines 277-281): change broken-state `.red` → `.white.opacity(0.55)`. Keep active state `.orange` (acceptable per HIG, matches `heroAccent` family)
- [ ] Lock Screen broken-state text colors (lines 128, 167, 46): change `.red` → `.white.opacity(0.7)`
- [ ] In Dynamic Island expanded center (line 42): change `"Fast complete"` → `"Rest complete"`
- [ ] Verify on Apple Watch (or simulator pair):
  - [ ] Start a fast → Live Activity appears on Apple Watch
  - [ ] Confirm WatchLogoRing renders correctly (line 244-273 path)
  - [ ] Text labels render at correct size, no truncation
  - Verify: visual confirmation Watch surface still works

### 3.3 — Notification copy

- [ ] Edit `FastingService.scheduleNotifications` (lines 209-263):
  - "Eating Window Closed" body → *"Your \(scheduleLabel) rest has begun. Hydrate well."*
  - "1 Hour Left" body → *"Eating window opens in 1 hour. Plan something nourishing."*
  - "Fast Complete" body → *"Rest complete. Break your fast whenever you feel ready."*
  - Caffeine cutoff: leave as-is
  - Verify: trigger notification manually in simulator (e.g. with `DispatchQueue.main.asyncAfter`), copy reads as updated

### 3.4 — Schedule editor preset subtitles

- [ ] In `FastingSchedule.swift` `FastingScheduleType.setupSubtitle` (lines 25-38) — update per Phase 0 step 0.5 if not already done:
  - `.ratio12_12`: "Beginner-friendly 12h eating window"
  - `.ratio14_10`: "Gentle plan with a 10h eating window"
  - `.ratio16_8`: "Common plan with an 8h eating window" (drop "most")
  - `.ratio18_6`: "Focused plan with a 6h eating window"
  - `.custom`: "Choose your own eating window"
  - Verify: open schedule editor in app, confirm subtitles match

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

- [ ] In `FastingService.swift`: add `@Published private(set) var isOverachieving: Bool = false` and `@Published private(set) var bonusElapsed: TimeInterval = 0` next to other @Published (line 39-43)
- [ ] In `updateState(...)`: add overachieving branch (must be ordered AFTER `isCapped24h` check from step 2.4 — capped takes precedence):
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
  - Verify: seed a session with `targetEndAt = now - 5min` → `isOverachieving = true`, `bonusElapsed ≈ 300`; seed 25h session → `isCapped24h = true`, `isOverachieving = false`

### 4.2 — Timer ring pulse + bonus label

- [ ] In `FastingView.swift` `activeTimerCard` (lines 246-353): when `fastingService.isOverachieving`:
  - Ring stays at full, opacity pulses 0.85 ↔ 1.0 via `.animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true))`
  - Replace `formattedTimeRemaining` label with `"+\(formattedDuration(fastingService.bonusElapsed))"`
  - Replace `"REMAINING"` subtitle with `"BONUS TIME"`
  - Hide percentage line
  - Fire one soft `HapticService.impact(.light)` at first transition (use `@State previousIsOverachieving: Bool`)
  - Verify: visual confirmation pulse + bonus label
- [ ] Respect `accessibilityReduceMotion`: when reduced, no pulse (hold at full opacity)
  - Verify: enable Reduce Motion in simulator Accessibility settings → no pulse animation
- [ ] Time label gets `.accessibilityLabel("Bonus time: \(spokenDuration)")` for VoiceOver
  - Verify: VoiceOver reads "Bonus time: 5 minutes"

### 4.3 — Decouple celebration from auto-transition

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
              celebration = FastingCompletionEvent(...)
          }
      } else {
          // Silent overachieve close
          session.completionStatus = FastingCompletionStatus.overachieved.rawValue
          session.completed = true
          ActivityManager.shared.endFastingActivity(completed: true)
      }
      didUserExplicitlyEnd = false
  }
  ```
- [ ] In `breakCurrentFast` (line 682): when called and `fastingService.isOverachieving == true`, set `didUserExplicitlyEnd = true`, `session.completionStatus = .completed`, fire celebration. When `isOverachieving == false`, set `completionStatus = .endedEarly`, no celebration (current behavior)
  - Verify: four scenarios all work correctly (see step 4.4)
- [ ] Reset `didUserExplicitlyEnd = false` on new session start (in `handleStateTransition` eating → fasting block and `startFastNow`)

### 4.4 — Phase 4 four-scenario QA

- [ ] **Scenario A:** Start fast, end BEFORE target (e.g. 1h into 12h fast). Tap End Fast.
  - Verify: `completionStatus = .endedEarly`, no celebration, ring is red-tinted "ended" style
- [ ] **Scenario B:** Start fast, let target pass, see bonus time, then tap End Fast.
  - Verify: `completionStatus = .completed`, celebration confetti fires
- [ ] **Scenario C:** Start fast, let target pass, do NOT tap End Fast, wait for next eating window to start (auto-transition).
  - Verify: `completionStatus = .overachieved`, NO celebration, history shows session as "Completed" silently
- [ ] **Scenario D:** Start fast, let 24h elapse (seed-time).
  - Verify: `isCapped24h = true` precedes overachieving, banner appears, no celebration

### 4.5 — Phase 4 build + commit

- [ ] Build all 4 targets
- [ ] `git commit -m "Phase 4: soft completion + bonus time + explicit-end celebration"`

---

## Phase 5: Contextual intelligence

### 5.1 — SharedHealthMetrics App-Group cache

- [ ] Create `Cadence/Widgets/SharedHealthMetrics.swift` (follow `SharedStressData.swift` pattern):
  ```swift
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
  }
  ```
  - Verify: compiles in both Cadence and CadenceWidget targets

### 5.2 — StressViewModel writes to cache

- [ ] Locate the HealthKit fetch completion path in `StressViewModel.loadData()` (`Cadence/Features + UI/Stress/ViewModels/StressViewModel.swift`)
- [ ] After `todayHRV` and `sleepHistory` are populated, write a `SharedHealthMetrics` row:
  ```swift
  let metrics = SharedHealthMetrics(
      date: Calendar.current.startOfDay(for: Date()),
      hrvMs: todayHRV,
      sleepScore: sleepHistory.last?.computedScore, // derive however existing logic does
      lastUpdated: .now
  )
  metrics.save()
  ```
  - Verify: open Stress view → inspect App Group UserDefaults via debug console → `sharedHealthMetrics` key exists with today's data

### 5.3 — FastingContextProvider

- [ ] Create `Cadence/Features + UI/Stress/Services/FastingContextProvider.swift`:
  ```swift
  @MainActor final class FastingContextProvider: ObservableObject {
      @Published var todayHRV: Double?
      @Published var lastNightSleepScore: Int?
      @Published var sevenDayStressAvg: Double?
      
      func loadContext(healthKit: HealthKitService, modelContext: ModelContext) async {
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
                  lastNightSleepScore = computeSleepScore(from: summary) // helper
              }
              // 3. Write back to cache
              SharedHealthMetrics(
                  date: today, hrvMs: todayHRV,
                  sleepScore: lastNightSleepScore, lastUpdated: .now
              ).save()
          }
          // 4. Stress avg from SwiftData
          sevenDayStressAvg = computeSevenDayAvg(modelContext: modelContext)
      }
  }
  ```
  - Verify: compiles; first call fetches, second call within same day uses cache (no duplicate HealthKit query in console log)

### 5.4 — Insight banner under timer

- [ ] In `FastingView.swift`: add `@StateObject private var contextProvider = FastingContextProvider()`
- [ ] In `configureService()`: call `Task { await contextProvider.loadContext(healthKit: ..., modelContext: modelContext) }`
- [ ] Add private view `insightBanner` between `activeTimerCard` and `todayInfoCard` rendering one of:
  - HRV high (today > baseline + 5ms): *"Your HRV is strong today. A \(scheduleHours)h rest aligns well with your recovery."*
  - HRV low (today < baseline - 5ms): *"Your autonomic nervous system shows elevated stress today. Consider a shorter rest (12h) to support recovery."*
  - Sleep score low (<70): *"Sleep was light last night. Listen to your body — it's okay to end your fast early today."*
  - No data: return `EmptyView()` (hide banner)
- [ ] Define thresholds as `private static let` constants at top of file
- [ ] Add `.accessibilityLabel` matching visible text + `.accessibilityHint("Personal recommendation based on your recent recovery metrics.")`
  - Verify: with seeded HRV high → banner shows recovery message; HRV low → shorter-rest message; no data → no banner

### 5.5 — Bind context to session on end

- [ ] In `FastingView.handleStateTransition` and `breakCurrentFast`: before save, write:
  ```swift
  session.contextualHRV = contextProvider.todayHRV
  session.contextualSleepScore = contextProvider.lastNightSleepScore
  ```
  - Verify: end a fast → inspect `FastingSession` row → `contextualHRV` and `contextualSleepScore` populated

### 5.6 — Phase 5 build + manual verification

- [ ] Build all 4 targets
- [ ] Manual test: with HealthKit auth granted and real HRV/sleep data:
  - [ ] Open FastingView → banner appears with appropriate copy
  - [ ] End a fast → row shows non-nil contextual fields
  - [ ] Verify no duplicate HealthKit queries via Console.app log (open Stress view first, then Fasting view → only one HRV fetch in logs)
- [ ] `git commit -m "Phase 5: contextual HRV/sleep insight + SharedHealthMetrics cache"`

---

## Phase 6: LiveActivityIntent End Fast

> **Depends on Phase −1 having shipped.** Cannot verify in Release without aligned App Group.

### 6.1 — BreakFastIntent (cross-process safe)

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
          let payload = PendingBreakPayload(timestamp: .now, reason: "userExplicit")
          if let d = UserDefaults(suiteName: "group.com.hariom.cadence"),
             let data = try? JSONEncoder().encode(payload) {
              d.set(data, forKey: "pendingBreakFast")
          }
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
  - Verify: builds in both Cadence and CadenceWidget targets
- [ ] Confirm target membership: file is in `Cadence/Widgets/` (auto-included in Cadence target via PBXFileSystemSynchronizedRootGroup) and accessible from CadenceWidget
  - Verify: `xcodebuild -project Cadence.xcodeproj -target CadenceWidget build` succeeds

### 6.2 — Set acceptsEndIntent true while fasting

- [ ] In `ActivityManager.startFastingActivity` (line 34-80): in the initial `ContentState`, set `acceptsEndIntent: true`
- [ ] In `ActivityManager.endFastingActivityInternal` (line 108-121): set `acceptsEndIntent: false` in finalState
  - Verify: Live Activity state correctly toggles `acceptsEndIntent` over lifecycle

### 6.3 — Wire intent button into Live Activity

- [ ] In `FastingLiveActivityView.swift` Lock Screen `phoneView` (lines 109-146): when `context.state.acceptsEndIntent && !context.state.isCompleted && !context.state.isBroken`, render `Button(intent: BreakFastIntent()) { Text("End").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.2))).foregroundStyle(.white) }` inline at the bottom-right
  - Verify: button appears on Lock Screen during active fast
- [ ] In Dynamic Island `.bottom` region (lines 60-71): when `acceptsEndIntent`, render same button on the right alongside the existing "Eat window opens" caption
  - Verify: button appears in expanded Dynamic Island
- [ ] Skip compact/minimal/Watch families (no space / out of scope for v1)
- [ ] Add `.accessibilityLabel("End Fast")` + `.accessibilityHint("Ends your current fast and opens the eating window.")` to each button
  - Verify: VoiceOver on Lock Screen reads "End Fast" + hint

### 6.4 — App reconciles pending-break on foreground

- [ ] In `FastingView.configureService()` (lines 591-609): at the top, add:
  ```swift
  if let d = UserDefaults(suiteName: "group.com.hariom.cadence"),
     let data = d.data(forKey: "pendingBreakFast"),
     let payload = try? JSONDecoder().decode(PendingBreakPayload.self, from: data) {
      if let session = activeSession {
          session.actualEndAt = payload.timestamp
          let wasOverachieving = session.actualDurationSeconds >= session.targetDurationSeconds
          session.completionStatus = (wasOverachieving ? FastingCompletionStatus.completed : .endedEarly).rawValue
          session.completed = wasOverachieving
          session.contextualHRV = contextProvider.todayHRV
          session.contextualSleepScore = contextProvider.lastNightSleepScore
          fastingService.cancel24hCapNotification()
          ActivityManager.shared.endFastingActivity(completed: wasOverachieving)
      }
      d.removeObject(forKey: "pendingBreakFast")
  }
  ```
  - Verify: idempotent — running twice with no active session is safe; running once correctly closes the session

### 6.5 — Phase 6 verification (REQUIRES TESTFLIGHT)

- [ ] Build for Release, upload to TestFlight, install on device
- [ ] Start a fast in the app, lock device, swipe to Lock Screen Live Activity, tap End
  - Verify: unlock app → fast shows as ended in history
- [ ] Repeat with Dynamic Island long-press → tap End
  - Verify: same result
- [ ] Repeat with app foregrounded → tap End on Live Activity
  - Verify: app immediately reflects ended state
- [ ] `git commit -m "Phase 6: LiveActivityIntent End Fast button (Lock Screen + Dynamic Island)"`

---

## Phase 7: Weekly grid + Home Digestive State card

### 7.1 — FastingWeeklyGridView

- [ ] Create `Cadence/Features + UI/Stress/Views/FastingWeeklyGridView.swift`:
  - Takes `sessions: [FastingSession]`
  - Horizontal 7-column grid using `Calendar.current.firstWeekday`
  - Each cell: day-of-week abbreviation (top), colored square (middle), small duration label (bottom)
  - Color logic by `resolvedStatus`:
    - `.completed` or `.overachieved` → filled `heroAccent`
    - `.endedEarly` → hatched (diagonal stripe)
    - `.autoCappedAt24h` → filled muted gray
    - No fast that day → empty outline
  - Highlight today with ring
  - Each cell: `.accessibilityElement(children: .combine)` with label like "Tuesday, 14h fast, completed"
  - Verify: compiles, renders in SwiftUI preview with sample data

### 7.2 — Integrate grid into FastingView

- [ ] In `FastingView.swift` `historySection` (lines 510-551): replace the `ForEach(completedSessions, id: \.persistentModelID) { session in fastHistoryRow(session) }` (lines 538-542) with `FastingWeeklyGridView(sessions: sessions)`
- [ ] Below the grid, render a separate "Recent" sub-section keeping the tappable history rows (preserves edit capability from step 2.8)
  - Verify: FastingView shows grid as primary, list as secondary

### 7.3 — HomeCardID.fasting case

- [ ] Edit `Cadence/Models/HomeLayoutConfig.swift` `HomeCardID` enum (lines 8-15): add `case fasting` after `case wellnessRings` (position 2c)
- [ ] In `displayName` switch (lines 18-27): add `case .fasting: return "Fasting"`
- [ ] In `iconName` switch (lines 29-38): add `case .fasting: return "fork.knife.circle"`
- [ ] In `hasSubElements` switch (lines 41-46): leave default `false` (no change)
- [ ] In `subElements` switch (lines 49-55): leave default `[]` (no change)
  - Verify: `HomeCardID.allCases` returns 7 cases (was 6); `HomeCardID.fasting.displayName == "Fasting"`
- [ ] Verify existing users' layouts auto-migrate: `HomeLayoutConfig.reconcileWithCurrentCards()` (lines 187-195) appends new cases. Test by:
  - [ ] Seed an existing layout with old `cardOrder` (no `.fasting`)
  - [ ] Call `reconcile()`
  - [ ] Confirm `.fasting` appears at end of `cardOrder`

### 7.4 — DigestiveStateCard

- [ ] Create `Cadence/Features + UI/Home/Components/DigestiveStateCard.swift`:
  - `@Query private var schedules: [FastingSchedule]`
  - `@Query private var sessions: [FastingSession]`
  - `@Query private var eligibility: [FastingEligibility]`
  - `@StateObject private var fastingService = FastingService()`
  - Card shows:
    - Current state label ("Resting" / "Eating Window" / "Set up fasting")
    - Mini circular progress (use existing `heroAccent` color logic)
    - Most recent fast result (e.g. "Last: 14h ✓")
    - One-line readiness summary (sleep + stress) from `SharedHealthMetrics` cache
  - Card background: `RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)).appShadow(radius: 15, y: 5)` (matches other Home cards)
  - On tap: route via `FastingEligibility.accessState(from: eligibility)` (per Phase 1 step 1.4 pattern)
  - Verify: card renders in SwiftUI preview; tap routes correctly per access state

### 7.5 — Integrate DigestiveStateCard into HomeView

- [ ] Edit `Cadence/Features + UI/Home/Views/HomeView.swift` `cardView(for:)` (line 130): add new branch:
  ```swift
  case .fasting:
      DigestiveStateCard()
  ```
- [ ] Remove the old `headerAssetIcon("fasting_icon")` launcher button (lines 593-601) — the card replaces it
  - Verify: Home dashboard shows DigestiveStateCard in correct slot; old launcher gone

### 7.6 — Phase 7 build + verification

- [ ] Build all 4 targets
- [ ] Manual test:
  - [ ] Seed varied session history (completed, ended early, no-fast days)
  - [ ] FastingView shows weekly grid correctly with right colors
  - [ ] Home shows DigestiveStateCard in layout (existing user → card auto-added at end of `cardOrder`)
  - [ ] DigestiveStateCard tap routes correctly for each access state (test all 3)
- [ ] VoiceOver pass on weekly grid cells
- [ ] `git commit -m "Phase 7: weekly grid + Home DigestiveStateCard (HomeCardID.fasting)"`

---

## Phase 8: Bedtime-derived start reminder

### 8.1 — Bedtime heuristic

- [ ] Create `Cadence/Features + UI/Stress/Services/FastingBedtimeHeuristic.swift`:
  ```swift
  struct FastingBedtimeHeuristic {
      let healthKit: HealthKitService
      
      func computeAverageBedtime(over days: Int = 14) async -> DateComponents? {
          let end = Date()
          let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
          let range = DateInterval(start: start, end: end)
          guard let summaries = try? await healthKit.fetchDailySleepSummaries(for: range),
                summaries.count >= 3 else { return nil }
          // Extract sleep-onset times (TBD: locate the actual onset field in DailySleepSummary)
          let onsetTimes = summaries.compactMap { $0.startTime } // adjust field name
          guard !onsetTimes.isEmpty else { return nil }
          // Convert to minutes-since-midnight and take median
          let minutes = onsetTimes.map { date -> Int in
              let comp = Calendar.current.dateComponents([.hour, .minute], from: date)
              return (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
          }.sorted()
          let median = minutes[minutes.count / 2]
          return DateComponents(hour: median / 60, minute: median % 60)
      }
  }
  ```
  - Verify: with seeded sleep data, returns a sensible DateComponents; with <3 nights, returns nil

### 8.2 — Schedule start-reminder

- [ ] In `FastingService.swift`: add identifier `private static let notifStartReminder = "wp.fasting.startReminder"`
- [ ] Add to `clearNotifications()` removal list
- [ ] In `scheduleNotifications(for:)` (lines 209-263): at the end, add:
  ```swift
  Task {
      let heuristic = FastingBedtimeHeuristic(healthKit: HealthKitService.shared) // or however injected
      guard let bedtime = await heuristic.computeAverageBedtime() else { return }
      guard let bedtimeHour = bedtime.hour, let bedtimeMin = bedtime.minute else { return }
      // Subtract 3h
      var startHour = bedtimeHour - 3
      var startMin = bedtimeMin
      if startHour < 0 { startHour += 24 }
      let formattedTime = String(format: "%d:%02d", bedtimeHour > 12 ? bedtimeHour - 12 : bedtimeHour, bedtimeMin)
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
  - Verify: with seeded sleep data, notification appears in pending list at bedtime-3h
- [ ] When `notificationsBlocked == true`: skip silently (guard at top)
- [ ] When heuristic returns nil: no notification scheduled (silent fallback)
  - Verify: simulator with <3 nights of sleep → `getPendingNotificationRequests` shows no `wp.fasting.startReminder`

### 8.3 — Phase 8 build + verification

- [ ] Build all 4 targets
- [ ] Manual test:
  - [ ] With ≥3 nights of HealthKit sleep data (real account or seeded): force re-schedule → confirm notification fires at bedtime-3h
  - [ ] With insufficient data: no notification scheduled
- [ ] `git commit -m "Phase 8: bedtime-derived circadian start reminder (no CLLocation)"`

---

## Post-Implementation

### Final build verification (all targets)

- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme Cadence -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -workspace Cadence.xcworkspace -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build`
- [ ] `xcodebuild -project Cadence.xcodeproj -target CadenceWidget -destination 'generic/platform=iOS Simulator' build`

### Success criteria walkthrough (from plan §Success Criteria)

- [ ] First-time user routed to onboarding (NOT Care view) on first Get Started tap
- [ ] SCOFF ≥2 positives routes to Care; individual answers persisted in 5 Bool fields
- [ ] Underage / pregnant / lactating users routed to Care
- [ ] No fasting session displays >24h; cap notification fires at +24h
- [ ] Live Activity displays paused-at-24h state with interactive End button (verified in Release/TestFlight)
- [ ] No "FASTING"/"BROKEN"/"Break Fast"/neon red/warning orange in any fasting surface
- [ ] Live Activity copy/color renders correctly on Apple Watch
- [ ] Schedule presets: 12:12 (default), 14:10, 16:8, 18:6, Custom. No 20:4
- [ ] Soft pulse + bonus time at target hit; celebration only on explicit End; 4 scenarios verified
- [ ] HRV/sleep insight banner shows contextually-relevant copy when data exists
- [ ] Ended sessions persist `contextualHRV` + `contextualSleepScore`
- [ ] No duplicate HealthKit queries (Stress view → Fasting view shows cached read)
- [ ] Weekly grid is primary history view; recent list secondary tappable
- [ ] Home `DigestiveStateCard` auto-appears in existing user layouts
- [ ] Bedtime start-reminder schedules when ≥3 nights HealthKit data; silently no-ops otherwise
- [ ] No CLLocation permission in Info.plist
- [ ] No HealthKit `mindfulSession` writes
- [ ] First-time user with existing data: no SwiftData crash
- [ ] Accessibility: VoiceOver pass through SCOFF, weekly grid, Live Activity button; soft pulse respects reduceMotion
- [ ] Care Intervention view footer notes US-only resources

### PR / merge

- [ ] Open PR per phase per plan §Suggested implementation sequencing (Phase −1 standalone; Phases 0+1+2+3 as v1.0.0; etc.)
- [ ] Each PR description references this checklist + plan + audit
- [ ] After merge of last PR for v1.0.0: tag release in Xcode, archive, submit to App Store Connect
