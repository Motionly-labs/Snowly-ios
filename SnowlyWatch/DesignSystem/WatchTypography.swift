//
//  WatchTypography.swift
//  SnowlyWatch
//
//  Display font styles for watchOS. Use these instead of
//  inline .system(size:weight:design:) calls.
//

import SwiftUI

enum WatchTypography {
    /// Large elapsed-time display on the main metrics page.
    static let timerLarge: Font = .system(size: 46, weight: .bold, design: .rounded).monospacedDigit()
    /// Reduced elapsed-time display in Always-On mode.
    static let timerAlwaysOn: Font = .system(size: 36, weight: .bold, design: .rounded).monospacedDigit()
    /// Primary metric value on the live workout page (runs, vertical).
    /// Uses dynamic-type title3 with rounded design, matching watchOS Workout app metric style.
    static let metricValue: Font = .system(.title3, design: .rounded).monospacedDigit().weight(.semibold)
    /// Icon inside the pause/resume control button.
    static let controlIcon: Font = .system(size: 24, weight: .bold)
    /// Icon in a stat row (StatsPageView).
    static let statIcon: Font = .system(size: 13, weight: .semibold)
}
