//
//  SnowlyTests.swift
//  SnowlyTests
//
//  Main test entry — individual test files are in separate files.
//

import Testing
@testable import Snowly

struct SnowlyTests {
    @Test func appBuilds() async throws {
        // Smoke test: the app module compiles and can be imported
        #expect(true)
    }
}
