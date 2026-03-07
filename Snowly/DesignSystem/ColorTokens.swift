//
//  ColorTokens.swift
//  Snowly
//
//  Centralized color constants derived from brand identity.
//  Use these instead of inline Color(hex:) calls.
//

import SwiftUI

enum ColorTokens {
    // MARK: - Brand
    static let brandWarmAmber = Color(hex: "F88800")
    static let brandWarmOrange = Color(hex: "F88000")
    static let brandRed = Color(hex: "D82000")
    static let brandGold = Color(hex: "FFD36A")

    // MARK: - Text
    static let textOnBrand = Color.black.opacity(0.86)

    // MARK: - Semantic
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    // MARK: - Sensor Status
    static let sensorGreen = Color(hex: "39D353")
    static let sensorRed = brandRed

    // MARK: - Trail Difficulty
    static let trailGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let trailBlue = Color(red: 0.25, green: 0.52, blue: 0.96)
    static let trailRed = Color(red: 0.92, green: 0.26, blue: 0.24)
    static let trailBlack = Color(red: 0.35, green: 0.35, blue: 0.40)
    static let trailOrange = Color(red: 1.0, green: 0.6, blue: 0.15)
    static let trailYellow = Color(red: 0.95, green: 0.85, blue: 0.25)
    static let trailUnknown = Color.white.opacity(0.35)

    // MARK: - Surface
    static let surfaceOverlay = Color.white.opacity(0.12)
    static let surfaceDivider = Color.white.opacity(0.15)

    // MARK: - Gradients
    static let brandGradient = LinearGradient(
        colors: [brandWarmAmber, brandWarmOrange],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let progressArcGradient = LinearGradient(
        colors: [brandGold, brandWarmAmber, brandWarmOrange, brandRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

}
