//
//  SnowlyApp.swift
//  Snowly
//
//  Entry point. Creates all services at app level and injects
//  them via @Environment so they survive view lifecycle changes.
//

import SwiftUI
import SwiftData
import UIKit
import WidgetKit
import CoreLocation

/// Holds all app-level services with stable identity.
/// Using a class (not @State in App struct) ensures services
/// are created once and the same instances are injected everywhere.
@Observable
@MainActor
final class AppServices {
    let locationService: LocationTrackingService
    let motionService: MotionDetectionService
    let batteryService: BatteryMonitorService
    let healthKitService: HealthKitService
    let trackingService: SessionTrackingService
    let skiMapCacheService: SkiMapCacheService
    let syncMonitorService: SyncMonitorService
    let musicPlayerService: MusicPlayerService
    let phoneConnectivityService: PhoneConnectivityService
    let watchBridgeService: WatchBridgeService
    let crewAPIClient: CrewAPIClient
    let crewService: CrewService
    let liveActivityService: LiveActivityService
    let crewPinNotificationService: CrewPinNotificationService
    let skiDataUploadService: SkiDataUploadService
    let gearReminderService: GearReminderService

    init() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let healthKit = HealthKitService()
        let liveActivity = LiveActivityService()

        self.locationService = location
        self.motionService = motion
        self.batteryService = battery
        self.healthKitService = healthKit
        self.liveActivityService = liveActivity

        let tracking = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery,
            healthKitService: healthKit,
            liveActivityService: liveActivity
        )
        self.trackingService = tracking

        self.skiMapCacheService = SkiMapCacheService()
        self.syncMonitorService = SyncMonitorService()
        self.musicPlayerService = MusicPlayerService()

        let phoneConnectivity = PhoneConnectivityService()
        self.phoneConnectivityService = phoneConnectivity
        self.watchBridgeService = WatchBridgeService(
            connectivityService: phoneConnectivity,
            trackingService: tracking,
            batteryService: battery
        )

        let crewAPI = CrewAPIClient()
        self.crewAPIClient = crewAPI
        let crew = CrewService(
            apiClient: crewAPI,
            locationService: location
        )
        self.crewService = crew

        self.crewPinNotificationService = CrewPinNotificationService()

        let skiDataAPI = SkiDataAPIClient()
        self.skiDataUploadService = SkiDataUploadService(apiClient: skiDataAPI)

        self.gearReminderService = GearReminderService()
    }
}

@main
struct SnowlyApp: App {

    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) var appDelegate

    let modelContainer: ModelContainer
    @State private var services = AppServices()
    @State private var deepLinkJoinError: String?
    @Environment(\.scenePhase) private var scenePhase
    private static var cloudContainerIdentifier: String {
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "iCloud.\(bundleIdentifier)"
        }
        return "iCloud.Snowly"
    }

    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        let launchArgumentSet = Set(launchArguments)
        let isUITesting = launchArgumentSet.contains("-ui_testing")
        let isTesting = isUITesting
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        let shouldUseCloudKit = !isTesting && SnowlyApp.canUseCloudKitAtLaunch

        do {
            let container: ModelContainer

            if shouldUseCloudKit {
                do {
                    container = try SnowlyApp.makeModelContainer(
                        isStoredInMemoryOnly: false,
                        cloudEnabled: true
                    )
                } catch {
                    print("CloudKit unavailable at launch. Falling back to local store: \(error)")
                    container = try SnowlyApp.makeModelContainer(
                        isStoredInMemoryOnly: false,
                        cloudEnabled: false
                    )
                }
            } else {
                container = try SnowlyApp.makeModelContainer(
                    isStoredInMemoryOnly: isTesting,
                    cloudEnabled: false
                )
            }

            SnowlyApp.seedUITestDataIfNeeded(
                in: container,
                launchArguments: launchArgumentSet
            )
            FixtureReplayService.replayFixtureDataIfNeeded(
                in: container,
                launchArguments: launchArguments
            )
            modelContainer = container
        } catch {
            if let recoveredContainer = SnowlyApp.attemptPersistentStoreRecoveryIfNeeded(
                after: error,
                isTesting: isTesting,
                launchArguments: launchArguments
            ) {
                modelContainer = recoveredContainer
                return
            }

            do {
                print("Persistent store unavailable. Using in-memory fallback: \(error)")
                let inMemoryContainer = try SnowlyApp.makeModelContainer(
                    isStoredInMemoryOnly: true,
                    cloudEnabled: false
                )
                SnowlyApp.seedUITestDataIfNeeded(
                    in: inMemoryContainer,
                    launchArguments: launchArgumentSet
                )
                FixtureReplayService.replayFixtureDataIfNeeded(
                    in: inMemoryContainer,
                    launchArguments: launchArguments
                )
                modelContainer = inMemoryContainer
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environment(services.locationService)
                .environment(services.motionService)
                .environment(services.batteryService)
                .environment(services.healthKitService)
                .environment(services.trackingService)
                .environment(services.skiMapCacheService)
                .environment(services.syncMonitorService)
                .environment(services.musicPlayerService)
                .environment(services.phoneConnectivityService)
                .environment(services.watchBridgeService)
                .environment(services.crewService)
                .environment(services.skiDataUploadService)
                .environment(services.gearReminderService)

                .environment(services.crewPinNotificationService)
                .onChange(of: scenePhase) { _, newPhase in
                    services.crewPinNotificationService.scenePhase = newPhase
                    if newPhase == .active {
                        services.phoneConnectivityService.refreshWatchState()
                    }
                }
                .onChange(of: services.crewService.activeCrew?.id) { _, crewId in
                    guard crewId != nil else { return }
                    services.crewPinNotificationService.requestPermissionIfNeeded()
                }
                .onChange(of: services.crewService.latestReceivedPin) { _, pin in
                    guard let pin else { return }
                    services.crewPinNotificationService.handleNewPin(pin, scenePhase: scenePhase)
                    services.crewService.consumeLatestReceivedPin()
                }
                .onChange(of: services.crewService.latestMembershipEvent) { _, event in
                    guard let event else { return }
                    services.crewPinNotificationService.handleMembershipEvent(event, scenePhase: scenePhase)
                    services.crewService.consumeLatestMembershipEvent()
                }
                .onChange(of: services.watchBridgeService.completedIndependentWorkout?.summary.sessionId) { _, _ in
                    guard let workout = services.watchBridgeService.completedIndependentWorkout else { return }
                    SnowlyApp.persistImportedWatchWorkout(workout, in: modelContainer.mainContext)
                    services.watchBridgeService.consumeCompletedIndependentWorkout()
                }
                .onChange(of: QuickActionState.shared.pending) { _, pending in
                    guard pending else { return }
                    QuickActionState.shared.pending = false
                    services.trackingService.quickStartPending = true
                }
                .onChange(of: TrackingEnabledIntentState.shared.pendingValue) { _, pendingValue in
                    guard let shouldTrack = pendingValue else { return }
                    TrackingEnabledIntentState.shared.pendingValue = nil

                    if shouldTrack {
                        services.trackingService.quickStartPending = true
                        return
                    }

                    guard services.trackingService.state != .idle else { return }

                    Task { @MainActor in
                        await services.trackingService.stopTracking()
                        await services.trackingService.finalizeHealthKitWorkout()
                        let resortCoordinate = services.locationService.currentLocation
                            ?? services.locationService.recentTrackPointsSnapshot().last.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }
                        let resort = await ResortResolver.resolveCurrentResort(
                            from: services.skiMapCacheService,
                            using: resortCoordinate,
                            in: modelContainer.mainContext
                        )
                        await services.trackingService.saveSession(to: modelContainer.mainContext, resort: resort)
                    }
                }
                .onChange(of: TogglePauseState.shared.pending) { _, pending in
                    guard pending else { return }
                    TogglePauseState.shared.pending = false
                    Task {
                        if services.trackingService.state == .paused {
                            await services.trackingService.resumeTracking()
                        } else if services.trackingService.state == .tracking {
                            await services.trackingService.pauseTracking()
                        }
                    }
                }
                .onChange(of: services.trackingService.state) { _, _ in
                    if #available(iOS 18.0, *) {
                        ControlCenter.shared.reloadControls(ofKind: "com.snowly.start-tracking-control")
                    }
                }
                .task {
                    SnowlyApp.restoreActiveServer(
                        in: modelContainer.mainContext,
                        crewAPIClient: services.crewAPIClient,
                        skiDataUploadService: services.skiDataUploadService
                    )
                }
                .onOpenURL { url in
                    guard let deepLink = DeepLinkHandler.parse(url: url) else { return }
                    switch deepLink {
                    case .crewJoin(let token):
                        Task {
                            do {
                                try await services.crewService.joinCrew(token: token)
                            } catch {
                                deepLinkJoinError = error.localizedDescription
                            }
                        }
                    case .startTracking:
                        services.trackingService.quickStartPending = true
                    }
                }
                .alert(String(localized: "alert.crew_join_failed_title"), isPresented: Binding(
                    get: { deepLinkJoinError != nil },
                    set: { if !$0 { deepLinkJoinError = nil } }
                )) {
                    Button(String(localized: "common_ok"), role: .cancel) {
                        deepLinkJoinError = nil
                    }
                } message: {
                    if let message = deepLinkJoinError {
                        Text(message)
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private static func restoreActiveServer(
        in context: ModelContext,
        crewAPIClient: CrewAPIClient,
        skiDataUploadService: SkiDataUploadService
    ) {
        let descriptor = FetchDescriptor<ServerProfile>(
            predicate: #Predicate<ServerProfile> { $0.isActive }
        )
        guard let activeServer = (try? context.fetch(descriptor))?.first,
              let apiBaseURL = activeServer.apiBaseURL else {
            return
        }
        crewAPIClient.updateBaseURL(apiBaseURL)
        skiDataUploadService.updateBaseURL(apiBaseURL)
    }

    private static var canUseCloudKitAtLaunch: Bool {
#if targetEnvironment(simulator)
        false
#else
        FileManager.default.ubiquityIdentityToken != nil
#endif
    }

    private static func attemptPersistentStoreRecoveryIfNeeded(
        after error: Error,
        isTesting: Bool,
        launchArguments: [String]
    ) -> ModelContainer? {
#if targetEnvironment(simulator)
        guard !isTesting else { return nil }
        let launchArgumentSet = Set(launchArguments)

        do {
            print("Simulator persistent store load failed. Attempting store reset recovery: \(error)")
            try resetPersistentStoreFiles()
            let recoveredContainer = try makeModelContainer(
                isStoredInMemoryOnly: false,
                cloudEnabled: false
            )
            seedUITestDataIfNeeded(
                in: recoveredContainer,
                launchArguments: launchArgumentSet
            )
            FixtureReplayService.replayFixtureDataIfNeeded(
                in: recoveredContainer,
                launchArguments: launchArguments
            )
            print("Recovered persistent store by resetting incompatible simulator files.")
            return recoveredContainer
        } catch {
            print("Persistent store recovery failed: \(error)")
            return nil
        }
#else
        return nil
#endif
    }

    private static func resetPersistentStoreFiles() throws {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        try fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let filenames = [
            "Synced.store",
            "Synced.store-shm",
            "Synced.store-wal",
            "Local.store",
            "Local.store-shm",
            "Local.store-wal",
        ]

        for filename in filenames {
            let fileURL = appSupportURL.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            try fileManager.removeItem(at: fileURL)
        }
    }

    fileprivate static func makeModelContainer(
        isStoredInMemoryOnly: Bool,
        cloudEnabled: Bool
    ) throws -> ModelContainer {
        let syncedSchema = Schema([
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
        ])
        let syncedConfig = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: cloudEnabled ? .private(cloudContainerIdentifier) : .none
        )

        let localSchema = Schema([DeviceSettings.self, ServerProfile.self])
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: SkiSession.self, SkiRun.self, Resort.self,
                 GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
                 DeviceSettings.self, ServerProfile.self,
            migrationPlan: SnowlyMigrationPlan.self,
            configurations: syncedConfig, localConfig
        )
    }

    @MainActor
    private static func persistImportedWatchWorkout(
        _ workout: ImportedWatchWorkout,
        in context: ModelContext
    ) {
        let sessionId = workout.summary.sessionId
        var descriptor = FetchDescriptor<SkiSession>(
            predicate: #Predicate<SkiSession> { session in
                session.id == sessionId
            }
        )
        descriptor.fetchLimit = 1

        if !((try? context.fetch(descriptor)) ?? []).isEmpty {
            return
        }

        let completedRuns = buildCompletedRuns(from: workout.trackPoints)
        let skiingRuns = completedRuns.filter { $0.activityType == .skiing }
        let skiingDistance = skiingRuns.reduce(0.0) { $0 + $1.distance }
        let skiingVertical = skiingRuns.reduce(0.0) { $0 + $1.verticalDrop }
        let skiingMaxSpeed = skiingRuns.map(\.maxSpeed).max() ?? 0
        let skiingRunCount = skiingRuns.count
        let lockerAssets = fetchLockerAssets(in: context)
        let session = SkiSession(
            id: sessionId,
            startDate: workout.summary.startDate,
            endDate: workout.summary.endDate,
            totalDistance: skiingDistance,
            totalVertical: skiingVertical,
            maxSpeed: skiingMaxSpeed,
            runCount: max(
                workout.summary.runCount,
                skiingRunCount
            )
        )
        session.applyGearSnapshot(
            from: fetchActiveGearSetup(in: context),
            lockerAssets: lockerAssets
        )
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

        var profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        profileDescriptor.fetchLimit = 1
        if let profile = (try? context.fetch(profileDescriptor))?.first {
            let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)
            if update.hasUpdates {
                StatsService.applyPersonalBestUpdate(update, to: profile)
            }
        }

        try? context.save()
    }

    @MainActor
    private static func fetchActiveGearSetup(in context: ModelContext) -> GearSetup? {
        let activeDescriptor = FetchDescriptor<GearSetup>(
            predicate: #Predicate<GearSetup> { $0.isActive },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        if let active = (try? context.fetch(activeDescriptor))?.first {
            return active
        }

        var fallbackDescriptor = FetchDescriptor<GearSetup>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        fallbackDescriptor.fetchLimit = 1
        return (try? context.fetch(fallbackDescriptor))?.first
    }

    @MainActor
    private static func fetchLockerAssets(in context: ModelContext) -> [GearAsset] {
        let descriptor = FetchDescriptor<GearAsset>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    /// Segments track points into completed runs with synchronous track data encoding.
    /// Does not use SegmentFinalizationService (which encodes asynchronously) so that
    /// callers relying on trackData being populated immediately (e.g. fixture seeding,
    /// HealthKit import) get valid data without requiring an event-loop yield.
    private static func buildCompletedRuns(from trackPoints: [TrackPoint]) -> [CompletedRunData] {
        let sortedPoints = trackPoints.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else { return [] }

        var gpsFilter = GPSKalmanFilter()
        var recentPoints: [FilteredTrackPoint] = []
        var currentActivity: DetectedActivity = .idle
        var candidateActivity: DetectedActivity?
        var candidateStartTime: Date?

        var currentSegmentType: RunActivityType?
        var currentSegmentFilteredPoints: [FilteredTrackPoint] = []
        var lastActiveTime: Date?
        var result: [CompletedRunData] = []

        func finalizeSegment() {
            guard let segType = currentSegmentType, !currentSegmentFilteredPoints.isEmpty else { return }
            if let filteredRun = FixtureReplayService.buildCompletedRunData(
                activityType: segType,
                points: currentSegmentFilteredPoints
            ) {
                let filteredTrackData = try? JSONEncoder().encode(currentSegmentFilteredPoints)
                result.append(
                    CompletedRunData(
                        startDate: filteredRun.startDate,
                        endDate: filteredRun.endDate,
                        distance: filteredRun.distance,
                        verticalDrop: filteredRun.verticalDrop,
                        maxSpeed: filteredRun.maxSpeed,
                        averageSpeed: filteredRun.averageSpeed,
                        activityType: filteredRun.activityType,
                        trackData: filteredTrackData
                    )
                )
            }
            currentSegmentType = nil
            currentSegmentFilteredPoints = []
            lastActiveTime = nil
        }

        for rawPoint in sortedPoints {
            let filteredPoint = gpsFilter.update(point: rawPoint)
            let rawActivity = RunDetectionService.detect(
                point: filteredPoint,
                recentPoints: recentPoints,
                previousActivity: currentActivity
            )
            recentPoints.append(filteredPoint)
            RecentTrackWindow.trimFilteredPoints(&recentPoints, relativeTo: filteredPoint.timestamp)
            let dwellResult = SessionTrackingService.applyDwellTime(
                rawActivity: rawActivity,
                currentActivity: currentActivity,
                candidateActivity: candidateActivity,
                candidateStartTime: candidateStartTime,
                timestamp: filteredPoint.timestamp
            )
            currentActivity = dwellResult.activity
            candidateActivity = dwellResult.candidate
            candidateStartTime = dwellResult.candidateStart

            let targetType: RunActivityType?
            switch currentActivity {
            case .skiing:    targetType = .skiing
            case .lift: targetType = .lift
            case .walk:      targetType = .walk
            case .idle:      targetType = nil
            }

            if let targetType {
                if currentSegmentType != targetType {
                    finalizeSegment()
                    currentSegmentType = targetType
                    currentSegmentFilteredPoints = [filteredPoint]
                } else {
                    currentSegmentFilteredPoints.append(filteredPoint)
                }
                lastActiveTime = filteredPoint.timestamp
            } else if !currentSegmentFilteredPoints.isEmpty,
                      let lastActive = lastActiveTime,
                      RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: filteredPoint.timestamp) {
                finalizeSegment()
            }
        }

        finalizeSegment()
        return result
    }

    private static func seedUITestDataIfNeeded(
        in container: ModelContainer,
        launchArguments: Set<String>
    ) {
        guard launchArguments.contains("-ui_testing") else { return }

        let context = container.mainContext

        if launchArguments.contains("-ui_testing_skip_onboarding") {
            let profileDescriptor = FetchDescriptor<UserProfile>()
            let existingProfiles = (try? context.fetch(profileDescriptor)) ?? []

            if existingProfiles.isEmpty {
                context.insert(UserProfile(
                    displayName: "UI Test",
                    preferredUnits: .metric
                ))
            }

            let settingsDescriptor = FetchDescriptor<DeviceSettings>()
            let existingSettings = (try? context.fetch(settingsDescriptor)) ?? []

            if existingSettings.isEmpty {
                context.insert(DeviceSettings(hasCompletedOnboarding: true))
            } else {
                existingSettings.first?.hasCompletedOnboarding = true
            }
        }
    }
}

@MainActor
private struct SnowlyAppPreviewHost: View {
    let modelContainer: ModelContainer
    @State private var services = AppServices()

    init() {
        do {
            modelContainer = try SnowlyApp.makeModelContainer(
                isStoredInMemoryOnly: true,
                cloudEnabled: false
            )
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }

    var body: some View {
        RootView()
            .environment(services.locationService)
            .environment(services.motionService)
            .environment(services.batteryService)
            .environment(services.healthKitService)
            .environment(services.trackingService)
            .environment(services.skiMapCacheService)
            .environment(services.syncMonitorService)
            .environment(services.musicPlayerService)
            .environment(services.phoneConnectivityService)
            .environment(services.watchBridgeService)
            .environment(services.crewService)
            .environment(services.crewPinNotificationService)
            .modelContainer(modelContainer)
    }
}

#Preview("Snowly App Root") {
    SnowlyAppPreviewHost()
}
