//
//  SegmentValidator.swift
//  Snowly
//
//  Single source of truth for segment quality validation.
//  Replaces identical 30-line inline blocks in TrackingEngine,
//  SegmentFinalizationService, and SnowlyApp.
//

import Foundation

enum SegmentValidator {

    /// Validates a raw segment and returns the effective `RunActivityType`, or `nil` to discard it.
    ///
    /// After real-time classification assigns a type, this validator confirms the segment meets
    /// minimum physical criteria. Segments that fail are demoted to `.walk`; very short walks
    /// are discarded entirely. This prevents noisy lift-exit transitions and GPS glitches from
    /// polluting session history.
    ///
    /// ## Algorithm
    ///
    /// 1. **Skiing validation** (only when `activityType == .skiing`):
    ///    - Compute `altitudeLoss = firstPoint.altitude − lastPoint.altitude`.
    ///    - Valid when ALL three hold: `duration ≥ 15 s`, `altitudeLoss ≥ 12 m`,
    ///      `averageSpeed ≥ 3.5 m/s`. Any failure → demote to `.walk`.
    ///
    /// 2. **Lift validation** (only when `activityType == .lift`):
    ///    - Compute `altitudeGain = lastPoint.altitude − firstPoint.altitude` and
    ///      `avgVerticalSpeed = altitudeGain / max(duration, 1)`.
    ///    - Valid when ALL three hold: `duration ≥ 30 s`, `altitudeGain ≥ 20 m`,
    ///      `avgVerticalSpeed ≥ 0.10 m/s`. Any failure → demote to `.walk`.
    ///
    /// 3. **Walk discard**: if `effective == .walk` AND `duration < 6 s` → return `nil`.
    ///
    /// 4. **Physics guard rail**: if `effective == .walk` AND `averageSpeed ≥ 8.0 m/s`,
    ///    restore the original `activityType` because that speed is not physically plausible for walking.
    ///
    /// 5. Otherwise return `effective`. `.idle` segments bypass all validation unchanged.
    ///
    /// - Parameters:
    ///   - activityType: Raw segment type from the classifier (`.skiing`, `.lift`, `.idle`, `.walk`).
    ///   - firstPoint:   Chronologically first `TrackPoint` in the segment.
    ///   - lastPoint:    Chronologically last `TrackPoint` in the segment.
    ///   - duration:     Total segment duration in seconds (≥ 0).
    ///   - averageSpeed: Mean horizontal speed over the segment in m/s (≥ 0).
    /// - Returns: Validated effective type, or `nil` if the segment should be discarded.
    ///
    /// ## Thresholds
    ///
    /// * `minSkiRunDuration = 15 s` — shorter segments are likely lift-exit transitions, not real runs.
    /// * `skiMinAltitudeLoss = 12 m` — minimum vertical drop to confirm a ski run.
    /// * `skiMinAvgSpeed = 3.5 m/s` — minimum average speed for a meaningful ski run.
    /// * `liftMinSegmentDuration = 30 s` — very short lifts are almost certainly false positives.
    /// * `liftMinAltitudeGain = 20 m` — minimum altitude gain to confirm a ski lift ride.
    /// * `liftMinAvgVerticalSpeed = 0.10 m/s` — distinguishes a lift from slow uphill walking.
    /// * `walkMinSegmentDuration = 6 s` — sub-threshold walk segments add noise to session history.
    /// * `walkHardMaxSpeed = 8.0 m/s` — hard guard rail: walking above this speed is impossible.
    ///
    /// ## Edge Cases
    ///
    /// * `duration = 0` — lift's `avgVerticalSpeed` uses `max(duration, 1)` to avoid division by zero.
    /// * A segment demoted from `.skiing` / `.lift` to `.walk` still undergoes the walk-discard check.
    /// * `.idle` segments are returned unchanged without any validation.
    nonisolated static func effectiveType(
        activityType: RunActivityType,
        firstPoint: TrackPoint,
        lastPoint: TrackPoint,
        duration: TimeInterval,
        averageSpeed: Double
    ) -> RunActivityType? {
        var effective = activityType

        if activityType == .skiing {
            let altitudeLoss = firstPoint.altitude - lastPoint.altitude
            let valid = duration >= SharedConstants.minSkiRunDuration
                     && altitudeLoss >= SharedConstants.skiMinAltitudeLoss
                     && averageSpeed >= SharedConstants.skiMinAvgSpeed
            if !valid { effective = .walk }
        }

        if activityType == .lift {
            let altitudeGain = lastPoint.altitude - firstPoint.altitude
            let avgVerticalSpeed = altitudeGain / max(duration, 1)
            let valid = duration >= SharedConstants.liftMinSegmentDuration
                     && altitudeGain >= SharedConstants.liftMinAltitudeGain
                     && avgVerticalSpeed >= SharedConstants.liftMinAvgVerticalSpeed
            if !valid { effective = .walk }
        }

        if effective == .walk, duration < SharedConstants.walkMinSegmentDuration {
            return nil
        }

        if effective == .walk,
           averageSpeed >= SharedConstants.walkHardMaxSpeed,
           activityType != .walk {
            effective = activityType
        }

        return effective
    }

    /// Returns the meaningful altitude change (m) for a completed segment, clamped to ≥ 0.
    ///
    /// The direction convention differs by activity type so callers never need to reason about
    /// the sign of raw altitude deltas:
    ///
    /// - `.skiing`: descent — `max(0, firstAltitude − lastAltitude)`.
    ///   A segment that ends higher than it started yields 0 (GPS noise, not a genuine climb).
    /// - `.lift`:   ascent  — `max(0, lastAltitude − firstAltitude)`.
    ///   A segment that ends lower than it started yields 0.
    /// - `.walk`, `.idle`: always 0 — these activities do not contribute vertical statistics.
    ///
    /// - Parameters:
    ///   - effectiveType:  The validated activity type (output of `effectiveType(...)`).
    ///   - firstAltitude:  Altitude of the first track point in the segment, in meters above sea level.
    ///   - lastAltitude:   Altitude of the last track point in the segment, in meters above sea level.
    /// - Returns: Non-negative altitude drop or gain in meters appropriate for the activity type.
    nonisolated static func verticalDrop(
        effectiveType: RunActivityType,
        firstAltitude: Double,
        lastAltitude: Double
    ) -> Double {
        switch effectiveType {
        case .skiing: return max(0, firstAltitude - lastAltitude)
        case .lift:   return max(0, lastAltitude - firstAltitude)
        case .idle, .walk: return 0
        }
    }
}
