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

enum LiveActivityRefreshIntervalOption: Int, Codable, CaseIterable, Identifiable {
    case sec1 = 1
    case sec2 = 2
    case sec3 = 3
    case sec5 = 5
    case sec10 = 10
    case sec15 = 15
    case sec30 = 30
    case sec60 = 60

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)s"
    }
}

enum AutoPauseOption: Int, Codable, CaseIterable, Identifiable {
    case never = 0
    case sec30 = 30
    case sec60 = 60
    case sec90 = 90
    case sec120 = 120
    case sec180 = 180
    case sec300 = 300

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .never:
            return String(localized: "settings_auto_pause_never")
        default:
            return String(localized: "settings_auto_pause_seconds \(rawValue)")
        }
    }
}

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
    var trackingUpdateIntervalSeconds: Double = 1.0
    var liveActivityRefreshActiveSeconds: Int = LiveActivityRefreshIntervalOption.sec1.rawValue
    var liveActivityRefreshInactiveSeconds: Int = LiveActivityRefreshIntervalOption.sec3.rawValue
    var liveActivityRefreshBackgroundSeconds: Int = LiveActivityRefreshIntervalOption.sec10.rawValue
    var autoPauseIdleSeconds: Int = AutoPauseOption.never.rawValue
    var createdAt: Date = Date()

    var resolvedAutoPause: AutoPauseOption {
        AutoPauseOption(rawValue: autoPauseIdleSeconds) ?? .never
    }

    var resolvedAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var colorScheme: ColorScheme? {
        resolvedAppearance.colorScheme
    }

    var resolvedTrackingUpdateIntervalSeconds: Double {
        min(max(trackingUpdateIntervalSeconds, 0.5), 30)
    }

    var resolvedLiveActivityRefreshActive: LiveActivityRefreshIntervalOption {
        LiveActivityRefreshIntervalOption(rawValue: liveActivityRefreshActiveSeconds) ?? .sec1
    }

    var resolvedLiveActivityRefreshInactive: LiveActivityRefreshIntervalOption {
        LiveActivityRefreshIntervalOption(rawValue: liveActivityRefreshInactiveSeconds) ?? .sec3
    }

    var resolvedLiveActivityRefreshBackground: LiveActivityRefreshIntervalOption {
        LiveActivityRefreshIntervalOption(rawValue: liveActivityRefreshBackgroundSeconds) ?? .sec10
    }

    init(
        id: UUID = UUID(),
        healthKitEnabled: Bool = false,
        hasCompletedOnboarding: Bool = false,
        appearanceMode: AppearanceMode = .system,
        trackingUpdateIntervalSeconds: Double = 1.0,
        liveActivityRefreshActiveSeconds: Int = LiveActivityRefreshIntervalOption.sec1.rawValue,
        liveActivityRefreshInactiveSeconds: Int = LiveActivityRefreshIntervalOption.sec3.rawValue,
        liveActivityRefreshBackgroundSeconds: Int = LiveActivityRefreshIntervalOption.sec10.rawValue,
        autoPauseIdleSeconds: Int = AutoPauseOption.never.rawValue,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.healthKitEnabled = healthKitEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.appearanceMode = appearanceMode.rawValue
        self.trackingUpdateIntervalSeconds = min(max(trackingUpdateIntervalSeconds, 0.5), 30)
        self.liveActivityRefreshActiveSeconds = liveActivityRefreshActiveSeconds
        self.liveActivityRefreshInactiveSeconds = liveActivityRefreshInactiveSeconds
        self.liveActivityRefreshBackgroundSeconds = liveActivityRefreshBackgroundSeconds
        self.autoPauseIdleSeconds = autoPauseIdleSeconds
        self.createdAt = createdAt
    }
}
