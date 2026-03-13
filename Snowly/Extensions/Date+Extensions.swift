//
//  Date+Extensions.swift
//  Snowly
//

import Foundation

extension Date {

    // MARK: - Cached Formatters

    private static let shortDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let longDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()

    private static let timeDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Display Properties

    /// Returns date formatted as "Mon, Jan 5".
    var shortDisplay: String {
        Self.shortDisplayFormatter.string(from: self)
    }

    /// Returns date formatted as "January 5, 2026".
    var longDisplay: String {
        Self.longDisplayFormatter.string(from: self)
    }

    /// Returns time formatted as "2:30 PM".
    var timeDisplay: String {
        Self.timeDisplayFormatter.string(from: self)
    }

    /// Returns relative description like "Today", "Yesterday", "3 days ago".
    var relativeDisplay: String {
        Self.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    /// The ski season year. Seasons span Oct-Apr, so Dec 2025 and Jan 2026 are both "2025/26".
    var seasonYear: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: self)
        let year = calendar.component(.year, from: self)

        if month >= 10 {
            // Oct-Dec: season starts this year
            let nextYear = (year + 1) % 100
            return "\(year)/\(String(format: "%02d", nextYear))"
        } else {
            // Jan-Sep: season started last year
            let prevYear = year - 1
            let thisYear = year % 100
            return "\(prevYear)/\(String(format: "%02d", thisYear))"
        }
    }
}
