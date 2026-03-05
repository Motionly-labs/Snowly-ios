//
//  MotionDetectionServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct MotionDetectionServiceTests {

    @Test func initialState() {
        let service = MotionDetectionService()
        #expect(service.currentMotion == .unknown)
    }

    @Test func detectedMotion_allCases() {
        // Verify all motion types exist
        let motions: [DetectedMotion] = [
            .stationary, .walking, .automotive, .cycling, .running, .unknown
        ]
        #expect(motions.count == 6)
    }

    @Test func stopMonitoring_resetsMotion() {
        let service = MotionDetectionService()
        service.stopMonitoring()
        #expect(service.currentMotion == .unknown)
    }
}
