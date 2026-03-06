//
//  CrewAPIProviding.swift
//  Snowly
//
//  Protocol for crew API client — enables mock injection for testing.
//

import Foundation

@MainActor
protocol CrewAPIProviding: Sendable {
    // Token
    func setToken(_ token: String)

    // Crew CRUD
    func createCrew(
        userId: String,
        displayName: String,
        crewName: String,
        avatarData: Data?
    ) async throws -> CreateCrewResponse

    func fetchCrew(id: String) async throws -> Crew
    func dissolveCrew(id: String) async throws

    // Membership
    func previewInvite(token: String) async throws -> CrewPreview
    func joinCrew(
        token: String,
        userId: String,
        displayName: String,
        avatarData: Data?
    ) async throws -> JoinCrewResponse

    func leaveCrew(crewId: String) async throws
    func kickMember(crewId: String, userId: String) async throws

    // Invite
    func regenerateInvite(crewId: String) async throws -> CrewInvite

    // Location
    func uploadLocation(crewId: String, location: LocationUpload) async throws
    func fetchLocations(
        crewId: String,
        since: Date?,
        etag: String?
    ) async throws -> LocationPollResult

    // Pins
    func createPin(crewId: String, pin: CrewPinUpload) async throws -> CrewPin
    func deletePin(crewId: String, pinId: String) async throws
}

/// Response from creating a new crew.
struct CreateCrewResponse: Codable, Sendable {
    let crew: Crew
    let invite: CrewInvite
    let memberToken: String
}

/// Response from joining a crew.
struct JoinCrewResponse: Codable, Sendable {
    let crew: Crew
    let memberToken: String
}

/// Result of polling member locations.
struct LocationPollResult: Sendable {
    let locations: [MemberLocation]?
    let pins: [CrewPin]?
    let crew: Crew?
    let membershipVersion: String?
    let etag: String?
    let pollInterval: TimeInterval
    let serverTimestamp: Date?
}
