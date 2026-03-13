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
    var isGPSReadyForTracking: Bool { true }

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
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 9,
        course: Double = 180
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            speed: speed,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
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

    @Test func persistSnapshotNowIfNeeded_persistsLatestProcessedMetrics() async {
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

        location.emit(makePoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2100,
            speed: 8.0,
            course: 180
        ))
        await Task.yield()

        location.emit(makePoint(
            timestamp: start.addingTimeInterval(5),
            latitude: 46.001,
            longitude: 7.001,
            altitude: 2050,
            speed: 8.0,
            course: 180
        ))
        await Task.yield()
        location.emit(makePoint(
            timestamp: start.addingTimeInterval(10),
            latitude: 46.002,
            longitude: 7.002,
            altitude: 2000,
            speed: 8.0,
            course: 180
        ))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(service.totalDistance > 0)
        #expect(service.totalVertical > 0)

        service.persistSnapshotNowIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))

        let persisted = TrackingStatePersistence.load()
        #expect(persisted?.totalDistance == service.totalDistance)
        #expect(persisted?.totalVertical == service.totalVertical)
        #expect(persisted?.maxSpeed == service.maxSpeed)
        #expect(persisted?.runCount == service.runCount)

        await service.stopTracking()
    }

    @Test func curveSamples_followGpsEvents_notTimerTicks() async {
        let location = MockLocationService()
        let motion = MockMotionService()
        let battery = MockBatteryService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        let start = Date()
        let firstPoint = makePoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2100,
            speed: 12.0
        )
        let secondPoint = makePoint(
            timestamp: start.addingTimeInterval(1),
            latitude: 46.0001,
            longitude: 7.0001,
            altitude: 2094,
            speed: 11.5
        )
        let thirdPoint = makePoint(
            timestamp: start.addingTimeInterval(3),
            latitude: 46.0003,
            longitude: 7.0003,
            altitude: 2080,
            speed: 10.8
        )

        service.startTracking()
        try? await Task.sleep(for: .milliseconds(20))

        location.emit(firstPoint)
        await Task.yield()
        location.emit(secondPoint)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(service.speedSamples.count == 1)
        #expect(service.altitudeSamples.count == 1)
        #expect(service.speedSamples.first?.time == firstPoint.timestamp)
        #expect(service.altitudeSamples.first?.time == firstPoint.timestamp)

        let sampleCount = service.speedSamples.count
        try? await Task.sleep(for: .milliseconds(2200))
        #expect(service.speedSamples.count == sampleCount)
        #expect(service.altitudeSamples.count == sampleCount)

        location.emit(thirdPoint)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(service.speedSamples.count == 2)
        #expect(service.altitudeSamples.count == 2)
        #expect(service.speedSamples.last?.time == thirdPoint.timestamp)
        #expect(service.altitudeSamples.last?.time == thirdPoint.timestamp)

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

        location.emit(makePoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2100,
            speed: 1.0,
            course: 180
        ))
        await Task.yield()

        location.emit(makePoint(
            timestamp: start.addingTimeInterval(1),
            latitude: 46.0005,
            longitude: 7.0005,
            altitude: 2095,
            speed: 9.0,
            course: 180
        ))
        await Task.yield()
        location.emit(makePoint(
            timestamp: start.addingTimeInterval(5),
            latitude: 46.0012,
            longitude: 7.0012,
            altitude: 2088,
            speed: 9.2,
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

        location.emit(makePoint(
            timestamp: start,
            latitude: 46.0,
            longitude: 7.0,
            altitude: 2000,
            speed: 14.0,
            course: 0
        ))
        await Task.yield()

        location.emit(makePoint(
            timestamp: start.addingTimeInterval(12),
            latitude: 46.001,
            longitude: 7.001,
            altitude: 2050,
            speed: 15.0,
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

    @Test func saveSession_persistsRawTrackData_andDerivesFilteredTrackPoints() async throws {
        TrackingStatePersistence.clear()

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
            horizontalAccuracy: 24,
            verticalAccuracy: 36,
            course: 15
        )
        let bootstrapPoint2 = makePoint(
            timestamp: base.addingTimeInterval(15),
            latitude: 46.0018,
            longitude: 7.0004,
            altitude: 2140,
            speed: 15.2,
            horizontalAccuracy: 30,
            verticalAccuracy: 45,
            course: 20
        )
        let bootstrapPoint3 = makePoint(
            timestamp: base.addingTimeInterval(30),
            latitude: 46.0039,
            longitude: 7.0010,
            altitude: 2080,
            speed: 14.9,
            horizontalAccuracy: 28,
            verticalAccuracy: 42,
            course: 24
        )
        let rawExportPoint1 = makePoint(
            timestamp: base.addingTimeInterval(45),
            latitude: 46.0062,
            longitude: 7.0006,
            altitude: 2010,
            speed: 15.4,
            horizontalAccuracy: 31,
            verticalAccuracy: 46,
            course: 28
        )
        let rawExportPoint2 = makePoint(
            timestamp: base.addingTimeInterval(60),
            latitude: 46.0087,
            longitude: 7.0014,
            altitude: 1940,
            speed: 15.1,
            horizontalAccuracy: 29,
            verticalAccuracy: 43,
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

        guard let rawTrackData = run.trackData else {
            Issue.record("Expected raw track data to be persisted")
            return
        }

        let rawDecoded = try JSONDecoder().decode([TrackPoint].self, from: rawTrackData)
        let rawTimestamps = Set(rawDecoded.map(\.timestamp))
        let emittedTimestamps = Set([
            bootstrapPoint1,
            bootstrapPoint2,
            bootstrapPoint3,
            rawExportPoint1,
            rawExportPoint2,
        ].map(\.timestamp))
        #expect(rawTimestamps.isSubset(of: emittedTimestamps))
        #expect(rawTimestamps.contains(rawExportPoint1.timestamp))
        #expect(rawTimestamps.contains(rawExportPoint2.timestamp))

        let decoded = run.trackPoints
        #expect(!decoded.isEmpty)

        var filter = GPSKalmanFilter()
        var expectedByTimestamp: [Date: FilteredTrackPoint] = [:]
        for point in rawDecoded.sorted(by: { $0.timestamp < $1.timestamp }) {
            expectedByTimestamp[point.timestamp] = filter.update(point: point)
        }

        guard let expectedPoint1 = expectedByTimestamp[rawExportPoint1.timestamp] else {
            Issue.record("Missing first raw segment point in persisted track data")
            return
        }
        guard let expectedPoint2 = expectedByTimestamp[rawExportPoint2.timestamp] else {
            Issue.record("Missing second raw segment point in persisted track data")
            return
        }

        guard let savedPoint1 = decoded.first(where: { $0.timestamp == rawExportPoint1.timestamp }) else {
            Issue.record("Missing first derived filtered segment point in saved track data")
            return
        }
        #expect(abs(savedPoint1.latitude - expectedPoint1.latitude) < 1e-9)
        #expect(abs(savedPoint1.longitude - expectedPoint1.longitude) < 1e-9)
        #expect(abs(savedPoint1.altitude - expectedPoint1.altitude) < 1e-9)
        #expect(abs(savedPoint1.estimatedSpeed - expectedPoint1.estimatedSpeed) < 1e-9)
        #expect(savedPoint1.rawTimestamp == rawExportPoint1.timestamp)
        #expect(savedPoint1.horizontalAccuracy == expectedPoint1.horizontalAccuracy)
        #expect(savedPoint1.verticalAccuracy == expectedPoint1.verticalAccuracy)
        #expect(abs(savedPoint1.course - expectedPoint1.course) < 1e-9)

        guard let savedPoint2 = decoded.first(where: { $0.timestamp == rawExportPoint2.timestamp }) else {
            Issue.record("Missing second derived filtered segment point in saved track data")
            return
        }
        #expect(abs(savedPoint2.latitude - expectedPoint2.latitude) < 1e-9)
        #expect(abs(savedPoint2.longitude - expectedPoint2.longitude) < 1e-9)
        #expect(abs(savedPoint2.altitude - expectedPoint2.altitude) < 1e-9)
        #expect(abs(savedPoint2.estimatedSpeed - expectedPoint2.estimatedSpeed) < 1e-9)
        #expect(savedPoint2.rawTimestamp == rawExportPoint2.timestamp)
        #expect(savedPoint2.horizontalAccuracy == expectedPoint2.horizontalAccuracy)
        #expect(savedPoint2.verticalAccuracy == expectedPoint2.verticalAccuracy)
        #expect(abs(savedPoint2.course - expectedPoint2.course) < 1e-9)
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
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
            course: 180
        )
        let bufferedPoint2 = makePoint(
            timestamp: base.addingTimeInterval(-15),
            latitude: 46.002,
            longitude: 7.0006,
            altitude: 2160,
            speed: 14.8,
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
            course: 182
        )
        location.bufferedPoints = [bufferedPoint1, bufferedPoint2]

        let livePoint1 = makePoint(
            timestamp: base,
            latitude: 46.004,
            longitude: 7.0012,
            altitude: 2090,
            speed: 15.0,
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
            course: 184
        )
        let livePoint2 = makePoint(
            timestamp: base.addingTimeInterval(15),
            latitude: 46.006,
            longitude: 7.0018,
            altitude: 2025,
            speed: 15.2,
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
            course: 186
        )
        let livePoint3 = makePoint(
            timestamp: base.addingTimeInterval(30),
            latitude: 46.008,
            longitude: 7.0024,
            altitude: 1960,
            speed: 15.1,
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
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
