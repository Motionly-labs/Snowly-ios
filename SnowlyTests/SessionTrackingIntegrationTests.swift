//
//  SessionTrackingIntegrationTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import Snowly

@MainActor
private final class MockLocationService: LocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var isTracking = false
    var currentAltitude: Double = 0

    private var continuation: AsyncStream<TrackPoint>.Continuation?
    var bufferedPoints: [TrackPoint] = []

    func requestAuthorization() {}

    func recentTrackPointsSnapshot() -> [TrackPoint] {
        bufferedPoints
    }

    func startTracking() -> AsyncStream<TrackPoint> {
        isTracking = true
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func stopTracking() {
        isTracking = false
        continuation?.finish()
        continuation = nil
    }

    func emit(_ point: TrackPoint) {
        bufferedPoints.append(point)
        continuation?.yield(point)
    }
}

@MainActor
private final class MockMotionService: MotionDetecting {
    var isAvailable = true
    var isAuthorized = true
    var currentMotion: DetectedMotion = .unknown

    func requestAuthorization() {}
    func startMonitoring() {}
    func stopMonitoring() {}
}

@MainActor
private final class MockBatteryService: BatteryMonitoring {
    var batteryLevel: Float = 1
    var isCharging = false
    var isLowBattery = false
    var estimatedRemainingTime: TimeInterval? = nil

    func startMonitoring() {}
    func stopMonitoring() {}
}

@Suite(.serialized)
@MainActor
struct SessionTrackingIntegrationTests {

    init() {
        TrackingStatePersistence.clear()
    }

    private func makePoint(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speed: Double,
        accuracy: Double = 5,
        course: Double = 180
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            speed: speed,
            accuracy: accuracy,
            course: course
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            SkiSession.self,
            SkiRun.self,
            Resort.self,
        ])
        let configuration = ModelConfiguration(
            "SessionTrackingTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: SkiSession.self,
                 SkiRun.self,
                 Resort.self,
            configurations: configuration
        )
    }

    @Test func initialState() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        #expect(service.state == .idle)
        #expect(service.currentSpeed == 0)
        #expect(service.maxSpeed == 0)
        #expect(service.totalDistance == 0)
        #expect(service.totalVertical == 0)
        #expect(service.runCount == 0)
        #expect(service.computeElapsedTime() == 0)
        #expect(service.activeSessionId == nil)
        #expect(service.startDate == nil)
    }

    @Test func stopTracking_whenIdle_isNoOp() async {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        await service.stopTracking()
        #expect(service.state == .idle)
    }

    @Test func pauseTracking_whenIdle_isNoOp() async {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        await service.pauseTracking()
        #expect(service.state == .idle)
    }

    @Test func resumeTracking_whenIdle_isNoOp() async {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        await service.resumeTracking()
        #expect(service.state == .idle)
    }

    @Test func segmentService_isAccessible() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        #expect(service.completedRuns.isEmpty)
        #expect(service.runCount == 0)
    }

    @Test func healthKitCoordinator_isAccessible() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        #expect(service.pendingHealthKitWorkoutId == nil)
    }

    @Test func finalizeHealthKitWorkout_whenNoHK_isNoOp() async {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        await service.finalizeHealthKitWorkout()
        #expect(service.pendingHealthKitWorkoutId == nil)
    }

    @Test func persistSnapshotNowIfNeeded_usesTrackingEngineState() async {
        let location = MockLocationService()
        let motion = MockMotionService()
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let start = Date()
        service.startTracking()
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(TrackPoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2100,
            speed: 8.0,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()

        location.emit(TrackPoint(
            timestamp: start.addingTimeInterval(5),
            latitude: 46.001,
            longitude: 7.001,
            altitude: 2050,
            speed: 8.0,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()
        location.emit(TrackPoint(
            timestamp: start.addingTimeInterval(10),
            latitude: 46.002,
            longitude: 7.002,
            altitude: 2000,
            speed: 8.0,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(service.totalDistance == 0)
        #expect(service.totalVertical == 0)

        service.persistSnapshotNowIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))

        let persisted = TrackingStatePersistence.load()
        #expect((persisted?.totalDistance ?? 0) > 0)
        #expect((persisted?.totalVertical ?? 0) > 0)

        await service.stopTracking()
    }

    @Test func detectionPipeline_processesEveryPoint_evenWhenUiIntervalIsHigh() async {
        let location = MockLocationService()
        let motion = MockMotionService()
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let start = Date()
        service.startTracking()
        service.updateTrackingUpdateInterval(seconds: 30)
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(TrackPoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2100,
            speed: 1.0,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()

        location.emit(TrackPoint(
            timestamp: start.addingTimeInterval(1),
            latitude: 46.0005,
            longitude: 7.0005,
            altitude: 2095,
            speed: 9.0,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()
        location.emit(TrackPoint(
            timestamp: start.addingTimeInterval(5),
            latitude: 46.0012,
            longitude: 7.0012,
            altitude: 2088,
            speed: 9.2,
            accuracy: 5,
            course: 180
        ))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        await service.pauseTracking()
        #expect(service.maxSpeed >= 8.0)

        await service.stopTracking()
    }

    @Test func skiingMetrics_excludesLiftSpeed() async {
        let location = MockLocationService()
        let motion = MockMotionService()
        motion.currentMotion = .automotive
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let start = Date()
        service.startTracking()
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(TrackPoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2000,
            speed: 14.0,
            accuracy: 5,
            course: 0
        ))
        await Task.yield()

        location.emit(TrackPoint(
            timestamp: start.addingTimeInterval(12),
            latitude: 46.001,
            longitude: 7.001,
            altitude: 2050,
            speed: 15.0,
            accuracy: 5,
            course: 0
        ))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))

        await service.pauseTracking()

        #expect(service.maxSpeed == 0)
        #expect(service.skiingMetrics.maxSpeed == 0)
        #expect(service.skiingMetrics.runCount == 0)
        #expect(service.skiingMetrics.totalDistance == 0)
        #expect(service.skiingMetrics.totalVertical == 0)

        await service.stopTracking()
    }

    @Test func saveSession_preservesRawTrackDataForExport() async throws {
        let location = MockLocationService()
        let motion = MockMotionService()
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let base = Date()
        let bootstrapPoint1 = makePoint(
            timestamp: base,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2200,
            speed: 15.0,
            accuracy: 24,
            course: 15
        )
        let bootstrapPoint2 = makePoint(
            timestamp: base.addingTimeInterval(15),
            latitude: 46.0018,
            longitude: 7.0004,
            altitude: 2140,
            speed: 15.2,
            accuracy: 30,
            course: 20
        )
        let bootstrapPoint3 = makePoint(
            timestamp: base.addingTimeInterval(30),
            latitude: 46.0039,
            longitude: 7.0010,
            altitude: 2080,
            speed: 14.9,
            accuracy: 28,
            course: 24
        )
        let rawExportPoint1 = makePoint(
            timestamp: base.addingTimeInterval(45),
            latitude: 46.0062,
            longitude: 7.0006,
            altitude: 2010,
            speed: 15.4,
            accuracy: 31,
            course: 28
        )
        let rawExportPoint2 = makePoint(
            timestamp: base.addingTimeInterval(60),
            latitude: 46.0087,
            longitude: 7.0014,
            altitude: 1940,
            speed: 15.1,
            accuracy: 29,
            course: 33
        )

        service.startTracking()
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(bootstrapPoint1)
        await Task.yield()
        location.emit(bootstrapPoint2)
        await Task.yield()
        location.emit(bootstrapPoint3)
        await Task.yield()
        location.emit(rawExportPoint1)
        await Task.yield()
        location.emit(rawExportPoint2)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))

        await service.stopTracking()

        let container = try makeInMemoryContainer()
        let context = container.mainContext

        await service.saveSession(to: context)
        try context.save()

        let runs = try context.fetch(FetchDescriptor<SkiRun>())
        #expect(runs.count == 1)

        guard let run = runs.first else {
            Issue.record("Expected one saved run")
            return
        }

        let decoded = run.trackPoints
        #expect(!decoded.isEmpty)

        guard let savedPoint1 = decoded.first(where: { $0.timestamp == rawExportPoint1.timestamp }) else {
            Issue.record("Missing first raw segment point in saved track data")
            return
        }
        #expect(savedPoint1.latitude == rawExportPoint1.latitude)
        #expect(savedPoint1.longitude == rawExportPoint1.longitude)
        #expect(savedPoint1.altitude == rawExportPoint1.altitude)
        #expect(savedPoint1.speed == rawExportPoint1.speed)
        #expect(savedPoint1.accuracy == rawExportPoint1.accuracy)
        #expect(savedPoint1.course == rawExportPoint1.course)

        guard let savedPoint2 = decoded.first(where: { $0.timestamp == rawExportPoint2.timestamp }) else {
            Issue.record("Missing second raw segment point in saved track data")
            return
        }
        #expect(savedPoint2.latitude == rawExportPoint2.latitude)
        #expect(savedPoint2.longitude == rawExportPoint2.longitude)
        #expect(savedPoint2.altitude == rawExportPoint2.altitude)
        #expect(savedPoint2.speed == rawExportPoint2.speed)
        #expect(savedPoint2.accuracy == rawExportPoint2.accuracy)
        #expect(savedPoint2.course == rawExportPoint2.course)
    }

    @Test func pretrackingBuffer_seedsWindowWithoutPersistingPreStartPoints() async throws {
        let location = MockLocationService()
        let motion = MockMotionService()
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let base = Date()
        let bufferedPoint1 = makePoint(
            timestamp: base.addingTimeInterval(-30),
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2220,
            speed: 14.5,
            accuracy: 8,
            course: 180
        )
        let bufferedPoint2 = makePoint(
            timestamp: base.addingTimeInterval(-15),
            latitude: 46.002,
            longitude: 7.0006,
            altitude: 2160,
            speed: 14.8,
            accuracy: 8,
            course: 182
        )
        location.bufferedPoints = [bufferedPoint1, bufferedPoint2]

        let livePoint1 = makePoint(
            timestamp: base,
            latitude: 46.004,
            longitude: 7.0012,
            altitude: 2090,
            speed: 15.0,
            accuracy: 8,
            course: 184
        )
        let livePoint2 = makePoint(
            timestamp: base.addingTimeInterval(15),
            latitude: 46.006,
            longitude: 7.0018,
            altitude: 2025,
            speed: 15.2,
            accuracy: 8,
            course: 186
        )
        let livePoint3 = makePoint(
            timestamp: base.addingTimeInterval(30),
            latitude: 46.008,
            longitude: 7.0024,
            altitude: 1960,
            speed: 15.1,
            accuracy: 8,
            course: 188
        )

        service.startTracking()
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(livePoint1)
        await Task.yield()
        location.emit(livePoint2)
        await Task.yield()
        location.emit(livePoint3)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))

        await service.stopTracking()

        let container = try makeInMemoryContainer()
        let context = container.mainContext
        await service.saveSession(to: context)
        try context.save()

        let runs = try context.fetch(FetchDescriptor<SkiRun>())
        #expect(runs.count == 1)

        guard let run = runs.first else {
            Issue.record("Expected one saved run")
            return
        }

        let savedTimestamps = Set(run.trackPoints.map(\.timestamp))
        #expect(!savedTimestamps.contains(bufferedPoint1.timestamp))
        #expect(!savedTimestamps.contains(bufferedPoint2.timestamp))
        #expect(savedTimestamps.contains(livePoint2.timestamp))
        #expect(savedTimestamps.contains(livePoint3.timestamp))
    }
}
