//
//  BatteryMonitoring.swift
//  Snowly
//
//  Protocol for battery monitoring — enables mock injection for testing.
//

import Foundation

@MainActor
protocol BatteryMonitoring: AnyObject, Sendable {
    var batteryLevel: Float { get }        // 0.0 - 1.0
    var isCharging: Bool { get }
    var isLowBattery: Bool { get }

    /// Estimated remaining tracking time in seconds, accounting for cold weather.
    var estimatedRemainingTime: TimeInterval? { get }

    func startMonitoring()
    func stopMonitoring()
}
