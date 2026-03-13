//
//  Opacity.swift
//  Snowly
//
//  Standardized opacity levels for consistent transparency.
//

import SwiftUI

enum Opacity {
    static let invisible: Double = 0.01
    static let faint: Double = 0.06
    /// Hairline separators and very subtle dividers on adaptive backgrounds.
    static let hairline: Double = 0.08
    static let subtle: Double = 0.1
    static let light: Double = 0.12
    /// Accent tint overlay while a glass button is being pressed.
    static let pressingAccent: Double = 0.13
    static let gentle: Double = 0.15
    static let muted: Double = 0.2
    static let soft: Double = 0.25
    static let moderate: Double = 0.3
    static let medium: Double = 0.35
    static let prominent: Double = 0.4
    /// Glass-button idle ring border and glass highlight top edge.
    static let mediumHigh: Double = 0.45
    static let half: Double = 0.5
    /// Accent ring border on active-session buttons (ResumeTrackingButton).
    static let ring: Double = 0.55
    static let strong: Double = 0.6
    static let heavy: Double = 0.85
    static let nearFull: Double = 0.9
}
