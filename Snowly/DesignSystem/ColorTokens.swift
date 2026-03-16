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
    static let brandIceBlue = Color(hex: "1E88E5")
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
    /// Adaptive surface tint: white 12% in dark mode, black 6% in light mode.
    static let surfaceOverlay = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)   // Opacity.light
            : UIColor(white: 0, alpha: 0.06)   // Opacity.faint
    })
    /// Adaptive divider: white 15% in dark mode, black 8% in light mode.
    static let surfaceDivider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.15)   // Opacity.gentle
            : UIColor(white: 0, alpha: 0.08)   // Opacity.hairline
    })
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryGroupedBackground = Color(uiColor: .secondarySystemGroupedBackground)

    // MARK: - Accent Hierarchy
    /// Primary accent — adaptive: ice blue (#1E88E5) in light mode, warm amber (#F88800) in dark mode.
    /// Use for navigation, selected states, key metrics, primary CTAs.
    static let primaryAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: "F88800"))  // brandWarmAmber
            : UIColor(Color(hex: "1E88E5")) // brandIceBlue
    })
    /// Secondary accent — warm orange. Fixed across modes.
    /// Use for media controls, lift chart segments, and layout-edit affordances.
    static let secondaryAccent = brandWarmOrange

    // MARK: - Activity State Semantic
    /// Color for skiing segments in charts and activity indicators.
    static let skiingAccent = primaryAccent
    /// Color for lift/gondola segments in charts and activity indicators.
    static let liftAccent = secondaryAccent
    /// Color for walk and idle segments in charts.
    static let walkAccent = Color.secondary.opacity(0.85)

    // MARK: - Context Semantic (domain aliases — resolve to the accent hierarchy above)
    static let sportAccent = primaryAccent       // Active sport, live tracking, skiing
    static let completedAccent = primaryAccent   // Completed sessions, history, archived data

    // MARK: - Map Overlays (satellite map — always dark background)
    /// Dashed polyline stroke for ski lifts on the satellite map.
    static let mapLiftPolyline = Color.white.opacity(0.85)   // Opacity.heavy
    /// Text color for lift name labels on the satellite map.
    static let mapLiftLabel = Color.white.opacity(0.9)        // Opacity.nearFull
    /// Shadow dot below the crosshair pin in pinning mode.
    static let mapPinShadow = Color.black.opacity(0.25)       // Opacity.soft
    /// White border ring on location dot annotations.
    static let mapAnnotationBorder = Color.white

    // MARK: - Location Dot
    /// Initial letter text rendered inside a colored location dot.
    static let locationDotLabel = Color.white

    // MARK: - Share Card (fixed light-mode export image — not adaptive)
    static let shareCardBackground = Color(hex: "F1F5F9")      // slate-100
    static let shareCardGridDot = Color(hex: "A8A2BC")          // lavender dot overlay
    static let shareCardTitle = Color(hex: "1E293B")            // slate-800
    static let shareCardHeadline = Color(hex: "0F172A")         // slate-900
    static let shareCardSecondary = Color(hex: "64748B")        // slate-500
    static let shareCardMuted = Color(hex: "94A3B8")            // slate-400
    static let shareCardBorder = Color(hex: "E2E8F0")           // slate-200

    // MARK: - Gradients

    /// Top-lit edge highlight shared by all glass circular buttons.
    /// Mimics the iOS 26 liquid-glass top-edge specular reflection.
    static let glassHighlightGradient = LinearGradient(
        colors: [Color.white.opacity(Opacity.mediumHigh), Color.white.opacity(Opacity.subtle)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradient = LinearGradient(
        colors: [Color(hex: "64B5F6"), brandIceBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let progressArcGradient = LinearGradient(
        colors: [Color(hex: "90CAF9"), brandIceBlue, Color(hex: "1565C0")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

}
