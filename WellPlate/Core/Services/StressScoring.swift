import Foundation

// MARK: - StressScoring (v3)
//
// Pure, stateless scoring for the v3 stress algorithm.
// 13 driver factors (Tier A/B/C, sum-to-100), recovery bonuses, time-ramped
// engagement penalty, multi-day pattern penalty, multiplicative HRV/RHR
// calibrator, coverage-weighted confidence.
//
// `computeStress(inputs:now:)` is the single entry point. No I/O, no
// side effects — every input change recomputes deterministically.
//
// Sugar dropped from formula in v3 (FoodLogEntry has no sugar field).
// Carbs ratio acts as proxy.

enum StressScoring {

    // MARK: - Source

    enum Source { case healthKit, manual }

    // MARK: - FactorPoints

    struct FactorPoints {
        let points: Double
        let maxPoints: Double
        let hasData: Bool
        let detail: String

        static let none = FactorPoints(points: 0, maxPoints: 0, hasData: false, detail: "No data")
    }

    // MARK: - Factor Inputs

    struct SleepInput {
        let totalHours: Double
        let deepHours: Double
        let source: Source
    }

    struct ExerciseInput {
        let steps: Double?
        let energy: Double?
        let manualMinutes: Int?
        let source: Source
    }

    struct CaffeineInput {
        let cups: Int
        let type: CoffeeType?
        /// True when the user has interacted with today's WellnessDayLog (per §0.1).
        let hasWellnessRow: Bool
    }

    struct ScreenInput {
        let totalHours: Double
        /// nil = no evening multiplier (no-op). Manual lane provides 0 or 2 hours.
        let eveningHours: Double?
        let source: Source
    }

    struct DietInput {
        let protein: Double
        let fiber: Double
        let carbs: Double
        let fat: Double
        let hasLogs: Bool
    }

    struct HydrationInput {
        let glasses: Int
        let hasWellnessRow: Bool
    }

    struct CircadianInput {
        let regularityScore: Double
        let hasEnoughData: Bool
    }

    struct DaylightInput {
        let minutes: Double
        let source: Source
    }

    struct FastingInput {
        let activeFastHours: Double?
        let isConfigured: Bool
    }

    struct RecoveryInput {
        let completedInterventionsToday: Int
        let hasJournalToday: Bool
        let hasMoodToday: Bool
        let hasMindfulSessionToday: Bool
    }

    struct VitalsInput {
        let todayHRV: Double?
        let hrvHistory: [DailyMetricSample]
        let todayRHR: Double?
        let rhrHistory: [DailyMetricSample]
    }

    struct HistoryInput {
        let recentWellnessLogs: [WellnessDayLog]      // last 3 days incl. today
        let foodLogPresenceByDay: [Date: Bool]        // last 3 days (key = startOfDay)
        let lastCompletedFastEnd: Date?
    }

    struct CalibratorInputs {
        let todayHRV: Double?
        let hrvBaseline: Double?
        let todayRHR: Double?
        let rhrBaseline: Double?
    }

    // MARK: - StressInputs

    struct StressInputs {
        var sleep: SleepInput?
        var exercise: ExerciseInput?
        var caffeine: CaffeineInput?
        var screen: ScreenInput?
        var diet: DietInput?
        var hydration: HydrationInput?
        var circadian: CircadianInput?
        var daylight: DaylightInput?
        var mealLogs: [FoodLogEntry]
        var fasting: FastingInput?
        var triggerLogs: [FoodLogEntry]
        var mood: MoodOption?
        var symptoms: [SymptomEntry]
        var recovery: RecoveryInput
        var history: HistoryInput
        var vitals: VitalsInput
        var goals: UserGoals
    }

    // MARK: - StressResult

    struct StressResult {
        let score: Double
        let factors: [FactorPoints]
        let driverSum: Double
        let recovery: Double
        let engagementPenalty: Double
        let patternPenalty: Double
        let calibrator: Double
        let confidence: Confidence
        let raw: Double
    }

    // MARK: - Confidence

    enum Confidence: String {
        case low, medium, high

        var label: String {
            switch self {
            case .low:    "Low confidence"
            case .medium: "Medium confidence"
            case .high:   "High confidence"
            }
        }

        var systemImage: String {
            switch self {
            case .low:    "gauge.with.dots.needle.0percent"
            case .medium: "gauge.with.dots.needle.50percent"
            case .high:   "gauge.with.dots.needle.100percent"
            }
        }
    }

    // MARK: - Weights (Tier A 60 / Tier B 25 / Tier C 15 = 100)

    enum Weights {
        // Tier A
        static let sleep: Double           = 20
        static let exercise: Double        = 12
        static let caffeine: Double        = 10
        static let screenTime: Double      = 10
        static let diet: Double            = 8
        // Tier B
        static let hydration: Double       = 5
        static let circadian: Double       = 5
        static let daylight: Double        = 3
        static let mealTiming: Double      = 4
        static let fasting: Double         = 3
        static let eatingTriggers: Double  = 5
        // Tier C
        static let mood: Double            = 8
        static let symptoms: Double        = 7
        // Caps
        static let recoveryCap: Double     = -10
        static let engagementCap: Double   = 18
        static let patternCap: Double      = 12
    }

    // MARK: - Tier A: Sleep

    /// Sleep penalty 0…20 per formula §3.1.
    static func sleepPoints(input: SleepInput?) -> FactorPoints {
        guard let input = input else { return .none }
        let h = input.totalHours
        let hoursTerm: Double
        switch h {
        case ..<4:    hoursTerm = 18
        case 4..<5:   hoursTerm = lerp(from: 18, to: 14, x: h, lo: 4, hi: 5)
        case 5..<6:   hoursTerm = lerp(from: 14, to:  9, x: h, lo: 5, hi: 6)
        case 6..<7:   hoursTerm = lerp(from:  9, to:  4, x: h, lo: 6, hi: 7)
        case 7..<9:   hoursTerm = lerp(from:  4, to:  0, x: h, lo: 7, hi: 9)
        case 9..<10:  hoursTerm = lerp(from:  0, to:  3, x: h, lo: 9, hi: 10)
        default:      hoursTerm = 5
        }

        let deepMin = input.deepHours * 60.0
        let deepTerm: Double
        switch deepMin {
        case ..<30:   deepTerm = 4
        case 30..<45: deepTerm = 2
        case 45..<60: deepTerm = 1
        default:      deepTerm = 0
        }

        let pts = min(Weights.sleep, hoursTerm + deepTerm)
        let detail = String(format: "%.1fh total · %.0fm deep", h, deepMin)
        return FactorPoints(points: pts, maxPoints: Weights.sleep, hasData: true, detail: detail)
    }

    // MARK: - Tier A: Exercise

    /// Exercise penalty (range −3…+12) per formula §3.2.
    static func exercisePoints(input: ExerciseInput?) -> FactorPoints {
        guard let input = input else { return .none }
        let activity: Double
        if input.steps != nil || input.energy != nil {
            let stepRatio = (input.steps ?? 0) / 7000.0
            let energyRatio = (input.energy ?? 0) / 400.0
            activity = max(stepRatio, energyRatio)
        } else if let mins = input.manualMinutes {
            // Treat 100 manual minutes as ~1 day of step activity (100 steps/min walking).
            activity = Double(mins * 100) / 7000.0
        } else {
            return .none
        }

        let pts: Double
        switch activity {
        case ..<0.1:   pts = 12
        case 0.1..<0.5: pts = lerp(from: 12, to:  6, x: activity, lo: 0.1, hi: 0.5)
        case 0.5..<1.0: pts = lerp(from:  6, to:  0, x: activity, lo: 0.5, hi: 1.0)
        case 1.0..<1.5: pts = lerp(from:  0, to: -3, x: activity, lo: 1.0, hi: 1.5)
        default:        pts = -3
        }

        let detail: String
        if let s = input.steps, let e = input.energy {
            detail = "\(Int(s)) steps · \(Int(e)) kcal"
        } else if let s = input.steps {
            detail = "\(Int(s)) steps"
        } else if let e = input.energy {
            detail = "\(Int(e)) kcal"
        } else if let m = input.manualMinutes {
            detail = "\(m) min logged"
        } else {
            detail = "Active"
        }
        return FactorPoints(points: pts, maxPoints: Weights.exercise, hasData: true, detail: detail)
    }

    // MARK: - Tier A: Caffeine

    /// Caffeine penalty 0…10 per formula §3.3. `mgPerCup` defaults to 80 for legacy
    /// rows where `coffeeType` is nil.
    static func caffeinePoints(input: CaffeineInput?) -> FactorPoints {
        guard let input = input else { return .none }
        guard input.hasWellnessRow else { return .none }
        let mgPerCup = input.type?.caffeineMg ?? 80   // legacy fallback
        let mg = Double(input.cups * mgPerCup)
        let pts: Double
        switch mg {
        case ..<100:    pts = 0
        case 100..<200: pts = 2
        case 200..<300: pts = 5
        case 300..<400: pts = 7
        default:        pts = 10
        }
        let detail = input.cups == 0 ? "No coffee logged" : "\(input.cups) cup\(input.cups == 1 ? "" : "s") · \(Int(mg))mg"
        return FactorPoints(points: pts, maxPoints: Weights.caffeine, hasData: true, detail: detail)
    }

    // MARK: - Tier A: Screen Time

    /// Screen time penalty 0…10 per formula §3.4. Evening multiplier no-ops when
    /// `eveningHours == nil` (auto-detected reading lacks hourly buckets in v3).
    static func screenTimePoints(input: ScreenInput?) -> FactorPoints {
        guard let input = input else { return .none }
        let h = input.totalHours
        let base: Double
        switch h {
        case ..<2:   base = 0
        case 2..<4:  base = lerp(from: 0, to: 3, x: h, lo: 2, hi: 4)
        case 4..<6:  base = lerp(from: 3, to: 6, x: h, lo: 4, hi: 6)
        case 6..<8:  base = lerp(from: 6, to: 9, x: h, lo: 6, hi: 8)
        default:     base = 10
        }

        let eveningMult: Double
        if let eh = input.eveningHours, eh > 0 {
            eveningMult = 1 + min(0.5, eh / 4.0)
        } else {
            eveningMult = 1.0
        }

        let pts = min(Weights.screenTime, base * eveningMult)
        let detail = String(format: "%.1fh on screen", h)
        return FactorPoints(points: pts, maxPoints: Weights.screenTime, hasData: true, detail: detail)
    }

    // MARK: - Tier A: Diet (carbs proxy)

    /// Diet penalty 0…8. Uses carbs ratio as proxy for sugar load — `FoodLogEntry`
    /// has no sugar field as of v3.
    static func dietPoints(input: DietInput?, goals: UserGoals) -> FactorPoints {
        guard let input = input, input.hasLogs else { return .none }

        let carbsGoal = max(goals.carbsGoalGrams, 1)
        let proteinGoal = max(goals.proteinGoalGrams, 1)
        let carbRatio = input.carbs / Double(carbsGoal)
        let proteinRatio = input.protein / Double(proteinGoal)

        let carbTerm: Double
        switch carbRatio {
        case ..<0.8:    carbTerm = 0
        case 0.8..<1.0: carbTerm = 1
        case 1.0..<1.5: carbTerm = lerp(from: 1, to: 4, x: carbRatio, lo: 1.0, hi: 1.5)
        default:        carbTerm = 5
        }
        let proteinTerm = proteinRatio < 0.5 ? 3.0 : 0.0
        let pts = min(Weights.diet, carbTerm + proteinTerm)

        let detail = String(format: "%.0fg protein · %.0fg carbs", input.protein, input.carbs)
        return FactorPoints(points: pts, maxPoints: Weights.diet, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Hydration

    /// Hydration penalty 0…5 per formula §3.6.
    static func hydrationPoints(input: HydrationInput?, goal: Int) -> FactorPoints {
        guard let input = input else { return .none }
        guard input.hasWellnessRow else { return .none }
        let goalSafe = max(goal, 1)
        let r = Double(input.glasses) / Double(goalSafe)
        let pts: Double
        switch r {
        case ..<0.3:   pts = 5
        case 0.3..<0.5: pts = 3
        case 0.5..<0.8: pts = 1
        default:       pts = 0
        }
        let detail = "\(input.glasses) of \(goalSafe) glasses"
        return FactorPoints(points: pts, maxPoints: Weights.hydration, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Circadian

    /// Circadian regularity penalty 0…5 per formula §3.7.
    static func circadianPoints(input: CircadianInput?) -> FactorPoints {
        guard let input = input else { return .none }
        guard input.hasEnoughData else { return .none }
        let normalized = max(0, min(100, input.regularityScore)) / 100.0
        let pts = (1.0 - normalized) * Weights.circadian
        let detail = String(format: "Regularity %.0f%%", input.regularityScore)
        return FactorPoints(points: pts, maxPoints: Weights.circadian, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Daylight

    /// Daylight penalty 0…3 per formula §3.8.
    static func daylightPoints(input: DaylightInput?) -> FactorPoints {
        guard let input = input else { return .none }
        let m = input.minutes
        let pts: Double
        switch m {
        case ..<15:   pts = 3
        case 15..<30: pts = 2
        case 30..<60: pts = 1
        default:      pts = 0
        }
        let detail = "\(Int(m)) min outside"
        return FactorPoints(points: pts, maxPoints: Weights.daylight, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Meal timing

    /// Meal timing penalty 0…4 per formula §3.9.
    static func mealTimingPoints(logs: [FoodLogEntry]) -> FactorPoints {
        guard !logs.isEmpty else { return .none }
        let cal = Calendar.current
        let sorted = logs.sorted { $0.createdAt < $1.createdAt }

        // Late penalty: any meal at or past 21:30
        let latePen: Double = sorted.contains { entry in
            let h = cal.component(.hour, from: entry.createdAt)
            let m = cal.component(.minute, from: entry.createdAt)
            return h > 21 || (h == 21 && m >= 30)
        } ? 2 : 0

        // Gap penalty: pair (i, i+1) with gap > 5h AND m_{i+1}.calories > 600
        var gapPen: Double = 0
        if sorted.count >= 2 {
            for i in 0..<(sorted.count - 1) {
                let gap = sorted[i + 1].createdAt.timeIntervalSince(sorted[i].createdAt)
                if gap > 5 * 3600 && sorted[i + 1].calories > 600 {
                    gapPen = 2
                    break
                }
            }
        }

        let pts = min(Weights.mealTiming, latePen + gapPen)
        let detail: String
        if pts == 0 {
            detail = "Meals well-timed"
        } else if latePen > 0 && gapPen > 0 {
            detail = "Late meal + long gap"
        } else if latePen > 0 {
            detail = "Late meal logged"
        } else {
            detail = "Long gap before heavy meal"
        }
        return FactorPoints(points: pts, maxPoints: Weights.mealTiming, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Fasting

    /// Fasting penalty 0…3 per formula §3.10.
    static func fastingPoints(input: FastingInput?) -> FactorPoints {
        guard let input = input else { return .none }
        guard input.isConfigured else { return .none }
        let h = input.activeFastHours ?? 0
        let pts: Double
        switch h {
        case ..<16:    pts = 0
        case 16..<20:  pts = 1
        case 20..<24:  pts = 2
        default:       pts = 3
        }
        let detail: String
        if h <= 0 {
            detail = "Not fasting"
        } else {
            detail = String(format: "%.1fh into fast", h)
        }
        return FactorPoints(points: pts, maxPoints: Weights.fasting, hasData: true, detail: detail)
    }

    // MARK: - Tier B: Eating triggers

    /// Eating triggers penalty 0…5 per formula §3.11.
    static func eatingTriggerPoints(logs: [FoodLogEntry]) -> FactorPoints {
        guard !logs.isEmpty else { return .none }
        let stressTriggers: Set<String> = [
            EatingTrigger.stressed.rawValue,
            EatingTrigger.rushed.rawValue,
            EatingTrigger.poorSleep.rawValue,
            EatingTrigger.bored.rawValue
        ]
        let count = logs.reduce(0) { acc, entry in
            acc + (entry.eatingTriggers?.filter { stressTriggers.contains($0) }.count ?? 0)
        }
        let pts: Double
        switch count {
        case 0: pts = 0
        case 1: pts = 2
        case 2: pts = 3
        default: pts = 5
        }
        let detail = count == 0 ? "No stress triggers" : "\(count) stress trigger\(count == 1 ? "" : "s")"
        return FactorPoints(points: pts, maxPoints: Weights.eatingTriggers, hasData: true, detail: detail)
    }

    // MARK: - Tier C: Mood

    /// Mood factor (range −2…+8) per formula §3.12.
    static func moodPoints(mood: MoodOption?) -> FactorPoints {
        guard let mood = mood else { return .none }
        let pts: Double
        switch mood {
        case .awful: pts = 8
        case .bad:   pts = 5
        case .okay:  pts = 2
        case .good:  pts = 0
        case .great: pts = -2
        }
        let detail = "Feeling \(mood.label.lowercased())"
        return FactorPoints(points: pts, maxPoints: Weights.mood, hasData: true, detail: detail)
    }

    // MARK: - Tier C: Symptoms

    /// Symptoms penalty 0…7 per formula §3.13. Always reports `hasData: true` —
    /// "no symptoms" is meaningful information.
    static func symptomPoints(entries: [SymptomEntry]) -> FactorPoints {
        guard !entries.isEmpty else {
            return FactorPoints(points: 0, maxPoints: Weights.symptoms, hasData: true, detail: "No symptoms today")
        }

        // Dedupe by name; take max severity per name
        var maxByName: [String: (severity: Int, category: String)] = [:]
        for entry in entries {
            if let existing = maxByName[entry.name] {
                if entry.severity > existing.severity {
                    maxByName[entry.name] = (entry.severity, entry.category)
                }
            } else {
                maxByName[entry.name] = (entry.severity, entry.category)
            }
        }

        func weight(for category: String) -> Double {
            switch SymptomCategory(rawValue: category) {
            case .cognitive, .pain: return 1.0
            case .energy:           return 0.7
            case .digestive:        return 0.5
            case .none:             return 0.5
            }
        }

        let weightedSum = maxByName.values.reduce(0.0) { acc, pair in
            acc + Double(pair.severity) * weight(for: pair.category)
        }

        let pts = min(Weights.symptoms, weightedSum / 30.0 * Weights.symptoms)
        let detail = "\(maxByName.count) symptom\(maxByName.count == 1 ? "" : "s") logged"
        return FactorPoints(points: pts, maxPoints: Weights.symptoms, hasData: true, detail: detail)
    }

    // MARK: - Recovery

    /// Intervention bonus, capped at −6.
    static func interventionBonus(sessions: [InterventionSession]) -> Double {
        let completed = sessions.filter { $0.completed }.count
        return max(-6, Double(completed) * -3)
    }

    static func journalBonus(hasEntry: Bool) -> Double {
        hasEntry ? -2 : 0
    }

    /// Mindful bonus — mood logging counts as a mindful act.
    static func mindfulBonus(hasMoodToday: Bool, hasMindfulSession: Bool) -> Double {
        (hasMoodToday || hasMindfulSession) ? -2 : 0
    }

    /// Recovery total, capped at `Weights.recoveryCap` (−10).
    static func recoveryTotal(_ inputs: RecoveryInput) -> Double {
        // Reconstruct intervention bonus from the count (skip `completed` filter — caller filters).
        let intervention = max(-6, Double(inputs.completedInterventionsToday) * -3)
        let journal = journalBonus(hasEntry: inputs.hasJournalToday)
        let mindful = mindfulBonus(hasMoodToday: inputs.hasMoodToday, hasMindfulSession: inputs.hasMindfulSessionToday)
        return max(Weights.recoveryCap, intervention + journal + mindful)
    }

    // MARK: - Engagement penalty

    /// Time-ramped engagement penalty 0…18.
    /// Note: hour-of-day uses Calendar.current → user's local TZ; DST handled by Calendar.
    static func engagementPenalty(inputs: StressInputs, now: Date) -> Double {
        // Activation guard: at least one driver must have data (per plan §0.1).
        let factors = allFactors(inputs: inputs)
        guard factors.contains(where: \.hasData) else { return 0 }

        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: now))
                 + Double(cal.component(.minute, from: now)) / 60.0

        func ramp(start: Double, end: Double) -> Double {
            guard end > start else { return 0 }
            return min(1, max(0, (hour - start) / (end - start)))
        }

        var sum: Double = 0

        // no_mood: max 5, 17→21
        if inputs.mood == nil {
            sum += 5 * ramp(start: 17, end: 21)
        }
        // no_food: max 4, 17→20
        if inputs.mealLogs.isEmpty {
            sum += 4 * ramp(start: 17, end: 20)
        }
        // no_water: max 4, 14→18
        if (inputs.hydration?.glasses ?? 0) == 0 {
            sum += 4 * ramp(start: 14, end: 18)
        }
        // low_steps: max 3, 16→20 — only when HK steps known and below threshold
        if let s = inputs.exercise?.steps, s < 2000 {
            sum += 3 * ramp(start: 16, end: 20)
        }
        // no_reflection: max 2, 18→21
        if !inputs.recovery.hasJournalToday
            && inputs.mood == nil
            && !inputs.recovery.hasMindfulSessionToday {
            sum += 2 * ramp(start: 18, end: 21)
        }

        return min(Weights.engagementCap, sum)
    }

    // MARK: - Pattern penalty

    /// 3-day / 14-day pattern penalty 0…12 per formula §6.
    static func patternPenalty(history: HistoryInput) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0...2).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }

        // no_food_3d: all 3 days have NO FoodLogEntry
        let noFood3d: Bool = days.allSatisfy { !(history.foodLogPresenceByDay[$0] ?? false) }

        // low_mood_3d: all 3 days have moodRaw resolving to .awful or .bad
        let logsByDay: [Date: WellnessDayLog] = Dictionary(uniqueKeysWithValues:
            history.recentWellnessLogs.map { (cal.startOfDay(for: $0.day), $0) }
        )
        let lowMood3d: Bool = days.allSatisfy { day in
            guard let log = logsByDay[day],
                  let raw = log.moodRaw,
                  let mood = MoodOption(rawValue: raw) else { return false }
            return mood == .awful || mood == .bad
        }

        // high_coffee_3d: all 3 days have coffeeCups >= 4
        let highCoffee3d: Bool = days.allSatisfy { day in
            guard let log = logsByDay[day] else { return false }
            return log.coffeeCups >= 4
        }

        // no_fast_14d: lastCompletedFastEnd is nil OR < now − 14d
        let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let noFast14d: Bool = (history.lastCompletedFastEnd == nil)
            || (history.lastCompletedFastEnd! < fourteenDaysAgo)

        var p: Double = 0
        if noFood3d     { p += 4 }
        if lowMood3d    { p += 3 }
        if highCoffee3d { p += 3 }
        if noFast14d    { p += 2 }

        return min(Weights.patternCap, p)
    }

    // MARK: - Calibrator + Baseline

    /// 14-day baseline mean over `samples` (excluding today and future), requiring
    /// ≥5 valid days (`value > 0`).
    static func baseline14Day(_ samples: [DailyMetricSample], excludingToday now: Date) -> Double? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let cutoff = cal.date(byAdding: .day, value: -14, to: startOfToday) ?? startOfToday
        let valid = samples.filter {
            $0.date >= cutoff
            && $0.date < startOfToday   // exclude today AND future
            && $0.value > 0
        }
        guard valid.count >= 5 else { return nil }
        return valid.map(\.value).reduce(0, +) / Double(valid.count)
    }

    /// Multiplicative calibrator clamped to [0.90, 1.15]. Collapses to 1.0 when
    /// no baseline is available (Watch-less or insufficient days).
    static func calibrator(_ inputs: CalibratorInputs) -> Double {
        var delta = 0.0
        var present = false
        if let t = inputs.todayHRV, let b = inputs.hrvBaseline, b > 0 {
            delta += ((b - t) / b) * 0.5
            present = true
        }
        if let t = inputs.todayRHR, let b = inputs.rhrBaseline, b > 0 {
            delta += ((t - b) / b) * 0.3
            present = true
        }
        return present ? max(0.90, min(1.15, 1.0 + delta)) : 1.0
    }

    // MARK: - Confidence

    /// Coverage-weighted confidence per formula §8.
    static func confidence(factors: [FactorPoints]) -> Confidence {
        let totalPossible: Double = 100   // sum of driver weights
        let covered = factors.reduce(0.0) { $0 + ($1.hasData ? $1.maxPoints : 0) }
        let coverage = covered / totalPossible
        switch coverage {
        case 0.70...:        return .high
        case 0.40..<0.70:    return .medium
        default:             return .low
        }
    }

    // MARK: - Factor assembly

    /// Returns all 13 driver factors in stable order. Index → title mapping
    /// owned by `StressViewModel` (see `factorTitle(_:)`).
    static func allFactors(inputs: StressInputs) -> [FactorPoints] {
        return [
            sleepPoints(input: inputs.sleep),
            exercisePoints(input: inputs.exercise),
            caffeinePoints(input: inputs.caffeine),
            screenTimePoints(input: inputs.screen),
            dietPoints(input: inputs.diet, goals: inputs.goals),
            hydrationPoints(input: inputs.hydration, goal: inputs.goals.waterDailyCups),
            circadianPoints(input: inputs.circadian),
            daylightPoints(input: inputs.daylight),
            mealTimingPoints(logs: inputs.mealLogs),
            fastingPoints(input: inputs.fasting),
            eatingTriggerPoints(logs: inputs.triggerLogs),
            moodPoints(mood: inputs.mood),
            symptomPoints(entries: inputs.symptoms),
        ]
    }

    // MARK: - computeStress (orchestrator)

    /// Pure stress computation. `S = clamp(max(0, D + R + E + P) · C, 0, 100)`.
    static func computeStress(inputs: StressInputs, now: Date) -> StressResult {
        let factors = allFactors(inputs: inputs)
        let driverSum = factors.filter(\.hasData).reduce(0.0) { $0 + $1.points }
        let recovery = recoveryTotal(inputs.recovery)
        let engagement = engagementPenalty(inputs: inputs, now: now)
        let patterns = patternPenalty(history: inputs.history)

        let hrvBaseline = baseline14Day(inputs.vitals.hrvHistory, excludingToday: now)
        let rhrBaseline = baseline14Day(inputs.vitals.rhrHistory, excludingToday: now)
        let calib = calibrator(CalibratorInputs(
            todayHRV: inputs.vitals.todayHRV,
            hrvBaseline: hrvBaseline,
            todayRHR: inputs.vitals.todayRHR,
            rhrBaseline: rhrBaseline
        ))

        let raw = max(0, driverSum + recovery + engagement + patterns)
        let score = max(0, min(100, raw * calib))

        return StressResult(
            score: score,
            factors: factors,
            driverSum: driverSum,
            recovery: recovery,
            engagementPenalty: engagement,
            patternPenalty: patterns,
            calibrator: calib,
            confidence: confidence(factors: factors),
            raw: raw
        )
    }

    // MARK: - Helpers

    private static func lerp(from a: Double, to b: Double, x: Double, lo: Double, hi: Double) -> Double {
        guard hi > lo else { return a }
        let t = max(0.0, min(1.0, (x - lo) / (hi - lo)))
        return a + (b - a) * t
    }
}
