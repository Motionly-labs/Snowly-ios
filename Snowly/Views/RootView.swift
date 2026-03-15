//
//  RootView.swift
//  Snowly
//
//  App launch flow:
//  1. Onboarding (first launch only) — Welcome → Permissions → Preferences
//  2. Main tab interface
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CrewService.self) private var crewService
    @Environment(GearReminderService.self) private var gearReminderService
    @Environment(PhoneConnectivityService.self) private var phoneConnectivityService
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    private var hasCompletedOnboarding: Bool {
        deviceSettings.contains(where: \.hasCompletedOnboarding)
    }

    private var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    private var watchUnitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? defaultUnitSystem
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .onAppear {
            normalizeProfiles()
            normalizeDeviceSettings()
            configureCrewService()
            resetSeasonBestsIfNeeded()
            gearReminderService.syncAll(using: modelContext)
            syncWatchMetadata()
        }
        .onChange(of: profiles.first?.id) { _, _ in
            configureCrewService()
            syncWatchMetadata()
        }
        .onChange(of: profiles.first?.displayName) { _, _ in
            configureCrewService()
        }
        .onChange(of: profiles.first?.preferredUnits) { _, _ in
            syncWatchMetadata()
        }
        .onChange(of: profiles.count) { _, _ in
            normalizeProfiles()
            syncWatchMetadata()
        }
        .onChange(of: deviceSettings.count) { _, _ in
            normalizeDeviceSettings()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncWatchMetadata()
        }
    }

    private func normalizeProfiles() {
        if profiles.isEmpty {
            guard hasCompletedOnboarding else { return }
            modelContext.insert(UserProfile(preferredUnits: defaultUnitSystem))
            return
        }

        guard profiles.count > 1, let primary = profiles.first else { return }

        for duplicate in profiles.dropFirst() {
            if primary.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let duplicateName = duplicate.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !duplicateName.isEmpty {
                    primary.displayName = duplicateName
                }
            }
            primary.personalBestMaxSpeed = max(primary.personalBestMaxSpeed, duplicate.personalBestMaxSpeed)
            primary.personalBestVertical = max(primary.personalBestVertical, duplicate.personalBestVertical)
            primary.personalBestDistance = max(primary.personalBestDistance, duplicate.personalBestDistance)
            primary.seasonBestMaxSpeed = max(primary.seasonBestMaxSpeed, duplicate.seasonBestMaxSpeed)
            primary.seasonBestVertical = max(primary.seasonBestVertical, duplicate.seasonBestVertical)
            primary.seasonBestDistance = max(primary.seasonBestDistance, duplicate.seasonBestDistance)
            modelContext.delete(duplicate)
        }
    }

    private func normalizeDeviceSettings() {
        if deviceSettings.isEmpty {
            modelContext.insert(DeviceSettings())
            return
        }

        guard deviceSettings.count > 1 else { return }
        let primary = deviceSettings.first(where: \.hasCompletedOnboarding) ?? deviceSettings[0]

        for duplicate in deviceSettings where duplicate.id != primary.id {
            primary.hasCompletedOnboarding = primary.hasCompletedOnboarding || duplicate.hasCompletedOnboarding
            primary.healthKitEnabled = primary.healthKitEnabled || duplicate.healthKitEnabled
            modelContext.delete(duplicate)
        }
    }

    private func resetSeasonBestsIfNeeded() {
        guard let profile = profiles.first else { return }
        let currentSeason = Date().seasonYear
        if profile.lastSeasonYear != currentSeason {
            StatsService.resetSeasonBests(for: profile)
            profile.lastSeasonYear = currentSeason
            try? modelContext.save()
        }
    }

    private func configureCrewService() {
        guard let profile = profiles.first else { return }
        crewService.configure(
            userId: profile.id.uuidString,
            displayName: profile.displayName
        )
    }

    private func syncWatchMetadata() {
        phoneConnectivityService.updateWatchMetadata(unitPreference: watchUnitSystem)
    }

}

#Preview {
    let location = LocationTrackingService()
    let motion = MotionDetectionService()
    let battery = BatteryMonitorService()
    let healthKit = HealthKitService()
    let tracking = SessionTrackingService(
        locationService: location,
        motionService: motion,
        batteryService: battery,
        healthKitService: healthKit
    )
    let skiMap = SkiMapCacheService()
    let syncMonitor = SyncMonitorService()
    let musicPlayer = MusicPlayerService()

    let crewAPI = CrewAPIClient()
    let crew = CrewService(apiClient: crewAPI, locationService: location)

    RootView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(syncMonitor)
        .environment(musicPlayer)
        .environment(crew)
        .environment(PhoneConnectivityService())
        .environment(GearReminderService())
        .modelContainer(for: [
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            DeviceSettings.self,
        ], inMemory: true)
}
