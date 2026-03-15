//
//  TrackingStatePersistence.swift
//  Snowly
//
//  Persists tracking state to UserDefaults every 30 seconds
//  for crash recovery.
//

import Foundation

/// Lightweight run snapshot used for crash recovery persistence.
struct PersistedCompletedRun: Codable, Sendable {
    let startDate: Date
    let endDate: Date
    let distance: Double
    let verticalDrop: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let activityType: RunActivityType
    /// Absolute path to the on-disk NDJSON track file stored in Application Support.
    /// Non-nil means the file survives app relaunch and can be read after crash recovery.
    let trackFilePath: String?
}

/// Minimal state snapshot for crash recovery.
struct PersistedTrackingState: Codable, Sendable {
    let sessionId: UUID
    let startDate: Date
    let lastUpdateDate: Date
    let totalDistance: Double
    let totalVertical: Double
    let maxSpeed: Double
    let runCount: Int
    let isActive: Bool
    let elapsedTime: TimeInterval?
    let completedRuns: [PersistedCompletedRun]?

    init(
        sessionId: UUID,
        startDate: Date,
        lastUpdateDate: Date,
        totalDistance: Double,
        totalVertical: Double,
        maxSpeed: Double,
        runCount: Int,
        isActive: Bool,
        elapsedTime: TimeInterval? = nil,
        completedRuns: [PersistedCompletedRun]? = nil
    ) {
        self.sessionId = sessionId
        self.startDate = startDate
        self.lastUpdateDate = lastUpdateDate
        self.totalDistance = totalDistance
        self.totalVertical = totalVertical
        self.maxSpeed = maxSpeed
        self.runCount = runCount
        self.isActive = isActive
        self.elapsedTime = elapsedTime
        self.completedRuns = completedRuns
    }
}

enum TrackingStatePersistence {

    private static let key = SharedConstants.trackingStateKey

    static func save(_ state: PersistedTrackingState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> PersistedTrackingState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedTrackingState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
