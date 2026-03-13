//
//  RunDetectionService.swift
//  Snowly
//
//  Pure-function activity detection using short and steady time windows.
//

import Foundation

/// Result of analyzing a track point for activity detection.
enum DetectedActivity: Sendable, Equatable {
    case idle
    case lift
    case skiing
    case walk

    nonisolated static func == (lhs: DetectedActivity, rhs: DetectedActivity) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.lift, .lift), (.skiing, .skiing), (.walk, .walk): true
        default: false
        }
    }
}

extension DetectedActivity {
    nonisolated var activityName: String {
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
    case automotive
}

struct DetectionDecision: Sendable, Equatable {
    let activity: DetectedActivity
    let shouldAccelerateDwell: Bool
    let transitionEstimate: MotionEstimate
    let steadyEstimate: MotionEstimate
}

enum RunDetectionService {
    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        previousActivity: DetectedActivity = .idle
    ) -> DetectedActivity {
        detect(
            point: point.filteredEstimatePoint,
            recentPoints: recentPoints.map(\.filteredEstimatePoint),
            previousActivity: previousActivity
        )
    }

    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        motion: MotionHint
    ) -> DetectedActivity {
        detect(
            point: point.filteredEstimatePoint,
            recentPoints: recentPoints.map(\.filteredEstimatePoint),
            motion: motion
        )
    }

    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        previousActivity: DetectedActivity,
        motion: MotionHint
    ) -> DetectedActivity {
        detect(
            point: point.filteredEstimatePoint,
            recentPoints: recentPoints.map(\.filteredEstimatePoint),
            previousActivity: previousActivity,
            motion: motion
        )
    }

    nonisolated static func detect(
        point: TrackPoint,
        recentTimestamps: [Double],
        recentAltitudes: [Double],
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectedActivity {
        detect(
            point: point.filteredEstimatePoint,
            recentTimestamps: recentTimestamps,
            recentAltitudes: recentAltitudes,
            previousActivity: previousActivity,
            motion: motion
        )
    }


    nonisolated static func detect(
        point: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        previousActivity: DetectedActivity = .idle
    ) -> DetectedActivity {
        analyze(
            point: point,
            recentPoints: recentPoints,
            previousActivity: previousActivity,
            motion: .unknown
        ).activity
    }

    nonisolated static func detect(
        point: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        motion: MotionHint
    ) -> DetectedActivity {
        analyze(
            point: point,
            recentPoints: recentPoints,
            previousActivity: .idle,
            motion: motion
        ).activity
    }

    nonisolated static func detect(
        point: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        previousActivity: DetectedActivity,
        motion: MotionHint
    ) -> DetectedActivity {
        analyze(
            point: point,
            recentPoints: recentPoints,
            previousActivity: previousActivity,
            motion: motion
        ).activity
    }

    nonisolated static func analyze(
        point: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectionDecision {
        let transitionEstimate = MotionEstimator.transitionEstimate(
            current: point,
            recentPoints: recentPoints
        )
        let steadyEstimate = MotionEstimator.steadyEstimate(
            current: point,
            recentPoints: recentPoints
        )

        let transitionActivity = classify(
            estimate: transitionEstimate,
            previousActivity: previousActivity,
            motion: motion
        )
        let steadyActivity = classify(
            estimate: steadyEstimate,
            previousActivity: previousActivity,
            motion: motion
        )

        let resolvedActivity = resolveActivity(
            previousActivity: previousActivity,
            transitionActivity: transitionActivity,
            steadyActivity: steadyActivity,
            transitionEstimate: transitionEstimate,
            steadyEstimate: steadyEstimate
        )

        return DetectionDecision(
            activity: resolvedActivity,
            shouldAccelerateDwell: shouldAccelerateDwell(
                previousActivity: previousActivity,
                resolvedActivity: resolvedActivity,
                transitionActivity: transitionActivity,
                steadyActivity: steadyActivity,
                transitionEstimate: transitionEstimate,
                steadyEstimate: steadyEstimate
            ),
            transitionEstimate: transitionEstimate,
            steadyEstimate: steadyEstimate
        )
    }

    /// Constructs synthetic history using only `recentTimestamps` and `recentAltitudes`.
    /// All synthesized points share the current point's lat/lon and speed, so
    /// `horizontalDistance` is always 0 for every window pair and `avgHorizontalSpeed`
    /// always falls back to `current.estimatedSpeed`. This overload exercises
    /// altitude-based detection paths only — do not assert `avgHorizontalSpeed` against it.
    nonisolated static func detect(
        point: FilteredTrackPoint,
        recentTimestamps: [Double],
        recentAltitudes: [Double],
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectedActivity {
        let recentPoints = zip(recentTimestamps, recentAltitudes).map { ts, alt in
            FilteredTrackPoint(
                rawTimestamp: Date(timeIntervalSinceReferenceDate: ts),
                timestamp: Date(timeIntervalSinceReferenceDate: ts),
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: alt,
                estimatedSpeed: point.estimatedSpeed,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
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

    nonisolated static func shouldEndRun(
        lastActivityTime: Date,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(lastActivityTime) >= SharedConstants.stopDurationThreshold
    }

    nonisolated internal static func classify(
        estimate: MotionEstimate,
        previousActivity: DetectedActivity = .idle,
        motion: MotionHint = .unknown
    ) -> DetectedActivity {
        let h = estimate.avgHorizontalSpeed
        let v = estimate.avgVerticalSpeed

        if h < SharedConstants.idleSpeedMax { return .idle }
        if case .automotive = motion { return .lift }
        if h >= SharedConstants.skiFastMin { return .skiing }

        let wasLift = previousActivity == .lift
        let inLiftSpeedBand = h >= SharedConstants.liftSpeedMin && h <= SharedConstants.liftSpeedMax

        if estimate.hasReliableAltitudeTrend {
            if wasLift
                && inLiftSpeedBand
                && v >= SharedConstants.liftContinuityVerticalSpeedMin {
                return .lift
            }

            if h >= SharedConstants.skiMinSpeed && v <= SharedConstants.skiVerticalSpeedMax {
                return .skiing
            }

            if inLiftSpeedBand && v >= SharedConstants.liftVerticalSpeedMin {
                return .lift
            }
        }

        if wasLift && inLiftSpeedBand {
            return .lift
        }

        if inLiftSpeedBand {
            return classifyAmbiguousLiftBand(previousActivity: previousActivity)
        }

        return h >= SharedConstants.skiMinSpeed ? .skiing : .idle
    }

    nonisolated private static func classifyAmbiguousLiftBand(
        previousActivity: DetectedActivity
    ) -> DetectedActivity {
        switch previousActivity {
        case .lift:
            return .lift
        case .skiing:
            return .skiing
        case .walk, .idle:
            return .walk
        }
    }

    nonisolated private static func resolveActivity(
        previousActivity: DetectedActivity,
        transitionActivity: DetectedActivity,
        steadyActivity: DetectedActivity,
        transitionEstimate: MotionEstimate,
        steadyEstimate: MotionEstimate
    ) -> DetectedActivity {
        if transitionActivity == steadyActivity {
            return transitionActivity
        }

        if transitionEstimate.confidence < SharedConstants.transitionOverrideConfidence {
            return steadyActivity
        }

        if steadyActivity == previousActivity {
            return transitionActivity
        }

        if transitionActivity == previousActivity {
            return steadyActivity
        }

        if transitionEstimate.confidence >= max(
            SharedConstants.transitionStrongOverrideConfidence,
            steadyEstimate.confidence + 0.15
        ) {
            return transitionActivity
        }

        return steadyActivity
    }

    nonisolated private static func shouldAccelerateDwell(
        previousActivity: DetectedActivity,
        resolvedActivity: DetectedActivity,
        transitionActivity: DetectedActivity,
        steadyActivity: DetectedActivity,
        transitionEstimate: MotionEstimate,
        steadyEstimate: MotionEstimate
    ) -> Bool {
        guard resolvedActivity != previousActivity else { return false }
        guard transitionActivity == resolvedActivity else { return false }
        guard transitionEstimate.confidence >= SharedConstants.acceleratedDwellConfidence else { return false }

        if steadyActivity == resolvedActivity {
            return true
        }

        return transitionEstimate.confidence >= max(
            SharedConstants.transitionStrongOverrideConfidence,
            steadyEstimate.confidence + 0.15
        )
    }
}
