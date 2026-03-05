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

    // MARK: - Private

    private var liveUpdateTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

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

        startObservingTrackingState()
    }

    private static let maxPendingTrackPoints = 10_000

    // MARK: - Public API

    /// Removes all pending Watch track points (call after merging into a saved session).
    func clearPendingWatchTrackPoints() {
        pendingWatchTrackPoints = []
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
            trackingService.pauseTracking()

        case .requestResume:
            trackingService.resumeTracking()

        case .requestStop:
            trackingService.stopTracking()

        case .requestStatus:
            sendCurrentStateToWatch()

        case .watchWorkoutStarted(let sessionId):
            Self.logger.info("Watch started independent workout: \(sessionId)")

        case .watchWorkoutEnded:
            Self.logger.info("Watch ended independent workout — \(self.pendingWatchTrackPoints.count) points buffered")

        case .watchTrackPoints(let points):
            pendingWatchTrackPoints.append(contentsOf: points)
            if pendingWatchTrackPoints.count > Self.maxPendingTrackPoints {
                let overflow = pendingWatchTrackPoints.count - Self.maxPendingTrackPoints
                pendingWatchTrackPoints.removeFirst(overflow)
                Self.logger.warning("Pending Watch track points exceeded \(Self.maxPendingTrackPoints), dropped \(overflow) oldest points")
            }
            Self.logger.debug("Received \(points.count) track points from Watch (total: \(self.pendingWatchTrackPoints.count))")

        default:
            Self.logger.warning("Unexpected Watch→Phone message: \(String(describing: message))")
        }
    }

    // MARK: - State observation

    private func startObservingTrackingState() {
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                // Capture current state to detect changes
                let currentState = self.trackingService.state
                self.reactToStateChange(currentState)

                // Wait until the next observation cycle
                await Task.yield()

                // withObservationTracking to suspend until state changes
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.trackingService.state
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func reactToStateChange(_ state: TrackingState) {
        sendCurrentStateToWatch()

        switch state {
        case .tracking:
            startLiveUpdates()
        case .paused, .idle:
            stopLiveUpdates()
            connectivityService.updateApplicationContext(state: state, liveData: nil)
        }
    }

    private func sendCurrentStateToWatch() {
        let state = trackingService.state
        switch state {
        case .tracking:
            guard let sessionId = trackingService.activeSessionId else { return }
            connectivityService.send(.trackingStarted(sessionId: sessionId))
        case .paused:
            connectivityService.send(.trackingPaused)
        case .idle:
            connectivityService.send(.trackingStopped)
        }
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
            elapsedTime: trackingService.elapsedTime,
            batteryLevel: batteryService.batteryLevel
        )
    }
}
