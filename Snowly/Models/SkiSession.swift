//
//  SkiSession.swift
//  Snowly
//
//  A complete ski session (one day of skiing).
//  Aggregate fields are denormalized for query performance.
//

import Foundation
import SwiftData

@Model
final class SkiSession {
    @Attribute(.unique) var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date?
    var totalDistance: Double = 0     // meters
    var totalVertical: Double = 0    // meters
    var maxSpeed: Double = 0         // m/s
    /// Denormalized run count cached for query performance.
    var runCount: Int = 0
    var healthKitWorkoutId: UUID?

    var resort: Resort?

    @Relationship(deleteRule: .cascade)
    var runs: [SkiRun] = []

    /// Computed duration in seconds.
    var duration: TimeInterval {
        guard let end = endDate else {
            return Date().timeIntervalSince(startDate)
        }
        return end.timeIntervalSince(startDate)
    }

    /// Average speed across all runs in m/s.
    var averageSpeed: Double {
        guard totalDistance > 0, duration > 0 else { return 0 }
        let skiingTime = runs
            .filter { $0.activityType == .skiing }
            .reduce(0.0) { $0 + ($1.duration) }
        guard skiingTime > 0 else { return 0 }
        return totalDistance / skiingTime
    }

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        totalDistance: Double = 0,
        totalVertical: Double = 0,
        maxSpeed: Double = 0,
        runCount: Int = 0,
        resort: Resort? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalDistance = totalDistance
        self.totalVertical = totalVertical
        self.maxSpeed = maxSpeed
        self.runCount = runCount
        self.resort = resort
    }
}
