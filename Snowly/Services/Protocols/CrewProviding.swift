//
//  CrewProviding.swift
//  Snowly
//
//  Protocol for crew management and location sharing.
//  Enables mock injection for testing.
//

import Foundation
import CoreLocation

@MainActor
protocol CrewProviding: AnyObject, Sendable {
    /// The currently active crew (nil if not in one).
    var activeCrew: Crew? { get }

    /// Latest locations of all crew members (excluding self).
    var memberLocations: [MemberLocation] { get }

    /// Active (non-expired) pins from crew members.
    var activePins: [CrewPin] { get }

    /// Whether the service is actively polling/uploading.
    var isActive: Bool { get }

    /// Whether the current user is the crew creator.
    var isHost: Bool { get }

    /// Device-local crew sync preferences.
    var syncPreferences: CrewSyncPreferences { get }

    /// Last successful crew sync timestamp.
    var lastSyncDate: Date? { get }

    /// Whether a manual sync is currently running.
    var isManualSyncInProgress: Bool { get }

    /// Last error for UI display.
    var lastError: String? { get }

    // Lifecycle
    func createCrew(name: String) async throws -> CrewInvite
    func joinCrew(token: String) async throws
    func leaveCrew() async throws
    func dissolveCrew() async throws

    // Invite
    func generateInvite() async throws -> CrewInvite

    // Location sync
    func startLocationSharing()
    func stopLocationSharing()
    func updateSyncPreferences(_ preferences: CrewSyncPreferences)
    func syncNow() async

    // Pins
    func dropPin(message: String, coordinate: CLLocationCoordinate2D?) async throws

    // User identity
    func configure(userId: String, displayName: String)
}
