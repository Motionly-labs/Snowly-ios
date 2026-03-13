//
//  HealthKitCoordinatorTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct HealthKitCoordinatorTests {

    private func makePoint(
        speed: Double = 5,
        altitude: Double = 2000,
        timestamp: Date = Date()
    ) -> FilteredTrackPoint {
        FilteredTrackPoint(
            rawTimestamp: timestamp,
            timestamp: timestamp,
            latitude: 46.0,
            longitude: 7.0,
            altitude: altitude,
            estimatedSpeed: speed,
            horizontalAccuracy: 5,
            verticalAccuracy: 9,
            course: 180
        )
    }

    @Test func init_withNilService() {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        #expect(coordinator.pendingWorkoutId == nil)
    }

    @Test func startWorkout_whenDisabled_doesNothing() {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        coordinator.startWorkout(healthKitEnabled: false, startDate: Date())
        #expect(coordinator.pendingWorkoutId == nil)
    }

    @Test func startWorkout_whenNoService_doesNothing() {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        coordinator.startWorkout(healthKitEnabled: true, startDate: Date())
        #expect(coordinator.pendingWorkoutId == nil)
    }

    @Test func cancel_doesNotCrash() {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        coordinator.cancel()
        #expect(coordinator.pendingWorkoutId == nil)
    }

    @Test func reset_clearsState() {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        coordinator.reset()
        #expect(coordinator.pendingWorkoutId == nil)
    }

    @Test func finalizeWorkout_withNilService_returnsNil() async {
        let coordinator = HealthKitCoordinator(healthKitService: nil)
        let result = await coordinator.finalizeWorkout()
        #expect(result == nil)
    }

    @Test func forwardPoint_withoutRequestedWorkout_doesNothing() async {
        let mock = MockHealthKitService()
        mock.isAuthorized = true
        mock.isRecording = true

        let coordinator = HealthKitCoordinator(healthKitService: mock, flushInterval: 0.01)
        let previous = makePoint(timestamp: Date().addingTimeInterval(-1))
        let point = makePoint(timestamp: Date())

        coordinator.forwardPoint(point, previousPoint: previous, distance: 42, isSkiing: true)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(mock.addRoutePointsCallCount == 0)
        #expect(mock.addDistanceSampleCallCount == 0)
        #expect(mock.finishWorkoutCallCount == 0)
    }

    @Test func finalizeWorkout_flushesBufferedPointsAndSamples() async {
        let mock = MockHealthKitService()
        mock.isAuthorized = true
        let coordinator = HealthKitCoordinator(healthKitService: mock, flushInterval: 60)

        coordinator.startWorkout(healthKitEnabled: true, startDate: Date())
        await Task.yield()

        let previous = makePoint(timestamp: Date().addingTimeInterval(-2))
        let point = makePoint(timestamp: Date())
        coordinator.forwardPoint(point, previousPoint: previous, distance: 120, isSkiing: true)

        let result = await coordinator.finalizeWorkout()

        #expect(result != nil)
        #expect(mock.addRoutePointsCallCount == 1)
        #expect(mock.addRoutePointsReceived == [[point]])
        #expect(mock.addDistanceSampleCallCount == 1)
        #expect(mock.finishWorkoutCallCount == 1)
        #expect(coordinator.pendingWorkoutId == result)
    }

    @Test func finalizeWorkout_waitsForInFlightFlushBeforeFinishing() async {
        let mock = MockHealthKitService()
        mock.isAuthorized = true
        mock.addRoutePointsDelay = 0.05
        let coordinator = HealthKitCoordinator(healthKitService: mock, flushInterval: 0.01)

        coordinator.startWorkout(healthKitEnabled: true, startDate: Date())
        await Task.yield()

        let previous = makePoint(timestamp: Date().addingTimeInterval(-2))
        let point = makePoint(timestamp: Date())
        coordinator.forwardPoint(point, previousPoint: previous, distance: 80, isSkiing: true)

        try? await Task.sleep(for: .milliseconds(20))
        let result = await coordinator.finalizeWorkout()

        #expect(result != nil)
        #expect(mock.addRoutePointsCallCount == 1)
        #expect(mock.finishWorkoutCallCount == 1)
        #expect(mock.lastRouteInsertFinishedAt != nil)
        #expect(mock.finishWorkoutCalledAt != nil)
        #expect((mock.finishWorkoutCalledAt ?? .distantPast) >= (mock.lastRouteInsertFinishedAt ?? .distantFuture))
    }
}
