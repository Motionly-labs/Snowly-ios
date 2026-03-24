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

private enum PendingCompanionControl: Sendable, Equatable {
    case start
    case pause
    case resume
    case stop
}

private enum IndependentSyncStatus: Sendable, Equatable {
    case syncing
    case synced
    case failed
}

private enum WatchUITestScenario {
    case idle
    case active
    case paused
    case summary

    init(arguments: [String]) {
        if arguments.contains("-watch_ui_testing_summary") {
            self = .summary
        } else if arguments.contains("-watch_ui_testing_paused") {
            self = .paused
        } else if arguments.contains("-watch_ui_testing_active") {
            self = .active
        } else {
            self = .idle
        }
    }
}

// MARK: - WatchWorkoutManager

@Observable
@MainActor
final class WatchWorkoutManager: NSObject {
    private static let trackPointBatchSize = 200
    private static let microBatchSize = 10
    private static let heartRatePushInterval: TimeInterval = 2
    private static let controlRequestTimeout: Duration = .seconds(3)
    private static let transientStatusDuration: Duration = .seconds(2)

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
    var transientStatusMessage: String?
    var preferredUnitSystem: UnitSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
    var lastCompletedRun: WatchMessage.LastRunData?

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
    private var bufferedPoints: [TrackPoint] = []
    private var lastSentBatchEndIndex: Int = 0
    private var totalBufferedPointCount: Int = 0
    private var activeMode: WatchTrackingMode?
    private var lastHeartRatePushAt: Date?
    private var pendingControl: PendingCompanionControl?
    private var pendingControlTimeoutTask: Task<Void, Never>?
    private var transientStatusTask: Task<Void, Never>?
    private var lastKnownPhoneReachability: Bool?
    private var summaryMode: WatchTrackingMode?
    private var independentSyncStatus: IndependentSyncStatus?
    private var isUITestingInteractive = false

    var statusMessage: String? {
        if let pendingControl {
            return pendingStatusMessage(for: pendingControl)
        }
        return transientStatusMessage
    }

    var isStartPending: Bool {
        pendingControl == .start
    }

    var isCompanionControlPending: Bool {
        pendingControl != nil
    }

    var summarySyncMessage: String? {
        guard summaryMode == .independent, let independentSyncStatus else { return nil }

        switch independentSyncStatus {
        case .syncing:
            return String(localized: "watch_sync_pending")
        case .synced:
            return String(localized: "watch_sync_complete")
        case .failed:
            return String(localized: "watch_sync_failed")
        }
    }

    // MARK: - Setup

    func configure(
        connectivity: WatchConnectivityService,
        location: WatchLocationService
    ) {
        connectivityService = connectivity
        locationService = location
        lastKnownPhoneReachability = connectivity.isPhoneReachable

        connectivity.onMessageReceived = { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
        connectivity.onReachabilityChanged = { [weak self] isReachable in
            Task { @MainActor in
                self?.handleReachabilityChange(isReachable)
            }
        }
        connectivity.onApplicationContextReceived = { [weak self] context in
            Task { @MainActor in
                self?.handleApplicationContext(context)
            }
        }

        if let latestContext = connectivity.latestApplicationContext {
            handleApplicationContext(latestContext)
        }
    }

    @discardableResult
    func applyUITestingConfigurationIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard arguments.contains("-watch_ui_testing") else { return false }

        resetStats()
        clearPendingControl()
        clearTransientStatus()
        lastKnownPhoneReachability = false
        isUITestingInteractive = arguments.contains("-watch_ui_testing_interactive")

        switch WatchUITestScenario(arguments: arguments) {
        case .idle:
            activeMode = nil
            summaryMode = nil
            trackingState = .idle

        case .active:
            configureUITestWorkoutState(as: .active(mode: .independent))

        case .paused:
            configureUITestWorkoutState(as: .paused)

        case .summary:
            configureUITestWorkoutState(as: .summary)
            summaryMode = .independent
            independentSyncStatus = .synced
        }

        return true
    }

    // MARK: - Companion Mode

    func start() {
        guard pendingControl == nil else { return }

        if isUITestingInteractive {
            configureUITestWorkoutState(as: .active(mode: .independent))
            summaryMode = nil
            independentSyncStatus = nil
            sessionId = UUID()
            startDate = .now.addingTimeInterval(-elapsedTime)
            pauseDate = nil
            accumulatedPauseTime = 0
            WatchWidgetSharedStore.write(isTracking: true, runCount: runCount, sessionStart: startDate)
            return
        }

        if connectivityService?.isPhoneReachable == true {
            beginPendingControl(.start)
            connectivityService?.send(.requestStart)
        } else {
            startIndependent()
        }
    }

    func startCompanion() {
        resetStats()
        clearPendingControl()
        clearTransientStatus()
        activeMode = .companion
        summaryMode = nil
        trackingState = .active(mode: .companion)
        WatchWidgetSharedStore.write(isTracking: true, runCount: 0, sessionStart: .now)
        WatchHapticService.playStart()
    }

    // MARK: - Independent Mode

    func startIndependent() {
        resetStats()
        let currentSessionId = UUID()
        sessionId = currentSessionId
        startDate = .now
        activeMode = .independent
        summaryMode = nil
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
        WatchWidgetSharedStore.write(isTracking: true, runCount: 0, sessionStart: startDate)
        WatchHapticService.playStart()
    }

    // MARK: - Controls

    func pause() {
        guard case .active(let mode) = trackingState else { return }

        if mode == .companion {
            guard beginCompanionControl(.pause) else { return }
            connectivityService?.send(.requestPause)
        } else {
            pauseDate = .now
            timer?.invalidate()
            timer = nil
            workoutSession?.pause()
            trackingState = .paused
            WatchHapticService.playPause()
        }
    }

    func resume() {
        guard case .paused = trackingState else { return }

        if activeMode == .companion {
            guard beginCompanionControl(.resume) else { return }
            connectivityService?.send(.requestResume)
        } else {
            if let pauseStart = pauseDate {
                accumulatedPauseTime += Date.now.timeIntervalSince(pauseStart)
                pauseDate = nil
            }
            startTimer()
            workoutSession?.resume()
            trackingState = .active(mode: .independent)
            WatchHapticService.playResume()
        }
    }

    func stop() {
        switch trackingState {
        case .active, .paused:
            break
        default:
            return
        }

        if isUITestingInteractive {
            timer?.invalidate()
            timer = nil
            pauseDate = nil
            summaryMode = .independent
            independentSyncStatus = .synced
            trackingState = .summary
            WatchWidgetSharedStore.write(isTracking: false, runCount: 0, sessionStart: nil)
            return
        }

        if activeMode == .independent {
            stopIndependent()
            summaryMode = .independent
            trackingState = .summary
            WatchHapticService.playStop()
        } else {
            guard beginCompanionControl(.stop) else { return }
            connectivityService?.send(.requestStop)
        }
    }

    func dismiss() {
        clearPendingControl()
        clearTransientStatus()
        activeMode = nil
        summaryMode = nil
        independentSyncStatus = nil
        trackingState = .idle
        WatchWidgetSharedStore.write(isTracking: false, runCount: 0, sessionStart: nil)
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WatchMessage) {
        switch message {
        case .trackingStarted:
            if pendingControl == .resume || trackingState == .paused {
                completeCompanionResume()
            } else if pendingControl == .start || trackingState == .idle || trackingState == .summary {
                startCompanion()
            }

        case .trackingPaused:
            let confirmedPause = pendingControl == .pause
            if confirmedPause || isCompanionSessionContext {
                clearPendingControl()
                trackingState = .paused
                if confirmedPause {
                    WatchHapticService.playPause()
                }
            }

        case .trackingResumed:
            if pendingControl == .resume || trackingState == .paused {
                completeCompanionResume()
            }

        case .trackingStopped:
            let confirmedStop = pendingControl == .stop
            clearPendingControl()
            if confirmedStop || isCompanionSessionContext {
                summaryMode = .companion
                trackingState = .summary
                if confirmedStop {
                    WatchHapticService.playStop()
                }
            }

        case .liveUpdate(let data):
            updateFromLiveData(data)

        case .newPersonalBest(let metric, _):
            WatchHapticService.playPersonalBest()
            showTransientStatus(personalBestMessage(metric: metric))

        case .unitPreference(let unitPreference):
            preferredUnitSystem = unitPreference

        case .lastCompletedRun(let lastCompletedRun):
            let didAdvanceRun = lastCompletedRun != nil && self.lastCompletedRun != lastCompletedRun
            self.lastCompletedRun = lastCompletedRun
            if didAdvanceRun, isCompanionSessionContext {
                WatchHapticService.playNewRun()
                showTransientStatus(lastRunCompleteMessage(for: lastCompletedRun))
            }

        case .independentWorkoutImported(let importedSessionId):
            guard sessionId == importedSessionId else { break }
            independentSyncStatus = .synced
            showTransientStatus(String(localized: "watch_sync_complete"))

        case .independentWorkoutImportFailed(let failedSessionId):
            guard sessionId == failedSessionId else { break }
            independentSyncStatus = .failed
            showTransientStatus(String(localized: "watch_sync_failed"))
            WatchHapticService.playFailure()

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
        let inferredStart = Date.now.addingTimeInterval(-data.elapsedTime)
        WatchWidgetSharedStore.write(isTracking: true, runCount: data.runCount, sessionStart: inferredStart)
    }

    private func handleApplicationContext(_ context: WatchApplicationContext) {
        if let unitPreference = context.unitPreference {
            preferredUnitSystem = unitPreference
        }
        lastCompletedRun = context.lastCompletedRun
        if let liveData = context.liveData {
            updateFromLiveData(liveData)
        }

        applyCompanionTrackingStateFromContext(context.trackingState)
    }

    private func applyCompanionTrackingStateFromContext(_ trackingStateValue: String) {
        switch trackingStateValue {
        case "tracking":
            clearPendingControl()
            guard trackingState != .active(mode: .independent) else { return }
            trackingState = .active(mode: .companion)

        case "paused":
            clearPendingControl()
            guard trackingState != .active(mode: .independent) else { return }
            trackingState = .paused

        case "idle":
            let shouldShowSummary = pendingControl == .stop || isCompanionSessionContext
            clearPendingControl()
            guard shouldShowSummary else { return }
            summaryMode = .companion
            trackingState = .summary

        default:
            break
        }
    }

    private func beginCompanionControl(_ control: PendingCompanionControl) -> Bool {
        guard pendingControl == nil else { return false }
        guard connectivityService?.isPhoneReachable == true else {
            showTransientStatus(String(localized: "watch_status_phone_unreachable"))
            WatchHapticService.playFailure()
            return false
        }

        beginPendingControl(control)
        return true
    }

    private func beginPendingControl(_ control: PendingCompanionControl) {
        clearTransientStatus()
        pendingControlTimeoutTask?.cancel()
        pendingControl = control
        pendingControlTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.controlRequestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.handlePendingControlTimeout(control)
            }
        }
    }

    private func completeCompanionResume() {
        let confirmedResume = pendingControl == .resume
        clearPendingControl()
        trackingState = .active(mode: .companion)
        if confirmedResume {
            WatchHapticService.playResume()
        }
    }

    private func handlePendingControlTimeout(_ control: PendingCompanionControl) {
        guard pendingControl == control else { return }
        clearPendingControl()
        showTransientStatus(String(localized: "watch_status_phone_no_response"))
        WatchHapticService.playFailure()
    }

    private func clearPendingControl() {
        pendingControlTimeoutTask?.cancel()
        pendingControlTimeoutTask = nil
        pendingControl = nil
    }

    private func showTransientStatus(_ message: String) {
        transientStatusTask?.cancel()
        transientStatusMessage = message
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(for: Self.transientStatusDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.transientStatusMessage = nil
                self?.transientStatusTask = nil
            }
        }
    }

    private func clearTransientStatus() {
        transientStatusTask?.cancel()
        transientStatusTask = nil
        transientStatusMessage = nil
    }

    private func handleReachabilityChange(_ isReachable: Bool) {
        let previous = lastKnownPhoneReachability
        lastKnownPhoneReachability = isReachable

        guard let previous, previous != isReachable else { return }

        if !isReachable {
            if pendingControl != nil {
                clearPendingControl()
            }

            if isCompanionSessionActive {
                escalateToIndependent()
            } else {
                showTransientStatus(String(localized: "watch_status_phone_unreachable"))
                WatchHapticService.playFailure()
            }
            return
        }

        guard isCompanionSessionContext else { return }
        showTransientStatus(String(localized: "watch_status_phone_connected"))
    }

    /// Whether the Watch is in an active or paused companion session
    /// (excludes pending-only states).
    private var isCompanionSessionActive: Bool {
        switch trackingState {
        case .active(let mode):
            return mode == .companion
        case .paused:
            return activeMode == .companion
        default:
            return false
        }
    }

    /// Transitions a companion session to independent mode so tracking
    /// continues even when the iPhone becomes unreachable.
    /// Preserves accumulated stats; starts local GPS, HealthKit, and timer.
    private func escalateToIndependent() {
        let wasActive: Bool
        switch trackingState {
        case .active(.companion):
            wasActive = true
        case .paused where activeMode == .companion:
            wasActive = false
        default:
            return
        }

        let currentSessionId = UUID()
        sessionId = currentSessionId
        // Back-date so the timer continues from the current elapsed time.
        startDate = Date.now.addingTimeInterval(-elapsedTime)
        accumulatedPauseTime = 0
        activeMode = .independent

        startHealthKitWorkout()
        connectivityService?.send(.watchWorkoutStarted(sessionId: currentSessionId))

        if wasActive {
            pauseDate = nil
            trackingState = .active(mode: .independent)
            locationService?.requestAuthorization()
            locationService?.startTracking { [weak self] point in
                Task { @MainActor in
                    self?.processTrackPoint(point)
                }
            }
            startTimer()
        } else {
            pauseDate = Date.now
            trackingState = .paused
            workoutSession?.pause()
        }

        showTransientStatus(String(localized: "watch_status_switched_independent"))
    }

    private var isCompanionSessionContext: Bool {
        if pendingControl != nil {
            return true
        }

        switch trackingState {
        case .active(let mode):
            return mode == .companion
        case .paused:
            return activeMode == .companion
        case .idle, .summary:
            return false
        }
    }

    private func pendingStatusMessage(for control: PendingCompanionControl) -> String {
        switch control {
        case .start:
            return String(localized: "watch_status_starting_phone")
        case .pause:
            return String(localized: "watch_status_pausing_phone")
        case .resume:
            return String(localized: "watch_status_resuming_phone")
        case .stop:
            return String(localized: "watch_status_stopping_phone")
        }
    }

    private func personalBestMessage(metric: String) -> String {
        let trimmedMetric = metric.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMetric.isEmpty else { return String(localized: "watch_status_personal_best") }

        let format = String(localized: "watch_status_personal_best_metric")
        return String(format: format, locale: Locale.current, trimmedMetric)
    }

    private func lastRunCompleteMessage(for lastCompletedRun: WatchMessage.LastRunData?) -> String {
        guard let lastCompletedRun else {
            return String(localized: "watch_last_run_title")
        }

        let format = String(localized: "watch_status_last_run_complete_format")
        return String(format: format, locale: Locale.current, lastCompletedRun.runNumber)
    }

    // MARK: - Independent Tracking

    private func processTrackPoint(_ point: TrackPoint) {
        bufferedPoints.append(point)
        totalBufferedPointCount += 1
        // Use raw CLLocation speed for immediate display; phone pushes back precise values.
        if point.speed >= 0 {
            currentSpeed = point.speed
            maxSpeed = max(maxSpeed, point.speed)
        }
        sendMicroBatchIfNeeded()
    }

    private func sendMicroBatchIfNeeded() {
        let pending = bufferedPoints.count - lastSentBatchEndIndex
        guard pending >= Self.microBatchSize,
              connectivityService?.isPhoneReachable == true else { return }
        let end = bufferedPoints.endIndex
        connectivityService?.send(.watchTrackPoints(Array(bufferedPoints[lastSentBatchEndIndex..<end])))
        // Trim already-sent prefix to prevent O(n) memory growth over the session.
        // totalBufferedPointCount preserves the true count for the workout summary.
        bufferedPoints.removeFirst(end)
        lastSentBatchEndIndex = 0
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
            showTransientStatus(String(localized: "watch_status_hk_unavailable"))
        }
    }

    private func stopIndependent() {
        timer?.invalidate()
        timer = nil
        locationService?.stopTracking()
        independentSyncStatus = .syncing

        let endDate = Date.now
        if let sessionId, let startDate {
            connectivityService?.send(.watchWorkoutSummary(.init(
                sessionId: sessionId,
                startDate: startDate,
                endDate: endDate,
                trackPointCount: totalBufferedPointCount
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

        // Flush any unsent points then signal end.
        // After micro-batch trimming, bufferedPoints only contains the unsent tail.
        if !bufferedPoints.isEmpty {
            var start = 0
            while start < bufferedPoints.count {
                let end = min(start + Self.trackPointBatchSize, bufferedPoints.count)
                connectivityService?.send(.watchTrackPoints(Array(bufferedPoints[start..<end])))
                start = end
            }
        }
        connectivityService?.send(.watchWorkoutEnded)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
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
        clearPendingControl()
        clearTransientStatus()
        currentSpeed = 0
        maxSpeed = 0
        totalDistance = 0
        totalVertical = 0
        runCount = 0
        elapsedTime = 0
        currentHeartRate = 0
        averageHeartRate = 0
        lastCompletedRun = nil
        sessionId = nil
        startDate = nil
        pauseDate = nil
        accumulatedPauseTime = 0
        bufferedPoints = []
        lastSentBatchEndIndex = 0
        totalBufferedPointCount = 0
        lastHeartRatePushAt = nil
        independentSyncStatus = nil
        isUITestingInteractive = false
    }

    private func configureUITestWorkoutState(as state: WatchTrackingState) {
        activeMode = .independent
        trackingState = state
        currentSpeed = 12.3
        maxSpeed = 24.8
        totalDistance = 5_420
        totalVertical = 1_180
        runCount = 6
        elapsedTime = 2_145
        currentHeartRate = 142
        averageHeartRate = 136
        preferredUnitSystem = .metric
        lastCompletedRun = .init(
            runNumber: 6,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_180),
            distance: 1_840,
            verticalDrop: 390,
            maxSpeed: 24.8,
            averageSpeed: 15.6
        )
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
