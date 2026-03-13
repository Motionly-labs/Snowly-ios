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
    @State private var selectedPage: Page = .live
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

                pageIndicator
            }
        }
    }

    // MARK: - Main Metrics

    private var mainMetricsPage: some View {
        VStack(spacing: WatchSpacing.lg) {
            Spacer()

            Text(String(localized: "common_ski_time"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(Formatters.timer(workoutManager.elapsedTime))
                .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColorTokens.brandGradient)
                .contentTransition(.numericText())

            HStack(spacing: WatchSpacing.sm) {
                liveCard(
                    icon: "number",
                    label: String(localized: "common_runs"),
                    value: "\(workoutManager.runCount)"
                )
                liveCard(
                    icon: "mountain.2.fill",
                    label: String(localized: "common_vertical"),
                    value: Formatters.vertical(workoutManager.totalVertical, unit: preferredUnitSystem)
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
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColorTokens.brandWarmAmber.opacity(0.6))

            Text("\(workoutManager.runCount) \(String(localized: "common_runs"))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: WatchSpacing.sm) {
            ForEach(pageOrder, id: \.rawValue) { page in
                Capsule()
                    .fill(page == selectedPage ? Color.white : Color.white.opacity(0.28))
                    .frame(width: page == selectedPage ? 14 : 6, height: 6)
            }
        }
        .padding(.bottom, WatchSpacing.xs)
    }

    private func liveCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: WatchSpacing.xs) {
            HStack(spacing: WatchSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WatchSpacing.sm)
        .padding(.horizontal, WatchSpacing.xs)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func liveChip(icon: String, value: String) -> some View {
        HStack(spacing: WatchSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(value)
                .font(.caption2.monospacedDigit())
                .bold()
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, WatchSpacing.sm)
        .padding(.vertical, WatchSpacing.xs)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    private func heartRateText(_ heartRate: Double) -> String {
        guard heartRate > 0 else { return String(localized: "watch_placeholder_dash") }
        let rounded = Int(heartRate.rounded())
        let format = String(localized: "watch_heart_rate_format")
        return String(format: format, locale: Locale.current, rounded)
    }

    private var preferredUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}
