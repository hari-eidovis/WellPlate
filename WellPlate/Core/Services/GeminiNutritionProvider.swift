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
            #if DEBUG
            print("┌─── ❌ GROQ PROVIDER ──────────────────────────────")
            print("│ Error: API key is missing or empty")
            print("└──────────────────────────────────────────────────")
            #endif
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
        print("┌─── 🤖 GROQ REQUEST ──────────────────────────────")
        print("│ Endpoint: POST \(url.absoluteString)")
        print("│ Model: \(modelProvider())")
        print("│ Timeout: \(timeoutProvider())s")
        print("│ Food: \"\(request.foodDescription)\"")
        print("│ Serving: \(servingText?.isEmpty == false ? servingText! : "not specified")")
        print("│ Body Size: \(urlRequest.httpBody?.count ?? 0) bytes")
        print("└──────────────────────────────────────────────────")
        #endif

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                print("┌─── ❌ GROQ ERROR ────────────────────────────────")
                print("│ Error: Non-HTTP response received")
                print("│ Latency: \(elapsed)")
                print("└──────────────────────────────────────────────────")
                #endif
                throw NutritionProviderError.invalidResponseShape
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let envelope = try? JSONDecoder().decode(GroqErrorEnvelope.self, from: data)
                #if DEBUG
                let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                print("┌─── ❌ GROQ ERROR ────────────────────────────────")
                print("│ Status: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
                print("│ Latency: \(elapsed)")
                if let errMsg = envelope?.error.message {
                    print("│ Groq Message: \(errMsg)")
                }
                if let rawBody = String(data: data, encoding: .utf8) {
                    let truncated = String(rawBody.prefix(300))
                    print("│ Raw Response: \(truncated)")
                }
                print("└──────────────────────────────────────────────────")
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
                print("┌─── ❌ GROQ ERROR ────────────────────────────────")
                print("│ Error: No choices or content in response")
                print("│ Latency: \(elapsed)")
                print("│ Raw Data: \(String(data: data, encoding: .utf8) ?? "<binary>")")
                print("└──────────────────────────────────────────────────")
                #endif
                throw NutritionProviderError.invalidResponseShape
            }

            let normalizedJSON = Self.stripCodeFencesIfNeeded(jsonText)
            guard let jsonData = normalizedJSON.data(using: .utf8) else {
                #if DEBUG
                print("┌─── ❌ GROQ ERROR ────────────────────────────────")
                print("│ Error: Could not convert model output to UTF-8")
                print("│ Raw Output: \(jsonText.prefix(200))")
                print("└──────────────────────────────────────────────────")
                #endif
                throw NutritionProviderError.invalidModelOutput
            }

            let payload = try JSONDecoder().decode(GroqNutritionPayload.self, from: jsonData)
            let result = Self.mapToNutritionalInfo(payload)

            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            print("┌─── ✅ GROQ RESPONSE ─────────────────────────────")
            print("│ Status: \(httpResponse.statusCode) OK")
            print("│ Latency: \(elapsed)")
            print("│ Response Size: \(data.count) bytes")
            print("│ ── Parsed Nutrition ──")
            print("│ Food: \(result.foodName)")
            print("│ Serving: \(result.servingSize ?? "N/A")")
            print("│ Calories: \(result.calories) kcal")
            print("│ Protein: \(String(format: "%.1f", result.protein))g")
            print("│ Carbs: \(String(format: "%.1f", result.carbs))g")
            print("│ Fat: \(String(format: "%.1f", result.fat))g")
            print("│ Fiber: \(String(format: "%.1f", result.fiber))g")
            if let confidence = result.confidence {
                print("│ Confidence: \(String(format: "%.0f%%", confidence * 100))")
            }
            print("└──────────────────────────────────────────────────")
            #endif

            return result
        } catch let error as NutritionProviderError {
            throw error
        } catch let urlError as URLError {
            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            print("┌─── ❌ GROQ NETWORK ERROR ────────────────────────")
            print("│ URLError Code: \(urlError.code.rawValue)")
            print("│ Description: \(urlError.localizedDescription)")
            print("│ Latency: \(elapsed)")
            if urlError.code == .timedOut {
                print("│ Note: Request exceeded \(timeoutProvider())s timeout")
            }
            print("└──────────────────────────────────────────────────")
            #endif
            if urlError.code == .timedOut {
                throw NutritionProviderError.timeout
            }
            throw NutritionProviderError.network(urlError)
        } catch {
            #if DEBUG
            let elapsed = String(format: "%.0fms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            print("┌─── ❌ GROQ UNEXPECTED ERROR ─────────────────────")
            print("│ Error: \(error.localizedDescription)")
            print("│ Type: \(type(of: error))")
            print("│ Latency: \(elapsed)")
            print("└──────────────────────────────────────────────────")
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
