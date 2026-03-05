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

    // MARK: - Sensor Status
    static let sensorGreen = Color(hex: "39D353")
    static let sensorRed = brandRed

    // MARK: - Gradients
    static let brandGradient = LinearGradient(
        colors: [brandWarmAmber, brandWarmOrange],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let brandVerticalGradient = LinearGradient(
        colors: [brandWarmAmber, brandWarmOrange],
        startPoint: .top,
        endPoint: .bottom
    )

    static let progressArcGradient = LinearGradient(
        colors: [brandGold, brandWarmAmber, brandWarmOrange, brandRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let buttonTextGradient = LinearGradient(
        colors: [brandWarmAmber, brandWarmOrange, brandRed],
        startPoint: .leading,
        endPoint: .trailing
    )
}
