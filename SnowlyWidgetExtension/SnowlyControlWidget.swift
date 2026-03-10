//
//  SnowlyControlWidget.swift
//  SnowlyWidgetExtension
//
//  Control Center widget to start ski tracking.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct SnowlyControlWidget: ControlWidget {
    private static let kind = "com.snowly.start-tracking-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: TrackingStatusProvider()) { isTracking in
            ControlWidgetToggle(isOn: isTracking, action: SetTrackingEnabledIntent()) {
                Label(
                    String(localized: "control_widget_start"),
                    systemImage: isTracking ? "figure.skiing.downhill.circle.fill" : "figure.skiing.downhill"
                )
            }
            .tint(isTracking ? .orange : .primary)
        }
        .displayName("control_widget_display_name")
        .description("control_widget_description")
    }
}

@available(iOS 18.0, *)
private struct TrackingStatusProvider: ControlValueProvider {
    let previewValue = false

    func currentValue() async throws -> Bool {
        Activity<SnowlyActivityAttributes>.activities.contains { $0.activityState == .active }
    }
}
