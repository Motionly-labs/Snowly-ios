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

extension DetectedActivity {
    var activityName: String {
        switch self {
        case .skiing: "skiing"
        case .chairlift: "chairlift"
        case .idle: "idle"
        }
    }
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
    nonisolated static func detect(
        point: TrackPoint,
        recentPoints: [TrackPoint],
        motion: DetectedMotion = .unknown
    ) -> DetectedActivity {
        classifyActivity(point: point, motion: motion) {
            calculateAltitudeTrend(current: point, recent: recentPoints)
        }
    }

    /// Overload that takes pre-extracted timestamps and altitudes to avoid
    /// intermediate array allocations when the caller already has raw data.
    nonisolated static func detect(
        point: TrackPoint,
        recentTimestamps: [Double],
        recentAltitudes: [Double],
        motion: DetectedMotion = .unknown
    ) -> DetectedActivity {
        classifyActivity(point: point, motion: motion) {
            calculateAltitudeTrendFromRaw(
                currentTimestamp: point.timestamp.timeIntervalSinceReferenceDate,
                currentAltitude: point.altitude,
                recentTimestamps: recentTimestamps,
                recentAltitudes: recentAltitudes
            )
        }
    }

    /// Core classification logic shared by all detect overloads.
    /// The altitudeTrendProvider closure is only called when the speed is in
    /// the ambiguous range, avoiding unnecessary computation for clear-cut cases.
    nonisolated private static func classifyActivity(
        point: TrackPoint,
        motion: DetectedMotion,
        altitudeTrendProvider: () -> Double
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

        // Medium speed range: use altitude trend to distinguish
        if speed >= SharedConstants.idleSpeedThreshold
            && speed <= SharedConstants.chairliftMaxSpeed {

            // Only compute altitude trend when actually needed
            let altitudeTrend = altitudeTrendProvider()

            if altitudeTrend > SharedConstants.altitudeTrendUpThreshold {
                // Altitude is rising consistently → chairlift
                return .chairlift
            }

            if altitudeTrend < SharedConstants.altitudeTrendDownThreshold {
                // Altitude is dropping → skiing
                return .skiing
            }

            // Flat altitude at medium speed: use CoreMotion hint
            if case .automotive = motion {
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
    /// Uses a single reusable scratch buffer to avoid per-element allocations.
    nonisolated static func medianFilter(
        values: [Double],
        windowSize: Int = SharedConstants.medianFilterWindowSize
    ) -> [Double] {
        guard values.count >= windowSize, windowSize >= 3 else { return values }
        let halfWindow = windowSize / 2
        var result = [Double](repeating: 0, count: values.count)
        var scratch = [Double]()
        scratch.reserveCapacity(windowSize)
        for i in values.indices {
            let start = max(0, i - halfWindow)
            let end = min(values.count - 1, i + halfWindow)
            scratch.removeAll(keepingCapacity: true)
            for j in start...end {
                scratch.append(values[j])
            }
            scratch.sort()
            result[i] = scratch[scratch.count / 2]
        }
        return result
    }

    /// Whether the current idle period has lasted long enough to end a run.
    nonisolated static func shouldEndRun(
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
    nonisolated private static func calculateAltitudeTrend(
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

    /// Altitude trend from pre-extracted timestamp/altitude arrays.
    /// Avoids allocating intermediate arrays when called from CircularBuffer paths.
    nonisolated private static func calculateAltitudeTrendFromRaw(
        currentTimestamp: Double,
        currentAltitude: Double,
        recentTimestamps: [Double],
        recentAltitudes: [Double]
    ) -> Double {
        let totalCount = recentTimestamps.count + 1
        guard totalCount >= SharedConstants.minPointsForAltitudeTrend else { return 0 }

        var allAltitudes = recentAltitudes
        allAltitudes.append(currentAltitude)
        let ys = medianFilter(values: allAltitudes)

        let baseTime = recentTimestamps[0]

        let n = Double(totalCount)
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0

        for i in 0..<recentTimestamps.count {
            let x = recentTimestamps[i] - baseTime
            let y = ys[i]
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        // Add current point
        let xCurrent = currentTimestamp - baseTime
        let yCurrent = ys[totalCount - 1]
        sumX += xCurrent
        sumY += yCurrent
        sumXY += xCurrent * yCurrent
        sumX2 += xCurrent * xCurrent

        let denominator = n * sumX2 - sumX * sumX
        guard denominator > 0 else { return 0 }

        return (n * sumXY - sumX * sumY) / denominator
    }
}
