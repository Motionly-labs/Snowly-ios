//
//  MainTabView.swift
//  Snowly
//
//  3-tab navigation using the system TabView/tab bar.
//

import SwiftData
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: TabID = .ride
    @State private var homeResetTrigger = 0

    enum TabID: Hashable {
        case gear
        case ride
        case tracks
    }

    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .ride { homeResetTrigger += 1 }
                selectedTab = newTab
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(String(localized: "tab_gear"), systemImage: "gearshape.fill", value: TabID.gear) {
                GearWorkspaceView()
            }

            Tab(String(localized: "tab_ride"), systemImage: "play.fill", value: TabID.ride) {
                HomeView(resetTrigger: homeResetTrigger)
            }

            Tab(String(localized: "tab_tracks"), systemImage: "person.fill", value: TabID.tracks) {
                ActivityHistoryView()
            }
        }
        .tint(ColorTokens.primaryAccent)
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

    MainTabView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(syncMonitor)
        .environment(musicPlayer)
        .modelContainer(for: [
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            DeviceSettings.self,
        ], inMemory: true)
}
