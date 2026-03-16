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
                    .foregroundStyle(LiveActivityTokens.minimalForeground)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SnowlyActivityAttributes>) -> some View {
        let state = context.state
        let unit = context.attributes.unitSystem

        VStack(alignment: .leading, spacing: LiveActivityTokens.sectionSpacing) {
            HStack(alignment: .center, spacing: LiveActivityTokens.sectionSpacing) {
                snowlyLogo(size: 30)

                VStack(alignment: .leading, spacing: LiveActivityTokens.labelSpacing) {
                    Text(activityLabel(for: state.currentActivity, isPaused: state.isPaused))
                        .font(.caption.bold())
                    Text(formattedElapsedTime(state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: LiveActivityTokens.minSpacerLength)

                HStack(alignment: .lastTextBaseline, spacing: LiveActivityTokens.metricValueSpacing) {
                    Text(formattedSpeed(state.currentSpeed, unit: unit))
                        .font(LiveActivityTokens.speedFont)
                        .lineLimit(1)
                        .minimumScaleFactor(LiveActivityTokens.speedMinScale)
                    Text(speedUnitLabel(unit: unit))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: LiveActivityTokens.pausePlayIconSize))
                        .foregroundStyle(state.isPaused ? LiveActivityTokens.playAccent : LiveActivityTokens.pauseAccent)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiveActivityTokens.gridSpacing), count: 2), spacing: LiveActivityTokens.gridSpacing) {
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
        .padding(.horizontal, LiveActivityTokens.contentPaddingH)
        .padding(.vertical, LiveActivityTokens.contentPaddingV)
    }

    // MARK: - Dynamic Island Expanded

    @DynamicIslandExpandedContentBuilder
    private func expandedContent(context: ActivityViewContext<SnowlyActivityAttributes>) -> DynamicIslandExpandedContent<some View> {
        let state = context.state
        let unit = context.attributes.unitSystem

        DynamicIslandExpandedRegion(.leading) {
            HStack(spacing: LiveActivityTokens.pillSpacing) {
                snowlyLogo(size: 14)
                Image(systemName: playbackIconName(isPaused: state.isPaused))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }

        DynamicIslandExpandedRegion(.trailing) {
            HStack(spacing: LiveActivityTokens.pillSpacing) {
                Text(formattedElapsedTime(state.elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(state.isPaused ? LiveActivityTokens.playAccent : LiveActivityTokens.pauseAccent)
                }
                .buttonStyle(.plain)
            }
        }

        DynamicIslandExpandedRegion(.bottom) {
            VStack(alignment: .leading, spacing: LiveActivityTokens.gridSpacing) {
                Text("\(formattedSpeed(state.currentSpeed, unit: unit)) \(speedUnitLabel(unit: unit))")
                    .font(.title3.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(LiveActivityTokens.contentMinScale)
                HStack(spacing: LiveActivityTokens.pillSpacing) {
                    metricPill("\(String(localized: "live_activity_max")) \(formattedSpeed(state.maxSpeed, unit: unit)) \(speedUnitLabel(unit: unit))")
                    metricPill("\(String(localized: "common_vertical")) \(formattedVertical(state.totalVertical, unit: unit)) \(verticalUnitLabel(unit: unit))")
                }
                HStack(spacing: LiveActivityTokens.pillSpacing) {
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

            HStack(spacing: LiveActivityTokens.compactItemSpacing) {
                Image(systemName: item.symbolName)
                    .font(.caption2)
                Text(item.value)
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(LiveActivityTokens.compactForeground)
            .lineLimit(1)
            .minimumScaleFactor(LiveActivityTokens.contentMinScale)
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
        VStack(alignment: align, spacing: LiveActivityTokens.labelSpacing) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(LiveActivityTokens.pillMinScale)
        }
        .padding(.horizontal, LiveActivityTokens.chipPaddingH)
        .padding(.vertical, LiveActivityTokens.chipPaddingV)
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LiveActivityTokens.chipCornerRadius))
    }

    private func metricPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(LiveActivityTokens.pillMinScale)
            .padding(.horizontal, LiveActivityTokens.pillPaddingH)
            .padding(.vertical, LiveActivityTokens.pillPaddingV)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func snowlyLogo(size: CGFloat) -> some View {
        Image("logo-small")
            .resizable()
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
