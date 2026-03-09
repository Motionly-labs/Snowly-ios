//
//  MotionEstimate.swift
//  Snowly
//
//  Public intermediate type produced by MotionEstimator.
//  Replaces the private MotionFeatures struct in RunDetectionService.
//  No platform-specific imports — shared between iOS and watchOS.
//

import Foundation

/// Aggregated motion features computed over a rolling GPS window.
struct MotionEstimate: Sendable, Equatable {
    /// Duration of the feature window in seconds (≥ 1).
    let duration: TimeInterval
    /// Average horizontal speed (m/s) — haversine path length / duration,
    /// falling back to GPS-reported speed when position delta is negligible.
    let avgHorizontalSpeed: Double
    /// Average vertical rate (m/s) — altitude delta / duration.
    /// Positive = ascending, negative = descending.
    let avgVerticalSpeed: Double
    /// True when enough history exists and the altitude trend exceeds the noise floor.
    /// When false, altitude-sensitive rules (lift/descent) are bypassed.
    let hasReliableAltitudeTrend: Bool
}
