//
//  SkiRun.swift
//  Snowly
//
//  An individual run within a session.
//  Track data stored as binary Data (Codable [TrackPoint]) to avoid
//  SwiftData performance issues with 100k+ objects while keeping raw GPS as source of truth.
//

import Foundation
import SwiftData
import os

@Model
final class SkiRun {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date?
    var distance: Double = 0           // meters
    var verticalDrop: Double = 0       // meters (positive = downhill)
    var maxSpeed: Double = 0           // m/s
    var averageSpeed: Double = 0       // m/s
    var activityType: RunActivityType = RunActivityType.skiing

    /// Raw GPS track points serialized as binary data.
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

    /// Returns `true` when `trackData` exists but cannot be decoded by any supported format.
    /// Surfaces corrupted or schema-incompatible track data so the UI can show a notice.
    var hasTrackDecodeError: Bool {
        guard let data = trackData else { return false }
        return decodeRawTrackPoints(from: data) == nil && decodeFilteredTrackPoints(from: data) == nil
    }

    /// Decode raw GPS points from binary storage.
    /// Legacy filtered blobs return an empty array because the original raw source is unavailable.
    var rawTrackPoints: [TrackPoint] {
        guard let data = trackData else {
            Self.logger.warning("rawTrackPoints accessed on run \(self.id.uuidString, privacy: .public) with nil trackData")
            return []
        }
        return decodeRawTrackPoints(from: data) ?? []
    }

    /// Derive filtered track points on demand from raw storage.
    /// Legacy sessions that only contain filtered blobs still decode directly.
    var trackPoints: [FilteredTrackPoint] {
        guard let data = trackData else {
            Self.logger.warning("trackPoints accessed on run \(self.id.uuidString, privacy: .public) with nil trackData")
            return []
        }

        if let rawPoints = decodeRawTrackPoints(from: data) {
            return deriveFilteredTrackPoints(from: rawPoints)
        }

        if let filteredPoints = decodeFilteredTrackPoints(from: data) {
            return filteredPoints
        }

        Self.logger.error("Failed to decode track points from stored run data")
        return []
    }

    private func decodeRawTrackPoints(from data: Data) -> [TrackPoint]? {
        if let points = try? JSONDecoder().decode([TrackPoint].self, from: data) { return points }
        return decodeNDJSONTrackPoints(from: data, as: TrackPoint.self)
    }

    private func decodeFilteredTrackPoints(from data: Data) -> [FilteredTrackPoint]? {
        if let points = try? JSONDecoder().decode([FilteredTrackPoint].self, from: data) { return points }
        return decodeNDJSONTrackPoints(from: data, as: FilteredTrackPoint.self)
    }

    private func decodeNDJSONTrackPoints<T: Decodable>(from data: Data, as _: T.Type) -> [T]? {
        let lines = data.split(separator: 0x0A)
        guard !lines.isEmpty else { return [] }

        let decoder = JSONDecoder()
        var points: [T] = []
        points.reserveCapacity(lines.count)

        for line in lines where !line.isEmpty {
            guard let point = try? decoder.decode(T.self, from: Data(line)) else {
                return nil
            }
            points.append(point)
        }
        return points
    }

    private func deriveFilteredTrackPoints(from rawPoints: [TrackPoint]) -> [FilteredTrackPoint] {
        var filter = GPSKalmanFilter()
        let sortedPoints = rawPoints.sorted { $0.timestamp < $1.timestamp }
        return sortedPoints.map { filter.update(point: $0) }
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
