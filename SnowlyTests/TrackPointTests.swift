//
//  TrackPointTests.swift
//  SnowlyTests
//
//  Tests for TrackPoint Codable encoding/decoding.
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct TrackPointTests {

    @Test func encodeDecode_roundTrip() throws {
        let original = TrackPoint(
            timestamp: Date(timeIntervalSince1970: 1000000),
            latitude: 46.123,
            longitude: 7.456,
            altitude: 2500.5,
            speed: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 9.0,
            course: 180.0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackPoint.self, from: data)

        #expect(decoded == original)
    }

    @Test func encodeDecodeArray_roundTrip() throws {
        let points = (0..<100).map { i in
            TrackPoint(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                latitude: 46.0 + Double(i) * 0.001,
                longitude: 7.0 + Double(i) * 0.001,
                altitude: 2500.0 - Double(i) * 5.0,
                speed: Double(i) * 0.5,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 9.0,
                course: 180.0
            )
        }

        let data = try JSONEncoder().encode(points)
        let decoded = try JSONDecoder().decode([TrackPoint].self, from: data)

        #expect(decoded.count == 100)
        #expect(decoded.first == points.first)
        #expect(decoded.last == points.last)
    }

    @Test func equality() {
        let a = TrackPoint(
            timestamp: Date(timeIntervalSince1970: 1000),
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2000,
            speed: 10.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 9.0,
            course: 180.0
        )
        let b = TrackPoint(
            timestamp: Date(timeIntervalSince1970: 1000),
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2000,
            speed: 10.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 9.0,
            course: 180.0
        )

        #expect(a == b)
    }

    @Test func inequality_differentSpeed() {
        let a = TrackPoint(
            timestamp: Date(timeIntervalSince1970: 1000),
            latitude: 46.0, longitude: 7.0, altitude: 2000,
            speed: 10.0, horizontalAccuracy: 5.0, verticalAccuracy: 9.0, course: 180.0
        )
        let b = TrackPoint(
            timestamp: Date(timeIntervalSince1970: 1000),
            latitude: 46.0, longitude: 7.0, altitude: 2000,
            speed: 15.0, horizontalAccuracy: 5.0, verticalAccuracy: 9.0, course: 180.0
        )

        #expect(a != b)
    }
}
