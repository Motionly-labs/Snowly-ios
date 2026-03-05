//
//  SnowlyWidgetBundle.swift
//  SnowlyWatch
//
//  Widget bundle for watchOS complications.
//  Note: Does NOT use @main — the watch app is the entry point.
//  Register widgets via the app's widget extension target.
//

import SwiftUI
import WidgetKit

struct SnowlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActiveSessionWidget()
    }
}
