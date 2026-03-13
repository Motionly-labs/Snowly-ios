//
//  WatchRootView.swift
//  SnowlyWatch
//
//  Root view that switches based on workout state.
//

import SwiftUI

struct WatchRootView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        switch workoutManager.trackingState {
        case .idle:
            IdleView()
        case .active, .paused:
            WorkoutActiveView()
        case .summary:
            WorkoutSummaryView()
        }
    }
}
