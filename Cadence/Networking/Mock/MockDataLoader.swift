//
//  MockDataLoader.swift
//  WellPlate
//
//  Created by Claude on 16.02.2026.
//

import Foundation

// MARK: - Mock Data Error

enum MockDataError: Error {
    case fileNotFound(String)
    case decodingFailed(Error)

    var localizedDescription: String {
        switch self {
        case .fileNotFound(let filename):
            return """
            ❌ Mock data file not found: \(filename).json

            Expected location: WellPlate/Resources/MockData/\(filename).json

            Solutions:
            1. Create the file in Resources/MockData/
            2. Add it to Xcode project (must be in Copy Bundle Resources)
            3. Register a different mapping in MockResponseRegistry
            4. Check that MockData folder is added as folder reference (blue icon)
            """
        case .decodingFailed(let error):
            return """
            ❌ Failed to decode mock data: \(error.localizedDescription)

            Check that:
            1. JSON file is valid and well-formed
            2. JSON structure matches the expected Codable model
            3. Date formats are ISO8601 compatible
            """
        }
    }
}

// MARK: - Mock Data Loader

/// Utility for loading mock JSON data from the app bundle
class MockDataLoader {

    /// Load and decode mock data from JSON file
    /// - Parameters:
    ///   - filename: Filename without extension (e.g., "mock_users_list")
    ///   - bundle: Bundle to search (defaults to main bundle)
    /// - Returns: Decoded object of type T
    /// - Throws: MockDataError if file not found or decoding fails
    static func load<T: Decodable>(_ filename: String, bundle: Bundle = .main) throws -> T {
        WPLogger.network.debug("MockDataLoader loading: \(filename).json")

        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            let error = MockDataError.fileNotFound(filename)
            WPLogger.network.error("File not found in bundle: \(filename).json")
            throw error
        }

        let data = try Data(contentsOf: url)

        do {
            let decoder = JSONDecoder()

            // Configure decoder for common date formats
            decoder.dateDecodingStrategy = .iso8601

            // Optional: Set custom key decoding strategy
            // decoder.keyDecodingStrategy = .convertFromSnakeCase

            let decoded = try decoder.decode(T.self, from: data)
            WPLogger.network.info("Loaded \(filename).json ✅")
            return decoded
        } catch {
            let mockError = MockDataError.decodingFailed(error)
            WPLogger.network.error("Decode failed for \(filename).json — \(error)")
            throw mockError
        }
    }

    /// Load raw data from JSON file without decoding
    /// - Parameters:
    ///   - filename: Filename without extension
    ///   - bundle: Bundle to search (defaults to main bundle)
    /// - Returns: Raw Data from file
    /// - Throws: MockDataError.fileNotFound if file doesn't exist
    static func loadRawData(_ filename: String, bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            throw MockDataError.fileNotFound(filename)
        }
        return try Data(contentsOf: url)
    }
}
