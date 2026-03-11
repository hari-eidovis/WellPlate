import Foundation

struct GroqChatCompletionsRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

struct GroqChatCompletionsResponse: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let message: Message?
    }

    struct Message: Decodable {
        let content: String?
    }
}

struct GroqErrorEnvelope: Decodable {
    let error: APIErrorBody

    struct APIErrorBody: Decodable {
        let message: String?
    }
}

struct GroqNutritionPayload: Decodable {
    let foodName: String
    let servingSize: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let confidence: Double?
}
