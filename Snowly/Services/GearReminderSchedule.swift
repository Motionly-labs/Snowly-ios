//
//  GearReminderSchedule.swift
//  Snowly
//
//  Local reminder schedule types for locker gear.
//

import Foundation

struct GearReminderEntry: Identifiable {
    let gear: GearAsset
    let schedule: GearReminderSchedule
    let nextDate: Date

    var id: UUID { gear.id }
}

enum GearReminderIntervalUnit: String, Codable, CaseIterable, Sendable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var calendarComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }

    var displayLabel: String {
        switch self {
        case .day:
            return "days"
        case .week:
            return "weeks"
        case .month:
            return "months"
        }
    }
}

struct GearReminderSchedule: Codable, Equatable, Sendable {
    var startDate: Date
    var endDate: Date
    var intervalValue: Int
    var intervalUnit: GearReminderIntervalUnit
    var hour: Int
    var minute: Int

    init(
        startDate: Date = Calendar.current.startOfDay(for: .now),
        endDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
        intervalValue: Int = 1,
        intervalUnit: GearReminderIntervalUnit = .day,
        hour: Int = 20,
        minute: Int = 0
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.intervalValue = intervalValue
        self.intervalUnit = intervalUnit
        self.hour = hour
        self.minute = minute
    }

    var isValid: Bool {
        intervalValue > 0 && startDate <= endDate
    }

    func nextOccurrence(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        scheduledOccurrences(limit: 1, after: now, calendar: calendar).first
    }

    func scheduledOccurrences(
        limit: Int,
        after now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        guard isValid, limit > 0 else { return [] }
        guard let firstOccurrence = occurrence(on: startDate, calendar: calendar) else { return [] }
        guard let finalMoment = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDate
        ) else {
            return []
        }

        var dates: [Date] = []
        var current = firstOccurrence
        var guardIterations = 0

        while current <= finalMoment && dates.count < limit && guardIterations < 512 {
            if current > now {
                dates.append(current)
            }

            guard let next = calendar.date(
                byAdding: intervalUnit.calendarComponent,
                value: intervalValue,
                to: current
            ) else {
                break
            }

            current = next
            guardIterations += 1
        }

        return dates
    }

    func summaryText(now: Date = .now, calendar: Calendar = .current) -> String {
        summaryText(nextDate: nextOccurrence(after: now, calendar: calendar), now: now, calendar: calendar)
    }

    func summaryText(nextDate: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        let dateText = "\(startDate.shortDisplay) to \(endDate.shortDisplay)"
        let timeText = Self.timeFormatter.string(from: occurrence(on: now, calendar: calendar) ?? now)
        let cadenceText = "Every \(intervalValue) \(intervalUnit.displayLabel) at \(timeText)"
        if let nextDate {
            return "\(cadenceText) · Next \(nextDate.relativeDisplay) · \(dateText)"
        }
        return "\(cadenceText) · \(dateText)"
    }

    private func occurrence(on date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
