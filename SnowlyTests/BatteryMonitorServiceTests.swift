//
//  BatteryMonitorServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct BatteryMonitorServiceTests {

    @Test func initialState() {
        let service = BatteryMonitorService()
        #expect(service.batteryLevel >= 0)
        #expect(service.batteryLevel <= 1.0)
    }

    @Test func isLowBattery_aboveThreshold() {
        let service = BatteryMonitorService()
        // Default battery level is 1.0
        #expect(service.isLowBattery == false)
    }

    @Test func estimatedRemainingTime_withoutStart() {
        let service = BatteryMonitorService()
        #expect(service.estimatedRemainingTime == nil)
    }

    @Test func lowBatteryThreshold_constant() {
        #expect(SharedConstants.lowBatteryThreshold == 0.20)
    }

    @Test func coldWeatherPenalty_constant() {
        #expect(SharedConstants.coldWeatherBatteryPenalty == 0.30)
    }
}
