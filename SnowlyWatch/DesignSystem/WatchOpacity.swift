//
//  WatchOpacity.swift
//  SnowlyWatch
//
//  Opacity scale for watchOS surfaces and overlays.
//

import Foundation

enum WatchOpacity {
    /// Background fill for stat/live cards.
    static let cardBackground: Double = 0.08
    /// Background fill for small chips and pills.
    static let chipBackground: Double = 0.12
    /// Background fill for control buttons (pause/resume circle).
    static let controlBackground: Double = 0.16
    /// Track ring behind the hold-progress arc.
    static let ringTrack: Double = 0.18
    /// Inner fill circle on the hold-progress button.
    static let ringInnerFill: Double = 0.18
    /// Primary elements in Always-On display.
    static let alwaysOn: Double = 0.6
    /// Inactive page indicator dots.
    static let pageIndicatorInactive: Double = 0.28
}
