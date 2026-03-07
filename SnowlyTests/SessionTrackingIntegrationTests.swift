//
//  SessionTrackingIntegrationTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@MainActor
private final class MockLocationService: LocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var isTracking = false

    private var continuation: AsyncStream<TrackPoint>.Continuation?

    func requestAuthorization() {}

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
        try? await Task.sleep(for: .milliseconds(50))

        #expect(service.totalDistance == 0)
        #expect(service.totalVertical == 0)

        service.persistSnapshotNowIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))

        let persisted = TrackingStatePersistence.load()
        #expect((persisted?.totalDistance ?? 0) > 0)
        #expect((persisted?.totalVertical ?? 0) > 0)
    }
}
