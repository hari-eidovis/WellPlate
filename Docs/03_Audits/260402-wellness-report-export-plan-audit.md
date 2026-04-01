# Plan Audit Report: Wellness Report Export

**Audit Date**: 2026-04-02
**Plan Audited**: `Docs/02_Planning/Specs/260402-wellness-report-export-plan.md`
**Auditor**: audit agent
**Verdict**: NEEDS REVISION

---

## Executive Summary

The plan is well-structured and the architecture is sound, but it contains two compile-breaking field name mismatches against the real `UserGoals` model, and two ShareLink usages with incorrect `Transferable` types (`SwiftUI.Image` and raw `Data`) that will either fail to compile or produce broken share behaviour at runtime. These must be resolved before implementation. Two additional medium-severity issues affect preview layout correctness and sheet placement precision.

---

## Issues Found

### CRITICAL (Must Fix Before Proceeding)

#### C1: `UserGoals` field names are wrong — will not compile

- **Location**: Step 2, `weekReportData` computed property, lines:
  ```swift
  waterGoal: goals.dailyCups,
  calorieGoal: goals.dailyCalorieGoal,
  ```
- **Problem**: Neither `dailyCups` nor `dailyCalorieGoal` exist on `UserGoals`. The actual field names (verified against `WellPlate/Models/UserGoals.swift`) are:
  - `waterDailyCups` (not `dailyCups`)
  - `calorieGoal` (not `dailyCalorieGoal` — this conflicts with the `WellnessReportData` parameter name but the struct field in `UserGoals` is literally `calorieGoal`)
- **Impact**: Build failure in Step 2. Nothing can be tested until fixed.
- **Recommendation**: Replace both references:
  ```swift
  waterGoal: goals.waterDailyCups,
  calorieGoal: goals.calorieGoal,
  ```

---

### HIGH (Should Fix Before Proceeding)

#### H1: `ShareLink(item: Image(uiImage:))` — `SwiftUI.Image` does not conform to `Transferable`

- **Location**: Step 5 (`WellnessReportShareSheet.swift`), the "Share as Image" button:
  ```swift
  ShareLink(
      item: Image(uiImage: image),
      preview: SharePreview("WellPlate Weekly Report", image: Image(uiImage: image))
  )
  ```
- **Problem**: `SwiftUI.Image` does NOT conform to the `Transferable` protocol. This will produce a compile error: *"Type 'Image' does not conform to protocol 'Transferable'"*. `UIImage` also does not conform to `Transferable` natively.
- **Impact**: The "Share as Image" button will fail to compile.
- **Recommendation**: Write the JPEG data to a temp file and share the URL. Replace the ShareLink with:
  ```swift
  if let image = renderedImage,
     let jpegData = image.jpegData(compressionQuality: 0.88) {
      let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("WellPlate_Weekly_Report.jpg")
      try? jpegData.write(to: url)
      ShareLink(
          item: url,
          preview: SharePreview(
              "WellPlate Weekly Report",
              image: Image(uiImage: image)
          )
      ) {
          Label("Share as Image", systemImage: "photo")
              ...
      }
  }
  ```
  The `@State var renderedImageURL: URL?` replaces `@State var renderedImage: UIImage?`.

#### H2: `ShareLink(item: csvData)` where `csvData: Data` — wrong Transferable type for file sharing

- **Location**: Step 5 (`WellnessReportShareSheet.swift`), the "Export as CSV" button:
  ```swift
  ShareLink(
      item: csvData,
      preview: SharePreview("WellPlate Weekly Data.csv")
  )
  ```
- **Problem**: While `Data` technically conforms to `Transferable` on iOS 16+, the share target receives raw bytes with no file name or UTI hint. Recipients won't know the data is a CSV — it will appear as generic binary data, not a `.csv` file with correct MIME type.
- **Impact**: CSV shares as unnamed binary data. Files app and other targets won't open it as a spreadsheet.
- **Recommendation**: Write to a temp URL with `.csv` extension and share the URL:
  ```swift
  let csvURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("WellPlate_Weekly_Data.csv")
  try? csvData.write(to: csvURL)
  ShareLink(item: csvURL, preview: SharePreview("WellPlate Weekly Data.csv")) { ... }
  ```
  The `@State var csvFileURL: URL?` replaces `@State var csvData: Data`. Both temp URLs can be written in the `.task` block. **Store as `@State var csvURL: URL?`** (nil-guarded like the image URL).

---

### MEDIUM (Fix During Implementation)

#### M1: `.scaleEffect()` without compensating `.frame()` — preview layout broken on non-390pt devices

- **Location**: Step 5 (`WellnessReportShareSheet.swift`), preview section:
  ```swift
  WellnessReportView(data: reportData)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .appShadow(radius: 16, y: 6)
      .padding(.horizontal, 20)
      .scaleEffect(UIScreen.main.bounds.width / 390)
      .frame(height: previewHeight)
  ```
- **Problem**: `.scaleEffect()` in SwiftUI is a visual-only transform — it does NOT change the view's layout size. The 390pt card is still 390pt from the layout system's perspective, overflowing its container on devices narrower than 430pt (iPhone SE, iPhone 15 base). The `.frame(height: previewHeight)` only fixes the height; horizontal overflow remains.
- **Impact**: Card clips or overflows horizontally on smaller-screen devices.
- **Recommendation**: Apply a proper scale-to-fit approach. Replace the block with:
  ```swift
  let screenW = UIScreen.main.bounds.width - 40
  let scale = screenW / 390
  WellnessReportView(data: reportData)
      .scaleEffect(scale, anchor: .top)
      .frame(width: 390 * scale, height: 340 * scale)  // constrain layout size
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .appShadow(radius: 16, y: 6)
  ```
  Alternatively, embed in a `GeometryReader` and calculate `scale` from `geometry.size.width`.

#### M2: `.sheet` placement instruction is ambiguous — should be outermost modifier

- **Location**: Step 6, placement instruction: "after the existing `.preferredColorScheme(colorScheme)` modifier (around line 235)"
- **Problem**: `.preferredColorScheme(colorScheme)` (line 235) is followed by `.background(StatusBarStyleModifier())` (line 237). Inserting `.sheet` between them would work syntactically, but is stylistically incorrect — `.sheet` should be the outermost modifier in the chain, after all visual modifiers, to ensure proper presentation context.
- **Impact**: Functionally works either way, but inserting between visual modifiers is confusing. If `.background(StatusBarStyleModifier())` modifies the sheet-host view, it may interfere with the sheet presentation on some iOS versions.
- **Recommendation**: Update the instruction to: "after `.background(StatusBarStyleModifier())` — make it the last modifier on the body, after all visual modifiers."

---

### LOW

#### L1: `weekReportData` recomputed on every render — consider lazy evaluation

- **Location**: Step 2, `weekReportData` as a plain computed property
- **Problem**: `weekReportData` iterates all food/stress/wellness logs, builds dictionaries, and formats strings on every SwiftUI render pass. While the 7-day window is small, any `@Query` data change (including unrelated ones) will recompute this.
- **Impact**: Negligible on current data volumes. Low risk but worth noting.
- **Recommendation**: No change needed for MVP. If performance becomes an issue, compute once in the `.task` of `WellnessReportShareSheet` and pass the result in.

#### L2: No cleanup of temp URLs after share sheet dismissal

- **Location**: Step 5, `.task` block writing to `FileManager.default.temporaryDirectory`
- **Problem**: The temp image and CSV files written to `temporaryDirectory` are never deleted. iOS will eventually clean them up, but a user who opens and dismisses the share sheet repeatedly accumulates stale files.
- **Impact**: Very low — iOS temp directory is not user-visible and is OS-managed.
- **Recommendation**: Add `.onDisappear { try? FileManager.default.removeItem(at: url) }` in `WellnessReportShareSheet` if desired. Not blocking for MVP.

---

## Verification of Key Assumptions

- [x] `ProgressInsightsView` has `@State private var showShareSheet = false` at line 21 — **confirmed**
- [x] Share button at line 188 sets `showShareSheet = true` — **confirmed**
- [x] `ProgressInsightsView` has a custom `init()` — adding plain `@Query` properties for `StressReading` and `WellnessDayLog` without init-body initialization is valid Swift — **confirmed** (property wrapper defaults apply; custom init only overrides `_allFoodLogs`)
- [x] `WellnessDayLog.day`, `.waterGlasses`, `.steps`, `.moodRaw`, `.mood` all exist — **confirmed** (verified `WellnessDayLog.swift`)
- [x] `StressReading.day` computed property exists — **confirmed** (line 46, `StressReading.swift`)
- [x] `MoodOption.emoji` property exists — **confirmed** (`MoodCheckInCard.swift` lines 10-18)
- [x] `AppColors.textPrimary`, `.textSecondary`, `.brand` exist — **confirmed** (`AppColor.swift`)
- [x] `Color(hex:)` extension available module-wide — **confirmed** (defined in `ByoSyncCustomProgressView.swift` as a global `extension Color`)
- [x] `UserGoals.calorieGoal` field name — **confirmed** (NOT `dailyCalorieGoal`)
- [x] `UserGoals.waterDailyCups` field name — **confirmed** (NOT `dailyCups`)
- [ ] `ShareLink(item: Image(uiImage:))` compiles — **NOT CONFIRMED** — `SwiftUI.Image` does not conform to `Transferable` ← **C1 in H1**
- [ ] `ShareLink(item: csvData: Data)` produces a named CSV file — **NOT CONFIRMED** — raw `Data` loses filename/type ← **H2**

---

## Missing Elements

- [ ] Temp URL cleanup (LOW — see L2)
- [ ] Mock mode: plan doesn't mention mock mode data for the share sheet. Acceptable since the sheet reads from existing `@Query`-backed arrays which respect mock-mode data.

---

## Recommendations

1. **(Blocking)** Fix C1: Change `goals.dailyCups` → `goals.waterDailyCups` and `goals.dailyCalorieGoal` → `goals.calorieGoal` in Step 2's `weekReportData` property
2. **(Blocking)** Fix H1: Replace `ShareLink(item: Image(uiImage:))` with `ShareLink(item: tempJPEGURL)` pattern — write JPEG to `FileManager.default.temporaryDirectory` in `.task` block
3. **(Blocking)** Fix H2: Replace `ShareLink(item: csvData: Data)` with `ShareLink(item: tempCSVURL)` — write CSV bytes to a `.csv`-named temp file in `.task` block; update `@State` to hold `URL?` instead of `Data`
4. Fix M1: Add explicit `.frame(width: 390 * scale, height: 340 * scale)` after `.scaleEffect()` to constrain layout size on narrow devices
5. Fix M2: Move `.sheet` placement instruction to after `.background(StatusBarStyleModifier())` (last modifier in chain)
6. Proceed to RESOLVE then CHECKLIST — no architectural blockers, only API-usage corrections needed
