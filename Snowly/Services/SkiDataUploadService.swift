//
//  SkiDataUploadService.swift
//  Snowly
//
//  Orchestrates device registration and ski session upload.
//  Silently registers on first upload; retries once on 401.
//

import Foundation
import os

@Observable
@MainActor
final class SkiDataUploadService {
    private(set) var isUploading = false
    private(set) var lastError: String?

    private let apiClient: any SkiDataAPIProviding

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "SkiDataUpload"
    )

    init(apiClient: some SkiDataAPIProviding) {
        self.apiClient = apiClient
    }

    func updateBaseURL(_ url: URL) {
        apiClient.updateBaseURL(url)
    }

    /// Silently registers the device if needed, then uploads the session.
    func upload(session: SkiSession, userId: String, displayName: String) async {
        isUploading = true
        lastError = nil
        defer { isUploading = false }

        do {
            let credentials = try await ensureCredentials(userId: userId, displayName: displayName)
            apiClient.setToken(credentials.apiToken)

            let payload = buildPayload(session)

            do {
                try await apiClient.uploadSession(payload)
            } catch SkiDataAPIError.unauthorized {
                let newToken = try await apiClient.reauthenticate(
                    userId: credentials.userId,
                    deviceSecret: credentials.deviceSecret
                )
                let updated = SnowlyUserCredentials(
                    userId: credentials.userId,
                    deviceSecret: credentials.deviceSecret,
                    apiToken: newToken
                )
                try SnowlyUserKeychainService.save(updated)
                apiClient.setToken(newToken)
                try await apiClient.uploadSession(payload)
            }
        } catch {
            Self.logger.error("Upload failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func ensureCredentials(userId: String, displayName: String) async throws -> SnowlyUserCredentials {
        if let existing = SnowlyUserKeychainService.load() {
            return existing
        }

        let deviceSecret = UUID().uuidString
        let apiToken = try await apiClient.register(
            userId: userId,
            displayName: displayName,
            deviceSecret: deviceSecret
        )
        let credentials = SnowlyUserCredentials(
            userId: userId,
            deviceSecret: deviceSecret,
            apiToken: apiToken
        )
        try SnowlyUserKeychainService.save(credentials)
        return credentials
    }

    private func buildPayload(_ session: SkiSession) -> SessionUploadPayload {
        let runs = session.runs.compactMap { buildRunPayload($0) }
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
