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

    func requestAuthorization()
    func startTracking() -> AsyncStream<TrackPoint>
    func stopTracking()
}
