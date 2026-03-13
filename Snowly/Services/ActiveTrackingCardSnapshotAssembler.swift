//
//  ActiveTrackingCardSnapshotAssembler.swift
//  Snowly
//
//  Pure function: assembles card snapshots from live tracking state.
//  No service references — fully testable without UI.
//

import Foundation

enum ActiveTrackingCardSnapshotAssembler {

    // MARK: - Context

    struct Context: Sendable {
        let unitSystem: UnitSystem
        let skiingMetrics: SessionSkiingMetrics
        let currentSpeed: Double           // m/s
        let completedRuns: [CompletedRunData]
        let speedSamples: [SpeedSample]
        let altitudeSamples: [AltitudeSample]  // already in display units (service-converted)
        let currentAltitudeMeters: Double  // raw meters — assembler converts
        let elapsedSeconds: TimeInterval
        let currentHeartRate: Double
        let averageHeartRate: Double
        let heartRateSamples: [HeartRateSample]
    }

    // MARK: - Entry point

    nonisolated static func snapshot(
        for instance: ActiveTrackingCardInstance,
        context: Context
    ) -> ActiveTrackingCardSnapshot {
        switch instance.presentationKind {
        case .scalar:
            return .scalar(scalarSnapshot(for: instance.kind, context: context))
        case .series:
            return .series(seriesSnapshot(for: instance, context: context))
        case .profile:
            return .profile(ProfileCardSnapshot(
                altitudeSamples: context.altitudeSamples.droppingLeadingZeroLikeSamples(),
                speedSamples: context.speedSamples.droppingLeadingZeroLikeSamples()
            ))
        case .text:
            return .text(textSnapshot(for: instance.kind, context: context))
        case .heartRateSeries:
            return .heartRateSeries(heartRateSeriesSnapshot(for: instance, context: context))
        }
    }

    // MARK: - Scalar

    private nonisolated static func scalarSnapshot(
        for kind: ActiveTrackingCardKind,
        context: Context
    ) -> ScalarCardSnapshot {
        let us = context.unitSystem
        switch kind {
        case .currentSpeed:
            return .init(kind: kind,
                         value: displaySpeed(context.currentSpeed, us),
                         decimals: 1, unit: speedUnit(us), animationDelay: 0.0)
        case .peakSpeed:
            return .init(kind: kind,
                         value: displaySpeed(context.skiingMetrics.maxSpeed, us),
                         decimals: 1, unit: speedUnit(us), animationDelay: 0.24)
        case .avgSpeed:
            return .init(kind: kind,
                         value: avgSkiingSpeed(context),
                         decimals: 1, unit: speedUnit(us), animationDelay: 0.08)
        case .vertical:
            return .init(kind: kind,
                         value: displayVertical(context.skiingMetrics.totalVertical, us),
                         decimals: 0, unit: verticalUnit(us), animationDelay: 0.0)
        case .distance:
            return .init(kind: kind,
                         value: displayDistance(context.skiingMetrics.totalDistance, us),
                         decimals: 1, unit: distanceUnit(us), animationDelay: 0.08)
        case .runCount:
            return .init(kind: kind,
                         value: Double(context.skiingMetrics.runCount),
                         decimals: 0, unit: "", animationDelay: 0.16)
        case .skiTime:
            return .init(kind: kind,
                         value: context.elapsedSeconds / 60,
                         decimals: 0,
                         unit: String(localized: "common_min_abbrev"),
                         animationDelay: 0.32)
        case .liftCount:
            return .init(kind: kind,
                         value: Double(liftCount(context)),
                         decimals: 0, unit: "", animationDelay: 0.16)
        case .currentAltitude:
            return .init(kind: kind,
                         value: displayAltitude(context.currentAltitudeMeters, us),
                         decimals: 0, unit: altitudeUnit(us), animationDelay: 0.0)
        case .altitudeCurve, .speedCurve, .profile, .heartRate, .heartRateCurve:
            // Non-scalar kinds — return zero placeholder (caller uses correct presentationKind)
            return .init(kind: kind, value: 0, decimals: 0, unit: "", animationDelay: 0.0)
        }
    }

    // MARK: - Series (altitude curve)

    private nonisolated static func seriesSnapshot(
        for instance: ActiveTrackingCardInstance,
        context: Context
    ) -> SeriesCardSnapshot {
        let window = instance.config.windowSeconds ?? SharedConstants.altitudeSampleWindowSeconds
        let cutoff = Date.now.addingTimeInterval(-window)
        let trimmed = context.altitudeSamples
            .filter { $0.time >= cutoff }
            .droppingLeadingZeroLikeSamples()
        return SeriesCardSnapshot(kind: instance.kind, samples: trimmed)
    }

    // MARK: - Heart Rate Series

    private nonisolated static func heartRateSeriesSnapshot(
        for instance: ActiveTrackingCardInstance,
        context: Context
    ) -> HeartRateSeriesCardSnapshot {
        let window = instance.config.windowSeconds ?? SharedConstants.heartRateSampleWindowSeconds
        let cutoff = Date.now.addingTimeInterval(-window)
        let trimmed = context.heartRateSamples
            .filter { $0.time >= cutoff }
            .droppingLeadingZeroLikeSamples()
        return HeartRateSeriesCardSnapshot(kind: instance.kind, samples: trimmed)
    }

    // MARK: - Text (heart rate)

    private nonisolated static func textSnapshot(
        for kind: ActiveTrackingCardKind,
        context: Context
    ) -> TextCardSnapshot {
        switch kind {
        case .heartRate:
            let hr = context.currentHeartRate
            let avgHr = context.averageHeartRate
            let value = hr > 0 ? "\(Int(hr.rounded()))" : "--"
            let unit  = hr > 0 ? "bpm" : ""
            let subtitle: String
            if avgHr > 0 {
                subtitle = "\(String(localized: "tracking_hero_heart_rate_subtitle")) · \(Int(avgHr.rounded())) bpm"
            } else {
                subtitle = String(localized: "tracking_hero_heart_rate_subtitle")
            }
            return TextCardSnapshot(kind: kind, value: value, unit: unit, subtitle: subtitle)
        default:
            return TextCardSnapshot(kind: kind, value: "--", unit: "", subtitle: "")
        }
    }

    // MARK: - Unit conversion helpers

    nonisolated static func displaySpeed(_ ms: Double, _ us: UnitSystem) -> Double {
        switch us {
        case .metric:   return UnitConversion.metersPerSecondToKmh(ms)
        case .imperial: return UnitConversion.metersPerSecondToMph(ms)
        }
    }

    nonisolated static func speedUnit(_ us: UnitSystem) -> String { Formatters.speedUnit(us) }

    nonisolated static func displayVertical(_ meters: Double, _ us: UnitSystem) -> Double {
        us == .imperial ? UnitConversion.metersToFeet(meters) : meters
    }

    nonisolated static func verticalUnit(_ us: UnitSystem) -> String { Formatters.verticalUnit(us) }

    nonisolated static func displayDistance(_ meters: Double, _ us: UnitSystem) -> Double {
        switch us {
        case .metric:   return meters / 1000
        case .imperial: return meters / 1609.344
        }
    }

    nonisolated static func distanceUnit(_ us: UnitSystem) -> String { Formatters.distanceUnit(us) }

    nonisolated static func displayAltitude(_ meters: Double, _ us: UnitSystem) -> Double {
        us == .imperial ? UnitConversion.metersToFeet(meters) : meters
    }

    nonisolated static func altitudeUnit(_ us: UnitSystem) -> String { Formatters.verticalUnit(us) }

    // MARK: - Derived metrics

    private nonisolated static func avgSkiingSpeed(_ ctx: Context) -> Double {
        let runs = ctx.completedRuns.filter { $0.activityType == .skiing }
        let dist = runs.reduce(0.0) { $0 + $1.distance }
        let time = runs.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        guard time > 0 else { return 0 }
        return displaySpeed(dist / time, ctx.unitSystem)
    }

    private nonisolated static func liftCount(_ ctx: Context) -> Int {
        ctx.completedRuns.filter { $0.activityType == .lift }.count
    }
}
