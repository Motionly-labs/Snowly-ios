//
//  SkiDataUploadService.swift
//  Snowly
//
//  Orchestrates device registration and ski session upload.
//  Silently registers on first upload; retries once on 401.
//

import Foundation
import os

// MARK: - Upload State

enum UploadState: Equatable {
    case idle
    case uploading
    case success
    case error(String)

    static func == (lhs: UploadState, rhs: UploadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.uploading, .uploading), (.success, .success):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@Observable
@MainActor
final class SkiDataUploadService {
    private(set) var uploadState: UploadState = .idle

    var isUploading: Bool { uploadState == .uploading }

    var lastError: String? {
        if case .error(let message) = uploadState { return message }
        return nil
    }

    private let apiClient: any SkiDataAPIProviding
    private let channelService: SkiSessionChannelService?
    private var activeServerURL: String?

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "SkiDataUpload"
    )

    init(apiClient: some SkiDataAPIProviding, channelService: SkiSessionChannelService? = nil) {
        self.apiClient = apiClient
        self.channelService = channelService
    }

    func updateBaseURL(_ url: URL) {
        apiClient.updateBaseURL(url)
        activeServerURL = ServerCredentialService.normalizeURL(url.absoluteString)
    }

    func resetState() {
        uploadState = .idle
    }

    /// Silently registers the device if needed, then uploads the session.
    func upload(session: SkiSession, userId: String, displayName: String) async {
        guard activeServerURL != nil else {
            uploadState = .error(String(localized: "upload_error_no_server"))
            return
        }

        uploadState = .uploading
        debugConsole("Starting upload for session \(session.id.uuidString) userId=\(userId) server=\(activeServerURL ?? "<nil>")")
        Self.logger.info(
            "Starting upload for session \(session.id.uuidString, privacy: .public) userId=\(userId, privacy: .public) server=\(self.activeServerURL ?? "<nil>", privacy: .public)"
        )

        do {
            let credential = try await ensureCredentials(userId: userId, displayName: displayName)
            apiClient.setToken(credential.apiToken)

            let payload = buildPayload(session)
            debugConsole("Prepared upload payload for session \(payload.id) runs=\(payload.runs.count)")
            Self.logger.info(
                "Prepared upload payload for session \(payload.id, privacy: .public) runs=\(payload.runs.count, privacy: .public)"
            )

            if let channelService, channelService.isConnected {
                let result = await channelService.uploadSession(payload)
                if case .success = result {
                    debugConsole("Upload succeeded over channel for session \(payload.id)")
                    Self.logger.info("Upload succeeded over channel for session \(payload.id, privacy: .public)")
                    uploadState = .success
                    return
                }
                if case .failure(let error) = result {
                    debugConsole("Channel upload failed for session \(payload.id): \(String(describing: error)). Falling back to REST.")
                    Self.logger.error(
                        "Channel upload failed for session \(payload.id, privacy: .public): \(String(describing: error), privacy: .public). Falling back to REST."
                    )
                }
            }

            do {
                try await apiClient.uploadSession(payload, userId: credential.userId)
            } catch SkiDataAPIError.unauthorized {
                debugConsole("Upload unauthorized for session \(payload.id). Attempting reauthentication.")
                Self.logger.error(
                    "Upload unauthorized for session \(payload.id, privacy: .public). Attempting reauthentication."
                )
                let newToken = try await apiClient.reauthenticate(
                    userId: credential.userId,
                    deviceSecret: credential.deviceSecret
                )
                try ServerCredentialService.update(apiToken: newToken, forServerURL: credential.serverURL)
                apiClient.setToken(newToken)
                try await apiClient.uploadSession(payload, userId: credential.userId)
            }
            debugConsole("Upload succeeded over REST for session \(payload.id)")
            Self.logger.info("Upload succeeded over REST for session \(payload.id, privacy: .public)")
            uploadState = .success
        } catch {
            debugConsole("Upload failed for session \(session.id.uuidString): \(String(describing: error))")
            Self.logger.error(
                "Upload failed for session \(session.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            uploadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func ensureCredentials(userId: String, displayName: String) async throws -> ServerCredential {
        guard let serverURL = activeServerURL else {
            throw SkiDataAPIError.networkUnavailable
        }

        // 1. Check per-server credentials
        if let credential = ServerCredentialService.load(forServerURL: serverURL) {
            debugConsole("Using existing server credential for \(serverURL)")
            Self.logger.info("Using existing server credential for \(serverURL, privacy: .public)")
            return credential
        }

        // 2. Compatibility: migrate legacy global Keychain entry
        if let legacy = SnowlyUserKeychainService.load() {
            debugConsole("Migrating legacy credential into per-server storage for \(serverURL)")
            Self.logger.info("Migrating legacy credential into per-server storage for \(serverURL, privacy: .public)")
            let credential = ServerCredential(
                serverURL: serverURL,
                userId: legacy.userId,
                username: displayName,
                deviceSecret: legacy.deviceSecret,
                apiToken: legacy.apiToken
            )
            try ServerCredentialService.save(credential)
            SnowlyUserKeychainService.delete()
            return credential
        }

        // 3. Fallback: register on the fly (normally registration happens when adding a server)
        let deviceSecret = UUID().uuidString
        debugConsole("No credential found for \(serverURL). Registering user \(userId) before upload.")
        Self.logger.info(
            "No credential found for \(serverURL, privacy: .public). Registering user \(userId, privacy: .public) before upload."
        )
        let registration = try await apiClient.register(
            userId: userId,
            displayName: displayName,
            deviceSecret: deviceSecret
        )
        let credential = ServerCredential(
            serverURL: serverURL,
            userId: userId,
            username: registration.username,
            deviceSecret: deviceSecret,
            apiToken: registration.apiToken
        )
        try ServerCredentialService.save(credential)
        return credential
    }

    private func debugConsole(_ message: String) {
#if DEBUG
        print("[SkiDataUpload] \(message)")
#endif
    }

    private func buildPayload(_ session: SkiSession) -> SessionUploadPayload {
        let runs = (session.runs ?? []).compactMap { buildRunPayload($0) }
        return SessionUploadPayload(
            id: session.id.uuidString,
            startDate: session.startDate,
            endDate: session.endDate ?? session.startDate,
            totalDistance: session.totalDistance,
            totalVertical: session.totalVertical,
            maxSpeed: session.maxSpeed,
            runCount: session.runCount,
            noteTitle: session.noteTitle,
            noteBody: session.noteBody,
            runs: runs
        )
    }

    private func buildRunPayload(_ run: SkiRun) -> RunUploadPayload? {
        guard let endDate = run.endDate else { return nil }

        return RunUploadPayload(
            id: run.id.uuidString,
            startDate: run.startDate,
            endDate: endDate,
            distance: run.distance,
            verticalDrop: run.verticalDrop,
            maxSpeed: run.maxSpeed,
            averageSpeed: run.averageSpeed,
            activityType: serverActivityType(run.activityType),
            trackPoints: run.trackPoints
        )
    }

    private func serverActivityType(_ type: RunActivityType) -> String {
        switch type {
        case .skiing: return "skiing"
        case .lift:   return "chairlift"
        case .walk:   return "walk"
        case .idle:   return "idle"
        }
    }
}
