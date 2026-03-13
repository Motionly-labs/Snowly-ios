//
//  Formatters.swift
//  Snowly
//
//  Centralized formatting for speed, distance, altitude, and duration.
//

import Foundation

enum Formatters {

    // MARK: - Speed

    /// Formats speed from m/s to display string.
    nonisolated static func speed(_ metersPerSecond: Double, unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            return String(format: "%.0f km/h", UnitConversion.metersPerSecondToKmh(metersPerSecond))
        case .imperial:
            return String(format: "%.0f mph", UnitConversion.metersPerSecondToMph(metersPerSecond))
        }
    }

    /// Formats speed value only (no unit suffix).
    nonisolated static func speedValue(_ metersPerSecond: Double, unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            return String(format: "%.0f", UnitConversion.metersPerSecondToKmh(metersPerSecond))
        case .imperial:
            return String(format: "%.0f", UnitConversion.metersPerSecondToMph(metersPerSecond))
        }
    }

    nonisolated static func speedUnit(_ unit: UnitSystem) -> String {
        switch unit {
        case .metric: return "km/h"
        case .imperial: return "mph"
        }
    }

    // MARK: - Distance

    /// Formats distance from meters to display string.
    nonisolated static func distance(_ meters: Double, unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            if meters >= 1000 {
                return String(format: "%.1f km", meters / 1000)
            }
            return String(format: "%.0f m", meters)
        case .imperial:
            let feet = UnitConversion.metersToFeet(meters)
            if feet >= 5280 {
                return String(format: "%.1f mi", UnitConversion.metersToMiles(meters))
            }
            return String(format: "%.0f ft", feet)
        }
    }

    nonisolated static func distanceUnit(_ unit: UnitSystem) -> String {
        unit == .imperial ? "mi" : "km"
    }

    // MARK: - Altitude / Vertical

    /// Formats altitude/vertical from meters.
    nonisolated static func vertical(_ meters: Double, unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            return String(format: "%.0f m", meters)
        case .imperial:
            return String(format: "%.0f ft", UnitConversion.metersToFeet(meters))
        }
    }

    nonisolated static func verticalUnit(_ unit: UnitSystem) -> String {
        switch unit {
        case .metric: return "m"
        case .imperial: return "ft"
        }
    }

    // MARK: - Duration

    /// Formats TimeInterval to "Xh Xm" or "Xm Xs".
    nonisolated static func duration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Formats TimeInterval to "HH:MM:SS" timer style.
    nonisolated static func timer(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Temperature

    nonisolated static func temperature(_ celsius: Double, unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            return String(format: "%.0f°C", celsius)
        case .imperial:
            let fahrenheit = UnitConversion.celsiusToFahrenheit(celsius)
            return String(format: "%.0f°F", fahrenheit)
        }
    }
}
