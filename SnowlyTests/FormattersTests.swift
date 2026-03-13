//
//  FormattersTests.swift
//  SnowlyTests
//
//  Tests for Formatters utility.
//

import Testing
import Foundation
@testable import Snowly

struct FormattersTests {

    // MARK: - Speed

    @Test func speed_metric() {
        // 10 m/s = 36 km/h
        let result = Formatters.speed(10.0, unit: .metric)
        #expect(result == "36 km/h")
    }

    @Test func speed_imperial() {
        // 10 m/s ≈ 22 mph
        let result = Formatters.speed(10.0, unit: .imperial)
        #expect(result == "22 mph")
    }

    @Test func speed_zero() {
        let result = Formatters.speed(0.0, unit: .metric)
        #expect(result == "0 km/h")
    }

    @Test func speedValue_metric() {
        let result = Formatters.speedValue(10.0, unit: .metric)
        #expect(result == "36")
    }

    @Test func speedUnit_metric() {
        #expect(Formatters.speedUnit(.metric) == "km/h")
    }

    @Test func speedUnit_imperial() {
        #expect(Formatters.speedUnit(.imperial) == "mph")
    }

    // MARK: - Distance

    @Test func distance_metersMetric() {
        let result = Formatters.distance(500.0, unit: .metric)
        #expect(result == "500 m")
    }

    @Test func distance_kilometersMetric() {
        let result = Formatters.distance(1500.0, unit: .metric)
        #expect(result == "1.5 km")
    }

    @Test func distance_feetImperial() {
        let result = Formatters.distance(500.0, unit: .imperial)
        #expect(result == "1640 ft")
    }

    @Test func distance_milesImperial() {
        let result = Formatters.distance(5000.0, unit: .imperial)
        // 5000m ≈ 16404 ft ≈ 3.1 mi
        #expect(result.contains("mi"))
    }

    // MARK: - Vertical

    @Test func vertical_metric() {
        let result = Formatters.vertical(350.0, unit: .metric)
        #expect(result == "350 m")
    }

    @Test func vertical_imperial() {
        let result = Formatters.vertical(100.0, unit: .imperial)
        #expect(result == "328 ft")
    }

    // MARK: - Duration

    @Test func duration_secondsOnly() {
        let result = Formatters.duration(45)
        #expect(result == "45s")
    }

    @Test func duration_minutesSeconds() {
        let result = Formatters.duration(125)
        #expect(result == "2m 5s")
    }

    @Test func duration_hoursMinutes() {
        let result = Formatters.duration(3750)
        #expect(result == "1h 2m")
    }

    // MARK: - Timer

    @Test func timer_minutesSeconds() {
        let result = Formatters.timer(125)
        #expect(result == "2:05")
    }

    @Test func timer_hoursMinutesSeconds() {
        let result = Formatters.timer(3661)
        #expect(result == "1:01:01")
    }

    // MARK: - Temperature

    @Test func temperature_metric() {
        let result = Formatters.temperature(-5.0, unit: .metric)
        #expect(result == "-5°C")
    }

    @Test func temperature_imperial() {
        let result = Formatters.temperature(0.0, unit: .imperial)
        #expect(result == "32°F")
    }
}
