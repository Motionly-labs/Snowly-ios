//
//  HealthKitCoordinatorTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct HealthKitCoordinatorTests {

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
}
