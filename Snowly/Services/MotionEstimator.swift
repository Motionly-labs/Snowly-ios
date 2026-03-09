//
//  MotionEstimator.swift
//  Snowly
//
//  Pure functions for computing motion features from GPS track points.
//  Extracted from RunDetectionService.computeFeatures() to allow independent testing.
//  No platform-specific imports — shared between iOS and watchOS.
//

import Foundation

enum MotionEstimator {

    // MARK: - Private Thresholds

    /// Minimum number of recent points required to establish a reliable altitude trend.
    /// At 1 Hz GPS sampling this equals ~featureWindowSeconds of history.
    private static let minHistoryForAltitudeTrend = 8

    /// Minimum in-window time span (s) required before trusting an altitude slope.
    /// Prevents low-frequency samples from producing "reliable" trends from only 1-2 points.
    private static let minAltitudeTrendTimeSpan: TimeInterval = 4

    /// Altitude rate (m/s) below which the trend is considered noise and ignored.
    /// Symmetric to |skiVerticalSpeedMax| so that ambiguous flat/gentle slopes fall through
    /// to the speed-only classification path.
    private static let altitudeTrendMinRate = 0.15

    /// Minimum haversine-derived horizontal speed (m/s) before falling back to GPS speed.
    /// Points created at the same lat/lon (e.g. in tests) produce haversine ≈ 0.
    private static let haversineFallbackThreshold = 0.5

    // MARK: - Public API

    /// Computes a `MotionEstimate` from the current GPS point and its rolling history window.
    ///
    /// Produces the feature vector consumed by `RunDetectionService.classify(estimate:motion:)`.
    /// Path-integrated haversine distance is used instead of a point-to-point displacement so
    /// that direction changes between samples (e.g. slalom turns) are correctly accounted for.
    ///
    /// ## Algorithm
    ///
    /// 1. Filter `recentPoints` to those within `featureWindowSeconds` (8 s) of `current.timestamp`.
    /// 2. If the filtered window is empty, return GPS-reported speed, `avgVerticalSpeed = 0`,
    ///    and `hasReliableAltitudeTrend = false` (no altitude context available yet).
    /// 3. Compute `duration` = time from the oldest window point to `current`, clamped to ≥ 1 s.
    /// 4. Sum haversine segment distances along `windowPoints + [current]` to get the total path
    ///    length. Divide by `duration` for `haversineH`. If `haversineH < haversineFallbackThreshold`
    ///    (0.5 m/s), substitute GPS Doppler speed — this covers same-location test fixtures and
    ///    momentary GPS stalls where haversine collapses to zero.
    /// 5. Apply a sliding-window median filter (size 3) to all altitude values when ≥ 3 points
    ///    exist, suppressing transient GPS altitude spikes before computing the vertical rate.
    /// 6. Compute `v = (filteredLastAltitude − filteredFirstAltitude) / duration`.
    ///    Positive = ascending (lift direction), negative = descending (ski direction).
    /// 7. Set `hasReliableAltitudeTrend = (window history count ≥ 8) AND (window span ≥ 4 s)
    ///    AND (|v| ≥ 0.15 m/s)`.
    ///    When false, callers must not apply altitude-sensitive classification rules.
    ///
    /// - Parameters:
    ///   - current: The newest GPS point, already accuracy-filtered by `LocationTrackingService`.
    ///              Its `speed` field is the GPS Doppler-derived speed in m/s.
    ///   - recentPoints: Chronological history buffer **not** including `current`. May be empty.
    /// - Returns: A `MotionEstimate` with horizontal speed (m/s), vertical rate (m/s),
    ///            window duration (s), and a flag indicating whether the altitude trend is reliable.
    ///
    /// ## Thresholds
    ///
    /// * `featureWindowSeconds = 8 s` — history beyond this is too stale for real-time classification.
    /// * `minHistoryForAltitudeTrend = 8` — fewer GPS samples produce an unreliable altitude slope.
    /// * `altitudeTrendMinRate = 0.15 m/s` — vertical rates below this are indistinguishable from GPS noise.
    /// * `haversineFallbackThreshold = 0.5 m/s` — haversine speed below this triggers GPS Doppler fallback.
    ///
    /// ## Edge Cases
    ///
    /// * Empty history → instant snapshot only; `hasReliableAltitudeTrend` is always `false`.
    /// * Fewer than 3 altitude points → median filter is skipped; raw values are used directly.
    /// * Identical timestamps in window → `duration` is clamped to 1 s to prevent division by zero.
    /// * Negative GPS speed (some devices report −1 when unavailable) → clamped to 0 before use.
    nonisolated static func estimate(current: TrackPoint, recentPoints: [TrackPoint]) -> MotionEstimate {
        let windowStart = current.timestamp.addingTimeInterval(-SharedConstants.featureWindowSeconds)
        let windowPoints = recentPoints.filter { $0.timestamp >= windowStart }

        let gpsSpeed = max(0, current.speed)

        guard let first = windowPoints.first else {
            // No history yet — GPS speed only, no altitude context.
            return MotionEstimate(
                duration: 1,
                avgHorizontalSpeed: gpsSpeed,
                avgVerticalSpeed: 0,
                hasReliableAltitudeTrend: false
            )
        }

        let duration = max(current.timestamp.timeIntervalSince(first.timestamp), 1)

        // Horizontal: sum haversine distances along path (accounts for direction changes)
        var horizontalDistance = 0.0
        let allPoints = windowPoints + [current]
        for i in 1..<allPoints.count {
            horizontalDistance += allPoints[i - 1].distance(to: allPoints[i])
        }
        let haversineH = horizontalDistance / duration
        // Fall back to GPS Doppler speed when haversine is negligible (same-location points)
        let h = haversineH > haversineFallbackThreshold ? haversineH : gpsSpeed

        // Vertical: apply median filter to altitude values to suppress GPS spikes
        let rawAltitudes = allPoints.map(\.altitude)
        let filteredAltitudes = rawAltitudes.count >= 3
            ? medianFilter(values: rawAltitudes, windowSize: 3)
            : rawAltitudes
        let altitudeChange = (filteredAltitudes.last ?? current.altitude) - (filteredAltitudes.first ?? first.altitude)
        let v = altitudeChange / duration

        // Reliable trend requires minimum history AND a clear altitude signal
        let hasEnoughHistory = windowPoints.count >= minHistoryForAltitudeTrend
        let hasEnoughTimeSpan = duration >= minAltitudeTrendTimeSpan
        let hasReliableTrend = hasEnoughHistory && hasEnoughTimeSpan && abs(v) >= altitudeTrendMinRate

        return MotionEstimate(
            duration: duration,
            avgHorizontalSpeed: h,
            avgVerticalSpeed: v,
            hasReliableAltitudeTrend: hasReliableTrend
        )
    }

    /// Applies a symmetric sliding-window median filter, suppressing isolated spikes.
    ///
    /// Choosing median over mean ensures a single extreme outlier cannot distort the trend signal.
    /// Used by `estimate(current:recentPoints:)` to clean GPS altitude values before computing
    /// the vertical rate.
    ///
    /// ## Algorithm
    ///
    /// For each index `i`:
    /// 1. Compute `lo = max(0, i − half)` and `hi = min(n−1, i + half)` where `half = windowSize / 2`.
    ///    Edge elements therefore use an asymmetric (narrower) window — no zero-padding or mirroring.
    /// 2. Sort the subslice `values[lo...hi]` and return `window[count / 2]` (lower median for even sizes).
    ///
    /// Output length always equals input length.
    ///
    /// - Parameters:
    ///   - values: Input signal values (any unit, e.g. altitude in meters).
    ///   - windowSize: Total width of the median window. Odd values produce a symmetric centre.
    ///                 A value of 1 is an identity pass.
    /// - Returns: Filtered array of the same length as `values`.
    ///
    /// ## Edge Cases
    ///
    /// * `windowSize ≤ 0` or empty `values` → returns `values` unchanged.
    /// * `windowSize = 1` → identity; each element is the median of a window of size 1.
    /// * Boundary elements use only available neighbours on one side.
    nonisolated static func medianFilter(values: [Double], windowSize: Int) -> [Double] {
        guard windowSize > 0, !values.isEmpty else { return values }
        let half = windowSize / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let window = values[lo...hi].sorted()
            return window[window.count / 2]
        }
    }
}
