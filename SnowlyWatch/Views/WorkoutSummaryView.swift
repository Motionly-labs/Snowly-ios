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
                Text(String(localized: "watch_session_complete"))
                    .font(.headline)
                    .foregroundStyle(WatchColorTokens.brandGradient)

                Divider()

                summaryRow(
                    icon: "clock",
                    label: String(localized: "common_duration"),
                    value: Formatters.duration(workoutManager.elapsedTime)
                )

                summaryRow(
                    icon: "number",
                    label: String(localized: "common_runs"),
                    value: "\(workoutManager.runCount)"
                )

                summaryRow(
                    icon: "gauge.with.dots.needle.67percent",
                    label: String(localized: "stat_max_speed"),
                    value: Formatters.speed(workoutManager.maxSpeed, unit: preferredUnitSystem)
                )

                summaryRow(
                    icon: "mountain.2.fill",
                    label: String(localized: "common_vertical"),
                    value: Formatters.vertical(workoutManager.totalVertical, unit: preferredUnitSystem)
                )

                summaryRow(
                    icon: "arrow.triangle.swap",
                    label: String(localized: "common_distance"),
                    value: Formatters.distance(workoutManager.totalDistance, unit: preferredUnitSystem)
                )

                Divider()

                Button(String(localized: "common_done")) {
                    workoutManager.dismiss()
                }
                .tint(WatchColorTokens.brandWarmAmber)
            }
            .padding(WatchSpacing.md)
        }
    }

    private var preferredUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
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
