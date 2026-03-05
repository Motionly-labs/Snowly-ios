//
//  SnowlyApp.swift
//  Snowly
//
//  Entry point. Creates all services at app level and injects
//  them via @Environment so they survive view lifecycle changes.
//

import SwiftUI
import SwiftData

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

    init() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        let battery = BatteryMonitorService()
        let healthKit = HealthKitService()

        self.locationService = location
        self.motionService = motion
        self.batteryService = battery
        self.healthKitService = healthKit

        let tracking = SessionTrackingService(
            locationService: location,
            motionService: motion,
            batteryService: battery,
            healthKitService: healthKit
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
    }
}

@main
struct SnowlyApp: App {

    let modelContainer: ModelContainer
    @State private var services = AppServices()
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]
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
            modelContainer = container
        } catch {
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
                modelContainer = inMemoryContainer
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(deviceSettings.first?.colorScheme)
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
        }
        .modelContainer(modelContainer)
    }

    private static var canUseCloudKitAtLaunch: Bool {
#if targetEnvironment(simulator)
        false
#else
        FileManager.default.ubiquityIdentityToken != nil
#endif
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

        let localSchema = Schema([DeviceSettings.self])
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: SkiSession.self, SkiRun.self, Resort.self,
                 GearSetup.self, GearItem.self, UserProfile.self,
                 DeviceSettings.self,
            migrationPlan: SnowlyMigrationPlan.self,
            configurations: syncedConfig, localConfig
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
            .modelContainer(modelContainer)
    }
}

#Preview("Snowly App Root") {
    SnowlyAppPreviewHost()
}
