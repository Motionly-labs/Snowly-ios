//
//  GearDetailView.swift
//  Snowly
//
//  Detail screen for one checklist and its selected gear.
//

import SwiftUI
import SwiftData

struct GearDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query(sort: \GearAsset.sortOrder) private var lockerAssets: [GearAsset]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var settingsQuery: [DeviceSettings]

    private var settings: DeviceSettings? { settingsQuery.first }

    let setup: GearSetup

    @State private var showingSetupEditor = false
    @State private var showingAddGear = false

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var usageSummary: StatsService.GearUsageSummary {
        StatsService.gearUsageSummary(for: setup.id, sessions: sessions)
    }

    private var recentSessions: [SkiSession] {
        Array(sessions
            .filter { $0.gearSetupId == setup.id && $0.runCount > 0 }
            .prefix(5))
    }

    private var gearInChecklist: [GearAsset] {
        GearLockerService.gear(in: setup, from: lockerAssets)
    }

    private var availableAssets: [GearAsset] {
        let selectedIDs = Set(gearInChecklist.map(\.id))
        return lockerAssets
            .filter { !$0.isArchived && !selectedIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var reminderSchedules: [UUID: GearReminderSchedule] {
        GearReminderScheduleStore.schedules(for: gearInChecklist + availableAssets, in: settings)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(setup.name)
                        .font(Typography.primaryTitle)

                    Text(GearLockerService.checklistSubtitle(for: setup, in: lockerAssets))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.sm) {
                            GearSummaryBadge(
                                "\(usageSummary.skiDays) ski days",
                                systemImage: "calendar",
                                tint: ColorTokens.primaryAccent
                            )
                            GearSummaryBadge(
                                "\(gearInChecklist.count) gear",
                                systemImage: "checklist",
                                tint: Color.secondary
                            )
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            GearSummaryBadge(
                                "\(usageSummary.skiDays) ski days",
                                systemImage: "calendar",
                                tint: ColorTokens.primaryAccent
                            )
                            GearSummaryBadge(
                                "\(gearInChecklist.count) gear",
                                systemImage: "checklist",
                                tint: Color.secondary
                            )
                        }
                    }

                    if setup.isActive {
                        GearSummaryBadge(
                            String(localized: "gear_detail_active_badge"),
                            systemImage: "checkmark.circle.fill",
                            tint: ColorTokens.success
                        )
                    } else {
                        Button(String(localized: "gear_detail_set_active_button")) {
                            activateSetup()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section(String(localized: "gear_detail_in_checklist_section")) {
                if gearInChecklist.isEmpty {
                    Text("gear_detail_no_gear_placeholder")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(gearInChecklist) { item in
                        NavigationLink(destination: GearAssetDetailView(asset: item)) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: item.category.iconName)
                                    .foregroundStyle(BodyZone.zone(for: item.category).accentColor)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(item.displayName)
                                        .fontWeight(.medium)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let nextReminder = nextReminderText(for: item) {
                                        Text(nextReminder)
                                            .font(.caption2)
                                            .foregroundStyle(ColorTokens.primaryAccent)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, Spacing.xxs)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(String(localized: "gear_detail_remove_button"), systemImage: "minus.circle.fill", role: .destructive) {
                                detach(item)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "gear_detail_available_section")) {
                if availableAssets.isEmpty {
                    Text("gear_detail_all_assigned_placeholder")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableAssets) { asset in
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(asset.displayName)
                                    .fontWeight(.medium)
                                Text(GearLockerService.checklistNamesSummary(for: asset, from: setups))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if let nextReminder = nextReminderText(for: asset) {
                                    Text(nextReminder)
                                        .font(.caption2)
                                        .foregroundStyle(ColorTokens.primaryAccent)
                                }
                            }
                            Spacer()
                            Button(String(localized: "gear_detail_add_button")) {
                                attach(asset)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
            }

            if !recentSessions.isEmpty {
                Section(String(localized: "gear_detail_recent_sessions_section")) {
                    ForEach(recentSessions) { session in
                        NavigationLink(
                            destination: SessionSummaryView(
                                selectedSession: session,
                                showsDoneButton: false,
                                processesPersonalBests: false
                            )
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(session.startDate.shortDisplay)
                                        .fontWeight(.medium)
                                    Text(session.resort?.name ?? "Unknown resort")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                    Text("session_run_count_format \(session.runCount)")
                                        .font(.caption)
                                    Text(Formatters.distance(session.totalDistance, unit: unitSystem))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(setup.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingSetupEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }

                Button {
                    showingAddGear = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingSetupEditor) {
            GearEditView(mode: .edit(setup))
        }
        .sheet(isPresented: $showingAddGear) {
            GearAssetEditorView(mode: .add(initialSetup: setup))
        }
    }

    private func attach(_ asset: GearAsset) {
        GearLockerService.assign(asset, to: setup)
    }

    private func detach(_ asset: GearAsset) {
        GearLockerService.unassign(asset, from: setup)
    }

    private func activateSetup() {
        let selectedSetupID = setup.id
        for other in (try? modelContext.fetch(FetchDescriptor<GearSetup>())) ?? [] {
            other.isActive = (other.id == selectedSetupID)
        }
    }

    private func nextReminderText(for asset: GearAsset) -> String? {
        guard let nextReminder = reminderSchedules[asset.id]?.nextOccurrence() else {
            return nil
        }
        return String(localized: "gear_locker_reminder_next_relative_format \(nextReminder.relativeDisplay)")
    }

}
