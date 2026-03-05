//
//  WatchWorkoutManager.swift
//  SnowlyWatch
//
//  Manages workout sessions in companion and independent modes.
//

import Foundation
import HealthKit

// MARK: - State Types

enum WatchTrackingState: Sendable, Equatable {
    case idle
    case active(mode: WatchTrackingMode)
    case paused
    case summary
}

enum WatchTrackingMode: Sendable, Equatable {
    case companion
    case independent
}

// MARK: - WatchWorkoutManager

@Observable
@MainActor
final class WatchWorkoutManager: NSObject {

    // MARK: - Published State

    var trackingState: WatchTrackingState = .idle
    var currentSpeed: Double = 0
    var maxSpeed: Double = 0
    var totalDistance: Double = 0
    var totalVertical: Double = 0
    var runCount: Int = 0
    var elapsedTime: TimeInterval = 0

    // MARK: - Dependencies

    private var connectivityService: WatchConnectivityService?
    private var locationService: WatchLocationService?

    // MARK: - Private State

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var startDate: Date?
    private var pauseDate: Date?
    private var accumulatedPauseTime: TimeInterval = 0
    private var lastLocation: TrackPoint?
    private var recentPoints: [TrackPoint] = []
    private var bufferedPoints: [TrackPoint] = []
    private var lastRunActivity: DetectedActivity = .idle
    private var lastActivityChangeTime: Date = .now
    private var isInRun = false

    // MARK: - Setup

    func configure(
        connectivity: WatchConnectivityService,
        location: WatchLocationService
    ) {
        connectivityService = connectivity
        locationService = location

        connectivity.onMessageReceived = { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
    }

    // MARK: - Companion Mode

    func startCompanion() {
        resetStats()
        trackingState = .active(mode: .companion)
        WatchHapticService.playStart()
    }

    // MARK: - Independent Mode

    func startIndependent() {
        resetStats()
        startDate = .now
        trackingState = .active(mode: .independent)

        startHealthKitWorkout()
        locationService?.requestAuthorization()
        locationService?.startTracking { [weak self] point in
            Task { @MainActor in
                self?.processTrackPoint(point)
            }
        }
        startTimer()
        WatchHapticService.playStart()
    }

    // MARK: - Controls

    func pause() {
        guard case .active(let mode) = trackingState else { return }

        if mode == .companion {
            connectivityService?.send(.requestPause)
        } else {
            pauseDate = .now
            timer?.invalidate()
            timer = nil
            workoutSession?.pause()
        }

        trackingState = .paused
        WatchHapticService.playPause()
    }

    func resume() {
        let wasCompanion: Bool
        if case .paused = trackingState {
            // Determine mode from context
            wasCompanion = workoutSession == nil && startDate == nil
        } else {
            return
        }

        if wasCompanion {
            connectivityService?.send(.requestResume)
            trackingState = .active(mode: .companion)
        } else {
            if let pauseStart = pauseDate {
                accumulatedPauseTime += Date.now.timeIntervalSince(pauseStart)
                pauseDate = nil
            }
            startTimer()
            workoutSession?.resume()
            trackingState = .active(mode: .independent)
        }
        WatchHapticService.playResume()
    }

    func stop() {
        let wasIndependent: Bool
        if case .active(let mode) = trackingState {
            wasIndependent = mode == .independent
        } else if case .paused = trackingState {
            wasIndependent = workoutSession != nil
        } else {
            return
        }

        if wasIndependent {
            stopIndependent()
        } else {
            connectivityService?.send(.requestStop)
        }

        trackingState = .summary
        WatchHapticService.playStop()
    }

    func dismiss() {
        trackingState = .idle
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WatchMessage) {
        switch message {
        case .trackingStarted:
            if case .idle = trackingState {
                startCompanion()
            }

        case .trackingPaused:
            if case .active(.companion) = trackingState {
                trackingState = .paused
            }

        case .trackingResumed:
            if case .paused = trackingState {
                trackingState = .active(mode: .companion)
            }

        case .trackingStopped:
            trackingState = .summary

        case .liveUpdate(let data):
            updateFromLiveData(data)

        case .newPersonalBest:
            WatchHapticService.playPersonalBest()

        default:
            break
        }
    }

    private func updateFromLiveData(_ data: WatchMessage.LiveTrackingData) {
        currentSpeed = data.currentSpeed
        maxSpeed = data.maxSpeed
        totalDistance = data.totalDistance
        totalVertical = data.totalVertical
        runCount = data.runCount
        elapsedTime = data.elapsedTime
    }

    // MARK: - Independent Tracking

    private func processTrackPoint(_ point: TrackPoint) {
        bufferedPoints.append(point)
        currentSpeed = point.speed
        maxSpeed = max(maxSpeed, point.speed)

        // Incremental distance
        if let last = lastLocation {
            let distance = haversineDistance(
                lat1: last.latitude, lon1: last.longitude,
                lat2: point.latitude, lon2: point.longitude
            )
            totalDistance += distance
        }

        // Vertical drop tracking
        if let last = lastLocation, point.altitude < last.altitude {
            totalVertical += last.altitude - point.altitude
        }

        // Run detection
        recentPoints.append(point)
        if recentPoints.count > SharedConstants.recentPointsBufferSize {
            recentPoints.removeFirst()
        }

        let activity = RunDetectionService.detect(
            point: point,
            recentPoints: Array(recentPoints.dropLast())
        )

        updateRunCount(activity: activity, at: point.timestamp)
        lastLocation = point
    }

    private func updateRunCount(activity: DetectedActivity, at time: Date) {
        if activity != lastRunActivity {
            if activity == .skiing && !isInRun {
                isInRun = true
                runCount += 1
                WatchHapticService.playNewRun()
            } else if activity == .chairlift || activity == .idle {
                if isInRun
                    && RunDetectionService.shouldEndRun(
                        lastActivityTime: lastActivityChangeTime,
                        now: time
                    ) {
                    isInRun = false
                }
            }
            lastRunActivity = activity
            lastActivityChangeTime = time
        }
    }

    // MARK: - HealthKit Workout

    private func startHealthKitWorkout() {
        let config = HKWorkoutConfiguration()
        config.activityType = .downhillSkiing
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: config
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            session.startActivity(with: .now)
            builder.beginCollection(withStart: .now) { _, error in
                if let error {
                    print("Workout builder start error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Failed to start workout session: \(error.localizedDescription)")
        }
    }

    private func stopIndependent() {
        timer?.invalidate()
        timer = nil
        locationService?.stopTracking()

        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: .now) { [weak self] _, error in
            if let error {
                print("Workout builder end error: \(error.localizedDescription)")
            }
            self?.workoutBuilder?.finishWorkout { _, error in
                if let error {
                    print("Workout finish error: \(error.localizedDescription)")
                }
            }
        }

        // Send buffered points to phone
        if !bufferedPoints.isEmpty {
            connectivityService?.send(.watchTrackPoints(bufferedPoints))
        }
        connectivityService?.send(.watchWorkoutEnded)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        guard let start = startDate else { return }
        elapsedTime = Date.now.timeIntervalSince(start) - accumulatedPauseTime
    }

    // MARK: - Helpers

    private func resetStats() {
        currentSpeed = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        runCount = 0
        elapsedTime = 0
        startDate = nil
        pauseDate = nil
        accumulatedPauseTime = 0
        lastLocation = nil
        recentPoints = []
        bufferedPoints = []
        lastRunActivity = .idle
        lastActivityChangeTime = .now
        isInRun = false
    }

    /// Haversine distance between two coordinates in meters.
    private func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadius = 6_371_000.0 // meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // State changes handled via our own trackingState
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("Workout session error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        // No-op: we track metrics via GPS
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // No-op: we track metrics via GPS
    }
}
