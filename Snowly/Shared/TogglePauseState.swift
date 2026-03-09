//
//  TogglePauseState.swift
//  Snowly
//
//  Shared state for triggering pause/resume toggle from
//  Live Activity button and AppIntents.
//

import Observation

@Observable
@MainActor
final class TogglePauseState {
    static let shared = TogglePauseState()
    var pending = false
    private init() {}
}
