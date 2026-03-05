//
//  WatchColorTokens.swift
//  SnowlyWatch
//
//  Brand color tokens for watchOS.
//

import SwiftUI

enum WatchColorTokens {
    static let brandWarmAmber = Color(hex: "F88800")
    static let brandWarmOrange = Color(hex: "F88000")
    static let brandRed = Color(hex: "D82000")
    static let brandGold = Color(hex: "FFD36A")

    static let brandGradient = LinearGradient(
        colors: [brandWarmAmber, brandWarmOrange],
        startPoint: .leading,
        endPoint: .trailing
    )
}
