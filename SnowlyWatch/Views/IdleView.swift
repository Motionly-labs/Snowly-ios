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
                subtitle: nil,
                tint: connectivity.isPhoneReachable ? .green : WatchColorTokens.brandWarmOrange,
                holdDuration: Self.startHoldDuration,
                diameter: 118,
                iconSize: 34
            ) {
                if connectivity.isPhoneReachable {
                    connectivity.send(.requestStart)
                } else {
                    workoutManager.startIndependent()
                }
            }

            Spacer()
        }
        .padding(WatchSpacing.md)
    }
}
