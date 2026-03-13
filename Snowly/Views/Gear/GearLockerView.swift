//
//  GearLockerView.swift
//  Snowly
//
//  Dedicated locker page shared across all checklists.
//

import SwiftData
import SwiftUI

struct GearLockerView: View {
    @Binding var selectedPage: GearWorkspacePage
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]
    @Query(sort: \GearAsset.sortOrder) private var assets: [GearAsset]
    @Query private var settingsQuery: [DeviceSettings]

    private var settings: DeviceSettings? { settingsQuery.first }

    @State private var showingNewGear = false

    private var lockerGear: [GearAsset] {
        assets
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func reminderEntries(from map: [UUID: GearReminderSchedule]) -> [GearReminderEntry] {
        lockerGear
            .compactMap { item in
                guard
                    let schedule = map[item.id],
                    let nextDate = schedule.nextOccurrence()
                else {
                    return nil
                }
                return GearReminderEntry(gear: item, schedule: schedule, nextDate: nextDate)
            }
            .sorted { $0.nextDate < $1.nextDate }
    }

    @ViewBuilder
    private var lockerContent: some View {
        if lockerGear.isEmpty {
            ContentUnavailableView {
                Label("gear_locker_empty_title", systemImage: "bag")
            } description: {
                Text("gear_locker_empty_description")
            } actions: {
                Button {
                    showingNewGear = true
                } label: {
                    Label("gear_locker_create_button", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            let schedules = GearReminderScheduleStore.schedules(for: lockerGear, in: settings)
            let entries = reminderEntries(from: schedules)
            List {
                if !entries.isEmpty {
                    Section(String(localized: "gear_locker_reminders_section")) {
                        ForEach(entries.prefix(3)) { entry in
                            NavigationLink(destination: GearAssetDetailView(asset: entry.gear)) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(entry.gear.displayName)
                                        .fontWeight(.medium)
                                    Text(entry.schedule.summaryText(nextDate: entry.nextDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("gear_locker_reminder_next_date_format \(entry.nextDate.longDisplay)")
                                        .font(.caption2)
                                        .foregroundStyle(ColorTokens.primaryAccent)
                                }
                                .padding(.vertical, Spacing.xxs)
                            }
                        }
                    }
                }

                Section(String(localized: "gear_locker_all_gear_section")) {
                    ForEach(lockerGear) { item in
                        NavigationLink(destination: GearAssetDetailView(asset: item)) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: item.category.iconName)
                                    .foregroundStyle(BodyZone.zone(for: item.category).accentColor)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(item.displayName)
                                        .fontWeight(.medium)
                                    Text(GearLockerService.checklistNamesSummary(for: item, from: setups))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let nextReminder = schedules[item.id]?.nextOccurrence() {
                                        Text("gear_locker_reminder_next_relative_format \(nextReminder.relativeDisplay)")
                                            .font(.caption2)
                                            .foregroundStyle(ColorTokens.primaryAccent)
                                    }
                                }
                            }
                            .padding(.vertical, Spacing.xxs)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    var body: some View {
        NavigationStack {
            lockerContent
            .navigationTitle(String(localized: "gear_locker_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedPage = .checklist
                        }
                    } label: {
                        Label("gear_locker_back_to_checklist", systemImage: "checklist")
                            .font(.caption.weight(.semibold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewGear = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewGear) {
                GearAssetEditorView(mode: .add(initialSetup: nil))
            }
        }
    }
}

#Preview {
    GearLockerView(selectedPage: .constant(.locker))
        .modelContainer(for: [
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            DeviceSettings.self,
        ], inMemory: true)
}
