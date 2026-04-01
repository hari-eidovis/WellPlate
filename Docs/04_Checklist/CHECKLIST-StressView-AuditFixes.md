# Checklist: Stress View Audit Fixes

**Source**: [screentime-stress-view-audit.md](file:///Users/hariom/Desktop/WellPlate/Docs/05_Audits/Code/screentime-stress-view-audit.md)
**Date**: 2026-02-21

---

## BUG-1 · Screen Time 0h treated as "no entry"

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift)

**Problem**: `UserDefaults.double(forKey:)` returns `0.0` for both "key missing" and "user saved 0". The `stored > 0` check conflates the two.

- [x] **Step 1.1** · In `init`, use `object(forKey:)` to detect presence:
  ```swift
  if UserDefaults.standard.object(forKey: key) != nil {
      self.screenTimeHours = UserDefaults.standard.double(forKey: key)
  }
  ```
- [x] **Step 1.2** · In `refreshScreenTimeFactor()`, same pattern:
  ```swift
  let hasEntry = UserDefaults.standard.object(forKey: key) != nil
  let stored = UserDefaults.standard.double(forKey: key)
  let score = computeScreenTimeScore(hours: hasEntry ? stored : nil)
  ```
- [x] **Step 1.3** · In `computeScreenTimeScore`, allow `hours == 0` as valid:
  ```swift
  guard let h = hours else { return 12.5 }
  // remove the `h > 0` check — 0h is a valid input scoring 2 pts
  ```

---

## BUG-2 · Gauge arc doesn't animate on first appear

**File**: [StressScoreGaugeView.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/Views/StressScoreGaugeView.swift)

**Problem**: `onAppear` sets `animatedProgress` without `withAnimation`, so the arc jumps.

- [x] **Step 2.1** · Wrap in delayed animation for a satisfying fill-up:
  ```swift
  .onAppear {
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
          animatedProgress = score / 100.0
      }
  }
  ```

---

## IMP-1 · DateFormatter missing POSIX locale

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift)

**Problem**: Without `en_US_POSIX` locale, `"yyyy-MM-dd"` can produce unexpected output on non-Gregorian calendars.

- [x] **Step 3.1** · Add locale to the static formatter:
  ```swift
  private static let dayFormatter: DateFormatter = {
      let f = DateFormatter()
      f.dateFormat = "yyyy-MM-dd"
      f.locale = Locale(identifier: "en_US_POSIX")
      return f
  }()
  ```

---

## IMP-2 · Non-tappable cards wrapped in Button

**File**: [StressFactorCardView.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/Views/StressFactorCardView.swift)

**Problem**: Exercise/Sleep/Diet cards have no `onTap` but are still wrapped in a `Button`, swallowing taps silently.

- [x] **Step 4.1** · Conditionally wrap in Button only if `onTap` is provided:
  ```swift
  var body: some View {
      if let onTap {
          Button(action: onTap) { cardContent }
              .buttonStyle(.plain)
      } else {
          cardContent
      }
  }

  private var cardContent: some View {
      VStack(alignment: .leading, spacing: 10) {
          // ... existing card layout moved here ...
      }
      .padding(14)
      .background(cardBackground)
  }
  ```

---

## IMP-3 · Diet predicate uses `>=` instead of `==`

**File**: [StressViewModel.swift](file:///Users/hariom/Desktop/WellPlate/WellPlate/Features%20+%20UI/Stress/ViewModels/StressViewModel.swift)

**Problem**: `entry.day >= today` could include future-dated entries. Spec says `==`.

- [ ] **Step 5.1** · Change to exact equality:
  ```swift
  predicate: #Predicate<FoodLogEntry> { entry in
      entry.day == today
  }
  ```

---

## Verification

- [ ] Build succeeds without warnings
- [ ] Set screen time to 0h → card shows "0.0 hours today", score = 2
- [ ] Relaunch app same day → 0h persists correctly
- [ ] Gauge arc animates smoothly on first load
- [ ] Exercise/Sleep/Diet cards are not tappable (no button highlight)
- [ ] Screen Time card remains tappable and opens sheet
- [ ] Diet score unaffected by pre-logged future entries
