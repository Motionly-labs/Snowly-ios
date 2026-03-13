//
//  BatteryIndicator.swift
//  Snowly
//
//  Shows battery level and estimated remaining tracking time.
//

import SwiftUI

struct BatteryIndicator: View {
    let level: Float
    let isCharging: Bool
    let estimatedTime: TimeInterval?

    private var color: Color {
        if isCharging { return ColorTokens.success }
        if level <= SharedConstants.lowBatteryThreshold { return ColorTokens.error }
        if level <= SharedConstants.lowBatteryWarningThreshold { return .yellow }
        return ColorTokens.success
    }

    private var iconName: String {
        if isCharging { return "battery.100percent.bolt" }
        if level <= 0.1 { return "battery.0percent" }
        if level <= 0.25 { return "battery.25percent" }
        if level <= 0.5 { return "battery.50percent" }
        if level <= 0.75 { return "battery.75percent" }
        return "battery.100percent"
    }

    private func timeRemainingText(_ time: TimeInterval) -> String {
        let format = String(localized: "battery_time_remaining_format")
        return String(format: format, locale: Locale.current, Formatters.duration(time))
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(color)

            Text("\(Int(level * 100))%")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)

            if let time = estimatedTime {
                Text(timeRemainingText(time))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(String(localized: "accessibility_battery_level"))
        .accessibilityValue("\(Int(level * 100))%")
    }
}
