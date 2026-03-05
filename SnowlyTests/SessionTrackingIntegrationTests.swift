//
//  SessionTrackingIntegrationTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

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
        #expect(service.elapsedTime == 0)
        #expect(service.activeSessionId == nil)
        #expect(service.startDate == nil)
    }

    @Test func stopTracking_whenIdle_isNoOp() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        service.stopTracking()
        #expect(service.state == .idle)
    }

    @Test func pauseTracking_whenIdle_isNoOp() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        service.pauseTracking()
        #expect(service.state == .idle)
    }

    @Test func resumeTracking_whenIdle_isNoOp() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let service = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery
        )

        service.resumeTracking()
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
}
