import XCTest
@testable import WellPlate

final class GroqNutritionProviderTests: XCTestCase {
    private final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.handler = nil
    }

    func testAnalyzeSuccessParsesStructuredJSON() async throws {
        let session = makeSession()
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        let payloadText = "{\"foodName\":\"Paneer Rice\",\"servingSize\":\"1 bowl\",\"calories\":480,\"protein\":18.5,\"carbs\":52.0,\"fat\":18.0,\"fiber\":4.1,\"confidence\":0.91}"
        let responseJSON = """
        {
          "choices": [
            {
              "message": {
                "content": "\(payloadText)"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let provider = GroqNutritionProvider(
            session: session,
            apiKeyProvider: { "test-key" },
            modelProvider: { "llama-3.3-70b-versatile" },
            timeoutProvider: { 5 }
        )

        let result = try await provider.analyze(.init(foodDescription: "paneer rice", servingSize: "1 bowl"))
        XCTAssertEqual(result.foodName, "Paneer Rice")
        XCTAssertEqual(result.calories, 480)
        XCTAssertEqual(result.protein, 18.5, accuracy: 0.001)
        XCTAssertEqual(result.confidence, 0.91, accuracy: 0.001)
    }

    func testAnalyzeThrowsInvalidModelOutputForMalformedJSON() async {
        let session = makeSession()
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        let responseJSON = """
        {
          "choices": [
            {
              "message": {
                "content": "not-json"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let provider = GroqNutritionProvider(
            session: session,
            apiKeyProvider: { "test-key" },
            modelProvider: { "llama-3.3-70b-versatile" },
            timeoutProvider: { 5 }
        )

        do {
            _ = try await provider.analyze(.init(foodDescription: "meal"))
            XCTFail("Expected invalidModelOutput")
        } catch let error as NutritionProviderError {
            guard case .invalidModelOutput = error else {
                XCTFail("Expected invalidModelOutput, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnalyzeThrowsRequestFailedForNon2xx() async {
        let session = makeSession()
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

        let responseJSON = """
        {
          "error": {
            "message": "Invalid API key"
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let provider = GroqNutritionProvider(
            session: session,
            apiKeyProvider: { "test-key" },
            modelProvider: { "llama-3.3-70b-versatile" },
            timeoutProvider: { 5 }
        )

        do {
            _ = try await provider.analyze(.init(foodDescription: "meal"))
            XCTFail("Expected requestFailed")
        } catch let error as NutritionProviderError {
            guard case .requestFailed(let statusCode, let message) = error else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "Invalid API key")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnalyzeThrowsTimeoutForTimedOutRequest() async {
        let session = makeSession()

        MockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        let provider = GroqNutritionProvider(
            session: session,
            apiKeyProvider: { "test-key" },
            modelProvider: { "llama-3.3-70b-versatile" },
            timeoutProvider: { 5 }
        )

        do {
            _ = try await provider.analyze(.init(foodDescription: "meal"))
            XCTFail("Expected timeout")
        } catch let error as NutritionProviderError {
            guard case .timeout = error else {
                XCTFail("Expected timeout, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
