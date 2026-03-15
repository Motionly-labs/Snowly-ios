//
//  WatchBridgeService.swift
//  Snowly
//
//  Bridges SessionTrackingService ↔ PhoneConnectivityService.
//  Observes tracking state changes, pushes 1 Hz live updates to the Watch,
//  and routes incoming Watch control commands to the tracking service.
//

import Foundation
import Observation
import os

struct ImportedWatchWorkout: Sendable, Equatable {
    let summary: WatchMessage.IndependentWorkoutSummary
    let trackPoints: [TrackPoint]
}

@Observable
@MainActor
final class WatchBridgeService {

    // MARK: - Dependencies

    private let connectivityService: PhoneConnectivityService
    private let trackingService: SessionTrackingService
    private let batteryService: BatteryMonitorService

    // MARK: - Published state

    /// Track points forwarded from the Watch during an independent Watch workout.
    /// Cleared once merged into a saved session.
    private(set) var pendingWatchTrackPoints: [TrackPoint] = []
    private(set) var completedIndependentWorkout: ImportedWatchWorkout?
    private(set) var currentHeartRate: Double = 0
    private(set) var averageHeartRate: Double = 0
    private(set) var heartRateSamples: [HeartRateSample] = []

    // MARK: - Watch live session state (independent mode real-time processing)

    private struct WatchLiveSessionState: Sendable {
        var kalmanFilter = GPSKalmanFilter()
        var lastFilteredPoint: FilteredTrackPoint?
        var recentPoints: [FilteredTrackPoint] = []
        var currentActivity: DetectedActivity = .idle
        var candidateActivity: DetectedActivity?
        var candidateActivityStart: Date?
        var runCount: Int = 0
        var totalDistance: Double = 0
        var totalVertical: Double = 0
        var maxSpeed: Double = 0
        var currentSpeed: Double = 0
        let startDate: Date
    }

    // MARK: - Private

    private var liveUpdateTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var pendingIndependentWorkoutSummary: WatchMessage.IndependentWorkoutSummary?
    private var pendingIndependentWorkoutDidEnd = false
    private var lastSentTrackingState: TrackingState?
    private var lastObservedTrackingState: TrackingState?
    private var lastSentCompletedRun: WatchMessage.LastRunData?
    private var watchLiveState: WatchLiveSessionState?

    private static let logger = Logger(subsystem: "com.Snowly", category: "WatchBridge")

    // MARK: - Init

    init(
        connectivityService: PhoneConnectivityService,
        trackingService: SessionTrackingService,
        batteryService: BatteryMonitorService
    ) {
        self.connectivityService = connectivityService
        self.trackingService = trackingService
        self.batteryService = batteryService

        connectivityService.registerMessageHandler { [weak self] message in
            self?.handleWatchMessage(message)
        }
        connectivityService.registerConnectivityStateHandler { [weak self] state in
            self?.handleConnectivityStateChange(state)
        }

        startObservingTrackingState()
    }

    private static let maxPendingTrackPoints = 100_000

    // MARK: - Public API

    /// Removes all pending Watch track points (call after merging into a saved session).
    func clearPendingWatchTrackPoints() {
        pendingWatchTrackPoints = []
    }

    func consumeCompletedIndependentWorkout() {
        completedIndependentWorkout = nil
    }

    /// Cancel all observation and live update tasks.
    func shutdown() {
        observationTask?.cancel()
        observationTask = nil
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
    }

    // MARK: - Watch message routing

    private func handleWatchMessage(_ message: WatchMessage) {
        switch message {
        case .requestStart:
            trackingService.startTracking()

        case .requestPause:
            Task { [weak self] in
                guard let self else { return }
                await self.trackingService.pauseTracking()
            }

        case .requestResume:
            Task { [weak self] in
                guard let self else { return }
                await self.trackingService.resumeTracking()
            }

        case .requestStop:
            Task { [weak self] in
                guard let self else { return }
                await self.trackingService.stopTracking()
            }

        case .requestStatus:
            sendCurrentStateToWatch(forceAbsoluteState: true)

        case .watchWorkoutStarted(let sessionId):
            prepareForIncomingWatchWorkout(sessionId: sessionId)
            watchLiveState = WatchLiveSessionState(startDate: .now)
            Self.logger.info("Watch started independent workout: \(sessionId)")

        case .watchWorkoutSummary(let summary):
            pendingIndependentWorkoutSummary = summary
            completePendingIndependentWorkoutIfPossible()

        case .watchWorkoutEnded:
            watchLiveState = nil
            Self.logger.info("Watch ended independent workout — \(self.pendingWatchTrackPoints.count) points buffered")
            pendingIndependentWorkoutDidEnd = true
            completePendingIndependentWorkoutIfPossible()

        case .watchTrackPoints(let points):
            pendingWatchTrackPoints.append(contentsOf: points)
            if pendingWatchTrackPoints.count > Self.maxPendingTrackPoints {
                let overflow = pendingWatchTrackPoints.count - Self.maxPendingTrackPoints
                pendingWatchTrackPoints.removeFirst(overflow)
                Self.logger.warning("Pending Watch track points exceeded \(Self.maxPendingTrackPoints), dropped \(overflow) oldest points")
            }
            Self.logger.debug("Received \(points.count) track points from Watch (total: \(self.pendingWatchTrackPoints.count))")
            processWatchPointsLive(points)
            completePendingIndependentWorkoutIfPossible()

        case .liveVitals(let vitals):
            currentHeartRate = vitals.currentHeartRate
            averageHeartRate = vitals.averageHeartRate
            if vitals.currentHeartRate > 0 {
                let sample = HeartRateSample(time: .now, bpm: vitals.currentHeartRate)
                let updated = heartRateSamples + [sample]
                heartRateSamples = updated.count > SharedConstants.heartRateCurveMaxPoints
                    ? Array(updated.suffix(SharedConstants.heartRateCurveMaxPoints))
                    : updated
            }

        default:
            Self.logger.warning("Unexpected Watch→Phone message: \(String(describing: message))")
        }
    }

    /// Pure computation — no actor isolation required. Safe to call from any context.
    private nonisolated static func applyPoints(
        _ points: [TrackPoint],
        to state: WatchLiveSessionState
    ) -> WatchLiveSessionState {
        var updated = state
        for point in points {
            let filtered = updated.kalmanFilter.update(point: point)
            updated.currentSpeed = filtered.estimatedSpeed

            // Detect activity (current point must NOT be in recentPoints yet)
            let decision = RunDetectionService.analyze(
                point: filtered,
                recentPoints: updated.recentPoints,
                previousActivity: updated.currentActivity
            )
            let rawActivity = decision.activity

            updated.recentPoints.append(filtered)
            RecentTrackWindow.trimFilteredPoints(&updated.recentPoints, relativeTo: filtered.timestamp)

            // Apply dwell-time hysteresis
            let dwellResult = SessionTrackingService.applyDwellTime(
                rawActivity: rawActivity,
                currentActivity: updated.currentActivity,
                candidateActivity: updated.candidateActivity,
                candidateStartTime: updated.candidateActivityStart,
                timestamp: filtered.timestamp,
                accelerated: decision.shouldAccelerateDwell
            )
            let previousActivity = updated.currentActivity
            updated.currentActivity = dwellResult.activity
            updated.candidateActivity = dwellResult.candidate
            updated.candidateActivityStart = dwellResult.candidateStart

            // Accumulate session metrics against rawActivity (pre-dwell)
            if let prev = updated.lastFilteredPoint {
                let distance = prev.distance(to: filtered)
                if case .skiing = rawActivity {
                    updated.totalDistance += distance
                    let verticalDrop = prev.altitude - filtered.altitude
                    if verticalDrop > 0 {
                        updated.totalVertical += verticalDrop
                    }
                }
            }
            if case .skiing = rawActivity {
                updated.maxSpeed = max(updated.maxSpeed, filtered.estimatedSpeed)
            }

            // Count run transitions (idle/lift/walk → skiing)
            if previousActivity != .skiing && updated.currentActivity == .skiing {
                updated.runCount += 1
            }

            updated.lastFilteredPoint = filtered
        }
        return updated
    }

    private func processWatchPointsLive(_ points: [TrackPoint]) {
        guard let current = watchLiveState else { return }
        let updated = Self.applyPoints(points, to: current)
        watchLiveState = updated

        let liveData = WatchMessage.LiveTrackingData(
            currentSpeed: updated.currentSpeed,
            maxSpeed: updated.maxSpeed,
            totalDistance: updated.totalDistance,
            totalVertical: updated.totalVertical,
            runCount: updated.runCount,
            elapsedTime: Date.now.timeIntervalSince(updated.startDate),
            batteryLevel: batteryService.batteryLevel
        )
        connectivityService.send(.liveUpdate(liveData))
    }

    private func prepareForIncomingWatchWorkout(sessionId: UUID) {
        if pendingIndependentWorkoutSummary?.sessionId != sessionId {
            pendingWatchTrackPoints = []
            pendingIndependentWorkoutSummary = nil
            pendingIndependentWorkoutDidEnd = false
        }
    }

    private func completePendingIndependentWorkoutIfPossible() {
        guard pendingIndependentWorkoutDidEnd,
              let summary = pendingIndependentWorkoutSummary,
              pendingWatchTrackPoints.count >= summary.trackPointCount else { return }

        let sortedPoints = pendingWatchTrackPoints.sorted { $0.timestamp < $1.timestamp }
        completedIndependentWorkout = ImportedWatchWorkout(
            summary: summary,
            trackPoints: sortedPoints
        )
        pendingWatchTrackPoints = []
        pendingIndependentWorkoutSummary = nil
        pendingIndependentWorkoutDidEnd = false
    }

    // MARK: - State observation

    private func startObservingTrackingState() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let currentState = self.trackingService.state
                let completedRuns = self.trackingService.completedRuns
                self.reactToObservedTrackingSnapshot(
                    state: currentState,
                    completedRuns: completedRuns
                )

                await Task.yield()

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.trackingService.state
                        _ = self.trackingService.completedRuns.count
                        _ = self.trackingService.completedRuns.last?.endDate
                        _ = self.trackingService.completedRuns.last?.maxSpeed
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func reactToObservedTrackingSnapshot(
        state: TrackingState,
        completedRuns: [CompletedRunData]
    ) {
        syncLastCompletedRunToWatch(
            for: state,
            completedRuns: completedRuns
        )

        guard lastObservedTrackingState != state else { return }
        lastObservedTrackingState = state
        sendCurrentStateToWatch(forceAbsoluteState: false)

        switch state {
        case .tracking:
            startLiveUpdates()
        case .paused:
            stopLiveUpdates()
            connectivityService.updateApplicationContext(
                state: state,
                liveData: buildLiveData()
            )
        case .idle:
            stopLiveUpdates()
            connectivityService.updateApplicationContext(state: state, liveData: nil)
            currentHeartRate = 0
            averageHeartRate = 0
            heartRateSamples = []
        }
    }

    private func handleConnectivityStateChange(_ state: WatchConnectivityState) {
        guard state.canCommunicate else { return }
        sendCurrentStateToWatch(forceAbsoluteState: true)
        if trackingService.state == .tracking {
            startLiveUpdates()
        }
    }

    private func syncLastCompletedRunToWatch(
        for state: TrackingState,
        completedRuns: [CompletedRunData]
    ) {
        let currentSummary = state == .idle
            ? nil
            : latestSkiingRunSummary(from: completedRuns)

        guard currentSummary != lastSentCompletedRun else { return }
        lastSentCompletedRun = currentSummary
        connectivityService.updateLastCompletedRun(currentSummary)
    }

    private func sendCurrentStateToWatch(forceAbsoluteState: Bool) {
        let state = trackingService.state
        switch state {
        case .tracking:
            guard let sessionId = trackingService.activeSessionId else { return }
            if !forceAbsoluteState, lastSentTrackingState == .paused {
                connectivityService.send(.trackingResumed)
            } else {
                connectivityService.send(.trackingStarted(sessionId: sessionId))
            }
        case .paused:
            connectivityService.send(.trackingPaused)
        case .idle:
            connectivityService.send(.trackingStopped)
        }
        lastSentTrackingState = state
    }

    // MARK: - Live updates (1 Hz)

    private func startLiveUpdates() {
        guard liveUpdateTask == nil else { return }
        liveUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                guard self.trackingService.state == .tracking else { break }

                let liveData = self.buildLiveData()
                self.connectivityService.send(.liveUpdate(liveData))
                self.connectivityService.updateApplicationContext(
                    state: self.trackingService.state,
                    liveData: liveData
                )
            }
        }
    }

    private func stopLiveUpdates() {
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
    }

    // MARK: - Live data builder

    private func buildLiveData() -> WatchMessage.LiveTrackingData {
        WatchMessage.LiveTrackingData(
            currentSpeed: trackingService.currentSpeed,
            maxSpeed: trackingService.maxSpeed,
            totalDistance: trackingService.totalDistance,
            totalVertical: trackingService.totalVertical,
            runCount: trackingService.runCount,
            elapsedTime: trackingService.computeElapsedTime(),
            batteryLevel: batteryService.batteryLevel
        )
    }

    private func latestSkiingRunSummary(
        from completedRuns: [CompletedRunData]
    ) -> WatchMessage.LastRunData? {
        let skiingRuns = completedRuns.filter { $0.activityType == .skiing }
        guard let lastRun = skiingRuns.last else { return nil }

        return WatchMessage.LastRunData(
            runNumber: skiingRuns.count,
            startDate: lastRun.startDate,
            endDate: lastRun.endDate,
            distance: lastRun.distance,
            verticalDrop: lastRun.verticalDrop,
            maxSpeed: lastRun.maxSpeed,
            averageSpeed: lastRun.averageSpeed
        )
    }
}
