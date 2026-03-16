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

    // MARK: - Hold Button Geometry

    /// Minimum ring stroke width for HoldProgressCircleButton.
    static let holdButtonMinRingWidth: CGFloat = 4
    /// Ring width as a proportion of button diameter.
    static let holdButtonRingWidthRatio: CGFloat = 0.065
    /// Inner filled circle as a proportion of button diameter.
    static let holdButtonInnerDiameterRatio: CGFloat = 0.78
    /// Maximum finger-drift distance before a hold gesture cancels.
    static let holdButtonGestureMaxDistance: CGFloat = 28

    // MARK: - Icon Frame Widths

    /// Leading icon frame width in dense stat rows (StatsPageView).
    static let statIconFrameWidth: CGFloat = 18
    /// Leading icon frame width in summary rows (WorkoutSummaryView).
    static let summaryIconFrameWidth: CGFloat = 20

    // MARK: - Page Indicator

    /// Width of the active (selected) page indicator pill.
    static let pageIndicatorActiveWidth: CGFloat = 14
    /// Diameter/height of page indicator dots.
    static let pageIndicatorInactiveSize: CGFloat = 6
}
