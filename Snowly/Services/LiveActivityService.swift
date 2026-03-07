//
//  LiveActivityService.swift
//  Snowly
//
//  Manages the Live Activity for ski tracking sessions.
//  Handles start, update, and end lifecycle via ActivityKit.
//

import ActivityKit
import Foundation
import Observation

@Observable
@MainActor
final class LiveActivityService {
    private static let dismissalDelay: TimeInterval = 300 // 5 minutes
    private static let minUpdateInterval: TimeInterval = 5
    private var currentActivity: Activity<SnowlyActivityAttributes>?
    private var lastUpdateTime: Date?

    func startLiveActivity(startDate: Date, unitSystem: UnitSystem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SnowlyActivityAttributes(
            startDate: startDate,
            unitSystem: unitSystem
        )
        let initialState = SnowlyActivityAttributes.ContentState(
            currentSpeed: 0,
            totalVertical: 0,
            runCount: 0,
            elapsedSeconds: 0,
            currentActivity: "idle",
            isPaused: false,
            maxSpeed: 0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    func update(state: SnowlyActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }

        let now = Date()
        if let last = lastUpdateTime,
           now.timeIntervalSince(last) < Self.minUpdateInterval {
            return
        }
        lastUpdateTime = now

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endLiveActivity(finalState: SnowlyActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + Self.dismissalDelay)
            )
        }
    }
}
