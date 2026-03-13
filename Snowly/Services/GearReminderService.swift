//
//  GearReminderService.swift
//  Snowly
//
//  Local reminder schedules for locker gear and notification syncing.
//

import Foundation
import SwiftData
@preconcurrency import UserNotifications

@Observable
@MainActor
final class GearReminderService {
    private let center = UNUserNotificationCenter.current()
    private let notificationPrefix = "gear-reminder"
    private let maxScheduledNotifications = 48
    private let maxNotificationsPerGear = 4

    init() {}

    func requestPermissionIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func syncAll(using context: ModelContext) {
        let descriptor = FetchDescriptor<GearAsset>(sortBy: [SortDescriptor(\.sortOrder)])
        let gear = (try? context.fetch(descriptor)) ?? []
        let settingsDescriptor = FetchDescriptor<DeviceSettings>()
        let settings = (try? context.fetch(settingsDescriptor))?.first
        syncNotifications(for: gear, settings: settings)
    }

    func syncNotifications(for gear: [GearAsset], settings: DeviceSettings?, now: Date = .now) {
        let sortedGear = gear
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        Task {
            let requests = await center.pendingNotificationRequests()
            let existingIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(notificationPrefix) }

            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
            center.removeDeliveredNotifications(withIdentifiers: existingIDs)

            let schedules = GearReminderScheduleStore.schedules(for: sortedGear, in: settings)
            var remainingSlots = maxScheduledNotifications

            for item in sortedGear {
                guard remainingSlots > 0 else { break }
                guard let schedule = schedules[item.id] else { continue }

                let occurrenceLimit = min(maxNotificationsPerGear, remainingSlots)
                let dates = schedule.scheduledOccurrences(limit: occurrenceLimit, after: now)

                for (index, date) in dates.enumerated() {
                    let content = UNMutableNotificationContent()
                    content.title = item.displayName
                    content.body = String(localized: "gear_reminder_notification_body \(item.displayName)")
                    content.sound = .default

                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: date
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let identifier = "\(notificationPrefix)-\(item.id.uuidString)-\(index)"
                    let request = UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: trigger
                    )

                    try? await center.add(request)
                    remainingSlots -= 1
                    if remainingSlots == 0 {
                        break
                    }
                }
            }
        }
    }
}
