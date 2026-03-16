//
//  TrackPoint.swift
//  Snowly
//
//  Shared between iOS and watchOS.
//

import Foundation

/// Haversine great-circle distance in meters between two geographic coordinates.
/// Pure Swift — avoids CLLocation allocation in hot paths.
nonisolated func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let φ1 = lat1 * .pi / 180
    let φ2 = lat2 * .pi / 180
    let dφ = (lat2 - lat1) * .pi / 180
    let dλ = (lon2 - lon1) * .pi / 180
    let a = sin(dφ / 2) * sin(dφ / 2)
        + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
    return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
}

/// A single GPS data point recorded during tracking.
/// Stored as Codable struct (NOT SwiftData @Model) to avoid
/// performance issues with 100k+ objects per season.
struct TrackPoint: Codable, Sendable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double        // m/s, -1 when unknown
    let horizontalAccuracy: Double   // meters
    let verticalAccuracy: Double     // meters
    let course: Double       // degrees, 0-360

    nonisolated init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speed: Double = -1,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        course: Double
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.course = course
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case latitude
        case longitude
        case altitude
        case speed
        case horizontalAccuracy
        case verticalAccuracy
        case course
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        altitude = try container.decode(Double.self, forKey: .altitude)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? -1
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        verticalAccuracy = try container.decode(Double.self, forKey: .verticalAccuracy)
        course = try container.decode(Double.self, forKey: .course)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(speed, forKey: .speed)
        try container.encode(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encode(verticalAccuracy, forKey: .verticalAccuracy)
        try container.encode(course, forKey: .course)
    }

    /// Haversine distance in meters to another track point.
    nonisolated func distance(to other: TrackPoint) -> Double {
        haversineDistance(lat1: latitude, lon1: longitude, lat2: other.latitude, lon2: other.longitude)
    }
}

struct FilteredTrackPoint: Codable, Sendable, Equatable {
    let rawTimestamp: Date
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let estimatedSpeed: Double  // m/s
    let horizontalAccuracy: Double  // meters
    let verticalAccuracy: Double    // meters
    let course: Double          // degrees, 0-360
    var speed: Double { estimatedSpeed }

    nonisolated init(
        rawTimestamp: Date,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        estimatedSpeed: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        course: Double
    ) {
        self.rawTimestamp = rawTimestamp
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.estimatedSpeed = estimatedSpeed
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.course = course
    }

    enum CodingKeys: String, CodingKey {
        case rawTimestamp
        case timestamp
        case latitude
        case longitude
        case altitude
        case estimatedSpeed
        case horizontalAccuracy
        case verticalAccuracy
        case course
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawTimestamp = try container.decode(Date.self, forKey: .rawTimestamp)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        altitude = try container.decode(Double.self, forKey: .altitude)
        estimatedSpeed = try container.decode(Double.self, forKey: .estimatedSpeed)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        verticalAccuracy = try container.decode(Double.self, forKey: .verticalAccuracy)
        course = try container.decode(Double.self, forKey: .course)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawTimestamp, forKey: .rawTimestamp)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(estimatedSpeed, forKey: .estimatedSpeed)
        try container.encode(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encode(verticalAccuracy, forKey: .verticalAccuracy)
        try container.encode(course, forKey: .course)
    }

    /// Haversine distance in meters to another filtered track point.
    nonisolated func distance(to other: FilteredTrackPoint) -> Double {
        haversineDistance(lat1: latitude, lon1: longitude, lat2: other.latitude, lon2: other.longitude)
    }
}

enum RecentTrackWindow {
    nonisolated static func trimTrackPoints(
        _ points: inout [TrackPoint],
        relativeTo timestamp: Date,
        retention: TimeInterval = SharedConstants.historyRetentionSeconds
    ) {
        trim(&points, relativeTo: timestamp, retention: retention, keyPath: \.timestamp)
    }

    nonisolated static func trimFilteredPoints(
        _ points: inout [FilteredTrackPoint],
        relativeTo timestamp: Date,
        retention: TimeInterval = SharedConstants.historyRetentionSeconds
    ) {
        trim(&points, relativeTo: timestamp, retention: retention, keyPath: \.timestamp)
    }

    nonisolated static func trackPoints(
        from points: [TrackPoint],
        endingAt timestamp: Date,
        within window: TimeInterval
    ) -> [TrackPoint] {
        slice(points, endingAt: timestamp, within: window, keyPath: \.timestamp)
    }

    nonisolated static func filteredPoints(
        from points: [FilteredTrackPoint],
        endingAt timestamp: Date,
        within window: TimeInterval
    ) -> [FilteredTrackPoint] {
        slice(points, endingAt: timestamp, within: window, keyPath: \.timestamp)
    }

    private nonisolated static func trim<T>(
        _ points: inout [T],
        relativeTo timestamp: Date,
        retention: TimeInterval,
        keyPath: KeyPath<T, Date>
    ) {
        let cutoff = timestamp.addingTimeInterval(-retention)
        // Binary search for cutoff — O(log n) vs O(n) linear scan.
        // Points are time-ordered (append-only).
        var lo = 0
        var hi = points.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if points[mid][keyPath: keyPath] < cutoff {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo >= points.count {
            points.removeAll(keepingCapacity: true)
        } else if lo > 0 {
            points.removeFirst(lo)
        }
    }

    private nonisolated static func slice<T>(
        _ points: [T],
        endingAt timestamp: Date,
        within window: TimeInterval,
        keyPath: KeyPath<T, Date>
    ) -> [T] {
        // points is always time-ordered (append-only, monotonically increasing timestamps).
        // True O(log n) binary search for the first point within the window.
        let cutoff = timestamp.addingTimeInterval(-window)
        var lo = 0
        var hi = points.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if points[mid][keyPath: keyPath] < cutoff {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        guard lo < points.count else { return [] }
        return Array(points[lo...])
    }
}

extension TrackPoint {
    nonisolated var filteredEstimatePoint: FilteredTrackPoint {
        FilteredTrackPoint(
            rawTimestamp: timestamp,
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            estimatedSpeed: max(speed, 0),
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course
        )
    }
}
