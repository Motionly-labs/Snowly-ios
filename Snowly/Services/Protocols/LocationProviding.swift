//
//  LocationProviding.swift
//  Snowly
//
//  Protocol for location services — enables mock injection for testing.
//

import Foundation
import CoreLocation

@MainActor
protocol LocationProviding: AnyObject, Sendable {
    var authorizationStatus: CLAuthorizationStatus { get }
    var isTracking: Bool { get }
    var currentAltitude: Double { get }

    func requestAuthorization()
    func recentTrackPointsSnapshot() -> [TrackPoint]
    func startTracking() -> AsyncStream<TrackPoint>
    func stopTracking()
}
