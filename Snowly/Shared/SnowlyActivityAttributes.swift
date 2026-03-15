//
//  SnowlyActivityAttributes.swift
//  Snowly
//
//  ActivityKit attributes for the ski tracking Live Activity.
//  Shared between the main app and SnowlyWidgetExtension.
//

import ActivityKit
import Foundation

struct SnowlyActivityAttributes: ActivityAttributes {
    /// Fixed at session start — does not change during the activity.
    let startDate: Date
    let unitSystem: UnitSystem

    /// Updated throughout the session.
    struct ContentState: Codable, Hashable, Sendable {
        let currentSpeed: Double   // m/s
        let totalVertical: Double  // meters
        let runCount: Int
        let elapsedSeconds: Int
        let currentActivity: String // "skiing", "lift", "walk", "idle"
        let isPaused: Bool
        let maxSpeed: Double       // m/s
    }
}
