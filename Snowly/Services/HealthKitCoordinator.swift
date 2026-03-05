//
//  HealthKitCoordinator.swift
//  Snowly
//
//  Coordinates HealthKit workout lifecycle during a tracking session.
//  Delegates actual HK API calls to HealthKitService.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class HealthKitCoordinator {

    private(set) var pendingWorkoutId: UUID?

    private let healthKitService: (any HealthKitProviding)?
    private var healthKitTask: Task<Void, Never>?
    private var totalVerticalAscent: Double = 0
    private var totalVerticalDescent: Double = 0
    private var forwardTaskCount = 0
    private static let maxForwardTasks = 10
    private static let logger = Logger(subsystem: "com.Snowly", category: "HealthKitCoordinator")

    init(healthKitService: (any HealthKitProviding)?) {
        self.healthKitService = healthKitService
    }

    /// Start a HealthKit workout session if enabled and authorized.
    func startWorkout(healthKitEnabled: Bool, startDate: Date) {
        guard healthKitEnabled,
              let hk = healthKitService,
              hk.isAuthorized else { return }

        healthKitTask = Task { [weak self] in
            do {
                try await hk.beginWorkout(startDate: startDate)
            } catch {
                Self.logger.error("Failed to start HealthKit workout: \(error.localizedDescription, privacy: .public)")
                self?.healthKitTask = nil
            }
        }
    }

    /// Forward a track point and distance/altitude data to HealthKit.
    func forwardPoint(
        _ point: TrackPoint,
        previousPoint: TrackPoint,
        distance: Double,
        isSkiing: Bool
    ) {
        guard let hk = healthKitService, hk.isRecording else { return }

        let altDelta = point.altitude - previousPoint.altitude
        if altDelta > 0 {
            totalVerticalAscent += altDelta
        } else if altDelta < 0 {
            totalVerticalDescent += abs(altDelta)
        }

        guard forwardTaskCount < Self.maxForwardTasks else { return }
        forwardTaskCount += 1
        Task { [weak self] in
            defer { self?.forwardTaskCount -= 1 }
            await hk.addRoutePoints([point])
            if isSkiing {
                await hk.addDistanceSample(
                    meters: distance,
                    start: previousPoint.timestamp,
                    end: point.timestamp
                )
            }
        }
    }

    /// Finalize the HealthKit workout. Returns the workout UUID if successful.
    func finalizeWorkout() async -> UUID? {
        guard let hk = healthKitService, hk.isRecording else { return nil }
        do {
            let workoutId = try await hk.finishWorkout(
                endDate: Date(),
                totalVerticalAscent: totalVerticalAscent,
                totalVerticalDescent: totalVerticalDescent
            )
            pendingWorkoutId = workoutId
            return workoutId
        } catch {
            Self.logger.error("Failed to finalize HealthKit workout: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cancel any in-progress HealthKit task.
    func cancel() {
        healthKitTask?.cancel()
        healthKitTask = nil
    }

    /// Reset state for a new session.
    func reset() {
        cancel()
        totalVerticalAscent = 0
        totalVerticalDescent = 0
        pendingWorkoutId = nil
    }
}
