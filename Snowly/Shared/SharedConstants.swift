//
//  SharedConstants.swift
//  Snowly
//
//  Constants shared between iOS and watchOS.
//

import Foundation

enum SharedConstants {
    // MARK: - Feature Window
    nonisolated static let featureWindowSeconds: TimeInterval = 8   // seconds of history used for classification

    // MARK: - Idle Detection
    nonisolated static let idleSpeedMax: Double = 0.6               // m/s — below = idle

    // MARK: - Skiing Detection
    nonisolated static let skiFastMin: Double = 6.0                 // m/s — unconditionally skiing (too fast for lift)
    nonisolated static let skiMinSpeed: Double = 2.8                // m/s — minimum for skiing + descent combo
    nonisolated static let skiVerticalSpeedMax: Double = -0.15      // m/s — must be descending to classify as skiing

    // MARK: - Lift Detection
    nonisolated static let liftSpeedMin: Double = 1.2               // m/s — minimum horizontal speed for lift
    nonisolated static let liftSpeedMax: Double = 6.5               // m/s — maximum horizontal speed for lift
    nonisolated static let liftVerticalSpeedMin: Double = -0.10     // m/s — allows horizontal and slight-descent lift transport (gondolas)

    // MARK: - Segment Validation (run → discard or degrade to walk)
    nonisolated static let skiMinAltitudeLoss: Double = 12          // m — minimum altitude loss for a valid ski run
    nonisolated static let skiMinAvgSpeed: Double = 3.5             // m/s — minimum average speed for a valid ski run
    nonisolated static let liftMinSegmentDuration: TimeInterval = 30 // s — minimum duration for a valid lift ride
    nonisolated static let liftMinAltitudeGain: Double = 20         // m — minimum altitude gain for a valid lift
    nonisolated static let liftMinAvgVerticalSpeed: Double = 0.10   // m/s — minimum avg vertical speed for a valid lift
    nonisolated static let walkMinSegmentDuration: TimeInterval = 6  // s — walk segments shorter than this are discarded

    // MARK: - Activity Dwell Time (hysteresis)
    nonisolated static let dwellTimeSkiingToLift: TimeInterval = 25  // conservative — lift confirmation takes longer
    nonisolated static let dwellTimeLiftToSkiing: TimeInterval = 5
    nonisolated static let dwellTimeIdleToSkiing: TimeInterval = 3
    nonisolated static let dwellTimeIdleToLift: TimeInterval = 10
    nonisolated static let dwellTimeAnyToWalk: TimeInterval = 4
    nonisolated static let dwellTimeWalkToSkiing: TimeInterval = 5
    nonisolated static let dwellTimeWalkToLift: TimeInterval = 15

    // MARK: - Segment Filtering
    nonisolated static let minSkiRunDuration: TimeInterval = 15.0   // seconds — shorter runs are discarded as lift-exit transitions

    // MARK: - GPS Sampling
    nonisolated static let highSpeedThreshold: Double = 5.0         // m/s
    nonisolated static let mediumSpeedThreshold: Double = 2.0       // m/s

    // MARK: - Buffer
    nonisolated static let recentPointsBufferSize: Int = 15         // ~15–20s of GPS points @1Hz

    // MARK: - Stop Detection
    nonisolated static let stopDurationThreshold: TimeInterval = 75 // seconds before ending a run

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
