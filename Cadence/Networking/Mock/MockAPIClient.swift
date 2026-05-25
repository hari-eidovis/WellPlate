//
//  MockAPIClient.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Mock implementation of APIClient for offline development and testing
/// Returns predefined JSON data from bundle instead of making network requests
class MockAPIClient: APIClientProtocol {
    static let shared = MockAPIClient()

    private init() {
        WPLogger.network.debug("MockAPIClient initialized — serving bundle JSON")
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String]? = nil,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        WPLogger.network.block(emoji: "🎭", title: "MOCK REQUEST", lines: [
            "\(method.rawValue) \(url.absoluteString)",
            headers.map { "Headers: \($0)" } ?? "Headers: none",
            body.flatMap { String(data: $0, encoding: .utf8) }.map { "Body: \($0.prefix(200))" } ?? "Body: none"
        ])

        // Simulate network delay for realistic testing
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Get mock filename from registry
        guard let mockFileName = MockResponseRegistry.shared.mockFile(for: url, method: method) else {
            WPLogger.network.warning("No mock mapping found for \(url.path)")
            throw APIError.noData
        }

        do {
            let result: T = try MockDataLoader.load(mockFileName)
            WPLogger.network.info("Mock response served: \(mockFileName).json")
            return result
        } catch {
            WPLogger.network.error("Failed to load mock data: \(error.localizedDescription)")
            throw APIError.noData
        }
    }

    func requestVoid(
        url: URL,
        method: HTTPMethod,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws {
        WPLogger.network.debug("Mock void: \(method.rawValue) \(url.absoluteString)")
        // For void responses, just simulate delay and return
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        WPLogger.network.info("Mock void request completed")
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
}
