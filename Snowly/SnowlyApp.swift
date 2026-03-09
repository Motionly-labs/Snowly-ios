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
    }
}

@main
struct SnowlyApp: App {

    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) var appDelegate

    let modelContainer: ModelContainer
    @State private var services = AppServices()
    @Environment(\.scenePhase) private var scenePhase
    private static let cloudContainerIdentifier = "iCloud.Roy-Kid.Snowly"

    init() {
        let launchArguments = Set(ProcessInfo.processInfo.arguments)
        let isUITesting = launchArguments.contains("-ui_testing")
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
                launchArguments: launchArguments
            )
            SnowlyApp.seedSummaryMockDataIfNeeded(
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
                    launchArguments: launchArguments
                )
                SnowlyApp.seedSummaryMockDataIfNeeded(
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
                .task {
                    SnowlyApp.restoreActiveServer(
                        in: modelContainer.mainContext,
                        crewAPIClient: services.crewAPIClient
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
                                print("[DeepLink] Failed to join crew: \(error)")
                            }
                        }
                    case .startTracking:
                        services.trackingService.quickStartPending = true
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private static func restoreActiveServer(
        in context: ModelContext,
        crewAPIClient: CrewAPIClient
    ) {
        let descriptor = FetchDescriptor<ServerProfile>(
            predicate: #Predicate<ServerProfile> { $0.isActive }
        )
        guard let activeServer = (try? context.fetch(descriptor))?.first,
              let apiBaseURL = activeServer.apiBaseURL else {
            return
        }
        crewAPIClient.updateBaseURL(apiBaseURL)
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
        launchArguments: Set<String>
    ) -> ModelContainer? {
#if targetEnvironment(simulator)
        guard !isTesting else { return nil }

        do {
            print("Simulator persistent store load failed. Attempting store reset recovery: \(error)")
            try resetPersistentStoreFiles()
            let recoveredContainer = try makeModelContainer(
                isStoredInMemoryOnly: false,
                cloudEnabled: false
            )
            seedUITestDataIfNeeded(
                in: recoveredContainer,
                launchArguments: launchArguments
            )
            seedSummaryMockDataIfNeeded(
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
            GearSetup.self, GearItem.self, UserProfile.self,
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
                 GearSetup.self, GearItem.self, UserProfile.self,
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
        let session = SkiSession(
            id: sessionId,
            startDate: workout.summary.startDate,
            endDate: workout.summary.endDate,
            totalDistance: workout.summary.totalDistance,
            totalVertical: workout.summary.totalVertical,
            maxSpeed: workout.summary.maxSpeed,
            runCount: max(
                workout.summary.runCount,
                completedRuns.filter { $0.activityType == .skiing }.count
            )
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
    /// Segments track points into completed runs with synchronous track data encoding.
    /// Does not use SegmentFinalizationService (which encodes asynchronously) so that
    /// callers relying on trackData being populated immediately (e.g. fixture seeding,
    /// HealthKit import) get valid data without requiring an event-loop yield.
    private static func buildCompletedRuns(from trackPoints: [TrackPoint]) -> [CompletedRunData] {
        let sortedPoints = trackPoints.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else { return [] }

        var recentPoints = CircularBuffer<TrackPoint>(capacity: SharedConstants.recentPointsBufferSize)
        var currentActivity: DetectedActivity = .idle
        var candidateActivity: DetectedActivity?
        var candidateStartTime: Date?

        var currentSegmentType: RunActivityType?
        var currentSegmentPoints: [TrackPoint] = []
        var lastActiveTime: Date?
        var result: [CompletedRunData] = []

        func finalizeSegment() {
            guard let segType = currentSegmentType, !currentSegmentPoints.isEmpty else { return }
            if let run = buildCompletedRunData(activityType: segType, points: currentSegmentPoints) {
                result.append(run)
            }
            currentSegmentType = nil
            currentSegmentPoints = []
            lastActiveTime = nil
        }

        for point in sortedPoints {
            recentPoints.append(point)

            let rawActivity = RunDetectionService.detect(
                point: point,
                recentPoints: recentPoints.elements,
                previousActivity: currentActivity
            )
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
                    currentSegmentPoints = [point]
                } else {
                    currentSegmentPoints.append(point)
                }
                lastActiveTime = point.timestamp
            } else if !currentSegmentPoints.isEmpty,
                      let lastActive = lastActiveTime,
                      RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: point.timestamp) {
                finalizeSegment()
            }
        }

        finalizeSegment()
        return result
    }

    private static func seedSummaryMockDataIfNeeded(
        in container: ModelContainer,
        launchArguments: Set<String>
    ) {
        guard launchArguments.contains("-seed_summary_mock") else { return }

        let context = container.mainContext
        let shouldReset = launchArguments.contains("-seed_summary_mock_reset")
        let mockSessionID = UUID(uuidString: "6E99CF0E-4E4A-4C06-8F15-8E0F9FF1DF00")!
        let mockResortID = UUID(uuidString: "F1AE37A3-22AC-4B70-8C69-A4CF0D3566F7")!

        if shouldReset {
            deleteAll(SkiRun.self, in: context)
            deleteAll(SkiSession.self, in: context)
            deleteAll(Resort.self, in: context)
        }

        var existingSessionDescriptor = FetchDescriptor<SkiSession>(
            predicate: #Predicate<SkiSession> { $0.id == mockSessionID }
        )
        existingSessionDescriptor.fetchLimit = 1
        if let existing = try? context.fetch(existingSessionDescriptor), !existing.isEmpty {
            return
        }

        let resort: Resort = {
            var descriptor = FetchDescriptor<Resort>(
                predicate: #Predicate<Resort> { $0.id == mockResortID }
            )
            descriptor.fetchLimit = 1
            if let existing = try? context.fetch(descriptor), let found = existing.first {
                return found
            }
            let newResort = Resort(
                id: mockResortID,
                name: "Zermatt",
                latitude: 46.0207,
                longitude: 7.7491,
                country: "CH"
            )
            context.insert(newResort)
            return newResort
        }()

        var profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        profileDescriptor.fetchLimit = 1
        let profile: UserProfile = {
            if let existing = try? context.fetch(profileDescriptor), let found = existing.first {
                if found.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    found.displayName = "Summary Mock Rider"
                }
                return found
            }
            let created = UserProfile(displayName: "Summary Mock Rider", preferredUnits: .metric)
            context.insert(created)
            return created
        }()

        var settingsDescriptor = FetchDescriptor<DeviceSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        if let existing = try? context.fetch(settingsDescriptor), let settings = existing.first {
            settings.hasCompletedOnboarding = true
        } else {
            context.insert(DeviceSettings(hasCompletedOnboarding: true))
        }

        // Keep seeded session near "now" so SessionSummaryView (sorted by latest)
        // always picks this fixture even if stale sessions remain in storage.
        let startDate = Date().addingTimeInterval(-90 * 60)
        guard let mockRuns = buildSummaryMockRunsFromFixture(startDate: startDate) else {
            print("seed_summary_mock skipped: missing or invalid ZermattSkiDay.trackpoints fixture")
            return
        }
        guard let endDate = mockRuns.last?.endDate else { return }

        let skiingRuns = mockRuns.filter { $0.activityType == .skiing }
        let totalDistance = skiingRuns.reduce(0.0) { $0 + $1.distance }
        let totalVertical = skiingRuns.reduce(0.0) { $0 + $1.verticalDrop }
        let maxSpeed = mockRuns.map(\.maxSpeed).max() ?? 0
        let runCount = skiingRuns.count

        let session = SkiSession(
            id: mockSessionID,
            startDate: startDate,
            endDate: endDate,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount,
            resort: resort
        )
        context.insert(session)

        for runData in mockRuns {
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

        let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)
        if update.hasUpdates {
            StatsService.applyPersonalBestUpdate(update, to: profile)
        }

        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(
        _: T.Type,
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<T>()
        guard let models = try? context.fetch(descriptor), !models.isEmpty else { return }
        for model in models {
            context.delete(model)
        }
        try? context.save()
    }

    private struct SummaryMockFixtureTrackPoint: Codable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let speed: Double
        let accuracy: Double
        let course: Double
    }

    private static func buildSummaryMockRunsFromFixture(startDate: Date) -> [CompletedRunData]? {
        guard let url = Bundle.main.url(forResource: "ZermattSkiDay.trackpoints", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let source = try? JSONDecoder().decode([SummaryMockFixtureTrackPoint].self, from: data),
              !source.isEmpty else {
            return nil
        }

        let anchor = source.first?.timestamp ?? 0
        let anchoredPoints = source.map { point in
            TrackPoint(
                timestamp: startDate.addingTimeInterval(point.timestamp - anchor),
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                speed: point.speed,
                accuracy: point.accuracy,
                course: point.course
            )
        }

        let completed = buildCompletedRuns(from: anchoredPoints)
            .filter { $0.activityType == .skiing || $0.activityType == .lift || $0.activityType == .walk }
        if !completed.isEmpty {
            print("seed_summary_mock loaded fixture: ZermattSkiDay.trackpoints.json, runs=\(completed.count)")
            return completed
        }
        return nil
    }

    private static func buildCompletedRunData(
        activityType: RunActivityType,
        points: [TrackPoint]
    ) -> CompletedRunData? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }

        let distance = zip(points, points.dropFirst()).reduce(0.0) { acc, pair in
            acc + pair.0.distance(to: pair.1)
        }
        let duration = max(last.timestamp.timeIntervalSince(first.timestamp), 1)
        let avgSpeed = distance / duration
        let maxSpeed = points.map(\.speed).max() ?? 0

        guard let effectiveType = SegmentValidator.effectiveType(
            activityType: activityType,
            firstPoint: first,
            lastPoint: last,
            duration: duration,
            averageSpeed: avgSpeed
        ) else { return nil }

        let verticalDrop = SegmentValidator.verticalDrop(
            effectiveType: effectiveType,
            firstAltitude: first.altitude,
            lastAltitude: last.altitude
        )

        let trackData = try? JSONEncoder().encode(points)

        return CompletedRunData(
            startDate: first.timestamp,
            endDate: last.timestamp,
            distance: distance,
            verticalDrop: verticalDrop,
            maxSpeed: maxSpeed,
            averageSpeed: avgSpeed,
            activityType: effectiveType,
            trackData: trackData
        )
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
