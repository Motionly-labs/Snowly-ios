//
//  GearListView.swift
//  Snowly
//
//  Gear screen with interactive skier figure visualization.
//  Top-left: preset selector. Top-right: add custom item.
//  Body figure acts as the central checklist.
//

import SwiftUI
import SwiftData

struct GearListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearSetup.sortOrder) private var setups: [GearSetup]

    @State private var isEditing = false
    @State private var showingAddItem = false
    @State private var showingNewPreset = false
    @State private var showingResetConfirm = false
    @State private var selectedZone: BodyZone?
    @State private var hasAutoSelected = false

    private var activeSetup: GearSetup? {
        setups.first(where: \.isActive) ?? setups.first
    }

    /// Zones that have at least one item.
    private var activeZones: [BodyZone] {
        guard let setup = activeSetup else { return [] }
        return BodyZone.allCases.filter { !$0.items(from: setup).isEmpty }
    }

    private var overallProgress: Double {
        activeSetup?.progress ?? 0
    }

    private var statusText: String {
        if overallProgress >= 1.0 { return String(localized: "gear_status_ready_to_ride") }
        if overallProgress >= 0.5 { return String(localized: "gear_status_almost_there") }
        if overallProgress > 0 { return String(localized: "gear_status_getting_started") }
        return String(localized: "gear_status_lets_get_ready")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.content) {
                    // Header: preset picker + status
                    header
                        .padding(.horizontal, Spacing.xl)

                    // Skier figure
                    if let setup = activeSetup {
                        SkierFigureView(
                            setup: setup,
                            selectedZone: selectedZone,
                            onZoneTap: { zone in
                                withAnimation(AnimationTokens.moderateEaseInOut) {
                                    selectedZone = (selectedZone == zone) ? nil : zone
                                }
                            }
                        )
                        .padding(.horizontal, Spacing.xl)

                        // Zone status dots
                        ZoneStatusBar(
                            setup: setup,
                            selectedZone: selectedZone,
                            onZoneTap: { zone in
                                withAnimation(AnimationTokens.moderateEaseInOut) {
                                    selectedZone = (selectedZone == zone) ? nil : zone
                                }
                            }
                        )

                        // Selected zone detail card
                        if let zone = selectedZone, let setup = activeSetup {
                            let zoneItems = zone.items(from: setup)
                            GearCategoryRow(
                                zone: zone,
                                items: zoneItems,
                                isEditing: isEditing,
                                onToggleItem: { item in
                                    toggleItem(item, in: zone, setup: setup)
                                },
                                onAddItem: isEditing ? {
                                    showingAddItem = true
                                } : nil
                            )
                            .padding(.horizontal, Spacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Ready message when complete
                        if overallProgress >= 1.0 {
                            readyBanner
                                .padding(.horizontal, Spacing.xl)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.section)
            }
            .navigationTitle(String(localized: "gear_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(AnimationTokens.standardEaseInOut) {
                            isEditing.toggle()
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                if let setup = activeSetup {
                    GearItemEditView(
                        setup: setup,
                        mode: .add,
                        initialZone: selectedZone
                    )
                }
            }
            .sheet(isPresented: $showingNewPreset) {
                GearEditView(mode: .add)
            }
            .alert(String(localized: "gear_alert_reset_title"), isPresented: $showingResetConfirm) {
                Button(String(localized: "common_cancel"), role: .cancel) {}
                Button(String(localized: "gear_alert_reset_confirm"), role: .destructive) { resetChecklist() }
            } message: {
                Text(String(localized: "gear_alert_reset_message"))
            }
            .onAppear {
                ensureDefaultSetup()
                autoSelectFirstIncompleteZone()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Preset picker
            presetMenu

            Spacer()

            Text(statusText)
                .font(.caption.bold())
                .foregroundStyle(overallProgress >= 1.0 ? ColorTokens.success : Color.secondary)
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(setups) { setup in
                Button {
                    switchToSetup(setup)
                } label: {
                    HStack {
                        Text(setup.name)
                        if setup.id == activeSetup?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                showingNewPreset = true
            } label: {
                Label(String(localized: "gear_menu_new_preset"), systemImage: "plus")
            }

            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Label(String(localized: "gear_menu_reset_checklist"), systemImage: "arrow.counterclockwise")
            }
            .disabled(overallProgress == 0)
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(activeSetup?.name ?? String(localized: "gear_nav_title"))
                    .font(.title2.bold())

                if setups.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Ready Banner

    private var readyBanner: some View {
        HStack {
            Spacer()
            Label(String(localized: "gear_banner_ready_to_ride"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(ColorTokens.success)
            Spacer()
        }
        .padding(Spacing.lg)
        .background(ColorTokens.success.opacity(Opacity.subtle), in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    // MARK: - Actions

    private func ensureDefaultSetup() {
        let targetSetup: GearSetup

        if setups.isEmpty {
            let setup = GearSetup(name: String(localized: "gear_default_setup_name"), isActive: true)
            modelContext.insert(setup)
            targetSetup = setup
        } else if let existing = activeSetup, existing.items.isEmpty {
            // Setup exists but lost its items (e.g. schema change) — repopulate
            targetSetup = existing
        } else {
            return
        }

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

        for (index, (name, category)) in defaults.enumerated() {
            let item = GearItem(
                name: name,
                category: category,
                sortOrder: index,
                setup: targetSetup
            )
            modelContext.insert(item)
        }
    }

    private func resetChecklist() {
        guard let setup = activeSetup else { return }
        for item in setup.items {
            item.isChecked = false
        }
        // Re-select first zone
        hasAutoSelected = false
        selectedZone = nil
        autoSelectFirstIncompleteZone()
    }

    private func switchToSetup(_ setup: GearSetup) {
        // Deactivate all, activate selected
        for s in setups {
            s.isActive = (s.id == setup.id)
        }
        // Reset zone selection for new setup
        hasAutoSelected = false
        selectedZone = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            autoSelectFirstIncompleteZone()
        }
    }

    private func toggleItem(_ item: GearItem, in zone: BodyZone, setup: GearSetup) {
        item.isChecked.toggle()

        // Check if zone just became complete
        if zone.isComplete(from: setup) {
            advanceToNextIncompleteZone(after: zone, setup: setup)
        }
    }

    private func advanceToNextIncompleteZone(after zone: BodyZone, setup: GearSetup) {
        let nextIncomplete = activeZones
            .filter { $0 != zone }
            .first { !$0.isComplete(from: setup) }

        withAnimation(AnimationTokens.moderateEaseInOut) {
            selectedZone = nextIncomplete
        }
    }

    private func autoSelectFirstIncompleteZone() {
        guard !hasAutoSelected, let setup = activeSetup else { return }
        hasAutoSelected = true

        let firstIncomplete = activeZones.first { !$0.isComplete(from: setup) }
        withAnimation(AnimationTokens.moderateEaseInOut) {
            selectedZone = firstIncomplete ?? activeZones.first
        }
    }
}

#Preview {
    @Previewable @State var container: ModelContainer = {
        let syncedSchema = Schema([
            SkiSession.self, SkiRun.self, Resort.self,
            GearSetup.self, GearItem.self, UserProfile.self,
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
            GearSetup.self, GearItem.self, UserProfile.self,
            DeviceSettings.self,
        ])
        let container = try! ModelContainer(
            for: fullSchema,
            configurations: syncedConfig, localConfig
        )
        let context = container.mainContext

        let setup = GearSetup(name: "My Setup", isActive: true)
        context.insert(setup)

        let defaults: [(String, GearCategory)] = [
            ("Ski Jacket", .clothing),
            ("Ski Pants", .clothing),
            ("Base Layer Top", .clothing),
            ("Helmet", .protection),
            ("Goggles", .protection),
            ("Gloves", .accessories),
            ("Skis", .equipment),
            ("Poles", .equipment),
            ("Ski Boots", .footwear),
            ("Lift Pass", .accessories),
            ("Phone Charger", .electronics),
            ("Backpack", .backpack),
        ]

        for (index, (name, category)) in defaults.enumerated() {
            let item = GearItem(
                name: name,
                category: category,
                sortOrder: index,
                setup: setup
            )
            context.insert(item)
        }

        return container
    }()

    GearListView()
        .modelContainer(container)
}
