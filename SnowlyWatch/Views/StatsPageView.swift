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
            VStack(spacing: 0) {
                statRow(
                    icon: "gauge.with.dots.needle.33percent",
                    label: String(localized: "watch_stat_speed_current"),
                    value: Formatters.speed(workoutManager.currentSpeed, unit: preferredUnitSystem)
                )
                Divider()
                statRow(
                    icon: "heart.fill",
                    label: String(localized: "watch_stat_heart_rate_current"),
                    value: heartRateText(workoutManager.currentHeartRate)
                )
                Divider()
                statRow(
                    icon: "heart.text.square.fill",
                    label: String(localized: "watch_stat_heart_rate_average"),
                    value: heartRateText(workoutManager.averageHeartRate)
                )
                Divider()
                statRow(
                    icon: "gauge.with.dots.needle.67percent",
                    label: String(localized: "stat_max_speed"),
                    value: Formatters.speed(workoutManager.maxSpeed, unit: preferredUnitSystem)
                )
                Divider()
                statRow(
                    icon: "mountain.2.fill",
                    label: String(localized: "common_vertical"),
                    value: Formatters.vertical(workoutManager.totalVertical, unit: preferredUnitSystem)
                )
                Divider()
                statRow(
                    icon: "arrow.triangle.swap",
                    label: String(localized: "common_distance"),
                    value: Formatters.distance(workoutManager.totalDistance, unit: preferredUnitSystem)
                )
                Divider()
                statRow(
                    icon: "number",
                    label: String(localized: "common_runs"),
                    value: "\(workoutManager.runCount)"
                )
                Divider()
                statRow(
                    icon: "clock",
                    label: String(localized: "common_ski_time"),
                    value: Formatters.timer(workoutManager.elapsedTime)
                )

                if let lastCompletedRun = workoutManager.lastCompletedRun {
                    Divider()
                    lastRunSection(lastCompletedRun)
                }
            }
        }
        .padding(.horizontal, WatchSpacing.md)
    }

    private var preferredUnitSystem: UnitSystem {
        workoutManager.preferredUnitSystem
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: icon)
                .font(WatchTypography.statIcon)
                .foregroundStyle(WatchColorTokens.sportAccent)
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
        .padding(.vertical, WatchSpacing.sm)
    }

    private func heartRateText(_ heartRate: Double) -> String {
        guard heartRate > 0 else { return String(localized: "watch_placeholder_dash") }
        let rounded = Int(heartRate.rounded())
        let format = String(localized: "watch_heart_rate_format")
        return String(format: format, locale: Locale.current, rounded)
    }

    private func lastRunSection(_ lastCompletedRun: WatchMessage.LastRunData) -> some View {
        VStack(alignment: .leading, spacing: WatchSpacing.sm) {
            Text(lastRunTitle(for: lastCompletedRun))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: WatchSpacing.md) {
                lastRunMetric(
                    label: String(localized: "stat_max_speed"),
                    value: Formatters.speed(lastCompletedRun.maxSpeed, unit: preferredUnitSystem)
                )
                lastRunMetric(
                    label: String(localized: "common_vertical"),
                    value: Formatters.vertical(lastCompletedRun.verticalDrop, unit: preferredUnitSystem)
                )
            }

            HStack(spacing: WatchSpacing.md) {
                lastRunMetric(
                    label: String(localized: "common_distance"),
                    value: Formatters.distance(lastCompletedRun.distance, unit: preferredUnitSystem)
                )
                lastRunMetric(
                    label: String(localized: "common_duration"),
                    value: Formatters.duration(lastCompletedRun.endDate.timeIntervalSince(lastCompletedRun.startDate))
                )
            }
        }
        .padding(.vertical, WatchSpacing.sm)
    }

    private func lastRunMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: WatchSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastRunTitle(for lastCompletedRun: WatchMessage.LastRunData) -> String {
        let format = String(localized: "watch_last_run_title_format")
        return String(format: format, locale: Locale.current, lastCompletedRun.runNumber)
    }
}
