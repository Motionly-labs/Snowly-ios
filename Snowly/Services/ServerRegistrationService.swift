//
//  ServerRegistrationService.swift
//  Snowly
//
//  Registers the user on a target server when adding a new server profile.
//  Instantiated locally in ServerEditSheet — not a global service.
//

import Foundation

@Observable @MainActor
final class ServerRegistrationService {
    enum State: Equatable {
        case idle
        case registering
        case success
        case failed(String)
    }

    private(set) var state: State = .idle

    func register(serverBaseURL: URL, userId: String, displayName: String) async {
        state = .registering

        let deviceSecret = UUID().uuidString
        let apiBaseURL = serverBaseURL.appendingPathComponent("api/v1")
        let apiClient = SkiDataAPIClient(baseURL: apiBaseURL)

        do {
            let registration = try await apiClient.register(
                userId: userId,
                displayName: displayName,
                deviceSecret: deviceSecret
            )
            let credential = ServerCredential(
                serverURL: ServerCredentialService.normalizeURL(serverBaseURL.absoluteString),
                userId: userId,
                username: registration.username,
                deviceSecret: deviceSecret,
                apiToken: registration.apiToken
            )
            try ServerCredentialService.save(credential)
            state = .success
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
