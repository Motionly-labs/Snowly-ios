//
//  UserProfile.swift
//  Snowly
//
//  User preferences and season bests. Synced via CloudKit.
//  Device-specific settings (healthKitEnabled, hasCompletedOnboarding)
//  live in DeviceSettings (local-only store).
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID = UUID()
    var displayName: String = ""
    var preferredUnits: UnitSystem

    // All-time personal bests (single session records)
    var seasonBestMaxSpeed: Double = 0      // m/s
    var seasonBestVertical: Double = 0      // meters
    var seasonBestDistance: Double = 0      // meters

    /// Daily activity goal in minutes (default: 4 hours).
    var dailyGoalMinutes: Double = 240

    /// Avatar photo stored as binary data (max ~100KB after compression).
    @Attribute(.externalStorage) var avatarData: Data?

    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        displayName: String = "",
        preferredUnits: UnitSystem = UnitSystem.metric,
        seasonBestMaxSpeed: Double = 0,
        seasonBestVertical: Double = 0,
        seasonBestDistance: Double = 0,
        dailyGoalMinutes: Double = 240,
        avatarData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredUnits = preferredUnits
        self.seasonBestMaxSpeed = seasonBestMaxSpeed
        self.seasonBestVertical = seasonBestVertical
        self.seasonBestDistance = seasonBestDistance
        self.dailyGoalMinutes = dailyGoalMinutes
        self.avatarData = avatarData
        self.createdAt = createdAt
    }
}
