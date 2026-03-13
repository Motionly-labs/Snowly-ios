//
//  GearWorkspaceView.swift
//  Snowly
//
//  Horizontal workspace for checklist and locker pages inside the Gear tab.
//

import SwiftData
import SwiftUI

enum GearWorkspacePage: Hashable {
    case checklist
    case locker
}

struct GearWorkspaceView: View {
    @State private var selectedPage: GearWorkspacePage = .checklist

    var body: some View {
        TabView(selection: $selectedPage) {
            GearLockerView(selectedPage: $selectedPage)
                .tag(GearWorkspacePage.locker)

            GearListView(selectedPage: $selectedPage)
                .tag(GearWorkspacePage.checklist)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

#Preview {
    GearWorkspaceView()
        .modelContainer(for: [
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            DeviceSettings.self,
        ], inMemory: true)
}
