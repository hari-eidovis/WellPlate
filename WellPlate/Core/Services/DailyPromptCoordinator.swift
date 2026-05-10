import Foundation
import SwiftUI
import SwiftData
import Combine

/// Owns the morning/evening manual check-in flow. Decides whether to surface
/// a global overlay sheet (`QuickCheckInSheet`) when HealthKit can't supply
/// one of the daily-resolved drivers (sleep / screen-time / exercise / daylight).
///
/// Source-of-truth lives in `ManualDailyInput` SwiftData rows. The coordinator
/// is intentionally state-free — methods receive `ModelContext` per call so
/// it stays testable.
@MainActor
final class DailyPromptCoordinator: ObservableObject {

    enum PromptKind: Identifiable {
        case morning(MorningGaps)
        case evening(EveningGaps)

        var id: String {
            switch self {
            case .morning: return "morning"
            case .evening: return "evening"
            }
        }
    }

    struct MorningGaps {
        let needsSleep: Bool
    }

    struct EveningGaps {
        let needsScreen: Bool
        let needsExercise: Bool
        let needsDaylight: Bool
    }

    /// The currently-presented prompt (drives `.sheet(item:)`). Set to nil to dismiss.
    @Published var pendingPrompt: PromptKind? = nil

    /// Bumped whenever a `ManualDailyInput` save lands so subscribers can recompute.
    @Published var manualInputSavedAt: Date = .distantPast

    // MARK: - UserDefaults keys

    private enum Defaults {
        static let dontAskAgain = "wp.stress.dontAskAgain"
    }

    // MARK: - Foreground evaluation

    /// Called from `RootView.onChange(of: scenePhase) { ... .active ... }`.
    /// Decides whether to surface a morning or evening prompt based on:
    /// 1. HK authorization (skip if HK denied OR not requested yet — let HK lane take over)
    /// 2. "Don't ask again" UserDefaults flag
    /// 3. 24h post-onboarding grace period
    /// 4. Time of day + presence of HK data + whether we already asked today.
    func evaluateOnAppForeground(
        now: Date,
        modelContext: ModelContext,
        healthService: HealthKitServiceProtocol
    ) async {
        // Guard 1 (HK auth): if HK isn't authorized we still need the manual lane,
        // BUT if the user explicitly denied during onboarding the prompts feel
        // pushy; rely on the dontAskAgain guard instead. Skip only when HK auth
        // hasn't been requested yet (HealthKitService.isAuthorized == false on
        // a fresh install before the auth sheet has been presented).
        // Per checklist H3: guard `healthService.isAuthorized` — but the manual
        // lane EXISTS specifically for HK-denied users. The "auth" guard here
        // protects only the sleep/screen/exercise HK fetch calls below.
        guard !UserDefaults.standard.bool(forKey: Defaults.dontAskAgain) else { return }

        // Guard 2 (24h grace post-onboarding)
        if let completedAt = UserProfileManager.shared.onboardingCompletedAt,
           now.timeIntervalSince(completedAt) < 24 * 3600 {
            return
        }

        // Resolve today's ManualDailyInput (or note absence)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let manualDescriptor = FetchDescriptor<ManualDailyInput>(
            predicate: #Predicate { $0.day == today }
        )
        let manual = (try? modelContext.fetch(manualDescriptor))?.first

        let hour = cal.component(.hour, from: now)

        // ── Morning prompt: ≥11:00, HK sleep silent, no manual sleep, not yet asked today
        if hour >= 11,
           manual?.morningAskedAt == nil,
           manual?.sleepHours == nil {
            let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
            let sleepRange = DateInterval(start: yesterday, end: now)
            let hkSleep: [DailySleepSummary]
            if healthService.isAuthorized {
                hkSleep = (try? await healthService.fetchDailySleepSummaries(for: sleepRange)) ?? []
            } else {
                hkSleep = []
            }
            if hkSleep.isEmpty {
                pendingPrompt = .morning(MorningGaps(needsSleep: true))
                return
            }
        }

        // ── Evening prompt: ≥19:00, not yet asked today, ≥1 silent driver
        if hour >= 19, manual?.eveningAskedAt == nil {
            let dayRange = DateInterval(start: today, end: now)
            // Screen — auto detection from ScreenTimeManager
            let screenSilent = ScreenTimeManager.shared.currentAutoDetectedReading == nil
                && manual?.screenTimeHours == nil
            // Exercise — HK steps / energy on today
            let exerciseSilent: Bool
            if healthService.isAuthorized {
                let stepsToday = (try? await healthService.fetchSteps(for: dayRange))?.map(\.value).reduce(0, +) ?? 0
                let energyToday = (try? await healthService.fetchActiveEnergy(for: dayRange))?.map(\.value).reduce(0, +) ?? 0
                exerciseSilent = stepsToday <= 0 && energyToday <= 0 && manual?.exerciseMinutes == nil
            } else {
                exerciseSilent = manual?.exerciseMinutes == nil
            }
            // Daylight — HK minutes on today
            let daylightSilent: Bool
            if healthService.isAuthorized {
                let dlToday = (try? await healthService.fetchDaylight(for: dayRange))?.map(\.value).reduce(0, +) ?? 0
                daylightSilent = dlToday <= 0 && manual?.amDaylightOutside == nil
            } else {
                daylightSilent = manual?.amDaylightOutside == nil
            }
            let gaps = EveningGaps(
                needsScreen: screenSilent,
                needsExercise: exerciseSilent,
                needsDaylight: daylightSilent
            )
            if gaps.needsScreen || gaps.needsExercise || gaps.needsDaylight {
                pendingPrompt = .evening(gaps)
                return
            }
        }
    }

    // MARK: - User actions

    /// User chose "Skip for today" — record the skip timestamp on `ManualDailyInput`.
    func recordSkip(_ kind: PromptKind, modelContext: ModelContext, now: Date) {
        let row = upsertTodayInput(modelContext: modelContext, now: now)
        switch kind {
        case .morning: row.morningAskedAt = now
        case .evening: row.eveningAskedAt = now
        }
        try? modelContext.save()
        pendingPrompt = nil
    }

    /// User saved values — write them into `ManualDailyInput` and clear the prompt.
    func recordSave(
        _ kind: PromptKind,
        values: ManualValues,
        modelContext: ModelContext,
        now: Date
    ) {
        let row = upsertTodayInput(modelContext: modelContext, now: now)
        if let h = values.sleepHours { row.sleepHours = h }
        if let q = values.sleepQuality { row.sleepQuality = q }
        if let bt = values.bedtime { row.bedtime = bt }
        if let wt = values.wakeTime { row.wakeTime = wt }
        if let s = values.screenTimeHours { row.screenTimeHours = s }
        if let he = values.heavyEveningScreens { row.heavyEveningScreens = he }
        if let e = values.exerciseMinutes { row.exerciseMinutes = e }
        if let d = values.amDaylightOutside { row.amDaylightOutside = d }
        switch kind {
        case .morning: row.morningAskedAt = now
        case .evening: row.eveningAskedAt = now
        }
        try? modelContext.save()
        manualInputSavedAt = now
        pendingPrompt = nil
    }

    /// User chose "Don't ask again" — persist the flag and clear any pending prompt.
    func disableForever() {
        UserDefaults.standard.set(true, forKey: Defaults.dontAskAgain)
        pendingPrompt = nil
    }

    // MARK: - Helpers

    private func upsertTodayInput(modelContext: ModelContext, now: Date) -> ManualDailyInput {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<ManualDailyInput>(
            predicate: #Predicate { $0.day == today }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let new = ManualDailyInput(day: today)
        modelContext.insert(new)
        return new
    }
}

// MARK: - ManualValues bag (used by QuickCheckInSheet → recordSave)

struct ManualValues {
    var sleepHours: Double?
    var sleepQuality: Int?
    var bedtime: Date?
    var wakeTime: Date?
    var screenTimeHours: Double?
    var heavyEveningScreens: Bool?
    var exerciseMinutes: Int?
    var amDaylightOutside: Bool?
}

// MARK: - ManualInputObservable conformance

extension DailyPromptCoordinator: ManualInputObservable {
    var manualInputSavedAtPublisher: Published<Date>.Publisher {
        $manualInputSavedAt
    }
}
