//
//  WatchMessageTests.swift
//  SnowlyTests
//
//  Tests for WatchMessage Codable encoding.
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct WatchMessageTests {

    @Test func liveUpdate_encodeDecode() throws {
        let data = WatchMessage.LiveTrackingData(
            currentSpeed: 12.5,
            maxSpeed: 22.0,
            totalDistance: 5000,
            totalVertical: 1200,
            runCount: 8,
            elapsedTime: 3600,
            batteryLevel: 0.65
        )
        let message = WatchMessage.liveUpdate(data)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .liveUpdate(let decodedData) = decoded {
            #expect(decodedData == data)
        } else {
            #expect(Bool(false), "Expected liveUpdate case")
        }
    }

    @Test func requestStart_encodeDecode() throws {
        let message = WatchMessage.requestStart

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .requestStart = decoded {
            // Success
        } else {
            #expect(Bool(false), "Expected requestStart case")
        }
    }

    @Test func trackingStarted_encodeDecode() throws {
        let id = UUID()
        let message = WatchMessage.trackingStarted(sessionId: id)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .trackingStarted(let decodedId) = decoded {
            #expect(decodedId == id)
        } else {
            #expect(Bool(false), "Expected trackingStarted case")
        }
    }
}
