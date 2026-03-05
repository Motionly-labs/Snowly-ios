//
//  SegmentFinalizationServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct SegmentFinalizationServiceTests {

    // MARK: - Helpers

    private func makePoint(
        speed: Double = 10.0,
        altitude: Double = 2000,
        timestamp: Date = Date(),
        lat: Double = 46.0,
        lon: Double = 7.0
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            speed: speed,
            accuracy: 5.0,
            course: 180.0
        )
    }

    // MARK: - Segment Processing

    @Test func processPoint_skiingCreatesSegment() {
        let service = SegmentFinalizationService()
        let base = Date()

        service.processPoint(makePoint(altitude: 2000, timestamp: base), activity: .skiing)
        service.processPoint(makePoint(altitude: 1990, timestamp: base.addingTimeInterval(2)), activity: .skiing)
        service.processPoint(makePoint(altitude: 1980, timestamp: base.addingTimeInterval(4)), activity: .skiing)

        #expect(service.completedRuns.isEmpty)
        #expect(service.runCount == 0)
    }

    @Test func processPoint_activityChange_finalizesSegment() {
        let service = SegmentFinalizationService()
        let base = Date()

        // Skiing segment
        service.processPoint(makePoint(altitude: 2000, timestamp: base), activity: .skiing)
        service.processPoint(makePoint(altitude: 1990, timestamp: base.addingTimeInterval(2)), activity: .skiing)

        // Switch to chairlift → finalizes skiing segment
        service.processPoint(makePoint(altitude: 1980, timestamp: base.addingTimeInterval(4)), activity: .chairlift)

        #expect(service.completedRuns.count == 1)
        #expect(service.completedRuns[0].activityType == .skiing)
        #expect(service.runCount == 1)
    }

    @Test func processPoint_chairliftToSkiing() {
        let service = SegmentFinalizationService()
        let base = Date()

        // Chairlift segment
        service.processPoint(makePoint(altitude: 1800, timestamp: base), activity: .chairlift)
        service.processPoint(makePoint(altitude: 1900, timestamp: base.addingTimeInterval(60)), activity: .chairlift)

        // Switch to skiing → finalizes chairlift segment
        service.processPoint(makePoint(altitude: 2000, timestamp: base.addingTimeInterval(120)), activity: .skiing)

        #expect(service.completedRuns.count == 1)
        #expect(service.completedRuns[0].activityType == .chairlift)
        #expect(service.runCount == 0)  // Chairlift doesn't increment runCount
    }

    @Test func finalizeCurrentSegment_emptySegment_noOp() {
        let service = SegmentFinalizationService()
        service.finalizeCurrentSegment()
        #expect(service.completedRuns.isEmpty)
    }

    @Test func finalizeCurrentSegment_producesRunData() {
        let service = SegmentFinalizationService()
        let base = Date()

        service.processPoint(makePoint(altitude: 2000, timestamp: base), activity: .skiing)
        service.processPoint(makePoint(altitude: 1950, timestamp: base.addingTimeInterval(5)), activity: .skiing)
        service.finalizeCurrentSegment()

        #expect(service.completedRuns.count == 1)
        let run = service.completedRuns[0]
        #expect(run.activityType == .skiing)
        #expect(run.verticalDrop >= 0)
        #expect(run.trackData != nil)
    }

    @Test func reset_clearsAllState() {
        let service = SegmentFinalizationService()
        let base = Date()

        service.processPoint(makePoint(timestamp: base), activity: .skiing)
        service.processPoint(makePoint(timestamp: base.addingTimeInterval(2)), activity: .skiing)
        service.finalizeCurrentSegment()

        #expect(service.completedRuns.count == 1)

        service.reset()
        #expect(service.completedRuns.isEmpty)
        #expect(service.runCount == 0)
    }

    @Test func idle_afterTimeout_finalizesSegment() {
        let service = SegmentFinalizationService()
        let base = Date()

        service.processPoint(makePoint(timestamp: base), activity: .skiing)
        service.processPoint(makePoint(timestamp: base.addingTimeInterval(2)), activity: .skiing)

        // Idle for longer than stopDurationThreshold (75s)
        service.processPoint(
            makePoint(timestamp: base.addingTimeInterval(2 + SharedConstants.stopDurationThreshold + 1)),
            activity: .idle
        )

        #expect(service.completedRuns.count == 1)
    }
}
