//
//  UserProfile.swift
//  Snowly
//
//  User preferences and personal bests. Synced via CloudKit.
//  Device-specific settings (healthKitEnabled, hasCompletedOnboarding)
//  live in DeviceSettings (local-only store).
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var preferredUnits: UnitSystem = UnitSystem.metric

    // All-time personal bests (single session records)
    var personalBestMaxSpeed: Double = 0      // m/s
    var personalBestVertical: Double = 0      // meters
    var personalBestDistance: Double = 0      // meters

    // Season bests (current ski season — lazy reset on app launch when season changes)
    var seasonBestMaxSpeed: Double = 0        // m/s
    var seasonBestVertical: Double = 0        // meters
    var seasonBestDistance: Double = 0        // meters

    /// The ski season year string when season bests were last reset (e.g. "2025/26").
    var lastSeasonYear: String = ""

    /// Daily activity goal in minutes (default: 4 hours).
    var dailyGoalMinutes: Double = 240

    /// Avatar photo stored as binary data (max ~100KB after compression).
    @Attribute(.externalStorage) var avatarData: Data?

    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        displayName: String = "",
        preferredUnits: UnitSystem = UnitSystem.metric,
        personalBestMaxSpeed: Double = 0,
        personalBestVertical: Double = 0,
        personalBestDistance: Double = 0,
        seasonBestMaxSpeed: Double = 0,
        seasonBestVertical: Double = 0,
        seasonBestDistance: Double = 0,
        lastSeasonYear: String = "",
        dailyGoalMinutes: Double = 240,
        avatarData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredUnits = preferredUnits
        self.personalBestMaxSpeed = personalBestMaxSpeed
        self.personalBestVertical = personalBestVertical
        self.personalBestDistance = personalBestDistance
        self.seasonBestMaxSpeed = seasonBestMaxSpeed
        self.seasonBestVertical = seasonBestVertical
        self.seasonBestDistance = seasonBestDistance
        self.lastSeasonYear = lastSeasonYear
        self.dailyGoalMinutes = dailyGoalMinutes
        self.avatarData = avatarData
        self.createdAt = createdAt
    }
}
