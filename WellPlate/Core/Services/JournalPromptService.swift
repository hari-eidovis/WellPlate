import Foundation
import SwiftUI
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - JournalPromptService
//
// Stateless prompt generator — no ModelContext or bindContext needed.
// All context (mood, stress level) is passed in via generatePrompt() parameters.

@MainActor
final class JournalPromptService: ObservableObject {

    @Published var currentPrompt: String?
    @Published var promptCategory: String?
    @Published var isGenerating: Bool = false

    /// The calendar day for which the current prompt was generated.
    private var promptDay: Date?

    // MARK: - Public API

    func generatePrompt(mood: MoodOption?, stressLevel: String?) async {
        // Only generate once per calendar day — prevents shuffling on tab switches.
        let today = Calendar.current.startOfDay(for: Date())
        if let promptDay, promptDay == today, currentPrompt != nil {
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        if #available(iOS 26, *) {
            if let result = await generateWithFoundationModels(mood: mood, stressLevel: stressLevel) {
                currentPrompt = result.prompt
                promptCategory = result.category
                promptDay = today
                return
            }
        }

        // Template fallback
        let result = templatePrompt(mood: mood, stressLevel: stressLevel)
        currentPrompt = result.prompt
        promptCategory = result.category
        promptDay = today
    }

    // MARK: - Foundation Models (iOS 26+)

    @available(iOS 26, *)
    private func generateWithFoundationModels(mood: MoodOption?, stressLevel: String?) async -> (prompt: String, category: String)? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            WPLogger.home.info("JournalPromptService: Foundation Models not available — using template")
            return nil
        }

        let promptText = buildFoundationModelsPrompt(mood: mood, stressLevel: stressLevel)

        do {
            let session = LanguageModelSession()
            let result = try await session.respond(to: promptText, generating: _JournalPromptSchema.self)
            return (prompt: result.content.prompt, category: result.content.category)
        } catch {
            WPLogger.home.warning("JournalPromptService: Foundation Models failed — \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private func buildFoundationModelsPrompt(mood: MoodOption?, stressLevel: String?) -> String {
        let moodDesc = mood.map { "\($0.emoji) \($0.label)" } ?? "unknown"
        let stressDesc = stressLevel ?? "unknown"
        let timeDesc = TimeOfDay.current.rawValue

        return """
        Generate a warm, non-clinical journal prompt for a wellness app.
        The user is feeling \(moodDesc). It's \(timeDesc). Their stress level is \(stressDesc).
        The prompt should encourage gentle self-reflection, not problem-solving.
        Keep it to 1–2 sentences. No medical language.
        """
    }

    // MARK: - Template Fallback

    private func templatePrompt(mood: MoodOption?, stressLevel: String?) -> (prompt: String, category: String) {
        let tier = MoodTier(from: mood)
        let time = TimeOfDay.current
        let bucket = Self.templates[tier]?[time] ?? Self.templates[.neutral]?[.morning] ?? []

        guard !bucket.isEmpty else {
            return ("What's on your mind today?", "reflection")
        }

        // Exclude last-used index to prevent consecutive repeats
        let lastKey = "journalLastPromptIndex_\(tier.rawValue)_\(time.rawValue)"
        let lastIndex = UserDefaults.standard.integer(forKey: lastKey)

        var candidates = Array(bucket.indices)
        if candidates.count > 1 {
            candidates.removeAll { $0 == lastIndex }
        }

        // Prefer category based on stress level
        let preferredCategory: String? = {
            switch stressLevel?.lowercased() {
            case "high", "very high": return ["awareness", "intention"].randomElement()
            case "excellent", "good": return "gratitude"
            default: return nil
            }
        }()

        let chosen: Int
        if let pref = preferredCategory,
           let preferred = candidates.first(where: { bucket[$0].category == pref }) {
            chosen = preferred
        } else {
            chosen = candidates.randomElement() ?? 0
        }

        UserDefaults.standard.set(chosen, forKey: lastKey)
        return (bucket[chosen].prompt, bucket[chosen].category)
    }
}

// MARK: - Foundation Models Schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct _JournalPromptSchema {
    @Guide(description: "A warm, specific 1–2 sentence journal prompt. No medical language. Encourage reflection, not fixing.")
    var prompt: String

    @Guide(description: "Single-word category: gratitude, reflection, awareness, or intention")
    var category: String
}
#endif

// MARK: - Internal Enums

private enum MoodTier: String, CaseIterable {
    case low, neutral, high

    init(from mood: MoodOption?) {
        switch mood {
        case .awful, .bad: self = .low
        case .good, .great: self = .high
        default: self = .neutral
        }
    }
}

private enum TimeOfDay: String, CaseIterable {
    case morning, afternoon, evening

    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        default:      return .evening
        }
    }
}

// MARK: - Template Library (~50 prompts across mood × time buckets)

private typealias Prompt = (prompt: String, category: String)

private extension JournalPromptService {
    static let templates: [MoodTier: [TimeOfDay: [Prompt]]] = [
        .low: [
            .morning: [
                ("What's one small thing you can look forward to today?", "intention"),
                ("If you could give yourself permission for one thing today, what would it be?", "awareness"),
                ("What does your body need most right now?", "awareness"),
                ("Name one person who makes things feel a little lighter. What do you appreciate about them?", "gratitude"),
                ("What's one tiny step you could take today — even if it feels insignificant?", "intention")
            ],
            .afternoon: [
                ("How has today surprised you — even in a small way?", "reflection"),
                ("What would it feel like to let go of one expectation you had this morning?", "awareness"),
                ("What's been the hardest part of today so far? What got you through it?", "reflection"),
                ("If a good friend were with you right now, what would you want them to know?", "awareness"),
                ("What's one moment today that was okay, even if just briefly?", "gratitude")
            ],
            .evening: [
                ("What carried you through today, even on a hard day?", "gratitude"),
                ("What do you wish you had more of today — and how might you create a little of it tomorrow?", "intention"),
                ("What emotion showed up most today? Where did you feel it in your body?", "awareness"),
                ("What's one thing you did today that took courage, even if no one else noticed?", "reflection"),
                ("If tomorrow could be even 10% easier, what would need to be different?", "intention")
            ]
        ],
        .neutral: [
            .morning: [
                ("What's one thing you're hoping for today?", "intention"),
                ("What does a good day look like for you right now?", "reflection"),
                ("What's something you've been putting off that might feel good to start?", "awareness"),
                ("Who or what are you quietly grateful for today?", "gratitude"),
                ("What's one thing you want to pay attention to today?", "awareness")
            ],
            .afternoon: [
                ("How does today compare to how you expected it to go?", "reflection"),
                ("What's been the most meaningful part of your day so far?", "gratitude"),
                ("What's something you noticed today that you usually overlook?", "awareness"),
                ("What conversation or interaction stood out today?", "reflection"),
                ("What would you do differently if you could restart this morning?", "reflection")
            ],
            .evening: [
                ("What's one thing from today you want to remember?", "gratitude"),
                ("What challenged you today — and what did that reveal about you?", "awareness"),
                ("What's something you're still thinking about from today?", "reflection"),
                ("Did you show up the way you wanted to today? What worked, what didn't?", "reflection"),
                ("What are you most looking forward to tomorrow?", "intention")
            ]
        ],
        .high: [
            .morning: [
                ("What are three things you're genuinely grateful for right now?", "gratitude"),
                ("What's making you feel good today? Can you name it?", "gratitude"),
                ("What intention do you want to carry into today?", "intention"),
                ("What's something you've been building toward that feels close?", "reflection"),
                ("Who in your life deserves a moment of appreciation today?", "gratitude")
            ],
            .afternoon: [
                ("What's been the highlight of today so far?", "gratitude"),
                ("What small moment today made you smile or feel at ease?", "gratitude"),
                ("What's something you're proud of from this week?", "reflection"),
                ("How are you different today compared to a month ago?", "awareness"),
                ("What's something you'd tell your past self that would have helped?", "reflection")
            ],
            .evening: [
                ("What made today worth it?", "gratitude"),
                ("What did you learn about yourself today?", "awareness"),
                ("What's one thing you did today that aligned with who you want to be?", "reflection"),
                ("What are you grateful for that you almost took for granted today?", "gratitude"),
                ("How did you take care of yourself today — even in a small way?", "gratitude")
            ]
        ]
    ]
}
