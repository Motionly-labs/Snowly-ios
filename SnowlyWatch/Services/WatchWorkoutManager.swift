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
    private static let trackPointBatchSize = 200
    private static let heartRatePushInterval: TimeInterval = 2

    // MARK: - Published State

    var trackingState: WatchTrackingState = .idle
    var currentSpeed: Double = 0
    var maxSpeed: Double = 0
    var totalDistance: Double = 0
    var totalVertical: Double = 0
    var runCount: Int = 0
    var elapsedTime: TimeInterval = 0
    var currentHeartRate: Double = 0
    var averageHeartRate: Double = 0

    // MARK: - Dependencies

    private var connectivityService: WatchConnectivityService?
    private var locationService: WatchLocationService?

    // MARK: - Private State

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var sessionId: UUID?
    private var startDate: Date?
    private var pauseDate: Date?
    private var accumulatedPauseTime: TimeInterval = 0
    private var lastFilteredPoint: FilteredTrackPoint?
    private var recentPoints: [FilteredTrackPoint] = []
    private var bufferedPoints: [TrackPoint] = []
    private var lastRunActivity: DetectedActivity = .idle
    private var lastActivityChangeTime: Date = .now
    private var isInRun = false
    private var lastHeartRatePushAt: Date?

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
        let currentSessionId = UUID()
        sessionId = currentSessionId
        startDate = .now
        trackingState = .active(mode: .independent)

        startHealthKitWorkout()
        connectivityService?.send(.watchWorkoutStarted(sessionId: currentSessionId))
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
        let filteredPoint = makeFilteredPoint(from: point, previous: lastFilteredPoint)
        currentSpeed = filteredPoint.estimatedSpeed
        maxSpeed = max(maxSpeed, filteredPoint.estimatedSpeed)

        // Incremental distance
        if let last = lastFilteredPoint {
            totalDistance += last.distance(to: filteredPoint)
        }

        // Vertical drop tracking
        if let last = lastFilteredPoint, filteredPoint.altitude < last.altitude {
            totalVertical += last.altitude - filteredPoint.altitude
        }

        // Run detection
        recentPoints.append(filteredPoint)
        RecentTrackWindow.trimFilteredPoints(&recentPoints, relativeTo: filteredPoint.timestamp)

        let activity = RunDetectionService.detect(
            point: filteredPoint,
            recentPoints: Array(recentPoints.dropLast()),
            previousActivity: lastRunActivity
        )

        updateRunCount(activity: activity, at: filteredPoint.timestamp)
        lastFilteredPoint = filteredPoint
    }

    private func updateRunCount(activity: DetectedActivity, at time: Date) {
        if activity != lastRunActivity {
            if activity == .skiing && !isInRun {
                isInRun = true
                runCount += 1
                WatchHapticService.playNewRun()
            } else if activity == .lift || activity == .idle || activity == .walk {
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

        let endDate = Date.now
        if let sessionId, let startDate {
            connectivityService?.send(.watchWorkoutSummary(.init(
                sessionId: sessionId,
                startDate: startDate,
                endDate: endDate,
                totalDistance: totalDistance,
                totalVertical: totalVertical,
                maxSpeed: maxSpeed,
                runCount: runCount,
                elapsedTime: elapsedTime,
                trackPointCount: bufferedPoints.count
            )))
        }

        workoutSession?.end()
        let builder = workoutBuilder
        builder?.endCollection(withEnd: .now) { _, error in
            if let error {
                print("Workout builder end error: \(error.localizedDescription)")
            }
            builder?.finishWorkout { _, error in
                if let error {
                    print("Workout finish error: \(error.localizedDescription)")
                }
            }
        }

        // Send buffered points to phone
        if !bufferedPoints.isEmpty {
            sendBufferedTrackPointsInBatches()
        }
        connectivityService?.send(.watchWorkoutEnded)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let manager = self
            Task { @MainActor in
                manager?.updateElapsedTime()
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
        currentHeartRate = 0
        averageHeartRate = 0
        sessionId = nil
        startDate = nil
        pauseDate = nil
        accumulatedPauseTime = 0
        lastFilteredPoint = nil
        recentPoints = []
        bufferedPoints = []
        lastRunActivity = .idle
        lastActivityChangeTime = .now
        isInRun = false
        lastHeartRatePushAt = nil
    }

    private func sendLiveVitalsIfNeeded(force: Bool = false) {
        guard let connectivityService else { return }
        switch trackingState {
        case .active, .paused:
            break
        case .idle, .summary:
            return
        }

        let now = Date.now
        if !force, let lastHeartRatePushAt, now.timeIntervalSince(lastHeartRatePushAt) < Self.heartRatePushInterval {
            return
        }

        lastHeartRatePushAt = now
        connectivityService.send(.liveVitals(.init(
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate
        )))
    }

    private func makeFilteredPoint(
        from point: TrackPoint,
        previous: FilteredTrackPoint?
    ) -> FilteredTrackPoint {
        let estimatedSpeed: Double
        if let previous {
            let previousRaw = TrackPoint(
                timestamp: previous.rawTimestamp,
                latitude: previous.latitude,
                longitude: previous.longitude,
                altitude: previous.altitude,
                speed: previous.estimatedSpeed,
                horizontalAccuracy: previous.horizontalAccuracy,
                verticalAccuracy: previous.verticalAccuracy,
                course: previous.course
            )
            let dt = point.timestamp.timeIntervalSince(previous.timestamp)
            estimatedSpeed = dt > 0 ? max(0, previousRaw.distance(to: point) / dt) : 0
        } else {
            estimatedSpeed = 0
        }

        return FilteredTrackPoint(
            rawTimestamp: point.timestamp,
            timestamp: point.timestamp,
            latitude: point.latitude,
            longitude: point.longitude,
            altitude: point.altitude,
            estimatedSpeed: estimatedSpeed,
            horizontalAccuracy: point.horizontalAccuracy,
            verticalAccuracy: point.verticalAccuracy,
            course: point.course
        )
    }

    private func sendBufferedTrackPointsInBatches() {
        guard let connectivityService else { return }

        var startIndex = bufferedPoints.startIndex
        while startIndex < bufferedPoints.endIndex {
            let endIndex = min(
                startIndex + Self.trackPointBatchSize,
                bufferedPoints.endIndex
            )
            let batch = Array(bufferedPoints[startIndex..<endIndex])
            connectivityService.send(.watchTrackPoints(batch))
            startIndex = endIndex
        }
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
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType)
        else {
            return
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let latest = statistics.mostRecentQuantity()?.doubleValue(for: unit)
        let average = statistics.averageQuantity()?.doubleValue(for: unit)

        Task { @MainActor [weak self] in
            if let latest {
                self?.currentHeartRate = latest
            }
            if let average {
                self?.averageHeartRate = average
            }
            self?.sendLiveVitalsIfNeeded()
        }
    }
}
