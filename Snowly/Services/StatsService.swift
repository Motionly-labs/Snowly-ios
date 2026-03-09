//
//  StatsService.swift
//  Snowly
//
//  Pure functions for computing aggregate statistics.
//  No side effects — takes data in, returns results.
//

import Foundation

enum StatsService {

    struct SeasonStats: Sendable {
        let totalSessions: Int
        let totalRuns: Int
        let totalDistance: Double      // meters
        let totalVertical: Double      // meters
        let totalDuration: TimeInterval
        let maxSpeed: Double           // m/s
        let averageRunsPerSession: Double
        let averageVerticalPerSession: Double
    }

    /// Compute season stats from a list of sessions.
    static func seasonStats(from sessions: [SkiSession]) -> SeasonStats {
        let totalSessions = sessions.count
        let totalRuns = sessions.reduce(0) { $0 + $1.runCount }
        let totalDistance = sessions.reduce(0.0) { $0 + $1.totalDistance }
        let totalVertical = sessions.reduce(0.0) { $0 + $1.totalVertical }
        let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
        let maxSpeed = sessions.map(\.maxSpeed).max() ?? 0

        return SeasonStats(
            totalSessions: totalSessions,
            totalRuns: totalRuns,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            totalDuration: totalDuration,
            maxSpeed: maxSpeed,
            averageRunsPerSession: totalSessions > 0
                ? Double(totalRuns) / Double(totalSessions) : 0,
            averageVerticalPerSession: totalSessions > 0
                ? totalVertical / Double(totalSessions) : 0
        )
    }

    /// Check if a session sets any new personal bests.
    static func checkPersonalBests(
        session: SkiSession,
        profile: UserProfile
    ) -> [String] {
        var newRecords: [String] = []

        if session.maxSpeed > profile.seasonBestMaxSpeed {
            newRecords.append(String(localized: "stat_max_speed"))
        }
        if session.totalVertical > profile.seasonBestVertical {
            newRecords.append(String(localized: "stat_vertical_drop"))
        }
        if session.totalDistance > profile.seasonBestDistance {
            newRecords.append(String(localized: "common_distance"))
        }
        if session.runCount > profile.seasonBestRunCount {
            newRecords.append(String(localized: "stat_run_count"))
        }

        return newRecords
    }

    /// Immutable result describing which personal bests to update.
    struct PersonalBestUpdate: Sendable {
        let maxSpeed: Double?
        let vertical: Double?
        let distance: Double?
        let runCount: Int?

        var hasUpdates: Bool {
            maxSpeed != nil || vertical != nil || distance != nil || runCount != nil
        }
    }

    /// Compute personal best updates for a session (pure — no mutation).
    static func computePersonalBestUpdates(
        session: SkiSession,
        profile: UserProfile
    ) -> PersonalBestUpdate {
        PersonalBestUpdate(
            maxSpeed: session.maxSpeed > profile.seasonBestMaxSpeed ? session.maxSpeed : nil,
            vertical: session.totalVertical > profile.seasonBestVertical ? session.totalVertical : nil,
            distance: session.totalDistance > profile.seasonBestDistance ? session.totalDistance : nil,
            runCount: session.runCount > profile.seasonBestRunCount ? session.runCount : nil
        )
    }

    /// Apply a personal best update to a profile.
    /// Note: Mutates the @Model directly — this is intentional for SwiftData persistence.
    static func applyPersonalBestUpdate(_ update: PersonalBestUpdate, to profile: UserProfile) {
        if let maxSpeed = update.maxSpeed {
            profile.seasonBestMaxSpeed = maxSpeed
        }
        if let vertical = update.vertical {
            profile.seasonBestVertical = vertical
        }
        if let distance = update.distance {
            profile.seasonBestDistance = distance
        }
        if let runCount = update.runCount {
            profile.seasonBestRunCount = runCount
        }
    }
}
