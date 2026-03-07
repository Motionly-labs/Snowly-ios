//
//  TrackPoint.swift
//  Snowly
//
//  Shared between iOS and watchOS.
//

import Foundation

/// A single GPS data point recorded during tracking.
/// Stored as Codable struct (NOT SwiftData @Model) to avoid
/// performance issues with 100k+ objects per season.
struct TrackPoint: Codable, Sendable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double        // m/s
    let accuracy: Double     // meters
    let course: Double       // degrees, 0-360

    /// Haversine distance in meters between two track points.
    /// Pure Swift — avoids CLLocation allocation in hot paths.
    nonisolated func distance(to other: TrackPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
