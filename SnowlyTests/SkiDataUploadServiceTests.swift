//
//  SkiDataUploadServiceTests.swift
//  SnowlyTests
//
//  Tests for SkiDataUploadService: credential management, upload flow,
//  and 401 retry logic.
//

import Testing
import Foundation
@testable import Snowly

// MARK: - Mock API Client

@MainActor
final class MockSkiDataAPIClient: SkiDataAPIProviding {
    var baseURL: URL = URL(string: "https://test.snowly.app")!
    var currentToken: String?

    // Call tracking
    var registerCallCount = 0
    var registerArgs: [(userId: String, displayName: String, deviceSecret: String)] = []
    var reauthenticateCallCount = 0
    var reauthenticateArgs: [(userId: String, deviceSecret: String)] = []
    var uploadCallCount = 0
    var uploadArgs: [(payload: SessionUploadPayload, userId: String)] = []

    // Response configuration
    var registerResult: Result<String, Error> = .success("mock-api-token")
    var reauthenticateResult: Result<String, Error> = .success("mock-new-token")
    var uploadError: Error?
    var uploadErrorOnFirstCallOnly = false

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func setToken(_ token: String) {
        currentToken = token
    }

    func register(userId: String, displayName: String, deviceSecret: String) async throws -> String {
        registerCallCount += 1
        registerArgs.append((userId, displayName, deviceSecret))
        return try registerResult.get()
    }

    func reauthenticate(userId: String, deviceSecret: String) async throws -> String {
        reauthenticateCallCount += 1
        reauthenticateArgs.append((userId, deviceSecret))
        return try reauthenticateResult.get()
    }

    func uploadSession(_ payload: SessionUploadPayload, userId: String) async throws {
        uploadCallCount += 1
        uploadArgs.append((payload, userId))
        if let error = uploadError {
            if uploadErrorOnFirstCallOnly && uploadCallCount > 1 {
                return
            }
            throw error
        }
    }
}

// MARK: - Test Helpers

@MainActor
private func makeSession() -> SkiSession {
    let session = SkiSession()
    session.startDate = Date(timeIntervalSince1970: 1700000000)
    session.endDate = Date(timeIntervalSince1970: 1700010000)
    session.totalDistance = 5000
    session.totalVertical = 1000
    session.maxSpeed = 20.0
    session.runCount = 3
    return session
}

// MARK: - Tests

@Suite(.serialized)
struct SkiDataUploadServiceTests {

    @Test @MainActor func initialState_isIdle() {
        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)

        #expect(service.uploadState == .idle)
        #expect(service.isUploading == false)
        #expect(service.lastError == nil)
    }

    @Test @MainActor func upload_registersWhenNoCredentials() async {
        // Ensure no stored credentials
        SnowlyUserKeychainService.delete()

        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "user-123", displayName: "Test User")

        #expect(client.registerCallCount == 1)
        #expect(client.registerArgs.first?.userId == "user-123")
        #expect(client.registerArgs.first?.displayName == "Test User")
        #expect(client.uploadCallCount == 1)
        #expect(service.uploadState == .success)

        // Clean up
        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func upload_usesExistingCredentials() async {
        // Pre-store credentials
        let creds = SnowlyUserCredentials(
            userId: "stored-user",
            deviceSecret: "stored-secret",
            apiToken: "stored-token"
        )
        try! SnowlyUserKeychainService.save(creds)

        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "stored-user", displayName: "Stored")

        #expect(client.registerCallCount == 0, "Should not register when credentials exist")
        #expect(client.currentToken == "stored-token")
        #expect(client.uploadCallCount == 1)
        #expect(client.uploadArgs.first?.userId == "stored-user")
        #expect(service.uploadState == .success)

        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func upload_passesUserIdToUploadSession() async {
        let creds = SnowlyUserCredentials(
            userId: "user-456",
            deviceSecret: "secret-456",
            apiToken: "token-456"
        )
        try! SnowlyUserKeychainService.save(creds)

        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "user-456", displayName: "User")

        #expect(client.uploadArgs.first?.userId == "user-456")

        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func upload_retriesOn401() async {
        let creds = SnowlyUserCredentials(
            userId: "retry-user",
            deviceSecret: "retry-secret",
            apiToken: "old-token"
        )
        try! SnowlyUserKeychainService.save(creds)

        let client = MockSkiDataAPIClient()
        client.uploadError = SkiDataAPIError.unauthorized
        client.uploadErrorOnFirstCallOnly = true
        client.reauthenticateResult = .success("refreshed-token")

        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "retry-user", displayName: "Retry")

        #expect(client.reauthenticateCallCount == 1)
        #expect(client.reauthenticateArgs.first?.userId == "retry-user")
        #expect(client.reauthenticateArgs.first?.deviceSecret == "retry-secret")
        #expect(client.uploadCallCount == 2, "Should retry upload after reauthentication")
        #expect(client.currentToken == "refreshed-token")
        #expect(service.uploadState == .success)

        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func upload_setsErrorStateOnFailure() async {
        SnowlyUserKeychainService.delete()

        let client = MockSkiDataAPIClient()
        client.registerResult = .failure(SkiDataAPIError.networkUnavailable)

        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "fail-user", displayName: "Fail")

        #expect(service.uploadState != .idle)
        #expect(service.uploadState != .uploading)
        #expect(service.uploadState != .success)
        #expect(service.lastError != nil)
        #expect(service.isUploading == false)

        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func upload_setsErrorWhenReauthFails() async {
        let creds = SnowlyUserCredentials(
            userId: "reauth-fail",
            deviceSecret: "secret",
            apiToken: "token"
        )
        try! SnowlyUserKeychainService.save(creds)

        let client = MockSkiDataAPIClient()
        client.uploadError = SkiDataAPIError.unauthorized
        client.reauthenticateResult = .failure(SkiDataAPIError.httpError(statusCode: 403, message: "Forbidden"))

        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "reauth-fail", displayName: "Fail")

        #expect(client.reauthenticateCallCount == 1)
        #expect(client.uploadCallCount == 1, "Should not retry when reauthentication fails")
        #expect(service.lastError != nil)

        SnowlyUserKeychainService.delete()
    }

    @Test @MainActor func resetState_returnsToIdle() {
        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)

        service.resetState()
        #expect(service.uploadState == .idle)
    }

    @Test @MainActor func updateBaseURL_delegatesToClient() {
        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)

        let newURL = URL(string: "https://new.snowly.app")!
        service.updateBaseURL(newURL)

        #expect(client.baseURL == newURL)
    }
}
