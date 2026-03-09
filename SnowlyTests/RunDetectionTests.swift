//
//  RunDetectionTests.swift
//  SnowlyTests
//
//  Tests for RunDetectionService — the core algorithm.
//  Target: >90% coverage for this critical service.
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct RunDetectionTests {

    // MARK: - Helpers

    private func makePoint(
        speed: Double,
        altitude: Double = 2000,
        timestamp: Date = Date()
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: 46.0,
            longitude: 7.0,
            altitude: altitude,
            speed: speed,
            accuracy: 5.0,
            course: 180.0
        )
    }

    private func makeRecentPoints(
        count: Int,
        startAltitude: Double,
        endAltitude: Double,
        startTime: Date = Date().addingTimeInterval(-30)
    ) -> [TrackPoint] {
        (0..<count).map { i in
            let fraction = Double(i) / Double(max(1, count - 1))
            let altitude = startAltitude + (endAltitude - startAltitude) * fraction
            let time = startTime.addingTimeInterval(Double(i) * 3)
            return makePoint(speed: 3.0, altitude: altitude, timestamp: time)
        }
    }

    // MARK: - GPS Noise Filter

    @Test func belowGpsNoiseFloor_isIdle() {
        let point = makePoint(speed: 0.5) // Below 1.0 m/s noise floor
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .idle)
    }

    @Test func atZeroSpeed_isIdle() {
        let point = makePoint(speed: 0.0)
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .idle)
    }

    // MARK: - Idle Detection

    @Test func belowIdleThreshold_isIdle() {
        let point = makePoint(speed: 1.2) // Above noise floor but below 1.5 m/s
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .idle)
    }

    // MARK: - High Speed = Skiing

    @Test func aboveChairliftMaxSpeed_isSkiing() {
        let point = makePoint(speed: 8.0) // > 6 m/s — definitely skiing
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .skiing)
    }

    @Test func veryHighSpeed_isSkiing() {
        let point = makePoint(speed: 20.0) // 72 km/h
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .skiing)
    }

    // MARK: - Chairlift Detection (altitude rising)

    @Test func mediumSpeed_altitudeRising_isChairlift() {
        let now = Date()
        // Recent points showing altitude increase (2000 → 2050) over 30s
        let recentPoints = makeRecentPoints(
            count: 10,
            startAltitude: 2000,
            endAltitude: 2050,
            startTime: now.addingTimeInterval(-30)
        )
        let point = makePoint(speed: 4.0, altitude: 2055, timestamp: now)

        let result = RunDetectionService.detect(point: point, recentPoints: recentPoints)
        #expect(result == .lift)
    }

    // MARK: - Skiing Detection (altitude falling)

    @Test func mediumSpeed_altitudeFalling_isSkiing() {
        let now = Date()
        // Recent points showing altitude decrease (2050 → 2000) over 30s
        let recentPoints = makeRecentPoints(
            count: 10,
            startAltitude: 2050,
            endAltitude: 2000,
            startTime: now.addingTimeInterval(-30)
        )
        let point = makePoint(speed: 4.0, altitude: 1995, timestamp: now)

        let result = RunDetectionService.detect(point: point, recentPoints: recentPoints)
        #expect(result == .skiing)
    }

    // MARK: - CoreMotion Enhancement

    @Test func mediumSpeed_flatAltitude_automotiveMotion_isChairlift() {
        let point = makePoint(speed: 4.0, altitude: 2000)
        let result = RunDetectionService.detect(
            point: point,
            recentPoints: [makePoint(speed: 4.0, altitude: 2000)],
            motion: .automotive
        )
        #expect(result == .lift)
    }

    // MARK: - Run End Detection

    @Test func shouldEndRun_afterThreshold() {
        let lastActive = Date().addingTimeInterval(-80) // 80s ago > 75s threshold
        #expect(RunDetectionService.shouldEndRun(lastActivityTime: lastActive))
    }

    @Test func shouldNotEndRun_beforeThreshold() {
        let lastActive = Date().addingTimeInterval(-30) // 30s ago < 75s threshold
        #expect(!RunDetectionService.shouldEndRun(lastActivityTime: lastActive))
    }

    @Test func shouldNotEndRun_justAtThreshold() {
        let lastActive = Date().addingTimeInterval(-74) // Just below 75s
        #expect(!RunDetectionService.shouldEndRun(lastActivityTime: lastActive))
    }

    // MARK: - Edge Cases

    @Test func emptyRecentPoints_mediumSpeed_isSkiing() {
        let point = makePoint(speed: 3.0)
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .skiing)
    }

    @Test func exactlyAtIdleThreshold_noAltitudeData_isIdle() {
        // 1.5 m/s is the idle threshold boundary. Without altitude data,
        // and below skiingMinSpeed (2.0), it falls through to idle.
        let point = makePoint(speed: 1.5)
        let result = RunDetectionService.detect(point: point, recentPoints: [])
        #expect(result == .idle)
    }

    // MARK: - Median Filter

    @Test func medianFilter_removesSpikes() {
        let values = [10.0, 11.0, 50.0, 12.0, 13.0, 14.0, 15.0]
        let filtered = MotionEstimator.medianFilter(values: values, windowSize: 5)

        // The spike at index 2 (50.0) should be replaced by the median of its window
        #expect(filtered[2] == 12.0)
        // Neighbors should reflect the local median correctly
        #expect(filtered[3] == 13.0)
        #expect(filtered[4] == 14.0)
    }

    @Test func altitudeSpike_rejectedByMedianFilter() {
        let now = Date()
        // 10 points ascending ~2m/s, with one extreme -100m spike at index 8
        var points: [TrackPoint] = []
        for i in 0..<10 {
            let normalAltitude = 2000.0 + Double(i) * 2
            let altitude: Double = (i == 8) ? normalAltitude - 100 : normalAltitude
            points.append(makePoint(
                speed: 4.0,
                altitude: altitude,
                timestamp: now.addingTimeInterval(Double(i - 10))
            ))
        }
        let current = makePoint(speed: 4.0, altitude: 2020, timestamp: now)

        // Without median filter the spike would skew regression negative.
        // With median filter the ascending trend is preserved → lift.
        let result = RunDetectionService.detect(point: current, recentPoints: points)
        #expect(result == .lift)
    }

    // MARK: - Minimum Points Threshold

    @Test func insufficientPoints_returnsZeroTrend() {
        let now = Date()
        // Only 5 recent points (+ 1 current = 6 < 8 minimum)
        let recentPoints = makeRecentPoints(
            count: 5,
            startAltitude: 2000,
            endAltitude: 2100,
            startTime: now.addingTimeInterval(-15)
        )
        let point = makePoint(speed: 4.0, altitude: 2100, timestamp: now)

        // Despite strong upward trend, too few points → trend = 0.
        // Medium speed, no trend, speed >= skiingMinSpeed → skiing.
        let result = RunDetectionService.detect(point: point, recentPoints: recentPoints)
        #expect(result == .skiing)
    }

    @Test func gentleSlope_belowThreshold_noTrendDetected() {
        let now = Date()
        // 10 points with very gentle slope (~0.1 m/s, below ±0.25 threshold)
        let recentPoints = makeRecentPoints(
            count: 10,
            startAltitude: 2000,
            endAltitude: 2003,
            startTime: now.addingTimeInterval(-30)
        )
        let point = makePoint(speed: 4.0, altitude: 2003.3, timestamp: now)

        // Slope ~0.1 m/s, within dead zone → no altitude verdict.
        // Medium speed, no motion hint, speed >= skiingMinSpeed → skiing.
        let result = RunDetectionService.detect(point: point, recentPoints: recentPoints)
        #expect(result == .skiing)
    }

    @Test func rawArrayOverload_matchesTrackPointOverload() {
        let now = Date()
        let recentPoints = makeRecentPoints(
            count: 10,
            startAltitude: 2050,
            endAltitude: 2000,
            startTime: now.addingTimeInterval(-30)
        )
        let point = makePoint(speed: 4.0, altitude: 1995, timestamp: now)

        let pointBased = RunDetectionService.detect(
            point: point,
            recentPoints: recentPoints,
            motion: .unknown
        )

        let rawBased = RunDetectionService.detect(
            point: point,
            recentTimestamps: recentPoints.map { $0.timestamp.timeIntervalSinceReferenceDate },
            recentAltitudes: recentPoints.map(\.altitude),
            motion: .unknown
        )

        #expect(rawBased == pointBased)
    }
}
