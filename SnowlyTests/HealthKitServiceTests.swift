//
//  HealthKitServiceTests.swift
//  SnowlyTests
//
//  Tests for HealthKit integration using a mock service.
//

import Testing
import Foundation
@testable import Snowly

/// Mock HealthKit service that records all calls for verification.
@MainActor
final class MockHealthKitService: HealthKitProviding {
    var isAuthorized = false
    var isRecording = false

    // Call tracking
    var requestAuthorizationCallCount = 0
    var beginWorkoutCallCount = 0
    var beginWorkoutDates: [Date] = []
    var addRoutePointsCallCount = 0
    var addRoutePointsReceived: [[TrackPoint]] = []
    var addDistanceSampleCallCount = 0
    var addDistanceSamplesReceived: [(meters: Double, start: Date, end: Date)] = []
    var finishWorkoutCallCount = 0
    var lastWorkoutId: UUID?

    // Error injection
    var beginWorkoutError: Error?
    var finishWorkoutError: Error?

    func requestAuthorization() async {
        requestAuthorizationCallCount += 1
    }

    func beginWorkout(startDate: Date) async throws {
        beginWorkoutCallCount += 1
        beginWorkoutDates.append(startDate)
        if let error = beginWorkoutError {
            throw error
        }
        isRecording = true
    }

    func addRoutePoints(_ points: [TrackPoint]) async {
        addRoutePointsCallCount += 1
        addRoutePointsReceived.append(points)
    }

    func addDistanceSample(meters: Double, start: Date, end: Date) async {
        addDistanceSampleCallCount += 1
        addDistanceSamplesReceived.append((meters: meters, start: start, end: end))
    }

    func finishWorkout(
        endDate: Date,
        totalVerticalAscent: Double,
        totalVerticalDescent: Double
    ) async throws -> UUID {
        finishWorkoutCallCount += 1
        if let error = finishWorkoutError {
            throw error
        }
        let id = UUID()
        lastWorkoutId = id
        isRecording = false
        return id
    }
}

@Suite("HealthKit Mock Service Tests")
struct HealthKitServiceTests {

    @MainActor
    @Test("beginWorkout sets isRecording to true")
    func beginWorkout_setsIsRecording() async throws {
        let mock = MockHealthKitService()
        #expect(!mock.isRecording)

        try await mock.beginWorkout(startDate: Date())

        #expect(mock.isRecording)
        #expect(mock.beginWorkoutCallCount == 1)
    }

    @MainActor
    @Test("addRoutePoints forwards points correctly")
    func addRoutePoints_forwarded() async throws {
        let mock = MockHealthKitService()
        try await mock.beginWorkout(startDate: Date())

        let points = [
            TrackPoint(
                timestamp: Date(),
                latitude: 49.2827,
                longitude: -123.1207,
                altitude: 1200,
                speed: 5.0,
                accuracy: 10,
                course: 180
            ),
        ]
        await mock.addRoutePoints(points)

        #expect(mock.addRoutePointsCallCount == 1)
        #expect(mock.addRoutePointsReceived.first?.count == 1)
    }

    @MainActor
    @Test("finishWorkout clears isRecording and sets lastWorkoutId")
    func finishWorkout_clearsIsRecording_setsLastWorkoutId() async throws {
        let mock = MockHealthKitService()
        try await mock.beginWorkout(startDate: Date())
        #expect(mock.isRecording)

        let workoutId = try await mock.finishWorkout(
            endDate: Date(),
            totalVerticalAscent: 500,
            totalVerticalDescent: 600
        )

        #expect(!mock.isRecording)
        #expect(mock.lastWorkoutId == workoutId)
        #expect(mock.finishWorkoutCallCount == 1)
    }

    @MainActor
    @Test("beginWorkout throws does not set isRecording")
    func beginWorkout_throws_doesNotSetRecording() async {
        let mock = MockHealthKitService()
        mock.beginWorkoutError = HealthKitError.notAvailable

        do {
            try await mock.beginWorkout(startDate: Date())
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(!mock.isRecording)
        }
    }

    @MainActor
    @Test("finishWorkout throws is handled gracefully")
    func finishWorkout_throws_handledGracefully() async throws {
        let mock = MockHealthKitService()
        try await mock.beginWorkout(startDate: Date())
        mock.finishWorkoutError = HealthKitError.builderNotStarted

        do {
            _ = try await mock.finishWorkout(
                endDate: Date(),
                totalVerticalAscent: 0,
                totalVerticalDescent: 0
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // isRecording should still be true since finishWorkout threw
            #expect(mock.isRecording)
        }
    }

    @MainActor
    @Test("addDistanceSample records distance data")
    func addDistanceSample_recorded() async throws {
        let mock = MockHealthKitService()
        try await mock.beginWorkout(startDate: Date())

        let start = Date()
        let end = start.addingTimeInterval(5)
        await mock.addDistanceSample(meters: 100.0, start: start, end: end)

        #expect(mock.addDistanceSampleCallCount == 1)
        #expect(mock.addDistanceSamplesReceived.first?.meters == 100.0)
    }
}
