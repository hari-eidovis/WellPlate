# Checklist Audit Report: Wellness Report Export

**Audit Date**: 2026-04-02
**Checklist Audited**: `Docs/04_Checklist/260402-wellness-report-export-checklist.md`
**Source Plan**: `Docs/02_Planning/Specs/260402-wellness-report-export-plan-RESOLVED.md`
**Auditor**: audit agent
**Verdict**: APPROVED WITH WARNINGS

---

## Executive Summary

The checklist is well-structured, covers all plan phases, and correctly carries forward all audit-resolved fixes (correct `UserGoals` field names, URL-based `ShareLink`, `scaleEffect` + `frame` fix, outermost `.sheet` placement). Two issues require fixing before implementation: the `Services/` subdirectory does not exist and the checklist does not tell the implementer to create it; and both temp file write steps set the URL unconditionally even when `try?` silently fails, which would surface a broken share button. Both are straightforward to fix in a RESOLVED checklist.

---

## Coverage Check

| Plan Step | Checklist Item | Covered? |
|-----------|---------------|----------|
| Step 1 — `WellnessReportData` struct | Phase 1.1 | ✅ |
| Step 2 — `@Query` additions + `weekReportData` | Phases 1.2, 1.3 | ✅ |
| Step 3 — `WellnessReportView` | Phase 2.1 | ✅ |
| Step 4 — `WellnessReportGenerator` (renderImage + generateCSV) | Phase 3.1 | ✅ |
| Step 5 — `WellnessReportShareSheet` (H1/H2 URL fix) | Phases 4.1–4.5 | ✅ |
| Step 6 — `.sheet` wired in `ProgressInsightsView` | Phase 5.1 | ✅ |
| Build all 4 targets | Post-Implementation | ✅ |
| Manual verification (6 flows) | Post-Implementation | ✅ |
| Git commit | Post-Implementation | ✅ |

---

## Issues Found

### CRITICAL
None.

### HIGH

#### H1: `Services/` subdirectory does not exist — Pre-Implementation verify will fail and implementer has no instruction to create it

- **Location**: Pre-Implementation, item 3: "Confirm `WellPlate/Features + UI/Progress/Services/` directory exists"
- **Problem**: Verified against the filesystem — `WellPlate/Features + UI/Progress/` contains only a `Views/` subdirectory. `Services/` does not exist. The verify step instructs `ls "WellPlate/Features + UI/Progress/Services/"` and expects "at least one existing file" — this will error with "No such file or directory", and the implementer has no instruction to create the directory. Without explicit guidance, an implementer unfamiliar with the project may put the new file in the wrong location or be blocked entirely.
- **Impact**: Implementer blocked or creates file in wrong directory.
- **Recommendation**: Replace the verify step with an action step: "Create the `Services/` subdirectory: `mkdir -p 'WellPlate/Features + UI/Progress/Services'`". Since the project uses `PBXFileSystemSynchronizedRootGroup`, any `.swift` file placed there is auto-included in the build — no pbxproj edit needed. Verify: `ls "WellPlate/Features + UI/Progress/Services/"` returns an empty listing (or lists the newly created generator file after step 1.1).

#### H2: `imageURL` and `csvURL` set unconditionally after `try?` write — broken share button on write failure

- **Location**: Phase 4.4, `.task` block instructions:
  > "If image non-nil: call `.jpegData(compressionQuality: 0.88)` → `try? data.write(to: url)` where `url = ...`
  > Set `imageURL = url`"
  > (and similarly for CSV)
- **Problem**: Both the image write and CSV write use `try?`, which silently discards write errors. In both cases the checklist then says to "Set `imageURL = url`" / "Set `csvURL = csvFileURL`" as unconditional next steps. If the write fails (disk full, permissions issue, etc.), the URL is still assigned — pointing to a file that was never written. The share button will appear but tapping it will present an empty or nonexistent file to the iOS share sheet.
- **Impact**: Silent data corruption in the share flow — user sees "Share as Image" / "Export as CSV" buttons but shares nothing. Hard to diagnose because there is no error UI.
- **Recommendation**: Condition the URL assignment on write success. For the image:
  ```swift
  if let uiImage = await WellnessReportGenerator.renderImage(data: reportData),
     let jpegData = uiImage.jpegData(compressionQuality: 0.88) {
      let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("WellPlate_Weekly_Report.jpg")
      if (try? jpegData.write(to: url)) != nil {
          imageURL = url
      }
  }
  ```
  For CSV (note: `Data.write(to:)` returns `Void` — `try?` on it returns `Void?` where non-nil = success):
  ```swift
  let csvFileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("WellPlate_Weekly_Data.csv")
  if (try? csvData.write(to: csvFileURL)) != nil {
      csvURL = csvFileURL
  }
  ```
  This keeps `imageURL` / `csvURL` as `nil` on failure, which correctly hides the corresponding button.

---

### MEDIUM

#### M1: Step 3.1 never instructs adding `import SwiftUI` to `WellnessReportGenerator.swift`

- **Location**: Phase 3.1, opening instruction: "In `WellnessReportGenerator.swift` (the file created in 1.1), below the `WellnessReportData` struct, add `@MainActor struct WellnessReportGenerator { ... }`"
- **Problem**: Step 1.1's verify notes "no `import` needed for this struct (pure Swift value types only)" — which is correct for `WellnessReportData` alone. But when step 3.1 adds `WellnessReportGenerator` to the same file, the file now needs `import SwiftUI` for `ImageRenderer`, `Image`, and `@MainActor` (UIKit bridging). Without the import, the file will not compile. The checklist never explicitly tells the implementer to add `import SwiftUI`.
- **Impact**: Build failure at phase 3 unless implementer infers the missing import.
- **Recommendation**: Add as the first bullet in Phase 3.1: "Add `import SwiftUI` at the top of `WellnessReportGenerator.swift` (above the `WellnessReportData` struct)." Alternatively update step 1.1 to already include `import SwiftUI` when creating the file, since `WellnessReportGenerator` will always follow in the same file.

---

### LOW

#### L1: Verify example for empty-day CSV row has an extra comma

- **Location**: Phase 3.1, generateCSV verify step: `"2026-03-26,,,0,0.0,0.0,0.0,0,0,"`
- **Problem**: The CSV header is `date,stress_score,calories,protein_g,carbs_g,fat_g,steps,water_glasses,mood` (9 columns). A day with no stress and no food should produce: `"2026-03-26,,0,0.0,0.0,0.0,0,0,"` (stress blank, calories 0, etc.) — 9 fields. The example has `"2026-03-26,,,0,..."` which has 10 fields (extra comma between date and stress), suggesting an off-by-one in the example.
- **Impact**: Purely a documentation inaccuracy in the verify description — does not affect implementation. The code itself will produce the correct 9-column output.
- **Recommendation**: Update the verify example to: `"2026-03-26,,0,0.0,0.0,0.0,0,0,"` (stress column blank, then zero values).

#### L2: Modifier attachment sequence for `.task` / `.onDisappear` / `.presentationDetents` not specified relative to each other

- **Location**: Phases 4.1, 4.4, 4.5 — `.presentationDetents([.large])` is in 4.1, `.task` in 4.4, `.onDisappear` in 4.5
- **Problem**: The checklist doesn't specify the order of these three modifiers relative to each other on the `NavigationStack`. In SwiftUI the order of these modifiers doesn't affect behaviour, but an implementer may wonder whether `.task` should come before or after `.presentationDetents`.
- **Impact**: Zero functional impact — all three can be in any order. Clarity only.
- **Recommendation**: Add a note in 4.4: "Modifier order relative to `.presentationDetents` does not matter; place `.task` and `.onDisappear` after `.presentationDetents` for readability."

---

## Verification of Key Assumptions

- [x] `ProgressInsightsView.swift` at correct path — **confirmed**
- [x] `@State private var showShareSheet = false` at line 21 — **confirmed**
- [x] Share button sets `showShareSheet = true` at line 188 — **confirmed**
- [x] `.background(StatusBarStyleModifier())` is the last modifier on the body (line 237) — **confirmed**
- [x] `WellnessDayLog.waterGlasses`, `.steps`, `.moodRaw`, `.mood`, `.day` — all exist — **confirmed**
- [x] `StressReading.day` computed property exists — **confirmed**
- [x] `MoodOption.emoji` property exists — **confirmed**
- [x] `UserGoals.calorieGoal` and `.waterDailyCups` used (not `dailyCalorieGoal` / `dailyCups`) — **confirmed in checklist** (step 1.3 explicit callout)
- [x] `Color(hex:)` extension available module-wide — **confirmed** (defined in `ByoSyncCustomProgressView.swift`)
- [x] `AppColors.textPrimary`, `.textSecondary`, `.brand` exist — **confirmed**
- [x] `ShareLink(item: URL)` approach (H1/H2 fix) carried through correctly in steps 4.3–4.4 — **confirmed**
- [x] `.frame(width: 390 * scale, height: 340 * scale)` after `.scaleEffect()` (M1 fix) present in step 4.2 — **confirmed**
- [x] `WellPlate/Features + UI/Progress/Services/` directory exists — **NOT CONFIRMED** — directory does not exist ← **H1**
- [x] `import SwiftUI` added to `WellnessReportGenerator.swift` before generator struct — **NOT CONFIRMED** — no checklist step adds this import ← **M1**

---

## Missing Elements

None beyond the issues listed above. All plan phases, 4 build targets, manual test flows (including edge cases), and git steps are covered.

---

## Recommendations

1. **(Blocking)** Fix H1: Replace Pre-Implementation item 3 with an action step to `mkdir -p` the `Services/` directory
2. **(Blocking)** Fix H2: Condition `imageURL = url` and `csvURL = csvFileURL` on successful `try?` write (check `!= nil`)
3. Fix M1: Add "Add `import SwiftUI` at the top of `WellnessReportGenerator.swift`" as the first item in Phase 3.1 (or update step 1.1 to include the import when the file is first created)
4. Fix L1: Correct the CSV row example to `"2026-03-26,,0,0.0,0.0,0.0,0,0,"` (9 columns)
5. Proceed to RESOLVE then IMPLEMENT — no architectural gaps found
