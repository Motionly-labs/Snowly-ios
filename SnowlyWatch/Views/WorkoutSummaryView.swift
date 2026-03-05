//
//  WorkoutSummaryView.swift
//  SnowlyWatch
//
//  Post-workout summary screen.
//

import SwiftUI

struct WorkoutSummaryView: View {

    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: WatchSpacing.lg) {
                Text("Session Complete")
                    .font(.headline)
                    .foregroundStyle(WatchColorTokens.brandGradient)

                Divider()

                summaryRow(
                    icon: "clock",
                    label: "Duration",
                    value: Formatters.duration(workoutManager.elapsedTime)
                )

                summaryRow(
                    icon: "number",
                    label: "Runs",
                    value: "\(workoutManager.runCount)"
                )

                summaryRow(
                    icon: "gauge.with.dots.needle.67percent",
                    label: "Max Speed",
                    value: Formatters.speed(workoutManager.maxSpeed, unit: .metric)
                )

                summaryRow(
                    icon: "mountain.2.fill",
                    label: "Vertical",
                    value: Formatters.vertical(workoutManager.totalVertical, unit: .metric)
                )

                summaryRow(
                    icon: "arrow.triangle.swap",
                    label: "Distance",
                    value: Formatters.distance(workoutManager.totalDistance, unit: .metric)
                )

                Divider()

                Button("Done") {
                    workoutManager.dismiss()
                }
                .tint(WatchColorTokens.brandWarmAmber)
            }
            .padding(WatchSpacing.md)
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
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
