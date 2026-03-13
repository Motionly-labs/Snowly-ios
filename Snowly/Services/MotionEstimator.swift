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
        estimate(
            current: current,
            recentPoints: recentPoints,
            windowSeconds: SharedConstants.transitionFeatureWindowSeconds,
            window: .transition
        )
    }

    nonisolated static func steadyEstimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint]
    ) -> MotionEstimate {
        estimate(
            current: current,
            recentPoints: recentPoints,
            windowSeconds: SharedConstants.steadyFeatureWindowSeconds,
            window: .steady
        )
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

    nonisolated private static func estimate(
        current: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        windowSeconds: TimeInterval,
        window: MotionEstimateWindow
    ) -> MotionEstimate {
        let windowPoints = RecentTrackWindow.filteredPoints(
            from: recentPoints,
            endingAt: current.timestamp,
            within: windowSeconds
        )
        // Avoid allPoints = windowPoints + [current] — current is handled inline below,
        // saving one O(n) copy per window (two windows = two fewer allocations per GPS update).
        let first = windowPoints.first ?? current
        let sampleCount = windowPoints.count + 1

        let rawDuration = max(current.timestamp.timeIntervalSince(first.timestamp), 0)
        let duration = max(rawDuration, 1)

        var horizontalDistance = 0.0
        if windowPoints.count > 1 {
            for index in 1..<windowPoints.count {
                horizontalDistance += windowPoints[index - 1].distance(to: windowPoints[index])
            }
        }
        if let lastWindow = windowPoints.last {
            horizontalDistance += lastWindow.distance(to: current)
        }
        let avgHorizontalSpeed: Double
        if horizontalDistance >= minimumHorizontalDistanceForPathSpeed, rawDuration > 0 {
            let pathSpeed = horizontalDistance / rawDuration
            let dopplerSpeed = current.estimatedSpeed
            // Doppler is unaffected by positional noise; cap path speed to Doppler + budget
            // to prevent GPS scatter from inflating speed across the skiFastMin boundary.
            avgHorizontalSpeed = dopplerSpeed > 0
                ? min(pathSpeed, dopplerSpeed + Self.horizontalSpeedNoiseBudget)
                : pathSpeed
        } else {
            avgHorizontalSpeed = current.estimatedSpeed
        }

        var rawAltitudes = windowPoints.map(\.altitude)
        rawAltitudes.append(current.altitude)
        let filteredAltitudes = rawAltitudes.count >= 3
            ? medianFilter(values: rawAltitudes, windowSize: 3)
            : rawAltitudes
        var relativeTimes = windowPoints.map { $0.timestamp.timeIntervalSince(first.timestamp) }
        relativeTimes.append(current.timestamp.timeIntervalSince(first.timestamp))
        let avgVerticalSpeed = verticalSlope(
            relativeTimes: relativeTimes,
            values: filteredAltitudes,
            fallbackDuration: duration
        )

        var horizontalAccuracies = windowPoints.map(\.horizontalAccuracy)
        horizontalAccuracies.append(current.horizontalAccuracy)
        let horizontalQuality = accuracyQualityFactor(
            accuracies: horizontalAccuracies,
            idealAccuracy: idealHorizontalAccuracy,
            maxReliableAccuracy: maxReliableHorizontalAccuracy
        )

        var verticalAccuracies = windowPoints.map(\.verticalAccuracy)
        verticalAccuracies.append(current.verticalAccuracy)
        let verticalQuality = accuracyQualityFactor(
            accuracies: verticalAccuracies,
            idealAccuracy: idealVerticalAccuracy,
            maxReliableAccuracy: maxReliableVerticalAccuracy
        )

        let maxGap = maxTimestampGap(in: windowPoints, current: current)
        let coverage = windowSeconds > 0 ? min(rawDuration / windowSeconds, 1) : 1
        let sampleFactor = min(Double(max(sampleCount - 1, 0)) / 3.0, 1)
        let targetGap = max(windowSeconds / 2, 1)
        let gapFactor: Double
        if sampleCount <= 1 {
            gapFactor = 0.5
        } else {
            gapFactor = min(targetGap / max(maxGap, 1), 1)
        }
        let confidence = clamp01(
            0.35 * coverage
            + 0.20 * sampleFactor
            + 0.15 * gapFactor
            + 0.15 * horizontalQuality
            + 0.15 * verticalQuality
        )

        let hasEnoughHistory = sampleCount >= 3 || (sampleCount >= 2 && rawDuration >= windowSeconds * 0.75)
        let hasReliableTrend = hasEnoughHistory
            && rawDuration >= minAltitudeTrendTimeSpan
            && abs(avgVerticalSpeed) >= altitudeTrendMinRate
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
}
