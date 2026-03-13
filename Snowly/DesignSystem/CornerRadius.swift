//
//  CornerRadius.swift
//  Snowly
//
//  Standardized corner radius values.
//

import SwiftUI

enum CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    /// Intentionally smaller than xLarge — used for pill-shaped elements (buttons, tags)
    /// where a tighter radius better matches the capsule aesthetic.
    static let pill: CGFloat = 18
    static let xLarge: CGFloat = 24
}
