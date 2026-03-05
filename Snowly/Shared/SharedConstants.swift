//
//  SharedConstants.swift
//  Snowly
//
//  Constants shared between iOS and watchOS.
//

import Foundation

enum SharedConstants {
    // MARK: - Run Detection Thresholds
    static let idleSpeedThreshold: Double = 1.5       // m/s — below = idle
    static let gpsNoiseFloor: Double = 1.0            // m/s — below = treat as stationary
    static let skiingMinSpeed: Double = 2.0            // m/s — above + altitude drop = skiing
    static let chairliftMaxSpeed: Double = 6.0         // m/s — above = definitely skiing
    static let stopDurationThreshold: TimeInterval = 75 // seconds before ending a run

    // MARK: - Signal Filtering
    static let medianFilterWindowSize: Int = 5          // median filter window for altitude spikes
    static let recentPointsBufferSize: Int = 15         // ~15-20s of GPS points @1Hz
    static let minPointsForAltitudeTrend: Int = 8       // minimum points for reliable regression
    static let altitudeTrendUpThreshold: Double = 0.25  // m/s — slope above = ascending
    static let altitudeTrendDownThreshold: Double = -0.25 // m/s — slope below = descending

    // MARK: - Activity Dwell Time (hysteresis)
    static let dwellTimeSkiingToChairlift: TimeInterval = 15
    static let dwellTimeChairliftToSkiing: TimeInterval = 8
    static let dwellTimeIdleToSkiing: TimeInterval = 3
    static let dwellTimeIdleToChairlift: TimeInterval = 10

    // MARK: - GPS Sampling
    static let highSpeedThreshold: Double = 5.0        // m/s
    static let mediumSpeedThreshold: Double = 2.0      // m/s

    // MARK: - Battery
    static let lowBatteryThreshold: Float = 0.20
    static let lowBatteryWarningThreshold: Float = 0.40
    static let coldWeatherBatteryPenalty: Float = 0.30 // 30% capacity loss in cold

    // MARK: - Crash Recovery
    static let statePersistenceInterval: TimeInterval = 30
    static let trackingStateKey = "snowly.tracking.state"

    // MARK: - WCSession
    static let watchSessionKey = "snowly.watch.message"
}
