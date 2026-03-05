//
//  DeviceSettings.swift
//  Snowly
//
//  Device-specific settings stored in local-only SwiftData store.
//  Not synced via CloudKit (each device has its own onboarding state
//  and HealthKit preferences).
//

import Foundation
import SwiftData
import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: String(localized: "settings_appearance_system")
        case .light: String(localized: "settings_appearance_light")
        case .dark: String(localized: "settings_appearance_dark")
        }
    }
}

@Model
final class DeviceSettings {
    @Attribute(.unique) var id: UUID = UUID()
    var healthKitEnabled: Bool = false
    var hasCompletedOnboarding: Bool = false
    var appearanceMode: String = AppearanceMode.system.rawValue
    var createdAt: Date = Date()

    var resolvedAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var colorScheme: ColorScheme? {
        resolvedAppearance.colorScheme
    }

    init(
        id: UUID = UUID(),
        healthKitEnabled: Bool = false,
        hasCompletedOnboarding: Bool = false,
        appearanceMode: AppearanceMode = .system,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.healthKitEnabled = healthKitEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.appearanceMode = appearanceMode.rawValue
        self.createdAt = createdAt
    }
}
