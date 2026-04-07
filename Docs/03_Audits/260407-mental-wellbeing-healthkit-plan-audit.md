# Plan Audit Report: HealthKit Mental Wellbeing Integration (F2)

**Audit Date**: 2026-04-07
**Plan Version**: `Docs/02_Planning/Specs/260407-mental-wellbeing-healthkit-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is well-structured and correctly scoped — 5 files, zero new files, thin integration layer. However, it contains **one critical design flaw** (prefilling `selectedMood` from HealthKit will trigger the `onChange` auto-save handler, bypassing user confirmation entirely), **one high-severity authorization gap** (no HealthKit auth call exists on the Home tab where mood lives), and **several medium issues** around unverified API signatures and stale usage descriptions. The plan must be revised before proceeding to checklist.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1. onChange(of: selectedMood) auto-save race condition

- **Location**: Plan Step 2.2 (`refreshTodayMoodState`) + Step 2.3 (`prefillMoodFromHealthIfNeeded`)
- **Problem**: The plan sets `selectedMood = mood` when prefilling from HealthKit. However, HomeView has an `onChange(of: selectedMood)` handler (line 191–194) that fires on ANY `selectedMood` change and immediately calls `logMoodForTodayIfNeeded(mood)`. Since `hasLoggedMoodToday` is `false` (that's why we're prefilling), the handler will:
  1. Create/fetch today's `WellnessDayLog`
  2. Set `todayLog.moodRaw = mood.rawValue`
  3. Save to SwiftData
  4. Set `hasLoggedMoodToday = true`
  5. The `MoodCheckInCard` disappears (it's guarded by `if !hasLoggedMoodToday`)
- **Impact**: The user never sees the prefilled card, never sees the "From Health" badge, and never gets the chance to override the Health-suggested mood. The entire prefill UX is broken.
- **Recommendation**: Do NOT set `selectedMood` for the prefill. Instead:
  - **Option A (preferred)**: Add a separate `@State private var healthSuggestedMood: MoodOption?` and pass it to `MoodCheckInCard` as a new `suggestion` parameter. The card shows the suggestion visually (pre-highlighted emoji + badge) but does NOT write to `selectedMood`. When the user taps any emoji, the normal `selectedMood` binding + `onChange` flow fires as before.
  - **Option B**: Guard the `onChange` handler with `!isMoodFromHealth`, and reset `isMoodFromHealth = false` inside `MoodCheckInCard.handleTap` via a new binding or callback. Messier, but fewer parameter changes.
  - Option A is cleaner because it keeps the mood card's existing binding semantics intact.

---

### HIGH (Should Fix Before Proceeding)

#### H1. No HealthKit authorization on the Home tab

- **Location**: Plan Step 1.3 Part D (authorization) and the general "authorization happens at onboarding" assumption in the strategy
- **Problem**: The plan states "this happens at the existing onboarding authorization point." **There is no onboarding HealthKit authorization.** HealthKit auth is called lazily — only when the user navigates to the Stress tab (`StressViewModel.requestPermissionAndLoad`), Sleep tab (`SleepViewModel`), or Burn tab (`BurnViewModel`). HomeView has no `requestAuthorization` call.
  - If a user installs the app and logs mood before ever visiting Stress/Sleep/Burn, the `writeMood` call fires against an unauthorized store → silently fails (acceptable due to `try?` pattern)
  - The `fetchTodayMood` call also fails → no prefill even if the user has Health data (unacceptable — defeats the feature's purpose)
- **Impact**: For new users or users who only use the Home tab, the entire HK sync is non-functional until they happen to visit another tab.
- **Recommendation**: Add a lightweight authorization step before the first HealthKit mood operation. Options:
  - Call `try? await HealthKitService().requestAuthorization()` once inside `prefillMoodFromHealthIfNeeded()` before calling `fetchTodayMood()`. This is safe because HealthKit's `requestAuthorization` is idempotent — it only shows the dialog once.
  - Or, add a `.task {}` in HomeView's `.onAppear` to request HealthKit authorization (alongside `bindContext` calls at line 178–180).
  - The second option is more forward-looking and matches the pattern in other views.

#### H2. HKStateOfMind API surface is speculative

- **Location**: Plan Step 1.3, Parts B/C/E/F
- **Problem**: The plan makes specific API assumptions that have not been verified against the iOS 18+ SDK:
  1. `HKStateOfMind.sampleType` — the correct static property may be named differently (e.g., `HKStateOfMind.stateOfMindType()`, or `HKSampleType(.stateOfMind)`)
  2. `HKStateOfMind(date:kind:valence:labels:associations:)` initializer — parameter names and types may differ
  3. `.stateOfMind(predicate)` factory on `HKSamplePredicate` — may have a different method name
  4. `store.save(sample)` async variant — `HKHealthStore` may require the callback-based save for HKStateOfMind
- **Impact**: If any of these API calls are wrong, the implementation will fail to compile. The plan's Step 1.5 (build verification) catches this, but the implementer won't know the correct API without research.
- **Recommendation**: The plan should include a **Step 1.0 (API Discovery)**: before writing any code, use Xcode's "Open Quickly" or a test file to verify the exact `HKStateOfMind` initializer, sample type accessor, and query predicate factory. Document the findings before proceeding. Alternatively, include fallback pseudocode for each API call with a note to "verify exact signature."

---

### MEDIUM (Fix During Implementation)

#### M1. Usage description strings need updating

- **Location**: Not mentioned in plan
- **Problem**: The project has these HealthKit usage descriptions in the Xcode build settings:
  - `NSHealthShareUsageDescription`: "WellPlate reads your activity and health data to show Burn and Sleep insights alongside your nutrition."
  - `NSHealthUpdateUsageDescription`: "Please allow this to fetch your health data in this app"
  
  The share (read) description doesn't mention mood. The update (write) description is a generic placeholder that says "fetch" when it should describe writing — and it doesn't mention mood/State of Mind. Apple may reject the app if the write description doesn't accurately describe what data is being written.
- **Impact**: Potential App Store rejection; poor user trust if the permission dialog doesn't explain why mood access is needed.
- **Recommendation**: Add a step to update both descriptions in the Xcode build settings:
  - `NSHealthShareUsageDescription`: "WellPlate reads your activity, health, and mood data to show wellness insights alongside your nutrition."
  - `NSHealthUpdateUsageDescription`: "WellPlate saves your daily mood check-in to Apple Health so it stays in sync with your other health data."

#### M2. MoodCheckInCard must support the suggestion pattern (from C1 fix)

- **Location**: Plan Step 3.1–3.2
- **Problem**: If C1 is fixed via Option A (separate `healthSuggestedMood` state), then `MoodCheckInCard` needs a `suggestion: MoodOption?` parameter instead of or alongside `isFromHealth: Bool`. The card must:
  1. Visually pre-highlight the suggested emoji (same ring/glow as selected)
  2. Show the "Suggested from Apple Health" badge
  3. NOT write to the `selectedMood` binding until the user taps
  4. If user taps the suggested emoji, treat it as a first selection (not double-tap confirm)
- **Impact**: The plan's current Step 3.1–3.2 must be reworked to match the C1 fix.
- **Recommendation**: Redesign the MoodCheckInCard changes:
  - Add `suggestion: MoodOption? = nil` parameter
  - In `MoodPill`, check `isSelected || (mood == suggestion)` for visual highlighting, with a slightly different style for suggestion (e.g., dashed ring instead of solid, or lower opacity)
  - Show badge when `suggestion != nil && selectedMood == nil`

#### M3. New HealthKitService() instances lack authorization state

- **Location**: Plan Steps 2.3 and 2.4
- **Problem**: The plan creates `HealthKitService()` inline for each mood operation. Each new instance starts with `isAuthorized = false`. The `writeMood` and `fetchTodayMood` methods don't check `isAuthorized` before making HealthKit calls — they rely on HealthKit's own error handling. This works (HealthKit returns errors or empty results for unauthorized queries), but is inconsistent with how other ViewModels use the service (they check `service.isAuthorized` after auth).
- **Impact**: Low — HealthKit handles unauthorized access gracefully. But `isAuthorized` is misleading.
- **Recommendation**: Either:
  - Accept this pattern for fire-and-forget calls (document the intent)
  - Or use a shared/singleton `HealthKitService` instance (more invasive change, defer to future)

#### M4. Existing users will see a new authorization prompt

- **Location**: Plan Step 1.3 Part D
- **Problem**: Adding `HKStateOfMind` to the authorization sets means existing users who already approved HealthKit access will see a new system dialog the next time `requestAuthorization` is called (on their next visit to Stress/Sleep/Burn tabs). The dialog will show only the new "State of Mind" type since previously approved types are already granted.
- **Impact**: Low — this is normal HealthKit behavior. But users may be confused by the unexpected prompt.
- **Recommendation**: No code change needed, but add a note to the testing strategy: verify the incremental authorization dialog on an existing device.

---

### LOW (Consider for Future)

#### L1. Preview not updated for MoodCheckInCard

- **Location**: Plan Step 3.1–3.2
- **Problem**: The `#Preview` at the bottom of `MoodCheckInCard.swift` (line 193–205) doesn't pass the new parameter, so the badge won't be visible in previews for easy design iteration.
- **Recommendation**: Add a second preview variant showing the badge: `MoodCheckInCard(selectedMood: .constant(.good), isFromHealth: true)` (or `suggestion: .good` depending on C1 fix).

#### L2. No Siri/Shortcuts integration mentioned

- **Location**: Non-goal boundary
- **Problem**: HKStateOfMind supports Siri Shortcuts for mood logging. The plan doesn't mention this as a non-goal.
- **Recommendation**: Add to non-goals: "Siri Shortcuts for mood logging — consider for future after base sync is stable."

---

## Missing Elements

- [ ] **Step for updating usage description strings** (NSHealthShareUsageDescription + NSHealthUpdateUsageDescription) — see M1
- [ ] **Step for HealthKit authorization in HomeView** — see H1
- [ ] **API discovery/verification step** before implementation — see H2
- [ ] **MoodCheckInCard redesign** accounting for C1 fix (suggestion pattern vs. binding mutation)
- [ ] **Preview variant** for the badge state — see L1

---

## Unverified Assumptions

- [ ] `HKStateOfMind.sampleType` is a valid static property — Risk: **High**
- [ ] `HKStateOfMind(date:kind:valence:labels:associations:)` is the correct initializer — Risk: **High**
- [ ] `.stateOfMind(predicate)` is a valid HKSamplePredicate factory — Risk: **High**
- [ ] `store.save(sample)` works with async/await for HKStateOfMind — Risk: **Medium**
- [ ] Authorization dialog at onboarding — **Incorrect**: no onboarding HK auth exists — Risk: N/A (factual error)
- [ ] Valence reverse-mapping formula `round((valence + 1.0) * 2.0)` produces correct values — Risk: **Low** (verified: -1→0, -0.5→1, 0→2, 0.5→3, 1→4 ✓)

---

## Questions for Clarification

1. Should the Health prefill attempt authorization on the Home tab (new prompt) or wait until user visits another tab (delayed sync)?
2. For the C1 fix: is Option A (separate suggestion parameter) or Option B (guarded onChange + binding flag) preferred? Option A is cleaner but changes MoodCheckInCard's interface more.
3. Should the NSHealthUpdateUsageDescription be updated now or deferred to a separate chore?

---

## Recommendations

1. **Fix C1 first** — the onChange race condition makes the entire prefill feature non-functional. Recommend Option A (suggestion parameter).
2. **Add authorization step** — either lazy (in prefill method) or eager (in `.onAppear`). Lazy is simpler and consistent with the "thin integration" goal.
3. **Add API discovery step** — 15 minutes in Xcode playground or test target to verify HKStateOfMind API surface before committing to specific code.
4. **Update usage strings** — easy win that prevents App Store friction.
5. After these revisions, the plan is ready for checklist.
