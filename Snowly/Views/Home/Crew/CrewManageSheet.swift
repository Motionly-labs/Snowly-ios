//
//  CrewManageSheet.swift
//  Snowly
//
//  Sheet for managing a crew: member list, invite link, leave/dissolve.
//

import SwiftUI

struct CrewManageSheet: View {
    @Environment(CrewService.self) private var crewService
    @Environment(\.dismiss) private var dismiss

    @State private var pendingInvite: CrewInvite?
    @State private var showLeaveConfirmation = false
    @State private var showInviteShareSheet = false
    @State private var isGeneratingInvite = false
    @State private var inviteShareItems: [Any] = []
    @State private var removingMemberIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let displayedErrorMessage {
                    Section {
                        Text(displayedErrorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                syncSection
                membersSection
                inviteSection
                dangerSection
            }
            .navigationTitle(crewService.activeCrew?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common_done")) { dismiss() }
                }
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button(confirmButtonLabel, role: .destructive) {
                    performLeaveOrDissolve()
                }
            }
            .sheet(isPresented: $showInviteShareSheet) {
                ShareSheet(items: inviteShareItems)
            }
        }
    }

    // MARK: - Members

    private var syncSection: some View {
        Section {
            Toggle(String(localized: "crew_sync_share_location"), isOn: shareLocationBinding)
                .disabled(crewService.isManualSyncInProgress)

            Picker(String(localized: "crew_sync_mode"), selection: syncModeBinding) {
                Text(String(localized: "crew_sync_mode_automatic")).tag(CrewSyncMode.automatic)
                Text(String(localized: "crew_sync_mode_manual")).tag(CrewSyncMode.manual)
            }
            .pickerStyle(.segmented)
            .disabled(crewService.isManualSyncInProgress)

            if crewService.syncPreferences.mode == .automatic {
                Picker(String(localized: "crew_sync_refresh_every"), selection: syncIntervalBinding) {
                    ForEach(CrewSyncPreferences.supportedIntervals, id: \.self) { interval in
                        Text(intervalLabel(for: interval)).tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .disabled(crewService.isManualSyncInProgress)
            } else {
                Button {
                    runManualSync()
                } label: {
                    HStack {
                        if crewService.isManualSyncInProgress {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "crew_sync_syncing"))
                        } else {
                            Label(
                                String(localized: "crew_sync_now"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                }
                .disabled(crewService.isManualSyncInProgress)
            }

            if let lastSyncDate = crewService.lastSyncDate {
                LabeledContent(String(localized: "crew_sync_last_sync")) {
                    Text(lastSyncDate, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "crew_sync_section_title"))
        } footer: {
            Text(syncFooterText)
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(crewService.activeCrew?.members ?? []) { member in
                HStack(spacing: 10) {
                    Circle()
                        .fill(member.isOnline ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(member.displayName)
                        .font(.body)

                    if member.isCreator {
                        Text(String(localized: "crew_host"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    Spacer()

                    if removingMemberIds.contains(member.id) {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .opacity(removingMemberIds.contains(member.id) ? 0.6 : 1)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if crewService.canKick(member) {
                        Button(role: .destructive) {
                            removeMember(member)
                        } label: {
                            Label(String(localized: "common_delete"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "crew_members"))
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            Button {
                generateInvite()
            } label: {
                Label(
                    String(localized: "crew_generate_invite"),
                    systemImage: "link.badge.plus"
                )
            }
            .disabled(isGeneratingInvite)
        } header: {
            Text(String(localized: "crew_invite"))
        }
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showLeaveConfirmation = true
            } label: {
                Label(
                    crewService.isHost
                        ? String(localized: "crew_dissolve")
                        : String(localized: "crew_leave"),
                    systemImage: crewService.isHost
                        ? "trash"
                        : "rectangle.portrait.and.arrow.right"
                )
            }
        }
    }

    // MARK: - Actions

    private func generateInvite() {
        isGeneratingInvite = true
        Task {
            do {
                pendingInvite = try await crewService.generateInvite()
                guard let url = pendingInvite?.shareURL else {
                    throw CrewServiceError.invalidInvite
                }
                inviteShareItems = [url]
                showInviteShareSheet = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isGeneratingInvite = false
        }
    }

    private func removeMember(_ member: CrewMember) {
        guard !removingMemberIds.contains(member.id) else { return }

        removingMemberIds.insert(member.id)
        Task {
            do {
                try await crewService.kickMember(member)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            removingMemberIds.remove(member.id)
        }
    }

    private func performLeaveOrDissolve() {
        Task {
            do {
                if crewService.isHost {
                    try await crewService.dissolveCrew()
                } else {
                    try await crewService.leaveCrew()
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var confirmTitle: String {
        crewService.isHost
            ? String(localized: "crew_dissolve_confirm")
            : String(localized: "crew_leave_confirm")
    }

    private var confirmButtonLabel: String {
        crewService.isHost
            ? String(localized: "crew_dissolve")
            : String(localized: "crew_leave")
    }

    private func runManualSync() {
        errorMessage = nil
        Task {
            await crewService.syncNow()
            if crewService.lastError != nil {
                errorMessage = crewService.lastError
            }
        }
    }

    private var displayedErrorMessage: String? {
        errorMessage ?? crewService.lastError
    }

    private var shareLocationBinding: Binding<Bool> {
        Binding(
            get: { crewService.syncPreferences.shareLocationEnabled },
            set: { newValue in
                var updated = crewService.syncPreferences
                updated.shareLocationEnabled = newValue
                crewService.updateSyncPreferences(updated)
            }
        )
    }

    private var syncModeBinding: Binding<CrewSyncMode> {
        Binding(
            get: { crewService.syncPreferences.mode },
            set: { newValue in
                var updated = crewService.syncPreferences
                updated.mode = newValue
                crewService.updateSyncPreferences(updated)
            }
        )
    }

    private var syncIntervalBinding: Binding<Int> {
        Binding(
            get: { crewService.syncPreferences.intervalSeconds },
            set: { newValue in
                var updated = crewService.syncPreferences
                updated.intervalSeconds = newValue
                crewService.updateSyncPreferences(updated)
            }
        )
    }

    private func intervalLabel(for interval: Int) -> String {
        if interval >= 60 {
            return localizedFormat("crew_sync_interval_minutes_format", Int64(interval / 60))
        }

        return localizedFormat("crew_sync_interval_seconds_format", Int64(interval))
    }

    private var syncFooterText: String {
        let effectiveIntervalLabel = intervalLabel(for: effectiveAutomaticIntervalSeconds)
        let isCrewLimited = effectiveAutomaticIntervalSeconds > crewService.syncPreferences.intervalSeconds

        switch (crewService.syncPreferences.mode, crewService.syncPreferences.shareLocationEnabled) {
        case (.automatic, true):
            if isCrewLimited {
                return localizedFormat(
                    "crew_sync_footer_auto_share_limited",
                    effectiveIntervalLabel,
                    effectiveIntervalLabel
                )
            }

            return localizedFormat("crew_sync_footer_auto_share", effectiveIntervalLabel)
        case (.automatic, false):
            if isCrewLimited {
                return localizedFormat(
                    "crew_sync_footer_auto_private_limited",
                    effectiveIntervalLabel,
                    effectiveIntervalLabel
                )
            }

            return localizedFormat("crew_sync_footer_auto_private", effectiveIntervalLabel)
        case (.manual, true):
            return String(localized: "crew_sync_footer_manual_share")
        case (.manual, false):
            return String(localized: "crew_sync_footer_manual_private")
        }
    }

    private var effectiveAutomaticIntervalSeconds: Int {
        max(
            crewService.syncPreferences.intervalSeconds,
            crewService.activeCrew?.locationUpdateIntervalSeconds ?? crewService.syncPreferences.intervalSeconds
        )
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        let format = String(localized: String.LocalizationValue(key))
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
