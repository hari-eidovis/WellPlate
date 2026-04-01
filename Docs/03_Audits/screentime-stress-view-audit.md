# Audit Report: Stress View — ScreenTime API Integration Plan

**Spec audited**: [260221-stress-view.md](file:///Users/hariom/Desktop/WellPlate/Docs/02_Planning/Specs/260221-stress-view.md)
**Date**: 2026-02-21
**Status**: Implementation complete — 7 issues found (2 bugs, 3 improvements, 2 observations)

---

## Executive Summary

The stress view feature is **fully implemented and integrated**. All 7 files from the spec exist, the `StressPlaceholderView` has been deleted, and `MainTabView` correctly injects the ViewModel. The scoring algorithms, data flow, and UI closely follow the spec. However, the audit uncovered **2 bugs**, **3 recommended improvements**, and **2 observations** about the ScreenTime API roadmap.

---

## Spec vs. Implementation Compliance Matrix

| Spec Item                                     | Status | Notes                                                           |
| --------------------------------------------- | ------ | --------------------------------------------------------------- |
| `StressModels.swift` — `StressLevel` enum     | ✅      | All 5 levels, colors, labels, encouragement text                |
| `StressModels.swift` — `StressFactorResult`   | ✅      | Includes `.neutral()` factory, `progress` computed prop         |
| `StressViewModel.swift` — MVVM + `@MainActor` | ✅      | Matches `SleepViewModel` pattern                                |
| Exercise scoring algorithm                    | ✅      | Steps/10k + energy/600, average if both available               |
| Sleep scoring algorithm                       | ✅      | Piecewise linear + deep sleep penalty, guarded `totalHours > 0` |
| Diet scoring algorithm                        | ✅      | Protein/fiber balance vs. fat/carb excess                       |
| Screen Time scoring algorithm                 | ✅      | Piecewise thresholds 0→25                                       |
| Screen Time persistence (`UserDefaults`)      | ⚠️ Bug  | See **BUG-1** below                                             |
| `StressScoreGaugeView` — 270° arc             | ✅      | Animated, color-interpolated, spring animation                  |
| `StressFactorCardView` — reusable card        | ✅      | Icon + progress bar + status/detail text                        |
| `ScreenTimeInputSheet` — slider + quick picks | ✅      | 0–12h, step 0.5, pills for 1/2/3/4/6h                           |
| `StressView` — state machine                  | ✅      | unavailable → loading → permission → mainContent                |
| `StressView` — insights card                  | ✅      | Top 2 stressors with tips                                       |
| `MainTabView` — integration                   | ✅      | Placeholder deleted, VM injected with `modelContext`            |
| Dark/light mode                               | ✅      | Uses system colors throughout                                   |

---

## 🐛 Bugs

### BUG-1: Screen Time of 0 hours is never persisted / read back correctly

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift)
**Lines**: 64–68, 296–299

`UserDefaults.double(forKey:)` returns `0.0` for **both** "key doesn't exist" and "user explicitly saved 0 hours". The init and `refreshScreenTimeFactor` both check `stored > 0` to decide if an entry exists:

```swift
// init (line 66)
if stored > 0 { self.screenTimeHours = stored }

// refreshScreenTimeFactor (line 298)
let hasEntry = stored > 0
```

If a user sets screen time to **0 hours** (via the slider at minimum), on next app launch:
- `screenTimeHours` stays at the default `0` (appears correct by coincidence)
- But `hasEntry` is `false`, so the card shows "Tap to enter" / "No entry for today" instead of "0.0 hours today"
- Score falls back to **12.5** (neutral) instead of **2** (the correct score for 0h)

**Fix**: Use `UserDefaults.object(forKey:) != nil` to detect presence, or store a sentinel value.

---

### BUG-2: `StressScoreGaugeView` animation skipped on first appearance

**File**: [StressScoreGaugeView.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/Views/StressScoreGaugeView.swift)
**Lines**: 60–66

```swift
.onAppear { animatedProgress = score / 100.0 }      // no animation
.onChange(of: score) { _, newValue in
    withAnimation(.spring(...)) { animatedProgress = newValue / 100.0 }
}
```

The `onAppear` sets the progress **without** `withAnimation`, so the arc "jumps" to its value on first render. The spring animation only fires on subsequent `score` changes.

**Fix**: Wrap `onAppear` body in `withAnimation(.spring(...))` for a satisfying fill-up animation on load.

---

## ⚡ Recommended Improvements

### IMP-1: `DateFormatter` locale safety

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift#L51-L55)

The `dayFormatter` used for `UserDefaults` keys does not set `.locale = Locale(identifier: "en_US_POSIX")`. On some locales (e.g. Saudi Arabia with Hijri calendar), `"yyyy-MM-dd"` output can differ, causing keys to mismatch across system locale changes.

```diff
 private static let dayFormatter: DateFormatter = {
     let f = DateFormatter()
     f.dateFormat = "yyyy-MM-dd"
+    f.locale = Locale(identifier: "en_US_POSIX")
     return f
 }()
```

---

### IMP-2: `StressFactorCardView` tappable even without `onTap`

**File**: [StressFactorCardView.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/Views/StressFactorCardView.swift#L15-L17)

The entire card is wrapped in a `Button` that calls `onTap?()`. When `onTap` is `nil` (Exercise, Sleep, Diet cards), the button still absorbs touch events and does nothing — the user gets no visual feedback because `.plainButtonStyle` is used, but the tap gesture is consumed. Consider:

```diff
- Button {
-     onTap?()
- } label: {
+ Group {
+     if let onTap {
+         Button(action: onTap) { cardContent }
+             .buttonStyle(.plain)
+     } else {
+         cardContent
+     }
+ }
```

Or simply disable the button: `.disabled(onTap == nil)`

---

### IMP-3: Diet predicate may miss entries logged before `startOfDay`

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift#L128-L133)

The predicate uses `entry.day >= today` where `today = startOfDay(for: Date())`. Since `FoodLogEntry.day` is stored as `startOfDay(date)`, this uses `>=` which will also include **future** entries if any exist (e.g. pre-logged meals for tomorrow). It should be exact equality:

```diff
- predicate: #Predicate<FoodLogEntry> { entry in
-     entry.day >= today
+ predicate: #Predicate<FoodLogEntry> { entry in
+     entry.day == today
  }
```

> [!NOTE]
> The spec explicitly says `day == startOfDay(for: Date())` (line 215). The implementation drifted to `>=`.

---

## 📋 Observations (ScreenTime API Roadmap)

### OBS-1: No `DeviceActivity` framework integration yet — by design

The spec explicitly notes this is **MVP** with manual input. The roadmap for Phase 2 mentions:
- `com.apple.developer.family-controls` entitlement
- `DeviceActivity.DeviceActivityReport` for automated phone usage
- Replace `UserDefaults` with live SDK data

Currently no entitlements, no `DeviceActivity` imports, and the `ScreenTimeInputSheet.swift` has a footer saying "DeviceActivity integration coming soon" (line 109). **This is intentional and correct for MVP.**

> [!IMPORTANT]
> When implementing `DeviceActivity` in Phase 2, note that:
> 1. The Family Controls entitlement requires a **special Apple capability request** (not just toggling in Xcode)
> 2. `DeviceActivityReport` only works in an **App Extension**, not the main app target
> 3. The Screen Time API does **not** provide raw hour counts — it provides category-grouped usage that needs parsing
> 4. This API requires **iOS 16+** and physical device testing (no Simulator support)

---

### OBS-2: No unit tests exist for scoring logic

The project has **zero test files**. The scoring algorithms (exercise, sleep, diet, screen time) are pure functions that would be trivially testable. This is especially important because:
- The sleep scoring uses a complex 6-segment piecewise linear function
- The diet scoring has a non-obvious net balance formula with cross-terms
- Edge cases (exactly 0h, exactly 10000 steps, boundary transitions) need verification

**Recommendation**: Add a `StressViewModelTests.swift` testing the `compute*Score` methods directly. These are private, so either make them `internal` for `@testable import` or extract them to a standalone `StressScoring` module.

---

## Summary of Actions Required

| #     | Type          | Severity | Summary                                    | Fix effort |
| ----- | ------------- | -------- | ------------------------------------------ | ---------- |
| BUG-1 | 🐛 Bug         | Medium   | 0h screen time treated as "no entry"       | ~5 min     |
| BUG-2 | 🐛 Bug         | Low      | Gauge arc doesn't animate on first appear  | ~2 min     |
| IMP-1 | ⚡ Improvement | Low      | DateFormatter missing POSIX locale         | ~1 min     |
| IMP-2 | ⚡ Improvement | Low      | Non-tappable cards still wrapped in Button | ~5 min     |
| IMP-3 | ⚡ Improvement | Medium   | Diet predicate `>=` should be `==`         | ~1 min     |
| OBS-1 | 📋 Observation | —        | DeviceActivity requires Phase 2 work       | Future     |
| OBS-2 | 📋 Observation | —        | No unit tests for scoring logic            | Future     |
