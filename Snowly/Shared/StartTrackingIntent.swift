//
//  StartTrackingIntent.swift
//  Snowly
//
//  AppIntent and Siri Shortcuts for starting ski tracking.
//  Main app target only — do not add to SnowlyWidgetExtension.
//

import AppIntents

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
