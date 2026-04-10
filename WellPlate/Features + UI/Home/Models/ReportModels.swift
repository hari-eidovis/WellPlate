import Foundation

// MARK: - Report State

enum ReportState {
    case idle
    case generating(progress: Double)
    case ready(ReportData)
    case error(String)
}

// MARK: - ReportData (final output consumed by view)

struct ReportData {
    let context: ReportContext
    let narratives: ReportNarratives
    let generatedAt: Date
}

// MARK: - ReportContext

struct ReportContext {
    let days: [WellnessDaySummary]
    let goals: UserGoalsSnapshot
    let availableVitals: Set<VitalMetric>
    let foodSymptomLinks: [FoodSymptomLink]
    let crossCorrelations: [CrossCorrelation]
    let interventionResults: [InterventionResult]
    let experimentSummaries: [ExperimentSummary]
    let topFoods: [(name: String, count: Int, totalCalories: Int)]
    let perSupplementAdherence: [(name: String, rate: Double)]
    let dataQualityNote: String
}

// MARK: - ReportNarratives

struct ReportNarratives {
    let executiveSummary: ExecutiveSummaryNarrative
    let sectionNarratives: [String: SectionNarrative]
    let actionPlan: [ActionRecommendation]
}

struct ExecutiveSummaryNarrative {
    let narrative: String
    let topWin: String
    let topConcern: String
}

struct SectionNarrative {
    let headline: String
    let narrative: String
}

struct ActionRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let rationale: String
    let domain: String
}

// MARK: - ReportPromptContext

struct ReportPromptContext {
    let text: String
}

// MARK: - FoodSymptomLink

enum FoodSymptomClassification: String {
    case potentialTrigger
    case potentialProtective
    case neutral
}

struct FoodSymptomLink: Identifiable {
    let id = UUID()
    let symptomName: String
    let foodName: String
    let symptomDayCount: Int
    let clearDayCount: Int
    let symptomDayAppearances: Int
    let clearDayAppearances: Int
    let ratio: Double
    let classification: FoodSymptomClassification
}

// MARK: - CrossCorrelation

struct CrossCorrelation: Identifiable {
    let id = UUID()
    let xName: String
    let yName: String
    let xDomain: WellnessDomain
    let yDomain: WellnessDomain
    let spearmanR: Double
    let ciLow: Double
    let ciHigh: Double
    let pairedDays: Int
    let isSignificant: Bool
    let scatterPoints: [(x: Double, y: Double)]
}

// MARK: - InterventionResult

struct InterventionResult: Identifiable {
    let id = UUID()
    let resetType: String
    let sessionCount: Int
    let avgPreStress: Double
    let avgPostStress: Double
    let avgDelta: Double
    let hasMeasurableData: Bool
}

// MARK: - ExperimentSummary

struct ExperimentSummary: Identifiable {
    let id = UUID()
    let name: String
    let hypothesis: String?
    let interventionType: String
    let baselineAvg: Double?
    let experimentAvg: Double?
    let delta: Double?
    let ciLow: Double?
    let ciHigh: Double?
    let isComplete: Bool
}
