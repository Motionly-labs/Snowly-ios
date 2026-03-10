//
//  GPSKalmanFilterTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct KalmanFilter1DTests {

    // MARK: - Predict

    @Test func predict_advancesPositionByVelocity() {
        var filter = KalmanFilter1D(position: 0, velocity: 5, p00: 1, p01: 0, p11: 1)
        filter.predict(dt: 2.0, processNoiseAccel: 0)
        #expect(abs(filter.position - 10.0) < 1e-9)
        #expect(abs(filter.velocity - 5.0) < 1e-9)
    }

    @Test func predict_increasesCovariance() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 1, p01: 0, p11: 1)
        let oldP00 = filter.p00
        let oldP11 = filter.p11
        filter.predict(dt: 1.0, processNoiseAccel: 1.0)
        #expect(filter.p00 > oldP00)
        #expect(filter.p11 > oldP11)
    }

    @Test func predict_zeroProcessNoise_covarianceGrowsFromCrossTerms() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 1, p01: 0.5, p11: 1)
        filter.predict(dt: 1.0, processNoiseAccel: 0)
        // P00 = p00 + 2*dt*p01 + dt^2*p11 = 1 + 1 + 1 = 3
        #expect(abs(filter.p00 - 3.0) < 1e-9)
    }

    // MARK: - Update Position

    @Test func updatePosition_convergesOnMeasurement() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 100, p01: 0, p11: 100)
        // Feed the same position measurement repeatedly
        for _ in 0..<20 {
            filter.updatePosition(measurement: 10.0, noise: 1.0)
        }
        #expect(abs(filter.position - 10.0) < 0.1)
    }

    @Test func updatePosition_reducesCovariance() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 100, p01: 0, p11: 100)
        let oldP00 = filter.p00
        filter.updatePosition(measurement: 5.0, noise: 1.0)
        #expect(filter.p00 < oldP00)
    }

    @Test func updatePosition_highNoise_smallCorrection() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 1, p01: 0, p11: 1)
        filter.updatePosition(measurement: 100.0, noise: 1000.0)
        // With very high measurement noise, filter barely moves
        #expect(abs(filter.position) < 1.0)
    }

    // MARK: - Update Velocity

    @Test func updateVelocity_convergesOnMeasurement() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 100, p01: 0, p11: 100)
        for _ in 0..<20 {
            filter.updateVelocity(measurement: 3.0, noise: 0.5)
        }
        #expect(abs(filter.velocity - 3.0) < 0.1)
    }

    @Test func updateVelocity_reducesVelocityCovariance() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 100, p01: 0, p11: 100)
        let oldP11 = filter.p11
        filter.updateVelocity(measurement: 5.0, noise: 1.0)
        #expect(filter.p11 < oldP11)
    }

    // MARK: - Spike Rejection

    @Test func spikeRejection_recoversAfterOutlier() {
        var filter = KalmanFilter1D(position: 0, velocity: 0, p00: 1, p01: 0, p11: 1)
        // Establish stable position near 0
        for _ in 0..<10 {
            filter.predict(dt: 1.0, processNoiseAccel: 0.5)
            filter.updatePosition(measurement: 0, noise: 1.0)
        }
        // Single spike at 100m
        filter.predict(dt: 1.0, processNoiseAccel: 0.5)
        filter.updatePosition(measurement: 100.0, noise: 1.0)
        // Filter should NOT jump all the way to 100
        #expect(filter.position < 100)
        // Feed normal measurements — filter should recover
        for _ in 0..<5 {
            filter.predict(dt: 1.0, processNoiseAccel: 0.5)
            filter.updatePosition(measurement: 0, noise: 1.0)
        }
        // After recovery, should be back near 0
        #expect(abs(filter.position) < 20)
    }
}

@MainActor
struct GPSKalmanFilterTests {

    // MARK: - Helpers

    private func makePoint(
        lat: Double = 46.0,
        lon: Double = 7.0,
        altitude: Double = 2000,
        speed: Double = 0,
        accuracy: Double = 5.0,
        course: Double = 180.0,
        timestamp: Date = Date()
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            speed: speed,
            accuracy: accuracy,
            course: course
        )
    }

    // MARK: - Initialization

    @Test func firstPoint_returnsUnmodified() {
        var filter = GPSKalmanFilter()
        let point = makePoint(lat: 46.5, lon: 7.5, altitude: 1800, speed: 3.0, course: 90)
        let result = filter.update(point: point)

        #expect(result.latitude == point.latitude)
        #expect(result.longitude == point.longitude)
        #expect(result.altitude == point.altitude)
        #expect(result.speed == point.speed)
        #expect(result.timestamp == point.timestamp)
    }

    @Test func reset_allowsReinitialization() {
        var filter = GPSKalmanFilter()
        let now = Date()
        _ = filter.update(point: makePoint(timestamp: now))
        _ = filter.update(point: makePoint(lat: 46.001, timestamp: now.addingTimeInterval(1)))

        filter.reset()

        // After reset, next point should be returned unmodified
        let fresh = makePoint(lat: 47.0, lon: 8.0, altitude: 1500, timestamp: now.addingTimeInterval(10))
        let result = filter.update(point: fresh)
        #expect(result.latitude == fresh.latitude)
        #expect(result.longitude == fresh.longitude)
    }

    // MARK: - Stationary Points

    @Test func stationaryPoints_convergeToMean() {
        var filter = GPSKalmanFilter()
        let now = Date()
        let baseLat = 46.5
        let baseLon = 7.5

        // First point initializes
        _ = filter.update(point: makePoint(lat: baseLat, lon: baseLon, timestamp: now))

        // Feed 20 stationary points with deterministic small oscillations around base
        let offsets: [Double] = [
            0.00003, -0.00002, 0.00004, -0.00001, 0.00002,
            -0.00003, 0.00001, -0.00004, 0.00002, -0.00002,
            0.00003, -0.00001, 0.00002, -0.00003, 0.00001,
            -0.00002, 0.00004, -0.00001, 0.00003, -0.00002
        ]
        var lastResult: FilteredTrackPoint?
        for i in 1...20 {
            let point = makePoint(
                lat: baseLat + offsets[i - 1],
                lon: baseLon + offsets[(i - 1 + 7) % 20],
                speed: 0,
                timestamp: now.addingTimeInterval(Double(i))
            )
            lastResult = filter.update(point: point)
        }

        // Filtered position should be close to the base position
        #expect(abs(lastResult!.latitude - baseLat) < 0.0002)
        #expect(abs(lastResult!.longitude - baseLon) < 0.0002)
        // Speed should be low (some residual from position noise)
        #expect(lastResult!.speed < 3.0)
    }

    // MARK: - Constant Velocity Tracking

    @Test func constantVelocity_tracksLinearMotion() {
        var filter = GPSKalmanFilter()
        let now = Date()
        let startLat = 46.0
        let speedMps = 10.0  // 10 m/s heading north
        let metersPerDegreeLat = 111_320.0

        // Initialize
        _ = filter.update(point: makePoint(
            lat: startLat, lon: 7.0, speed: speedMps, course: 0, timestamp: now
        ))

        // Feed 30 points moving north at 10 m/s
        var lastResult: FilteredTrackPoint?
        for i in 1...30 {
            let t = Double(i)
            let lat = startLat + (speedMps * t) / metersPerDegreeLat
            let point = makePoint(
                lat: lat, lon: 7.0, speed: speedMps, course: 0,
                timestamp: now.addingTimeInterval(t)
            )
            lastResult = filter.update(point: point)
        }

        // Filtered speed should be close to 10 m/s
        #expect(abs(lastResult!.speed - speedMps) < 2.0)
        // Position should have advanced northward
        #expect(lastResult!.latitude > startLat)
    }

    // MARK: - Altitude Smoothing

    @Test func altitudeSmoothing_suppressesSpike() {
        var filter = GPSKalmanFilter()
        let now = Date()

        // Initialize at 2000m
        _ = filter.update(point: makePoint(altitude: 2000, timestamp: now))

        // Feed stable altitude for 10 seconds
        for i in 1...10 {
            _ = filter.update(point: makePoint(
                altitude: 2000, timestamp: now.addingTimeInterval(Double(i))
            ))
        }

        // Single 100m spike
        let spikeResult = filter.update(point: makePoint(
            altitude: 2100, timestamp: now.addingTimeInterval(11)
        ))

        // Filter should suppress the spike — not jump to 2100
        #expect(spikeResult.altitude < 2060)
        #expect(spikeResult.altitude > 1950)
    }

    @Test func altitudeSmoothing_tracksGradualDescent() {
        var filter = GPSKalmanFilter()
        let now = Date()

        _ = filter.update(point: makePoint(altitude: 2500, timestamp: now))

        // Descend 5 m/s for 20 seconds
        var lastResult: FilteredTrackPoint?
        for i in 1...20 {
            let alt = 2500 - 5.0 * Double(i)
            lastResult = filter.update(point: makePoint(
                altitude: alt, speed: 8, course: 180,
                timestamp: now.addingTimeInterval(Double(i))
            ))
        }

        // Should have descended substantially
        #expect(lastResult!.altitude < 2450)
        #expect(lastResult!.altitude > 2350)
    }

    // MARK: - GPS Gap Handling

    @Test func gpsGap_doesNotExplode() {
        var filter = GPSKalmanFilter()
        let now = Date()

        _ = filter.update(point: makePoint(lat: 46.0, lon: 7.0, timestamp: now))
        _ = filter.update(point: makePoint(
            lat: 46.0001, lon: 7.0, speed: 5, course: 0,
            timestamp: now.addingTimeInterval(1)
        ))

        // 60-second GPS gap
        let afterGap = filter.update(point: makePoint(
            lat: 46.001, lon: 7.0, speed: 5, course: 0,
            timestamp: now.addingTimeInterval(61)
        ))

        // Should produce a valid, finite result
        #expect(afterGap.latitude.isFinite)
        #expect(afterGap.longitude.isFinite)
        #expect(afterGap.speed.isFinite)
        #expect(afterGap.altitude.isFinite)
    }

    // MARK: - Speed Filtering

    @Test func speedFiltering_recoversAfterSpike() {
        var filter = GPSKalmanFilter()
        let now = Date()

        _ = filter.update(point: makePoint(speed: 5, course: 0, timestamp: now))

        // Establish baseline speed of 5 m/s heading north
        for i in 1...10 {
            _ = filter.update(point: makePoint(
                lat: 46.0 + 0.000045 * Double(i),
                speed: 5, course: 0,
                timestamp: now.addingTimeInterval(Double(i))
            ))
        }

        // Single speed spike to 50 m/s (without matching position jump)
        _ = filter.update(point: makePoint(
            lat: 46.0 + 0.000045 * 11,
            speed: 50, course: 0,
            timestamp: now.addingTimeInterval(11)
        ))

        // Feed 5 more normal points — filter should recover toward 5 m/s
        var lastResult: FilteredTrackPoint?
        for i in 12...16 {
            lastResult = filter.update(point: makePoint(
                lat: 46.0 + 0.000045 * Double(i),
                speed: 5, course: 0,
                timestamp: now.addingTimeInterval(Double(i))
            ))
        }

        // After recovery, speed should be back near baseline
        #expect(lastResult!.speed < 15)
        #expect(lastResult!.speed > 1)
    }

    // MARK: - Zero-dt Edge Case

    @Test func zeroDt_returnsPreviousState() {
        var filter = GPSKalmanFilter()
        let now = Date()

        _ = filter.update(point: makePoint(lat: 46.0, lon: 7.0, timestamp: now))
        let first = filter.update(point: makePoint(
            lat: 46.001, lon: 7.0, speed: 5, timestamp: now.addingTimeInterval(1)
        ))

        // Same timestamp — should return filtered state without crashing
        let duplicate = filter.update(point: makePoint(
            lat: 46.002, lon: 7.0, speed: 10, timestamp: now.addingTimeInterval(1)
        ))

        #expect(duplicate.latitude.isFinite)
        #expect(duplicate.longitude.isFinite)
        // Position should not have changed since dt = 0
        #expect(abs(duplicate.latitude - first.latitude) < 0.0001)
    }
}
