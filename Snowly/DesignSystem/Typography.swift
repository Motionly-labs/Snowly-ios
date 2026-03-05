//
//  Typography.swift
//  Snowly
//
//  Shared type styles for consistent hierarchy.
//

import SwiftUI

enum Typography {
    static let onboardingHeroIcon = Font.system(size: 80, weight: .thin)
    static let onboardingIcon = Font.system(size: 60, weight: .regular)
    static let onboardingTitle = Font.title.weight(.bold)
    static let buttonLabel = Font.title3.weight(.semibold)

    static let primaryTitle = Font.title2.weight(.semibold)
    static let metricHero = Font.system(size: 72, weight: .bold, design: .rounded)
    static let temperatureHero = Font.system(size: 76, weight: .semibold, design: .rounded)
}
