//
//  WatchMessage.swift
//  Snowly
//
//  Communication protocol between iOS and watchOS.
//

import Foundation

/// Messages exchanged between iPhone and Apple Watch via WCSession.
enum WatchMessage: Codable, Sendable {

    // MARK: - Phone → Watch
    case trackingStarted(sessionId: UUID)
    case trackingPaused
    case trackingResumed
    case trackingStopped
    case liveUpdate(LiveTrackingData)
    case newPersonalBest(metric: String, value: Double)

    case unitPreference(UnitSystem)
    case sessionHistory(SeasonBestData)

    // MARK: - Watch → Phone
    case requestStart
    case requestPause
    case requestResume
    case requestStop
    case requestStatus
    case watchWorkoutStarted(sessionId: UUID)
    case watchWorkoutSummary(IndependentWorkoutSummary)
    case watchWorkoutEnded
    case watchTrackPoints([TrackPoint])
    case liveVitals(LiveVitalsData)

    // MARK: - Shared payload
    struct LiveTrackingData: Codable, Sendable, Equatable {
        let currentSpeed: Double
        let maxSpeed: Double
        let totalDistance: Double
        let totalVertical: Double
        let runCount: Int
        let elapsedTime: TimeInterval
        let batteryLevel: Float
    }

    struct SeasonBestData: Codable, Sendable, Equatable {
        let bestMaxSpeed: Double
        let bestVertical: Double
        let totalRuns: Int
        let totalSessions: Int
    }

    struct IndependentWorkoutSummary: Codable, Sendable, Equatable {
        let sessionId: UUID
        let startDate: Date
        let endDate: Date
        let totalDistance: Double
        let totalVertical: Double
        let maxSpeed: Double
        let runCount: Int
        let elapsedTime: TimeInterval
        let trackPointCount: Int
    }

    struct LiveVitalsData: Codable, Sendable, Equatable {
        let currentHeartRate: Double
        let averageHeartRate: Double
    }
}
