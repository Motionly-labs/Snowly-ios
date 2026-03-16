//
//  ActiveTrackingCardSnapshotAssembler.swift
//  Snowly
//
//  Pure function: assembles the tracking dashboard's card inputs from a single
//  semantic + presentation source. Views may smooth rendered curves, but they
//  must not recalculate motion semantics locally.
//

import Foundation

enum ActiveTrackingCardInputAssembler {

    // MARK: - Source Snapshots

    struct MotionSemanticSnapshot: Sendable {
        let skiingMetrics: SessionSkiingMetrics
        let currentSpeed: Double
        let currentAltitudeMeters: Double
        let completedRuns: [CompletedRunData]
        let elapsedSeconds: TimeInterval
        let currentHeartRate: Double
        let averageHeartRate: Double
    }

    struct MotionPresentationSnapshot: Sendable {
        let speedSamples: [SpeedSample]
        let altitudeSamples: [AltitudeSample]
        let heartRateSamples: [HeartRateSample]
    }

    struct TrackingCardPresentationContext: Sendable {
        let unitSystem: UnitSystem
    }

    struct Source: Sendable {
        let semantic: MotionSemanticSnapshot
        let presentation: MotionPresentationSnapshot
        let context: TrackingCardPresentationContext
    }

    // MARK: - Entry points

    nonisolated static func input(
        for instance: ActiveTrackingCardInstance,
        source: Source
    ) -> AnyActiveTrackingCardInput {
        switch instance.kind {
        case .speedCurve, .altitudeCurve, .heartRateCurve:
            return .series(seriesInput(for: instance, source: source))
        default:
            return .scalar(scalarInput(for: instance, source: source))
        }
    }

    nonisolated static func scalarChip(
        for kind: ActiveTrackingCardKind,
        source: Source
    ) -> ActiveTrackingCompositeChip? {
        guard let descriptor = scalarDescriptor(for: kind, source: source) else { return nil }
        return ActiveTrackingCompositeChip(
            kind: kind,
            title: descriptor.title,
            primaryValue: descriptor.primaryValue
        )
    }

    nonisolated static func scalarInput(
        for kind: ActiveTrackingCardKind,
        source: Source,
        instanceId: UUID = UUID(),
        slot: ActiveTrackingSlot = .grid
    ) -> ActiveTrackingScalarCardInput? {
        guard let descriptor = scalarDescriptor(for: kind, source: source) else { return nil }
        return ActiveTrackingScalarCardInput(
            instanceId: instanceId,
            kind: kind,
            slot: slot,
            title: descriptor.title,
            primaryValue: descriptor.primaryValue,
            subtitle: descriptor.subtitle
        )
    }

    nonisolated static func seriesInput(
        for kind: ActiveTrackingCardKind,
        source: Source,
        instanceId: UUID = UUID(),
        slot: ActiveTrackingSlot = .hero,
        config: ActiveTrackingCardConfig? = nil
    ) -> ActiveTrackingSeriesCardInput? {
        switch kind {
        case .speedCurve, .altitudeCurve, .heartRateCurve:
            let definition = ActiveTrackingCardRegistry.definition(for: kind)
            let instance = ActiveTrackingCardInstance(
                instanceId: instanceId,
                kind: kind,
                slot: slot,
                presentationKind: definition.defaultPresentationKind,
                config: config ?? definition.defaultConfig
            )
            return seriesInput(for: instance, source: source)
        default:
            return nil
        }
    }

    // MARK: - Card family builders

    private nonisolated static func scalarInput(
        for instance: ActiveTrackingCardInstance,
        source: Source
    ) -> ActiveTrackingScalarCardInput {
        scalarInput(
            for: instance.kind,
            source: source,
            instanceId: instance.instanceId,
            slot: instance.slot
        ) ?? ActiveTrackingScalarCardInput(
            instanceId: instance.instanceId,
            kind: instance.kind,
            slot: instance.slot,
            title: "",
            primaryValue: .text(ActiveTrackingTextValue(value: "--", unit: "")),
            subtitle: nil
        )
    }

    private nonisolated static func seriesInput(
        for instance: ActiveTrackingCardInstance,
        source: Source
    ) -> ActiveTrackingSeriesCardInput {
        let policy = renderingPolicy(for: instance)

        switch instance.kind {
        case .speedCurve:
            return ActiveTrackingSeriesCardInput(
                instanceId: instance.instanceId,
                kind: instance.kind,
                slot: instance.slot,
                title: String(localized: "stat_speed_curve"),
                primaryValue: .numeric(numericSpeed(source.semantic.currentSpeed, source.context.unitSystem)),
                subtitle: nil,
                seriesPayload: .speed(trimmedSpeedSamples(window: policy.windowSeconds, source: source)),
                renderingPolicy: policy
            )
        case .altitudeCurve:
            let trimmedAltitude = trimmedAltitudeSamples(window: policy.windowSeconds, source: source)
            return ActiveTrackingSeriesCardInput(
                instanceId: instance.instanceId,
                kind: instance.kind,
                slot: instance.slot,
                title: String(localized: "stat_altitude_curve"),
                primaryValue: altitudeCurvePrimaryValue(from: trimmedAltitude, unitSystem: source.context.unitSystem),
                subtitle: nil,
                seriesPayload: .altitude(trimmedAltitude),
                renderingPolicy: policy
            )
        case .heartRateCurve:
            return ActiveTrackingSeriesCardInput(
                instanceId: instance.instanceId,
                kind: instance.kind,
                slot: instance.slot,
                title: String(localized: "stat_heart_rate_curve"),
                primaryValue: heartRatePrimaryValue(source.semantic.currentHeartRate),
                subtitle: heartRateSubtitle(
                    currentHeartRate: source.semantic.currentHeartRate,
                    averageHeartRate: source.semantic.averageHeartRate
                ),
                seriesPayload: .heartRate(trimmedHeartRateSamples(window: policy.windowSeconds, source: source)),
                renderingPolicy: policy
            )
        default:
            return ActiveTrackingSeriesCardInput(
                instanceId: instance.instanceId,
                kind: instance.kind,
                slot: instance.slot,
                title: "",
                primaryValue: nil,
                subtitle: nil,
                seriesPayload: .altitude([]),
                renderingPolicy: policy
            )
        }
    }

    // MARK: - Scalar semantics

    private struct ScalarDescriptor: Sendable {
        let title: String
        let primaryValue: ActiveTrackingCardPrimaryValue
        let subtitle: String?
    }

    private nonisolated static func scalarDescriptor(
        for kind: ActiveTrackingCardKind,
        source: Source
    ) -> ScalarDescriptor? {
        let semantic = source.semantic
        let us = source.context.unitSystem

        switch kind {
        case .currentSpeed:
            return ScalarDescriptor(
                title: String(localized: "stat_current_speed"),
                primaryValue: .numeric(numericSpeed(semantic.currentSpeed, us)),
                subtitle: nil
            )
        case .peakSpeed:
            return ScalarDescriptor(
                title: String(localized: "stat_peak_speed"),
                primaryValue: .numeric(numericPeakSpeed(semantic.skiingMetrics.maxSpeed, us)),
                subtitle: peakSpeedSubtitle(source)
            )
        case .avgSpeed:
            return ScalarDescriptor(
                title: String(localized: "stat_avg_speed"),
                primaryValue: .numeric(numericAvgSpeed(avgSkiingSpeed(source), us)),
                subtitle: String(localized: "tracking_avg_label_session")
            )
        case .vertical:
            return ScalarDescriptor(
                title: String(localized: "common_vertical"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: displayVertical(semantic.skiingMetrics.totalVertical, us),
                        decimals: 0,
                        unit: verticalUnit(us),
                        animationDelay: 0.0
                    )
                ),
                subtitle: verticalSubtitle(source)
            )
        case .distance:
            return ScalarDescriptor(
                title: String(localized: "common_distance"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: displayDistance(semantic.skiingMetrics.totalDistance, us),
                        decimals: 1,
                        unit: distanceUnit(us),
                        animationDelay: 0.08
                    )
                ),
                subtitle: nil
            )
        case .runCount:
            return ScalarDescriptor(
                title: String(localized: "common_runs"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: Double(semantic.skiingMetrics.runCount),
                        decimals: 0,
                        unit: "",
                        animationDelay: 0.16
                    )
                ),
                subtitle: nil
            )
        case .skiTime:
            return ScalarDescriptor(
                title: String(localized: "common_ski_time"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: semantic.elapsedSeconds / 60,
                        decimals: 0,
                        unit: String(localized: "common_min_abbrev"),
                        animationDelay: 0.32
                    )
                ),
                subtitle: nil
            )
        case .liftCount:
            return ScalarDescriptor(
                title: String(localized: "stat_lift_count"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: Double(liftCount(source)),
                        decimals: 0,
                        unit: "",
                        animationDelay: 0.16
                    )
                ),
                subtitle: nil
            )
        case .currentAltitude:
            return ScalarDescriptor(
                title: String(localized: "stat_current_altitude"),
                primaryValue: .numeric(
                    ActiveTrackingNumericValue(
                        value: displayAltitude(semantic.currentAltitudeMeters, us),
                        decimals: 0,
                        unit: altitudeUnit(us),
                        animationDelay: 0.0
                    )
                ),
                subtitle: nil
            )
        case .heartRate:
            return ScalarDescriptor(
                title: String(localized: "stat_heart_rate"),
                primaryValue: heartRatePrimaryValue(semantic.currentHeartRate) ?? .text(
                    ActiveTrackingTextValue(value: "--", unit: "")
                ),
                subtitle: heartRateSubtitle(
                    currentHeartRate: semantic.currentHeartRate,
                    averageHeartRate: semantic.averageHeartRate
                )
            )
        case .speedCurve, .altitudeCurve, .heartRateCurve:
            return nil
        }
    }

    // MARK: - Presentation helpers

    private nonisolated static func renderingPolicy(
        for instance: ActiveTrackingCardInstance
    ) -> ActiveTrackingSeriesRenderingPolicy {
        let defaultWindow: TimeInterval? = switch instance.kind {
        case .speedCurve:
            SharedConstants.speedSampleWindowSeconds
        case .altitudeCurve:
            SharedConstants.altitudeSampleWindowSeconds
        case .heartRateCurve:
            SharedConstants.heartRateSampleWindowSeconds
        default:
            nil
        }

        return ActiveTrackingSeriesRenderingPolicy(
            windowSeconds: instance.config.windowSeconds ?? defaultWindow,
            smoothingAlpha: instance.config.smoothingAlpha,
            allowsRenderOnlySmoothing: true
        )
    }

    private nonisolated static func trimmedSpeedSamples(
        window: TimeInterval?,
        source: Source
    ) -> [SpeedSample] {
        let samples = source.presentation.speedSamples
        guard let window else {
            return samples.droppingLeadingZeroLikeSamples()
        }

        let cutoff = Date.now.addingTimeInterval(-window)
        let startIndex = binarySearchFirstIndex(in: samples, where: { $0.time >= cutoff })
        guard startIndex < samples.count else { return [] }
        return samples[startIndex...].droppingLeadingZeroLikeSamples()
    }

    private nonisolated static func trimmedAltitudeSamples(
        window: TimeInterval?,
        source: Source
    ) -> [AltitudeSample] {
        let samples = source.presentation.altitudeSamples
        guard let window else {
            return samples.droppingLeadingZeroLikeSamples()
        }

        let cutoff = Date.now.addingTimeInterval(-window)
        let startIndex = binarySearchFirstIndex(in: samples, where: { $0.time >= cutoff })
        guard startIndex < samples.count else { return [] }
        return samples[startIndex...].droppingLeadingZeroLikeSamples()
    }

    private nonisolated static func trimmedHeartRateSamples(
        window: TimeInterval?,
        source: Source
    ) -> [HeartRateSample] {
        let samples = source.presentation.heartRateSamples
        guard let window else {
            return samples.droppingLeadingZeroLikeSamples()
        }

        let cutoff = Date.now.addingTimeInterval(-window)
        let startIndex = binarySearchFirstIndex(in: samples, where: { $0.time >= cutoff })
        guard startIndex < samples.count else { return [] }
        return samples[startIndex...].droppingLeadingZeroLikeSamples()
    }

    /// O(log n) binary search for the first index where `predicate` is true.
    /// Assumes the predicate transitions from false to true (time-sorted samples).
    private nonisolated static func binarySearchFirstIndex<T>(
        in array: [T],
        where predicate: (T) -> Bool
    ) -> Int {
        var lo = 0
        var hi = array.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if predicate(array[mid]) {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }

    private nonisolated static func altitudeCurvePrimaryValue(
        from samples: [AltitudeSample],
        unitSystem: UnitSystem
    ) -> ActiveTrackingCardPrimaryValue {
        guard let first = samples.first?.altitude, let last = samples.last?.altitude else {
            return .text(ActiveTrackingTextValue(value: "--", unit: ""))
        }
        let delta = last - first
        let unit = verticalUnit(unitSystem)
        let value = String(format: "%+.0f", delta)
        return .text(ActiveTrackingTextValue(value: value, unit: unit))
    }

    private nonisolated static func heartRatePrimaryValue(
        _ currentHeartRate: Double
    ) -> ActiveTrackingCardPrimaryValue? {
        guard currentHeartRate > 0 else {
            return .text(ActiveTrackingTextValue(value: "--", unit: ""))
        }
        return .text(
            ActiveTrackingTextValue(
                value: "\(Int(currentHeartRate.rounded()))",
                unit: String(localized: "stat_heart_rate_unit")
            )
        )
    }

    private nonisolated static func heartRateSubtitle(
        currentHeartRate _: Double,
        averageHeartRate: Double
    ) -> String {
        if averageHeartRate > 0 {
            return "\(String(localized: "tracking_hero_heart_rate_subtitle")) · \(Int(averageHeartRate.rounded())) \(String(localized: "stat_heart_rate_unit"))"
        }
        return String(localized: "tracking_hero_heart_rate_subtitle")
    }

    private nonisolated static func peakSpeedSubtitle(_ source: Source) -> String {
        let format = String(localized: "tracking_peak_subtitle_session_format")
        return String(
            format: format,
            locale: Locale.current,
            formatVertical(source.semantic.skiingMetrics.totalVertical, source.context.unitSystem),
            elapsedMinutes(source.semantic.elapsedSeconds)
        )
    }

    private nonisolated static func verticalSubtitle(_ source: Source) -> String {
        let format = String(localized: "tracking_vertical_subtitle_format")
        return String(
            format: format,
            locale: Locale.current,
            Int64(source.semantic.skiingMetrics.runCount),
            elapsedMinutes(source.semantic.elapsedSeconds)
        )
    }

    // MARK: - Numeric builders

    private nonisolated static func numericSpeed(
        _ metersPerSecond: Double,
        _ unitSystem: UnitSystem
    ) -> ActiveTrackingNumericValue {
        ActiveTrackingNumericValue(
            value: displaySpeed(metersPerSecond, unitSystem),
            decimals: 1,
            unit: speedUnit(unitSystem),
            animationDelay: 0.0
        )
    }

    private nonisolated static func numericPeakSpeed(
        _ metersPerSecond: Double,
        _ unitSystem: UnitSystem
    ) -> ActiveTrackingNumericValue {
        ActiveTrackingNumericValue(
            value: displaySpeed(metersPerSecond, unitSystem),
            decimals: 1,
            unit: speedUnit(unitSystem),
            animationDelay: 0.24
        )
    }

    private nonisolated static func numericAvgSpeed(
        _ metersPerSecond: Double,
        _ unitSystem: UnitSystem
    ) -> ActiveTrackingNumericValue {
        ActiveTrackingNumericValue(
            value: displaySpeed(metersPerSecond, unitSystem),
            decimals: 1,
            unit: speedUnit(unitSystem),
            animationDelay: 0.08
        )
    }

    // MARK: - Unit conversion helpers

    nonisolated static func displaySpeed(_ ms: Double, _ us: UnitSystem) -> Double {
        switch us {
        case .metric:
            UnitConversion.metersPerSecondToKmh(ms)
        case .imperial:
            UnitConversion.metersPerSecondToMph(ms)
        }
    }

    nonisolated static func speedUnit(_ us: UnitSystem) -> String {
        Formatters.speedUnit(us)
    }

    nonisolated static func displayVertical(_ meters: Double, _ us: UnitSystem) -> Double {
        us == .imperial ? UnitConversion.metersToFeet(meters) : meters
    }

    nonisolated static func verticalUnit(_ us: UnitSystem) -> String {
        Formatters.verticalUnit(us)
    }

    nonisolated static func displayDistance(_ meters: Double, _ us: UnitSystem) -> Double {
        switch us {
        case .metric:
            meters / 1000
        case .imperial:
            meters / 1609.344
        }
    }

    nonisolated static func distanceUnit(_ us: UnitSystem) -> String {
        Formatters.distanceUnit(us)
    }

    nonisolated static func displayAltitude(_ meters: Double, _ us: UnitSystem) -> Double {
        us == .imperial ? UnitConversion.metersToFeet(meters) : meters
    }

    nonisolated static func altitudeUnit(_ us: UnitSystem) -> String {
        Formatters.verticalUnit(us)
    }

    // MARK: - Derived metrics

    private nonisolated static func avgSkiingSpeed(_ source: Source) -> Double {
        let runs = source.semantic.completedRuns.filter { $0.activityType == .skiing }
        let dist = runs.reduce(0.0) { $0 + $1.distance }
        let time = runs.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        guard time > 0 else { return 0 }
        return dist / time
    }

    private nonisolated static func liftCount(_ source: Source) -> Int {
        source.semantic.completedRuns.filter { $0.activityType == .lift }.count
    }

    private nonisolated static func elapsedMinutes(_ elapsedSeconds: TimeInterval) -> Double {
        max(elapsedSeconds / 60, 0)
    }

    private nonisolated static func formatVertical(
        _ meters: Double,
        _ unitSystem: UnitSystem
    ) -> String {
        String(format: "%.0f%@", displayVertical(meters, unitSystem), verticalUnit(unitSystem))
    }
}
