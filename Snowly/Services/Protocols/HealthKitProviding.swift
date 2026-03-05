//
//  HealthKitProviding.swift
//  Snowly
//
//  Protocol for HealthKit workout services — enables mock injection for testing.
//

import Foundation

enum HealthKitError: Error, Sendable {
    case notAvailable
    case notAuthorized
    case builderNotStarted
    case workoutFinalizationFailed(String)
}

@MainActor
protocol HealthKitProviding: AnyObject, Sendable {
    var isAuthorized: Bool { get }
    var isRecording: Bool { get }

    func requestAuthorization() async
    func beginWorkout(startDate: Date) async throws
    func addRoutePoints(_ points: [TrackPoint]) async
    func addDistanceSample(meters: Double, start: Date, end: Date) async
    func finishWorkout(
        endDate: Date,
        totalVerticalAscent: Double,
        totalVerticalDescent: Double
    ) async throws -> UUID
}
