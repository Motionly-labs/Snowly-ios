//
//  Typography.swift
//  Snowly
//
//  Shared type styles for consistent hierarchy.
//

import SwiftUI

enum Typography {
    // MARK: - Display
    static let onboardingHeroIcon = Font.system(size: 80, weight: .thin)
    static let splashIcon = Font.system(size: 64, weight: .thin)
    static let onboardingIcon = Font.system(size: 60, weight: .regular)
    static let musicIcon = Font.system(size: 48)
    static let splashTitle = Font.system(size: 48, weight: .black)
    static let splashSubtitle = Font.system(size: 18, weight: .light)

    // MARK: - Metric
    static let temperatureHero = Font.system(size: 76, weight: .semibold, design: .rounded)
    static let metricHero = Font.system(size: 72, weight: .bold, design: .rounded)
    static let metricLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    static let metricMedium = Font.system(size: 44, weight: .bold, design: .rounded)
    static let metricSmall = Font.system(size: 36, weight: .bold, design: .rounded)
    static let speedDisplay = Font.system(size: 44, weight: .medium)

    // MARK: - Heading
    static let onboardingTitle = Font.title.weight(.bold)
    static let primaryTitle = Font.title2.weight(.semibold)
    static let headingLarge = Font.system(size: 28, weight: .semibold)
    static let headingMedium = Font.system(size: 22, weight: .semibold)
    static let settingsIcon = Font.system(size: 22)

    // MARK: - Button
    static let buttonLabel = Font.title3.weight(.semibold)
    static let buttonHero = Font.system(size: 26, weight: .bold, design: .rounded)
    static let buttonResume = Font.system(size: 22, weight: .bold, design: .rounded)
    static let buttonStrong = Font.system(size: 18, weight: .bold)

    // MARK: - Body
    static let bodyLabel = Font.system(size: 18, weight: .medium)
    static let bodyMedium = Font.system(size: 17, weight: .medium)
    static let captionMedium = Font.system(size: 16, weight: .medium)

    // MARK: - Small
    static let smallSemibold = Font.system(size: 14, weight: .semibold)
    static let smallBold = Font.system(size: 13, weight: .bold)
    static let smallLabel = Font.system(size: 13, weight: .semibold)
    static let badgeLabel = Font.system(size: 12, weight: .bold)
    static let iconBold = Font.system(size: 16, weight: .bold)

    // MARK: - System Weighted
    static let subheadlineMedium = Font.subheadline.weight(.medium)
    static let captionSemibold = Font.caption.weight(.semibold)
    static let caption2Semibold = Font.caption2.weight(.semibold)
}
