//
//  GearAssetEditorView.swift
//  Snowly
//
//  Create or edit locker gear and choose which checklists use it.
//

import SwiftUI
import SwiftData

struct GearAssetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GearReminderService.self) private var gearReminderService
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]
    @Query(sort: \GearAsset.sortOrder) private var lockerAssets: [GearAsset]
    @Query private var settingsQuery: [DeviceSettings]

    private var settings: DeviceSettings? { settingsQuery.first }

    enum Mode: Identifiable {
        case add(initialSetup: GearSetup?)
        case edit(GearAsset)

        var id: String {
            switch self {
            case .add(let setup):
                return "add-\(setup?.id.uuidString ?? "locker")"
            case .edit(let asset):
                return asset.id.uuidString
            }
        }
    }

    let mode: Mode

    @State private var name = ""
    @State private var category: GearAssetCategory = .skis
    @State private var brand = ""
    @State private var model = ""
    @State private var notes = ""
    @State private var hasAcquiredDate = false
    @State private var acquiredAt = Date()
    @State private var reminderEnabled = false
    @State private var reminderStartDate = Calendar.current.startOfDay(for: .now)
    @State private var reminderEndDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var reminderIntervalValueText = "1"
    @State private var reminderIntervalUnit: GearReminderIntervalUnit = .day
    @State private var reminderTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
    @State private var isArchived = false
    @State private var selectedSetupIDs: Set<UUID> = []

    private var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    private var title: String {
        isEditing ? "Edit Gear" : "New Gear"
    }

    private var parsedReminderIntervalValue: Int? {
        let trimmed = reminderIntervalValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var reminderSchedule: GearReminderSchedule? {
        guard reminderEnabled, let intervalValue = parsedReminderIntervalValue, intervalValue > 0 else {
            return nil
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        return GearReminderSchedule(
            startDate: reminderStartDate,
            endDate: reminderEndDate,
            intervalValue: intervalValue,
            intervalUnit: reminderIntervalUnit,
            hour: components.hour ?? 20,
            minute: components.minute ?? 0
        )
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if reminderEnabled {
            guard let schedule = reminderSchedule, schedule.isValid else {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "gear_editor_gear_section")) {
                    TextField(String(localized: "gear_editor_gear_name_placeholder"), text: $name)

                    NavigationLink {
                        GearCategoryPickerView(selection: $category)
                    } label: {
                        HStack {
                            Text("Category")
                                .foregroundStyle(.primary)
                            Spacer()
                            Label(category.rawValue, systemImage: category.iconName)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    TextField(String(localized: "gear_editor_brand_placeholder"), text: $brand)
                    TextField(String(localized: "gear_editor_model_placeholder"), text: $model)
                }

                Section(String(localized: "gear_editor_used_in_section")) {
                    if setups.isEmpty {
                        Text("gear_editor_no_checklists_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(setups) { setup in
                            Toggle(
                                isOn: Binding(
                                    get: { selectedSetupIDs.contains(setup.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedSetupIDs.insert(setup.id)
                                        } else {
                                            selectedSetupIDs.remove(setup.id)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(setup.name)
                                    Text(GearLockerService.checklistSubtitle(for: setup, in: lockerAssets))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "gear_editor_reminder_section")) {
                    Toggle(String(localized: "gear_editor_enable_reminders_toggle"), isOn: $reminderEnabled.animation())

                    if reminderEnabled {
                        DatePicker(String(localized: "gear_editor_from_date_label"), selection: $reminderStartDate, displayedComponents: .date)
                        DatePicker(
                            String(localized: "gear_editor_to_date_label"),
                            selection: $reminderEndDate,
                            in: reminderStartDate...,
                            displayedComponents: .date
                        )

                        HStack {
                            TextField(String(localized: "gear_editor_every_placeholder"), text: $reminderIntervalValueText)
                                .keyboardType(.numberPad)

                            Picker(String(localized: "gear_editor_unit_picker_label"), selection: $reminderIntervalUnit) {
                                ForEach(GearReminderIntervalUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayLabel.capitalized)
                                        .tag(unit)
                                }
                            }
                        }

                        DatePicker(String(localized: "gear_editor_time_label"), selection: $reminderTime, displayedComponents: .hourAndMinute)

                        Text("gear_editor_reminder_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "gear_editor_extra_section")) {
                    Toggle(String(localized: "gear_editor_track_acquisition_toggle"), isOn: $hasAcquiredDate.animation())
                    if hasAcquiredDate {
                        DatePicker(String(localized: "gear_editor_acquired_label"), selection: $acquiredAt, displayedComponents: .date)
                    }

                    TextField(String(localized: "gear_editor_notes_placeholder"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)

                    if isEditing {
                        Toggle(String(localized: "gear_editor_archived_toggle"), isOn: $isArchived)
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
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        switch mode {
        case .add(let initialSetup):
            if let initialSetup {
                selectedSetupIDs = [initialSetup.id]
            }

        case .edit(let asset):
            name = asset.name
            category = asset.category
            brand = asset.brand
            model = asset.model
            notes = asset.notes ?? ""
            acquiredAt = asset.acquiredAt ?? acquiredAt
            hasAcquiredDate = asset.acquiredAt != nil
            isArchived = asset.isArchived
            selectedSetupIDs = Set(asset.setupIDs)

            if let schedule = GearReminderScheduleStore.schedule(for: asset.id, in: settings) {
                reminderEnabled = true
                reminderStartDate = schedule.startDate
                reminderEndDate = schedule.endDate
                reminderIntervalValueText = String(schedule.intervalValue)
                reminderIntervalUnit = schedule.intervalUnit
                reminderTime = Calendar.current.date(
                    bySettingHour: schedule.hour,
                    minute: schedule.minute,
                    second: 0,
                    of: reminderTime
                ) ?? reminderTime
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty

        let resolvedSetupIDs = setups
            .filter { selectedSetupIDs.contains($0.id) }
            .map(\.id)

        let targetAsset: GearAsset

        switch mode {
        case .add:
            let nextSortOrder = (lockerAssets.map(\.sortOrder).max() ?? -1) + 1
            let asset = GearAsset(
                name: trimmedName,
                category: category,
                brand: trimmedBrand,
                model: trimmedModel,
                notes: trimmedNotes,
                acquiredAt: hasAcquiredDate ? acquiredAt : nil,
                isArchived: false,
                sortOrder: nextSortOrder,
                setupIDs: resolvedSetupIDs
            )
            modelContext.insert(asset)
            targetAsset = asset

        case .edit(let asset):
            asset.name = trimmedName
            asset.category = category
            asset.brand = trimmedBrand
            asset.model = trimmedModel
            asset.notes = trimmedNotes
            asset.acquiredAt = hasAcquiredDate ? acquiredAt : nil
            asset.isArchived = isArchived
            asset.setupIDs = resolvedSetupIDs
            targetAsset = asset
        }

        if let settings {
            GearReminderScheduleStore.setSchedule(reminderSchedule, for: targetAsset.id, in: settings)
        }
        try? modelContext.save()
        if reminderEnabled {
            gearReminderService.requestPermissionIfNeeded()
        }
        gearReminderService.syncAll(using: modelContext)
    }
}
