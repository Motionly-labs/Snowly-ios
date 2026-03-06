//
//  CrewSyncPreferences.swift
//  Snowly
//
//  Device-local preferences for crew sync cadence and location sharing.
//

import Foundation

enum CrewSyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual

    var id: String { rawValue }
}

struct CrewSyncPreferences: Codable, Equatable, Sendable {
    static let supportedIntervals: [Int] = [5, 10, 15, 30, 60, 120]

    var shareLocationEnabled: Bool
    var mode: CrewSyncMode
    var intervalSeconds: Int

    static let `default` = CrewSyncPreferences(
        shareLocationEnabled: true,
        mode: .automatic,
        intervalSeconds: 5
    )

    var sanitized: CrewSyncPreferences {
        CrewSyncPreferences(
            shareLocationEnabled: shareLocationEnabled,
            mode: mode,
            intervalSeconds: Self.supportedIntervals.contains(intervalSeconds)
                ? intervalSeconds
                : Self.default.intervalSeconds
        )
    }
}

enum CrewSyncPreferencesStore {
    static func load(from userDefaults: UserDefaults = .standard) -> CrewSyncPreferences {
        guard let data = userDefaults.data(forKey: SharedConstants.crewSyncPreferencesKey),
              let preferences = try? JSONDecoder().decode(CrewSyncPreferences.self, from: data)
        else {
            return .default
        }

        return preferences.sanitized
    }

    static func save(
        _ preferences: CrewSyncPreferences,
        to userDefaults: UserDefaults = .standard
    ) {
        let sanitized = preferences.sanitized
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        userDefaults.set(data, forKey: SharedConstants.crewSyncPreferencesKey)
    }
}
