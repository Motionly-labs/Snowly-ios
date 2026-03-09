//
//  SegmentValidatorTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct SegmentValidatorTests {

    // MARK: - Helpers

    private func makePoint(altitude: Double, timestamp: Date = Date()) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: 46.0, longitude: 7.0,
            altitude: altitude,
            speed: 10.0, accuracy: 5.0, course: 180.0
        )
    }

    // MARK: - effectiveType: skiing

    @Test func skiing_validCriteria_remainsSkiing() {
        let base = Date()
        let first = makePoint(altitude: 2100, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(30))
        // duration=30 ≥ 15, altitudeLoss=100 ≥ 12, avgSpeed=3.67 ≥ 3.5
        let result = SegmentValidator.effectiveType(
            activityType: .skiing, firstPoint: first, lastPoint: last,
            duration: 30, averageSpeed: 3.67)
        #expect(result == .skiing)
    }

    @Test func skiing_insufficientAltitudeLoss_degradesToWalk() {
        let base = Date()
        let first = makePoint(altitude: 2005, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(30))
        // altitudeLoss=5 < 12 m minimum
        let result = SegmentValidator.effectiveType(
            activityType: .skiing, firstPoint: first, lastPoint: last,
            duration: 30, averageSpeed: 4.0)
        #expect(result == .walk)
    }

    @Test func skiing_belowMinAvgSpeed_degradesToWalk() {
        let base = Date()
        let first = makePoint(altitude: 2100, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(30))
        // avgSpeed=2.0 < 3.5 minimum
        let result = SegmentValidator.effectiveType(
            activityType: .skiing, firstPoint: first, lastPoint: last,
            duration: 30, averageSpeed: 2.0)
        #expect(result == .walk)
    }

    @Test func skiing_tooShort_degradesToWalk() {
        let base = Date()
        let first = makePoint(altitude: 2100, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(10))
        // duration=10 < 15 s minimum
        let result = SegmentValidator.effectiveType(
            activityType: .skiing, firstPoint: first, lastPoint: last,
            duration: 10, averageSpeed: 4.0)
        #expect(result == .walk)
    }

    // MARK: - effectiveType: lift

    @Test func lift_validCriteria_remainsLift() {
        let base = Date()
        let first = makePoint(altitude: 1800, timestamp: base)
        let last  = makePoint(altitude: 1900, timestamp: base.addingTimeInterval(60))
        // duration=60 ≥ 30, gain=100 ≥ 20, avgVertSpeed=100/60≈1.67 ≥ 0.10
        let result = SegmentValidator.effectiveType(
            activityType: .lift, firstPoint: first, lastPoint: last,
            duration: 60, averageSpeed: 3.0)
        #expect(result == .lift)
    }

    @Test func lift_insufficientAltitudeGain_degradesToWalk() {
        let base = Date()
        let first = makePoint(altitude: 1800, timestamp: base)
        let last  = makePoint(altitude: 1810, timestamp: base.addingTimeInterval(60))
        // gain=10 < 20 m minimum
        let result = SegmentValidator.effectiveType(
            activityType: .lift, firstPoint: first, lastPoint: last,
            duration: 60, averageSpeed: 3.0)
        #expect(result == .walk)
    }

    // MARK: - effectiveType: walk

    @Test func walk_aboveMinDuration_remains() {
        let base = Date()
        let first = makePoint(altitude: 2000, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(10))
        let result = SegmentValidator.effectiveType(
            activityType: .walk, firstPoint: first, lastPoint: last,
            duration: 10, averageSpeed: 1.5)
        #expect(result == .walk)
    }

    @Test func walk_belowMinDuration_returnsNil() {
        let base = Date()
        let first = makePoint(altitude: 2000, timestamp: base)
        let last  = makePoint(altitude: 2000, timestamp: base.addingTimeInterval(2))
        // duration=2 < 6 s minimum
        let result = SegmentValidator.effectiveType(
            activityType: .walk, firstPoint: first, lastPoint: last,
            duration: 2, averageSpeed: 1.5)
        #expect(result == nil)
    }

    @Test func walkPhysicsGuard_highSpeedRestoresOriginalType() {
        let base = Date()
        let first = makePoint(altitude: 2000, timestamp: base)
        let last  = makePoint(altitude: 2005, timestamp: base.addingTimeInterval(40))

        // Invalid lift by altitude gain/slope, but average speed is too high to classify as walk.
        let result = SegmentValidator.effectiveType(
            activityType: .lift,
            firstPoint: first,
            lastPoint: last,
            duration: 40,
            averageSpeed: SharedConstants.walkHardMaxSpeed + 0.5
        )
        #expect(result == .lift)
    }

    // MARK: - verticalDrop

    @Test func verticalDrop_skiing_isDescendingDelta() {
        let drop = SegmentValidator.verticalDrop(effectiveType: .skiing,
                                                  firstAltitude: 2100, lastAltitude: 2000)
        #expect(drop == 100)
    }

    @Test func verticalDrop_skiing_clampedToZeroIfAscending() {
        let drop = SegmentValidator.verticalDrop(effectiveType: .skiing,
                                                  firstAltitude: 2000, lastAltitude: 2100)
        #expect(drop == 0)
    }

    @Test func verticalDrop_lift_isAscendingDelta() {
        let drop = SegmentValidator.verticalDrop(effectiveType: .lift,
                                                  firstAltitude: 1800, lastAltitude: 1900)
        #expect(drop == 100)
    }

    @Test func verticalDrop_walk_isZero() {
        let drop = SegmentValidator.verticalDrop(effectiveType: .walk,
                                                  firstAltitude: 2000, lastAltitude: 2050)
        #expect(drop == 0)
    }
}
