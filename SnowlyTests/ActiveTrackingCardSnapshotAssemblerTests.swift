//
//  ActiveTrackingCardSnapshotAssemblerTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct ActiveTrackingCardInputAssemblerTests {

    private func makeSource(
        unitSystem: UnitSystem = .metric,
        skiingMetrics: SessionSkiingMetrics = .zero,
        currentSpeed: Double = 0,
        completedRuns: [CompletedRunData] = [],
        speedSamples: [SpeedSample] = [],
        altitudeSamples: [AltitudeSample] = [],
        currentAltitudeMeters: Double = 0,
        elapsedSeconds: TimeInterval = 0,
        currentHeartRate: Double = 0,
        averageHeartRate: Double = 0,
        heartRateSamples: [HeartRateSample] = []
    ) -> ActiveTrackingCardInputAssembler.Source {
        ActiveTrackingCardInputAssembler.Source(
            semantic: ActiveTrackingCardInputAssembler.MotionSemanticSnapshot(
                skiingMetrics: skiingMetrics,
                currentSpeed: currentSpeed,
                currentAltitudeMeters: currentAltitudeMeters,
                completedRuns: completedRuns,
                elapsedSeconds: elapsedSeconds,
                currentHeartRate: currentHeartRate,
                averageHeartRate: averageHeartRate
            ),
            presentation: ActiveTrackingCardInputAssembler.MotionPresentationSnapshot(
                speedSamples: speedSamples,
                altitudeSamples: altitudeSamples,
                heartRateSamples: heartRateSamples
            ),
            context: ActiveTrackingCardInputAssembler.TrackingCardPresentationContext(
                unitSystem: unitSystem
            )
        )
    }

    @Test func peakSpeed_scalarInput_usesSessionSemanticMax() {
        let now = Date()
        let lastRun = CompletedRunData(
            startDate: now.addingTimeInterval(-120),
            endDate: now.addingTimeInterval(-60),
            distance: 900,
            verticalDrop: 280,
            maxSpeed: 18,
            averageSpeed: 12,
            activityType: .skiing,
            trackData: nil
        )
        let bestEarlierRun = CompletedRunData(
            startDate: now.addingTimeInterval(-300),
            endDate: now.addingTimeInterval(-240),
            distance: 1200,
            verticalDrop: 420,
            maxSpeed: 26,
            averageSpeed: 14,
            activityType: .skiing,
            trackData: nil
        )
        let source = makeSource(
            skiingMetrics: SessionSkiingMetrics(
                totalDistance: 2100,
                totalVertical: 700,
                maxSpeed: 26,
                runCount: 2
            ),
            completedRuns: [bestEarlierRun, lastRun],
            elapsedSeconds: 1800
        )

        let input = ActiveTrackingCardInputAssembler.scalarInput(for: .peakSpeed, source: source)

        guard let input else {
            Issue.record("Expected scalar input")
            return
        }
        guard case .numeric(let value) = input.primaryValue else {
            Issue.record("Expected numeric peak speed")
            return
        }

        #expect(value.value == ActiveTrackingCardInputAssembler.displaySpeed(26, .metric))
        #expect(input.subtitle?.contains("700") == true)
    }

    @Test func avgSpeed_scalarInput_usesSessionRunsNotLastRunOnly() {
        let now = Date()
        let runs = [
            CompletedRunData(
                startDate: now.addingTimeInterval(-200),
                endDate: now.addingTimeInterval(-100),
                distance: 1000,
                verticalDrop: 320,
                maxSpeed: 20,
                averageSpeed: 10,
                activityType: .skiing,
                trackData: nil
            ),
            CompletedRunData(
                startDate: now.addingTimeInterval(-90),
                endDate: now,
                distance: 600,
                verticalDrop: 200,
                maxSpeed: 16,
                averageSpeed: 6.67,
                activityType: .skiing,
                trackData: nil
            )
        ]
        let source = makeSource(
            skiingMetrics: SessionSkiingMetrics(totalDistance: 1600, totalVertical: 520, maxSpeed: 20, runCount: 2),
            completedRuns: runs
        )

        let input = ActiveTrackingCardInputAssembler.scalarInput(for: .avgSpeed, source: source)

        guard let input else {
            Issue.record("Expected avg speed input")
            return
        }
        guard case .numeric(let value) = input.primaryValue else {
            Issue.record("Expected numeric avg speed")
            return
        }

        let expectedSessionAvg = ActiveTrackingCardInputAssembler.displaySpeed(1600.0 / 190.0, .metric)
        #expect(abs(value.value - expectedSessionAvg) < 0.001)
        #expect(input.subtitle == String(localized: "tracking_avg_label_session"))
    }

    @Test func altitudeCurve_seriesInput_trimsWindowAndDropsLeadingZeros() {
        let now = Date()
        let altitudeSamples = [
            AltitudeSample(time: now.addingTimeInterval(-7200), altitude: 0, state: .skiing),
            AltitudeSample(time: now.addingTimeInterval(-1200), altitude: 1180, state: .skiing),
            AltitudeSample(time: now.addingTimeInterval(-600), altitude: 1210, state: .skiing),
            AltitudeSample(time: now, altitude: 1235, state: .skiing)
        ]
        var instance = ActiveTrackingCardInstance.make(kind: .altitudeCurve)
        instance = ActiveTrackingCardInstance(
            instanceId: instance.instanceId,
            kind: instance.kind,
            slot: instance.slot,
            presentationKind: instance.presentationKind,
            config: ActiveTrackingCardConfig(windowSeconds: 1800, smoothingAlpha: 0.22)
        )
        let source = makeSource(altitudeSamples: altitudeSamples)

        let input = ActiveTrackingCardInputAssembler.input(for: instance, source: source)

        guard case .series(let series) = input else {
            Issue.record("Expected series input")
            return
        }
        guard case .altitude(let trimmed) = series.seriesPayload else {
            Issue.record("Expected altitude payload")
            return
        }
        #expect(trimmed.map(\.altitude) == [1180, 1210, 1235])
        #expect(series.renderingPolicy.windowSeconds == 1800)
        #expect(series.renderingPolicy.smoothingAlpha == 0.22)
    }

    @Test func heartRate_scalarInput_returnsTextValueAndSubtitle() {
        let source = makeSource(currentHeartRate: 142.4, averageHeartRate: 136.2)

        let input = ActiveTrackingCardInputAssembler.scalarInput(for: .heartRate, source: source)

        guard let input else {
            Issue.record("Expected heart-rate scalar input")
            return
        }
        guard case .text(let value) = input.primaryValue else {
            Issue.record("Expected text heart-rate value")
            return
        }

        #expect(value.value == "142")
        #expect(value.unit == String(localized: "stat_heart_rate_unit"))
        #expect(input.subtitle?.contains("136") == true)
    }

}
