//
//  Constants.swift
//  Snowly
//
//  App-level constants for the iOS app.
//

import SwiftUI

enum AppConstants {

    // MARK: - Share Card Colors (fixed dark palette for rendered image)
    static let backgroundDark = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let backgroundCard = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.20)

    // MARK: - Touch Targets
    static let minimumTouchTarget: CGFloat = 60  // Gloved operation

    // MARK: - Long Press
    static let longPressDuration: TimeInterval = 2.0

    // MARK: - Share Card
    static let shareCardWidth: CGFloat = 1920
    static let shareCardHeight: CGFloat = 1080
    static let shareCardExportScale: CGFloat = 3.0
    static let shareCardMapSnapshotScale: CGFloat = 3.0
    static let shareCardHorizontalPadding: CGFloat = 44
    static let shareCardVerticalPadding: CGFloat = 38
    static let shareCardColumnSpacing: CGFloat = 36
    static let shareCardInfoPanelWidth: CGFloat = 640

    static var shareCardMapPanelWidth: CGFloat {
        shareCardWidth - (shareCardHorizontalPadding * 2) - shareCardColumnSpacing - shareCardInfoPanelWidth
    }

    static var shareCardMapPanelHeight: CGFloat {
        shareCardHeight - (shareCardVerticalPadding * 2)
    }

    // MARK: - App Info
    static let appName = "Snowly"
    static let tagline = String(localized: "common_app_tagline")
}
