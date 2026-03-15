//
//  WorkoutControlsView.swift
//  SnowlyWatch
//
//  Pause/resume and stop controls.
//

import SwiftUI

struct WorkoutControlsView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager

    private static let stopHoldDuration: TimeInterval = 1.0

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
        VStack(spacing: WatchSpacing.sm) {
            let isPaused = workoutManager.trackingState == .paused

            Button {
                if case .paused = workoutManager.trackingState {
                    workoutManager.resume()
                } else {
                    workoutManager.pause()
                }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(WatchTypography.controlIcon)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(WatchColorTokens.sportAccent)

            Text(isPaused ? String(localized: "common_resume") : String(localized: "common_pause"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .disabled(workoutManager.isCompanionControlPending)
        .opacity(workoutManager.isCompanionControlPending ? 0.55 : 1)
    }

    // MARK: - Stop (Long Press)

    private var stopButton: some View {
        HoldProgressCircleButton(
            systemImage: "stop.fill",
            title: String(localized: "watch_hold_to_stop"),
            subtitle: nil,
            tint: WatchColorTokens.brandRed,
            isDisabled: workoutManager.isCompanionControlPending,
            holdDuration: Self.stopHoldDuration,
            diameter: WatchSpacing.stopButtonDiameter,
            iconSize: WatchSpacing.stopButtonIconSize
        ) {
            workoutManager.stop()
        }
    }
}
