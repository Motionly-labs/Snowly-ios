//
//  StartTrackingIntent.swift
//  Snowly
//
//  AppIntent for starting ski tracking from Control Center widget.
//  Shared between Snowly and SnowlyWidgetExtension targets.
//

import AppIntents

struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Ski Tracking"
    static let description: IntentDescription = "Start a ski tracking session in Snowly."
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
