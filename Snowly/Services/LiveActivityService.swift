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
    private var minUpdateInterval: TimeInterval = 5
    private var currentActivity: Activity<SnowlyActivityAttributes>?
    private var lastUpdateTime: Date?

    func setMinimumUpdateInterval(seconds: TimeInterval) {
        let next = min(max(seconds, 0.5), 300)
        guard minUpdateInterval != next else { return }
        minUpdateInterval = next
        // Apply interval changes immediately without waiting for old throttle window.
        lastUpdateTime = nil
    }

    func startLiveActivity(startDate: Date, unitSystem: UnitSystem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Activities are disabled in system settings")
            return
        }

        // Reuse only truly active activities. Ended/dismissed ones must not be reused.
        if let current = currentActivity, current.activityState == .active {
            currentActivity = current
            lastUpdateTime = nil
            print("[LiveActivity] Reusing current active activity: \(current.id)")
            return
        }

        if let existing = Activity<SnowlyActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            currentActivity = existing
            lastUpdateTime = nil
            print("[LiveActivity] Reusing discovered active activity: \(existing.id)")
            return
        }

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
            lastUpdateTime = nil
            print("[LiveActivity] Started: \(activity.id)")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    func update(state: SnowlyActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }

        let now = Date()
        if let last = lastUpdateTime,
           now.timeIntervalSince(last) < minUpdateInterval {
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
        lastUpdateTime = nil

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
