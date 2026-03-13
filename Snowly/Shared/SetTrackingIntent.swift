//
//  SetTrackingIntent.swift
//  Snowly
//
//  SetValueIntent for the Control Center toggle.
//  Shared between Snowly and SnowlyWidgetExtension targets.
//

import AppIntents
import Observation

@Observable
@MainActor
final class TrackingEnabledIntentState {
    static let shared = TrackingEnabledIntentState()
    var pendingValue: Bool?
    private init() {}
}

struct SetTrackingEnabledIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Tracking"
    static let description: IntentDescription = IntentDescription("intent_start_tracking_description", categoryName: "Tracking")
    static let openAppWhenRun = true

    @Parameter(title: "Tracking Enabled")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            TrackingEnabledIntentState.shared.pendingValue = value
        }
        return .result()
    }
}
