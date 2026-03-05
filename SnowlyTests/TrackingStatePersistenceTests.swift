//
//  TrackingStatePersistenceTests.swift
//  SnowlyTests
//
//  Tests for crash recovery state persistence.
//  Serialized to avoid race conditions on shared UserDefaults.
//

import Testing
import Foundation
@testable import Snowly

@Suite(.serialized)
struct TrackingStatePersistenceTests {

    init() {
        // Clean state before each test
        TrackingStatePersistence.clear()
    }

    @Test func saveAndLoad_roundTrip() {
        let state = PersistedTrackingState(
            sessionId: UUID(),
            startDate: Date(timeIntervalSince1970: 1000000),
            lastUpdateDate: Date(timeIntervalSince1970: 1001000),
            totalDistance: 5432.1,
            totalVertical: 1234.5,
            maxSpeed: 18.3,
            runCount: 7,
            isActive: true
        )

        TrackingStatePersistence.save(state)
        let loaded = TrackingStatePersistence.load()

        #expect(loaded != nil)
        #expect(loaded?.sessionId == state.sessionId)
        #expect(loaded?.totalDistance == state.totalDistance)
        #expect(loaded?.totalVertical == state.totalVertical)
        #expect(loaded?.maxSpeed == state.maxSpeed)
        #expect(loaded?.runCount == state.runCount)
        #expect(loaded?.isActive == true)

        TrackingStatePersistence.clear()
    }

    @Test func clear_removesState() {
        let state = PersistedTrackingState(
            sessionId: UUID(),
            startDate: Date(),
            lastUpdateDate: Date(),
            totalDistance: 0,
            totalVertical: 0,
            maxSpeed: 0,
            runCount: 0,
            isActive: true
        )

        TrackingStatePersistence.save(state)
        TrackingStatePersistence.clear()
        let loaded = TrackingStatePersistence.load()

        #expect(loaded == nil)
    }

    @Test func load_whenEmpty_returnsNil() {
        let loaded = TrackingStatePersistence.load()
        #expect(loaded == nil)
    }
}
