//
//  GearEmptyState.swift
//  Snowly
//
//  Empty state when no gear setups exist.
//

import SwiftUI

struct GearEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "gear_empty_title"), systemImage: "backpack")
        } description: {
            Text(String(localized: "gear_empty_description"))
        } actions: {
            Button(action: onAdd) {
                Label(String(localized: "gear_empty_action_create_setup"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
