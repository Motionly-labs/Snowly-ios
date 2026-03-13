//
//  DateExtensionTests.swift
//  SnowlyTests
//
//  Tests for Date extension methods.
//

import Testing
import Foundation
@testable import Snowly

struct DateExtensionTests {

    @Test func seasonYear_december() {
        // December 2025 → season "2025/26"
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 15
        let date = Calendar.current.date(from: components)!

        #expect(date.seasonYear == "2025/26")
    }

    @Test func seasonYear_january() {
        // January 2026 → season "2025/26"
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        let date = Calendar.current.date(from: components)!

        #expect(date.seasonYear == "2025/26")
    }

    @Test func seasonYear_october() {
        // October 2025 → season "2025/26"
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 1
        let date = Calendar.current.date(from: components)!

        #expect(date.seasonYear == "2025/26")
    }

    @Test func seasonYear_march() {
        // March 2026 → season "2025/26"
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date = Calendar.current.date(from: components)!

        #expect(date.seasonYear == "2025/26")
    }

    @Test func shortDisplay_isNotEmpty() {
        let result = Date().shortDisplay
        #expect(!result.isEmpty)
    }

    @Test func longDisplay_isNotEmpty() {
        let result = Date().longDisplay
        #expect(!result.isEmpty)
    }

    @Test func timeDisplay_isNotEmpty() {
        let result = Date().timeDisplay
        #expect(!result.isEmpty)
    }
}
