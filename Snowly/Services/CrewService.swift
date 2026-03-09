//
//  CrewService.swift
//  Snowly
//
//  Orchestrates crew lifecycle and real-time location sharing.
//  Depends on CrewAPIProviding (network) and LocationTrackingService (GPS).
//

import Foundation
import CoreLocation
import os

// MARK: - Service Error

enum CrewServiceError: LocalizedError {
    case notInCrew
    case notConfigured
    case invalidInvite
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .notInCrew:
            return String(localized: "crew_error_not_in_crew")
        case .notConfigured:
            return String(localized: "crew_error_not_authenticated")
        case .invalidInvite:
            return String(localized: "crew_error_invalid_invite")
        case .locationUnavailable:
            return String(localized: "crew_error_location_unavailable")
        }
    }
}

// MARK: - Crew Service

@Observable
@MainActor
final class CrewService: CrewProviding {

    // MARK: - Published State

    private(set) var activeCrew: Crew?
    private(set) var memberLocations: [MemberLocation] = []
    private(set) var activePins: [CrewPin] = []
    private(set) var unreadPinCount: Int = 0
    private(set) var focusRequestedPin: CrewPin?
    private(set) var isActive = false
    private(set) var syncPreferences = CrewSyncPreferencesStore.load()
    private(set) var lastSyncDate: Date?
    private(set) var isManualSyncInProgress = false
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let apiClient: any CrewAPIProviding
    private let locationService: LocationTrackingService

    // MARK: - Private State

    private var uploadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var userId: String = ""
    private var displayName: String = ""
    private var lastEtag: String?
    private var lastServerTimestamp: Date?
    private var consecutiveErrors = 0
    private var knownPinIds: Set<String> = []
    private var unreadPinIds: Set<String> = []

    /// Most recently received pin from another crew member (for notification).
    /// Reset to nil after being consumed by the notification service.
    private(set) var latestReceivedPin: CrewPin?
    /// Most recently detected membership change from server snapshots.
    /// Reset to nil after being consumed by the notification service.
    private(set) var latestMembershipEvent: CrewMembershipEvent?

    private static let maxConsecutiveErrors = 5
    private static let defaultInterval: TimeInterval = 5

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "CrewService"
    )

    // MARK: - Init

    init(
        apiClient: any CrewAPIProviding,
        locationService: LocationTrackingService
    ) {
        self.apiClient = apiClient
        self.locationService = locationService
    }

    // MARK: - Configuration

    func configure(userId: String, displayName: String) {
        self.userId = userId.lowercased()
        self.displayName = displayName
        restoreFromKeychain()
    }

    /// Restore memberToken from Keychain on launch and fetch crew state.
    private func restoreFromKeychain() {
        guard let creds = CrewKeychainService.load() else { return }

        // Credentials belong to a different user (e.g. app reinstalled) — discard.
        guard creds.userId.lowercased() == userId else {
            Self.logger.info("Keychain credentials belong to a different user, deleting")
            CrewKeychainService.delete()
            return
        }

        apiClient.setToken(creds.memberToken)
        Self.logger.info("Restored crew member token from Keychain")

        Task { [weak self] in
            guard let self else { return }
            do {
                let crew = try await self.apiClient.fetchCrew(id: creds.crewId)
                self.activeCrew = crew
                self.startLocationSharing()
                Self.logger.info("Restored active crew: \(crew.name, privacy: .public)")
            } catch {
                Self.logger.error("Failed to restore crew: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
            }
        }
    }

    var isHost: Bool {
        activeCrew?.creatorId == userId
    }

    // MARK: - Crew Lifecycle

    func createCrew(name: String) async throws -> CrewInvite {
        guard !userId.isEmpty else { throw CrewServiceError.notConfigured }

        let response = try await apiClient.createCrew(
            userId: userId,
            displayName: displayName,
            crewName: name,
            avatarData: nil
        )
        activeCrew = response.crew

        let credentials = CrewCredentials(
            memberToken: response.memberToken,
            crewId: response.crew.id,
            userId: userId
        )
        try CrewKeychainService.save(credentials)

        startLocationSharing()
        return response.invite
    }

    func joinCrew(token: String) async throws {
        guard !userId.isEmpty else { throw CrewServiceError.notConfigured }
        guard let inviteToken = DeepLinkHandler.inviteToken(from: token) else {
            throw CrewServiceError.invalidInvite
        }

        let response = try await apiClient.joinCrew(
            token: inviteToken,
            userId: userId,
            displayName: displayName,
            avatarData: nil
        )
        activeCrew = response.crew

        let credentials = CrewCredentials(
            memberToken: response.memberToken,
            crewId: response.crew.id,
            userId: userId
        )
        try CrewKeychainService.save(credentials)

        startLocationSharing()
    }

    func leaveCrew() async throws {
        guard let crew = activeCrew else { return }
        try await apiClient.leaveCrew(crewId: crew.id)
        cleanupAfterLeave()
    }

    func dissolveCrew() async throws {
        guard let crew = activeCrew else { return }
        try await apiClient.dissolveCrew(id: crew.id)
        cleanupAfterLeave()
    }

    func generateInvite() async throws -> CrewInvite {
        guard let crew = activeCrew else {
            throw CrewServiceError.notInCrew
        }
        return try await apiClient.regenerateInvite(crewId: crew.id)
    }

    func canKick(_ member: CrewMember) -> Bool {
        isHost && !member.isCreator
    }

    func kickMember(_ member: CrewMember) async throws {
        guard let crew = activeCrew else {
            throw CrewServiceError.notInCrew
        }
        guard canKick(member) else {
            throw CrewAPIError.forbidden(String(localized: "crew_error_no_permission"))
        }

        try await apiClient.kickMember(crewId: crew.id, userId: member.id)
        removeMemberLocally(userId: member.id)
    }

    // MARK: - Location Sharing

    func startLocationSharing() {
        guard activeCrew != nil else { return }
        stopLocationSharing()
        consecutiveErrors = 0
        lastError = nil
        guard syncPreferences.mode == .automatic else { return }

        if syncPreferences.shareLocationEnabled {
            startUploadLoop()
        }
        startPollLoop()
    }

    func stopLocationSharing() {
        uploadTask?.cancel()
        pollTask?.cancel()
        uploadTask = nil
        pollTask = nil
        isActive = false
        lastEtag = nil
        lastServerTimestamp = nil
        consecutiveErrors = 0
    }

    func updateSyncPreferences(_ preferences: CrewSyncPreferences) {
        let sanitized = preferences.sanitized
        guard sanitized != syncPreferences else { return }

        syncPreferences = sanitized
        CrewSyncPreferencesStore.save(sanitized)

        guard activeCrew != nil else { return }
        startLocationSharing()
    }

    func syncNow() async {
        guard let crew = activeCrew else { return }
        guard !isManualSyncInProgress else { return }

        isManualSyncInProgress = true
        defer { isManualSyncInProgress = false }

        await uploadCurrentLocationIfNeeded(for: crew)
        _ = await pollCrewUpdates(for: crew)
    }

    // MARK: - Server Configuration

    /// Switch the API client to a different server URL.
    func updateServerBaseURL(_ url: URL) {
        apiClient.updateBaseURL(url)
    }

    // MARK: - Upload Loop

    private func startUploadLoop() {
        uploadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let interval = self.automaticInterval

                if let crew = self.activeCrew {
                    await self.uploadCurrentLocationIfNeeded(for: crew)
                }

                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // MARK: - Poll Loop

    private func startPollLoop() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                var interval = self.automaticInterval

                if let crew = self.activeCrew {
                    interval = await self.pollCrewUpdates(for: crew)
                }

                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // MARK: - Pins

    func consumeLatestReceivedPin() {
        latestReceivedPin = nil
    }

    func consumeLatestMembershipEvent() {
        latestMembershipEvent = nil
    }

    func canManagePin(_ pin: CrewPin) -> Bool {
        pin.senderId == userId
    }

    func requestFocusOnLatestUnreadPin() {
        let unreadPins = activePins.filter { unreadPinIds.contains($0.id) && !$0.isExpired }
        guard let target = unreadPins.max(by: { $0.createdAt < $1.createdAt }) else { return }

        focusRequestedPin = target
        unreadPinIds.remove(target.id)
        unreadPinCount = unreadPinIds.count
    }

    func consumeFocusRequestedPin() {
        focusRequestedPin = nil
    }

    func dropPin(message: String, coordinate: CLLocationCoordinate2D? = nil) async throws {
        guard let crew = activeCrew else {
            throw CrewServiceError.notInCrew
        }
        guard let coord = coordinate ?? locationService.currentLocation else {
            throw CrewServiceError.locationUnavailable
        }

        let upload = CrewPinUpload(
            latitude: coord.latitude,
            longitude: coord.longitude,
            message: message
        )
        let pin = try await apiClient.createPin(crewId: crew.id, pin: upload)
        activePins.append(pin)
        knownPinIds.insert(pin.id)
    }

    func resendPin(_ pin: CrewPin) async throws {
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        try await dropPin(message: pin.message, coordinate: coordinate)
    }

    func deletePin(_ pin: CrewPin) async throws {
        guard let crew = activeCrew else {
            throw CrewServiceError.notInCrew
        }
        guard canManagePin(pin) else {
            throw CrewAPIError.forbidden(String(localized: "crew_error_no_permission"))
        }

        try await apiClient.deletePin(crewId: crew.id, pinId: pin.id)

        activePins.removeAll { $0.id == pin.id }
        knownPinIds.remove(pin.id)
        unreadPinIds.remove(pin.id)
        unreadPinCount = unreadPinIds.count
        if focusRequestedPin?.id == pin.id {
            focusRequestedPin = nil
        }
    }

    private func processPins(_ pins: [CrewPin]) {
        let serverPins = pins.filter { !$0.isExpired }
        let serverPinIds = Set(serverPins.map(\.id))

        // Keep locally-created pins that the server hasn't echoed back yet
        let localOnly = activePins.filter { $0.senderId == userId && !serverPinIds.contains($0.id) && !$0.isExpired }
        let merged = serverPins + localOnly

        // New pins from others become unread and trigger a notification.
        let newPinsFromOthers = serverPins.filter { !knownPinIds.contains($0.id) && $0.senderId != userId }
        if !newPinsFromOthers.isEmpty {
            newPinsFromOthers.forEach { unreadPinIds.insert($0.id) }
            unreadPinCount = unreadPinIds.count
            // Server returns pins newest-first; notify using the newest unseen pin.
            latestReceivedPin = newPinsFromOthers.first
        }

        activePins = merged
        knownPinIds = Set(merged.map(\.id))
        unreadPinIds = unreadPinIds.intersection(knownPinIds)
        unreadPinCount = unreadPinIds.count
    }

    private func applyCrewSnapshot(_ snapshot: Crew) {
        let previousCrew = activeCrew
        activeCrew = snapshot

        guard let previousCrew else { return }

        let previousById = Dictionary(uniqueKeysWithValues: previousCrew.members.map { ($0.id, $0) })
        let currentById = Dictionary(uniqueKeysWithValues: snapshot.members.map { ($0.id, $0) })

        let joined = snapshot.members.first { previousById[$0.id] == nil && $0.id != userId }
        let left = previousCrew.members.first { currentById[$0.id] == nil && $0.id != userId }

        if let joined {
            latestMembershipEvent = CrewMembershipEvent(
                kind: .joined,
                memberId: joined.id,
                displayName: joined.displayName,
                occurredAt: joined.joinedAt
            )
        } else if let left {
            latestMembershipEvent = CrewMembershipEvent(
                kind: .left,
                memberId: left.id,
                displayName: left.displayName,
                occurredAt: .now
            )
        }
    }

    // MARK: - Helpers

    private var automaticInterval: TimeInterval {
        let crewInterval = activeCrew.map { TimeInterval($0.locationUpdateIntervalSeconds) } ?? Self.defaultInterval
        let userInterval = TimeInterval(syncPreferences.intervalSeconds)
        return max(crewInterval, userInterval)
    }

    private func pollInterval(for serverInterval: TimeInterval) -> TimeInterval {
        max(serverInterval, TimeInterval(syncPreferences.intervalSeconds))
    }

    private func uploadCurrentLocationIfNeeded(for crew: Crew) async {
        guard syncPreferences.shareLocationEnabled else { return }
        guard let location = buildLocationUpload() else { return }

        do {
            try await apiClient.uploadLocation(
                crewId: crew.id,
                location: location
            )
            markSuccess()
        } catch {
            handleError(error, context: "location upload")
        }
    }

    private func pollCrewUpdates(for crew: Crew) async -> TimeInterval {
        do {
            let result = try await apiClient.fetchLocations(
                crewId: crew.id,
                since: lastServerTimestamp,
                etag: lastEtag
            )

            if let crew = result.crew {
                applyCrewSnapshot(crew)
            }

            if let locations = result.locations {
                memberLocations = locations.filter { $0.userId != userId }
            }

            if let pins = result.pins {
                processPins(pins)
            }
            activePins = activePins.filter { !$0.isExpired }

            lastEtag = result.etag
            if let ts = result.serverTimestamp {
                lastServerTimestamp = ts
            }

            markSuccess()
            return pollInterval(for: result.pollInterval)
        } catch {
            handleError(error, context: "location poll")
            return automaticInterval
        }
    }

    private func buildLocationUpload() -> LocationUpload? {
        guard let coord = locationService.currentLocation else { return nil }
        // CoreLocation returns -1 for course/accuracy when unavailable;
        // server validates course 0..360 and accuracy >= 0.
        let course = locationService.currentCourse
        let accuracy = locationService.currentAccuracy
        return LocationUpload(
            latitude: coord.latitude,
            longitude: coord.longitude,
            altitude: locationService.currentAltitude,
            speed: locationService.currentSpeed,
            course: course >= 0 ? course : 0,
            accuracy: accuracy >= 0 ? accuracy : 0,
            timestamp: .now,
            batteryLevel: nil,
            activityType: nil
        )
    }

    private func markSuccess() {
        if !isActive { isActive = true }
        consecutiveErrors = 0
        lastError = nil
        lastSyncDate = .now
    }

    private func handleError(_ error: Error, context: String) {
        consecutiveErrors += 1
        let message = "\(context): \(error.localizedDescription)"
        lastError = message
        Self.logger.error(
            "[\(context, privacy: .public)] failed (\(self.consecutiveErrors, privacy: .public)x): \(error.localizedDescription, privacy: .public)"
        )

        if consecutiveErrors >= Self.maxConsecutiveErrors {
            isActive = false
            lastError = String(localized: "crew_error_connection_lost")
        }
    }

    private func cleanupAfterLeave() {
        stopLocationSharing()
        activeCrew = nil
        memberLocations = []
        activePins = []
        knownPinIds = []
        unreadPinIds = []
        unreadPinCount = 0
        focusRequestedPin = nil
        lastSyncDate = nil
        isManualSyncInProgress = false
        latestReceivedPin = nil
        latestMembershipEvent = nil
        CrewKeychainService.delete()
    }

    private func removeMemberLocally(userId removedUserId: String) {
        guard let crew = activeCrew else { return }

        let updatedMembers = crew.members.filter { $0.id != removedUserId }
        activeCrew = Crew(
            id: crew.id,
            name: crew.name,
            creatorId: crew.creatorId,
            createdAt: crew.createdAt,
            memberCount: updatedMembers.count,
            maxMembers: crew.maxMembers,
            locationUpdateIntervalSeconds: crew.locationUpdateIntervalSeconds,
            members: updatedMembers
        )
        memberLocations.removeAll { $0.userId == removedUserId }
    }
}
