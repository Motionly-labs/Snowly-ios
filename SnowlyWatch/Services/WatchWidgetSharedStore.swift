//
//  WatchWidgetSharedStore.swift
//  SnowlyWatch
//
//  Persists live tracking state to UserDefaults so the embedded
//  ActiveSessionWidget complication can reflect real-time data.
//  Calls WidgetCenter to trigger a timeline refresh after each write.
//

import Foundation
import WidgetKit

enum WatchWidgetSharedStore {

    /// Writes the current tracking snapshot and triggers a complication reload.
    static func write(isTracking: Bool, runCount: Int, sessionStart: Date?) {
        let defaults = UserDefaults.standard
        defaults.set(isTracking, forKey: SharedConstants.complicationIsTrackingKey)
        defaults.set(runCount, forKey: SharedConstants.complicationRunCountKey)
        if let sessionStart {
            defaults.set(
                sessionStart.timeIntervalSinceReferenceDate,
                forKey: SharedConstants.complicationSessionStartKey
            )
        } else {
            defaults.removeObject(forKey: SharedConstants.complicationSessionStartKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedConstants.complicationWidgetKind)
    }

    /// Reads the last persisted snapshot.
    static func read() -> (isTracking: Bool, runCount: Int, duration: TimeInterval) {
        let defaults = UserDefaults.standard
        let isTracking = defaults.bool(forKey: SharedConstants.complicationIsTrackingKey)
        let runCount = defaults.integer(forKey: SharedConstants.complicationRunCountKey)
        let duration: TimeInterval
        if isTracking,
           let raw = defaults.object(forKey: SharedConstants.complicationSessionStartKey) as? Double {
            let start = Date(timeIntervalSinceReferenceDate: raw)
            duration = Date.now.timeIntervalSince(start)
        } else {
            duration = 0
        }
        return (isTracking, runCount, duration)
    }
}
