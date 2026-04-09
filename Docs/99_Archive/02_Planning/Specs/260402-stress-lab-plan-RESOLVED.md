# Implementation Plan: Stress Lab (n-of-1 Experiments) — RESOLVED

**Date**: 2026-04-02
**Strategy**: `Docs/02_Planning/Specs/260402-stress-lab-strategy.md`
**Audit**: `Docs/03_Audits/260402-stress-lab-plan-audit.md`
**Status**: Audit-Resolved — Ready for Checklist

---

## Audit Resolution Summary

| Issue | Severity | Resolution |
|-------|----------|------------|
| C1 — 3rd `.sheet()` added to `StressView`, violates CLAUDE.md | CRITICAL | Fixed: add `.stressLab` to `StressSheet` enum; present via existing `activeSheet` mechanism; removed `showStressLab` Bool and new `.sheet()` modifier |
| H1 — `StressLabView` has two `.sheet()` calls internally | HIGH | Fixed: introduce `StressLabSheet` enum with `.create` / `.result(StressExperiment)` cases; single `.sheet(item: $activeSheet)` |
| M1 — `@Query allReadings` has no predicate, fetches entire table | MEDIUM | Fixed: add `init()` with 30-day `#Predicate` filter |
| L2 — Cache writes not saved to modelContext | LOW | Fixed: inject `@Environment(\.modelContext)` in `StressLabResultView`; call `try? modelContext.save()` after caching |
| L3 — `randomElement()!` force-unwrap in bootstrap | LOW | Fixed: replaced with `randomElement() ?? 0` |
| L1 — `flask.fill` SF Symbol availability | LOW | Acknowledged — iOS 16+ symbol, no issue on iOS 26 target |

---

## Overview

Add a Stress Lab feature where users run structured 7- or 14-day micro-intervention experiments (e.g. "No caffeine after 2pm") and see an honest before/after stress score comparison with a bootstrap confidence interval. Entry is via a new "Lab" toolbar button in `StressView`. Results are computed on-device from existing `StressReading` SwiftData records — no new data collection needed.

---

## Requirements

- User can create an experiment: name, optional hypothesis, intervention type, 7 or 14-day duration
- Active experiment shows a countdown card ("Day 3 of 7")
- On completion, result card shows: baseline avg, experiment avg, delta, confidence band, and plain-language summary
- Only one active experiment at a time
- Minimum data guard: at least 3 days with readings in both baseline and experiment windows
- Strictly non-causal language throughout
- New `StressExperiment` SwiftData model — additive migration, no existing data touched
- No new tabs, no new top-level navigation routes
- No new `.sheet()` modifiers on `StressView` — use existing `StressSheet` enum pattern

---

## Architecture Changes

- `WellPlate/App/WellPlateApp.swift` — add `StressExperiment.self` to `modelContainer` schema
- `WellPlate/Models/StressExperiment.swift` *(new)* — `@Model` class + `InterventionType` enum
- `WellPlate/Features + UI/Stress/Views/StressView.swift` — add `.stressLab` to `StressSheet`; add "Lab" toolbar button setting `activeSheet = .stressLab`; handle `.stressLab` case in existing `.sheet(item: $activeSheet)` switch
- `WellPlate/Features + UI/Stress/Views/StressLabView.swift` *(new)* — main Lab screen with single `StressLabSheet` enum
- `WellPlate/Features + UI/Stress/Views/StressLabCreateView.swift` *(new)* — new experiment form sheet
- `WellPlate/Features + UI/Stress/Views/StressLabResultView.swift` *(new)* — result detail sheet
- `WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` *(new)* — pure analytics struct

---

## Implementation Steps

### Phase 1: Data Model

**Step 1 — Create `StressExperiment.swift`**
(`WellPlate/Models/StressExperiment.swift` — new file)

```swift
import Foundation
import SwiftData

enum InterventionType: String, CaseIterable, Identifiable {
    case caffeine     = "caffeine"
    case screenCurfew = "screenCurfew"
    case sleep        = "sleep"
    case exercise     = "exercise"
    case diet         = "diet"
    case custom       = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .caffeine:     return "Caffeine Cutoff"
        case .screenCurfew: return "Screen Curfew"
        case .sleep:        return "Sleep Schedule"
        case .exercise:     return "Exercise"
        case .diet:         return "Diet Change"
        case .custom:       return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .caffeine:     return "cup.and.saucer.fill"
        case .screenCurfew: return "iphone.slash"
        case .sleep:        return "moon.fill"
        case .exercise:     return "figure.run"
        case .diet:         return "leaf.fill"
        case .custom:       return "flask.fill"
        }
    }

    var suggestedHypothesis: String {
        switch self {
        case .caffeine:     return "Cutting caffeine after 2pm will lower my evening stress."
        case .screenCurfew: return "No screens after 10pm will reduce my stress the next morning."
        case .sleep:        return "Going to bed at a consistent time will lower my weekly stress."
        case .exercise:     return "Daily movement will bring my stress score down."
        case .diet:         return "Reducing processed food will improve my stress baseline."
        case .custom:       return ""
        }
    }
}

@Model
final class StressExperiment {
    var name: String
    var hypothesis: String?
    var interventionType: String   // InterventionType.rawValue
    var startDate: Date
    var durationDays: Int          // 7 or 14
    var cachedBaselineAvg: Double?
    var cachedExperimentAvg: Double?
    var cachedDelta: Double?
    var cachedCILow: Double?
    var cachedCIHigh: Double?
    var completedAt: Date?         // nil = in progress
    var createdAt: Date

    init(
        name: String,
        hypothesis: String? = nil,
        interventionType: String,
        startDate: Date,
        durationDays: Int
    ) {
        self.name = name
        self.hypothesis = hypothesis
        self.interventionType = interventionType
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.durationDays = durationDays
        self.createdAt = .now
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationDays, to: startDate) ?? startDate
    }

    var isComplete: Bool { Date() >= endDate }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    var daysElapsed: Int {
        min(durationDays, Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0)
    }

    var resolvedInterventionType: InterventionType {
        InterventionType(rawValue: interventionType) ?? .custom
    }
}
```

- **Dependencies**: None
- **Risk**: Low

---

**Step 2 — Register `StressExperiment` in `WellPlateApp.swift`**

Edit line 34 of `WellPlate/App/WellPlateApp.swift`:

From:
```swift
.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self])
```
To:
```swift
.modelContainer(for: [FoodCache.self, FoodLogEntry.self, WellnessDayLog.self, UserGoals.self, StressReading.self, StressExperiment.self])
```

- **Dependencies**: Step 1
- **Risk**: Low — additive SwiftData table

---

### Phase 2: Analytics Engine

**Step 3 — Create `StressLabAnalyzer.swift`**
(`WellPlate/Features + UI/Stress/Services/StressLabAnalyzer.swift` — new file)

<!-- RESOLVED: L3 — randomElement()! replaced with randomElement() ?? 0 throughout bootstrapCI -->

```swift
import Foundation

struct StressLabResult {
    let baselineAvg: Double
    let experimentAvg: Double
    let delta: Double
    let ciLow: Double
    let ciHigh: Double
    let baselineDayCount: Int
    let experimentDayCount: Int
}

struct StressLabAnalyzer {

    static let minimumDays = 3

    static func analyze(
        experiment: StressExperiment,
        allReadings: [StressReading]
    ) -> StressLabResult? {
        let cal = Calendar.current

        let baselineEnd   = experiment.startDate
        let baselineStart = cal.date(byAdding: .day, value: -7, to: baselineEnd) ?? baselineEnd
        let experimentEnd = min(experiment.endDate, cal.startOfDay(for: Date()))

        let baselineReadings   = allReadings.filter { $0.timestamp >= baselineStart && $0.timestamp < baselineEnd }
        let experimentReadings = allReadings.filter { $0.timestamp >= experiment.startDate && $0.timestamp < experimentEnd }

        let baselineDailyAvgs   = dailyAverages(from: baselineReadings)
        let experimentDailyAvgs = dailyAverages(from: experimentReadings)

        guard baselineDailyAvgs.count >= minimumDays,
              experimentDailyAvgs.count >= minimumDays else { return nil }

        let baselineAvg   = baselineDailyAvgs.reduce(0, +) / Double(baselineDailyAvgs.count)
        let experimentAvg = experimentDailyAvgs.reduce(0, +) / Double(experimentDailyAvgs.count)
        let delta         = experimentAvg - baselineAvg

        let (ciLow, ciHigh) = bootstrapCI(
            baseline: baselineDailyAvgs,
            experiment: experimentDailyAvgs,
            iterations: 1000
        )

        return StressLabResult(
            baselineAvg: baselineAvg,
            experimentAvg: experimentAvg,
            delta: delta,
            ciLow: ciLow,
            ciHigh: ciHigh,
            baselineDayCount: baselineDailyAvgs.count,
            experimentDayCount: experimentDailyAvgs.count
        )
    }

    private static func dailyAverages(from readings: [StressReading]) -> [Double] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.timestamp) }
        return grouped.values.map { day in
            day.map(\.score).reduce(0, +) / Double(day.count)
        }
    }

    private static func bootstrapCI(
        baseline: [Double],
        experiment: [Double],
        iterations: Int
    ) -> (low: Double, high: Double) {
        var deltas: [Double] = []
        deltas.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let bSample = (0..<baseline.count).map { _ in baseline.randomElement() ?? 0 }
            let eSample = (0..<experiment.count).map { _ in experiment.randomElement() ?? 0 }
            let bAvg = bSample.reduce(0, +) / Double(bSample.count)
            let eAvg = eSample.reduce(0, +) / Double(eSample.count)
            deltas.append(eAvg - bAvg)
        }

        deltas.sort()
        let lo = Int(Double(iterations) * 0.05)
        let hi = Int(Double(iterations) * 0.95)
        return (deltas[lo], deltas[hi])
    }
}
```

- **Dependencies**: Step 1
- **Risk**: Low

---

### Phase 3: UI — Lab Main Screen

**Step 4 — Create `StressLabView.swift`**
(`WellPlate/Features + UI/Stress/Views/StressLabView.swift` — new file)

<!-- RESOLVED: H1 — replaced two .sheet() calls with a single StressLabSheet enum + .sheet(item: $activeLabSheet) -->
<!-- RESOLVED: M1 — added init() with 30-day #Predicate on allReadings query -->

```swift
import SwiftUI
import SwiftData

// RESOLVED: H1 — single enum drives all sheets in this view
private enum StressLabSheet: Identifiable {
    case create
    case result(StressExperiment)

    var id: String {
        switch self {
        case .create:        return "create"
        case .result(let e): return "result_\(e.persistentModelID)"
        }
    }
}

struct StressLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StressExperiment.createdAt, order: .reverse) private var experiments: [StressExperiment]
    // RESOLVED: M1 — 30-day predicate, initialized in init()
    @Query private var allReadings: [StressReading]

    @State private var activeLabSheet: StressLabSheet? = nil

    // RESOLVED: M1 — custom init with predicate for allReadings
    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        _allReadings = Query(
            filter: #Predicate<StressReading> { $0.timestamp >= cutoff },
            sort: \.timestamp,
            order: .forward
        )
    }

    private var activeExperiment: StressExperiment? {
        experiments.first { !$0.isComplete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let active = activeExperiment {
                        activeCard(active)
                    } else {
                        emptyActiveCard
                    }

                    let past = experiments.filter { $0.isComplete }
                    if !past.isEmpty {
                        pastExperimentsSection(past)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stress Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if activeExperiment == nil {
                        Button {
                            HapticService.impact(.light)
                            activeLabSheet = .create
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                }
            }
            // RESOLVED: H1 — single .sheet() driven by StressLabSheet enum
            .sheet(item: $activeLabSheet) { sheet in
                switch sheet {
                case .create:
                    StressLabCreateView()
                case .result(let exp):
                    StressLabResultView(experiment: exp, allReadings: allReadings)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Active Card

    private func activeCard(_ exp: StressExperiment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: exp.resolvedInterventionType.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.name)
                        .font(.r(.headline, .semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(exp.resolvedInterventionType.label)
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(exp.daysRemaining)")
                        .font(.r(.title2, .bold))
                        .foregroundColor(AppColors.brand)
                    Text("days left")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            let progress = min(1.0, Double(exp.daysElapsed) / Double(exp.durationDays))
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.brand.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.brand)
                            .frame(width: geo.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)
                Text("Day \(exp.daysElapsed) of \(exp.durationDays)")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(AppColors.textSecondary)
            }

            if let hypothesis = exp.hypothesis, !hypothesis.isEmpty {
                Text(""\(hypothesis)"")
                    .font(.r(.caption, .regular))
                    .foregroundColor(AppColors.textSecondary)
                    .italic()
            }

            Button(role: .destructive) {
                modelContext.delete(exp)
                try? modelContext.save()
            } label: {
                Label("Delete experiment", systemImage: "trash")
                    .font(.r(.caption, .regular))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private var emptyActiveCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.system(size: 36))
                .foregroundColor(AppColors.brand.opacity(0.4))
            Text("No active experiment")
                .font(.r(.headline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("Pick a micro-intervention, run it for 7–14 days, and see if your stress score changes.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                HapticService.impact(.light)
                activeLabSheet = .create
            } label: {
                Text("Start an Experiment")
                    .font(.r(.body, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Past Experiments

    private func pastExperimentsSection(_ past: [StressExperiment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Experiments")
                .font(.r(.subheadline, .semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 4)
            ForEach(past) { exp in
                pastRow(exp)
            }
        }
    }

    private func pastRow(_ exp: StressExperiment) -> some View {
        Button {
            activeLabSheet = .result(exp)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: exp.resolvedInterventionType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.name)
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text("\(exp.durationDays)-day experiment")
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                if let delta = exp.cachedDelta {
                    deltaLabel(delta)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func deltaLabel(_ delta: Double) -> some View {
        let improved = delta < 0
        let text = improved ? "\(String(format: "%.1f", delta))" : "+\(String(format: "%.1f", delta))"
        let color: Color = improved ? .green : .red
        return Text(text)
            .font(.r(.caption, .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
```

- **Dependencies**: Steps 1–3
- **Risk**: Low

---

### Phase 4: Create Experiment Form

**Step 5 — Create `StressLabCreateView.swift`**
(`WellPlate/Features + UI/Stress/Views/StressLabCreateView.swift` — new file)

```swift
import SwiftUI
import SwiftData

struct StressLabCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var hypothesis: String = ""
    @State private var selectedType: InterventionType = .caffeine
    @State private var durationDays: Int = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Intervention Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(InterventionType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: selectedType) {
                        if name.isEmpty { name = selectedType.label }
                        if hypothesis.isEmpty { hypothesis = selectedType.suggestedHypothesis }
                    }
                }

                Section("Experiment Name") {
                    TextField("e.g. No caffeine after 2pm", text: $name)
                }

                Section {
                    TextField("Optional — what do you expect to happen?", text: $hypothesis, axis: .vertical)
                        .lineLimit(3...5)
                } header: {
                    Text("Hypothesis (optional)")
                } footer: {
                    Text("Keep it honest. The result will tell you what the data shows — not what you hoped.")
                        .font(.r(.caption2, .regular))
                }

                Section("Duration") {
                    Picker("Duration", selection: $durationDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("The app will compare your average stress score during this experiment against the 7 days before it started. Results need at least 3 days of data in each window.")
                        .font(.r(.caption, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .navigationTitle("New Experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.brand)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") { saveAndDismiss() }
                        .font(.r(.body, .semibold))
                        .foregroundColor(name.isEmpty ? .secondary : AppColors.brand)
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty { name = selectedType.label }
                if hypothesis.isEmpty { hypothesis = selectedType.suggestedHypothesis }
            }
        }
        .presentationDetents([.large])
    }

    private func saveAndDismiss() {
        let exp = StressExperiment(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            hypothesis: hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hypothesis,
            interventionType: selectedType.rawValue,
            startDate: Date(),
            durationDays: durationDays
        )
        modelContext.insert(exp)
        try? modelContext.save()
        HapticService.impact(.medium)
        dismiss()
    }
}
```

- **Dependencies**: Step 1
- **Risk**: Low

---

### Phase 5: Result View

**Step 6 — Create `StressLabResultView.swift`**
(`WellPlate/Features + UI/Stress/Views/StressLabResultView.swift` — new file)

<!-- RESOLVED: L2 — added @Environment(\.modelContext) and try? modelContext.save() after caching result fields -->

```swift
import SwiftUI

struct StressLabResultView: View {
    let experiment: StressExperiment
    let allReadings: [StressReading]

    @State private var result: StressLabResult? = nil
    @State private var isComputing = true
    @Environment(\.dismiss) private var dismiss
    // RESOLVED: L2 — needed to save cached result fields
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isComputing {
                        ProgressView("Analyzing…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let result {
                        resultContent(result)
                    } else {
                        notEnoughDataView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(experiment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            let computed = await Task.detached(priority: .userInitiated) {
                StressLabAnalyzer.analyze(experiment: experiment, allReadings: allReadings)
            }.value
            result = computed
            isComputing = false

            // RESOLVED: L2 — cache result and save context so delta pill appears immediately in list
            if let r = computed {
                experiment.cachedBaselineAvg   = r.baselineAvg
                experiment.cachedExperimentAvg = r.experimentAvg
                experiment.cachedDelta         = r.delta
                experiment.cachedCILow         = r.ciLow
                experiment.cachedCIHigh        = r.ciHigh
                if experiment.completedAt == nil && experiment.isComplete {
                    experiment.completedAt = experiment.endDate
                }
                try? modelContext.save()
            }
        }
    }

    // MARK: - Result Content

    private func resultContent(_ r: StressLabResult) -> some View {
        VStack(spacing: 20) {
            scoreComparisonCard(r)
            confidenceCard(r)
            interpretationCard(r)
            dataCoverageNote(r)
        }
    }

    private func scoreComparisonCard(_ r: StressLabResult) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Before")
                        .font(.r(.caption, .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .textCase(.uppercase)
                    Text(String(format: "%.1f", r.baselineAvg))
                        .font(.r(.largeTitle, .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("avg stress")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Image(systemName: r.delta < 0 ? "arrow.down" : "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(r.delta < 0 ? .green : .red)
                    Text(String(format: "%+.1f", r.delta))
                        .font(.r(.headline, .bold))
                        .foregroundColor(r.delta < 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("During")
                        .font(.r(.caption, .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .textCase(.uppercase)
                    Text(String(format: "%.1f", r.experimentAvg))
                        .font(.r(.largeTitle, .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("avg stress")
                        .font(.r(.caption2, .regular))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func confidenceCard(_ r: StressLabResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confidence Band (90%)")
                .font(.r(.subheadline, .semibold))
                .foregroundColor(AppColors.textPrimary)

            GeometryReader { geo in
                let range = 40.0
                let midX  = geo.size.width / 2
                let scale = geo.size.width / range
                let loX   = midX + CGFloat(r.ciLow)  * scale
                let hiX   = midX + CGFloat(r.ciHigh) * scale
                let dotX  = midX + CGFloat(r.delta)  * scale

                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 6)
                    Capsule()
                        .fill(AppColors.brand.opacity(0.25))
                        .frame(width: max(4, hiX - loX), height: 10)
                        .offset(x: min(loX, hiX))
                    Circle()
                        .fill(AppColors.brand)
                        .frame(width: 14, height: 14)
                        .offset(x: dotX - 7)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 20)
                        .offset(x: midX)
                }
            }
            .frame(height: 20)

            Text("The band shows where the true delta likely falls. A band entirely below zero suggests a real improvement; one crossing zero is inconclusive.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func interpretationCard(_ r: StressLabResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundColor(AppColors.brand)
                Text("What the data shows")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            Text(interpretation(for: r))
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
            Text("This is an observation, not a proof. Many factors affect stress — this experiment can't isolate just one.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func dataCoverageNote(_ r: StressLabResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)
            Text("Based on \(r.baselineDayCount) baseline days and \(r.experimentDayCount) experiment days with stress readings.")
                .font(.r(.caption, .regular))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var notEnoughDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textSecondary.opacity(0.4))
            Text("Not enough data yet")
                .font(.r(.headline, .semibold))
                .foregroundColor(AppColors.textPrimary)
            Text("At least 3 days of stress readings are needed in both the baseline (7 days before) and experiment windows. Keep the app open daily to collect more data.")
                .font(.r(.subheadline, .regular))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 12, y: 4)
        )
    }

    private func interpretation(for r: StressLabResult) -> String {
        let deltaMag = abs(r.delta)
        let ciSpansZero = r.ciLow < 0 && r.ciHigh > 0

        if ciSpansZero {
            return "During \"\(experiment.name)\", your average stress was \(String(format: "%.1f", r.experimentAvg)) compared to \(String(format: "%.1f", r.baselineAvg)) before. The difference (\(String(format: "%+.1f", r.delta)) points) is within the range of normal variation — the data doesn't clearly support or contradict your hypothesis."
        } else if r.delta < 0 {
            return "During \"\(experiment.name)\", your average stress dropped \(String(format: "%.1f", deltaMag)) points — from \(String(format: "%.1f", r.baselineAvg)) to \(String(format: "%.1f", r.experimentAvg)). The confidence band sits below zero, suggesting this wasn't random variation."
        } else {
            return "During \"\(experiment.name)\", your average stress rose \(String(format: "%.1f", deltaMag)) points — from \(String(format: "%.1f", r.baselineAvg)) to \(String(format: "%.1f", r.experimentAvg)). The confidence band sits above zero. This could mean the intervention didn't help, or that other factors were at play."
        }
    }
}
```

- **Dependencies**: Steps 1–3
- **Risk**: Low

---

### Phase 6: Wire Into StressView

**Step 7 — Edit `StressView.swift`**

<!-- RESOLVED: C1 — no new .sheet() added to StressView; StressLabView is presented via the existing StressSheet enum / activeSheet mechanism -->

Three targeted edits to `WellPlate/Features + UI/Stress/Views/StressView.swift`:

**Edit A — Add `.stressLab` case to `StressSheet` enum** (around line 12):

Add after the existing `case screenTimeDetail` line:
```swift
case stressLab
```

Add `case .stressLab: return "stressLab"` in the `var id: String` switch.

**Edit B — Add "Lab" toolbar button** (inside the existing `.toolbar { }` block, around line 66):

The existing toolbar has one `ToolbarItem(placement: .topBarTrailing)`. Add a second item for `.topBarLeading`:
```swift
ToolbarItem(placement: .topBarLeading) {
    if (HealthKitService.isAvailable || viewModel.usesMockData) && viewModel.isAuthorized && !viewModel.isLoading {
        Button {
            HapticService.impact(.light)
            activeSheet = .stressLab
        } label: {
            Label("Lab", systemImage: "flask.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(viewModel.stressLevel.color)
        }
    }
}
```

**Edit C — Handle `.stressLab` in existing `.sheet(item: $activeSheet)` switch** (around line 112):

In the existing switch inside `.sheet(item: $activeSheet)`, add after the `case .vital` branch:
```swift
case .stressLab:
    StressLabView()
```

- **Why**: Zero new `.sheet()` modifiers on `StressView` — CLAUDE.md constraint satisfied. The `StressLabView` is presented identically to how `ExerciseDetailView`, `SleepDetailView` etc. are presented today.
- **Dependencies**: Steps 1–6
- **Risk**: Low

---

## Testing Strategy

**Build verification** (all 4 targets):
```bash
xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build
```

**Manual verification flows**:
1. Stress tab → "Lab" button (flask) visible in top-left toolbar when authorized → tap opens `StressLabView`
2. Empty state shown → tap "Start an Experiment" → `StressLabCreateView` opens → type picker pre-fills name/hypothesis → tap "Start" → active card appears
3. Active card shows progress bar, days remaining, hypothesis text
4. Delete active experiment → returns to empty state
5. Past experiment row → tap → `StressLabResultView` opens → score comparison + CI band + interpretation rendered
6. Insufficient data → "Not enough data yet" view (no crash)
7. Past row shows colored delta pill after result is viewed once
8. Lab button absent on loading/permission screens

---

## Risks & Mitigations

- **Risk**: Bootstrap `randomElement() ?? 0` — zero substitution skews result on empty array
  - **Mitigation**: `minimumDays` guard before `bootstrapCI` ensures arrays are always non-empty in production; `?? 0` is purely a crash-safety fallback, never reached

- **Risk**: `Task.detached` result cached via `@Environment(\.modelContext)` — context access from non-main-actor
  - **Mitigation**: Cache mutations happen after `await Task.detached { }.value` which resumes on the calling actor (main actor, because `StressLabResultView` is implicitly `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)

- **Risk**: Schema migration fails on device with existing store
  - **Mitigation**: Adding `StressExperiment` to the container is non-destructive; SwiftData handles additive table creation automatically

---

## Success Criteria

- [ ] All 4 build targets compile cleanly
- [ ] "Lab" (flask) button visible in `StressView` top-left toolbar when authorized
- [ ] `StressView` still has exactly 2 `.sheet()` modifiers after this feature (no new ones added)
- [ ] Creating an experiment persists across app restart
- [ ] Active card shows correct day count and progress bar
- [ ] Result view shows score comparison + CI band + interpretation
- [ ] Insufficient data → "Not enough data yet" (no crash)
- [ ] Past experiments list shows cached delta pills after first result view
- [ ] All result text avoids causal language
