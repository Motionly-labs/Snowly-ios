//
//  SnowlyControlWidget.swift
//  SnowlyWidgetExtension
//
//  Control Center widget to start ski tracking.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct SnowlyControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.snowly.start-tracking-control") {
            ControlWidgetButton(action: StartTrackingIntent()) {
                Label(String(localized: "control_widget_start"), systemImage: "figure.skiing.downhill")
            }
        }
        .displayName("control_widget_display_name")
        .description("control_widget_description")
    }
}
