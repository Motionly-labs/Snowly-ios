//
//  GearListView.swift
//  Snowly
//
//  Locker-first Gear home with a visual checklist layered on top.
//

import SwiftData
import SwiftUI

struct GearListView: View {
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]
    @Query(sort: \GearAsset.sortOrder) private var assets: [GearAsset]
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query private var settingsQuery: [DeviceSettings]
    @Environment(\.modelContext) private var modelContext

    private var settings: DeviceSettings? { settingsQuery.first }

    @Binding var selectedPage: GearWorkspacePage
    @State private var showingNewChecklist = false
    @State private var selectedZone: BodyZone?
    @State private var hasAutoSelectedZone = false

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

    private var activeChecklist: GearSetup? {
        setups.first(where: \.isActive) ?? setups.first
    }

    private var activeChecklistUsage: StatsService.GearUsageSummary? {
        guard let activeChecklist else { return nil }
        return StatsService.gearUsageSummary(for: activeChecklist.id, sessions: sessions)
    }

    private var activeChecklistSessions: [SkiSession] {
        guard let activeChecklist else { return [] }
        return sessions.filter { $0.gearSetupId == activeChecklist.id && $0.runCount > 0 }
    }

    private var emptyLocker: Bool {
        setups.isEmpty && lockerGear.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.content) {
                    if emptyLocker {
                        emptyState
                            .padding(.horizontal, Spacing.xl)
                    } else {
                        header
                            .padding(.horizontal, Spacing.xl)

                        if let activeChecklist {
                            visualChecklistSection(activeChecklist)
                                .padding(.horizontal, Spacing.xl)
                        } else {
                            noChecklistSection
                                .padding(.horizontal, Spacing.xl)
                        }

                        if let activeChecklist, !activeChecklistSessions.isEmpty {
                            recentSessionsSection(activeChecklist)
                                .padding(.horizontal, Spacing.xl)
                        }
                    }
                }
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.section)
            }
            .navigationTitle(String(localized: "gear_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedPage = .locker
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("Locker")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewChecklist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewChecklist) {
                GearEditView(mode: .add)
            }
            .onAppear {
                resetZoneSelection()
            }
            .onChange(of: activeChecklist?.id) { _, _ in
                resetZoneSelection()
            }
            .onChange(of: assets.map(\.id)) { _, _ in
                resetZoneSelection()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            GearEmptyState {
                showingNewChecklist = true
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedPage = .locker
                }
            } label: {
                Label(String(localized: "gear_open_locker"), systemImage: "line.3.horizontal")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Menu {
                ForEach(setups) { checklist in
                    Button {
                        activate(checklist)
                    } label: {
                        HStack {
                            Text(checklist.name)
                            if checklist.id == activeChecklist?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(activeChecklist?.name ?? "Locker")
                        .font(.title2.bold())
                    if !setups.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let activeChecklist {
                NavigationLink(destination: GearDetailView(setup: activeChecklist)) {
                    Text("gear_list_checklist_link")
                        .font(.caption.weight(.semibold))
                }
            } else {
                Text(lockerGear.isEmpty ? "EMPTY" : "\(lockerGear.count) GEAR")
                    .font(.caption.bold())
                    .foregroundStyle(lockerGear.isEmpty ? .secondary : ColorTokens.primaryAccent)
            }
        }
    }

    private var noChecklistSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "gear_no_checklist_selected"))
                .font(Typography.primaryTitle)
            Text(String(localized: "gear_pull_gear_hint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showingNewChecklist = true
            } label: {
                Label(String(localized: "gear_empty_action_create_setup"), systemImage: "square.stack.3d.up")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xl)
        .dashboardCardBackground(accent: ColorTokens.primaryAccent)
    }

    private func visualChecklistSection(_ checklist: GearSetup) -> some View {
        let checklistGear = gear(in: checklist)
        let checkedIDs = checkedGearIDs(for: checklist, in: checklistGear)
        let packedCount = checkedIDs.count
        let totalCount = checklistGear.count
        let zoneGear = selectedZone.map { $0.gear(from: checklistGear) } ?? []
        let usage = activeChecklistUsage ?? .empty(for: checklist.id)

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            if !checklistGear.isEmpty {
                HStack(spacing: Spacing.md) {
                    summaryPill(value: "\(packedCount)/\(totalCount)", label: "Packed", accent: ColorTokens.primaryAccent)
                    summaryPill(value: "\(usage.skiDays)", label: "Ski days", accent: ColorTokens.primaryAccent)
                    summaryPill(value: usage.lastUsedDate?.relativeDisplay ?? "--", label: "Last used", accent: ColorTokens.primaryAccent)
                }
            }

            SkierFigureView(
                gear: checklistGear,
                checkedGearIDs: checkedIDs,
                selectedZone: selectedZone,
                onZoneTap: { handleZoneTap($0, in: checklistGear) }
            )
            .padding(.horizontal, Spacing.lg)

            if checklistGear.isEmpty {
                NavigationLink(destination: GearDetailView(setup: checklist)) {
                    Label(String(localized: "gear_choose_gear_from_locker"), systemImage: "bag.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ZoneStatusBar(
                    gear: checklistGear,
                    checkedGearIDs: checkedIDs,
                    selectedZone: selectedZone,
                    onZoneTap: { handleZoneTap($0, in: checklistGear) }
                )

                if !checkedIDs.isEmpty {
                    Button("Reset") {
                        resetChecklist(checklist)
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let selectedZone, !zoneGear.isEmpty {
                    GearZoneChecklistCard(
                        zone: selectedZone,
                        gear: zoneGear,
                        checkedGearIDs: checkedIDs,
                        onToggleGear: { item in
                            toggleChecklist(item, in: checklist)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(Spacing.xl)
        .dashboardCardBackground(accent: ColorTokens.primaryAccent)
    }

    private func recentSessionsSection(_ checklist: GearSetup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "gear_recent_sessions_section \(checklist.name)"))
                .font(.headline)

            VStack(spacing: Spacing.sm) {
                ForEach(Array(activeChecklistSessions.prefix(3))) { session in
                    NavigationLink(
                        destination: SessionSummaryView(
                            selectedSession: session,
                            showsDoneButton: false,
                            processesPersonalBests: false
                        )
                    ) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(session.startDate.shortDisplay)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(session.resort?.name ?? "Unknown resort")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !session.gearAssetDisplaySummary.isEmpty {
                                    Text(session.gearAssetDisplaySummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text("session_run_count_format \(session.runCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.xl)
        .dashboardCardBackground(accent: ColorTokens.primaryAccent)
    }

    private func summaryPill(value: String, label: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .dashboardGridCardBackground(accent: accent)
    }

    private func checklistStatusText(progress: Double, packedCount: Int, totalCount: Int) -> String {
        guard totalCount > 0 else {
            return String(localized: "gear_pull_gear_hint")
        }

        if progress >= 1 {
            return String(localized: "gear_progress_status_all_packed")
        }
        if progress >= 0.66 {
            return String(localized: "gear_progress_status_almost_there")
        }
        if packedCount > 0 {
            return String(localized: "gear_progress_status_getting_ready")
        }
        return String(localized: "gear_progress_status_not_started")
    }

    private func activate(_ checklist: GearSetup) {
        let selectedChecklistID = checklist.id
        for other in setups {
            other.isActive = (other.id == selectedChecklistID)
        }
    }

    private func gear(in checklist: GearSetup) -> [GearAsset] {
        GearLockerService.gear(in: checklist, from: lockerGear)
    }

    private func checkedGearIDs(for checklist: GearSetup, in checklistGear: [GearAsset]? = nil) -> Set<UUID> {
        let validGearIDs = Set((checklistGear ?? gear(in: checklist)).map(\.id))
        return GearChecklistStore.checkedGearIDs(for: checklist.id, in: settings).intersection(validGearIDs)
    }

    private func checklistProgress(for checklistGear: [GearAsset], checkedGearIDs: Set<UUID>) -> Double {
        guard !checklistGear.isEmpty else { return 0 }
        return Double(checkedGearIDs.count) / Double(checklistGear.count)
    }

    private func activeZones(for checklistGear: [GearAsset]) -> [BodyZone] {
        BodyZone.allCases.filter { !$0.gear(from: checklistGear).isEmpty }
    }

    private func toggleChecklist(_ item: GearAsset, in checklist: GearSetup) {
        guard let settings else { return }
        let checklistGear = gear(in: checklist)
        var checkedIDs = checkedGearIDs(for: checklist, in: checklistGear)
        if checkedIDs.contains(item.id) {
            checkedIDs.remove(item.id)
        } else {
            checkedIDs.insert(item.id)
        }
        GearChecklistStore.setCheckedGearIDs(checkedIDs, for: checklist.id, in: settings)
        try? modelContext.save()
        let zone = BodyZone.zone(for: item.category)
        if zone.isComplete(in: checklistGear, checkedGearIDs: checkedIDs) {
            advanceToNextIncompleteZone(after: zone, checklist: checklist, checklistGear: checklistGear, checkedGearIDs: checkedIDs)
        }
    }

    private func resetChecklist(_ checklist: GearSetup) {
        guard let settings else { return }
        GearChecklistStore.reset(for: checklist.id, in: settings)
        try? modelContext.save()
        resetZoneSelection()
    }

    private func advanceToNextIncompleteZone(
        after zone: BodyZone,
        checklist: GearSetup,
        checklistGear: [GearAsset],
        checkedGearIDs: Set<UUID>
    ) {
        let nextZone = activeZones(for: checklistGear)
            .filter { $0 != zone }
            .first { !$0.isComplete(in: checklistGear, checkedGearIDs: checkedGearIDs) }

        withAnimation(.easeInOut(duration: 0.25)) {
            selectedZone = nextZone ?? selectedZone
        }
    }

    private func handleZoneTap(_ zone: BodyZone, in checklistGear: [GearAsset]) {
        guard !zone.gear(from: checklistGear).isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedZone = selectedZone == zone ? nil : zone
        }
    }

    private func resetZoneSelection() {
        hasAutoSelectedZone = false
        selectedZone = nil
        autoSelectFirstZoneIfNeeded()
    }

    private func autoSelectFirstZoneIfNeeded() {
        guard !hasAutoSelectedZone, let activeChecklist else { return }

        let checklistGear = gear(in: activeChecklist)
        let zones = activeZones(for: checklistGear)
        guard !zones.isEmpty else { return }

        let checkedIDs = checkedGearIDs(for: activeChecklist, in: checklistGear)
        let firstIncomplete = zones.first { !$0.isComplete(in: checklistGear, checkedGearIDs: checkedIDs) }

        hasAutoSelectedZone = true
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedZone = firstIncomplete ?? zones.first
        }
    }

}

#Preview {
    @Previewable @State var container: ModelContainer = {
        let syncedSchema = Schema([
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
        ])
        let syncedConfig = ModelConfiguration(
            "Synced",
            schema: syncedSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let localSchema = Schema([DeviceSettings.self])
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let fullSchema = Schema([
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearAsset.self, GearMaintenanceEvent.self, UserProfile.self,
            DeviceSettings.self,
        ])
        let container = try! ModelContainer(for: fullSchema, configurations: syncedConfig, localConfig)
        let context = container.mainContext

        let checklist = GearSetup(name: "Storm Checklist", notes: "Cold-day shell + wider skis", isActive: true, sortOrder: 0)
        let spareChecklist = GearSetup(name: "Frontside Checklist", notes: "Fast carving days", isActive: false, sortOrder: 1)
        context.insert(checklist)
        context.insert(spareChecklist)

        let skis = GearAsset(name: "Bent 100", category: .skis, brand: "Atomic", model: "Bent 100", sortOrder: 0)
        let boots = GearAsset(name: "Hawk Prime", category: .boots, brand: "Atomic", model: "120 S", sortOrder: 1)
        let jacket = GearAsset(name: "Shell Jacket", category: .jacket, brand: "Norrøna", model: "Lofoten", sortOrder: 2)
        let goggles = GearAsset(name: "Line Miner", category: .goggles, brand: "Oakley", model: "XM", sortOrder: 3)
        skis.setupIDs = [checklist.id, spareChecklist.id]
        boots.setupIDs = [checklist.id]
        jacket.setupIDs = [checklist.id]
        goggles.setupIDs = [checklist.id, spareChecklist.id]
        context.insert(skis)
        context.insert(boots)
        context.insert(jacket)
        context.insert(goggles)

        let resort = Resort(name: "Are", latitude: 63.398, longitude: 13.082, country: "Sweden")
        context.insert(resort)

        let session = SkiSession(startDate: .now.addingTimeInterval(-86_400 * 3), endDate: .now.addingTimeInterval(-86_400 * 3 + 14_400), totalDistance: 18_500, totalVertical: 5_600, maxSpeed: 24, runCount: 9)
        session.resort = resort
        session.applyGearSnapshot(from: checklist, lockerAssets: [skis, boots, jacket, goggles])
        context.insert(session)

        return container
    }()

    GearListView(selectedPage: .constant(.checklist))
        .modelContainer(container)
}
