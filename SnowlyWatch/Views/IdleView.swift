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

    var body: some View {
        VStack(spacing: WatchSpacing.lg) {
            Spacer()

            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 40))
                .foregroundStyle(WatchColorTokens.brandGradient)

            Text("Snowly")
                .font(.title2)
                .bold()
                .foregroundStyle(WatchColorTokens.brandGradient)

            Spacer()

            if connectivity.isPhoneReachable {
                Button {
                    connectivity.send(.requestStart)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            } else {
                Button {
                    workoutManager.startIndependent()
                } label: {
                    Label("Start on Watch", systemImage: "applewatch")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchColorTokens.brandWarmOrange)
            }
        }
        .padding(WatchSpacing.md)
    }
}
