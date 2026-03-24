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
    var registerResult: Result<ServerRegistrationResult, Error> = .success(
        ServerRegistrationResult(
            userId: "user",
            username: "User#1234",
            displayName: "User",
            tag: "1234",
            apiToken: "mock-api-token"
        )
    )
    var registerResults: [Result<ServerRegistrationResult, Error>] = []
    var reauthenticateResult: Result<String, Error> = .success("mock-new-token")
    var uploadError: Error?
    var uploadErrorOnFirstCallOnly = false

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    func setToken(_ token: String) {
        currentToken = token
    }

    func register(userId: String, displayName: String, deviceSecret: String) async throws -> ServerRegistrationResult {
        registerCallCount += 1
        registerArgs.append((userId, displayName, deviceSecret))
        if !registerResults.isEmpty {
            return try registerResults.removeFirst().get()
        }
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

    func updateProfile(userId: String, displayName: String) async throws -> ServerUserIdentity {
        ServerUserIdentity(userId: userId, username: "\(displayName)#1234", displayName: displayName, tag: "1234")
    }
}

// MARK: - Test Helpers

private let testServerURL = URL(string: "https://test.snowly.app")!
private let testServerNormalized = ServerCredentialService.normalizeURL(testServerURL.absoluteString)

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

@MainActor
private func makeServiceWithBaseURL(client: MockSkiDataAPIClient) -> SkiDataUploadService {
    let service = SkiDataUploadService(apiClient: client)
    service.updateBaseURL(testServerURL)
    return service
}

private func cleanUpCredentials() {
    ServerCredentialService.delete(forServerURL: testServerNormalized)
    SnowlyUserKeychainService.delete()
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
        cleanUpCredentials()

        let client = MockSkiDataAPIClient()
        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        client.registerResult = .success(
            ServerRegistrationResult(
                userId: "user-123",
                username: "Test User#1234",
                displayName: "Test User",
                tag: "1234",
                apiToken: "mock-api-token"
            )
        )
        await service.upload(session: session, userId: "user-123", displayName: "Test User")

        #expect(client.registerCallCount == 1)
        #expect(client.registerArgs.first?.userId == "user-123")
        #expect(client.registerArgs.first?.displayName == "Test User")
        #expect(client.uploadCallCount == 1)
        #expect(service.uploadState == .success)

        cleanUpCredentials()
    }

    @Test @MainActor func upload_usesExistingCredentials() async {
        cleanUpCredentials()

        let credential = ServerCredential(
            serverURL: testServerNormalized,
            userId: "stored-user",
            username: "Stored#1234",
            deviceSecret: "stored-secret",
            apiToken: "stored-token"
        )
        try! ServerCredentialService.save(credential)

        let client = MockSkiDataAPIClient()
        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "stored-user", displayName: "Stored")

        #expect(client.registerCallCount == 0, "Should not register when credentials exist")
        #expect(client.currentToken == "stored-token")
        #expect(client.uploadCallCount == 1)
        #expect(client.uploadArgs.first?.userId == "stored-user")
        #expect(service.uploadState == .success)

        cleanUpCredentials()
    }

    @Test @MainActor func upload_passesUserIdToUploadSession() async {
        cleanUpCredentials()

        let credential = ServerCredential(
            serverURL: testServerNormalized,
            userId: "user-456",
            username: "User#1234",
            deviceSecret: "secret-456",
            apiToken: "token-456"
        )
        try! ServerCredentialService.save(credential)

        let client = MockSkiDataAPIClient()
        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "user-456", displayName: "User")

        #expect(client.uploadArgs.first?.userId == "user-456")

        cleanUpCredentials()
    }

    @Test @MainActor func upload_retriesOn401() async {
        cleanUpCredentials()

        let credential = ServerCredential(
            serverURL: testServerNormalized,
            userId: "retry-user",
            username: "Retry#1234",
            deviceSecret: "retry-secret",
            apiToken: "old-token"
        )
        try! ServerCredentialService.save(credential)

        let client = MockSkiDataAPIClient()
        client.uploadError = SkiDataAPIError.unauthorized
        client.uploadErrorOnFirstCallOnly = true
        client.reauthenticateResult = .success("refreshed-token")

        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "retry-user", displayName: "Retry")

        #expect(client.reauthenticateCallCount == 1)
        #expect(client.reauthenticateArgs.first?.userId == "retry-user")
        #expect(client.reauthenticateArgs.first?.deviceSecret == "retry-secret")
        #expect(client.uploadCallCount == 2, "Should retry upload after reauthentication")
        #expect(client.currentToken == "refreshed-token")
        #expect(service.uploadState == .success)

        cleanUpCredentials()
    }

    @Test @MainActor func upload_setsErrorStateOnFailure() async {
        cleanUpCredentials()

        let client = MockSkiDataAPIClient()
        client.registerResult = .failure(SkiDataAPIError.networkUnavailable)

        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "fail-user", displayName: "Fail")

        #expect(service.uploadState != .idle)
        #expect(service.uploadState != .uploading)
        #expect(service.uploadState != .success)
        #expect(service.lastError != nil)
        #expect(service.isUploading == false)

        cleanUpCredentials()
    }

    @Test @MainActor func upload_setsErrorWhenReauthFails() async {
        cleanUpCredentials()

        let credential = ServerCredential(
            serverURL: testServerNormalized,
            userId: "reauth-fail",
            username: "Fail#1234",
            deviceSecret: "secret",
            apiToken: "token"
        )
        try! ServerCredentialService.save(credential)

        let client = MockSkiDataAPIClient()
        client.uploadError = SkiDataAPIError.unauthorized
        client.reauthenticateResult = .failure(SkiDataAPIError.httpError(statusCode: 403, message: "Forbidden"))

        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "reauth-fail", displayName: "Fail")

        #expect(client.reauthenticateCallCount == 1)
        #expect(client.uploadCallCount == 1, "Should not retry when reauthentication fails")
        #expect(service.lastError != nil)

        cleanUpCredentials()
    }

    @Test @MainActor func upload_failsWithNoServer() async {
        let client = MockSkiDataAPIClient()
        let service = SkiDataUploadService(apiClient: client)
        let session = makeSession()

        await service.upload(session: session, userId: "user", displayName: "User")

        #expect(service.lastError != nil)
        #expect(client.uploadCallCount == 0)
    }

    @Test @MainActor func upload_migratesLegacyCredentials() async {
        cleanUpCredentials()

        // Store legacy global credentials
        let legacy = SnowlyUserCredentials(
            userId: "legacy-user",
            deviceSecret: "legacy-secret",
            apiToken: "legacy-token"
        )
        try! SnowlyUserKeychainService.save(legacy)

        let client = MockSkiDataAPIClient()
        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "legacy-user", displayName: "Legacy")

        // Should have migrated — not re-registered
        #expect(client.registerCallCount == 0)
        #expect(client.currentToken == "legacy-token")
        #expect(client.uploadCallCount == 1)
        #expect(service.uploadState == .success)

        // Legacy entry should be deleted
        #expect(SnowlyUserKeychainService.load() == nil)
        // Per-server entry should exist
        #expect(ServerCredentialService.load(forServerURL: testServerNormalized) != nil)

        cleanUpCredentials()
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

    @Test @MainActor func upload_usesServerAssignedUsernameWhenRegistering() async {
        cleanUpCredentials()

        let client = MockSkiDataAPIClient()
        client.registerResults = [
            .success(
                ServerRegistrationResult(
                    userId: "user-123",
                    username: "Taken#4821",
                    displayName: "Taken",
                    tag: "4821",
                    apiToken: "resolved-token"
                )
            )
        ]

        let service = makeServiceWithBaseURL(client: client)
        let session = makeSession()

        await service.upload(session: session, userId: "user-123", displayName: "Taken")

        #expect(client.registerCallCount == 1)
        #expect(client.registerArgs.first?.displayName == "Taken")
        #expect(ServerCredentialService.load(forServerURL: testServerNormalized)?.username == "Taken#4821")
        #expect(service.uploadState == .success)

        cleanUpCredentials()
    }
}
