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
import os

/// Tracking session state machine.
enum TrackingState: Sendable, Equatable {
    case idle
    case tracking
    case paused
}

/// Aggregated session metrics that only count validated skiing activity.
struct SessionSkiingMetrics: Sendable, Equatable {
    let totalDistance: Double
    let totalVertical: Double
    let maxSpeed: Double
    let runCount: Int

    static let zero = SessionSkiingMetrics(
        totalDistance: 0,
        totalVertical: 0,
        maxSpeed: 0,
        runCount: 0
    )
}

/// Coarse state used by the live speed curve coloring.
enum SpeedCurveState: String, Codable, Sendable, Equatable {
    case skiing
    case lift
    case others
}

/// A time-stamped speed reading for the live speed curve.
struct SpeedSample: Sendable, Equatable {
    let time: Date
    let speed: Double // m/s
    let state: SpeedCurveState
}

/// A time-stamped altitude reading for the altitude curve widget.
/// Altitude is pre-converted to the user's display unit before storing.
struct AltitudeSample: Sendable, Equatable {
    let time: Date
    let altitude: Double        // display units (m or ft)
    let state: SpeedCurveState  // activity phase for per-segment coloring
}

/// A time-stamped heart rate reading for the heart rate curve hero card.
struct HeartRateSample: Sendable, Equatable {
    let time: Date
    let bpm: Double
}

struct SavedSessionOutcome: Sendable {
    let sessionId: UUID
    let personalBestRecords: [String]
    let personalBestUpdate: StatsService.PersonalBestUpdate?
}

private struct TrackingPointIngestResult: Sendable {
    let point: FilteredTrackPoint?
    let previousPoint: FilteredTrackPoint?
    let distance: Double
    let activity: DetectedActivity
    let scalar: ScalarSnapshot
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
    let currentAltitude: Double
    let maxSpeed: Double
    let totalDistance: Double
    let totalVertical: Double
    let skiingMetrics: SessionSkiingMetrics
    let currentActivity: DetectedActivity
    let runCount: Int
    let completedRunsVersion: Int
}

private struct TrackingEngineSnapshot: Sendable {
    let currentSpeed: Double
    let maxSpeed: Double
    let totalDistance: Double
    let totalVertical: Double
    let skiingMetrics: SessionSkiingMetrics
    let currentActivity: DetectedActivity
    let runCount: Int
    let completedRuns: [CompletedRunData]
    let completedRunFilePaths: [String?]
}

private extension DetectedActivity {
    nonisolated var speedCurveState: SpeedCurveState {
        switch self {
        case .skiing:
            return .skiing
        case .lift:
            return .lift
        case .idle, .walk:
            return .others
        }
    }
}

/// Core runtime engine for motion estimation, activity detection, segmenting,
/// and run materialization.
///
/// Dependency graph of the tracking pipeline:
/// ```mermaid
/// graph TD
/// A[LocationTrackingService] --> B[SessionTrackingService]
/// B --> C[TrackingEngine]
/// C --> D[GPSKalmanFilter]
/// C --> E[RunDetectionService]
/// E --> F[MotionEstimator]
/// C --> G[Dwell/Hysteresis]
/// C --> H[SegmentProcessor]
/// H --> I[SegmentValidator]
/// H --> J[Raw TrackFile Writer]
/// J --> K[materializeTrackFileIfNeeded]
/// K --> L[SkiRun.trackData]
/// L --> M[SessionSummary Export]
/// B --> N[HealthKitCoordinator]
/// O[SharedConstants] --> F
/// O --> E
/// O --> I
/// ```
private actor TrackingEngine {
    struct Seed: Sendable {
        let totalDistance: Double
        let totalVertical: Double
        let maxSpeed: Double
        let completedRuns: [CompletedRunData]
        let completedRunFileURLs: [URL?]
        let runCount: Int
    }

    // MARK: - Session stats
    private var currentSpeed: Double = 0
    private var maxSpeed: Double = 0
    private var totalDistance: Double = 0
    private var totalVertical: Double = 0
    private var currentActivity: DetectedActivity = .idle

    // MARK: - GPS filtering
    private var gpsFilter = GPSKalmanFilter()
    private var currentAltitude: Double = 0

    // MARK: - Detection state
    private var recentPoints = RecentTrackBuffer<FilteredTrackPoint>()
    private var previousFilteredPoint: FilteredTrackPoint?
    private var candidateActivity: DetectedActivity?
    private var candidateStartTime: Date?
    /// Timestamp of the last point seeded via primeRecentWindow. Points with timestamp ≤ this
    /// are skipped in ingest() to prevent double-processing through the Kalman filter.
    private var primeEndTimestamp: Date?

    // MARK: - Completed runs
    private var completedRuns: [CompletedRunData] = []
    private var completedRunFiles: [URL?] = []
    private var runCount: Int = 0

    // MARK: - Version counters
    private var completedRunsVersion: Int = 0

    // MARK: - Active segment (streamed to temp file)
    private var currentSegmentType: RunActivityType?
    private var segmentStartPoint: FilteredTrackPoint?
    private var segmentLastPoint: FilteredTrackPoint?
    private var segmentDistance: Double = 0
    private var segmentMaxSpeed: Double = 0
    private var segmentPointCount: Int = 0
    private var segmentTrackFileURL: URL?
    private var segmentTrackFileHandle: FileHandle?
    private var lastActiveTime: Date?

    private let encoder = JSONEncoder()

    init(seed: Seed? = nil) {
        if let seed {
            totalDistance = seed.totalDistance
            totalVertical = seed.totalVertical
            maxSpeed = seed.maxSpeed
            completedRuns = seed.completedRuns
            runCount = max(seed.runCount, seed.completedRuns.filter { $0.activityType == .skiing }.count)
            completedRunFiles = seed.completedRunFileURLs.isEmpty
                ? Array(repeating: nil, count: completedRuns.count)
                : seed.completedRunFileURLs
        }
    }

    func primeRecentWindow(with points: [TrackPoint]) {
        guard !points.isEmpty else { return }

        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        recentPoints.removeAll()
        for point in sortedPoints {
            recentPoints.append(point.filteredEstimatePoint)
        }

        primeEndTimestamp = sortedPoints.last?.timestamp
        currentAltitude = sortedPoints.last?.altitude ?? 0

        previousFilteredPoint = nil
        candidateActivity = nil
        candidateStartTime = nil
        currentActivity = .idle
        currentSpeed = 0

        // Warm up the Kalman filter with passively collected GPS history
        // so covariances are settled before the first live point arrives.
        gpsFilter.reset()
        for point in sortedPoints {
            _ = gpsFilter.update(point: point)
        }
    }

    func ingest(point: TrackPoint, motion: MotionHint) -> TrackingPointIngestResult {
        // Skip live-stream points that overlap with the seeded history window.
        // The seed history only warms run detection; it does not initialize the
        // Kalman filter. This cutoff prevents pre-start or pre-resume overlap from
        // being processed twice once live GPS delivery begins.
        if let cutoff = primeEndTimestamp {
            if point.timestamp <= cutoff {
                return TrackingPointIngestResult(
                    point: nil,
                    previousPoint: nil,
                    distance: 0,
                    activity: currentActivity, scalar: scalarSnapshot()
                )
            }
            primeEndTimestamp = nil
        }

        let filteredPoint = gpsFilter.update(point: point)
        currentSpeed = filteredPoint.estimatedSpeed
        currentAltitude = filteredPoint.altitude

        // Consumer pattern invariant: filteredPoint is NOT in recentPoints here.
        // Detection reads history before append so the current point cannot bias its own
        // classification. recentPoints.append() happens below, AFTER detection.
        // Do not move the append call above this block.
        let detectionDecision = RunDetectionService.analyze(
            point: filteredPoint,
            recentPoints: recentPoints,
            previousActivity: currentActivity,
            motion: motion
        )
        let rawActivity = detectionDecision.activity

        recentPoints.append(filteredPoint)

        // applyDwellTime is nonisolated — no MainActor hop needed.
        let dwellResult = SessionTrackingService.applyDwellTime(
            rawActivity: rawActivity,
            currentActivity: currentActivity,
            candidateActivity: candidateActivity,
            candidateStartTime: candidateStartTime,
            timestamp: filteredPoint.timestamp,
            accelerated: detectionDecision.shouldAccelerateDwell
        )
        currentActivity = dwellResult.activity
        candidateActivity = dwellResult.candidate
        candidateStartTime = dwellResult.candidateStart

        // Accumulate session metrics against rawActivity (pre-dwell), not currentActivity.
        // This prevents lift travel distance from being credited to skiing during the dwell
        // window (e.g. 14s skiing→lift at ~3 m/s = ~42m that would otherwise be miscounted).
        // Segment boundaries still use currentActivity for stability.
        var distance = 0.0
        let previousForHealthKit = previousFilteredPoint
        if let prev = previousFilteredPoint {
            distance = prev.distance(to: filteredPoint)
            switch rawActivity {
            case .skiing:
                totalDistance += distance
                let verticalDrop = prev.altitude - filteredPoint.altitude
                if verticalDrop > 0 {
                    totalVertical += verticalDrop
                }
            case .lift, .idle, .walk:
                break
            }
        }

        if case .skiing = rawActivity, filteredPoint.estimatedSpeed > maxSpeed {
            maxSpeed = filteredPoint.estimatedSpeed
        }

        processSegment(filteredPoint: filteredPoint, rawPoint: point, activity: currentActivity)
        previousFilteredPoint = filteredPoint
        return TrackingPointIngestResult(
            point: filteredPoint,
            previousPoint: previousForHealthKit,
            distance: distance,
            activity: currentActivity,
            scalar: scalarSnapshot()
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
        let metrics = SessionSkiingMetrics(
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount
        )
        return ScalarSnapshot(
            currentSpeed: currentSpeed,
            currentAltitude: currentAltitude,
            maxSpeed: maxSpeed,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            skiingMetrics: metrics,
            currentActivity: currentActivity,
            runCount: runCount,
            completedRunsVersion: completedRunsVersion
        )
    }

    func fetchCompletedRuns() -> [CompletedRunData] {
        completedRuns
    }

    func snapshot() -> TrackingEngineSnapshot {
        let metrics = SessionSkiingMetrics(
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount
        )
        return TrackingEngineSnapshot(
            currentSpeed: currentSpeed,
            maxSpeed: maxSpeed,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            skiingMetrics: metrics,
            currentActivity: currentActivity,
            runCount: runCount,
            completedRuns: completedRuns,
            completedRunFilePaths: completedRunFiles.map { $0?.path }
        )
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
        gpsFilter.reset()
        currentSpeed = 0
        currentAltitude = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        currentActivity = .idle

        recentPoints.removeAll()
        previousFilteredPoint = nil
        candidateActivity = nil
        candidateStartTime = nil

        completedRuns = []
        runCount = 0

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

    private func processSegment(
        filteredPoint: FilteredTrackPoint,
        rawPoint: TrackPoint,
        activity: DetectedActivity
    ) {
        let targetType: RunActivityType?
        switch activity {
        case .skiing: targetType = .skiing
        case .lift:   targetType = .lift
        case .walk:   targetType = .walk
        case .idle:   targetType = nil
        }

        if let targetType {
            if currentSegmentType != targetType {
                finalizeCurrentSegment()
                startSegment(type: targetType)
            }
            appendPointToCurrentSegment(filteredPoint: filteredPoint, rawPoint: rawPoint)
            lastActiveTime = filteredPoint.timestamp
            return
        }

        if currentSegmentType != nil,
           let lastActive = lastActiveTime,
           RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: filteredPoint.timestamp) {
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

    private func appendPointToCurrentSegment(filteredPoint: FilteredTrackPoint, rawPoint: TrackPoint) {
        guard currentSegmentType != nil else { return }

        if segmentStartPoint == nil {
            segmentStartPoint = filteredPoint
            segmentLastPoint = filteredPoint
            segmentMaxSpeed = filteredPoint.estimatedSpeed
            segmentPointCount = 1
            appendPointToSegmentFile(rawPoint)
            return
        }

        if let last = segmentLastPoint {
            segmentDistance += last.distance(to: filteredPoint)
        }
        segmentLastPoint = filteredPoint
        segmentMaxSpeed = max(segmentMaxSpeed, filteredPoint.estimatedSpeed)
        segmentPointCount += 1
        appendPointToSegmentFile(rawPoint)
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

        let duration = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        let averageSpeed = duration > 0 ? segmentDistance / duration : 0

        guard let effectiveType = SegmentValidator.effectiveType(
            activityType: segmentType,
            firstPoint: first,
            lastPoint: last,
            duration: duration,
            averageSpeed: averageSpeed
        ) else {
            resetCurrentSegmentState(deleteFile: true)
            return
        }

        let verticalDrop = SegmentValidator.verticalDrop(
            effectiveType: effectiveType,
            firstAltitude: first.altitude,
            lastAltitude: last.altitude
        )

        let summary = CompletedRunData(
            startDate: first.timestamp,
            endDate: last.timestamp,
            distance: segmentDistance,
            verticalDrop: verticalDrop,
            maxSpeed: segmentMaxSpeed,
            averageSpeed: averageSpeed,
            activityType: effectiveType,
            trackData: nil
        )

        completedRuns.append(summary)
        completedRunFiles.append(segmentTrackFileURL)
        completedRunsVersion += 1

        if effectiveType == .skiing {
            runCount += 1
        }

        resetCurrentSegmentState(deleteFile: false)
    }

    private func clearRealtimeState() {
        gpsFilter.reset()
        previousFilteredPoint = nil
        recentPoints.removeAll()
        candidateActivity = nil
        candidateStartTime = nil
        currentSpeed = 0
        currentActivity = .idle
    }

    // MARK: - Segment file IO

    private func appendPointToSegmentFile(_ point: TrackPoint) {
        guard let handle = segmentTrackFileHandle else { return }
        guard let encoded = try? encoder.encode(point) else { return }
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
        } else {
            // The file URL has already been moved to `completedRunFiles`.
            // Clearing it here prevents later no-op finalization from deleting
            // a completed segment's persisted track file.
            segmentTrackFileURL = nil
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
        let fm = FileManager.default
        do {
            let support = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let base = support.appendingPathComponent("snowly-tracking-runs", isDirectory: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
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
    /// Kalman-filtered altitude in meters. Always read this — never locationService.currentAltitude.
    private(set) var currentAltitude: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var totalDistance: Double = 0
    private(set) var totalVertical: Double = 0
    private(set) var currentActivity: DetectedActivity = .idle

    private(set) var activeSessionId: UUID?
    private(set) var startDate: Date?

    /// Set to true by deep links / quick actions. HomeView observes and starts tracking.
    var quickStartPending = false
    private(set) var didRecoverSession = false

    private(set) var runCount: Int = 0
    private(set) var completedRuns: [CompletedRunData] = []
    private(set) var skiingMetrics: SessionSkiingMetrics = .zero
    private(set) var lastSavedSessionOutcome: SavedSessionOutcome?
    var pendingHealthKitWorkoutId: UUID? { healthKitCoordinator.pendingWorkoutId }

    /// Rolling 10-minute window of GPS-driven speed samples for the live curve.
    /// Materialized only when a new sample is appended, not on every view read.
    private(set) var speedSamples: [SpeedSample] = []

    /// Rolling 1-hour window of GPS-driven altitude samples for the profile widget.
    /// Materialized only when a new sample is appended, not on every view read.
    private(set) var altitudeSamples: [AltitudeSample] = []

    // CircularBuffer backing for rolling sample windows — O(1) append, no Array shifting.
    // Capacities match the retention windows: 600s / 2s = 300, 3600s / 2s = 1800.
    private var speedSampleBuffer = CircularBuffer<SpeedSample>(capacity: 300)
    private var altitudeSampleBuffer = CircularBuffer<AltitudeSample>(capacity: 1800)

    // MARK: - Internal state
    private var trackingTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var trackingEngine = TrackingEngine()

    private(set) var pauseStartTime: Date?
    private(set) var totalPausedTime: TimeInterval = 0
    private var lastSyncedRunsVersion: Int = 0
    private var liveActivityUnitSystem: UnitSystem = .metric
    private var trackingUpdateIntervalSeconds: TimeInterval = 1.0
    private var autoPauseIdleThreshold: TimeInterval = 0
    private var idleSinceDate: Date?

    private var isDashboardVisible = false
    private var isAppActive = true
    private var lastGPSSyncDate: Date?

    private static let curveSampleIntervalSeconds: TimeInterval = 2
    private static let recoveryStateMaxAge: TimeInterval = 12 * 3600
    nonisolated private static let logger = Logger(subsystem: "com.Snowly", category: "SessionTracking")

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

    func dismissRecoveryNotification() {
        didRecoverSession = false
    }

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
        liveActivityUnitSystem = unitSystem
        lastSavedSessionOutcome = nil

        resetPublishedStats()
        state = .tracking
        motionService.startMonitoring()
        batteryService.startMonitoring()

        healthKitCoordinator.startWorkout(
            healthKitEnabled: healthKitEnabled,
            startDate: startDate ?? Date()
        )

        ensureLiveActivityStarted(unitSystem: unitSystem)

        startLiveTrackingPipeline(seedHistory: locationService.recentTrackPointsSnapshot())
        startTimer()
        startPeriodicPersistence()
    }

    func pauseTracking() async {
        guard state == .tracking else { return }
        await trackingEngine.pauseTracking()

        state = .paused
        pauseStartTime = Date()
        idleSinceDate = nil

        await syncPublishedSnapshot()
    }

    func resumeTracking(unitSystem: UnitSystem? = nil) async {
        guard state == .paused else { return }

        if trackingTask == nil {
            motionService.startMonitoring()
            batteryService.startMonitoring()
            startLiveTrackingPipeline(seedHistory: locationService.recentTrackPointsSnapshot())
            if timerTask == nil {
                startTimer()
            }
            if persistenceTask == nil {
                startPeriodicPersistence()
            }
        }

        await trackingEngine.primeRecentWindow(with: locationService.recentTrackPointsSnapshot())

        if let pauseStart = pauseStartTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        idleSinceDate = nil
        state = .tracking
        ensureLiveActivityStarted(unitSystem: unitSystem ?? liveActivityUnitSystem)

        await syncPublishedSnapshot()
    }

    func stopTracking() async {
        guard state != .idle else { return }

        // Finish the location stream first so the consumer task can drain any
        // already-buffered GPS points before segment finalization.
        locationService.stopTracking()
        if let trackingTask {
            await trackingTask.value
        }

        await trackingEngine.stopTracking()

        timerTask?.cancel()
        persistenceTask?.cancel()
        trackingTask = nil
        timerTask = nil
        persistenceTask = nil

        motionService.stopMonitoring()
        batteryService.stopMonitoring()

        // Set state = .idle BEFORE clear() so that any persistence task that slipped
        // through cancellation fails its `guard state != .idle` check and cannot
        // re-write isActive: true after the clear.
        state = .idle
        pauseStartTime = nil
        TrackingStatePersistence.clear()

        await syncPublishedSnapshot()
        liveActivityService?.endLiveActivity(finalState: buildLiveActivityState())
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

        await syncPublishedSnapshot()

        let runStorage = await trackingEngine.completedRunStorage()
        let materializedRuns = await loadTrackData(for: runStorage)
        let activeGearSetup = fetchActiveGearSetup(in: context)
        let lockerAssets = fetchLockerAssets(in: context)

        let session = SkiSession(
            id: sessionId,
            startDate: start,
            endDate: Date(),
            totalDistance: skiingMetrics.totalDistance,
            totalVertical: skiingMetrics.totalVertical,
            maxSpeed: skiingMetrics.maxSpeed,
            runCount: skiingMetrics.runCount
        )

        if let workoutId = pendingHealthKitWorkoutId {
            session.healthKitWorkoutId = workoutId
        }

        session.resort = resort
        session.applyGearSnapshot(from: activeGearSetup, lockerAssets: lockerAssets)

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

        var personalBestRecords: [String] = []
        var personalBestUpdate: StatsService.PersonalBestUpdate?
        var profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        profileDescriptor.fetchLimit = 1
        if let profile = (try? context.fetch(profileDescriptor))?.first {
            personalBestRecords = StatsService.checkPersonalBests(
                session: session,
                profile: profile
            )

            let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)
            if update.hasUpdates {
                StatsService.applyPersonalBestUpdate(update, to: profile)
                personalBestUpdate = update
            }

            let seasonUpdate = StatsService.computeSeasonBestUpdates(session: session, profile: profile)
            if seasonUpdate.hasUpdates {
                StatsService.applySeasonBestUpdate(seasonUpdate, to: profile)
            }
        }

        do {
            try context.save()
            lastSavedSessionOutcome = SavedSessionOutcome(
                sessionId: session.id,
                personalBestRecords: personalBestRecords,
                personalBestUpdate: personalBestUpdate
            )
        } catch {
            Self.logger.error("Failed to save tracked session: \(error.localizedDescription, privacy: .public)")
            lastSavedSessionOutcome = nil
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

    func updateTrackingUpdateInterval(seconds: TimeInterval) {
        let clamped = min(max(seconds, 0.5), 30)
        guard trackingUpdateIntervalSeconds != clamped else { return }
        trackingUpdateIntervalSeconds = clamped
        liveActivityService?.setMinimumUpdateInterval(seconds: clamped)
    }

    func updateAutoPauseThreshold(seconds: TimeInterval) {
        autoPauseIdleThreshold = max(seconds, 0)
    }

    // MARK: - Private

    private func startLiveTrackingPipeline(seedHistory: [TrackPoint] = []) {
        trackingTask?.cancel()
        let stream = locationService.startTracking()
        trackingTask = Task { [weak self] in
            guard let self else { return }
            if !seedHistory.isEmpty {
                await self.trackingEngine.primeRecentWindow(with: seedHistory)
            }
            for await point in stream {
                guard !Task.isCancelled else { break }
                await self.processTrackPoint(point)
            }
        }
    }

    private func fetchActiveGearSetup(in context: ModelContext) -> GearSetup? {
        var descriptor = FetchDescriptor<GearSetup>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        descriptor.fetchLimit = 1

        if let active = (try? context.fetch(FetchDescriptor<GearSetup>(
            predicate: #Predicate<GearSetup> { $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        )))?.first {
            return active
        }

        return (try? context.fetch(descriptor))?.first
    }

    private func fetchLockerAssets(in context: ModelContext) -> [GearAsset] {
        let descriptor = FetchDescriptor<GearAsset>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func ensureLiveActivityStarted(unitSystem: UnitSystem) {
        liveActivityUnitSystem = unitSystem
        guard let liveActivityService else {
            Self.logger.error("Live Activity service missing")
            return
        }
        liveActivityService.setMinimumUpdateInterval(seconds: trackingUpdateIntervalSeconds)
        let start = startDate ?? Date()
        liveActivityService.startLiveActivity(startDate: start, unitSystem: unitSystem)
        liveActivityService.update(state: buildLiveActivityState())
    }

    private func processTrackPoint(_ point: TrackPoint) async {
        guard state == .tracking else { return }

        let motionHint: MotionHint = motionService.currentMotion == .automotive ? .automotive : .unknown
        let ingestResult = await trackingEngine.ingest(point: point, motion: motionHint)

        if let point = ingestResult.point, let previous = ingestResult.previousPoint {
            healthKitCoordinator.forwardPoint(
                point,
                previousPoint: previous,
                distance: ingestResult.distance,
                isSkiing: ingestResult.activity == .skiing
            )
        }

        applyScalarSnapshot(ingestResult.scalar)
        await syncCompletedRunsIfNeeded(version: ingestResult.scalar.completedRunsVersion)
        if let filteredPoint = ingestResult.point {
            appendCurveSample(
                point: filteredPoint,
                state: ingestResult.activity.speedCurveState
            )
        }

        lastGPSSyncDate = Date()

        // Use the scalar returned by ingest() — no second actor hop into TrackingEngine.
        pushLiveActivityUpdate(scalar: ingestResult.scalar)
    }

    /// Pushes a Live Activity update using a scalar snapshot already in hand.
    /// Synchronous — no actor access needed.
    private func pushLiveActivityUpdate(scalar: ScalarSnapshot) {
        guard let liveActivityService else { return }
        let state = SnowlyActivityAttributes.ContentState(
            currentSpeed: scalar.currentSpeed,
            totalVertical: scalar.skiingMetrics.totalVertical,
            runCount: scalar.skiingMetrics.runCount,
            elapsedSeconds: Int(computeElapsedTime()),
            currentActivity: scalar.currentActivity.activityName,
            isPaused: self.state == .paused,
            maxSpeed: scalar.skiingMetrics.maxSpeed
        )
        liveActivityService.update(state: state)
    }

    private func startTimer() {
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
        guard state == .tracking else { return 1.0 }
        return trackingUpdateIntervalSeconds
    }

    private func handleTimerTick(interval _: TimeInterval) async {
        guard startDate != nil else { return }

        // Skip full UI sync when a GPS-driven sync already ran recently — the
        // per-point processTrackPoint() path already calls applyScalarSnapshot(),
        // so repeating it from the timer wastes an actor hop and doubles the
        // @Observable mutations that drive SwiftUI re-renders.
        let gpsSyncedRecently = lastGPSSyncDate.map { Date().timeIntervalSince($0) < 0.8 } ?? false
        if !gpsSyncedRecently, isDashboardVisible || isAppActive {
            await syncPublishedSnapshot()
        }

        // Auto-pause when idle exceeds threshold
        if state == .tracking && autoPauseIdleThreshold > 0 {
            if currentActivity == .idle {
                if idleSinceDate == nil {
                    idleSinceDate = Date()
                } else if let idleSince = idleSinceDate,
                          Date().timeIntervalSince(idleSince) >= autoPauseIdleThreshold {
                    await pauseTracking()
                }
            } else {
                idleSinceDate = nil
            }
        }
    }

    private func startPeriodicPersistence() {
        persistenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SharedConstants.statePersistenceInterval))
                // try? swallows CancellationError, so re-check after sleep.
                guard !Task.isCancelled else { break }
                guard let self else { continue }
                await self.persistCurrentStateSnapshot(lastUpdateDate: Date())
            }
        }
    }

    private func syncPublishedSnapshot() async {
        let scalar = await trackingEngine.scalarSnapshot()
        applyScalarSnapshot(scalar)
        await syncCompletedRunsIfNeeded(version: scalar.completedRunsVersion)
        liveActivityService?.update(state: buildLiveActivityState())
    }

    private func applyScalarSnapshot(_ scalar: ScalarSnapshot) {
        if currentSpeed != scalar.currentSpeed {
            currentSpeed = scalar.currentSpeed
        }
        if currentAltitude != scalar.currentAltitude {
            currentAltitude = scalar.currentAltitude
        }
        if skiingMetrics != scalar.skiingMetrics {
            skiingMetrics = scalar.skiingMetrics
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
    }

    private func syncCompletedRunsIfNeeded(version: Int) async {
        guard version != lastSyncedRunsVersion else { return }
        completedRuns = await trackingEngine.fetchCompletedRuns()
        lastSyncedRunsVersion = version
    }

    private func appendCurveSample(point: FilteredTrackPoint, state: SpeedCurveState) {
        let timestamp = point.timestamp
        var didAppendSpeed = false
        var didAppendAltitude = false

        // Speed: append only when minimumSpacing has elapsed since the last buffered sample.
        let lastSpeed = speedSampleBuffer.last
        if lastSpeed == nil || timestamp.timeIntervalSince(lastSpeed!.time) >= Self.curveSampleIntervalSeconds {
            speedSampleBuffer.append(SpeedSample(
                time: timestamp,
                speed: max(point.estimatedSpeed, 0),
                state: state
            ))
            didAppendSpeed = true
        }

        // Altitude: same spacing rule, value pre-converted to display units.
        let displayAltitude = liveActivityUnitSystem == .imperial
            ? UnitConversion.metersToFeet(point.altitude)
            : point.altitude
        let lastAltitude = altitudeSampleBuffer.last
        if lastAltitude == nil || timestamp.timeIntervalSince(lastAltitude!.time) >= Self.curveSampleIntervalSeconds {
            altitudeSampleBuffer.append(AltitudeSample(
                time: timestamp,
                altitude: displayAltitude,
                state: state
            ))
            didAppendAltitude = true
        }

        if didAppendSpeed {
            speedSamples = speedSampleBuffer.elements
        }
        if didAppendAltitude {
            altitudeSamples = altitudeSampleBuffer.elements
        }
    }

    private func buildLiveActivityState() -> SnowlyActivityAttributes.ContentState {
        SnowlyActivityAttributes.ContentState(
            currentSpeed: currentSpeed,
            totalVertical: skiingMetrics.totalVertical,
            runCount: skiingMetrics.runCount,
            elapsedSeconds: Int(computeElapsedTime()),
            currentActivity: currentActivity.activityName,
            isPaused: state == .paused,
            maxSpeed: skiingMetrics.maxSpeed
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
            totalDistance: snapshot.skiingMetrics.totalDistance,
            totalVertical: snapshot.skiingMetrics.totalVertical,
            maxSpeed: snapshot.skiingMetrics.maxSpeed,
            runCount: snapshot.skiingMetrics.runCount,
            isActive: true,
            elapsedTime: computeElapsedTime(),
            completedRuns: snapshot.completedRuns.enumerated().map { index, run in
                PersistedCompletedRun(
                    startDate: run.startDate,
                    endDate: run.endDate,
                    distance: run.distance,
                    verticalDrop: run.verticalDrop,
                    maxSpeed: run.maxSpeed,
                    averageSpeed: run.averageSpeed,
                    activityType: run.activityType,
                    trackFilePath: index < snapshot.completedRunFilePaths.count
                        ? snapshot.completedRunFilePaths[index]
                        : nil
                )
            }
        )
        TrackingStatePersistence.save(state)
    }

    private func loadTrackData(for runStorage: [CompletedRunStorage]) async -> [MaterializedCompletedRun] {
        await Task.detached(priority: .utility) {
            func decodeNDJSON<T: Decodable>(from data: Data, as _: T.Type) -> [T]? {
                let lines = data.split(separator: 0x0A)
                guard !lines.isEmpty else { return [] }

                let decoder = JSONDecoder()
                var points: [T] = []
                points.reserveCapacity(lines.count)

                for line in lines where !line.isEmpty {
                    guard let point = try? decoder.decode(T.self, from: Data(line)) else {
                        return nil
                    }
                    points.append(point)
                }
                return points
            }

            func canonicalTrackData(from rawData: Data?) -> Data? {
                guard let rawData else { return nil }

                if let points = try? JSONDecoder().decode([TrackPoint].self, from: rawData) {
                    return try? JSONEncoder().encode(points)
                }

                if let points = decodeNDJSON(from: rawData, as: TrackPoint.self) {
                    return try? JSONEncoder().encode(points)
                }

                // Keep legacy filtered blobs readable during migration, but new runs
                // now canonicalize to raw TrackPoint arrays.
                if let points = try? JSONDecoder().decode([FilteredTrackPoint].self, from: rawData) {
                    return try? JSONEncoder().encode(points)
                }

                if let points = decodeNDJSON(from: rawData, as: FilteredTrackPoint.self) {
                    return try? JSONEncoder().encode(points)
                }

                return nil
            }

            return runStorage.map { storedRun in
                let rawTrackData: Data?
                if let embedded = storedRun.summary.trackData {
                    rawTrackData = embedded
                } else if let url = storedRun.trackFileURL {
                    rawTrackData = try? Data(contentsOf: url, options: .mappedIfSafe)
                } else {
                    rawTrackData = nil
                }

                return MaterializedCompletedRun(
                    summary: storedRun.summary,
                    trackData: canonicalTrackData(from: rawTrackData)
                )
            }
        }.value
    }

    private func restoreState(from persisted: PersistedTrackingState) {
        didRecoverSession = true
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
        skiingMetrics = SessionSkiingMetrics(
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount
        )

        let fileURLs = (persisted.completedRuns ?? []).map { run -> URL? in
            guard let path = run.trackFilePath else { return nil }
            return URL(fileURLWithPath: path)
        }
        let seed = TrackingEngine.Seed(
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            completedRuns: restoredRuns,
            completedRunFileURLs: fileURLs,
            runCount: runCount
        )
        trackingEngine = TrackingEngine(seed: seed)

        currentSpeed = 0
        currentActivity = .idle
        speedSampleBuffer.removeAll()
        altitudeSampleBuffer.removeAll()
        speedSamples = []
        altitudeSamples = []
        state = .paused
    }

    /// Returns the required dwell time for a state transition.
    /// `nonisolated` so TrackingEngine can call it without a MainActor hop.
    nonisolated static func dwellTimeForTransition(
        from current: DetectedActivity,
        to target: DetectedActivity,
        accelerated: Bool = false
    ) -> TimeInterval {
        let base: TimeInterval
        switch (current, target) {
        case (.skiing, .lift):
            base = SharedConstants.dwellTimeSkiingToLift
        case (.lift, .skiing):
            base = SharedConstants.dwellTimeLiftToSkiing
        case (.idle, .skiing):
            base = SharedConstants.dwellTimeIdleToSkiing
        case (.idle, .lift):
            base = SharedConstants.dwellTimeIdleToLift
        case (_, .walk):
            base = SharedConstants.dwellTimeAnyToWalk
        case (.walk, .skiing):
            base = SharedConstants.dwellTimeWalkToSkiing
        case (.walk, .lift):
            base = SharedConstants.dwellTimeWalkToLift
        default:
            base = 0
        }

        guard accelerated else { return base }

        switch (current, target) {
        case (.skiing, .lift):
            return min(base, 8)   // high-confidence lift entry: 8s floor (down from 12s)
        case (.lift, .skiing):
            return min(base, 4)
        case (.idle, .skiing):
            return min(base, 2)
        case (.idle, .lift):
            return min(base, 6)
        default:
            return base
        }
    }

    /// Pure function: applies dwell time hysteresis to raw activity detection.
    /// State only switches after the candidate activity persists for the required dwell time.
    /// `nonisolated` so TrackingEngine can call it without a MainActor hop.
    nonisolated static func applyDwellTime(
        rawActivity: DetectedActivity,
        currentActivity: DetectedActivity,
        candidateActivity: DetectedActivity?,
        candidateStartTime: Date?,
        timestamp: Date,
        accelerated: Bool = false
    ) -> (activity: DetectedActivity, candidate: DetectedActivity?, candidateStart: Date?) {
        if rawActivity == currentActivity {
            return (currentActivity, nil, nil)
        }

        if rawActivity == candidateActivity, let candidateStart = candidateStartTime {
            let required = dwellTimeForTransition(
                from: currentActivity,
                to: rawActivity,
                accelerated: accelerated
            )
            if timestamp.timeIntervalSince(candidateStart) >= required {
                return (rawActivity, nil, nil)
            }
            return (currentActivity, candidateActivity, candidateStartTime)
        }

        return (currentActivity, rawActivity, timestamp)
    }

    private func resetPublishedStats() {
        currentSpeed = 0
        currentAltitude = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        currentActivity = .idle
        runCount = 0
        completedRuns = []
        skiingMetrics = .zero
        speedSampleBuffer.removeAll()
        altitudeSampleBuffer.removeAll()
        speedSamples = []
        altitudeSamples = []

        totalPausedTime = 0
        pauseStartTime = nil
        idleSinceDate = nil
        lastSyncedRunsVersion = 0

        healthKitCoordinator.reset()
    }
}
