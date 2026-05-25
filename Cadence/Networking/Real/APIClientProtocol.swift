//
//  APIClientProtocol.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// MARK: - API Error Types

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)
}

// MARK: - Empty Response for 204 No Content

struct EmptyResponse: Codable {}

// MARK: - Protocol Definition

protocol APIClientProtocol {
    // MARK: - Generic Requests

    /// Generic request with decodable response
    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    /// Request with no response (void) - for 204 No Content, DELETE, etc.
    func requestVoid(
        url: URL,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?
    ) async throws

    // MARK: - Convenience Methods (with response)

    func get<T: Decodable>(
        url: URL,
        headers: [String: String]?,
        responseType: T.Type
    ) async throws -> T

    func post<T: Decodable>(
        url: URL,
        headers: [String: String]?,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    func put<T: Decodable>(
        url: URL,
        headers: [String: String]?,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    func delete<T: Decodable>(
        url: URL,
        headers: [String: String]?,
        responseType: T.Type
    ) async throws -> T

    func patch<T: Decodable>(
        url: URL,
        headers: [String: String]?,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    // MARK: - Void Variants (no response expected)

    /// DELETE request with no response body
    func deleteVoid(
        url: URL,
        headers: [String: String]?
    ) async throws

    /// PUT request with no response body
    func putVoid(
        url: URL,
        headers: [String: String]?,
        body: Data?
    ) async throws

    // MARK: - Helper Methods

    /// Encode a Swift object to JSON Data
    func encodeBody<T: Encodable>(_ body: T) throws -> Data
}
