import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - ReportNarrativeGenerator
//
// Generates LLM narratives via Foundation Models (iOS 26+) with template fallback.
// Makes ~7 FM calls: 1 executive summary, up to 5 section narratives, 1 action plan.

@MainActor
final class ReportNarrativeGenerator {

    // Section priority for FM narrative generation
    private let sectionPriority = ["stress", "nutrition", "sleep", "symptoms", "activity", "cross"]

    // MARK: - Public API

    func generateNarratives(
        for context: ReportContext,
        promptContext: ReportPromptContext
    ) async -> ReportNarratives {
        if #available(iOS 26, *) {
            if let fmResult = await generateWithFM(for: context, promptContext: promptContext) {
                return fmResult
            }
        }
        return generateTemplates(for: context, promptContext: promptContext)
    }

    // MARK: - Foundation Models Path

    @available(iOS 26, *)
    private func generateWithFM(
        for context: ReportContext,
        promptContext: ReportPromptContext
    ) async -> ReportNarratives? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        // Call 1: Executive Summary
        var execSummary: ExecutiveSummaryNarrative?
        do {
            let session = LanguageModelSession()
            let prompt = buildExecutiveSummaryPrompt(promptContext: promptContext)
            let result = try await session.respond(to: prompt, generating: _ReportExecutiveSummary.self)
            execSummary = ExecutiveSummaryNarrative(
                narrative: result.content.narrative,
                topWin: result.content.topWin,
                topConcern: result.content.topConcern
            )
        } catch {
            WPLogger.home.warning("ReportNarrativeGenerator: FM exec summary failed — \(error.localizedDescription)")
        }

        // Calls 2-6: Section Narratives (top 5 with data)
        let activeSections = sectionPriority.filter { sectionHasData($0, context: context) }
        var sectionNarratives: [String: SectionNarrative] = [:]

        for section in activeSections.prefix(5) {
            do {
                let session = LanguageModelSession()
                let prompt = buildSectionNarrativePrompt(sectionName: section, promptContext: promptContext)
                let result = try await session.respond(to: prompt, generating: _ReportSectionNarrative.self)
                sectionNarratives[section] = SectionNarrative(
                    headline: result.content.headline,
                    narrative: result.content.narrative
                )
            } catch {
                WPLogger.home.warning("ReportNarrativeGenerator: FM section '\(section)' failed — \(error.localizedDescription)")
            }
        }

        // Call 7: Action Plan
        var actionPlan: [ActionRecommendation] = []
        do {
            let session = LanguageModelSession()
            let prompt = buildActionPlanPrompt(promptContext: promptContext)
            let result = try await session.respond(to: prompt, generating: _ReportActionPlan.self)
            actionPlan = result.content.recommendations.map { rec in
                ActionRecommendation(title: rec.title, rationale: rec.rationale, domain: rec.domain)
            }
        } catch {
            WPLogger.home.warning("ReportNarrativeGenerator: FM action plan failed — \(error.localizedDescription)")
        }

        // Fall through to template for any missing pieces
        let templateFallback = generateTemplates(for: context, promptContext: promptContext)

        return ReportNarratives(
            executiveSummary: execSummary ?? templateFallback.executiveSummary,
            sectionNarratives: sectionNarratives.isEmpty ? templateFallback.sectionNarratives : sectionNarratives,
            actionPlan: actionPlan.isEmpty ? templateFallback.actionPlan : actionPlan
        )
        #else
        return nil
        #endif
    }

    // MARK: - Template Fallback

    private func generateTemplates(
        for context: ReportContext,
        promptContext: ReportPromptContext
    ) -> ReportNarratives {
        let days = context.days
        let goals = context.goals

        // Executive summary
        let stressValues = days.compactMap(\.stressScore)
        let sleepValues = days.compactMap(\.sleepHours)
        let stepValues = days.compactMap(\.steps)

        var summaryParts: [String] = []
        if !stressValues.isEmpty {
            let avg = Int(stressValues.reduce(0, +) / Double(stressValues.count))
            let trend = detectTrendDirection(stressValues)
            summaryParts.append("Your stress averaged \(avg)/100 and has been \(trend) over the period.")
        }
        if !sleepValues.isEmpty {
            let avg = sleepValues.reduce(0, +) / Double(sleepValues.count)
            let metGoal = sleepValues.filter { $0 >= goals.sleepGoalHours }.count
            summaryParts.append("Sleep averaged \(String(format: "%.1f", avg))h with \(metGoal) nights meeting your goal.")
        }
        if !stepValues.isEmpty {
            let avg = stepValues.reduce(0, +) / stepValues.count
            summaryParts.append("You averaged \(avg) steps per day.")
        }
        if summaryParts.isEmpty {
            summaryParts.append("Keep logging your wellness data to unlock deeper insights.")
        }

        let topWin = findTopWin(context: context)
        let topConcern = findTopConcern(context: context)

        let execSummary = ExecutiveSummaryNarrative(
            narrative: summaryParts.joined(separator: " "),
            topWin: topWin,
            topConcern: topConcern
        )

        // Section narratives
        var sectionNarratives: [String: SectionNarrative] = [:]
        if !stressValues.isEmpty {
            let avg = Int(stressValues.reduce(0, +) / Double(stressValues.count))
            sectionNarratives["stress"] = SectionNarrative(
                headline: "Stress averaged \(avg)/100",
                narrative: "Your stress score averaged \(avg) over 15 days, ranging from \(Int(stressValues.min() ?? 0)) to \(Int(stressValues.max() ?? 0))."
            )
        }
        if !days.compactMap(\.totalCalories).isEmpty {
            let avgCal = days.compactMap(\.totalCalories).reduce(0, +) / max(1, days.compactMap(\.totalCalories).count)
            sectionNarratives["nutrition"] = SectionNarrative(
                headline: "Averaging \(avgCal) kcal/day",
                narrative: "Calorie intake averaged \(avgCal) kcal against your \(goals.calorieGoal) kcal goal."
            )
        }
        if !sleepValues.isEmpty {
            let avg = sleepValues.reduce(0, +) / Double(sleepValues.count)
            sectionNarratives["sleep"] = SectionNarrative(
                headline: "Sleep at \(String(format: "%.1f", avg))h average",
                narrative: "You slept an average of \(String(format: "%.1f", avg)) hours against your \(String(format: "%.0f", goals.sleepGoalHours))h goal."
            )
        }
        if days.contains(where: { !$0.symptomNames.isEmpty }) {
            let symptomDayCount = days.filter { !$0.symptomNames.isEmpty }.count
            sectionNarratives["symptoms"] = SectionNarrative(
                headline: "Symptoms on \(symptomDayCount) days",
                narrative: "You logged symptoms on \(symptomDayCount) out of \(days.count) days."
            )
        }
        if !stepValues.isEmpty {
            let avg = stepValues.reduce(0, +) / stepValues.count
            sectionNarratives["activity"] = SectionNarrative(
                headline: "\(avg) steps/day average",
                narrative: "You averaged \(avg) steps per day against your \(goals.dailyStepsGoal) step goal."
            )
        }

        // Action plan (template)
        var actions: [ActionRecommendation] = []
        let proteinAvg = days.compactMap(\.totalProteinG).reduce(0, +) / max(1, Double(days.compactMap(\.totalProteinG).count))
        if proteinAvg > 0 && proteinAvg < Double(goals.proteinGoalGrams) * 0.8 {
            actions.append(ActionRecommendation(
                title: "Increase protein intake",
                rationale: "Protein averaged \(Int(proteinAvg))g, which is \(Int((1 - proteinAvg / Double(goals.proteinGoalGrams)) * 100))% below your \(goals.proteinGoalGrams)g goal.",
                domain: "nutrition"
            ))
        }
        if let avgSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count),
           avgSleep < goals.sleepGoalHours {
            actions.append(ActionRecommendation(
                title: "Prioritize more sleep",
                rationale: "You averaged \(String(format: "%.1f", avgSleep))h, below your \(String(format: "%.0f", goals.sleepGoalHours))h target.",
                domain: "sleep"
            ))
        }
        if !context.crossCorrelations.isEmpty {
            let top = context.crossCorrelations.first!
            actions.append(ActionRecommendation(
                title: "Watch your \(top.xName)-\(top.yName) link",
                rationale: "\(top.xName) and \(top.yName) show a notable association (r = \(String(format: "%.2f", top.spearmanR))).",
                domain: top.xDomain.rawValue
            ))
        }
        if actions.isEmpty {
            actions.append(ActionRecommendation(
                title: "Keep tracking consistently",
                rationale: "More data helps surface meaningful patterns. Keep logging daily.",
                domain: "cross"
            ))
        }

        return ReportNarratives(
            executiveSummary: execSummary,
            sectionNarratives: sectionNarratives,
            actionPlan: actions
        )
    }

    // MARK: - Prompt Builders

    private func buildExecutiveSummaryPrompt(promptContext: ReportPromptContext) -> String {
        """
        You are a wellness coach writing a summary for a health app called WellPlate.

        Here is the user's 15-day wellness data summary:
        \(promptContext.text)

        Write a 3-4 sentence executive summary. Reference specific numbers. \
        Use 'may suggest' framing. No medical claims. Mention the strongest positive habit \
        and the most actionable area for improvement.
        """
    }

    private func buildSectionNarrativePrompt(sectionName: String, promptContext: ReportPromptContext) -> String {
        """
        You are a wellness coach writing insight cards for a health app.

        Here is the user's 15-day data summary:
        \(promptContext.text)

        Write a punchy headline (max 50 chars) and a 1-2 sentence narrative for the \
        "\(sectionName)" section. Reference specific data points. Use 'may suggest' or \
        'appears linked' framing. No medical claims.
        """
    }

    private func buildActionPlanPrompt(promptContext: ReportPromptContext) -> String {
        """
        You are a wellness coach for a health app called WellPlate.

        Here is the user's 15-day data summary:
        \(promptContext.text)

        Generate 3-5 specific actionable recommendations ranked by potential impact. \
        Each must reference a specific data point from the summary. Use 'consider' and \
        'may help' framing. No medical advice.
        """
    }

    // MARK: - Helpers

    private func sectionHasData(_ section: String, context: ReportContext) -> Bool {
        switch section {
        case "stress":    return context.days.contains { $0.stressScore != nil }
        case "nutrition": return context.days.contains { $0.totalCalories != nil }
        case "sleep":     return context.days.contains { $0.sleepHours != nil }
        case "symptoms":  return context.days.contains { !$0.symptomNames.isEmpty }
        case "activity":  return context.days.contains { $0.steps != nil }
        case "cross":     return !context.crossCorrelations.isEmpty
        default:          return false
        }
    }

    private func detectTrendDirection(_ values: [Double]) -> String {
        guard values.count >= 3 else { return "steady" }
        let recent = Array(values.suffix(5))
        let isRising = zip(recent, recent.dropFirst()).allSatisfy { $0 < $1 }
        let isFalling = zip(recent, recent.dropFirst()).allSatisfy { $0 > $1 }
        if isRising { return "rising" }
        if isFalling { return "declining" }
        return "steady"
    }

    private func findTopWin(context: ReportContext) -> String {
        let days = context.days
        let goals = context.goals

        // Check water streak
        let waterMetDays = days.filter { ($0.waterGlasses ?? 0) >= goals.waterDailyCups }.count
        if waterMetDays >= 5 { return "Water goal met \(waterMetDays) of \(days.count) days" }

        // Check step streak
        let stepMetDays = days.filter { ($0.steps ?? 0) >= goals.dailyStepsGoal }.count
        if stepMetDays >= 5 { return "Step goal hit \(stepMetDays) of \(days.count) days" }

        // Check sleep
        let sleepMetDays = days.filter { ($0.sleepHours ?? 0) >= goals.sleepGoalHours }.count
        if sleepMetDays >= 5 { return "Sleep goal met \(sleepMetDays) nights" }

        return "Consistent data logging"
    }

    private func findTopConcern(context: ReportContext) -> String {
        let days = context.days
        let goals = context.goals

        let proteinAvg = days.compactMap(\.totalProteinG).reduce(0, +) / max(1, Double(days.compactMap(\.totalProteinG).count))
        if proteinAvg > 0 && proteinAvg < Double(goals.proteinGoalGrams) * 0.7 {
            return "Protein \(Int((1 - proteinAvg / Double(goals.proteinGoalGrams)) * 100))% below goal"
        }

        let sleepAvg = days.compactMap(\.sleepHours).reduce(0, +) / max(1, Double(days.compactMap(\.sleepHours).count))
        if sleepAvg > 0 && sleepAvg < goals.sleepGoalHours * 0.85 {
            return "Sleep averaging below target"
        }

        return "Room to improve consistency"
    }
}

// MARK: - Foundation Models Schemas (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _ReportExecutiveSummary {
    @Guide(description: "3-4 sentence narrative summary of the 15-day wellness period. Reference specific numbers. Use 'may suggest' framing. No medical claims.")
    var narrative: String
    @Guide(description: "Single strongest positive finding from the period, max 60 chars")
    var topWin: String
    @Guide(description: "Single most actionable improvement area, max 60 chars")
    var topConcern: String
}

@available(iOS 26, *)
@Generable
private struct _ReportSectionNarrative {
    @Guide(description: "Punchy headline for this section, max 50 chars, no medical claims")
    var headline: String
    @Guide(description: "1-2 sentence narrative. Reference specific data points. Use 'may suggest' or 'appears linked' framing.")
    var narrative: String
}

@available(iOS 26, *)
@Generable
private struct _ReportActionPlan {
    @Guide(description: "3-5 specific actionable recommendations ranked by potential impact")
    var recommendations: [_ReportActionRecommendation]
}

@available(iOS 26, *)
@Generable
private struct _ReportActionRecommendation {
    @Guide(description: "Short action title, max 50 chars, e.g. 'Prioritize 7.5h sleep'")
    var title: String
    @Guide(description: "1-2 sentences explaining why, referencing a specific data point")
    var rationale: String
    @Guide(description: "Wellness domain: stress, nutrition, sleep, activity, hydration, caffeine, symptoms, supplements, fasting, or mood")
    var domain: String
}
#endif
