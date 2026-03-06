//
//  SessionTrackingService.swift
//  Snowly
//
//  Orchestrates a ski tracking session. Created at app level,
//  injected via @Environment. Coordinates location, motion,
//  battery, segment finalization, and HealthKit.
//

import Foundation
import SwiftData
import Observation
import CoreLocation

/// Tracking session state machine.
enum TrackingState: Sendable, Equatable {
    case idle
    case tracking
    case paused
}

@Observable
@MainActor
final class SessionTrackingService {
    // MARK: - Dependencies (injected)
    private let locationService: any LocationProviding
    private let motionService: any MotionDetecting
    private let batteryService: any BatteryMonitoring
    private let segmentService: SegmentFinalizationService
    private let healthKitCoordinator: HealthKitCoordinator

    // MARK: - Published state
    private(set) var state: TrackingState = .idle
    private(set) var currentSpeed: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var totalDistance: Double = 0
    private(set) var totalVertical: Double = 0
    private(set) var currentActivity: DetectedActivity = .idle
    private(set) var elapsedTime: TimeInterval = 0

    private(set) var activeSessionId: UUID?
    private(set) var startDate: Date?

    var runCount: Int { segmentService.runCount }
    var completedRuns: [CompletedRunData] { segmentService.completedRuns }
    var pendingHealthKitWorkoutId: UUID? { healthKitCoordinator.pendingWorkoutId }

    // MARK: - Internal state
    private var trackingTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var recentPoints = CircularBuffer<TrackPoint>(capacity: SharedConstants.recentPointsBufferSize)
    private var previousPoint: TrackPoint?
    private var pauseStartTime: Date?
    private var totalPausedTime: TimeInterval = 0
    private var candidateActivity: DetectedActivity?
    private var candidateStartTime: Date?
    private static let recoveryStateMaxAge: TimeInterval = 12 * 3600

    init(
        locationService: any LocationProviding,
        motionService: any MotionDetecting,
        batteryService: any BatteryMonitoring,
        healthKitService: HealthKitService? = nil,
        segmentService: SegmentFinalizationService? = nil,
        healthKitCoordinator: HealthKitCoordinator? = nil
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.batteryService = batteryService
        self.segmentService = segmentService ?? SegmentFinalizationService()
        self.healthKitCoordinator = healthKitCoordinator ?? HealthKitCoordinator(healthKitService: healthKitService)

        // Check for crash recovery
        if let persisted = TrackingStatePersistence.load(), persisted.isActive {
            let recoveryAge = Date().timeIntervalSince(persisted.lastUpdateDate)
            if recoveryAge <= Self.recoveryStateMaxAge {
                restoreState(from: persisted)
            } else {
                TrackingStatePersistence.clear()
            }
        }
    }

    // MARK: - Public API

    func startTracking(healthKitEnabled: Bool = false) {
        guard state == .idle else { return }

        let sessionId = UUID()
        activeSessionId = sessionId
        startDate = Date()

        resetStats()
        state = .tracking
        motionService.startMonitoring()
        batteryService.startMonitoring()

        healthKitCoordinator.startWorkout(
            healthKitEnabled: healthKitEnabled,
            startDate: startDate ?? Date()
        )

        startLiveTrackingPipeline()
        startTimer()
        startPeriodicPersistence()
    }

    func pauseTracking() {
        guard state == .tracking else { return }
        segmentService.finalizeCurrentSegment()
        state = .paused
        pauseStartTime = Date()
        currentSpeed = 0
        currentActivity = .idle
        previousPoint = nil
        recentPoints.removeAll()
        candidateActivity = nil
        candidateStartTime = nil
    }

    func resumeTracking() {
        guard state == .paused else { return }

        // Crash-recovery path: paused state restored from disk has no active pipeline.
        if trackingTask == nil {
            motionService.startMonitoring()
            batteryService.startMonitoring()
            startLiveTrackingPipeline()
            if timerTask == nil {
                startTimer()
            }
            if persistenceTask == nil {
                startPeriodicPersistence()
            }
        }

        if let pauseStart = pauseStartTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        state = .tracking
    }

    func stopTracking() {
        guard state != .idle else { return }

        segmentService.finalizeCurrentSegment()

        trackingTask?.cancel()
        timerTask?.cancel()
        persistenceTask?.cancel()
        trackingTask = nil
        timerTask = nil
        persistenceTask = nil
        healthKitCoordinator.cancel()

        locationService.stopTracking()
        motionService.stopMonitoring()
        batteryService.stopMonitoring()
        TrackingStatePersistence.clear()

        state = .idle
    }

    /// Finalizes the HealthKit workout asynchronously.
    /// Call after stopTracking() and before saveSession().
    func finalizeHealthKitWorkout() async {
        _ = await healthKitCoordinator.finalizeWorkout()
    }

    /// Persists an immediate crash-recovery snapshot while a session is active.
    /// Useful before app background transitions.
    func persistSnapshotNowIfNeeded() {
        guard state != .idle else { return }
        persistCurrentStateSnapshot(lastUpdateDate: Date())
    }

    /// Saves the session to SwiftData. Call after stopTracking().
    func saveSession(to context: ModelContext, resort: Resort? = nil) {
        guard let sessionId = activeSessionId,
              let start = startDate else { return }

        let session = SkiSession(
            id: sessionId,
            startDate: start,
            endDate: Date(),
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount
        )

        if let workoutId = pendingHealthKitWorkoutId {
            session.healthKitWorkoutId = workoutId
        }

        session.resort = resort

        context.insert(session)

        for runData in completedRuns {
            let run = SkiRun(
                startDate: runData.startDate,
                endDate: runData.endDate,
                distance: runData.distance,
                verticalDrop: runData.verticalDrop,
                maxSpeed: runData.maxSpeed,
                averageSpeed: runData.averageSpeed,
                activityType: runData.activityType,
                trackData: runData.trackData
            )
            run.session = session
            context.insert(run)
        }

        resetStats()
        activeSessionId = nil
        startDate = nil
    }

    // MARK: - Private

    private func startLiveTrackingPipeline() {
        trackingTask?.cancel()
        let stream = locationService.startTracking()
        trackingTask = Task { [weak self] in
            for await point in stream {
                guard let self, !Task.isCancelled else { break }
                self.processTrackPoint(point)
            }
        }
    }

    private func processTrackPoint(_ point: TrackPoint) {
        guard state == .tracking else { return }

        currentSpeed = point.speed

        // Update recent points buffer (O(1) circular buffer)
        recentPoints.append(point)

        // Detect activity (raw per-point detection)
        let rawActivity = RunDetectionService.detect(
            point: point,
            recentPoints: recentPoints.elements,
            motion: motionService.currentMotion
        )

        // Apply dwell time hysteresis filter
        let dwellResult = SessionTrackingService.applyDwellTime(
            rawActivity: rawActivity,
            currentActivity: currentActivity,
            candidateActivity: candidateActivity,
            candidateStartTime: candidateStartTime,
            timestamp: point.timestamp
        )
        currentActivity = dwellResult.activity
        candidateActivity = dwellResult.candidate
        candidateStartTime = dwellResult.candidateStart
        let activity = dwellResult.activity

        // Track distance from previous point
        if let prev = previousPoint {
            let dist = prev.distance(to: point)
            if activity == .skiing {
                totalDistance += dist
                let vertDrop = prev.altitude - point.altitude
                if vertDrop > 0 {
                    totalVertical += vertDrop
                }
            }

            healthKitCoordinator.forwardPoint(
                point,
                previousPoint: prev,
                distance: dist,
                isSkiing: activity == .skiing
            )
        }

        // Track max speed
        if point.speed > maxSpeed {
            maxSpeed = point.speed
        }

        segmentService.processPoint(point, activity: activity)

        previousPoint = point
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { break }
                guard let start = self.startDate else { continue }
                let pausedNow = self.pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
                self.elapsedTime = Date().timeIntervalSince(start) - self.totalPausedTime - pausedNow
            }
        }
    }

    private func startPeriodicPersistence() {
        persistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SharedConstants.statePersistenceInterval))
                guard let self else { continue }
                self.persistCurrentStateSnapshot(lastUpdateDate: Date())
            }
        }
    }

    private func persistCurrentStateSnapshot(lastUpdateDate: Date) {
        guard let sessionId = activeSessionId,
              let start = startDate else { return }

        let state = PersistedTrackingState(
            sessionId: sessionId,
            startDate: start,
            lastUpdateDate: lastUpdateDate,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount,
            isActive: true,
            elapsedTime: elapsedTime,
            completedRuns: completedRuns.map {
                PersistedCompletedRun(
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    distance: $0.distance,
                    verticalDrop: $0.verticalDrop,
                    maxSpeed: $0.maxSpeed,
                    averageSpeed: $0.averageSpeed,
                    activityType: $0.activityType
                )
            }
        )
        TrackingStatePersistence.save(state)
    }

    private func restoreState(from persisted: PersistedTrackingState) {
        activeSessionId = persisted.sessionId
        startDate = persisted.startDate
        totalDistance = persisted.totalDistance
        totalVertical = persisted.totalVertical
        maxSpeed = persisted.maxSpeed
        elapsedTime = persisted.elapsedTime ?? max(0, Date().timeIntervalSince(persisted.startDate))
        totalPausedTime = max(0, Date().timeIntervalSince(persisted.startDate) - elapsedTime)
        pauseStartTime = Date()

        let restoredRuns = (persisted.completedRuns ?? []).map {
            CompletedRunData(
                startDate: $0.startDate,
                endDate: $0.endDate,
                distance: $0.distance,
                verticalDrop: $0.verticalDrop,
                maxSpeed: $0.maxSpeed,
                averageSpeed: $0.averageSpeed,
                activityType: $0.activityType,
                trackData: nil
            )
        }
        segmentService.restoreCompletedRuns(restoredRuns, runCount: persisted.runCount)

        currentSpeed = 0
        currentActivity = .idle
        recentPoints.removeAll()
        previousPoint = nil
        candidateActivity = nil
        candidateStartTime = nil
        state = .paused
        // Don't auto-resume tracking after crash — user must explicitly resume or stop.
    }

    /// Returns the required dwell time for a state transition.
    static func dwellTimeForTransition(
        from current: DetectedActivity,
        to target: DetectedActivity
    ) -> TimeInterval {
        switch (current, target) {
        case (.skiing, .chairlift):
            return SharedConstants.dwellTimeSkiingToChairlift
        case (.chairlift, .skiing):
            return SharedConstants.dwellTimeChairliftToSkiing
        case (.idle, .skiing):
            return SharedConstants.dwellTimeIdleToSkiing
        case (.idle, .chairlift):
            return SharedConstants.dwellTimeIdleToChairlift
        default:
            return 0
        }
    }

    /// Pure function: applies dwell time hysteresis to raw activity detection.
    /// State only switches after the candidate activity persists for the required dwell time.
    static func applyDwellTime(
        rawActivity: DetectedActivity,
        currentActivity: DetectedActivity,
        candidateActivity: DetectedActivity?,
        candidateStartTime: Date?,
        timestamp: Date
    ) -> (activity: DetectedActivity, candidate: DetectedActivity?, candidateStart: Date?) {
        // Raw matches current → no transition in progress, reset candidate
        if rawActivity == currentActivity {
            return (currentActivity, nil, nil)
        }

        // Raw matches existing candidate → check if dwell time exceeded
        if rawActivity == candidateActivity, let candidateStart = candidateStartTime {
            let required = dwellTimeForTransition(from: currentActivity, to: rawActivity)
            if timestamp.timeIntervalSince(candidateStart) >= required {
                return (rawActivity, nil, nil)
            }
            // Not yet — keep waiting
            return (currentActivity, candidateActivity, candidateStartTime)
        }

        // New candidate — start dwell timer
        return (currentActivity, rawActivity, timestamp)
    }

    private func resetStats() {
        currentSpeed = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        elapsedTime = 0
        currentActivity = .idle
        recentPoints.removeAll()
        previousPoint = nil
        totalPausedTime = 0
        pauseStartTime = nil
        candidateActivity = nil
        candidateStartTime = nil
        segmentService.reset()
        healthKitCoordinator.reset()
    }
}
