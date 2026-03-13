//
//  TogglePauseIntent.swift
//  Snowly
//
//  AppIntent for toggling pause/resume from Live Activity button.
//  Shared between Snowly and SnowlyWidgetExtension targets.
//

import AppIntents

struct TogglePauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Pause"
    static let description: IntentDescription = IntentDescription("intent_toggle_pause_description", categoryName: "Tracking")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            TogglePauseState.shared.pending = true
        }
        return .result()
    }
}
