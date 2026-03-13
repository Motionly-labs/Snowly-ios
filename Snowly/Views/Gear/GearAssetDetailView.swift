//
//  GearAssetDetailView.swift
//  Snowly
//
//  Detail screen for one locker gear.
//

import SwiftUI
import SwiftData

struct GearAssetDetailView: View {
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]
    @Query(sort: \GearAsset.sortOrder) private var lockerAssets: [GearAsset]
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var settingsQuery: [DeviceSettings]

    private var settings: DeviceSettings? { settingsQuery.first }

    let asset: GearAsset

    @State private var showingEditor = false

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var usageSummary: StatsService.GearAssetUsageSummary {
        StatsService.gearAssetUsageSummary(for: asset, sessions: sessions)
    }

    private var reminderSchedule: GearReminderSchedule? {
        GearReminderScheduleStore.schedule(for: asset.id, in: settings)
    }

    private var nextReminderDate: Date? {
        reminderSchedule?.nextOccurrence()
    }

    private var assignedSetups: [GearSetup] {
        GearLockerService.checklists(for: asset, from: setups)
    }

    private var recentSessions: [SkiSession] {
        GearLockerService.recentSessions(for: asset, from: sessions)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Label(asset.category.rawValue, systemImage: asset.category.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ColorTokens.primaryAccent)
                            Text(asset.displayName)
                                .font(Typography.primaryTitle)
                            Text(asset.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.sm) {
                            GearSummaryBadge(
                                "\(usageSummary.skiDays) ski days",
                                systemImage: "calendar",
                                tint: ColorTokens.primaryAccent
                            )
                            reminderBadge
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            GearSummaryBadge(
                                "\(usageSummary.skiDays) ski days",
                                systemImage: "calendar",
                                tint: ColorTokens.primaryAccent
                            )
                            reminderBadge
                        }
                    }

                    if let reminderSchedule {
                        Label(reminderSchedule.summaryText(), systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section(String(localized: "gear_asset_in_checklists_section")) {
                if assignedSetups.isEmpty {
                    Text(String(localized: "gear_asset_not_in_checklist"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedSetups) { setup in
                        NavigationLink(destination: GearDetailView(setup: setup)) {
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

            Section(String(localized: "gear_asset_reminder_schedule_section")) {
                if let reminderSchedule {
                    detailRow("Schedule", value: reminderSchedule.summaryText())
                    if let nextReminderDate {
                        detailRow("Next", value: nextReminderDate.longDisplay)
                    }
                } else {
                    Text(String(localized: "gear_asset_no_reminders"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "gear_asset_gear_section")) {
                if let acquiredAt = asset.acquiredAt {
                    detailRow("Acquired", value: acquiredAt.longDisplay)
                }
            }

            if !recentSessions.isEmpty {
                Section(String(localized: "gear_asset_recent_sessions_section")) {
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

            if let notes = asset.notes, !notes.isEmpty {
                Section(String(localized: "gear_asset_notes_section")) {
                    Text(notes)
                }
            }
        }
        .navigationTitle(asset.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            GearAssetEditorView(mode: .edit(asset))
        }
    }

    @ViewBuilder
    private var reminderBadge: some View {
        if let nextReminderDate {
            GearSummaryBadge(
                "Next \(nextReminderDate.relativeDisplay)",
                systemImage: "bell.badge",
                tint: ColorTokens.primaryAccent.opacity(0.9)
            )
        } else {
            GearSummaryBadge(
                "No reminder",
                systemImage: "bell.slash",
                tint: Color.secondary
            )
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
