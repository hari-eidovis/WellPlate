//
//  APIClient.swift
//  WellPlate
//
//  Updated by Claude on 16.02.2026.
//

import Foundation

class APIClient: APIClientProtocol {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String]? = nil,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        #if DEBUG
        let requestId = UUID().uuidString.prefix(8)
        let startTime = CFAbsoluteTimeGetCurrent()
        logRequest(id: String(requestId), method: method, url: url, headers: headers, body: body)
        #endif

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                logError(id: String(requestId), method: method, url: url, elapsed: CFAbsoluteTimeGetCurrent() - startTime, error: .invalidResponse)
                #endif
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8)
                let apiError = APIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
                #if DEBUG
                logError(id: String(requestId), method: method, url: url, elapsed: CFAbsoluteTimeGetCurrent() - startTime, error: apiError, statusCode: httpResponse.statusCode, responseBody: errorMessage)
                #endif
                throw apiError
            }

            #if DEBUG
            logResponse(id: String(requestId), method: method, url: url, statusCode: httpResponse.statusCode, dataSize: data.count, elapsed: CFAbsoluteTimeGetCurrent() - startTime)
            #endif

            do {
                let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                return decodedResponse
            } catch {
                #if DEBUG
                logDecodingError(id: String(requestId), type: T.self, error: error, rawBody: String(data: data, encoding: .utf8))
                #endif
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            #if DEBUG
            logError(id: String(requestId), method: method, url: url, elapsed: CFAbsoluteTimeGetCurrent() - startTime, error: .networkError(error))
            #endif
            throw APIError.networkError(error)
        }
    }

    func requestVoid(
        url: URL,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws {
        // For void responses, we make the request but don't decode a response
        let _: EmptyResponse = try await request(
            url: url,
            method: method,
            headers: headers,
            body: body,
            responseType: EmptyResponse.self
        )
    }

    // MARK: - Convenience Methods

    func get<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(url: url, method: .get, headers: headers, responseType: responseType)
    }

    func post<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(url: url, method: .post, headers: headers, body: body, responseType: responseType)
    }

    func put<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(url: url, method: .put, headers: headers, body: body, responseType: responseType)
    }

    func delete<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(url: url, method: .delete, headers: headers, responseType: responseType)
    }

    func patch<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await request(url: url, method: .patch, headers: headers, body: body, responseType: responseType)
    }

    // MARK: - Void Variants

    func deleteVoid(
        url: URL,
        headers: [String: String]? = nil
    ) async throws {
        try await requestVoid(url: url, method: .delete, headers: headers, body: nil)
    }

    func putVoid(
        url: URL,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws {
        try await requestVoid(url: url, method: .put, headers: headers, body: body)
    }

    // MARK: - Helper Methods

    func encodeBody<T: Encodable>(_ body: T) throws -> Data {
        try JSONEncoder().encode(body)
    }

    // MARK: - Structured Logging (DEBUG only)

    #if DEBUG
    private func logRequest(id: String, method: HTTPMethod, url: URL, headers: [String: String]?, body: Data?) {
        var lines: [String] = []
        lines.append("┌─── 📤 API REQUEST [\(id)] ────────────────────────")
        lines.append("│ \(method.rawValue) \(url.absoluteString)")
        lines.append("│ Host: \(url.host ?? "unknown")")
        lines.append("│ Path: \(url.path)")
        if let query = url.query, !query.isEmpty {
            lines.append("│ Query: \(query)")
        }
        if let headers, !headers.isEmpty {
            lines.append("│ Headers:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let displayValue = Self.redactSensitiveHeader(key: key, value: value)
                lines.append("│   \(key): \(displayValue)")
            }
        }
        if let body {
            let bodyPreview = Self.truncatedBodyPreview(body, maxLength: 500)
            lines.append("│ Body (\(body.count) bytes):")
            for line in bodyPreview.components(separatedBy: "\n").prefix(10) {
                lines.append("│   \(line)")
            }
        }
        lines.append("└──────────────────────────────────────────────────")
        print(lines.joined(separator: "\n"))
    }

    private func logResponse(id: String, method: HTTPMethod, url: URL, statusCode: Int, dataSize: Int, elapsed: CFAbsoluteTime) {
        let emoji = (200...299).contains(statusCode) ? "✅" : "⚠️"
        let latency = String(format: "%.0fms", elapsed * 1000)
        var lines: [String] = []
        lines.append("┌─── \(emoji) API RESPONSE [\(id)] ──────────────────────")
        lines.append("│ \(method.rawValue) \(url.path) → \(statusCode)")
        lines.append("│ Latency: \(latency)")
        lines.append("│ Body Size: \(Self.formattedByteCount(dataSize))")
        lines.append("└──────────────────────────────────────────────────")
        print(lines.joined(separator: "\n"))
    }

    private func logError(
        id: String,
        method: HTTPMethod,
        url: URL,
        elapsed: CFAbsoluteTime,
        error: APIError,
        statusCode: Int? = nil,
        responseBody: String? = nil
    ) {
        let latency = String(format: "%.0fms", elapsed * 1000)
        var lines: [String] = []
        lines.append("┌─── ❌ API ERROR [\(id)] ──────────────────────────")
        lines.append("│ \(method.rawValue) \(url.path)")
        lines.append("│ Latency: \(latency)")
        lines.append("│ Error: \(Self.errorDescription(error))")
        if let statusCode {
            lines.append("│ Status: \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))")
        }
        if let responseBody, !responseBody.isEmpty {
            let truncated = String(responseBody.prefix(300))
            lines.append("│ Response Body:")
            for line in truncated.components(separatedBy: "\n").prefix(6) {
                lines.append("│   \(line)")
            }
        }
        lines.append("└──────────────────────────────────────────────────")
        print(lines.joined(separator: "\n"))
    }

    private func logDecodingError<T>(id: String, type: T.Type, error: Error, rawBody: String?) {
        var lines: [String] = []
        lines.append("┌─── 🔴 DECODING ERROR [\(id)] ────────────────────")
        lines.append("│ Target Type: \(String(describing: T.self))")
        lines.append("│ Error: \(error.localizedDescription)")
        if let decodingError = error as? DecodingError {
            lines.append("│ Detail: \(Self.decodingErrorDetail(decodingError))")
        }
        if let rawBody {
            let truncated = String(rawBody.prefix(300))
            lines.append("│ Raw Body Preview:")
            for line in truncated.components(separatedBy: "\n").prefix(6) {
                lines.append("│   \(line)")
            }
        }
        lines.append("└──────────────────────────────────────────────────")
        print(lines.joined(separator: "\n"))
    }

    // MARK: - Formatting Helpers

    private static func redactSensitiveHeader(key: String, value: String) -> String {
        let sensitiveKeys = ["authorization", "x-api-key", "api-key", "token", "cookie"]
        guard sensitiveKeys.contains(key.lowercased()) else { return value }
        guard value.count > 10 else { return "****" }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private static func truncatedBodyPreview(_ data: Data, maxLength: Int) -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes binary>"
        }
        if string.count <= maxLength { return string }
        return String(string.prefix(maxLength)) + "… (\(string.count) chars total)"
    }

    private static func formattedByteCount(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
    }

    private static func errorDescription(_ error: APIError) -> String {
        switch error {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Non-HTTP response received"
        case .noData: return "No data in response"
        case .decodingError(let inner): return "Decoding failed: \(inner.localizedDescription)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "no message")"
        case .networkError(let inner): return "Network error: \(inner.localizedDescription)"
        }
    }

    private static func decodingErrorDetail(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx):
            return "Missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let ctx):
            return "Type mismatch for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let ctx):
            return "Null value for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx):
            return "Corrupted data at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
    #endif
}
