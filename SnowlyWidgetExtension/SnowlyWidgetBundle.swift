//
//  SnowlyWidgetBundle.swift
//  SnowlyWidgetExtension
//
//  Entry point for the widget extension.
//

import SwiftUI
import WidgetKit

@main
struct SnowlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        SnowlyLiveActivityWidget()
        SnowlyControlWidget()
    }
}
