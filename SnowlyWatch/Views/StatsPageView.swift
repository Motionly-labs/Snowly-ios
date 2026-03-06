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
        ScrollView {
            VStack(spacing: WatchSpacing.sm) {
                statCard(
                    icon: "gauge.with.dots.needle.33percent",
                    label: String(localized: "watch_stat_speed_current"),
                    value: Formatters.speed(workoutManager.currentSpeed, unit: preferredUnitSystem)
                )

                statCard(
                    icon: "heart.fill",
                    label: String(localized: "watch_stat_heart_rate_current"),
                    value: heartRateText(workoutManager.currentHeartRate)
                )

                statCard(
                    icon: "heart.text.square.fill",
                    label: String(localized: "watch_stat_heart_rate_average"),
                    value: heartRateText(workoutManager.averageHeartRate)
                )

                statCard(
                    icon: "gauge.with.dots.needle.67percent",
                    label: String(localized: "stat_max_speed"),
                    value: Formatters.speed(workoutManager.maxSpeed, unit: preferredUnitSystem)
                )

                statCard(
                    icon: "mountain.2.fill",
                    label: String(localized: "common_vertical"),
                    value: Formatters.vertical(workoutManager.totalVertical, unit: preferredUnitSystem)
                )

                statCard(
                    icon: "arrow.triangle.swap",
                    label: String(localized: "common_distance"),
                    value: Formatters.distance(workoutManager.totalDistance, unit: preferredUnitSystem)
                )

                statCard(
                    icon: "number",
                    label: String(localized: "common_runs"),
                    value: "\(workoutManager.runCount)"
                )

                statCard(
                    icon: "clock",
                    label: String(localized: "common_ski_time"),
                    value: Formatters.timer(workoutManager.elapsedTime)
                )
            }
        }
        .padding(WatchSpacing.md)
    }

    private var preferredUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    private func statCard(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WatchColorTokens.brandWarmAmber)
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, WatchSpacing.sm)
        .padding(.vertical, WatchSpacing.sm)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func heartRateText(_ heartRate: Double) -> String {
        guard heartRate > 0 else { return String(localized: "watch_placeholder_dash") }
        let rounded = Int(heartRate.rounded())
        let format = String(localized: "watch_heart_rate_format")
        return String(format: format, locale: Locale.current, rounded)
    }
}
