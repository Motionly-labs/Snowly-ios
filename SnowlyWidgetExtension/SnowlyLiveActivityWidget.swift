//
//  SnowlyLiveActivityWidget.swift
//  SnowlyWidgetExtension
//
//  Live Activity widget for ski tracking.
//  Shows speed, vertical, run count, and elapsed time
//  on the lock screen and Dynamic Island.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct SnowlyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnowlyActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                expandedContent(context: context)
            } compactLeading: {
                activityIcon(for: context.state.currentActivity, isPaused: context.state.isPaused)
                    .font(.caption)
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(formattedSpeed(context.state.currentSpeed, unit: context.attributes.unitSystem))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "figure.skiing.downhill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SnowlyActivityAttributes>) -> some View {
        let state = context.state
        let unit = context.attributes.unitSystem

        HStack(spacing: 16) {
            // Left: activity icon + elapsed time
            VStack(spacing: 4) {
                activityIcon(for: state.currentActivity, isPaused: state.isPaused)
                    .font(.title2)
                Text(formattedElapsedTime(state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 56)

            // Center: current speed (large)
            VStack(spacing: 2) {
                Text(formattedSpeed(state.currentSpeed, unit: unit))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                Text(speedUnitLabel(unit: unit))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Right: vertical + run count
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(formattedVertical(state.totalVertical, unit: unit))
                        .font(.callout.bold().monospacedDigit())
                    Text(verticalUnitLabel(unit: unit))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text("\(state.runCount)")
                        .font(.callout.bold().monospacedDigit())
                    Text(String(localized: "live_activity_runs"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 56)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.75))
    }

    // MARK: - Dynamic Island Expanded

    @DynamicIslandExpandedContentBuilder
    private func expandedContent(context: ActivityViewContext<SnowlyActivityAttributes>) -> DynamicIslandExpandedContent<some View> {
        let state = context.state
        let unit = context.attributes.unitSystem

        DynamicIslandExpandedRegion(.leading) {
            Label {
                Text(activityLabel(for: state.currentActivity, isPaused: state.isPaused))
            } icon: {
                activityIcon(for: state.currentActivity, isPaused: state.isPaused)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        DynamicIslandExpandedRegion(.trailing) {
            Text(formattedElapsedTime(state.elapsedSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        DynamicIslandExpandedRegion(.bottom) {
            HStack(spacing: 0) {
                statCell(
                    value: formattedSpeed(state.currentSpeed, unit: unit),
                    label: speedUnitLabel(unit: unit)
                )
                statCell(
                    value: formattedSpeed(state.maxSpeed, unit: unit),
                    label: String(localized: "live_activity_max")
                )
                statCell(
                    value: formattedVertical(state.totalVertical, unit: unit),
                    label: verticalUnitLabel(unit: unit)
                )
                statCell(
                    value: "\(state.runCount)",
                    label: String(localized: "live_activity_runs")
                )
            }
        }
    }

    // MARK: - Helpers

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityIcon(for activity: String, isPaused: Bool) -> Image {
        if isPaused {
            return Image(systemName: "pause.fill")
        }
        switch activity {
        case "skiing":
            return Image(systemName: "figure.skiing.downhill")
        case "chairlift":
            return Image(systemName: "cablecar")
        default:
            return Image(systemName: "figure.skiing.downhill")
        }
    }

    private func activityLabel(for activity: String, isPaused: Bool) -> String {
        if isPaused {
            return String(localized: "live_activity_paused")
        }
        switch activity {
        case "skiing":
            return String(localized: "live_activity_skiing")
        case "chairlift":
            return String(localized: "live_activity_chairlift")
        default:
            return String(localized: "live_activity_idle")
        }
    }

    private func formattedSpeed(_ metersPerSecond: Double, unit: UnitSystem) -> String {
        Formatters.speedValue(metersPerSecond, unit: unit)
    }

    private func formattedVertical(_ meters: Double, unit: UnitSystem) -> String {
        String(format: "%.0f", unit == .imperial ? UnitConversion.metersToFeet(meters) : meters)
    }

    private func speedUnitLabel(unit: UnitSystem) -> String {
        Formatters.speedUnit(unit)
    }

    private func verticalUnitLabel(unit: UnitSystem) -> String {
        Formatters.verticalUnit(unit)
    }

    private func formattedElapsedTime(_ totalSeconds: Int) -> String {
        Formatters.timer(TimeInterval(totalSeconds))
    }
}
