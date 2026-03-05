//
//  TrackPointCoreLocationTests.swift
//  SnowlyTests
//
//  Tests for TrackPoint → CLLocation conversion.
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@Suite("TrackPoint CoreLocation Extension Tests")
@MainActor
struct TrackPointCoreLocationTests {

    @Test("clLocation preserves coordinate")
    func clLocation_coordinatePreserved() {
        let point = TrackPoint(
            timestamp: Date(),
            latitude: 49.2827,
            longitude: -123.1207,
            altitude: 1200,
            speed: 10.0,
            accuracy: 5.0,
            course: 270
        )

        let location = point.clLocation

        #expect(location.coordinate.latitude == point.latitude)
        #expect(location.coordinate.longitude == point.longitude)
        #expect(location.altitude == point.altitude)
        #expect(location.horizontalAccuracy == point.accuracy)
        #expect(location.course == point.course)
        #expect(location.speed == point.speed)
    }

    @Test("clLocation preserves timestamp")
    func clLocation_timestampPreserved() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let point = TrackPoint(
            timestamp: date,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2500,
            speed: 15.0,
            accuracy: 8.0,
            course: 90
        )

        let location = point.clLocation

        #expect(location.timestamp == date)
    }

    @Test("clLocation clamps negative speed to zero")
    func clLocation_negativeSpeedClamped() {
        let point = TrackPoint(
            timestamp: Date(),
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2500,
            speed: -5.0,
            accuracy: 8.0,
            course: 90
        )

        let location = point.clLocation

        #expect(location.speed == 0)
    }

    @Test("clLocation handles negative course as -1")
    func clLocation_negativeCoursePreserved() {
        let point = TrackPoint(
            timestamp: Date(),
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2500,
            speed: 10.0,
            accuracy: 8.0,
            course: -1
        )

        let location = point.clLocation

        #expect(location.course == -1)
    }
}
