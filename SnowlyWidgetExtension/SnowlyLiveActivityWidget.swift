//
//  SnowlyLiveActivityWidget.swift
//  SnowlyWidgetExtension
//
//  Live Activity widget for ski tracking.
//  Shows speed, vertical, run count, and elapsed time
//  on the lock screen and Dynamic Island.
//

import ActivityKit
import AppIntents
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
                snowlyLogo(size: 16)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                Image(systemName: playbackIconName(isPaused: context.state.isPaused))
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

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                snowlyLogo(size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activityLabel(for: state.currentActivity, isPaused: state.isPaused))
                        .font(.caption.bold())
                    Text(formattedElapsedTime(state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formattedSpeed(state.currentSpeed, unit: unit))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(speedUnitLabel(unit: unit))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(state.isPaused ? .green : .orange)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                statChip(
                    label: String(localized: "live_activity_max"),
                    value: "\(formattedSpeed(state.maxSpeed, unit: unit)) \(speedUnitLabel(unit: unit))",
                    align: .leading
                )
                statChip(
                    label: String(localized: "live_activity_runs"),
                    value: "\(state.runCount)",
                    align: .trailing
                )
                statChip(
                    label: String(localized: "common_vertical"),
                    value: "\(formattedVertical(state.totalVertical, unit: unit)) \(verticalUnitLabel(unit: unit))",
                    align: .leading
                )
                statChip(
                    label: String(localized: "stat_current_speed"),
                    value: "\(formattedSpeed(state.currentSpeed, unit: unit)) \(speedUnitLabel(unit: unit))",
                    align: .trailing
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Dynamic Island Expanded

    @DynamicIslandExpandedContentBuilder
    private func expandedContent(context: ActivityViewContext<SnowlyActivityAttributes>) -> DynamicIslandExpandedContent<some View> {
        let state = context.state
        let unit = context.attributes.unitSystem

        DynamicIslandExpandedRegion(.leading) {
            HStack(spacing: 6) {
                snowlyLogo(size: 14)
                Image(systemName: playbackIconName(isPaused: state.isPaused))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }

        DynamicIslandExpandedRegion(.trailing) {
            HStack(spacing: 6) {
                Text(formattedElapsedTime(state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(state.isPaused ? .green : .orange)
                }
                .buttonStyle(.plain)
            }
        }

        DynamicIslandExpandedRegion(.bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(formattedSpeed(state.currentSpeed, unit: unit)) \(speedUnitLabel(unit: unit))")
                    .font(.title3.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    metricPill("\(String(localized: "live_activity_max")) \(formattedSpeed(state.maxSpeed, unit: unit)) \(speedUnitLabel(unit: unit))")
                    metricPill("\(String(localized: "common_vertical")) \(formattedVertical(state.totalVertical, unit: unit)) \(verticalUnitLabel(unit: unit))")
                }
                HStack(spacing: 6) {
                    metricPill("\(String(localized: "live_activity_runs")) \(state.runCount)")
                    metricPill(formattedElapsedTime(state.elapsedSeconds))
                    metricPill(activityLabel(for: state.currentActivity, isPaused: state.isPaused))
                }
            }
        }
    }

    // MARK: - Helpers

    private struct CompactCarouselItem {
        let symbolName: String
        let value: String
    }

    private func compactTrailingView(context: ActivityViewContext<SnowlyActivityAttributes>) -> some View {
        TimelineView(.periodic(from: context.attributes.startDate, by: 4)) { timeline in
            let item = compactCarouselItem(context: context, at: timeline.date)

            HStack(spacing: 3) {
                Image(systemName: item.symbolName)
                    .font(.caption2)
                Text(item.value)
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.numericText())
        }
    }

    private func compactCarouselItem(
        context: ActivityViewContext<SnowlyActivityAttributes>,
        at date: Date
    ) -> CompactCarouselItem {
        let state = context.state
        let unit = context.attributes.unitSystem
        let items = [
            CompactCarouselItem(symbolName: "speedometer", value: formattedSpeed(state.currentSpeed, unit: unit)),
            CompactCarouselItem(symbolName: "hare.fill", value: formattedSpeed(state.maxSpeed, unit: unit)),
            CompactCarouselItem(symbolName: "arrow.up.and.down", value: "\(formattedVertical(state.totalVertical, unit: unit))\(verticalUnitLabel(unit: unit))"),
            CompactCarouselItem(symbolName: "flag.checkered", value: "\(state.runCount)"),
            CompactCarouselItem(symbolName: "timer", value: formattedElapsedTime(state.elapsedSeconds))
        ]

        let secondsSinceStart = max(0, Int(date.timeIntervalSince(context.attributes.startDate)))
        let index = (secondsSinceStart / 4) % items.count
        return items[index]
    }

    private func statChip(label: String, value: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func snowlyLogo(size: CGFloat) -> some View {
        Image("SnowlyLiveLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func playbackIconName(isPaused: Bool) -> String {
        isPaused ? "pause.fill" : "play.fill"
    }

    private func activityLabel(for activity: String, isPaused: Bool) -> String {
        if isPaused {
            return String(localized: "live_activity_paused")
        }
        switch activity {
        case "skiing":
            return String(localized: "live_activity_skiing")
        case "lift":
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
