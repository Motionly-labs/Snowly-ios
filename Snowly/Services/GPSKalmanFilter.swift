//
//  GPSKalmanFilter.swift
//  Snowly
//
//  Online Kalman filter for GPS tracking. Smooths position, speed, and altitude
//  by fusing GPS position and Doppler velocity measurements through three
//  independent 2-state constant-velocity filters (east, north, altitude).
//
//  No platform-specific imports — shared between iOS and watchOS.
//

import Foundation

// MARK: - 1D Constant-Velocity Kalman Filter

/// A single-axis Kalman filter with state [position, velocity].
///
/// Uses a constant-velocity process model with acceleration process noise.
/// Supports sequential scalar updates for position and velocity measurements.
///
/// ## State Model
///
/// State vector: `x = [position, velocity]`
/// Transition:   `F = [[1, dt], [0, 1]]`
/// Process noise: `Q = σ_a² × [[dt⁴/4, dt³/2], [dt³/2, dt²]]`
///
/// ## Covariance
///
/// Stored as three elements of the symmetric 2×2 matrix: `p00`, `p01`, `p11`.
struct KalmanFilter1D: Sendable, Equatable {
    var position: Double
    var velocity: Double
    /// Variance of position.
    var p00: Double
    /// Covariance of position and velocity (symmetric: p01 == p10).
    var p01: Double
    /// Variance of velocity.
    var p11: Double

    /// Advances the state by `dt` seconds under the constant-velocity model.
    ///
    /// - Parameters:
    ///   - dt: Time step in seconds. Must be > 0.
    ///   - processNoiseAccel: Standard deviation of the acceleration noise (m/s²).
    nonisolated mutating func predict(dt: Double, processNoiseAccel: Double) {
        // State prediction: position += velocity * dt
        position += velocity * dt

        // Covariance prediction: P = F·P·Fᵀ + Q
        let dt2 = dt * dt
        let dt3 = dt2 * dt
        let dt4 = dt3 * dt
        let q = processNoiseAccel * processNoiseAccel

        p00 = p00 + 2 * dt * p01 + dt2 * p11 + q * dt4 / 4
        p01 = p01 + dt * p11 + q * dt3 / 2
        p11 = p11 + q * dt2
    }

    /// Incorporates a position measurement.
    ///
    /// - Parameters:
    ///   - measurement: Observed position value (meters).
    ///   - noise: Standard deviation of the measurement noise (meters).
    nonisolated mutating func updatePosition(measurement: Double, noise: Double) {
        let r = noise * noise
        let s = p00 + r
        guard s > 1e-12 else { return }

        let k0 = p00 / s
        let k1 = p01 / s

        let innovation = measurement - position
        position += k0 * innovation
        velocity += k1 * innovation

        // P = (I − K·H) · P  with H = [1, 0]
        let oldP01 = p01
        p00 = p00 * r / s
        p01 = p01 * r / s
        p11 = p11 - k1 * oldP01
    }

    /// Incorporates a velocity measurement.
    ///
    /// - Parameters:
    ///   - measurement: Observed velocity value (m/s).
    ///   - noise: Standard deviation of the measurement noise (m/s).
    nonisolated mutating func updateVelocity(measurement: Double, noise: Double) {
        let r = noise * noise
        let s = p11 + r
        guard s > 1e-12 else { return }

        let k0 = p01 / s
        let k1 = p11 / s

        let innovation = measurement - velocity
        position += k0 * innovation
        velocity += k1 * innovation

        // P = (I − K·H) · P  with H = [0, 1]
        p00 = p00 - k0 * p01
        p01 = p01 * r / s
        p11 = p11 * r / s
    }
}

// MARK: - GPS Kalman Filter

/// Online Kalman filter that smooths raw GPS track points.
///
/// Internally uses three independent `KalmanFilter1D` instances for east, north,
/// and altitude axes. GPS lat/lon is converted to a local East-North-Up (ENU) frame
/// in meters from the first observed position.
///
/// ## Usage
///
/// ```swift
/// var filter = GPSKalmanFilter()
/// let smoothed = filter.update(point: rawTrackPoint)
/// ```
///
/// Call `reset()` when starting a new tracking session.
struct GPSKalmanFilter: Sendable {
    private var eastFilter: KalmanFilter1D
    private var northFilter: KalmanFilter1D
    private var altFilter: KalmanFilter1D

    private var originLat: Double       // radians
    private var originLon: Double       // radians
    private var cosOriginLat: Double    // cached cos(originLat)

    private var lastTimestamp: Date?
    private var isInitialized: Bool

    // MARK: - Tuning Constants

    /// Horizontal acceleration noise (m/s²). Accounts for skiing turns, stops, and starts.
    nonisolated private static let horizontalProcessNoise: Double = 3.0
    /// Vertical acceleration noise (m/s²). Altitude changes are smoother than horizontal.
    nonisolated private static let verticalProcessNoise: Double = 1.0
    /// Base GPS Doppler velocity noise (m/s) for good signal conditions.
    nonisolated private static let baseVelocityNoise: Double = 0.3
    /// GPS altitude accuracy is typically this factor worse than horizontal.
    nonisolated private static let altitudeAccuracyFactor: Double = 2.5
    /// Maximum time step before capping (seconds). Prevents covariance explosion on GPS gaps.
    nonisolated private static let maxDt: Double = 10.0
    /// Minimum GPS speed (m/s) for Doppler velocity to be usable.
    nonisolated private static let minDopplerSpeed: Double = 0.1

    /// Meters per degree of latitude (WGS-84 mean).
    nonisolated private static let metersPerDegree: Double = 111_320

    nonisolated init() {
        let zeroFilter = KalmanFilter1D(position: 0, velocity: 0, p00: 0, p01: 0, p11: 0)
        eastFilter = zeroFilter
        northFilter = zeroFilter
        altFilter = zeroFilter
        originLat = 0
        originLon = 0
        cosOriginLat = 1
        lastTimestamp = nil
        isInitialized = false
    }

    /// Filters a raw GPS point and returns a smoothed `TrackPoint`.
    ///
    /// On the first call, initializes the filter state and returns the point unmodified.
    /// Subsequent calls run predict→update and produce a filtered output.
    ///
    /// - Parameter point: Raw GPS track point from `LocationTrackingService`.
    /// - Returns: Filtered track point with smoothed position, speed, and course.
    nonisolated mutating func update(point: TrackPoint) -> TrackPoint {
        guard isInitialized else {
            initialize(from: point)
            return point
        }

        guard let prevTime = lastTimestamp else { return point }
        let rawDt = point.timestamp.timeIntervalSince(prevTime)
        guard rawDt > 0 else { return buildFilteredPoint(from: point) }

        let dt = min(rawDt, Self.maxDt)

        // Scale process noise up when we had a GPS gap (uncertainty grows faster)
        let gapFactor = rawDt > Self.maxDt ? sqrt(rawDt / Self.maxDt) : 1.0
        let hNoise = Self.horizontalProcessNoise * gapFactor
        let vNoise = Self.verticalProcessNoise * gapFactor

        // — Predict —
        eastFilter.predict(dt: dt, processNoiseAccel: hNoise)
        northFilter.predict(dt: dt, processNoiseAccel: hNoise)
        altFilter.predict(dt: dt, processNoiseAccel: vNoise)

        // — Update: position —
        let (east, north) = geoToLocal(lat: point.latitude, lon: point.longitude)
        let posNoise = max(point.accuracy, 1.0)

        eastFilter.updatePosition(measurement: east, noise: posNoise)
        northFilter.updatePosition(measurement: north, noise: posNoise)
        altFilter.updatePosition(measurement: point.altitude, noise: posNoise * Self.altitudeAccuracyFactor)

        // — Update: horizontal velocity from GPS Doppler —
        let gpsSpeed = max(0, point.speed)
        if gpsSpeed > Self.minDopplerSpeed {
            let courseRad = point.course * .pi / 180
            let vEast = gpsSpeed * sin(courseRad)
            let vNorth = gpsSpeed * cos(courseRad)
            let velNoise = Self.baseVelocityNoise * max(1, posNoise / 10)

            eastFilter.updateVelocity(measurement: vEast, noise: velNoise)
            northFilter.updateVelocity(measurement: vNorth, noise: velNoise)
        }

        lastTimestamp = point.timestamp
        return buildFilteredPoint(from: point)
    }

    /// Resets the filter to its uninitialized state. Call when starting a new session.
    nonisolated mutating func reset() {
        let zeroFilter = KalmanFilter1D(position: 0, velocity: 0, p00: 0, p01: 0, p11: 0)
        eastFilter = zeroFilter
        northFilter = zeroFilter
        altFilter = zeroFilter
        originLat = 0
        originLon = 0
        cosOriginLat = 1
        lastTimestamp = nil
        isInitialized = false
    }

    // MARK: - Private

    nonisolated private mutating func initialize(from point: TrackPoint) {
        originLat = point.latitude * .pi / 180
        originLon = point.longitude * .pi / 180
        cosOriginLat = cos(originLat)

        let initialPosVariance = max(point.accuracy * point.accuracy, 1.0)
        let initialVelVariance = 100.0  // 10 m/s uncertainty squared

        eastFilter = KalmanFilter1D(
            position: 0, velocity: 0,
            p00: initialPosVariance, p01: 0, p11: initialVelVariance
        )
        northFilter = KalmanFilter1D(
            position: 0, velocity: 0,
            p00: initialPosVariance, p01: 0, p11: initialVelVariance
        )
        altFilter = KalmanFilter1D(
            position: point.altitude, velocity: 0,
            p00: initialPosVariance * Self.altitudeAccuracyFactor * Self.altitudeAccuracyFactor,
            p01: 0,
            p11: initialVelVariance
        )

        lastTimestamp = point.timestamp
        isInitialized = true
    }

    nonisolated private func geoToLocal(lat: Double, lon: Double) -> (east: Double, north: Double) {
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let east = (lonRad - originLon) * cosOriginLat * Self.metersPerDegree * (180 / .pi)
        let north = (latRad - originLat) * Self.metersPerDegree * (180 / .pi)
        return (east, north)
    }

    nonisolated private func localToGeo(east: Double, north: Double) -> (lat: Double, lon: Double) {
        let latRad = originLat + north / (Self.metersPerDegree * (180 / .pi))
        let lonRad = originLon + east / (cosOriginLat * Self.metersPerDegree * (180 / .pi))
        return (latRad * 180 / .pi, lonRad * 180 / .pi)
    }

    nonisolated private func buildFilteredPoint(from original: TrackPoint) -> TrackPoint {
        let (lat, lon) = localToGeo(east: eastFilter.position, north: northFilter.position)
        let speed = sqrt(
            eastFilter.velocity * eastFilter.velocity
            + northFilter.velocity * northFilter.velocity
        )
        let courseRad = atan2(eastFilter.velocity, northFilter.velocity)
        let courseDeg = courseRad * 180 / .pi
        let normalizedCourse = courseDeg >= 0 ? courseDeg : courseDeg + 360

        return TrackPoint(
            timestamp: original.timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altFilter.position,
            speed: max(0, speed),
            accuracy: original.accuracy,
            course: normalizedCourse
        )
    }
}
