import Foundation

final class GroqNutritionProvider: NutritionProvider {
    private let session: URLSession
    private let apiKeyProvider: () -> String?
    private let modelProvider: () -> String
    private let timeoutProvider: () -> TimeInterval

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { SecretsLoader.groqAPIKey },
        modelProvider: @escaping () -> String = { AppConfig.shared.groqModel },
        timeoutProvider: @escaping () -> TimeInterval = { AppConfig.shared.apiTimeout }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.timeoutProvider = timeoutProvider
    }

    func analyze(_ request: NutritionAnalysisRequest) async throws -> NutritionalInfo {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            WPLogger.nutrition.error("Groq API key is missing or empty")
            throw NutritionProviderError.missingAPIKey
        }

        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw NutritionProviderError.invalidURL
        }

        let servingText = request.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = """
        You are a nutrition analysis engine.
        Return strict JSON only with exactly these keys and value types:
        {
          "foodName": string,
          "servingSize": string,
          "calories": integer,
          "protein": number,
          "carbs": number,
          "fat": number,
          "fiber": number,
          "confidence": number
        }

        Rules:
        - No markdown, no explanation, no code fences.
        - confidence must be from 0.0 to 1.0.
        - values must be realistic for the provided serving.
        """
        let userPrompt = """
        Meal description: \(request.foodDescription)
        Serving size: \(servingText?.isEmpty == false ? servingText! : "unknown")
        """

        let body = GroqChatCompletionsRequest(
            model: modelProvider(),
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: 0.2,
            responseFormat: .init(type: "json_object")
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.timeoutInterval = timeoutProvider()
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        WPLogger.nutrition.block(emoji: "🤖", title: "GROQ REQUEST", lines: [
            "POST \(url.absoluteString)",
            "Model   : \(modelProvider())   Timeout: \(timeoutProvider())s",
            "Food    : \"\(request.foodDescription)\"",
            "Serving : \(servingText?.isEmpty == false ? servingText! : "not specified")",
            "Body    : \(urlRequest.httpBody?.count ?? 0) bytes"
        ])
        #endif

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                WPLogger.nutrition.block(emoji: "❌", title: "GROQ ERROR", lines: [
                    "Non-HTTP response received",
                    "Latency: \(elapsed)"
                ])
                #endif
                throw NutritionProviderError.invalidResponseShape
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let envelope = try? JSONDecoder().decode(GroqErrorEnvelope.self, from: data)
                #if DEBUG
                let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                var lines = [
                    "Status  : \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))",
                    "Latency : \(elapsed)"
                ]
                if let errMsg = envelope?.error.message { lines.append("Message : \(errMsg)") }
                if let raw = String(data: data, encoding: .utf8) { lines.append("Body    : \(String(raw.prefix(200)))") }
                WPLogger.nutrition.block(emoji: "❌", title: "GROQ ERROR", lines: lines)
                #endif
                throw NutritionProviderError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: envelope?.error.message
                )
            }

            let apiResponse = try JSONDecoder().decode(GroqChatCompletionsResponse.self, from: data)
            guard
                let choices = apiResponse.choices,
                let jsonText = choices.first?.message?.content
            else {
                #if DEBUG
                let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                WPLogger.nutrition.block(emoji: "❌", title: "GROQ ERROR", lines: [
                    "No choices or content in response",
                    "Latency : \(elapsed)",
                    "Raw     : \(String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>")"
                ])
                #endif
                throw NutritionProviderError.invalidResponseShape
            }

            let normalizedJSON = Self.stripCodeFencesIfNeeded(jsonText)
            guard let jsonData = normalizedJSON.data(using: .utf8) else {
                #if DEBUG
                WPLogger.nutrition.block(emoji: "❌", title: "GROQ ERROR", lines: [
                    "Could not convert model output to UTF-8",
                    "Output  : \(jsonText.prefix(200))"
                ])
                #endif
                throw NutritionProviderError.invalidModelOutput
            }

            let payload = try JSONDecoder().decode(GroqNutritionPayload.self, from: jsonData)
            let result = Self.mapToNutritionalInfo(payload)

            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            WPLogger.nutrition.block(emoji: "✅", title: "GROQ RESPONSE", lines: [
                "Status  : \(httpResponse.statusCode) OK   Latency: \(elapsed)   Size: \(data.count) bytes",
                "Food    : \(result.foodName)",
                "Serving : \(result.servingSize ?? "N/A")",
                "Calories: \(result.calories) kcal   Protein: \(String(format: "%.1f", result.protein))g",
                "Carbs   : \(String(format: "%.1f", result.carbs))g   Fat: \(String(format: "%.1f", result.fat))g   Fiber: \(String(format: "%.1f", result.fiber))g",
                result.confidence.map { "Confidence: \(String(format: "%.0f%%", $0 * 100))" } ?? "Confidence: n/a"
            ])
            #endif

            return result
        } catch let error as NutritionProviderError {
            throw error
        } catch let urlError as URLError {
            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            var lines = [
                "URLError \(urlError.code.rawValue) — \(urlError.localizedDescription)",
                "Latency : \(elapsed)"
            ]
            if urlError.code == .timedOut { lines.append("Note    : exceeded \(timeoutProvider())s timeout") }
            WPLogger.nutrition.block(emoji: "❌", title: "GROQ NETWORK ERROR", lines: lines)
            #endif
            if urlError.code == .timedOut {
                throw NutritionProviderError.timeout
            }
            throw NutritionProviderError.network(urlError)
        } catch {
            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            WPLogger.nutrition.block(emoji: "❌", title: "GROQ UNEXPECTED ERROR", lines: [
                "Error   : \(error.localizedDescription)",
                "Type    : \(type(of: error))",
                "Latency : \(elapsed)"
            ])
            #endif
            throw NutritionProviderError.invalidModelOutput
        }
    }

    private static func mapToNutritionalInfo(_ payload: GroqNutritionPayload) -> NutritionalInfo {
        let foodName = payload.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let servingSize = payload.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)

        return NutritionalInfo(
            foodName: foodName.isEmpty ? "Unknown meal" : foodName,
            servingSize: servingSize.isEmpty ? nil : servingSize,
            calories: max(0, min(payload.calories, 10_000)),
            protein: max(0, min(payload.protein, 1_000)),
            carbs: max(0, min(payload.carbs, 1_000)),
            fat: max(0, min(payload.fat, 1_000)),
            fiber: max(0, min(payload.fiber, 500)),
            confidence: payload.confidence.map { max(0, min($0, 1)) }
        )
    }

    private static func stripCodeFencesIfNeeded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let withoutPrefix = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        return withoutPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

typealias GeminiNutritionProvider = GroqNutritionProvider
