//
//  WorkoutActiveView.swift
//  SnowlyWatch
//
//  Main workout view with paged metrics.
//

import SwiftUI

struct WorkoutActiveView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            alwaysOnDisplay
        } else {
            TabView {
                mainMetricsPage
                StatsPageView()
                WorkoutControlsView()
            }
            .tabViewStyle(.verticalPage(transitionStyle: .blur))
        }
    }

    // MARK: - Main Metrics

    private var mainMetricsPage: some View {
        VStack(spacing: WatchSpacing.sm) {
            Spacer()

            Text(Formatters.speedValue(workoutManager.currentSpeed, unit: .metric))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(WatchColorTokens.brandGradient)
                .contentTransition(.numericText())

            Text(Formatters.speedUnit(.metric))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(Formatters.timer(workoutManager.elapsedTime))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white)

            HStack(spacing: WatchSpacing.sm) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(Formatters.speed(workoutManager.maxSpeed, unit: .metric))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(WatchSpacing.md)
    }

    // MARK: - Always-On Display

    private var alwaysOnDisplay: some View {
        VStack(spacing: WatchSpacing.md) {
            Spacer()

            Text(Formatters.speedValue(workoutManager.currentSpeed, unit: .metric))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(WatchColorTokens.brandWarmAmber.opacity(0.6))

            Text(Formatters.timer(workoutManager.elapsedTime))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
    }
}
