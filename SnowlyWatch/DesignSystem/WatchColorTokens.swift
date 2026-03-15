//
//  WatchColorTokens.swift
//  SnowlyWatch
//
//  Brand color tokens for watchOS.
//

import SwiftUI

enum WatchColorTokens {
    static let brandIceBlue = Color(hex: "1E88E5")
    static let brandWarmAmber = Color(hex: "F88800")
    static let brandWarmOrange = Color(hex: "F88000")
    static let brandRed = Color(hex: "D82000")
    static let brandGold = Color(hex: "FFD36A")

    // MARK: - Accent Hierarchy (mirrors iOS ColorTokens)
    /// Primary accent — ice blue. Active tracking, key metrics, primary CTAs.
    static let primaryAccent = brandIceBlue
    /// Secondary accent — warm orange. Secondary actions, offline/independent indicators.
    static let secondaryAccent = brandWarmOrange

    // MARK: - Semantic Aliases
    /// Color for active sport / live tracking elements (matches iOS sportAccent).
    static let sportAccent = primaryAccent
    /// Color for completed session summary elements (matches iOS completedAccent).
    static let completedAccent = primaryAccent
    /// Tint used when the paired iPhone is reachable.
    static let connectedAccent = Color(hex: "34C759")

    // MARK: - Gradients (matches iOS brandGradient)
    static let brandGradient = LinearGradient(
        colors: [Color(hex: "64B5F6"), brandIceBlue],
        startPoint: .leading,
        endPoint: .trailing
    )
}
