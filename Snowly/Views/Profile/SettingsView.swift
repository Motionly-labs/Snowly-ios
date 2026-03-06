//
//  SettingsView.swift
//  Snowly
//
//  App settings with dark theme design.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncMonitorService.self) private var syncMonitorService
    @Environment(SkiMapCacheService.self) private var skiMapService
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    @State private var showingDeleteConfirmation = false
    @State private var showingExportSuccess = false
    @State private var showingFileExporter = false
    @State private var showingCacheSheet = false
    @State private var exportDocument: JSONExportDocument?
    @State private var exportErrorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isResettingData = false

    private var profile: UserProfile? { profiles.first }
    private var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    var body: some View {
        Form {
            profileSection
            unitsSection
            syncSection
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(String(localized: "settings_nav_title"))
        .onAppear {
            guard !isResettingData else { return }
            ensureSettingsDataIfNeeded()
        }
        .onChange(of: profiles.count) { _, _ in
            guard !isResettingData else { return }
            ensureSettingsDataIfNeeded()
        }
        .onChange(of: deviceSettings.count) { _, _ in
            guard !isResettingData else { return }
            ensureSettingsDataIfNeeded()
        }
        .alert(String(localized: "settings_alert_delete_title"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "common_cancel"), role: .cancel) {}
            Button(String(localized: "settings_alert_delete_confirm"), role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text(String(localized: "settings_alert_delete_message"))
        }
        .alert(String(localized: "settings_alert_export_complete_title"), isPresented: $showingExportSuccess) {
            Button(String(localized: "common_ok")) {}
        } message: {
            Text(String(localized: "settings_alert_export_complete_message"))
        }
        .alert(String(localized: "settings_alert_export_failed_title"), isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue { exportErrorMessage = nil }
            }
        )) {
            Button(String(localized: "common_ok"), role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? String(localized: "settings_alert_export_unknown_error"))
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                showingExportSuccess = true
            case .failure(let error):
                exportErrorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingCacheSheet) {
            CachedAreasSheet()
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            if let profile {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        AvatarView(
                            avatarData: profile.avatarData,
                            displayName: profile.displayName,
                            size: 72
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .onChange(of: selectedPhoto) { _, newItem in
                    Task { await loadAvatar(from: newItem, into: profile) }
                }

                LabeledContent(String(localized: "settings_profile_name_label")) {
                    TextField(String(localized: "settings_profile_name_placeholder"), text: Binding(
                        get: { profile.displayName },
                        set: { profile.displayName = $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Label(String(localized: "settings_section_profile"), systemImage: "person.crop.circle")
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?, into profile: UserProfile) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let original = UIImage(data: data) else {
            return
        }
        profile.avatarData = compressAvatar(original)
    }

    private func compressAvatar(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 512
        let size = image.size
        let scale: CGFloat
        if max(size.width, size.height) > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    private var unitsSection: some View {
        Section {
            if let profile {
                Picker(String(localized: "settings_units_picker_title"), selection: Binding(
                    get: { profile.preferredUnits },
                    set: { profile.preferredUnits = $0 }
                )) {
                    Text(String(localized: "settings_units_metric")).tag(UnitSystem.metric)
                    Text(String(localized: "settings_units_imperial")).tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Label(String(localized: "settings_section_units"), systemImage: "ruler")
        }
    }

    private var syncSection: some View {
        Section {
            HStack {
                Label(String(localized: "settings_sync_status_label"), systemImage: syncStatusSymbol)
                Spacer()
                Text(syncStatusText)
                    .foregroundStyle(syncStatusColor)
            }

            if syncMonitorService.isSyncing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "settings_sync_in_progress"))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastSyncDate = syncMonitorService.lastSyncDate {
                HStack {
                    Text(String(localized: "settings_sync_last_sync_label"))
                    Spacer()
                    Text(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            if let syncError = syncMonitorService.syncError, !syncError.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "settings_sync_error_title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "settings_sync_retry_notice"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label(String(localized: "settings_sync_section_title"), systemImage: "icloud")
        } footer: {
            Text(String(localized: "settings_sync_footer"))
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                showingCacheSheet = true
            } label: {
                Label(String(localized: "cache_region_action"), systemImage: "square.and.arrow.down")
            }

            Button {
                exportData()
            } label: {
                Label(String(localized: "settings_data_export_json"), systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "settings_data_delete_all"), systemImage: "trash")
            }
        } header: {
            Label(String(localized: "settings_section_data"), systemImage: "externaldrive")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink(destination: PrivacyView()) {
                Text(String(localized: "settings_about_privacy_policy"))
            }
            LabeledContent(String(localized: "settings_about_app_version")) {
                Text(appVersionDisplay)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label(String(localized: "settings_section_about"), systemImage: "info.circle")
        }
    }

    // MARK: - Actions

    private func ensureSettingsDataIfNeeded() {
        guard !isResettingData else { return }

        if profiles.isEmpty {
            modelContext.insert(UserProfile(preferredUnits: defaultUnitSystem))
        }

        if deviceSettings.isEmpty {
            // User already reached settings, so keep onboarding as completed.
            modelContext.insert(DeviceSettings(hasCompletedOnboarding: true))
        } else if let settings = deviceSettings.first,
                  settings.appearanceMode != AppearanceMode.system.rawValue {
            // Appearance is now always system-driven.
            settings.appearanceMode = AppearanceMode.system.rawValue
        }
    }

    private func exportData() {
        do {
            let payload = try buildExportPayload()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            exportDocument = JSONExportDocument(data: data)
            showingFileExporter = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func deleteAllData() {
        isResettingData = true
        do {
            try modelContext.delete(model: SkiSession.self)
            try modelContext.delete(model: SkiRun.self)
            try modelContext.delete(model: GearSetup.self)
            try modelContext.delete(model: GearItem.self)
            try modelContext.delete(model: Resort.self)
            try modelContext.delete(model: UserProfile.self)
            try modelContext.delete(model: DeviceSettings.self)
            TrackingStatePersistence.clear()
            CrewKeychainService.delete()
            skiMapService.clearCache()
            try? modelContext.save()
        } catch {
            // Data deletion is best-effort
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private var exportFilename: String {
        "Snowly-Export-\(Self.exportDateFormatter.string(from: Date()))"
    }

    private func buildExportPayload() throws -> ExportPayload {
        let sessions = try modelContext.fetch(
            FetchDescriptor<SkiSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
        let resorts = try modelContext.fetch(
            FetchDescriptor<Resort>(sortBy: [SortDescriptor(\.name)])
        )
        let gearSetups = try modelContext.fetch(
            FetchDescriptor<GearSetup>(sortBy: [SortDescriptor(\.createdAt)])
        )

        return ExportPayload(
            appVersion: appVersionDisplay,
            exportedAt: Date(),
            profiles: profiles.map(ProfileSnapshot.init),
            deviceSettings: deviceSettings.map(DeviceSettingsSnapshot.init),
            sessions: sessions.map(SessionSnapshot.init),
            resorts: resorts.map(ResortSnapshot.init),
            gearSetups: gearSetups.map(GearSetupSnapshot.init)
        )
    }

    private var appVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var syncStatusText: String {
        if syncMonitorService.isSyncing {
            return String(localized: "settings_sync_status_syncing")
        }
        if syncMonitorService.syncError != nil {
            return String(localized: "settings_sync_status_needs_attention")
        }
        if syncMonitorService.lastSyncDate != nil {
            return String(localized: "settings_sync_status_up_to_date")
        }
        return String(localized: "settings_sync_status_not_synced")
    }

    private var syncStatusColor: Color {
        if syncMonitorService.isSyncing {
            return .blue
        }
        if syncMonitorService.syncError != nil {
            return .red
        }
        if syncMonitorService.lastSyncDate != nil {
            return .green
        }
        return .secondary
    }

    private var syncStatusSymbol: String {
        if syncMonitorService.isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        if syncMonitorService.syncError != nil {
            return "exclamationmark.icloud.fill"
        }
        if syncMonitorService.lastSyncDate != nil {
            return "icloud.fill"
        }
        return "icloud"
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ExportPayload: Codable {
    let appVersion: String
    let exportedAt: Date
    let profiles: [ProfileSnapshot]
    let deviceSettings: [DeviceSettingsSnapshot]
    let sessions: [SessionSnapshot]
    let resorts: [ResortSnapshot]
    let gearSetups: [GearSetupSnapshot]
}

private struct ProfileSnapshot: Codable {
    let id: UUID
    let displayName: String
    let preferredUnits: UnitSystem
    let seasonBestMaxSpeed: Double
    let seasonBestVertical: Double
    let seasonBestDistance: Double
    let seasonBestRunCount: Int
    let dailyGoalMinutes: Double
    let createdAt: Date

    @MainActor init(_ profile: UserProfile) {
        id = profile.id
        displayName = profile.displayName
        preferredUnits = profile.preferredUnits
        seasonBestMaxSpeed = profile.seasonBestMaxSpeed
        seasonBestVertical = profile.seasonBestVertical
        seasonBestDistance = profile.seasonBestDistance
        seasonBestRunCount = profile.seasonBestRunCount
        dailyGoalMinutes = profile.dailyGoalMinutes
        createdAt = profile.createdAt
    }
}

private struct DeviceSettingsSnapshot: Codable {
    let id: UUID
    let healthKitEnabled: Bool
    let hasCompletedOnboarding: Bool
    let appearanceMode: String
    let createdAt: Date

    @MainActor init(_ settings: DeviceSettings) {
        id = settings.id
        healthKitEnabled = settings.healthKitEnabled
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        appearanceMode = settings.appearanceMode
        createdAt = settings.createdAt
    }
}

private struct SessionSnapshot: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let totalDistance: Double
    let totalVertical: Double
    let maxSpeed: Double
    let runCount: Int
    let healthKitWorkoutId: UUID?
    let resortId: UUID?
    let runs: [RunSnapshot]

    @MainActor init(_ session: SkiSession) {
        id = session.id
        startDate = session.startDate
        endDate = session.endDate
        totalDistance = session.totalDistance
        totalVertical = session.totalVertical
        maxSpeed = session.maxSpeed
        runCount = session.runCount
        healthKitWorkoutId = session.healthKitWorkoutId
        resortId = session.resort?.id
        runs = session.runs
            .sorted { $0.startDate < $1.startDate }
            .map(RunSnapshot.init)
    }
}

private struct RunSnapshot: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let distance: Double
    let verticalDrop: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let activityType: RunActivityType
    let trackPoints: [TrackPoint]

    @MainActor init(_ run: SkiRun) {
        id = run.id
        startDate = run.startDate
        endDate = run.endDate
        distance = run.distance
        verticalDrop = run.verticalDrop
        maxSpeed = run.maxSpeed
        averageSpeed = run.averageSpeed
        activityType = run.activityType
        trackPoints = run.trackPoints
    }
}

private struct ResortSnapshot: Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String

    @MainActor init(_ resort: Resort) {
        id = resort.id
        name = resort.name
        latitude = resort.latitude
        longitude = resort.longitude
        country = resort.country
    }
}

private struct GearSetupSnapshot: Codable {
    let id: UUID
    let name: String
    let brand: String
    let model: String
    let isActive: Bool
    let createdAt: Date
    let sortOrder: Int
    let items: [GearItemSnapshot]

    @MainActor init(_ setup: GearSetup) {
        id = setup.id
        name = setup.name
        brand = setup.brand
        model = setup.model
        isActive = setup.isActive
        createdAt = setup.createdAt
        sortOrder = setup.sortOrder
        items = setup.items
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(GearItemSnapshot.init)
    }
}

private struct GearItemSnapshot: Codable {
    let id: UUID
    let name: String
    let category: GearCategory
    let isChecked: Bool
    let sortOrder: Int

    @MainActor init(_ item: GearItem) {
        id = item.id
        name = item.name
        category = item.category
        isChecked = item.isChecked
        sortOrder = item.sortOrder
    }
}
