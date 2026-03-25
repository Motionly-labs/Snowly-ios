//
//  SkiDataAPIClientTests.swift
//  SnowlyTests
//
//  Tests for SkiDataAPIClient: URL construction, auth headers,
//  and error handling via URLProtocol stubbing.
//

import Testing
import Foundation
@testable import Snowly

// MARK: - URLProtocol Stub

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
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

// MARK: - Helpers

@MainActor
private func makeClient() -> SkiDataAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    return SkiDataAPIClient(
        baseURL: URL(string: "https://test.snowly.app")!,
        session: session
    )
}

// MARK: - Tests

@Suite(.serialized)
struct SkiDataAPIClientTests {

    @Test @MainActor func register_postsToCorrectPath() async throws {
        StubURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/users/register") == true)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            // No auth header for register
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let body = """
            {"userId":"u1","username":"Test#1234","displayName":"Test","tag":"1234","apiToken":"test-token-123"}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }

        let client = makeClient()
        let registration = try await client.register(
            userId: "u1",
            displayName: "Test",
            deviceSecret: "secret"
        )
        #expect(registration.apiToken == "test-token-123")
        #expect(registration.username == "Test#1234")
    }

    @Test @MainActor func reauthenticate_postsToCorrectPath() async throws {
        StubURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/users/reauthenticate") == true)
            #expect(request.httpMethod == "POST")

            let body = """
            {"apiToken":"new-token"}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }

        let client = makeClient()
        let token = try await client.reauthenticate(userId: "u1", deviceSecret: "sec")
        #expect(token == "new-token")
    }

    @Test @MainActor func uploadSession_constructsCorrectURL() async throws {
        StubURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/snowly/users/user-abc/sessions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let client = makeClient()
        client.setToken("my-token")

        let payload = SessionUploadPayload(
            id: "s1",
            startDate: Date(),
            endDate: Date(),
            totalDistance: 100,
            totalVertical: 50,
            maxSpeed: 10,
            runCount: 1,
            noteTitle: nil,
            noteBody: nil,
            runs: []
        )

        try await client.uploadSession(payload, userId: "user-abc")
    }

    @Test @MainActor func uploadSession_throws401AsUnauthorized() async {
        StubURLProtocol.requestHandler = { request in
            let body = """
            {"error":{"code":"unauthorized","message":"Invalid token"}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }

        let client = makeClient()
        client.setToken("expired-token")

        let payload = SessionUploadPayload(
            id: "s2",
            startDate: Date(),
            endDate: Date(),
            totalDistance: 0,
            totalVertical: 0,
            maxSpeed: 0,
            runCount: 0,
            noteTitle: nil,
            noteBody: nil,
            runs: []
        )

        do {
            try await client.uploadSession(payload, userId: "user-x")
            Issue.record("Expected unauthorized error")
        } catch let error as SkiDataAPIError {
            if case .unauthorized = error {
                // Expected
            } else {
                Issue.record("Expected .unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test @MainActor func uploadSession_throwsWithoutToken() async {
        let client = makeClient()
        // Don't set token

        let payload = SessionUploadPayload(
            id: "s3",
            startDate: Date(),
            endDate: Date(),
            totalDistance: 0,
            totalVertical: 0,
            maxSpeed: 0,
            runCount: 0,
            noteTitle: nil,
            noteBody: nil,
            runs: []
        )

        do {
            try await client.uploadSession(payload, userId: "user-y")
            Issue.record("Expected unauthorized error")
        } catch let error as SkiDataAPIError {
            if case .unauthorized = error {
                // Expected: no token set
            } else {
                Issue.record("Expected .unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test @MainActor func register_throwsOnServerError() async {
        StubURLProtocol.requestHandler = { request in
            let body = """
            {"error":{"code":"internal_error","message":"Something broke"}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, body)
        }

        let client = makeClient()

        do {
            _ = try await client.register(userId: "u1", displayName: "Test", deviceSecret: "s")
            Issue.record("Expected httpError")
        } catch let error as SkiDataAPIError {
            if case .httpError(let code, let msg) = error {
                #expect(code == 500)
                #expect(msg == "Something broke")
            } else {
                Issue.record("Expected .httpError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test @MainActor func updateBaseURL_changesURL() {
        let client = makeClient()
        let newURL = URL(string: "https://new.snowly.app")!
        client.updateBaseURL(newURL)
        #expect(client.baseURL == newURL)
    }
}
