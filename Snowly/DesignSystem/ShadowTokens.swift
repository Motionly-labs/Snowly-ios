//
//  ShadowTokens.swift
//  Snowly
//
//  Standardized shadow styles for consistent elevation.
//

import SwiftUI

enum ShadowTokens {
    struct Style {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let small = Style(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
        static let medium = Style(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        static let large = Style(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        static let subtle = Style(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        static let innerGlow = Style(color: .white.opacity(0.25), radius: 2, x: 0, y: 1)
        static let brandGlow = Style(color: ColorTokens.brandIceBlue.opacity(0.18), radius: 22, x: 0, y: 12)
        static let brandGlowPressed = Style(color: ColorTokens.brandIceBlue.opacity(0.28), radius: 16, x: 0, y: 8)
        static let danger = Style(color: .red.opacity(0.3), radius: 8, x: 0, y: 2)
        static let topBar = Style(color: .black.opacity(0.15), radius: 8, x: 0, y: -2)
        /// Base-layer drop shadow applied beneath glass buttons. Sits under the
        /// accent glow layer to add depth without competing with the brand color.
        static let glassBase = Style(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func shadowStyle(_ style: ShadowTokens.Style) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
