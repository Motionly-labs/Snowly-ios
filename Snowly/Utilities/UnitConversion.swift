//
//  UnitConversion.swift
//  Snowly
//
//  Pure functions for unit conversion.
//

import Foundation

enum UnitConversion {

    // MARK: - Speed
    nonisolated static func metersPerSecondToKmh(_ mps: Double) -> Double { mps * 3.6 }
    nonisolated static func metersPerSecondToMph(_ mps: Double) -> Double { mps * 2.23694 }
    nonisolated static func kmhToMetersPerSecond(_ kmh: Double) -> Double { kmh / 3.6 }

    // MARK: - Distance
    nonisolated static func metersToKilometers(_ m: Double) -> Double { m / 1000.0 }
    nonisolated static func metersToMiles(_ m: Double) -> Double { m / 1609.344 }
    nonisolated static func metersToFeet(_ m: Double) -> Double { m * 3.28084 }
    nonisolated static func feetToMeters(_ ft: Double) -> Double { ft / 3.28084 }

    // MARK: - Temperature
    nonisolated static func celsiusToFahrenheit(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
    nonisolated static func fahrenheitToCelsius(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
}
