//
//  SharedConstants.swift
//  Snowly
//
//  Constants shared between iOS and watchOS.
//

import Foundation

enum SharedConstants {
    // MARK: - Run Detection Thresholds
    nonisolated static let idleSpeedThreshold: Double = 1.5       // m/s — below = idle
    nonisolated static let gpsNoiseFloor: Double = 1.0            // m/s — below = treat as stationary
    nonisolated static let skiingMinSpeed: Double = 2.0            // m/s — above + altitude drop = skiing
    nonisolated static let chairliftMaxSpeed: Double = 6.0         // m/s — above = definitely skiing
    nonisolated static let stopDurationThreshold: TimeInterval = 75 // seconds before ending a run

    // MARK: - Signal Filtering
    nonisolated static let medianFilterWindowSize: Int = 5          // median filter window for altitude spikes
    nonisolated static let recentPointsBufferSize: Int = 15         // ~15-20s of GPS points @1Hz
    nonisolated static let minPointsForAltitudeTrend: Int = 8       // minimum points for reliable regression
    nonisolated static let altitudeTrendUpThreshold: Double = 0.25  // m/s — slope above = ascending
    nonisolated static let altitudeTrendDownThreshold: Double = -0.25 // m/s — slope below = descending

    // MARK: - Activity Dwell Time (hysteresis)
    nonisolated static let dwellTimeSkiingToChairlift: TimeInterval = 15
    nonisolated static let dwellTimeChairliftToSkiing: TimeInterval = 8
    nonisolated static let dwellTimeIdleToSkiing: TimeInterval = 3
    nonisolated static let dwellTimeIdleToChairlift: TimeInterval = 10

    // MARK: - GPS Sampling
    nonisolated static let highSpeedThreshold: Double = 5.0        // m/s
    nonisolated static let mediumSpeedThreshold: Double = 2.0      // m/s

    // MARK: - Battery
    nonisolated static let lowBatteryThreshold: Float = 0.20
    nonisolated static let lowBatteryWarningThreshold: Float = 0.40
    nonisolated static let coldWeatherBatteryPenalty: Float = 0.30 // 30% capacity loss in cold

    // MARK: - Crash Recovery
    nonisolated static let statePersistenceInterval: TimeInterval = 30
    nonisolated static let trackingStateKey = "snowly.tracking.state"
    nonisolated static let crewSyncPreferencesKey = "snowly.crew.syncPreferences"

    // MARK: - WCSession
    nonisolated static let watchSessionKey = "snowly.watch.message"
}
