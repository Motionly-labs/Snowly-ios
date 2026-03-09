//
//  MotionEstimatorTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct MotionEstimatorTests {

    // MARK: - Helpers

    private func makePoint(
        speed: Double,
        altitude: Double = 2000,
        timestamp: Date = Date(),
        lat: Double = 46.0,
        lon: Double = 7.0
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            speed: speed,
            accuracy: 5.0,
            course: 180.0
        )
    }

    private func makePoints(
        count: Int,
        startAltitude: Double,
        endAltitude: Double,
        speed: Double = 4.0,
        startTime: Date
    ) -> [TrackPoint] {
        (0..<count).map { i in
            let fraction = count > 1 ? Double(i) / Double(count - 1) : 0
            let alt = startAltitude + (endAltitude - startAltitude) * fraction
            return makePoint(speed: speed, altitude: alt, timestamp: startTime.addingTimeInterval(Double(i) * 3))
        }
    }

    // MARK: - estimate: empty history

    @Test func estimate_emptyHistory_usesInstantaneousSpeed() {
        let current = makePoint(speed: 5.0, altitude: 2000)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: [])
        #expect(estimate.avgHorizontalSpeed == 5.0)
        #expect(estimate.avgVerticalSpeed == 0)
        #expect(!estimate.hasReliableAltitudeTrend)
    }

    @Test func estimate_emptyHistory_zeroSpeed_isZero() {
        let current = makePoint(speed: 0.0)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: [])
        #expect(estimate.avgHorizontalSpeed == 0)
        #expect(!estimate.hasReliableAltitudeTrend)
    }

    // MARK: - estimate: altitude trend

    @Test func estimate_altitudeDelta_positiveForAscent() {
        let now = Date()
        let recent = makePoints(count: 10, startAltitude: 2000, endAltitude: 2050,
                                startTime: now.addingTimeInterval(-30))
        let current = makePoint(speed: 4.0, altitude: 2055, timestamp: now)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: recent)
        #expect(estimate.avgVerticalSpeed > 0)
        #expect(estimate.hasReliableAltitudeTrend)
    }

    @Test func estimate_altitudeDelta_negativeForDescent() {
        let now = Date()
        let recent = makePoints(count: 10, startAltitude: 2050, endAltitude: 2000,
                                startTime: now.addingTimeInterval(-30))
        let current = makePoint(speed: 4.0, altitude: 1995, timestamp: now)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: recent)
        #expect(estimate.avgVerticalSpeed < 0)
        #expect(estimate.hasReliableAltitudeTrend)
    }

    @Test func estimate_gentleSlope_belowDeadZone_hasNoReliableTrend() {
        let now = Date()
        // Very gentle ascent, well below 0.15 m/s altitude trend threshold
        let recent = makePoints(count: 10, startAltitude: 2000, endAltitude: 2003,
                                startTime: now.addingTimeInterval(-30))
        let current = makePoint(speed: 4.0, altitude: 2003.3, timestamp: now)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: recent)
        #expect(!estimate.hasReliableAltitudeTrend)
    }

    // MARK: - estimate: insufficient history

    @Test func estimate_insufficientHistory_hasNoReliableTrend() {
        let now = Date()
        // Only 5 recent points — below the minimum (8) for reliable altitude trend
        let recent = makePoints(count: 5, startAltitude: 2000, endAltitude: 2100,
                                startTime: now.addingTimeInterval(-15))
        let current = makePoint(speed: 4.0, altitude: 2100, timestamp: now)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: recent)
        #expect(!estimate.hasReliableAltitudeTrend)
    }

    // MARK: - estimate: horizontal speed fallback

    @Test func estimate_sameLatLon_fallsBackToGPSSpeed() {
        let now = Date()
        // Points all at same lat/lon → haversine = 0 → use GPS speed
        let recent = makePoints(count: 10, startAltitude: 2000, endAltitude: 2050,
                                startTime: now.addingTimeInterval(-30))
        let current = makePoint(speed: 6.5, altitude: 2055, timestamp: now)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: recent)
        #expect(estimate.avgHorizontalSpeed == 6.5)
    }

    // MARK: - medianFilter

    @Test func medianFilter_removesSpike() {
        let values = [10.0, 11.0, 50.0, 12.0, 13.0, 14.0, 15.0]
        let filtered = MotionEstimator.medianFilter(values: values, windowSize: 5)
        #expect(filtered[2] == 12.0)
        #expect(filtered[3] == 13.0)
        #expect(filtered[4] == 14.0)
    }

    @Test func medianFilter_windowSizeOne_isIdentity() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        let filtered = MotionEstimator.medianFilter(values: values, windowSize: 1)
        #expect(filtered == values)
    }

    @Test func medianFilter_emptyInput_returnsEmpty() {
        let filtered = MotionEstimator.medianFilter(values: [], windowSize: 3)
        #expect(filtered.isEmpty)
    }

    @Test func medianFilter_preservesLength() {
        let values = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0]
        let filtered = MotionEstimator.medianFilter(values: values, windowSize: 3)
        #expect(filtered.count == values.count)
    }
}
