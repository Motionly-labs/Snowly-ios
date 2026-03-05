//
//  RunDetectionService.swift
//  Snowly
//
//  Pure-function run/chairlift/idle detection.
//  Uses speed + altitude trend + CoreMotion for triple-confirmation.
//  No side effects — all state is passed in, result is returned.
//

import Foundation

/// Result of analyzing a track point for activity detection.
enum DetectedActivity: Sendable, Equatable {
    case idle
    case chairlift
    case skiing
}

enum RunDetectionService {

    /// Determines activity type from a new track point plus recent history.
    ///
    /// Algorithm:
    /// - speed < gpsNoiseFloor → idle (GPS drift filter)
    /// - speed < idleSpeedThreshold → idle
    /// - speed > chairliftMaxSpeed → skiing (lifts can't go this fast)
    /// - speed 1.5–6 m/s + altitude rising → chairlift
    /// - speed > skiingMinSpeed + altitude falling/flat → skiing
    ///
    /// - Parameters:
    ///   - point: The current track point.
    ///   - recentPoints: Last 5-10 points for altitude trend analysis.
    ///   - motion: Current CoreMotion activity (optional enhancement).
    /// - Returns: The detected activity type.
    static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        motion: DetectedMotion = .unknown
    ) -> DetectedActivity {
        let speed = point.speed

        // GPS noise filter
        if speed < SharedConstants.gpsNoiseFloor {
            return .idle
        }

        // Clearly idle
        if speed < SharedConstants.idleSpeedThreshold {
            return .idle
        }

        // Too fast for a chairlift — definitely skiing
        if speed > SharedConstants.chairliftMaxSpeed {
            return .skiing
        }

        // Analyze altitude trend from recent points
        let altitudeTrend = calculateAltitudeTrend(current: point, recent: recentPoints)

        // Medium speed range: use altitude trend to distinguish
        if speed >= SharedConstants.idleSpeedThreshold
            && speed <= SharedConstants.chairliftMaxSpeed {

            if altitudeTrend > SharedConstants.altitudeTrendUpThreshold {
                // Altitude is rising consistently → chairlift
                return .chairlift
            }

            if altitudeTrend < SharedConstants.altitudeTrendDownThreshold {
                // Altitude is dropping → skiing
                return .skiing
            }

            // Flat altitude at medium speed: use CoreMotion hint
            if motion == .automotive {
                return .chairlift
            }
        }

        // Default: if above skiing threshold and altitude not rising
        if speed >= SharedConstants.skiingMinSpeed {
            return .skiing
        }

        return .idle
    }

    /// Applies a median filter to smooth altitude values and remove GPS spikes.
    /// Window size must be odd; values at edges use a smaller window.
    static func medianFilter(
        values: [Double],
        windowSize: Int = SharedConstants.medianFilterWindowSize
    ) -> [Double] {
        guard values.count >= windowSize, windowSize >= 3 else { return values }
        let halfWindow = windowSize / 2
        return values.indices.map { i in
            let start = max(0, i - halfWindow)
            let end = min(values.count - 1, i + halfWindow)
            let window = values[start...end].sorted()
            return window[window.startIndex + window.count / 2]
        }
    }

    /// Whether the current idle period has lasted long enough to end a run.
    static func shouldEndRun(
        lastActivityTime: Date,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(lastActivityTime) >= SharedConstants.stopDurationThreshold
    }

    // MARK: - Private

    /// Calculates altitude trend using least-squares linear regression.
    /// Returns slope in meters per second (positive = ascending, negative = descending).
    /// Regression is far more robust to single-point GPS altitude spikes than
    /// simple endpoint subtraction.
    private static func calculateAltitudeTrend(
        current: TrackPoint,
        recent: [TrackPoint]
    ) -> Double {
        let allPoints = recent + [current]
        guard allPoints.count >= SharedConstants.minPointsForAltitudeTrend else { return 0 }

        let baseTime = allPoints[0].timestamp.timeIntervalSinceReferenceDate
        let xs = allPoints.map { $0.timestamp.timeIntervalSinceReferenceDate - baseTime }
        let ys = medianFilter(values: allPoints.map { $0.altitude })

        let n = Double(allPoints.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0.0) { $0 + $1 * $1 }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator > 0 else { return 0 }

        return (n * sumXY - sumX * sumY) / denominator
    }
}
