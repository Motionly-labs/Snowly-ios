//
//  SkiRun.swift
//  Snowly
//
//  An individual run within a session.
//  Track data stored as binary Data (Codable [TrackPoint]) to avoid
//  SwiftData performance issues with 100k+ objects.
//

import Foundation
import SwiftData
import os

@Model
final class SkiRun {
    @Attribute(.unique) var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date?
    var distance: Double = 0           // meters
    var verticalDrop: Double = 0       // meters (positive = downhill)
    var maxSpeed: Double = 0           // m/s
    var averageSpeed: Double = 0       // m/s
    var activityType: RunActivityType

    /// GPS track points serialized as binary data.
    @Attribute(.externalStorage) var trackData: Data?

    @Relationship(inverse: \SkiSession.runs) var session: SkiSession?

    /// Computed duration in seconds.
    var duration: TimeInterval {
        guard let end = endDate else {
            return Date().timeIntervalSince(startDate)
        }
        return end.timeIntervalSince(startDate)
    }

    private nonisolated static let logger = Logger(subsystem: "com.Snowly", category: "SkiRun")

    /// Decode track points from binary storage.
    var trackPoints: [TrackPoint] {
        guard let data = trackData else { return [] }
        do {
            return try JSONDecoder().decode([TrackPoint].self, from: data)
        } catch {
            Self.logger.error("Failed to decode track points: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        distance: Double = 0,
        verticalDrop: Double = 0,
        maxSpeed: Double = 0,
        averageSpeed: Double = 0,
        activityType: RunActivityType = RunActivityType.skiing,
        trackData: Data? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.verticalDrop = verticalDrop
        self.maxSpeed = maxSpeed
        self.averageSpeed = averageSpeed
        self.activityType = activityType
        self.trackData = trackData
    }
}
