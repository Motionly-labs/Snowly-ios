//
//  GearEditView.swift
//  Snowly
//
//  Add or edit a gear setup (name, brand, model, active status).
//

import SwiftUI
import SwiftData

struct GearEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Mode: Identifiable {
        case add
        case edit(GearSetup)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let setup): return setup.id.uuidString
            }
        }
    }

    let mode: Mode

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var isActive: Bool = true

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String {
        isEditing
            ? String(localized: "gear_edit_nav_title_edit")
            : String(localized: "gear_edit_nav_title_new")
    }

    var body: some View {
        NavigationStack {
            Form {

                Section(String(localized: "gear_edit_section_details")) {
                    TextField(String(localized: "gear_edit_field_setup_name"), text: $name)
                    TextField(String(localized: "gear_edit_field_brand_optional"), text: $brand)
                    TextField(String(localized: "gear_edit_field_model_optional"), text: $model)
                }

                Section {
                    Toggle(String(localized: "common_active"), isOn: $isActive)
                }

                if isEditing {
                    Section {
                        Button(String(localized: "gear_edit_action_add_default_items")) {
                            addDefaultItems()
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
                if case .edit(let setup) = mode {
                    name = setup.name
                    brand = setup.brand
                    model = setup.model
                    isActive = setup.isActive
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .add:
            let setup = GearSetup(
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespaces),
                model: model.trimmingCharacters(in: .whitespaces),
                isActive: isActive
            )
            modelContext.insert(setup)
            addDefaultItems(to: setup)

        case .edit(let setup):
            setup.name = trimmedName
            setup.brand = brand.trimmingCharacters(in: .whitespaces)
            setup.model = model.trimmingCharacters(in: .whitespaces)
            setup.isActive = isActive
        }
    }

    private func addDefaultItems() {
        guard case .edit(let setup) = mode else { return }
        addDefaultItems(to: setup)
    }

    private func addDefaultItems(to setup: GearSetup) {
        let defaults: [(String, GearCategory)] = [
            (String(localized: "gear.default_item.ski_jacket"), .clothing),
            (String(localized: "gear.default_item.ski_pants"), .clothing),
            (String(localized: "gear.default_item.base_layer_top"), .clothing),
            (String(localized: "gear.default_item.base_layer_bottom"), .clothing),
            (String(localized: "gear.default_item.ski_socks"), .clothing),
            (String(localized: "gear.default_item.helmet"), .protection),
            (String(localized: "gear.default_item.goggles"), .protection),
            (String(localized: "gear.default_item.gloves"), .accessories),
            (String(localized: "gear.default_item.skis"), .equipment),
            (String(localized: "gear.default_item.poles"), .equipment),
            (String(localized: "gear.default_item.ski_boots"), .footwear),
            (String(localized: "gear.default_item.lift_pass"), .accessories),
            (String(localized: "gear.default_item.sunscreen"), .accessories),
            (String(localized: "gear.default_item.phone_charger"), .electronics),
            (String(localized: "gear.default_item.backpack"), .backpack),
        ]

        let existingNames = Set(setup.items.map(\.name))
        for (index, (name, category)) in defaults.enumerated() {
            guard !existingNames.contains(name) else { continue }
            let item = GearItem(
                name: name,
                category: category,
                sortOrder: setup.items.count + index,
                setup: setup
            )
            modelContext.insert(item)
        }
    }
}
