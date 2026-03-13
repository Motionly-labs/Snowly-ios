//
//  ActiveTrackingCardSnapshotAssemblerTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct ActiveTrackingCardSnapshotAssemblerTests {

    private func makeContext(
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
    ) -> ActiveTrackingCardSnapshotAssembler.Context {
        ActiveTrackingCardSnapshotAssembler.Context(
            unitSystem: unitSystem,
            skiingMetrics: skiingMetrics,
            currentSpeed: currentSpeed,
            completedRuns: completedRuns,
            speedSamples: speedSamples,
            altitudeSamples: altitudeSamples,
            currentAltitudeMeters: currentAltitudeMeters,
            elapsedSeconds: elapsedSeconds,
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            heartRateSamples: heartRateSamples
        )
    }

    @Test func snapshot_verticalScalar_convertsMetricCorrectly() {
        let metrics = SessionSkiingMetrics(totalDistance: 0, totalVertical: 500, maxSpeed: 0, runCount: 0)
        let ctx = makeContext(unitSystem: .metric, skiingMetrics: metrics)
        let instance = ActiveTrackingCardInstance.make(kind: .vertical)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .scalar(let s) = snapshot else {
            Issue.record("Expected scalar snapshot")
            return
        }
        #expect(s.value == 500)
        #expect(s.unit == "m")
    }

    @Test func snapshot_altitudeCurveSeries_trimsToWindowSeconds() {
        let now = Date()
        let old = now.addingTimeInterval(-7200)  // 2 hours ago — outside 1hr window
        let recent = now.addingTimeInterval(-1800) // 30 min ago — inside 1hr window
        let samples = [
            AltitudeSample(time: old, altitude: 1000, state: .skiing),
            AltitudeSample(time: recent, altitude: 1100, state: .skiing),
            AltitudeSample(time: now, altitude: 1200, state: .skiing)
        ]
        let ctx = makeContext(altitudeSamples: samples)
        var instance = ActiveTrackingCardInstance.make(kind: .altitudeCurve)
        instance = ActiveTrackingCardInstance(
            instanceId: instance.instanceId,
            kind: instance.kind,
            slot: instance.slot,
            presentationKind: instance.presentationKind,
            config: ActiveTrackingCardConfig(windowSeconds: 3600, smoothingAlpha: nil)
        )

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .series(let s) = snapshot else {
            Issue.record("Expected series snapshot")
            return
        }
        // Only the 2 recent samples (within 1hr) should be included
        #expect(s.samples.count == 2)
    }

    @Test func snapshot_altitudeCurveSeries_dropsLeadingZeroPlaceholder() {
        let now = Date()
        let samples = [
            AltitudeSample(time: now.addingTimeInterval(-20), altitude: 0, state: .skiing),
            AltitudeSample(time: now.addingTimeInterval(-10), altitude: 1240, state: .skiing),
            AltitudeSample(time: now, altitude: 1260, state: .skiing),
        ]
        let ctx = makeContext(altitudeSamples: samples)
        let instance = ActiveTrackingCardInstance.make(kind: .altitudeCurve)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .series(let s) = snapshot else {
            Issue.record("Expected series snapshot")
            return
        }
        #expect(s.samples.map(\.altitude) == [1240, 1260])
    }

    @Test func snapshot_heartRate_returnsDoubleDashWhenZero() {
        let ctx = makeContext(currentHeartRate: 0)
        let instance = ActiveTrackingCardInstance.make(kind: .heartRate)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .text(let t) = snapshot else {
            Issue.record("Expected text snapshot")
            return
        }
        #expect(t.value == "--")
        #expect(t.unit == "")
    }

    @Test func snapshot_heartRate_returnsFormattedBpmWhenNonZero() {
        let ctx = makeContext(currentHeartRate: 142.6)
        let instance = ActiveTrackingCardInstance.make(kind: .heartRate)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .text(let t) = snapshot else {
            Issue.record("Expected text snapshot")
            return
        }
        #expect(t.value == "143")
        #expect(t.unit == "bpm")
    }

    @Test func snapshot_heartRateCurve_returnsHeartRateSeriesSnapshot() {
        let sample = HeartRateSample(time: .now, bpm: 145)
        let ctx = makeContext(heartRateSamples: [sample])
        let instance = ActiveTrackingCardInstance.make(kind: .heartRateCurve)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .heartRateSeries(let s) = snapshot else {
            Issue.record("Expected heartRateSeries snapshot")
            return
        }
        #expect(s.kind == .heartRateCurve)
        #expect(s.samples.count == 1)
        #expect(s.samples.first?.bpm == 145)
    }

    @Test func snapshot_heartRateCurve_trimsToWindowSeconds() {
        let now = Date()
        let old = now.addingTimeInterval(-7200)    // 2 hr ago — outside 1 hr window
        let recent = now.addingTimeInterval(-1800)  // 30 min ago — inside 1 hr window
        let samples = [
            HeartRateSample(time: old, bpm: 120),
            HeartRateSample(time: recent, bpm: 140),
            HeartRateSample(time: now, bpm: 155),
        ]
        let ctx = makeContext(heartRateSamples: samples)
        let instance = ActiveTrackingCardInstance.make(kind: .heartRateCurve)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .heartRateSeries(let s) = snapshot else {
            Issue.record("Expected heartRateSeries snapshot")
            return
        }
        #expect(s.samples.count == 2)
    }

    @Test func snapshot_heartRateCurve_dropsLeadingZeroPlaceholder() {
        let now = Date()
        let samples = [
            HeartRateSample(time: now.addingTimeInterval(-20), bpm: 0),
            HeartRateSample(time: now.addingTimeInterval(-10), bpm: 136),
            HeartRateSample(time: now, bpm: 142),
        ]
        let ctx = makeContext(heartRateSamples: samples)
        let instance = ActiveTrackingCardInstance.make(kind: .heartRateCurve)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .heartRateSeries(let s) = snapshot else {
            Issue.record("Expected heartRateSeries snapshot")
            return
        }
        #expect(s.samples.map(\.bpm) == [136, 142])
    }

    @Test func snapshot_profileCard_passesThroughSamples() {
        let speed = SpeedSample(time: .now, speed: 10, state: .skiing)
        let alt   = AltitudeSample(time: .now, altitude: 1200, state: .skiing)
        let ctx = makeContext(speedSamples: [speed], altitudeSamples: [alt])
        let instance = ActiveTrackingCardInstance.make(kind: .profile)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .profile(let p) = snapshot else {
            Issue.record("Expected profile snapshot")
            return
        }
        #expect(p.speedSamples.count == 1)
        #expect(p.altitudeSamples.count == 1)
    }

    @Test func snapshot_profileCard_dropsLeadingZeroPlaceholders() {
        let now = Date()
        let speedSamples = [
            SpeedSample(time: now.addingTimeInterval(-20), speed: 0, state: .skiing),
            SpeedSample(time: now.addingTimeInterval(-10), speed: 12, state: .skiing),
        ]
        let altitudeSamples = [
            AltitudeSample(time: now.addingTimeInterval(-20), altitude: 0, state: .skiing),
            AltitudeSample(time: now.addingTimeInterval(-10), altitude: 1180, state: .skiing),
        ]
        let ctx = makeContext(speedSamples: speedSamples, altitudeSamples: altitudeSamples)
        let instance = ActiveTrackingCardInstance.make(kind: .profile)

        let snapshot = ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx)

        guard case .profile(let p) = snapshot else {
            Issue.record("Expected profile snapshot")
            return
        }
        #expect(p.speedSamples.map(\.speed) == [12])
        #expect(p.altitudeSamples.map(\.altitude) == [1180])
    }
}
