//
//  Constants.swift
//  Snowly
//
//  App-level constants for the iOS app.
//

import SwiftUI

enum AppConstants {

    // MARK: - Share Card Colors (fixed dark palette for rendered 1080x1920 image)
    static let backgroundDark = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let backgroundCard = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.20)

    // MARK: - Touch Targets
    static let minimumTouchTarget: CGFloat = 60  // Gloved operation

    // MARK: - Long Press
    static let longPressDuration: TimeInterval = 2.0

    // MARK: - Animation
    static let defaultAnimation: Animation = .easeInOut(duration: 0.3)

    // MARK: - Share Card
    static let shareCardWidth: CGFloat = 1080
    static let shareCardHeight: CGFloat = 1920

    // MARK: - App Info
    static let appName = "Snowly"
    static let tagline = "Your skiing companion"
}
