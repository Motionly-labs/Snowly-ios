//
//  WorkoutActiveView.swift
//  SnowlyWatch
//
//  Main workout view with paged metrics.
//

import SwiftUI

struct WorkoutActiveView: View {
    private enum Page: Int, CaseIterable {
        case live
        case stats
        case controls
    }

    @Environment(WatchWorkoutManager.self) private var workoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var selectedPage: Page = ProcessInfo.processInfo.arguments.contains("-watch_ui_testing_controls")
        ? .controls
        : .live
    private let pageOrder: [Page] = [.stats, .live, .controls]

    var body: some View {
        if isLuminanceReduced {
            alwaysOnDisplay
        } else {
            VStack(spacing: WatchSpacing.sm) {
                TabView(selection: $selectedPage) {
                    StatsPageView()
                        .tag(Page.stats)
                    mainMetricsPage
                        .tag(Page.live)
                    WorkoutControlsView()
                        .tag(Page.controls)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if let statusMessage = workoutManager.statusMessage {
                    Text(statusMessage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, WatchSpacing.md)
                }

                pageIndicator
            }
            .accessibilityIdentifier("watch_active_screen")
        }
    }

    // MARK: - Main Metrics

    private var mainMetricsPage: some View {
        VStack(spacing: WatchSpacing.lg) {
            Spacer()

            Text(Formatters.timer(workoutManager.elapsedTime))
                .font(WatchTypography.timerLarge)
                .foregroundStyle(WatchColorTokens.brandGradient)
                .contentTransition(.numericText())

            HStack(spacing: WatchSpacing.sm) {
                liveMetric(
                    icon: "number",
                    label: String(localized: "common_runs"),
                    value: "\(workoutManager.runCount)"
                )
                liveMetric(
                    icon: "arrow.triangle.swap",
                    label: String(localized: "common_distance"),
                    value: Formatters.distance(workoutManager.totalDistance, unit: preferredUnitSystem)
                )
            }

            liveChip(
                icon: "heart.fill",
                value: heartRateText(workoutManager.currentHeartRate)
            )
            .padding(.top, WatchSpacing.xs)

            Spacer(minLength: WatchSpacing.sm)
        }
        .padding(WatchSpacing.md)
    }

    // MARK: - Always-On Display

    private var alwaysOnDisplay: some View {
        VStack(spacing: WatchSpacing.md) {
            Spacer()

            Text(Formatters.timer(workoutManager.elapsedTime))
                .font(WatchTypography.timerAlwaysOn)
                .foregroundStyle(WatchColorTokens.sportAccent.opacity(WatchOpacity.alwaysOn))

            Text("\(workoutManager.runCount) \(String(localized: "common_runs"))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(WatchOpacity.alwaysOn))

            Spacer()
        }
        .accessibilityIdentifier("watch_active_screen")
    }

    private var pageIndicator: some View {
        HStack(spacing: WatchSpacing.sm) {
            ForEach(pageOrder, id: \.rawValue) { page in
                Capsule()
                    .fill(page == selectedPage ? Color.white : Color.white.opacity(WatchOpacity.pageIndicatorInactive))
                    .frame(width: page == selectedPage ? WatchSpacing.pageIndicatorActiveWidth : WatchSpacing.pageIndicatorInactiveSize, height: WatchSpacing.pageIndicatorInactiveSize)
            }
        }
        .padding(.bottom, WatchSpacing.xs)
    }

    private func liveMetric(icon: String, label: String, value: String) -> some View {
        VStack(spacing: WatchSpacing.xs) {
            Text(value)
                .font(WatchTypography.metricValue)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: WatchSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func liveChip(icon: String, value: String) -> some View {
        HStack(spacing: WatchSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(value)
                .font(.caption2.monospacedDigit())
                .bold()
        }
        .foregroundStyle(.secondary)
    }

    private func heartRateText(_ heartRate: Double) -> String {
        guard heartRate > 0 else { return String(localized: "watch_placeholder_dash") }
        let rounded = Int(heartRate.rounded())
        let format = String(localized: "watch_heart_rate_format")
        return String(format: format, locale: Locale.current, rounded)
    }

    private var preferredUnitSystem: UnitSystem {
        workoutManager.preferredUnitSystem
    }
}
