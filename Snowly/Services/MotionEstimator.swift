//
//  MotionEstimator.swift
//  Snowly
//
//  Pure functions for computing motion features from GPS track points.
//  No platform-specific imports — shared between iOS and watchOS.
//

import Foundation

enum MotionEstimator {
    nonisolated private static let minAltitudeTrendTimeSpan: TimeInterval = 4
    nonisolated private static let altitudeTrendMinRate = 0.15
    nonisolated private static let minimumHorizontalDistanceForPathSpeed = 0.5
    nonisolated private static let idealHorizontalAccuracy = 6.0
    nonisolated private static let idealVerticalAccuracy = 10.0
    nonisolated private static let maxReliableHorizontalAccuracy = 50.0
    nonisolated private static let maxReliableVerticalAccuracy = 60.0
    /// Max m/s by which path speed may exceed GPS Doppler before capping.
    /// Doppler is noise-free; ~2 m/s covers ±2m positional error per point.
    nonisolated private static let horizontalSpeedNoiseBudget: Double = 2.0

    struct DualWindowEstimates: Sendable, Equatable {
        let transition: MotionEstimate
        let steady: MotionEstimate
    }

    nonisolated static func transitionEstimate(
        current: TrackPoint,
        recentPoints: [TrackPoint]
    ) -> MotionEstimate {
        transitionEstimate(
            current: current.filteredEstimatePoint,
            recentPoints: recentPoints.map(\.filteredEstimatePoint)
        )
    }

    nonisolated static func steadyEstimate(
        current: TrackPoint,
        recentPoints: [TrackPoint]
    ) -> MotionEstimate {
        steadyEstimate(
            current: current.filteredEstimatePoint,
            recentPoints: recentPoints.map(\.filteredEstimatePoint)
        )
    }

    nonisolated static func transitionEstimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint]
    ) -> MotionEstimate {
        dualWindowEstimates(
            current: current,
            recentPoints: recentPoints
        ).transition
    }

    nonisolated static func steadyEstimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint]
    ) -> MotionEstimate {
        dualWindowEstimates(
            current: current,
            recentPoints: recentPoints
        ).steady
    }

    nonisolated static func estimate(
        current: TrackPoint,
        recentPoints: [TrackPoint]
    ) -> MotionEstimate {
        steadyEstimate(current: current, recentPoints: recentPoints)
    }

    nonisolated static func estimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint]
    ) -> MotionEstimate {
        steadyEstimate(current: current, recentPoints: recentPoints)
    }

    nonisolated static func dualWindowEstimates(
        current: FilteredTrackPoint,
        recentPoints: RecentTrackBuffer<FilteredTrackPoint>
    ) -> DualWindowEstimates {
        let transitionCutoff = current.timestamp.addingTimeInterval(-SharedConstants.transitionFeatureWindowSeconds)
        var transitionBuilder = EstimateWindowBuilder(
            windowSeconds: SharedConstants.transitionFeatureWindowSeconds,
            window: .transition
        )
        var steadyBuilder = EstimateWindowBuilder(
            windowSeconds: SharedConstants.steadyFeatureWindowSeconds,
            window: .steady
        )

        recentPoints.forEach(within: SharedConstants.steadyFeatureWindowSeconds, endingAt: current.timestamp) { point in
            steadyBuilder.append(point)
            if point.timestamp >= transitionCutoff {
                transitionBuilder.append(point)
            }
        }

        return DualWindowEstimates(
            transition: transitionBuilder.build(current: current),
            steady: steadyBuilder.build(current: current)
        )
    }

    nonisolated static func dualWindowEstimates(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint]
    ) -> DualWindowEstimates {
        let transitionCutoff = current.timestamp.addingTimeInterval(-SharedConstants.transitionFeatureWindowSeconds)
        let steadyCutoff = current.timestamp.addingTimeInterval(-SharedConstants.steadyFeatureWindowSeconds)
        var transitionBuilder = EstimateWindowBuilder(
            windowSeconds: SharedConstants.transitionFeatureWindowSeconds,
            window: .transition
        )
        var steadyBuilder = EstimateWindowBuilder(
            windowSeconds: SharedConstants.steadyFeatureWindowSeconds,
            window: .steady
        )

        for point in recentPoints where point.timestamp >= steadyCutoff {
            steadyBuilder.append(point)
            if point.timestamp >= transitionCutoff {
                transitionBuilder.append(point)
            }
        }

        return DualWindowEstimates(
            transition: transitionBuilder.build(current: current),
            steady: steadyBuilder.build(current: current)
        )
    }

    nonisolated private static func estimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        windowSeconds: TimeInterval,
        window: MotionEstimateWindow
    ) -> MotionEstimate {
        let cutoff = current.timestamp.addingTimeInterval(-windowSeconds)
        var builder = EstimateWindowBuilder(windowSeconds: windowSeconds, window: window)
        for point in recentPoints where point.timestamp >= cutoff {
            builder.append(point)
        }
        return builder.build(current: current)
    }

    nonisolated static func medianFilter(values: [Double], windowSize: Int) -> [Double] {
        guard windowSize > 0, !values.isEmpty else { return values }
        if windowSize == 3 {
            return medianFilter3(values: values)
        }
        let half = windowSize / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let window = values[lo...hi].sorted()
            return window[window.count / 2]
        }
    }

    nonisolated private static func verticalSlope(
        relativeTimes: [TimeInterval],
        values: [Double],
        fallbackDuration: TimeInterval
    ) -> Double {
        guard relativeTimes.count == values.count, !relativeTimes.isEmpty else { return 0 }
        guard relativeTimes.count > 1 else { return 0 }

        let meanTime = relativeTimes.reduce(0, +) / Double(relativeTimes.count)
        let meanValue = values.reduce(0, +) / Double(values.count)

        var numerator = 0.0
        var denominator = 0.0
        for (time, value) in zip(relativeTimes, values) {
            let centeredTime = time - meanTime
            numerator += centeredTime * (value - meanValue)
            denominator += centeredTime * centeredTime
        }

        if denominator > 1e-6 {
            return numerator / denominator
        }

        let fallbackDelta = (values.last ?? 0) - (values.first ?? 0)
        return fallbackDelta / max(fallbackDuration, 1)
    }

    nonisolated private static func maxTimestampGap(
        in windowPoints: [FilteredTrackPoint],
        current: FilteredTrackPoint
    ) -> TimeInterval {
        guard !windowPoints.isEmpty else { return 0 }
        var maxGap: TimeInterval = 0
        if windowPoints.count > 1 {
            for index in 1..<windowPoints.count {
                maxGap = max(maxGap, windowPoints[index].timestamp.timeIntervalSince(windowPoints[index - 1].timestamp))
            }
        }
        if let last = windowPoints.last {
            maxGap = max(maxGap, current.timestamp.timeIntervalSince(last.timestamp))
        }
        return maxGap
    }

    nonisolated private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    nonisolated private static func accuracyQualityFactor(
        accuracies: [Double],
        idealAccuracy: Double,
        maxReliableAccuracy: Double
    ) -> Double {
        guard !accuracies.isEmpty else { return 0.5 }
        let sorted = accuracies.sorted()
        let medianAccuracy = sorted[sorted.count / 2]

        if medianAccuracy <= idealAccuracy { return 1 }
        if medianAccuracy >= maxReliableAccuracy { return 0 }

        let span = max(maxReliableAccuracy - idealAccuracy, 1)
        return 1 - (medianAccuracy - idealAccuracy) / span
    }

    nonisolated private static func medianFilter3(values: [Double]) -> [Double] {
        guard values.count > 2 else { return values }

        var filtered = values
        filtered[0] = max(values[0], values[1])

        if values.count > 2 {
            for index in 1..<(values.count - 1) {
                filtered[index] = medianOfThree(
                    values[index - 1],
                    values[index],
                    values[index + 1]
                )
            }
        }

        filtered[values.count - 1] = max(values[values.count - 2], values[values.count - 1])
        return filtered
    }

    nonisolated private static func medianOfThree(_ a: Double, _ b: Double, _ c: Double) -> Double {
        a + b + c - min(a, min(b, c)) - max(a, max(b, c))
    }

    private struct EstimateWindowBuilder {
        let windowSeconds: TimeInterval
        let window: MotionEstimateWindow

        private var firstPoint: FilteredTrackPoint?
        private var previousPoint: FilteredTrackPoint?
        private var horizontalDistance: Double = 0
        private var rawAltitudes: [Double] = []
        private var relativeTimes: [TimeInterval] = []
        private var horizontalAccuracies: [Double] = []
        private var verticalAccuracies: [Double] = []
        private var maxGap: TimeInterval = 0

        nonisolated init(windowSeconds: TimeInterval, window: MotionEstimateWindow) {
            self.windowSeconds = windowSeconds
            self.window = window
            rawAltitudes.reserveCapacity(16)
            relativeTimes.reserveCapacity(16)
            horizontalAccuracies.reserveCapacity(16)
            verticalAccuracies.reserveCapacity(16)
        }

        nonisolated mutating func append(_ point: FilteredTrackPoint) {
            if firstPoint == nil {
                firstPoint = point
                relativeTimes.append(0)
            } else {
                let firstTimestamp = firstPoint?.timestamp ?? point.timestamp
                relativeTimes.append(point.timestamp.timeIntervalSince(firstTimestamp))
            }

            if let previousPoint {
                horizontalDistance += previousPoint.distance(to: point)
                maxGap = max(maxGap, point.timestamp.timeIntervalSince(previousPoint.timestamp))
            }

            previousPoint = point
            rawAltitudes.append(point.altitude)
            horizontalAccuracies.append(point.horizontalAccuracy)
            verticalAccuracies.append(point.verticalAccuracy)
        }

        nonisolated func build(current: FilteredTrackPoint) -> MotionEstimate {
            let first = firstPoint ?? current
            let sampleCount = rawAltitudes.count + 1
            let rawDuration = max(current.timestamp.timeIntervalSince(first.timestamp), 0)
            let duration = max(rawDuration, 1)

            var totalHorizontalDistance = horizontalDistance
            var localMaxGap = maxGap
            if let previousPoint {
                totalHorizontalDistance += previousPoint.distance(to: current)
                localMaxGap = max(localMaxGap, current.timestamp.timeIntervalSince(previousPoint.timestamp))
            }

            let avgHorizontalSpeed: Double
            if totalHorizontalDistance >= MotionEstimator.minimumHorizontalDistanceForPathSpeed, rawDuration > 0 {
                let pathSpeed = totalHorizontalDistance / rawDuration
                let dopplerSpeed = current.estimatedSpeed
                avgHorizontalSpeed = dopplerSpeed > 0
                    ? min(pathSpeed, dopplerSpeed + MotionEstimator.horizontalSpeedNoiseBudget)
                    : pathSpeed
            } else {
                avgHorizontalSpeed = current.estimatedSpeed
            }

            var altitudes = rawAltitudes
            altitudes.append(current.altitude)
            let filteredAltitudes = altitudes.count >= 3
                ? MotionEstimator.medianFilter3(values: altitudes)
                : altitudes

            var times = relativeTimes
            times.append(current.timestamp.timeIntervalSince(first.timestamp))
            let avgVerticalSpeed = MotionEstimator.verticalSlope(
                relativeTimes: times,
                values: filteredAltitudes,
                fallbackDuration: duration
            )

            var horizontalAccuracies = self.horizontalAccuracies
            horizontalAccuracies.append(current.horizontalAccuracy)
            let horizontalQuality = MotionEstimator.accuracyQualityFactor(
                accuracies: horizontalAccuracies,
                idealAccuracy: MotionEstimator.idealHorizontalAccuracy,
                maxReliableAccuracy: MotionEstimator.maxReliableHorizontalAccuracy
            )

            var verticalAccuracies = self.verticalAccuracies
            verticalAccuracies.append(current.verticalAccuracy)
            let verticalQuality = MotionEstimator.accuracyQualityFactor(
                accuracies: verticalAccuracies,
                idealAccuracy: MotionEstimator.idealVerticalAccuracy,
                maxReliableAccuracy: MotionEstimator.maxReliableVerticalAccuracy
            )

            let coverage = windowSeconds > 0 ? min(rawDuration / windowSeconds, 1) : 1
            let sampleFactor = min(Double(max(sampleCount - 1, 0)) / 3.0, 1)
            let targetGap = max(windowSeconds / 2, 1)
            let gapFactor: Double
            if sampleCount <= 1 {
                gapFactor = 0.5
            } else {
                gapFactor = min(targetGap / max(localMaxGap, 1), 1)
            }

            let confidence = MotionEstimator.clamp01(
                0.35 * coverage
                + 0.20 * sampleFactor
                + 0.15 * gapFactor
                + 0.15 * horizontalQuality
                + 0.15 * verticalQuality
            )

            let hasEnoughHistory = sampleCount >= 3
                || (sampleCount >= 2 && rawDuration >= windowSeconds * 0.75)
            let hasReliableTrend = hasEnoughHistory
                && rawDuration >= MotionEstimator.minAltitudeTrendTimeSpan
                && abs(avgVerticalSpeed) >= MotionEstimator.altitudeTrendMinRate
                && confidence >= 0.35
                && verticalQuality >= 0.35

            return MotionEstimate(
                duration: duration,
                avgHorizontalSpeed: avgHorizontalSpeed,
                avgVerticalSpeed: avgVerticalSpeed,
                hasReliableAltitudeTrend: hasReliableTrend,
                sampleCount: sampleCount,
                confidence: confidence,
                window: window
            )
        }
    }
}
