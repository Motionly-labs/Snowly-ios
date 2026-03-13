//
//  GearChecklistStore.swift
//  Snowly
//
//  Local persistence for visual checklist checkmarks per checklist/setup.
//  State is stored as JSON in the local SwiftData store (DeviceSettings).
//

import Foundation
import SwiftData

enum GearChecklistStore {

    static func checkedGearIDs(for checklistID: UUID, in settings: DeviceSettings?) -> Set<UUID> {
        guard let settings else { return [] }
        let rawMap = loadStorage(from: settings)
        guard let storedIDs = rawMap[checklistID.uuidString] else {
            return []
        }
        return Set(storedIDs.compactMap { UUID(uuidString: $0) })
    }

    static func setCheckedGearIDs(_ checkedGearIDs: Set<UUID>, for checklistID: UUID, in settings: DeviceSettings) {
        var storage = loadStorage(from: settings)
        if checkedGearIDs.isEmpty {
            storage.removeValue(forKey: checklistID.uuidString)
        } else {
            storage[checklistID.uuidString] = checkedGearIDs
                .map(\.uuidString)
                .sorted()
        }
        saveStorage(storage, to: settings)
    }

    static func toggle(_ gearID: UUID, in checklistID: UUID, settings: DeviceSettings) {
        var checked = checkedGearIDs(for: checklistID, in: settings)
        if checked.contains(gearID) {
            checked.remove(gearID)
        } else {
            checked.insert(gearID)
        }
        setCheckedGearIDs(checked, for: checklistID, in: settings)
    }

    static func reset(for checklistID: UUID, in settings: DeviceSettings) {
        var storage = loadStorage(from: settings)
        storage.removeValue(forKey: checklistID.uuidString)
        saveStorage(storage, to: settings)
    }

    // MARK: - Private

    private static func loadStorage(from settings: DeviceSettings) -> [String: [String]] {
        guard
            let data = settings.gearChecklistStateJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func saveStorage(_ storage: [String: [String]], to settings: DeviceSettings) {
        guard
            let data = try? JSONEncoder().encode(storage),
            let json = String(data: data, encoding: .utf8)
        else { return }
        settings.gearChecklistStateJSON = json
    }
}
