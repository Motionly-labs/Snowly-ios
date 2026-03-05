//
//  GearItemEditView.swift
//  Snowly
//
//  Add or edit a single gear item.
//  Uses BodyZone picker so items map to the skier figure.
//

import SwiftUI
import SwiftData

struct GearItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let setup: GearSetup

    enum Mode {
        case add
        case edit(GearItem)
    }

    let mode: Mode
    var initialZone: BodyZone?

    @State private var name: String = ""
    @State private var selectedZone: BodyZone = .body

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String {
        isEditing
            ? String(localized: "gear_item_edit_nav_title_edit")
            : String(localized: "gear_item_edit_nav_title_add")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "gear_item_edit_section_details")) {
                    TextField(String(localized: "gear_item_edit_field_name"), text: $name)
                    Picker(String(localized: "gear_item_edit_picker_body_zone"), selection: $selectedZone) {
                        ForEach(BodyZone.allCases) { zone in
                            Label(zone.displayName, systemImage: zone.iconName)
                                .tag(zone)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common_save")) {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                switch mode {
                case .add:
                    if let zone = initialZone {
                        selectedZone = zone
                    }
                case .edit(let item):
                    name = item.name
                    selectedZone = BodyZone.zone(for: item.category)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let category = selectedZone.categories.first ?? .other

        switch mode {
        case .add:
            let item = GearItem(
                name: trimmedName,
                category: category,
                sortOrder: setup.items.count,
                setup: setup
            )
            modelContext.insert(item)

        case .edit(let item):
            item.name = trimmedName
            item.category = category
        }
    }
}
