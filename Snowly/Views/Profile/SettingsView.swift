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
    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(HealthKitService.self) private var healthKitService
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]
    @Query(sort: \ServerProfile.createdAt) private var servers: [ServerProfile]

    @State private var showingDeleteConfirmation = false
    @State private var showingExportSuccess = false
    @State private var showingFileExporter = false
    @State private var showingCacheSheet = false
    @State private var exportDocument: JSONExportDocument?
    @State private var exportErrorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isResettingData = false
    @State private var profileNameDraft = ""

    private var profile: UserProfile? { profiles.first }
    private var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
    private let trackingIntervalOptions: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 30]

    var body: some View {
        Form {
            profileSection
            unitsSection
            syncSection
            if (deviceSettings.first?.healthKitEnabled ?? false) && !healthKitService.isAuthorized {
                healthKitUnauthorizedSection
            }
            liveActivitySection
            autoPauseSection
            serverSection
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    ColorTokens.groupedBackground,
                    ColorTokens.secondaryGroupedBackground
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
            applyTrackingIntervalIfNeeded()
            applyAutoPauseSettingIfNeeded()
            syncProfileNameDraft()
        }
        .onChange(of: profiles.count) { _, _ in
            guard !isResettingData else { return }
            ensureSettingsDataIfNeeded()
            syncProfileNameDraft()
        }
        .onChange(of: deviceSettings.count) { _, _ in
            guard !isResettingData else { return }
            ensureSettingsDataIfNeeded()
            applyTrackingIntervalIfNeeded()
        }
        .onChange(of: deviceSettings.first?.trackingUpdateIntervalSeconds) { _, _ in
            applyTrackingIntervalIfNeeded()
        }
        .onChange(of: deviceSettings.first?.autoPauseIdleSeconds) { _, _ in
            applyAutoPauseSettingIfNeeded()
        }
        .onDisappear {
            guard let profile else { return }
            commitProfileNameChanges(for: profile)
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
                            displayName: profile.resolvedDisplayName,
                            size: 72
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(Typography.settingsIcon)
                                .foregroundStyle(.white, ColorTokens.primaryAccent)
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
                    TextField(String(localized: "settings_profile_name_placeholder"), text: $profileNameDraft)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        commitProfileNameChanges(for: profile)
                    }
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

    private func syncProfileNameDraft() {
        guard let profile else {
            profileNameDraft = ""
            return
        }
        profile.ensureIdentityDefaults()
        profileNameDraft = profile.displayName
    }

    private func commitProfileNameChanges(for profile: UserProfile) {
        let trimmed = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = profile.resolvedDisplayName
        profile.updateDisplayName(trimmed)
        profileNameDraft = profile.displayName

        guard previous.caseInsensitiveCompare(profile.resolvedDisplayName) != .orderedSame else {
            return
        }

        Task { @MainActor in
            await syncUsernameToServers(for: profile)
        }
    }

    private func syncUsernameToServers(for profile: UserProfile) async {
        let registeredServers = servers.compactMap { server -> (URL, String, ServerCredential)? in
            guard let apiBaseURL = server.apiBaseURL else { return nil }
            let normalizedURL = ServerCredentialService.normalizeURL(server.urlString)
            guard let credential = ServerCredentialService.load(forServerURL: normalizedURL) else {
                return nil
            }
            return (apiBaseURL, normalizedURL, credential)
        }

        guard !registeredServers.isEmpty else {
            return
        }

        for (apiBaseURL, normalizedURL, credential) in registeredServers {
            do {
                try await updateUsername(
                    userId: profile.id.uuidString,
                    displayName: profile.resolvedDisplayName,
                    apiBaseURL: apiBaseURL,
                    normalizedServerURL: normalizedURL,
                    credential: credential
                )
            } catch {
                return
            }
        }
    }

    private func updateUsername(
        userId: String,
        displayName: String,
        apiBaseURL: URL,
        normalizedServerURL: String,
        credential: ServerCredential
    ) async throws {
        let client = SkiDataAPIClient(baseURL: apiBaseURL)
        client.setToken(credential.apiToken)

        do {
            let identity = try await client.updateProfile(userId: userId, displayName: displayName)
            try ServerCredentialService.update(username: identity.username, forServerURL: normalizedServerURL)
        } catch let error as SkiDataAPIError {
            guard case .unauthorized = error else {
                throw error
            }

            let refreshedToken = try await client.reauthenticate(
                userId: credential.userId,
                deviceSecret: credential.deviceSecret
            )
            try ServerCredentialService.update(apiToken: refreshedToken, forServerURL: normalizedServerURL)
            client.setToken(refreshedToken)
            let identity = try await client.updateProfile(userId: userId, displayName: displayName)
            try ServerCredentialService.update(
                apiToken: refreshedToken,
                username: identity.username,
                forServerURL: normalizedServerURL
            )
        }
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
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    Text(String(localized: "settings_sync_error_title"))
                        .font(Typography.subheadlineSemibold)
                        .foregroundStyle(ColorTokens.error)
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

    private var serverSection: some View {
        Section {
            NavigationLink(destination: ServerManagementView()) {
                Label(String(localized: "settings_server_management"), systemImage: "server.rack")
            }
        } header: {
            Label(String(localized: "settings_section_server"), systemImage: "network")
        } footer: {
            Text(String(localized: "settings_server_footer"))
        }
    }

    private var healthKitUnauthorizedSection: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "heart.slash")
                    .foregroundStyle(.red)
                Text(String(localized: "settings.healthkit_unauthorized_notice"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label(String(localized: "common_open_settings"), systemImage: "gear")
            }
        } header: {
            Label(String(localized: "settings_section_healthkit"), systemImage: "heart.fill")
        }
    }

    private var liveActivitySection: some View {
        Section {
            if let settings = deviceSettings.first {
                Picker(
                    String(localized: "settings_tracking_interval_label"),
                    selection: Binding(
                        get: { settings.resolvedTrackingUpdateIntervalSeconds },
                        set: { settings.trackingUpdateIntervalSeconds = $0 }
                    )
                ) {
                    ForEach(trackingIntervalOptions, id: \.self) { option in
                        Text(formattedTrackingInterval(option)).tag(option)
                    }
                }
            }
        } header: {
            Label(String(localized: "settings_tracking_interval_title"), systemImage: "location")
        } footer: {
            Text(String(localized: "settings_tracking_interval_footer"))
        }
    }

    private var autoPauseSection: some View {
        Section {
            if let settings = deviceSettings.first {
                Picker(
                    String(localized: "settings_auto_pause_label"),
                    selection: Binding(
                        get: { settings.resolvedAutoPause },
                        set: { settings.autoPauseIdleSeconds = $0.rawValue }
                    )
                ) {
                    ForEach(AutoPauseOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            }
        } header: {
            Label(String(localized: "settings_section_auto_pause"), systemImage: "pause.circle")
        } footer: {
            Text(String(localized: "settings_auto_pause_footer"))
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
            Link(destination: URL(string: "https://github.com/Motionly-labs/Snowly-ios")!) {
                Label(String(localized: "settings.about.feedback_button"), systemImage: "arrow.up.right.square")
                    .foregroundStyle(.primary)
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

    private func applyTrackingIntervalIfNeeded() {
        guard let settings = deviceSettings.first else { return }
        trackingService.updateTrackingUpdateInterval(seconds: settings.resolvedTrackingUpdateIntervalSeconds)
    }

    private func applyAutoPauseSettingIfNeeded() {
        guard let settings = deviceSettings.first else { return }
        trackingService.updateAutoPauseThreshold(seconds: TimeInterval(settings.resolvedAutoPause.rawValue))
    }

    private func formattedTrackingInterval(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return "\(Int(value.rounded()))s"
        }
        return String(format: "%.1fs", value)
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
            try modelContext.delete(model: GearMaintenanceEvent.self)
            try modelContext.delete(model: GearAsset.self)
            try modelContext.delete(model: GearSetup.self)
            try modelContext.delete(model: Resort.self)
            try modelContext.delete(model: UserProfile.self)
            try modelContext.delete(model: DeviceSettings.self)
            try modelContext.delete(model: ServerProfile.self)
            TrackingStatePersistence.clear()
            CrewKeychainService.delete()
            ServerCredentialService.deleteAll()
            UserIdentityKeychainService.delete()
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
        let gearAssets = try modelContext.fetch(
            FetchDescriptor<GearAsset>(sortBy: [SortDescriptor(\.createdAt)])
        )

        return ExportPayload(
            appVersion: appVersionDisplay,
            exportedAt: Date(),
            profiles: profiles.map(ProfileSnapshot.init),
            deviceSettings: deviceSettings.map(DeviceSettingsSnapshot.init),
            sessions: sessions.map(SessionSnapshot.init),
            resorts: resorts.map(ResortSnapshot.init),
            gearSetups: gearSetups.map { GearSetupSnapshot($0, assets: gearAssets) },
            gearAssets: gearAssets.map(GearAssetSnapshot.init)
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
            return ColorTokens.info
        }
        if syncMonitorService.syncError != nil {
            return ColorTokens.error
        }
        if syncMonitorService.lastSyncDate != nil {
            return ColorTokens.success
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
    let gearAssets: [GearAssetSnapshot]
}

private struct ProfileSnapshot: Codable {
    let id: UUID
    let displayName: String
    let preferredUnits: UnitSystem
    let personalBestMaxSpeed: Double
    let personalBestVertical: Double
    let personalBestDistance: Double
    let seasonBestMaxSpeed: Double
    let seasonBestVertical: Double
    let seasonBestDistance: Double
    let lastSeasonYear: String
    let dailyGoalMinutes: Double
    let createdAt: Date

    @MainActor init(_ profile: UserProfile) {
        id = profile.id
        displayName = profile.displayName
        preferredUnits = profile.preferredUnits
        personalBestMaxSpeed = profile.personalBestMaxSpeed
        personalBestVertical = profile.personalBestVertical
        personalBestDistance = profile.personalBestDistance
        seasonBestMaxSpeed = profile.seasonBestMaxSpeed
        seasonBestVertical = profile.seasonBestVertical
        seasonBestDistance = profile.seasonBestDistance
        lastSeasonYear = profile.lastSeasonYear
        dailyGoalMinutes = profile.dailyGoalMinutes
        createdAt = profile.createdAt
    }
}

private struct DeviceSettingsSnapshot: Codable {
    let id: UUID
    let healthKitEnabled: Bool
    let hasCompletedOnboarding: Bool
    let appearanceMode: String
    let trackingUpdateIntervalSeconds: Double
    let liveActivityRefreshActiveSeconds: Int
    let liveActivityRefreshInactiveSeconds: Int
    let liveActivityRefreshBackgroundSeconds: Int
    let autoPauseIdleSeconds: Int
    let createdAt: Date

    @MainActor init(_ settings: DeviceSettings) {
        id = settings.id
        healthKitEnabled = settings.healthKitEnabled
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        appearanceMode = settings.appearanceMode
        trackingUpdateIntervalSeconds = settings.trackingUpdateIntervalSeconds
        liveActivityRefreshActiveSeconds = settings.liveActivityRefreshActiveSeconds
        liveActivityRefreshInactiveSeconds = settings.liveActivityRefreshInactiveSeconds
        liveActivityRefreshBackgroundSeconds = settings.liveActivityRefreshBackgroundSeconds
        autoPauseIdleSeconds = settings.autoPauseIdleSeconds
        createdAt = settings.createdAt
    }
}

private struct SessionSnapshot: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let noteTitle: String?
    let noteBody: String?
    let note: String?
    let totalDistance: Double
    let totalVertical: Double
    let maxSpeed: Double
    let runCount: Int
    let healthKitWorkoutId: UUID?
    let resortId: UUID?
    let gearSetupId: UUID?
    let gearSetupSnapshotName: String?
    let gearAssetSnapshotSummary: String?
    let runs: [RunSnapshot]

    @MainActor init(_ session: SkiSession) {
        id = session.id
        startDate = session.startDate
        endDate = session.endDate
        noteTitle = session.noteTitle
        noteBody = session.noteBody
        note = session.note
        totalDistance = session.totalDistance
        totalVertical = session.totalVertical
        maxSpeed = session.maxSpeed
        runCount = session.runCount
        healthKitWorkoutId = session.healthKitWorkoutId
        resortId = session.resort?.id
        gearSetupId = session.gearSetupId
        gearSetupSnapshotName = session.gearSetupSnapshotName
        gearAssetSnapshotSummary = session.gearAssetSnapshotSummary
        runs = (session.runs ?? [])
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
    let trackPoints: [FilteredTrackPoint]

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
    let notes: String?
    let isActive: Bool
    let createdAt: Date
    let sortOrder: Int
    let assetIDs: [UUID]

    @MainActor init(_ setup: GearSetup, assets: [GearAsset]) {
        id = setup.id
        name = setup.name
        notes = setup.notes
        isActive = setup.isActive
        createdAt = setup.createdAt
        sortOrder = setup.sortOrder
        assetIDs = assets
            .filter { $0.setupIDs.contains(setup.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
    }
}

private struct GearAssetSnapshot: Codable {
    let id: UUID
    let name: String
    let category: GearAssetCategory
    let brand: String
    let model: String
    let notes: String?
    let acquiredAt: Date?
    let isArchived: Bool
    let dueRuleType: GearMaintenanceRuleType
    let dueEverySkiDays: Int?
    let dueDate: Date?
    let sortOrder: Int
    let setupIDs: [UUID]
    let maintenanceEvents: [GearMaintenanceEventSnapshot]

    @MainActor init(_ asset: GearAsset) {
        id = asset.id
        name = asset.name
        category = asset.category
        brand = asset.brand
        model = asset.model
        notes = asset.notes
        acquiredAt = asset.acquiredAt
        isArchived = asset.isArchived
        dueRuleType = asset.dueRuleType
        dueEverySkiDays = asset.dueEverySkiDays
        dueDate = asset.dueDate
        sortOrder = asset.sortOrder
        setupIDs = asset.setupIDs
        maintenanceEvents = (asset.maintenanceEvents ?? [])
            .sorted { $0.date > $1.date }
            .map(GearMaintenanceEventSnapshot.init)
    }
}

private struct GearMaintenanceEventSnapshot: Codable {
    let id: UUID
    let type: GearMaintenanceEventType
    let date: Date
    let notes: String?

    @MainActor init(_ event: GearMaintenanceEvent) {
        id = event.id
        type = event.type
        date = event.date
        notes = event.notes
    }
}
