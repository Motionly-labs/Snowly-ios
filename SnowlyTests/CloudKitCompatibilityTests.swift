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
        let bundleID = Bundle.main.bundleIdentifier ?? "Snowly"
        let cloudContainerID = "iCloud.\(bundleID)"
        let syncedConfig = ModelConfiguration(
            "Synced",
            schema: Schema([
                SkiSession.self, SkiRun.self, Resort.self,
                GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            ]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: cloudEnabled ? .private(cloudContainerID) : .none
        )

        let localConfig = ModelConfiguration(
            "Local",
            schema: Schema([DeviceSettings.self]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: SkiSession.self, SkiRun.self, Resort.self,
                 GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
                 DeviceSettings.self,
            configurations: syncedConfig, localConfig
        )
    }

    @Test("Dual-store container creates successfully")
    @MainActor
    func dualStoreContainerCreation() throws {
        let container = try makeDualStoreContainer(cloudEnabled: false)

        #expect(container.schema.entities.count == 8)
    }

    @Test("Dual-store container creates successfully with CloudKit enabled")
    @MainActor
    func dualStoreContainerCreationWithCloudKit() throws {
        let container = try makeDualStoreContainer(cloudEnabled: true)

        #expect(container.schema.entities.count == 8)
    }

    @Test("UserProfile does not contain device-specific fields")
    @MainActor
    func userProfileFields() throws {
        let profile = UserProfile(
            displayName: "Test User",
            preferredUnits: .metric,
            personalBestMaxSpeed: 25.0,
            dailyGoalMinutes: 180
        )

        #expect(profile.displayName == "Test User")
        #expect(profile.preferredUnits == .metric)
        #expect(profile.personalBestMaxSpeed == 25.0)
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

    @Test("SchemaV1 includes device and gear models")
    func schemaV1IncludesDeviceSettings() {
        let modelTypes = SchemaV1.models
        let typeNames = modelTypes.map { String(describing: $0) }

        // V1 uses a frozen snapshot of DeviceSettings (V1DeviceSettings).
        #expect(typeNames.contains("V1DeviceSettings"))
        #expect(typeNames.contains("UserProfile"))
        #expect(typeNames.contains("ServerProfile"))
        #expect(typeNames.contains("GearSetup"))
        #expect(typeNames.contains("GearAsset"))
        #expect(typeNames.contains("GearMaintenanceEvent"))
        #expect(modelTypes.count == 9)
    }

    @Test("SchemaV2 references current DeviceSettings")
    func schemaV2IncludesDeviceSettings() {
        let modelTypes = SchemaV2.models
        let typeNames = modelTypes.map { String(describing: $0) }

        #expect(typeNames.contains("DeviceSettings"))
        #expect(typeNames.contains("UserProfile"))
        #expect(modelTypes.count == 9)
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
