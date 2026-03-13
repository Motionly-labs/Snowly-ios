//
//  GearEmptyState.swift
//  Snowly
//
//  Empty state when no checklists exist.
//

import SwiftUI

struct GearEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("gear_empty_no_checklists_title", systemImage: "checklist")
        } description: {
            Text("gear_empty_checklist_description")
        } actions: {
            Button(action: onAdd) {
                Label("gear_empty_create_checklist_button", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
