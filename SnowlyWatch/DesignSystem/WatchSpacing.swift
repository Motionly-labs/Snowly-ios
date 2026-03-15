//
//  WatchSpacing.swift
//  SnowlyWatch
//
//  Tighter spacing grid for watchOS layouts.
//

import SwiftUI

enum WatchSpacing {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16

    // MARK: - Button Geometry

    /// Diameter of the start-session button on IdleView.
    static let startButtonDiameter: CGFloat = 118
    /// Icon size for the start-session button.
    static let startButtonIconSize: CGFloat = 34
    /// Diameter of the stop (hold-to-stop) button.
    static let stopButtonDiameter: CGFloat = 92
    /// Icon size for the stop button.
    static let stopButtonIconSize: CGFloat = 26
    /// Diameter of the pause/resume circle button.
    static let controlButtonSize: CGFloat = 72
}
