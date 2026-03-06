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
    @Environment(CrewService.self) private var crewService
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    private var hasCompletedOnboarding: Bool {
        deviceSettings.contains(where: \.hasCompletedOnboarding)
    }

    private var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
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
        }
        .onChange(of: profiles.first?.id) { _, _ in
            configureCrewService()
        }
        .onChange(of: profiles.first?.displayName) { _, _ in
            configureCrewService()
        }
        .onChange(of: profiles.count) { _, _ in
            normalizeProfiles()
        }
        .onChange(of: deviceSettings.count) { _, _ in
            normalizeDeviceSettings()
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
            primary.seasonBestMaxSpeed = max(primary.seasonBestMaxSpeed, duplicate.seasonBestMaxSpeed)
            primary.seasonBestVertical = max(primary.seasonBestVertical, duplicate.seasonBestVertical)
            primary.seasonBestDistance = max(primary.seasonBestDistance, duplicate.seasonBestDistance)
            primary.seasonBestRunCount = max(primary.seasonBestRunCount, duplicate.seasonBestRunCount)
            modelContext.delete(duplicate)
        }
    }

    private func normalizeDeviceSettings() {
        if deviceSettings.isEmpty {
            modelContext.insert(DeviceSettings(hasCompletedOnboarding: hasExistingAppData()))
            return
        }

        if deviceSettings.count == 1, let only = deviceSettings.first {
            if !only.hasCompletedOnboarding && hasExistingAppData() {
                only.hasCompletedOnboarding = true
            }
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

    private func configureCrewService() {
        guard let profile = profiles.first else { return }
        crewService.configure(
            userId: profile.id.uuidString,
            displayName: profile.displayName
        )
    }

    private func hasExistingAppData() -> Bool {
        if !profiles.isEmpty {
            return true
        }

        var sessionDescriptor = FetchDescriptor<SkiSession>()
        sessionDescriptor.fetchLimit = 1
        if !((try? modelContext.fetch(sessionDescriptor)) ?? []).isEmpty {
            return true
        }

        var gearDescriptor = FetchDescriptor<GearSetup>()
        gearDescriptor.fetchLimit = 1
        if !((try? modelContext.fetch(gearDescriptor)) ?? []).isEmpty {
            return true
        }

        var resortDescriptor = FetchDescriptor<Resort>()
        resortDescriptor.fetchLimit = 1
        return !((try? modelContext.fetch(resortDescriptor)) ?? []).isEmpty
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
        .modelContainer(for: [
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearItem.self, UserProfile.self,
            DeviceSettings.self,
        ], inMemory: true)
}
