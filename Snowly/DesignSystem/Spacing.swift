//
//  Spacing.swift
//  Snowly
//
//  4-point spacing grid for consistent layout.
//

import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let gap: CGFloat = 6
    static let sm: CGFloat = 8
    static let gutter: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let card: CGFloat = 18
    static let content: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let section: CGFloat = 48

    // MARK: - Component Sizes
    /// Diameter of the primary circular hero button (Start / Resume).
    /// Shared by LongPressStartButton and ResumeTrackingButton.
    static let heroButton: CGFloat = 188
    /// Width of the left stats panel in the landscape tracking dashboard.
    static let landscapeStatPanel: CGFloat = 210
}
