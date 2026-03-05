//
//  StatsPageView.swift
//  SnowlyWatch
//
//  Secondary stats page in the workout TabView.
//

import SwiftUI

struct StatsPageView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        VStack(spacing: WatchSpacing.lg) {
            Spacer()

            statRow(
                icon: "mountain.2.fill",
                label: "Vertical",
                value: Formatters.vertical(workoutManager.totalVertical, unit: .metric)
            )

            statRow(
                icon: "arrow.triangle.swap",
                label: "Distance",
                value: Formatters.distance(workoutManager.totalDistance, unit: .metric)
            )

            statRow(
                icon: "number",
                label: "Runs",
                value: "\(workoutManager.runCount)"
            )

            Spacer()
        }
        .padding(WatchSpacing.md)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(WatchColorTokens.brandWarmAmber)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.body.monospacedDigit())
                .bold()
        }
    }
}
