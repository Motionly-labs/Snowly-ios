//
//  GearReminderScheduleStore.swift
//  Snowly
//
//  Persists reminder schedules as JSON in the local SwiftData store.
//

import Foundation
import SwiftData

enum GearReminderScheduleStore {

    static func schedule(for gearID: UUID, in settings: DeviceSettings?) -> GearReminderSchedule? {
        guard let settings else { return nil }
        return loadSchedules(from: settings)[gearID.uuidString]
    }

    static func schedules(for gear: [GearAsset], in settings: DeviceSettings?) -> [UUID: GearReminderSchedule] {
        guard let settings else { return [:] }
        let storage = loadSchedules(from: settings)
        return gear.reduce(into: [:]) { result, item in
            if let schedule = storage[item.id.uuidString], schedule.isValid {
                result[item.id] = schedule
            }
        }
    }

    static func setSchedule(_ schedule: GearReminderSchedule?, for gearID: UUID, in settings: DeviceSettings) {
        var storage = loadSchedules(from: settings)
        if let schedule, schedule.isValid {
            storage[gearID.uuidString] = schedule
        } else {
            storage.removeValue(forKey: gearID.uuidString)
        }
        saveSchedules(storage, to: settings)
    }

    // MARK: - Private

    private static func loadSchedules(from settings: DeviceSettings) -> [String: GearReminderSchedule] {
        guard
            let data = settings.gearReminderSchedulesJSON.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: GearReminderSchedule].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func saveSchedules(_ storage: [String: GearReminderSchedule], to settings: DeviceSettings) {
        guard
            let data = try? JSONEncoder().encode(storage),
            let json = String(data: data, encoding: .utf8)
        else { return }
        settings.gearReminderSchedulesJSON = json
    }
}
