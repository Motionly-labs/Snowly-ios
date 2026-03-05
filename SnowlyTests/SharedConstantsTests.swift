//
//  SharedConstantsTests.swift
//  SnowlyTests
//
//  Tests for shared constants validity.
//

import Testing
import Foundation
@testable import Snowly

struct SharedConstantsTests {

    @Test func speedThresholds_areOrdered() {
        // GPS noise < idle < skiing min < chairlift max
        #expect(SharedConstants.gpsNoiseFloor < SharedConstants.idleSpeedThreshold)
        #expect(SharedConstants.idleSpeedThreshold < SharedConstants.skiingMinSpeed)
        #expect(SharedConstants.skiingMinSpeed < SharedConstants.chairliftMaxSpeed)
    }

    @Test func stopDuration_isReasonable() {
        // Should be between 30 and 120 seconds
        #expect(SharedConstants.stopDurationThreshold >= 30)
        #expect(SharedConstants.stopDurationThreshold <= 120)
    }

    @Test func lowBatteryThreshold_isReasonable() {
        #expect(SharedConstants.lowBatteryThreshold > 0)
        #expect(SharedConstants.lowBatteryThreshold < 0.5)
    }

    @Test func coldWeatherPenalty_isReasonable() {
        #expect(SharedConstants.coldWeatherBatteryPenalty > 0)
        #expect(SharedConstants.coldWeatherBatteryPenalty < 1.0)
    }
}
