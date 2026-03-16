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
    private var activeFlushTask: Task<Void, Never>?
    private var totalVerticalAscent: Double = 0
    private var totalVerticalDescent: Double = 0
    private var pendingRoutePoints: [FilteredTrackPoint] = []
    private var pendingDistanceSamples: [(meters: Double, start: Date, end: Date)] = []
    private var flushTask: Task<Void, Never>?
    private var workoutRequested = false
    private var workoutStartToken = UUID()
    private let flushInterval: TimeInterval
    private static let logger = Logger(subsystem: "com.Snowly", category: "HealthKitCoordinator")
    private static let maxPendingRoutePoints = 1_800
    private static let maxPendingDistanceSamples = 1_800

    init(
        healthKitService: (any HealthKitProviding)?,
        flushInterval: TimeInterval = 3
    ) {
        self.healthKitService = healthKitService
        self.flushInterval = flushInterval
    }

    /// Start a HealthKit workout session if enabled and authorized.
    func startWorkout(healthKitEnabled: Bool, startDate: Date) {
        guard healthKitEnabled,
              let hk = healthKitService,
              hk.isAuthorized else {
            workoutRequested = false
            return
        }

        let startToken = UUID()
        workoutRequested = true
        workoutStartToken = startToken

        healthKitTask = Task { [weak self, startToken] in
            do {
                try await hk.beginWorkout(startDate: startDate)
                await self?.handleWorkoutStart(token: startToken, error: nil)
            } catch {
                await self?.handleWorkoutStart(token: startToken, error: error)
            }
        }
    }

    /// Buffer a track point for batched HealthKit submission.
    func forwardPoint(
        _ point: FilteredTrackPoint,
        previousPoint: FilteredTrackPoint,
        distance: Double,
        isSkiing: Bool
    ) {
        guard workoutRequested, healthKitService != nil else { return }

        let altDelta = point.altitude - previousPoint.altitude
        if altDelta > 0 {
            totalVerticalAscent += altDelta
        } else if altDelta < 0 {
            totalVerticalDescent += abs(altDelta)
        }

        pendingRoutePoints.append(point)
        trimPendingRoutePointsIfNeeded()
        if isSkiing && distance > 0 {
            pendingDistanceSamples.append((
                meters: distance,
                start: previousPoint.timestamp,
                end: point.timestamp
            ))
            trimPendingDistanceSamplesIfNeeded()
        }

        // Schedule a flush if not already pending
        if flushTask == nil {
            let interval = flushInterval
            flushTask = Task { [weak self, interval] in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.flushPendingHealthKitData()
            }
        }
    }

    /// Flushes buffered route points and distance samples to HealthKit in a single Task.
    private func flushPendingHealthKitData() async {
        flushTask = nil

        guard activeFlushTask == nil else { return }
        guard let hk = healthKitService, workoutRequested else { return }
        guard hk.isRecording else {
            scheduleFlushIfNeeded()
            return
        }
        guard !pendingRoutePoints.isEmpty || !pendingDistanceSamples.isEmpty else { return }

        let points = pendingRoutePoints
        let samples = pendingDistanceSamples
        pendingRoutePoints.removeAll(keepingCapacity: true)
        pendingDistanceSamples.removeAll(keepingCapacity: true)

        activeFlushTask = Task { [weak self] in
            await hk.addRoutePoints(points)
            for sample in samples {
                await hk.addDistanceSample(
                    meters: sample.meters,
                    start: sample.start,
                    end: sample.end
                )
            }

            guard !Task.isCancelled else { return }
            await self?.flushDidComplete()
        }
    }

    /// Finalize the HealthKit workout. Returns the workout UUID if successful.
    func finalizeWorkout() async -> UUID? {
        guard let hk = healthKitService, workoutRequested else { return nil }
        await healthKitTask?.value
        guard hk.isRecording else { return nil }

        await drainPendingHealthKitData()
        do {
            let workoutId = try await hk.finishWorkout(
                endDate: Date(),
                totalVerticalAscent: totalVerticalAscent,
                totalVerticalDescent: totalVerticalDescent
            )
            pendingWorkoutId = workoutId
            workoutRequested = false
            return workoutId
        } catch {
            Self.logger.error("Failed to finalize HealthKit workout: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cancel any in-progress HealthKit task and discard the workout builder.
    func cancel() {
        let shouldDiscard = workoutRequested
        workoutRequested = false
        workoutStartToken = UUID()
        healthKitTask?.cancel()
        healthKitTask = nil
        activeFlushTask?.cancel()
        activeFlushTask = nil
        flushTask?.cancel()
        flushTask = nil

        if shouldDiscard, let hk = healthKitService {
            Task { await hk.cancelWorkout() }
        }
    }

    /// Reset state for a new session.
    func reset() {
        cancel()
        totalVerticalAscent = 0
        totalVerticalDescent = 0
        pendingWorkoutId = nil
        pendingRoutePoints.removeAll()
        pendingDistanceSamples.removeAll()
    }

    private func handleWorkoutStart(token: UUID, error: Error?) async {
        guard token == workoutStartToken else { return }
        healthKitTask = nil

        if let error {
            Self.logger.error("Failed to start HealthKit workout: \(error.localizedDescription, privacy: .public)")
            workoutRequested = false
            flushTask?.cancel()
            flushTask = nil
            pendingRoutePoints.removeAll(keepingCapacity: true)
            pendingDistanceSamples.removeAll(keepingCapacity: true)
            return
        }

        await flushPendingHealthKitData()
    }

    private func flushDidComplete() async {
        activeFlushTask = nil
        await flushPendingHealthKitData()
    }

    private func drainPendingHealthKitData() async {
        flushTask?.cancel()
        flushTask = nil

        while true {
            await flushPendingHealthKitData()
            guard let activeFlushTask else { return }
            await activeFlushTask.value
        }
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil,
              !pendingRoutePoints.isEmpty || !pendingDistanceSamples.isEmpty else { return }

        let interval = flushInterval
        flushTask = Task { [weak self, interval] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.flushPendingHealthKitData()
        }
    }

    private func trimPendingRoutePointsIfNeeded() {
        guard pendingRoutePoints.count > Self.maxPendingRoutePoints else { return }
        pendingRoutePoints = Array(pendingRoutePoints.suffix(Self.maxPendingRoutePoints))
        Self.logger.debug("Trimmed pending HealthKit route buffer to \(Self.maxPendingRoutePoints, privacy: .public) points")
    }

    private func trimPendingDistanceSamplesIfNeeded() {
        guard pendingDistanceSamples.count > Self.maxPendingDistanceSamples else { return }
        pendingDistanceSamples = Array(pendingDistanceSamples.suffix(Self.maxPendingDistanceSamples))
        Self.logger.debug("Trimmed pending HealthKit distance buffer to \(Self.maxPendingDistanceSamples, privacy: .public) samples")
    }
}
