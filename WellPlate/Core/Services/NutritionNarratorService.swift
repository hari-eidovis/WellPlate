import AVFoundation
import SwiftUI
import Combine

// MARK: - NutritionNarratorService
//
// Generates an AI coaching narrative from today's nutrition data and speaks it
// aloud via AVSpeechSynthesizer.
//
// Availability tiers:
//   iOS 26+  → FoundationModels on-device LLM generates the narrative.
//   iOS 18.1 → Deterministic template narrative + AVFoundation TTS.
//
// Note: DailyGoals is defined in GoalExpandableView.swift and already contains
// all macro goals including fiber — no extension needed.

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class NutritionNarratorService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: - Published State

    @Published var isSpeaking: Bool = false
    @Published var isGenerating: Bool = false
    /// True when only a default-quality voice is available; prompt user to download enhanced.
    @Published var showVoiceNudge: Bool = false

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var selectedVoice: AVSpeechSynthesisVoice?

    // MARK: - Init

    override init() {
        super.init()
        synthesizer.delegate = self
        selectedVoice = Self.pickBestVoice()
        showVoiceNudge = (selectedVoice?.quality == .default)
    }

    // MARK: - Public API

    /// Generates a nutrition narrative and speaks it.
    /// Second call while speaking → stops speech instead.
    func generateAndSpeak(nutrition: NutritionalInfo, goals: DailyGoals) async {
        guard !isSpeaking else { stop(); return }

        isGenerating = true
        defer { isGenerating = false }

        let narrative: String
        if #available(iOS 26, *) {
            narrative = (try? await generateWithFoundationModels(nutrition: nutrition, goals: goals))
                ?? templateNarrative(nutrition: nutrition, goals: goals)
        } else {
            narrative = templateNarrative(nutrition: nutrition, goals: goals)
        }

        HapticService.narratorStart()
        speakText(narrative)
    }

    /// Stops any active speech immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Foundation Models Generation (iOS 26+)

    @available(iOS 26, *)
    private func generateWithFoundationModels(
        nutrition: NutritionalInfo,
        goals: DailyGoals
    ) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = """
        You are a friendly, concise nutrition coach inside a health app called WellPlate.
        Write exactly 2–3 sentences coaching the user on their nutrition for today.
        Be specific with numbers. End with one small, actionable suggestion for tomorrow.

        Today's data:
        - Calories: \(nutrition.calories) kcal (goal: \(goals.calories) kcal)
        - Protein: \(Int(nutrition.protein))g (goal: \(goals.protein)g)
        - Carbs: \(Int(nutrition.carbs))g (goal: \(goals.carbs)g)
        - Fat: \(Int(nutrition.fat))g (goal: \(goals.fat)g)
        - Fiber: \(Int(nutrition.fiber))g (goal: \(goals.fiber)g)
        """
        let result = try await session.respond(
            to: prompt,
            generating: NutritionNarrative.self
        )
        return result.content.summary
        #else
        throw NarratorError.unsupported
        #endif
    }

    // MARK: - Template Fallback

    private func templateNarrative(nutrition: NutritionalInfo, goals: DailyGoals) -> String {
        let calorieDiff = nutrition.calories - goals.calories
        let calorieLine: String
        if calorieDiff > 100 {
            calorieLine = "You're \(calorieDiff) calories over your goal today."
        } else if calorieDiff < -100 {
            calorieLine = "You're \(abs(calorieDiff)) calories under your goal — consider a small snack."
        } else {
            calorieLine = "You're right on target with your calories today — great work."
        }

        let proteinLine: String
        let proteinPct = goals.protein > 0 ? (nutrition.protein / Double(goals.protein)) : 0
        if proteinPct >= 0.9 {
            proteinLine = "Protein is solid at \(Int(nutrition.protein))g."
        } else {
            let remaining = Int(Double(goals.protein) - nutrition.protein)
            proteinLine = "You still need \(remaining)g of protein — try adding eggs, chicken, or Greek yogurt."
        }

        let fiberLine = nutrition.fiber < 15
            ? "Fiber is low at \(Int(nutrition.fiber))g — add veggies or legumes tomorrow."
            : "Fiber intake looks good."

        return "\(calorieLine) \(proteinLine) \(fiberLine)"
    }

    // MARK: - Speech

    private func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
    }

    // MARK: - Voice Selection

    /// Returns the highest-quality English voice available: premium → enhanced → default.
    private static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        return englishVoices.first { $0.quality == .premium }
            ?? englishVoices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - AVSpeechSynthesizerDelegate (nonisolated — bridged back to MainActor)

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Generable Schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct NutritionNarrative {
    @Guide(description: "2–3 sentence coaching summary of today's nutrition, ending with one specific, actionable suggestion for tomorrow.")
    var summary: String
}
#endif

// MARK: - Errors

private enum NarratorError: Error {
    case unsupported
}
