//
//  RunDetectionService.swift
//  Snowly
//
//  Pure-function activity detection using a rolling feature window.
//  Motion estimation is delegated to MotionEstimator.
//  No side effects — all state is passed in, result is returned.
//

import Foundation

/// Result of analyzing a track point for activity detection.
enum DetectedActivity: Sendable, Equatable {
    case idle
    case lift
    case skiing
    case walk
}

extension DetectedActivity {
    var activityName: String {
        switch self {
        case .skiing: "skiing"
        case .lift:   "lift"
        case .idle:   "idle"
        case .walk:   "walk"
        }
    }
}

/// Optional CoreMotion hint that can strengthen lift classification.
enum MotionHint: Sendable, Equatable {
    case unknown
    case automotive   // CoreMotion detected smooth motorized movement (gondola / chairlift)
}

enum RunDetectionService {

    /// Classifies a GPS track point into one of four ski activity states.
    ///
    /// Returns a **raw** classification. Callers must apply dwell-time hysteresis
    /// (`SessionTrackingService.applyDwellTime`) before surfacing the result.
    ///
    /// Delegates motion feature extraction to `MotionEstimator.estimate()` and classification
    /// to `classify(estimate:motion:)`. See `classify` for the full decision tree.
    ///
    /// - Parameters:
    ///   - point: Current GPS track point.
    ///   - recentPoints: Recent history buffer (chronological, not including `point`).
    ///   - previousActivity: Previous stable activity, used for lift continuity handling.
    /// - Returns: Raw detected activity. Apply dwell-time hysteresis before acting on it.
    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        previousActivity: DetectedActivity = .idle
    ) -> DetectedActivity {
        detect(
            point: point,
            recentPoints: recentPoints,
            previousActivity: previousActivity,
            motion: .unknown
        )
    }

    /// Overload that accepts a CoreMotion hint for enhanced lift detection.
    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        motion: MotionHint
    ) -> DetectedActivity {
        detect(
            point: point,
            recentPoints: recentPoints,
            previousActivity: .idle,
            motion: motion
        )
    }

    /// Overload that accepts prior activity and CoreMotion hint.
    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        previousActivity: DetectedActivity,
        motion: MotionHint
    ) -> DetectedActivity {
        let estimate = MotionEstimator.estimate(current: point, recentPoints: recentPoints)
        return classify(estimate: estimate, previousActivity: previousActivity, motion: motion)
    }

    /// Raw-array overload for callers that store timestamps and altitudes separately.
    /// Reconstructs `TrackPoint` values using the current point's position and passes
    /// through to the standard overload.
    nonisolated static func detect(
        point: TrackPoint,
        recentTimestamps: [Double],
        recentAltitudes: [Double],
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectedActivity {
        let recentPoints = zip(recentTimestamps, recentAltitudes).map { ts, alt in
            TrackPoint(
                timestamp: Date(timeIntervalSinceReferenceDate: ts),
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: alt,
                speed: point.speed,
                accuracy: point.accuracy,
                course: point.course
            )
        }
        return detect(
            point: point,
            recentPoints: recentPoints,
            previousActivity: previousActivity,
            motion: motion
        )
    }

    /// Whether the current idle period has lasted long enough to end a run.
    nonisolated static func shouldEndRun(
        lastActivityTime: Date,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(lastActivityTime) >= SharedConstants.stopDurationThreshold
    }

    // MARK: - Internal (testable)

    /// Maps a `MotionEstimate` and optional CoreMotion hint to a `DetectedActivity`.
    ///
    /// This is the single classification authority for the entire run-detection pipeline.
    /// `internal` access allows unit tests to supply synthetic `MotionEstimate` values
    /// without going through the full GPS pipeline.
    ///
    /// ## State Decision Logic (evaluated in priority order)
    ///
    /// | # | Condition                                          | Result    |
    /// |---|----------------------------------------------------|-----------|
    /// | 1 | `h < idleSpeedMax` (0.6 m/s)                      | `.idle`   |
    /// | 2 | `motion == .automotive`                            | `.lift`   |
    /// | 3 | `h ≥ skiFastMin` (6.0 m/s)                        | `.skiing` |
    /// | 4 | reliable trend AND `h ≥ skiMinSpeed` (2.8) AND `v ≤ skiVerticalSpeedMax` (−0.15) | `.skiing` |
    /// | 5 | previous is lift AND continuity band AND `v ≥ liftContinuityVerticalSpeedMin` | `.lift` |
    /// | 6 | reliable trend AND `h ∈ [liftSpeedMin, liftSpeedMax]` [1.2, 6.5] AND `v ≥ liftVerticalSpeedMin` (−0.10) | `.lift` |
    /// | 7 | previous is lift AND speed continuity band (no reliable trend) | `.lift` |
    /// | 8 | `h ≥ skiMinSpeed` (2.8) [no altitude context]     | `.skiing` |
    /// | 9 | fallthrough                                        | `.idle`   |
    ///
    /// Rules 4–5 require `estimate.hasReliableAltitudeTrend = true`; when false, the
    /// classifier falls through directly to rule 6/7 (speed-only path).
    ///
    /// - Parameters:
    ///   - estimate: Feature vector from `MotionEstimator.estimate()`. `h` and `v` are in m/s.
    ///   - previousActivity: Previous stable activity after dwell-time filtering.
    ///   - motion: Optional CoreMotion hint. `.automotive` short-circuits to `.lift` (rule 2).
    /// - Returns: Raw activity classification. Apply dwell-time hysteresis before surfacing.
    ///
    /// ## Thresholds
    ///
    /// * `idleSpeedMax = 0.6 m/s` — below this, motion is too slow for any ski activity.
    /// * `skiFastMin = 6.0 m/s` — above this, speed alone confirms skiing; no lift moves this fast.
    /// * `skiMinSpeed = 2.8 m/s` — minimum horizontal speed for the altitude-informed skiing rule.
    /// * `skiVerticalSpeedMax = −0.15 m/s` — must be descending at ≥ 0.15 m/s to confirm skiing.
    /// * `liftSpeedMin = 1.2 m/s` — minimum horizontal speed for chairlift / gondola detection.
    /// * `liftSpeedMax = 6.5 m/s` — above this, an ascending object is more likely an outlier.
    /// * `liftVerticalSpeedMin = −0.10 m/s` — allows slight descent (gondola transition sections).
    ///
    /// ## Edge Cases
    ///
    /// * `hasReliableAltitudeTrend = false` → rules 4 and 5 are skipped entirely; classification
    ///   falls through to speed-only rule 6/7 (speeds in [0.6, 2.8) return `.idle`).
    /// * `motion == .automotive` short-circuits to `.lift` regardless of speed or altitude (rule 2).
    /// * When `previousActivity == .lift`, continuity guards prefer `.lift` through flat/brief descent sections.
    /// * Speed between `idleSpeedMax` (0.6) and `skiMinSpeed` (2.8) with no lift continuity context → `.idle`.
    nonisolated internal static func classify(
        estimate: MotionEstimate,
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectedActivity {
        let h = estimate.avgHorizontalSpeed
        let v = estimate.avgVerticalSpeed

        // Barely moving — idle regardless of altitude
        if h < SharedConstants.idleSpeedMax { return .idle }

        // Automotive motion hint overrides to lift (motorized transport confirmed)
        if motion == .automotive { return .lift }

        // Very fast — definitely skiing regardless of altitude
        if h >= SharedConstants.skiFastMin { return .skiing }

        let wasLift = previousActivity == .lift
        let inLiftSpeedBand = h >= SharedConstants.liftSpeedMin && h <= SharedConstants.liftSpeedMax

        if estimate.hasReliableAltitudeTrend {
            // Preserve lift across horizontal / slight descent transfer sections.
            if wasLift
                && inLiftSpeedBand
                && v >= SharedConstants.liftContinuityVerticalSpeedMin {
                return .lift
            }

            // Medium-fast + descending — skiing
            if h >= SharedConstants.skiMinSpeed && v <= SharedConstants.skiVerticalSpeedMax {
                return .skiing
            }
            // Moderate speed + not steeply descending — lift (gondola, chairlift)
            if inLiftSpeedBand && v >= SharedConstants.liftVerticalSpeedMin {
                return .lift
            }
        }

        // No reliable trend: keep lift continuity through flat sections.
        if wasLift && inLiftSpeedBand {
            return .lift
        }

        // No reliable altitude context: classify by speed alone
        // (below skiMinSpeed we default to idle — not enough speed for skiing or walk)
        return h >= SharedConstants.skiMinSpeed ? .skiing : .idle
    }
}
