//
//  UnitConversionTests.swift
//  SnowlyTests
//
//  Tests for UnitConversion utility.
//

import Testing
import Foundation
@testable import Snowly

struct UnitConversionTests {

    // MARK: - Speed

    @Test func mpsToKmh() {
        let result = UnitConversion.metersPerSecondToKmh(10.0)
        #expect(result == 36.0)
    }

    @Test func mpsToMph() {
        let result = UnitConversion.metersPerSecondToMph(10.0)
        #expect(abs(result - 22.3694) < 0.001)
    }

    @Test func kmhToMps() {
        let result = UnitConversion.kmhToMetersPerSecond(36.0)
        #expect(result == 10.0)
    }

    // MARK: - Distance

    @Test func metersToKm() {
        let result = UnitConversion.metersToKilometers(1500.0)
        #expect(result == 1.5)
    }

    @Test func metersToMiles() {
        let result = UnitConversion.metersToMiles(1609.344)
        #expect(abs(result - 1.0) < 0.001)
    }

    @Test func metersToFeet() {
        let result = UnitConversion.metersToFeet(1.0)
        #expect(abs(result - 3.28084) < 0.001)
    }

    // MARK: - Temperature

    @Test func celsiusToFahrenheit_freezing() {
        let result = UnitConversion.celsiusToFahrenheit(0.0)
        #expect(result == 32.0)
    }

    @Test func celsiusToFahrenheit_boiling() {
        let result = UnitConversion.celsiusToFahrenheit(100.0)
        #expect(result == 212.0)
    }

    @Test func fahrenheitToCelsius_freezing() {
        let result = UnitConversion.fahrenheitToCelsius(32.0)
        #expect(abs(result) < 0.001)
    }
}
