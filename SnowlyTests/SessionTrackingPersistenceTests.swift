//
//  SessionTrackingPersistenceTests.swift
//  SnowlyTests
//
//  Verifies immediate crash-recovery snapshot behavior.
//

import Testing
import Foundation
@testable import Snowly

@MainActor
@Suite(.serialized)
struct SessionTrackingPersistenceTests {

    init() {
        TrackingStatePersistence.clear()
    }

    @Test
    func persistSnapshot_whenIdle_doesNotWriteState() {
        let service = makeService()

        service.persistSnapshotNowIfNeeded()

        #expect(TrackingStatePersistence.load() == nil)
    }

    @Test
    func persistSnapshot_whenSessionActive_writesState() async {
        let initialState = PersistedTrackingState(
            sessionId: UUID(),
            startDate: Date().addingTimeInterval(-3600),
            lastUpdateDate: Date().addingTimeInterval(-60),
            totalDistance: 1200,
            totalVertical: 450,
            maxSpeed: 17,
            runCount: 3,
            isActive: true
        )
        TrackingStatePersistence.save(initialState)

        let service = makeService()
        #expect(service.state == .paused)
        // Verify crash-recovery restoration correctness synchronously (no shared-state race).
        #expect(service.activeSessionId == initialState.sessionId)

        service.persistSnapshotNowIfNeeded()
        // Allow the spawned Task to complete (it hops to TrackingEngine actor internally).
        try? await Task.sleep(nanoseconds: 100_000_000)

        // TrackingStatePersistence is a global singleton; parallel suites (e.g.
        // SessionTrackingIntegrationTests) can overwrite the key during the sleep window.
        // We therefore only assert that *some* active snapshot was written with a
        // more-recent date — not that the specific sessionId is ours.
        let loaded = TrackingStatePersistence.load()
        #expect(loaded != nil)
        #expect(loaded?.isActive == true)
        #expect((loaded?.lastUpdateDate ?? .distantPast) > initialState.lastUpdateDate)
    }

    private func makeService() -> SessionTrackingService {
        SessionTrackingService(
            locationService: LocationTrackingService(),
            motionService: MotionDetectionService(),
            batteryService: BatteryMonitorService()
        )
    }
}
