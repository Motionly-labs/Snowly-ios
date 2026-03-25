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

    @Test
    func restoreState_whenCompletedRunHasTrackFile_restoresTrackData() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let trackPoints = [
            TrackPoint(
                timestamp: timestamp,
                latitude: 46.0,
                longitude: 7.0,
                altitude: 2_400,
                speed: 12,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                course: 180
            ),
            TrackPoint(
                timestamp: timestamp.addingTimeInterval(5),
                latitude: 46.0005,
                longitude: 7.0005,
                altitude: 2_360,
                speed: 15,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                course: 182
            ),
        ]
        let trackFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try JSONEncoder().encode(trackPoints).write(to: trackFileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: trackFileURL) }

        let initialState = PersistedTrackingState(
            sessionId: UUID(),
            startDate: timestamp,
            lastUpdateDate: timestamp.addingTimeInterval(60),
            totalDistance: 1200,
            totalVertical: 450,
            maxSpeed: 15,
            runCount: 1,
            isActive: true,
            completedRuns: [
                PersistedCompletedRun(
                    startDate: timestamp,
                    endDate: timestamp.addingTimeInterval(5),
                    distance: 120,
                    verticalDrop: 40,
                    maxSpeed: 15,
                    averageSpeed: 13,
                    activityType: .skiing,
                    trackFilePath: trackFileURL.path
                ),
            ]
        )
        TrackingStatePersistence.save(initialState)

        let service = makeService()

        #expect(service.state == .paused)
        #expect(service.completedRuns.count == 1)
        let restoredData = try #require(service.completedRuns.first?.trackData)
        let restoredPoints = try JSONDecoder().decode([TrackPoint].self, from: restoredData)
        #expect(restoredPoints == trackPoints)
    }

    @Test
    func restoreState_whenCompletedRunHasNDJSONTrackFile_restoresTrackData() throws {
        let timestamp = Date(timeIntervalSince1970: 1_100_000)
        let trackPoints = [
            TrackPoint(
                timestamp: timestamp,
                latitude: 46.1,
                longitude: 7.1,
                altitude: 2_410,
                speed: 10,
                horizontalAccuracy: 4,
                verticalAccuracy: 6,
                course: 175
            ),
            TrackPoint(
                timestamp: timestamp.addingTimeInterval(4),
                latitude: 46.1004,
                longitude: 7.1004,
                altitude: 2_380,
                speed: 14,
                horizontalAccuracy: 4,
                verticalAccuracy: 6,
                course: 176
            ),
        ]
        let encoder = JSONEncoder()
        let ndjson = try trackPoints
            .map { try String(decoding: encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
        let trackFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ndjson")
        try Data(ndjson.utf8).write(to: trackFileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: trackFileURL) }

        let initialState = PersistedTrackingState(
            sessionId: UUID(),
            startDate: timestamp,
            lastUpdateDate: timestamp.addingTimeInterval(60),
            totalDistance: 900,
            totalVertical: 300,
            maxSpeed: 14,
            runCount: 1,
            isActive: true,
            completedRuns: [
                PersistedCompletedRun(
                    startDate: timestamp,
                    endDate: timestamp.addingTimeInterval(4),
                    distance: 90,
                    verticalDrop: 30,
                    maxSpeed: 14,
                    averageSpeed: 12,
                    activityType: .skiing,
                    trackFilePath: trackFileURL.path
                ),
            ]
        )
        TrackingStatePersistence.save(initialState)

        let service = makeService()

        #expect(service.completedRuns.count == 1)
        let restoredData = try #require(service.completedRuns.first?.trackData)
        let restoredPoints = try JSONDecoder().decode([TrackPoint].self, from: restoredData)
        #expect(restoredPoints == trackPoints)
    }

    private func makeService() -> SessionTrackingService {
        SessionTrackingService(
            locationService: LocationTrackingService(),
            motionService: MotionDetectionService(),
            batteryService: BatteryMonitorService()
        )
    }
}
