//
//  WatchWorkoutManagerUITestingTests.swift
//  SnowlyWatchTests
//

import Testing
@testable import Snowly_Watch_App

@MainActor
struct WatchWorkoutManagerUITestingTests {

    @Test func uiTestingConfiguration_withoutFlag_leavesStateUntouched() {
        let manager = WatchWorkoutManager()

        let didApply = manager.applyUITestingConfigurationIfNeeded(arguments: [])

        #expect(didApply == false)
        #expect(manager.trackingState == .idle)
        #expect(manager.runCount == 0)
    }

    @Test func uiTestingConfiguration_active_setsIndependentWorkoutSampleData() {
        let manager = WatchWorkoutManager()

        let didApply = manager.applyUITestingConfigurationIfNeeded(
            arguments: ["-watch_ui_testing", "-watch_ui_testing_active"]
        )

        #expect(didApply == true)
        #expect(manager.trackingState == .active(mode: .independent))
        #expect(manager.runCount == 6)
        #expect(manager.totalDistance == 5_420)
        #expect(manager.currentHeartRate == 142)
        #expect(manager.summarySyncMessage == nil)
    }

    @Test func uiTestingConfiguration_paused_marksPausedState() {
        let manager = WatchWorkoutManager()

        let didApply = manager.applyUITestingConfigurationIfNeeded(
            arguments: ["-watch_ui_testing", "-watch_ui_testing_paused"]
        )

        #expect(didApply == true)
        #expect(manager.trackingState == .paused)
        #expect(manager.maxSpeed == 24.8)
        #expect(manager.lastCompletedRun?.runNumber == 6)
    }

    @Test func uiTestingConfiguration_summary_exposesSyncMessage() {
        let manager = WatchWorkoutManager()

        let didApply = manager.applyUITestingConfigurationIfNeeded(
            arguments: ["-watch_ui_testing", "-watch_ui_testing_summary"]
        )

        #expect(didApply == true)
        #expect(manager.trackingState == .summary)
        #expect(manager.summarySyncMessage != nil)
    }

    @Test func uiTestingInteractiveFlow_transitionsThroughWorkoutStates() {
        let manager = WatchWorkoutManager()

        let didApply = manager.applyUITestingConfigurationIfNeeded(
            arguments: ["-watch_ui_testing", "-watch_ui_testing_interactive"]
        )

        #expect(didApply == true)
        #expect(manager.trackingState == .idle)

        manager.start()
        #expect(manager.trackingState == .active(mode: .independent))

        manager.pause()
        #expect(manager.trackingState == .paused)

        manager.resume()
        #expect(manager.trackingState == .active(mode: .independent))

        manager.stop()
        #expect(manager.trackingState == .summary)
        #expect(manager.summarySyncMessage != nil)

        manager.dismiss()
        #expect(manager.trackingState == .idle)
    }
}
