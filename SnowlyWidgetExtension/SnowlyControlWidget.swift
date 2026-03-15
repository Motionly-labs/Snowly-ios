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

struct SnowlyControlWidget: ControlWidget {
    private static let kind = "com.snowly.start-tracking-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: TrackingStatusProvider()) { isTracking in
            ControlWidgetToggle(isOn: isTracking, action: SetTrackingEnabledIntent()) {
                Label {
                    Text(String(localized: "control_widget_start"))
                } icon: {
                    Image("logo-control")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            }
            .tint(isTracking ? LiveActivityTokens.pauseAccent : .primary)
        }
        .displayName(LocalizedStringResource("control_widget_display_name"))
        .description(LocalizedStringResource("control_widget_description"))
    }
}
private struct TrackingStatusProvider: ControlValueProvider {
    let previewValue = false

    func currentValue() async throws -> Bool {
        Activity<SnowlyActivityAttributes>.activities.contains { $0.activityState == .active }
    }
}

