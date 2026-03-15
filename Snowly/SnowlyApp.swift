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
    let locationChannelService: LocationChannelService
    let skiSessionChannelService: SkiSessionChannelService

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

        let locationChannel = LocationChannelService()
        self.locationChannelService = locationChannel

        let skiSessionChannel = SkiSessionChannelService()
        self.skiSessionChannelService = skiSessionChannel

        let crew = CrewService(
            apiClient: crewAPI,
            locationService: location,
            locationChannelService: locationChannel
        )
        self.crewService = crew

        self.crewPinNotificationService = CrewPinNotificationService()

        let skiDataAPI = SkiDataAPIClient()
        self.skiDataUploadService = SkiDataUploadService(
            apiClient: skiDataAPI,
            channelService: skiSessionChannel
        )

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
    private static let storeCompatibilityStampKey = "snowly_store_compatibility_stamp"
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

        // Pre-flight: reset incompatible store files before SwiftData can abort.
        // If stores were reset, disable CloudKit for this launch to avoid
        // the mirroring delegate aborting on incompatible remote records.
        var shouldSkipCloudKitForLaunch = false
        if !isTesting {
            shouldSkipCloudKitForLaunch = SnowlyApp.preparePersistentStoresForLaunch()
        }

        let shouldUseCloudKit = !isTesting && !shouldSkipCloudKitForLaunch && SnowlyApp.canUseCloudKitAtLaunch

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

#if DEBUG
            SnowlyApp.seedUITestDataIfNeeded(
                in: container,
                launchArguments: launchArgumentSet
            )
            FixtureReplayService.replayFixtureDataIfNeeded(
                in: container,
                launchArguments: launchArguments
            )
#endif
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
#if DEBUG
                SnowlyApp.seedUITestDataIfNeeded(
                    in: inMemoryContainer,
                    launchArguments: launchArgumentSet
                )
                FixtureReplayService.replayFixtureDataIfNeeded(
                    in: inMemoryContainer,
                    launchArguments: launchArguments
                )
#endif
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
                    let importResult = SnowlyApp.persistImportedWatchWorkout(
                        workout,
                        in: modelContainer.mainContext
                    )
                    switch importResult {
                    case .imported(let personalBestUpdate):
                        services.phoneConnectivityService.send(
                            .independentWorkoutImported(sessionId: workout.summary.sessionId)
                        )
                        if let personalBestUpdate,
                           let notification = StatsService.watchPersonalBestNotification(for: personalBestUpdate) {
                            services.phoneConnectivityService.send(.newPersonalBest(
                                metric: notification.metric,
                                value: notification.value
                            ))
                        }
                    case .alreadyImported:
                        services.phoneConnectivityService.send(
                            .independentWorkoutImported(sessionId: workout.summary.sessionId)
                        )
                    case .failed:
                        services.phoneConnectivityService.send(
                            .independentWorkoutImportFailed(sessionId: workout.summary.sessionId)
                        )
                    }
                    services.watchBridgeService.consumeCompletedIndependentWorkout()
                }
                .onChange(of: services.trackingService.lastSavedSessionOutcome?.sessionId) { _, _ in
                    guard let savedOutcome = services.trackingService.lastSavedSessionOutcome,
                          let personalBestUpdate = savedOutcome.personalBestUpdate,
                          let notification = StatsService.watchPersonalBestNotification(for: personalBestUpdate) else {
                        return
                    }
                    services.phoneConnectivityService.send(.newPersonalBest(
                        metric: notification.metric,
                        value: notification.value
                    ))
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
        guard !isTesting else { return nil }
        guard !hasMigrationStages else {
            print("Persistent store load failed with migration stages present. Skipping destructive store reset: \(error)")
            return nil
        }
        let launchArgumentSet = Set(launchArguments)

        do {
            print("Persistent store load failed. Attempting store reset recovery: \(error)")
            try resetPersistentStoreFiles()
            let recoveredContainer = try makeModelContainer(
                isStoredInMemoryOnly: false,
                cloudEnabled: false
            )
#if DEBUG
            seedUITestDataIfNeeded(
                in: recoveredContainer,
                launchArguments: launchArgumentSet
            )
            FixtureReplayService.replayFixtureDataIfNeeded(
                in: recoveredContainer,
                launchArguments: launchArguments
            )
#endif
            print("Recovered persistent store by resetting incompatible store files.")
            return recoveredContainer
        } catch {
            print("Persistent store recovery failed: \(error)")
            return nil
        }
    }

    /// Pre-flight store handling before SwiftData opens SQLite files.
    ///
    /// If migration stages exist, preserve the stores and let SwiftData migrate.
    /// If no migration stages exist, treat an app-bundle change as incompatible
    /// and reset the existing stores once before opening them.
    /// Returns `true` when CloudKit should be skipped for this launch.
    private static func preparePersistentStoresForLaunch() -> Bool {
        // Ensure Application Support directory exists before SwiftData tries to create store files.
        // On first install the directory is absent, which causes verbose CoreData recovery noise.
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        let currentStamp = currentStoreCompatibilityStamp
        let storedStamp = UserDefaults.standard.string(forKey: storeCompatibilityStampKey)
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: storedStamp,
            currentStamp: currentStamp,
            storeFilesExist: storeFilesExist(),
            hasMigrationStages: hasMigrationStages
        )

        if decision.shouldResetStores {
            print("Persistent store compatibility changed without migration stages. Resetting existing stores before launch.")
            try? resetPersistentStoreFiles()
        } else if storedStamp != nil, storedStamp != currentStamp {
            print("Persistent store compatibility stamp updated (\(storedStamp ?? "") -> \(currentStamp)). SwiftData migration will handle the upgrade.")
        }

        UserDefaults.standard.set(currentStamp, forKey: storeCompatibilityStampKey)
        return decision.shouldSkipCloudKit
    }

    private static var hasMigrationStages: Bool {
        !SnowlyMigrationPlan.stages.isEmpty
    }

    private static var currentStoreCompatibilityStamp: String {
        if hasMigrationStages {
            return "migration:\(currentMigrationSchemaStamp)"
        }
        return "reset-on-bundle-change:\(currentBundleFingerprint)"
    }

    private static var currentMigrationSchemaStamp: String {
        SnowlyMigrationPlan.schemas
            .map { $0.versionIdentifier }
            .map { version in
                [version.major, version.minor, version.patch]
                    .map(String.init)
                    .joined(separator: ".")
            }
            .joined(separator: "->")
    }

    private static var currentBundleFingerprint: String {
        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let modificationDate = bundleContentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(marketingVersion)-\(buildVersion)-\(Int(modificationDate))"
    }

    private static var bundleContentModificationDate: Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]

        if let date = try? Bundle.main.bundleURL.resourceValues(forKeys: keys).contentModificationDate {
            return date
        }

        if let executableURL = Bundle.main.executableURL,
           let date = try? executableURL.resourceValues(forKeys: keys).contentModificationDate {
            return date
        }

        return nil
    }

    private static func storeFilesExist() -> Bool {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return false }

        let storeNames = ["Synced.store", "Local.store"]
        return storeNames.contains { name in
            FileManager.default.fileExists(atPath: appSupportURL.appendingPathComponent(name).path)
        }
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
    private enum PersistImportedWatchWorkoutResult {
        case imported(personalBestUpdate: StatsService.PersonalBestUpdate?)
        case alreadyImported
        case failed
    }

    @MainActor
    private static func persistImportedWatchWorkout(
        _ workout: ImportedWatchWorkout,
        in context: ModelContext
    ) -> PersistImportedWatchWorkoutResult {
        let sessionId = workout.summary.sessionId
        var descriptor = FetchDescriptor<SkiSession>(
            predicate: #Predicate<SkiSession> { session in
                session.id == sessionId
            }
        )
        descriptor.fetchLimit = 1

        if !((try? context.fetch(descriptor)) ?? []).isEmpty {
            return .alreadyImported
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
            runCount: skiingRunCount
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
        var personalBestUpdate: StatsService.PersonalBestUpdate?
        if let profile = (try? context.fetch(profileDescriptor))?.first {
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
            return .imported(personalBestUpdate: personalBestUpdate)
        } catch {
            return .failed
        }
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

        let encoder = JSONEncoder()
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
            guard let segType = currentSegmentType,
                  let first = currentSegmentFilteredPoints.first,
                  let last = currentSegmentFilteredPoints.last,
                  currentSegmentFilteredPoints.count >= 2 else {
                currentSegmentType = nil
                currentSegmentFilteredPoints = []
                lastActiveTime = nil
                return
            }
            let pts = currentSegmentFilteredPoints
            let distance = zip(pts, pts.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
            let duration = max(last.timestamp.timeIntervalSince(first.timestamp), 1)
            let avgSpeed = distance / duration
            let maxSpeed = pts.map(\.estimatedSpeed).max() ?? 0
            if let effectiveType = SegmentValidator.effectiveType(
                activityType: segType,
                firstPoint: first,
                lastPoint: last,
                duration: duration,
                averageSpeed: avgSpeed
            ) {
                let verticalDrop = SegmentValidator.verticalDrop(
                    effectiveType: effectiveType,
                    firstAltitude: first.altitude,
                    lastAltitude: last.altitude
                )
                let trackData = try? encoder.encode(pts)
                result.append(CompletedRunData(
                    startDate: first.timestamp,
                    endDate: last.timestamp,
                    distance: distance,
                    verticalDrop: verticalDrop,
                    maxSpeed: maxSpeed,
                    averageSpeed: avgSpeed,
                    activityType: effectiveType,
                    trackData: trackData
                ))
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

#if DEBUG
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
#endif
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
