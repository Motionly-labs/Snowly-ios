//
//  MotionEstimate.swift
//  Snowly
//
//  Public intermediate type produced by MotionEstimator.
//  Replaces the private MotionFeatures struct in RunDetectionService.
//  No platform-specific imports — shared between iOS and watchOS.
//

import Foundation

enum MotionEstimateWindow: String, Sendable, Equatable {
    case transition
    case steady
}

/// Aggregated motion features computed over a rolling GPS window.
struct MotionEstimate: Sendable, Equatable {
    /// Duration of the feature window in seconds (≥ 1).
    let duration: TimeInterval
    /// Average horizontal speed (m/s) — haversine path length / duration.
    let avgHorizontalSpeed: Double
    /// Average vertical rate (m/s) — altitude delta / duration.
    /// Positive = ascending, negative = descending.
    let avgVerticalSpeed: Double
    /// True when enough history exists and the altitude trend exceeds the noise floor.
    /// When false, altitude-sensitive rules (lift/descent) are bypassed.
    let hasReliableAltitudeTrend: Bool
    /// Number of filtered samples used to compute the estimate, including `current`.
    let sampleCount: Int
    /// Confidence in [0, 1], higher when the time window is well covered.
    let confidence: Double
    /// The source window used for this estimate.
    let window: MotionEstimateWindow

    nonisolated init(
        duration: TimeInterval,
        avgHorizontalSpeed: Double,
        avgVerticalSpeed: Double,
        hasReliableAltitudeTrend: Bool,
        sampleCount: Int = 0,
        confidence: Double = 0,
        window: MotionEstimateWindow = .steady
    ) {
        self.duration = duration
        self.avgHorizontalSpeed = avgHorizontalSpeed
        self.avgVerticalSpeed = avgVerticalSpeed
        self.hasReliableAltitudeTrend = hasReliableAltitudeTrend
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.window = window
    }
}
