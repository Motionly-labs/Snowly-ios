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
    func persistSnapshot_whenSessionActive_writesState() {
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

        service.persistSnapshotNowIfNeeded()

        let loaded = TrackingStatePersistence.load()
        #expect(loaded != nil)
        #expect(loaded?.sessionId == initialState.sessionId)
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
