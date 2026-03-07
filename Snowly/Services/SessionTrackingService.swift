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

/// A time-stamped speed reading for the live speed curve.
struct SpeedSample: Sendable, Equatable {
    let time: Date
    let speed: Double // m/s
}

private struct TrackingPointIngestResult: Sendable {
    let previousPoint: TrackPoint?
    let distance: Double
    let activity: DetectedActivity
}

private struct CompletedRunStorage: Sendable {
    let summary: CompletedRunData
    let trackFileURL: URL?
}

private struct MaterializedCompletedRun: Sendable {
    let summary: CompletedRunData
    let trackData: Data?
}

private struct ScalarSnapshot: Sendable {
    let currentSpeed: Double
    let maxSpeed: Double
    let totalDistance: Double
    let totalVertical: Double
    let currentActivity: DetectedActivity
    let runCount: Int
    let completedRunsVersion: Int
    let speedSamplesVersion: Int
}

private struct TrackingEngineSnapshot: Sendable {
    let currentSpeed: Double
    let maxSpeed: Double
    let totalDistance: Double
    let totalVertical: Double
    let currentActivity: DetectedActivity
    let runCount: Int
    let completedRuns: [CompletedRunData]
    let speedSamples: [SpeedSample]
}

private actor TrackingEngine {
    struct Seed: Sendable {
        let totalDistance: Double
        let totalVertical: Double
        let maxSpeed: Double
        let completedRuns: [CompletedRunData]
        let runCount: Int
    }

    // MARK: - Session stats
    private var currentSpeed: Double = 0
    private var maxSpeed: Double = 0
    private var totalDistance: Double = 0
    private var totalVertical: Double = 0
    private var currentActivity: DetectedActivity = .idle

    // MARK: - Detection state
    private var recentPoints: [TrackPoint] = []
    private var previousPoint: TrackPoint?
    private var candidateActivity: DetectedActivity?
    private var candidateStartTime: Date?

    // MARK: - Completed runs
    private var completedRuns: [CompletedRunData] = []
    private var completedRunFiles: [URL?] = []
    private var runCount: Int = 0

    // MARK: - Speed curve
    private var speedSamples: [SpeedSample] = []
    private static let speedSampleWindow: TimeInterval = 600 // 10 minutes

    // MARK: - Version counters
    private var completedRunsVersion: Int = 0
    private var speedSamplesVersion: Int = 0

    // MARK: - Active segment (streamed to temp file)
    private var currentSegmentType: RunActivityType?
    private var segmentStartPoint: TrackPoint?
    private var segmentLastPoint: TrackPoint?
    private var segmentDistance: Double = 0
    private var segmentMaxSpeed: Double = 0
    private var segmentPointCount: Int = 0
    private var segmentTrackFileURL: URL?
    private var segmentTrackFileHandle: FileHandle?
    private var lastActiveTime: Date?

    private struct NDJSONTrackPoint: Encodable {
        let timestamp: Double
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let speed: Double
        let accuracy: Double
        let course: Double

        init(_ point: TrackPoint) {
            timestamp = point.timestamp.timeIntervalSinceReferenceDate
            latitude = point.latitude
            longitude = point.longitude
            altitude = point.altitude
            speed = point.speed
            accuracy = point.accuracy
            course = point.course
        }
    }

    private let encoder = JSONEncoder()

    init(seed: Seed? = nil) {
        if let seed {
            totalDistance = seed.totalDistance
            totalVertical = seed.totalVertical
            maxSpeed = seed.maxSpeed
            completedRuns = seed.completedRuns
            runCount = max(seed.runCount, seed.completedRuns.filter { $0.activityType == .skiing }.count)
            completedRunFiles = Array(repeating: nil, count: completedRuns.count)
        }
    }

    func ingest(point: TrackPoint, motion: DetectedMotion) async -> TrackingPointIngestResult {
        currentSpeed = point.speed

        var recentTimestamps = [Double]()
        var recentAltitudes = [Double]()
        recentTimestamps.reserveCapacity(recentPoints.count)
        recentAltitudes.reserveCapacity(recentPoints.count)
        for p in recentPoints {
            recentTimestamps.append(p.timestamp.timeIntervalSinceReferenceDate)
            recentAltitudes.append(p.altitude)
        }

        let rawActivity = RunDetectionService.detect(
            point: point,
            recentTimestamps: recentTimestamps,
            recentAltitudes: recentAltitudes,
            motion: motion
        )

        recentPoints.append(point)
        if recentPoints.count > SharedConstants.recentPointsBufferSize {
            recentPoints.removeFirst(recentPoints.count - SharedConstants.recentPointsBufferSize)
        }

        let dwellResult = await SessionTrackingService.applyDwellTime(
            rawActivity: rawActivity,
            currentActivity: currentActivity,
            candidateActivity: candidateActivity,
            candidateStartTime: candidateStartTime,
            timestamp: point.timestamp
        )
        currentActivity = dwellResult.activity
        candidateActivity = dwellResult.candidate
        candidateStartTime = dwellResult.candidateStart

        var distance = 0.0
        let previousForHealthKit = previousPoint
        if let prev = previousPoint {
            distance = prev.distance(to: point)
            switch currentActivity {
            case .skiing:
                totalDistance += distance
                let verticalDrop = prev.altitude - point.altitude
                if verticalDrop > 0 {
                    totalVertical += verticalDrop
                }
            case .chairlift, .idle:
                break
            }
        }

        if point.speed > maxSpeed {
            maxSpeed = point.speed
        }

        processSegment(point, activity: currentActivity)
        previousPoint = point

        return TrackingPointIngestResult(
            previousPoint: previousForHealthKit,
            distance: distance,
            activity: currentActivity
        )
    }

    func pauseTracking() {
        finalizeCurrentSegment()
        clearRealtimeState()
    }

    func stopTracking() {
        finalizeCurrentSegment()
        clearRealtimeState()
    }

    func scalarSnapshot() -> ScalarSnapshot {
        ScalarSnapshot(
            currentSpeed: currentSpeed,
            maxSpeed: maxSpeed,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            currentActivity: currentActivity,
            runCount: runCount,
            completedRunsVersion: completedRunsVersion,
            speedSamplesVersion: speedSamplesVersion
        )
    }

    func fetchCompletedRuns() -> [CompletedRunData] {
        completedRuns
    }

    func fetchSpeedSamples() -> [SpeedSample] {
        speedSamples
    }

    func snapshot() -> TrackingEngineSnapshot {
        TrackingEngineSnapshot(
            currentSpeed: currentSpeed,
            maxSpeed: maxSpeed,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            currentActivity: currentActivity,
            runCount: runCount,
            completedRuns: completedRuns,
            speedSamples: speedSamples
        )
    }

    func recordSpeedSample() {
        let now = Date.now
        speedSamples.append(SpeedSample(time: now, speed: max(currentSpeed, 0)))
        let cutoff = now.addingTimeInterval(-Self.speedSampleWindow)
        if let firstValid = speedSamples.firstIndex(where: { $0.time >= cutoff }),
           firstValid > 0 {
            speedSamples.removeSubrange(0..<firstValid)
        }
        speedSamplesVersion += 1
    }

    func completedRunStorage() -> [CompletedRunStorage] {
        completedRuns.enumerated().map { index, run in
            CompletedRunStorage(
                summary: run,
                trackFileURL: index < completedRunFiles.count ? completedRunFiles[index] : nil
            )
        }
    }

    func reset() {
        currentSpeed = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        currentActivity = .idle

        recentPoints = []
        previousPoint = nil
        candidateActivity = nil
        candidateStartTime = nil

        completedRuns = []
        runCount = 0
        speedSamples = []

        closeSegmentHandle()
        deleteSegmentFileIfPresent()
        deleteCompletedRunFiles()

        currentSegmentType = nil
        segmentStartPoint = nil
        segmentLastPoint = nil
        segmentDistance = 0
        segmentMaxSpeed = 0
        segmentPointCount = 0
        lastActiveTime = nil
    }

    // MARK: - Segment processing

    private func processSegment(_ point: TrackPoint, activity: DetectedActivity) {
        let targetType: RunActivityType?
        switch activity {
        case .skiing: targetType = .skiing
        case .chairlift: targetType = .chairlift
        case .idle: targetType = nil
        }

        if let targetType {
            if currentSegmentType != targetType {
                finalizeCurrentSegment()
                startSegment(type: targetType)
            }
            appendPointToCurrentSegment(point)
            lastActiveTime = point.timestamp
            return
        }

        if currentSegmentType != nil,
           let lastActive = lastActiveTime,
           RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: point.timestamp) {
            finalizeCurrentSegment()
        }
    }

    private func startSegment(type: RunActivityType) {
        currentSegmentType = type
        segmentStartPoint = nil
        segmentLastPoint = nil
        segmentDistance = 0
        segmentMaxSpeed = 0
        segmentPointCount = 0
        closeSegmentHandle()
        deleteSegmentFileIfPresent()
        segmentTrackFileURL = makeSegmentFileURL()
        if let segmentTrackFileURL {
            FileManager.default.createFile(atPath: segmentTrackFileURL.path, contents: nil)
            segmentTrackFileHandle = try? FileHandle(forWritingTo: segmentTrackFileURL)
        }
    }

    private func appendPointToCurrentSegment(_ point: TrackPoint) {
        guard currentSegmentType != nil else { return }

        if segmentStartPoint == nil {
            segmentStartPoint = point
            segmentLastPoint = point
            segmentMaxSpeed = point.speed
            segmentPointCount = 1
            appendPointToSegmentFile(point)
            return
        }

        if let last = segmentLastPoint {
            segmentDistance += last.distance(to: point)
        }
        segmentLastPoint = point
        segmentMaxSpeed = max(segmentMaxSpeed, point.speed)
        segmentPointCount += 1
        appendPointToSegmentFile(point)
    }

    private func finalizeCurrentSegment() {
        guard let segmentType = currentSegmentType,
              let first = segmentStartPoint,
              let last = segmentLastPoint,
              segmentPointCount > 0 else {
            resetCurrentSegmentState(deleteFile: true)
            return
        }

        closeSegmentHandle()

        let verticalDrop: Double
        switch segmentType {
        case .skiing:
            verticalDrop = max(0, first.altitude - last.altitude)
        case .chairlift:
            verticalDrop = max(0, last.altitude - first.altitude)
        case .idle:
            verticalDrop = 0
        }

        let duration = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        let averageSpeed = duration > 0 ? segmentDistance / duration : 0

        let summary = CompletedRunData(
            startDate: first.timestamp,
            endDate: last.timestamp,
            distance: segmentDistance,
            verticalDrop: verticalDrop,
            maxSpeed: segmentMaxSpeed,
            averageSpeed: averageSpeed,
            activityType: segmentType,
            trackData: nil
        )

        completedRuns.append(summary)
        completedRunFiles.append(segmentTrackFileURL)
        completedRunsVersion += 1

        if segmentType == .skiing {
            runCount += 1
        }

        resetCurrentSegmentState(deleteFile: false)
    }

    private func clearRealtimeState() {
        previousPoint = nil
        recentPoints = []
        candidateActivity = nil
        candidateStartTime = nil
        currentSpeed = 0
        currentActivity = .idle
    }

    // MARK: - Segment file IO

    private func appendPointToSegmentFile(_ point: TrackPoint) {
        guard let handle = segmentTrackFileHandle else { return }
        guard let encoded = try? encoder.encode(NDJSONTrackPoint(point)) else { return }
        var line = encoded
        line.append(0x0A)
        try? handle.write(contentsOf: line)
    }

    private func closeSegmentHandle() {
        guard let handle = segmentTrackFileHandle else { return }
        try? handle.synchronize()
        try? handle.close()
        segmentTrackFileHandle = nil
    }

    private func resetCurrentSegmentState(deleteFile: Bool) {
        closeSegmentHandle()
        if deleteFile {
            deleteSegmentFileIfPresent()
        }
        currentSegmentType = nil
        segmentStartPoint = nil
        segmentLastPoint = nil
        segmentDistance = 0
        segmentMaxSpeed = 0
        segmentPointCount = 0
        lastActiveTime = nil
    }

    private func makeSegmentFileURL() -> URL? {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowly-tracking-runs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("\(UUID().uuidString).ndjson")
        } catch {
            return nil
        }
    }

    private func deleteSegmentFileIfPresent() {
        guard let url = segmentTrackFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        segmentTrackFileURL = nil
    }

    private func deleteCompletedRunFiles() {
        for case let url? in completedRunFiles {
            try? FileManager.default.removeItem(at: url)
        }
        completedRunFiles = []
    }
}

@Observable
@MainActor
final class SessionTrackingService {
    // MARK: - Dependencies (injected)
    private let locationService: any LocationProviding
    private let motionService: any MotionDetecting
    private let batteryService: any BatteryMonitoring
    private let healthKitCoordinator: HealthKitCoordinator
    private let liveActivityService: LiveActivityService?

    // MARK: - Published state
    private(set) var state: TrackingState = .idle
    private(set) var currentSpeed: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var totalDistance: Double = 0
    private(set) var totalVertical: Double = 0
    private(set) var currentActivity: DetectedActivity = .idle

    private(set) var activeSessionId: UUID?
    private(set) var startDate: Date?

    /// Set to true by deep links / quick actions. HomeView observes and starts tracking.
    var quickStartPending = false

    private(set) var runCount: Int = 0
    private(set) var completedRuns: [CompletedRunData] = []
    var pendingHealthKitWorkoutId: UUID? { healthKitCoordinator.pendingWorkoutId }

    /// Rolling 10-minute window of time-stamped speed samples for the live curve.
    private(set) var speedSamples: [SpeedSample] = []

    // MARK: - Internal state
    private var trackingTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var trackingEngine = TrackingEngine()

    private(set) var pauseStartTime: Date?
    private(set) var totalPausedTime: TimeInterval = 0
    private var speedSampleAccumulator: TimeInterval = 0
    private var lastProcessedPointTime: Date?
    private var lastSyncedRunsVersion: Int = 0
    private var lastSyncedSamplesVersion: Int = 0

    private var isDashboardVisible = false
    private var isAppActive = true

    private static let recoveryStateMaxAge: TimeInterval = 12 * 3600
    private static let activeForegroundRefreshInterval: TimeInterval = 1
    private static let passiveRefreshInterval: TimeInterval = 3

    init(
        locationService: any LocationProviding,
        motionService: any MotionDetecting,
        batteryService: any BatteryMonitoring,
        healthKitService: HealthKitService? = nil,
        segmentService _: SegmentFinalizationService? = nil,
        healthKitCoordinator: HealthKitCoordinator? = nil,
        liveActivityService: LiveActivityService? = nil
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.batteryService = batteryService
        self.healthKitCoordinator = healthKitCoordinator ?? HealthKitCoordinator(healthKitService: healthKitService)
        self.liveActivityService = liveActivityService

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

    func startTracking(healthKitEnabled: Bool = false, unitSystem: UnitSystem = .metric) {
        guard state == .idle else { return }

        let staleEngine = trackingEngine
        Task {
            await staleEngine.reset()
        }
        trackingEngine = TrackingEngine()

        let sessionId = UUID()
        activeSessionId = sessionId
        startDate = Date()

        resetPublishedStats()
        state = .tracking
        motionService.startMonitoring()
        batteryService.startMonitoring()

        healthKitCoordinator.startWorkout(
            healthKitEnabled: healthKitEnabled,
            startDate: startDate ?? Date()
        )

        liveActivityService?.startLiveActivity(
            startDate: startDate ?? Date(),
            unitSystem: unitSystem
        )

        startLiveTrackingPipeline()
        startTimer()
        startPeriodicPersistence()
    }

    func pauseTracking() async {
        guard state == .tracking else { return }
        await trackingEngine.pauseTracking()

        state = .paused
        pauseStartTime = Date()
        speedSampleAccumulator = 0

        await syncPublishedSnapshot(recordSpeedSample: false)
    }

    func resumeTracking() async {
        guard state == .paused else { return }

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

        await syncPublishedSnapshot(recordSpeedSample: false)
    }

    func stopTracking() async {
        guard state != .idle else { return }

        await trackingEngine.stopTracking()

        trackingTask?.cancel()
        timerTask?.cancel()
        persistenceTask?.cancel()
        trackingTask = nil
        timerTask = nil
        persistenceTask = nil

        locationService.stopTracking()
        motionService.stopMonitoring()
        batteryService.stopMonitoring()
        TrackingStatePersistence.clear()

        await syncPublishedSnapshot(recordSpeedSample: false)
        liveActivityService?.endLiveActivity(finalState: buildLiveActivityState())

        state = .idle
        pauseStartTime = nil
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
        Task { [weak self] in
            await self?.persistCurrentStateSnapshot(lastUpdateDate: Date())
        }
    }

    /// Saves the session to SwiftData. Call after stopTracking().
    func saveSession(to context: ModelContext, resort: Resort? = nil) async {
        guard let sessionId = activeSessionId,
              let start = startDate else { return }

        await syncPublishedSnapshot(recordSpeedSample: false)

        let runStorage = await trackingEngine.completedRunStorage()
        let materializedRuns = await loadTrackData(for: runStorage)

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

        for storedRun in materializedRuns {
            let runData = storedRun.summary
            let run = SkiRun(
                startDate: runData.startDate,
                endDate: runData.endDate,
                distance: runData.distance,
                verticalDrop: runData.verticalDrop,
                maxSpeed: runData.maxSpeed,
                averageSpeed: runData.averageSpeed,
                activityType: runData.activityType,
                trackData: storedRun.trackData
            )
            run.session = session
            context.insert(run)
        }

        await trackingEngine.reset()
        trackingEngine = TrackingEngine()

        resetPublishedStats()
        activeSessionId = nil
        startDate = nil
    }

    /// Computes current elapsed time on demand (not stored).
    func computeElapsedTime() -> TimeInterval {
        guard let start = startDate else { return 0 }
        let pausedNow = pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(start) - totalPausedTime - pausedNow)
    }

    /// Called by UI to control adaptive refresh cadence.
    func setTrackingDashboardVisible(_ visible: Bool) {
        isDashboardVisible = visible
    }

    /// Called when scene phase changes.
    func updateAppActiveState(_ active: Bool) {
        isAppActive = active
    }

    // MARK: - Private

    private func startLiveTrackingPipeline() {
        trackingTask?.cancel()
        let stream = locationService.startTracking()
        trackingTask = Task { [weak self] in
            for await point in stream {
                guard let self, !Task.isCancelled else { break }
                await self.processTrackPoint(point)
            }
        }
    }

    /// Minimum interval between processed points to cap CPU at high speed.
    private static let minPointInterval: TimeInterval = 0.4

    private func processTrackPoint(_ point: TrackPoint) async {
        guard state == .tracking else { return }

        // Throttle: skip points arriving faster than minPointInterval
        if let lastTime = lastProcessedPointTime,
           point.timestamp.timeIntervalSince(lastTime) < Self.minPointInterval {
            return
        }
        lastProcessedPointTime = point.timestamp

        let motion = motionService.currentMotion
        let ingestResult = await trackingEngine.ingest(point: point, motion: motion)

        if let previous = ingestResult.previousPoint {
            healthKitCoordinator.forwardPoint(
                point,
                previousPoint: previous,
                distance: ingestResult.distance,
                isSkiing: ingestResult.activity == .skiing
            )
        }
    }

    private func startTimer() {
        speedSampleAccumulator = 0
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let interval = self.currentRefreshInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self.handleTimerTick(interval: interval)
            }
        }
    }

    private var currentRefreshInterval: TimeInterval {
        guard state == .tracking else { return Self.activeForegroundRefreshInterval }
        return (isDashboardVisible && isAppActive)
            ? Self.activeForegroundRefreshInterval
            : Self.passiveRefreshInterval
    }

    private func handleTimerTick(interval: TimeInterval) async {
        guard startDate != nil else { return }

        var shouldRecordSpeedSample = false
        if state == .tracking {
            speedSampleAccumulator += interval
            if speedSampleAccumulator >= 2 {
                shouldRecordSpeedSample = true
                speedSampleAccumulator.formTruncatingRemainder(dividingBy: 2)
            }
        }

        // Skip full UI sync when dashboard not visible and app inactive
        if !isDashboardVisible && !isAppActive && !shouldRecordSpeedSample {
            return
        }

        await syncPublishedSnapshot(recordSpeedSample: shouldRecordSpeedSample)
    }

    private func startPeriodicPersistence() {
        persistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SharedConstants.statePersistenceInterval))
                guard let self else { continue }
                await self.persistCurrentStateSnapshot(lastUpdateDate: Date())
            }
        }
    }

    private func syncPublishedSnapshot(recordSpeedSample: Bool) async {
        if recordSpeedSample {
            await trackingEngine.recordSpeedSample()
        }

        let scalar = await trackingEngine.scalarSnapshot()

        // Fetch arrays only when their version has changed
        let newRuns: [CompletedRunData]?
        if scalar.completedRunsVersion != lastSyncedRunsVersion {
            newRuns = await trackingEngine.fetchCompletedRuns()
            lastSyncedRunsVersion = scalar.completedRunsVersion
        } else {
            newRuns = nil
        }

        let newSamples: [SpeedSample]?
        if scalar.speedSamplesVersion != lastSyncedSamplesVersion {
            newSamples = await trackingEngine.fetchSpeedSamples()
            lastSyncedSamplesVersion = scalar.speedSamplesVersion
        } else {
            newSamples = nil
        }

        // Batch all MainActor mutations in one synchronous block
        if currentSpeed != scalar.currentSpeed {
            currentSpeed = scalar.currentSpeed
        }
        if maxSpeed != scalar.maxSpeed {
            maxSpeed = scalar.maxSpeed
        }
        if totalDistance != scalar.totalDistance {
            totalDistance = scalar.totalDistance
        }
        if totalVertical != scalar.totalVertical {
            totalVertical = scalar.totalVertical
        }
        if currentActivity != scalar.currentActivity {
            currentActivity = scalar.currentActivity
        }
        if runCount != scalar.runCount {
            runCount = scalar.runCount
        }
        if let newRuns {
            completedRuns = newRuns
        }
        if let newSamples {
            speedSamples = newSamples
        }

        liveActivityService?.update(state: buildLiveActivityState())
    }

    private func buildLiveActivityState() -> SnowlyActivityAttributes.ContentState {
        SnowlyActivityAttributes.ContentState(
            currentSpeed: currentSpeed,
            totalVertical: totalVertical,
            runCount: runCount,
            elapsedSeconds: Int(computeElapsedTime()),
            currentActivity: currentActivity.activityName,
            isPaused: state == .paused,
            maxSpeed: maxSpeed
        )
    }

    private func persistCurrentStateSnapshot(lastUpdateDate: Date) async {
        guard state != .idle,
              let sessionId = activeSessionId,
              let start = startDate else { return }

        let snapshot = await trackingEngine.snapshot()
        guard state != .idle,
              activeSessionId == sessionId,
              startDate == start else { return }

        let state = PersistedTrackingState(
            sessionId: sessionId,
            startDate: start,
            lastUpdateDate: lastUpdateDate,
            totalDistance: snapshot.totalDistance,
            totalVertical: snapshot.totalVertical,
            maxSpeed: snapshot.maxSpeed,
            runCount: snapshot.runCount,
            isActive: true,
            elapsedTime: computeElapsedTime(),
            completedRuns: snapshot.completedRuns.map {
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

    private func loadTrackData(for runStorage: [CompletedRunStorage]) async -> [MaterializedCompletedRun] {
        await Task.detached(priority: .utility) {
            runStorage.map { storedRun in
                let trackData: Data?
                if let embedded = storedRun.summary.trackData {
                    trackData = embedded
                } else if let url = storedRun.trackFileURL {
                    trackData = try? Data(contentsOf: url, options: .mappedIfSafe)
                } else {
                    trackData = nil
                }

                return MaterializedCompletedRun(
                    summary: storedRun.summary,
                    trackData: trackData
                )
            }
        }.value
    }

    private func restoreState(from persisted: PersistedTrackingState) {
        activeSessionId = persisted.sessionId
        startDate = persisted.startDate
        totalDistance = persisted.totalDistance
        totalVertical = persisted.totalVertical
        maxSpeed = persisted.maxSpeed
        let restoredElapsed = persisted.elapsedTime ?? max(0, Date().timeIntervalSince(persisted.startDate))
        totalPausedTime = max(0, Date().timeIntervalSince(persisted.startDate) - restoredElapsed)
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
        completedRuns = restoredRuns
        runCount = max(persisted.runCount, restoredRuns.filter { $0.activityType == .skiing }.count)

        let seed = TrackingEngine.Seed(
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            completedRuns: restoredRuns,
            runCount: runCount
        )
        trackingEngine = TrackingEngine(seed: seed)

        currentSpeed = 0
        currentActivity = .idle
        speedSamples = []
        state = .paused
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
        if rawActivity == currentActivity {
            return (currentActivity, nil, nil)
        }

        if rawActivity == candidateActivity, let candidateStart = candidateStartTime {
            let required = dwellTimeForTransition(from: currentActivity, to: rawActivity)
            if timestamp.timeIntervalSince(candidateStart) >= required {
                return (rawActivity, nil, nil)
            }
            return (currentActivity, candidateActivity, candidateStartTime)
        }

        return (currentActivity, rawActivity, timestamp)
    }

    private func resetPublishedStats() {
        currentSpeed = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        currentActivity = .idle
        runCount = 0
        completedRuns = []
        speedSamples = []

        totalPausedTime = 0
        pauseStartTime = nil
        speedSampleAccumulator = 0
        lastProcessedPointTime = nil
        lastSyncedRunsVersion = 0
        lastSyncedSamplesVersion = 0

        healthKitCoordinator.reset()
    }
}
