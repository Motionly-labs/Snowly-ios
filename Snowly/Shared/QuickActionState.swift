//
//  QuickActionState.swift
//  Snowly
//
//  Shared state for triggering quick-start from Quick Actions,
//  Control Center widget, and deep links.
//

import Observation

@Observable
@MainActor
final class QuickActionState {
    static let shared = QuickActionState()
    var pending = false
    private init() {}
}
