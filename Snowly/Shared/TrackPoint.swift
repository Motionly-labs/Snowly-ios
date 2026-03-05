//
//  TrackPoint.swift
//  Snowly
//
//  Shared between iOS and watchOS.
//

import Foundation
import CoreLocation

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
    func distance(to other: TrackPoint) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
