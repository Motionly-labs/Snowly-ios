//
//  SnowlyWatchApp.swift
//  SnowlyWatch
//
//  Entry point for the watchOS app.
//

import SwiftUI

@main
struct SnowlyWatchApp: App {

    @State private var connectivityService = WatchConnectivityService()
    @State private var locationService = WatchLocationService()
    @State private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connectivityService)
                .environment(locationService)
                .environment(workoutManager)
                .onAppear {
                    workoutManager.configure(
                        connectivity: connectivityService,
                        location: locationService
                    )
                }
        }
    }
}
