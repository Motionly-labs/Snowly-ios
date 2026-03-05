//
//  WorkoutControlsView.swift
//  SnowlyWatch
//
//  Pause/resume and stop controls.
//

import SwiftUI

struct WorkoutControlsView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager
    @State private var stopProgress: CGFloat = 0
    @State private var isHoldingStop = false

    private static let stopHoldDuration: TimeInterval = 1.5

    var body: some View {
        VStack(spacing: WatchSpacing.lg) {
            Spacer()

            pauseResumeButton

            stopButton

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
            Label(
                isPaused ? "Resume" : "Pause",
                systemImage: isPaused ? "play.fill" : "pause.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .tint(WatchColorTokens.brandWarmAmber)
    }

    // MARK: - Stop (Long Press)

    private var stopButton: some View {
        Button(role: .destructive) {
            // Tap does nothing; must long-press
        } label: {
            ZStack {
                Label("Hold to Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)

                GeometryReader { geo in
                    Rectangle()
                        .fill(WatchColorTokens.brandRed.opacity(0.3))
                        .frame(width: geo.size.width * stopProgress)
                        .animation(
                            isHoldingStop
                                ? .linear(duration: Self.stopHoldDuration)
                                : .easeOut(duration: 0.2),
                            value: stopProgress
                        )
                }
                .clipped()
                .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.stopHoldDuration)
                .onChanged { _ in
                    isHoldingStop = true
                    stopProgress = 1.0
                }
                .onEnded { _ in
                    isHoldingStop = false
                    stopProgress = 0
                    workoutManager.stop()
                }
        )
        .onChange(of: isHoldingStop) { _, newValue in
            if !newValue {
                stopProgress = 0
            }
        }
    }
}
