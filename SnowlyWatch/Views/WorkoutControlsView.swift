//
//  WorkoutControlsView.swift
//  SnowlyWatch
//
//  Pause/resume and stop controls.
//

import SwiftUI

struct WorkoutControlsView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager

    private static let stopHoldDuration: TimeInterval = 2.0

    var body: some View {
        VStack(spacing: WatchSpacing.xl) {
            Spacer()

            HStack(spacing: WatchSpacing.lg) {
                pauseResumeButton
                stopButton
            }

            Spacer()
        }
        .padding(WatchSpacing.md)
    }

    // MARK: - Pause / Resume

    private var pauseResumeButton: some View {
        Button {
            if case .paused = workoutManager.trackingState {
                workoutManager.resume()
            } else {
                workoutManager.pause()
            }
        } label: {
            let isPaused = workoutManager.trackingState == .paused
            VStack(spacing: WatchSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(WatchColorTokens.brandWarmAmber.opacity(0.16))
                        .frame(width: 72, height: 72)

                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WatchColorTokens.brandWarmAmber)
                }

                Text(isPaused ? String(localized: "common_resume") : String(localized: "common_pause"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stop (Long Press)

    private var stopButton: some View {
        HoldProgressCircleButton(
            systemImage: "stop.fill",
            title: String(localized: "watch_hold_to_stop"),
            subtitle: nil,
            tint: WatchColorTokens.brandRed,
            holdDuration: Self.stopHoldDuration,
            diameter: 92,
            iconSize: 26
        ) {
            workoutManager.stop()
        }
    }
}
