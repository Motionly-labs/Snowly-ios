//
//  CloudKitCompatibilityTests.swift
//  SnowlyTests
//
//  Verifies CloudKit-compatible dual-store container configuration
//  and model split (UserProfile vs DeviceSettings).
//

import Testing
import SwiftData
import Foundation
@testable import Snowly

@Suite("CloudKit Compatibility")
struct CloudKitCompatibilityTests {

    // MARK: - Helpers

    private func temporaryStoreURL(_ fileName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnowlyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private func makeDualStoreContainer(cloudEnabled: Bool) throws -> ModelContainer {
        let syncedConfig = ModelConfiguration(
            "Synced",
            schema: Schema([
                SkiSession.self, SkiRun.self, Resort.self,
                GearSetup.self, GearItem.self, UserProfile.self,
            ]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: cloudEnabled ? .private("iCloud.Roy-Kid.Snowly") : .none
        )

        let localConfig = ModelConfiguration(
            "Local",
            schema: Schema([DeviceSettings.self]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: SkiSession.self, SkiRun.self, Resort.self,
                 GearSetup.self, GearItem.self, UserProfile.self,
                 DeviceSettings.self,
            configurations: syncedConfig, localConfig
        )
    }

    @Test("Dual-store container creates successfully")
    @MainActor
    func dualStoreContainerCreation() throws {
        let container = try makeDualStoreContainer(cloudEnabled: false)

        #expect(container.schema.entities.count == 7)
    }

    @Test("UserProfile does not contain device-specific fields")
    @MainActor
    func userProfileFields() throws {
        let profile = UserProfile(
            displayName: "Test User",
            preferredUnits: .metric,
            seasonBestMaxSpeed: 25.0,
            dailyGoalMinutes: 180
        )

        #expect(profile.displayName == "Test User")
        #expect(profile.preferredUnits == .metric)
        #expect(profile.seasonBestMaxSpeed == 25.0)
        #expect(profile.dailyGoalMinutes == 180)
    }

    @Test("DeviceSettings contains device-specific fields")
    @MainActor
    func deviceSettingsFields() throws {
        let settings = DeviceSettings(
            healthKitEnabled: true,
            hasCompletedOnboarding: true
        )

        #expect(settings.healthKitEnabled == true)
        #expect(settings.hasCompletedOnboarding == true)
    }

    @Test("Models can be inserted into correct stores")
    @MainActor
    func insertIntoCorrectStores() throws {
        let container = try makeDualStoreContainer(cloudEnabled: false)

        let context = container.mainContext

        // Insert into synced store
        let profile = UserProfile(displayName: "Sync Test")
        context.insert(profile)

        // Insert into local store
        let settings = DeviceSettings(hasCompletedOnboarding: true)
        context.insert(settings)

        let fetchedProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        let fetchedSettings = try context.fetch(FetchDescriptor<DeviceSettings>())

        #expect(fetchedProfiles.count == 1)
        #expect(fetchedProfiles.first?.displayName == "Sync Test")
        #expect(fetchedSettings.count == 1)
        #expect(fetchedSettings.first?.hasCompletedOnboarding == true)
    }

    @Test("SchemaV1 includes DeviceSettings")
    func schemaV1IncludesDeviceSettings() {
        let modelTypes = SchemaV1.models
        let typeNames = modelTypes.map { String(describing: $0) }

        #expect(typeNames.contains("DeviceSettings"))
        #expect(typeNames.contains("UserProfile"))
        #expect(typeNames.contains("ServerProfile"))
        #expect(modelTypes.count == 8)
    }

    // MARK: - Regression Scenarios

    @Test("Regression: New install starts with empty data")
    @MainActor
    func regression_newInstall_emptyData() throws {
        let container = try makeDualStoreContainer(cloudEnabled: false)
        let context = container.mainContext

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let settings = try context.fetch(FetchDescriptor<DeviceSettings>())
        let sessions = try context.fetch(FetchDescriptor<SkiSession>())

        #expect(profiles.isEmpty)
        #expect(settings.isEmpty)
        #expect(sessions.isEmpty)
    }

    @Test("Regression: V1 store reopens and allows DeviceSettings")
    @MainActor
    func regression_reopen_v1Store() throws {
        let syncedURL = temporaryStoreURL("synced.sqlite")
        let localURL = temporaryStoreURL("local.sqlite")

        // Step 1: simulate existing v1 store (synced models only)
        let syncedSchema = Schema([
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearItem.self, UserProfile.self,
        ])
        do {
            let v1Config = ModelConfiguration(
                "Synced",
                schema: syncedSchema,
                url: syncedURL,
                cloudKitDatabase: .none
            )
            let v1Container = try ModelContainer(
                for: syncedSchema,
                configurations: [v1Config]
            )
            let context = v1Container.mainContext
            context.insert(UserProfile(displayName: "Migrating User"))
            try context.save()
        }

        // Step 2: reopen with dual-store config (synced + local)
        let localSchema = Schema([DeviceSettings.self])

        let reopenedSyncedConfig = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            url: syncedURL,
            cloudKitDatabase: .none
        )
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            url: localURL,
            cloudKitDatabase: .none
        )
        let reopenedContainer = try ModelContainer(
            for: SkiSession.self, SkiRun.self, Resort.self,
                 GearSetup.self, GearItem.self, UserProfile.self,
                 DeviceSettings.self,
            configurations: reopenedSyncedConfig, localConfig
        )
        let reopenedContext = reopenedContainer.mainContext

        let profiles = try reopenedContext.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Migrating User")

        // DeviceSettings is writable in the local store.
        reopenedContext.insert(DeviceSettings(hasCompletedOnboarding: true))
        try reopenedContext.save()
        let settings = try reopenedContext.fetch(FetchDescriptor<DeviceSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.hasCompletedOnboarding == true)
    }

    @Test("Regression: App remains usable with iCloud disabled")
    @MainActor
    func regression_iCloudDisabled_localOnlyStillWorks() throws {
        let container = try makeDualStoreContainer(cloudEnabled: false)
        let context = container.mainContext

        context.insert(UserProfile(displayName: "Offline User"))
        context.insert(DeviceSettings(healthKitEnabled: true))
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let settings = try context.fetch(FetchDescriptor<DeviceSettings>())

        #expect(profiles.count == 1)
        #expect(settings.count == 1)
    }

    @Test("Regression: weak network sync error can recover")
    @MainActor
    func regression_weakNetworkRecovery() {
        let monitor = SyncMonitorService()

        monitor.markSyncStarted()
        #expect(monitor.isSyncing == true)
        #expect(monitor.syncError == nil)

        monitor.markSyncCompleted(
            endDate: Date(),
            error: URLError(.notConnectedToInternet)
        )
        #expect(monitor.isSyncing == false)
        #expect(monitor.syncError != nil)
        #expect(monitor.lastSyncDate != nil)

        monitor.markSyncStarted()
        monitor.markSyncCompleted(endDate: Date(), error: nil)
        #expect(monitor.isSyncing == false)
        #expect(monitor.syncError == nil)
        #expect(monitor.lastSyncDate != nil)
    }
}
