//
//  BatteryMonitorService.swift
//  Snowly
//
//  Monitors battery level and estimates remaining tracking time
//  accounting for cold weather degradation.
//

import UIKit
import Observation

@Observable
@MainActor
final class BatteryMonitorService: BatteryMonitoring {
    private(set) var batteryLevel: Float = 1.0
    private(set) var isCharging = false

    private var trackingStartLevel: Float?
    private var trackingStartTime: Date?
    private var batteryLevelObserver: NSObjectProtocol?
    private var batteryStateObserver: NSObjectProtocol?

    var isLowBattery: Bool {
        batteryLevel <= SharedConstants.lowBatteryThreshold
    }

    /// Estimated remaining tracking time, accounting for cold weather.
    /// The observed drain rate already includes cold-weather effects since monitoring
    /// started, so we apply the penalty only to the remaining capacity.
    var estimatedRemainingTime: TimeInterval? {
        guard let startLevel = trackingStartLevel,
              let startTime = trackingStartTime else { return nil }

        let elapsed = Date().timeIntervalSince(startTime)
        let consumed = startLevel - batteryLevel
        guard consumed > 0.01, elapsed > 60 else { return nil }

        let drainRate = consumed / Float(elapsed)
        return TimeInterval(batteryLevel / drainRate)
    }

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryState()

        trackingStartLevel = batteryLevel
        trackingStartTime = Date()

        removeBatteryObservers()

        batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateBatteryState()
            }
        }

        batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.updateBatteryState()
            }
        }
    }

    func stopMonitoring() {
        removeBatteryObservers()
        trackingStartLevel = nil
        trackingStartTime = nil
    }

    private func updateBatteryState() {
        let device = UIDevice.current
        batteryLevel = max(0, device.batteryLevel)
        isCharging = device.batteryState == .charging || device.batteryState == .full
    }

    private func removeBatteryObservers() {
        if let levelObserver = batteryLevelObserver {
            NotificationCenter.default.removeObserver(levelObserver)
            batteryLevelObserver = nil
        }
        if let stateObserver = batteryStateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
            batteryStateObserver = nil
        }
    }
}
