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

    @Test func trackingResumed_encodeDecode() throws {
        let message = WatchMessage.trackingResumed

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .trackingResumed = decoded {
            // Success
        } else {
            #expect(Bool(false), "Expected trackingResumed case")
        }
    }

    @Test func lastCompletedRun_encodeDecode() throws {
        let summary = WatchMessage.LastRunData(
            runNumber: 4,
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 1120),
            distance: 1800,
            verticalDrop: 420,
            maxSpeed: 24.5,
            averageSpeed: 13.2
        )
        let message = WatchMessage.lastCompletedRun(summary)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .lastCompletedRun(let decodedSummary) = decoded {
            #expect(decodedSummary == summary)
        } else {
            #expect(Bool(false), "Expected lastCompletedRun case")
        }
    }

    @Test func lastCompletedRun_nil_encodeDecode() throws {
        let message = WatchMessage.lastCompletedRun(nil)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .lastCompletedRun(let decodedSummary) = decoded {
            #expect(decodedSummary == nil)
        } else {
            #expect(Bool(false), "Expected lastCompletedRun case")
        }
    }

    @Test func independentWorkoutImported_encodeDecode() throws {
        let sessionId = UUID()
        let message = WatchMessage.independentWorkoutImported(sessionId: sessionId)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .independentWorkoutImported(let decodedSessionId) = decoded {
            #expect(decodedSessionId == sessionId)
        } else {
            #expect(Bool(false), "Expected independentWorkoutImported case")
        }
    }

    @Test func independentWorkoutImportFailed_encodeDecode() throws {
        let sessionId = UUID()
        let message = WatchMessage.independentWorkoutImportFailed(sessionId: sessionId)

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(WatchMessage.self, from: encoded)

        if case .independentWorkoutImportFailed(let decodedSessionId) = decoded {
            #expect(decodedSessionId == sessionId)
        } else {
            #expect(Bool(false), "Expected independentWorkoutImportFailed case")
        }
    }
}
