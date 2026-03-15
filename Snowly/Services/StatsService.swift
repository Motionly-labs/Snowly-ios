//
//  StatsService.swift
//  Snowly
//
//  Pure functions for computing aggregate statistics.
//  No side effects — takes data in, returns results.
//

import Foundation

enum StatsService {

    struct AggregateStats: Sendable {
        let totalSessions: Int
        let totalRuns: Int
        let totalDistance: Double      // meters
        let totalVertical: Double      // meters
        let totalDuration: TimeInterval
        let maxSpeed: Double           // m/s
        let averageRunsPerSession: Double
        let averageVerticalPerSession: Double
    }

    struct GearUsageSummary: Sendable {
        let setupId: UUID
        let skiDays: Int
        let totalDistance: Double
        let totalVertical: Double
        let totalRuns: Int
        let lastUsedDate: Date?
        let lastResortName: String?
        let recentSessionIDs: [UUID]

        static func empty(for setupId: UUID) -> GearUsageSummary {
            GearUsageSummary(
                setupId: setupId,
                skiDays: 0,
                totalDistance: 0,
                totalVertical: 0,
                totalRuns: 0,
                lastUsedDate: nil,
                lastResortName: nil,
                recentSessionIDs: []
            )
        }
    }

    struct GearAssetUsageSummary: Sendable {
        let assetId: UUID
        let skiDays: Int
        let totalDistance: Double
        let totalVertical: Double
        let totalRuns: Int
        let lastUsedDate: Date?
        let lastResortName: String?

        static func empty(for assetId: UUID) -> GearAssetUsageSummary {
            GearAssetUsageSummary(
                assetId: assetId,
                skiDays: 0,
                totalDistance: 0,
                totalVertical: 0,
                totalRuns: 0,
                lastUsedDate: nil,
                lastResortName: nil
            )
        }
    }

    /// Compute aggregate stats from a list of sessions.
    static func aggregateStats(from sessions: [SkiSession]) -> AggregateStats {
        let totalSessions = sessions.count
        let totalRuns = sessions.reduce(0) { $0 + $1.runCount }
        let totalDistance = sessions.reduce(0.0) { $0 + $1.totalDistance }
        let totalVertical = sessions.reduce(0.0) { $0 + $1.totalVertical }
        let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
        let maxSpeed = sessions.map(\.maxSpeed).max() ?? 0

        return AggregateStats(
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

    static func gearUsageSummary(
        for setupId: UUID,
        sessions: [SkiSession]
    ) -> GearUsageSummary {
        let qualifyingSessions = sessions
            .filter { $0.gearSetupId == setupId && $0.runCount > 0 }
            .sorted { $0.startDate > $1.startDate }

        guard !qualifyingSessions.isEmpty else {
            return .empty(for: setupId)
        }

        let uniqueDays = Set(qualifyingSessions.map { Calendar.current.startOfDay(for: $0.startDate) })

        return GearUsageSummary(
            setupId: setupId,
            skiDays: uniqueDays.count,
            totalDistance: qualifyingSessions.reduce(0) { $0 + $1.totalDistance },
            totalVertical: qualifyingSessions.reduce(0) { $0 + $1.totalVertical },
            totalRuns: qualifyingSessions.reduce(0) { $0 + $1.runCount },
            lastUsedDate: qualifyingSessions.first?.startDate,
            lastResortName: qualifyingSessions.first?.resort?.name,
            recentSessionIDs: qualifyingSessions.prefix(5).map(\.id)
        )
    }

    static func gearAssetUsageSummary(
        for asset: GearAsset,
        sessions: [SkiSession]
    ) -> GearAssetUsageSummary {
        let setupIDs = Set(asset.setupIDs)
        guard !setupIDs.isEmpty else {
            return .empty(for: asset.id)
        }

        let qualifyingSessions = sessions
            .filter { session in
                guard session.runCount > 0, let setupId = session.gearSetupId else {
                    return false
                }
                return setupIDs.contains(setupId)
            }
            .sorted { $0.startDate > $1.startDate }

        guard !qualifyingSessions.isEmpty else {
            return .empty(for: asset.id)
        }

        let uniqueDays = Set(qualifyingSessions.map { Calendar.current.startOfDay(for: $0.startDate) })

        return GearAssetUsageSummary(
            assetId: asset.id,
            skiDays: uniqueDays.count,
            totalDistance: qualifyingSessions.reduce(0) { $0 + $1.totalDistance },
            totalVertical: qualifyingSessions.reduce(0) { $0 + $1.totalVertical },
            totalRuns: qualifyingSessions.reduce(0) { $0 + $1.runCount },
            lastUsedDate: qualifyingSessions.first?.startDate,
            lastResortName: qualifyingSessions.first?.resort?.name
        )
    }

    /// Check if a session sets any new all-time personal bests.
    static func checkPersonalBests(
        session: SkiSession,
        profile: UserProfile
    ) -> [String] {
        var newRecords: [String] = []

        if session.maxSpeed > profile.personalBestMaxSpeed {
            newRecords.append(String(localized: "stat_max_speed"))
        }
        if session.totalVertical > profile.personalBestVertical {
            newRecords.append(String(localized: "stat_vertical_drop"))
        }
        if session.totalDistance > profile.personalBestDistance {
            newRecords.append(String(localized: "common_distance"))
        }

        return newRecords
    }

    /// Immutable result describing which personal bests to update.
    struct PersonalBestUpdate: Sendable {
        let maxSpeed: Double?
        let vertical: Double?
        let distance: Double?

        var hasUpdates: Bool {
            maxSpeed != nil || vertical != nil || distance != nil
        }
    }

    struct WatchPersonalBestNotification: Sendable {
        let metric: String
        let value: Double
    }

    /// Compute personal best updates for a session (pure — no mutation).
    static func computePersonalBestUpdates(
        session: SkiSession,
        profile: UserProfile
    ) -> PersonalBestUpdate {
        PersonalBestUpdate(
            maxSpeed: session.maxSpeed > profile.personalBestMaxSpeed ? session.maxSpeed : nil,
            vertical: session.totalVertical > profile.personalBestVertical ? session.totalVertical : nil,
            distance: session.totalDistance > profile.personalBestDistance ? session.totalDistance : nil
        )
    }

    /// Apply a personal best update to a profile.
    /// Note: Mutates the @Model directly — this is intentional for SwiftData persistence.
    static func applyPersonalBestUpdate(_ update: PersonalBestUpdate, to profile: UserProfile) {
        if let maxSpeed = update.maxSpeed {
            profile.personalBestMaxSpeed = maxSpeed
        }
        if let vertical = update.vertical {
            profile.personalBestVertical = vertical
        }
        if let distance = update.distance {
            profile.personalBestDistance = distance
        }
    }

    static func watchPersonalBestNotification(
        for update: PersonalBestUpdate
    ) -> WatchPersonalBestNotification? {
        if let maxSpeed = update.maxSpeed {
            return WatchPersonalBestNotification(
                metric: String(localized: "stat_max_speed"),
                value: maxSpeed
            )
        }
        if let vertical = update.vertical {
            return WatchPersonalBestNotification(
                metric: String(localized: "stat_vertical_drop"),
                value: vertical
            )
        }
        if let distance = update.distance {
            return WatchPersonalBestNotification(
                metric: String(localized: "common_distance"),
                value: distance
            )
        }
        return nil
    }

    /// Reset all personal bests to zero.
    /// Note: Mutates the @Model directly — this is intentional for SwiftData persistence.
    static func resetPersonalBests(for profile: UserProfile) {
        profile.personalBestMaxSpeed = 0
        profile.personalBestVertical = 0
        profile.personalBestDistance = 0
    }

    // MARK: - Season Bests

    /// Check if a session sets any new season bests.
    static func checkSeasonBests(
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

        return newRecords
    }

    /// Immutable result describing which season bests to update.
    struct SeasonBestUpdate: Sendable {
        let maxSpeed: Double?
        let vertical: Double?
        let distance: Double?

        var hasUpdates: Bool {
            maxSpeed != nil || vertical != nil || distance != nil
        }
    }

    /// Compute season best updates for a session (pure — no mutation).
    static func computeSeasonBestUpdates(
        session: SkiSession,
        profile: UserProfile
    ) -> SeasonBestUpdate {
        SeasonBestUpdate(
            maxSpeed: session.maxSpeed > profile.seasonBestMaxSpeed ? session.maxSpeed : nil,
            vertical: session.totalVertical > profile.seasonBestVertical ? session.totalVertical : nil,
            distance: session.totalDistance > profile.seasonBestDistance ? session.totalDistance : nil
        )
    }

    /// Apply a season best update to a profile.
    /// Note: Mutates the @Model directly — this is intentional for SwiftData persistence.
    static func applySeasonBestUpdate(_ update: SeasonBestUpdate, to profile: UserProfile) {
        if let maxSpeed = update.maxSpeed {
            profile.seasonBestMaxSpeed = maxSpeed
        }
        if let vertical = update.vertical {
            profile.seasonBestVertical = vertical
        }
        if let distance = update.distance {
            profile.seasonBestDistance = distance
        }
    }

    /// Reset all season bests to zero.
    /// Note: Mutates the @Model directly — this is intentional for SwiftData persistence.
    static func resetSeasonBests(for profile: UserProfile) {
        profile.seasonBestMaxSpeed = 0
        profile.seasonBestVertical = 0
        profile.seasonBestDistance = 0
    }

    // MARK: - Gear Maintenance Status

    enum GearMaintenanceState: Sendable, Equatable {
        case ok
        case dueSoon
        case overdue
    }

    struct GearMaintenanceStatus: Sendable {
        let assetId: UUID
        let state: GearMaintenanceState
        let skiDaysSinceService: Int
        let remainingSkiDays: Int?
        let lastServiceDate: Date?
        let dueDate: Date?
    }

    /// Compute maintenance status for a gear asset based on its due rule and session history.
    static func gearMaintenanceStatus(
        for asset: GearAsset,
        sessions: [SkiSession],
        now: Date = Date()
    ) -> GearMaintenanceStatus {
        switch asset.dueRuleType {
        case .skiDays:
            guard let dueEvery = asset.dueEverySkiDays, dueEvery > 0 else {
                return GearMaintenanceStatus(
                    assetId: asset.id, state: .ok,
                    skiDaysSinceService: 0, remainingSkiDays: nil,
                    lastServiceDate: nil, dueDate: nil
                )
            }
            let lastService = (asset.maintenanceEvents ?? [])
                .map(\.date)
                .max()
            let cutoff = lastService ?? .distantPast
            let setupIDs = Set(asset.setupIDs)
            let skiDays = Set(
                sessions
                    .filter { session in
                        guard session.runCount > 0, let sid = session.gearSetupId else { return false }
                        return setupIDs.contains(sid) && session.startDate > cutoff
                    }
                    .map { Calendar.current.startOfDay(for: $0.startDate) }
            ).count
            let remaining = dueEvery - skiDays
            let state: GearMaintenanceState
            if remaining <= 0 { state = .overdue }
            else if remaining <= 2 { state = .dueSoon }
            else { state = .ok }
            return GearMaintenanceStatus(
                assetId: asset.id, state: state,
                skiDaysSinceService: skiDays, remainingSkiDays: remaining,
                lastServiceDate: lastService, dueDate: nil
            )
        case .date:
            guard let dueDate = asset.dueDate else {
                return GearMaintenanceStatus(
                    assetId: asset.id, state: .ok,
                    skiDaysSinceService: 0, remainingSkiDays: nil,
                    lastServiceDate: nil, dueDate: nil
                )
            }
            let state: GearMaintenanceState = now > dueDate ? .overdue : .ok
            return GearMaintenanceStatus(
                assetId: asset.id, state: state,
                skiDaysSinceService: 0, remainingSkiDays: nil,
                lastServiceDate: nil, dueDate: dueDate
            )
        case .none:
            return GearMaintenanceStatus(
                assetId: asset.id, state: .ok,
                skiDaysSinceService: 0, remainingSkiDays: nil,
                lastServiceDate: nil, dueDate: nil
            )
        }
    }
}
