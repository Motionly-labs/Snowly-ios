//
//  StartTrackingIntent.swift
//  Snowly
//
//  AppIntent for starting ski tracking from Control Center widget.
//  Shared between Snowly and SnowlyWidgetExtension targets.
//

import AppIntents
import Observation

struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Ski Tracking"
    static let description: IntentDescription = IntentDescription("intent_start_tracking_description", categoryName: "Tracking")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            QuickActionState.shared.pending = true
        }
        return .result()
    }
}

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

struct SnowlyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTrackingIntent(),
            phrases: [
                "Start skiing in \(.applicationName)",
                "Start tracking in \(.applicationName)",
            ],
            shortTitle: "Start Skiing",
            systemImageName: "figure.skiing.downhill"
        )
    }
}
