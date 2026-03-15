//
//  IdleView.swift
//  SnowlyWatch
//
//  Idle screen shown before tracking starts.
//

import SwiftUI

struct IdleView: View {

    @Environment(WatchConnectivityService.self) private var connectivity
    @Environment(WatchWorkoutManager.self) private var workoutManager

    private static let startHoldDuration: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: WatchSpacing.xl) {
            Spacer()

            Text("Snowly")
                .font(.title2.weight(.bold))
                .foregroundStyle(WatchColorTokens.brandGradient)

            HoldProgressCircleButton(
                systemImage: "figure.skiing.downhill",
                title: nil,
                subtitle: workoutManager.statusMessage,
                tint: workoutManager.isStartPending
                    ? WatchColorTokens.brandWarmAmber
                    : (connectivity.isPhoneReachable ? WatchColorTokens.connectedAccent : WatchColorTokens.secondaryAccent),
                isDisabled: workoutManager.isStartPending,
                holdDuration: Self.startHoldDuration,
                diameter: WatchSpacing.startButtonDiameter,
                iconSize: WatchSpacing.startButtonIconSize
            ) {
                workoutManager.start()
            }
            Spacer()
        }
        .padding(WatchSpacing.md)
    }
}
