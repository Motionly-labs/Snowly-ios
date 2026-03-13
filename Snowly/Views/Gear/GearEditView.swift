//
//  GearEditView.swift
//  Snowly
//
//  Add or edit a checklist that selects gear from the locker.
//

import SwiftUI
import SwiftData

struct GearEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]

    enum Mode: Identifiable {
        case add
        case edit(GearSetup)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let setup):
                return setup.id.uuidString
            }
        }
    }

    let mode: Mode

    @State private var name = ""
    @State private var notes = ""
    @State private var isActive = false

    private var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    private var title: String {
        isEditing ? String(localized: "gear_edit_edit_title") : String(localized: "gear_edit_new_title")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "gear_edit_checklist_section")) {
                    TextField(String(localized: "gear_edit_checklist_name_placeholder"), text: $name)
                    TextField(String(localized: "gear_edit_notes_placeholder"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle(String(localized: "gear_edit_active_toggle"), isOn: $isActive)
                }

                if isEditing {
                    Section {
                        Text("gear_edit_active_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common_cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common_save")) {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard case .edit(let setup) = mode else { return }
        name = setup.name
        notes = setup.notes ?? ""
        isActive = setup.isActive
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        guard !trimmedName.isEmpty else { return }

        if isActive {
            for setup in setups {
                setup.isActive = false
            }
        }

        switch mode {
        case .add:
            let nextSortOrder = (setups.map(\.sortOrder).max() ?? -1) + 1
            let setup = GearSetup(
                name: trimmedName,
                notes: trimmedNotes,
                isActive: isActive || setups.isEmpty,
                sortOrder: nextSortOrder
            )
            modelContext.insert(setup)

        case .edit(let setup):
            setup.name = trimmedName
            setup.notes = trimmedNotes
            setup.isActive = isActive
        }
    }
}
