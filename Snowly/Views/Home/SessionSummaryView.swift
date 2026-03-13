//
//  SessionSummaryView.swift
//  Snowly
//
//  Post-session summary.
//  Compact ScrollView layout with route map, avatar, stats grid,
//  speed curve, per-run breakdown, and share button.
//

import SwiftUI
import SwiftData
import LinkPresentation

struct SessionSummaryView: View {
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \GearSetup.sortOrder) private var gearSetups: [GearSetup]
    @Query(sort: \GearAsset.sortOrder) private var gearAssets: [GearAsset]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SkiDataUploadService.self) private var uploadService

    let selectedSession: SkiSession?
    let showsDoneButton: Bool
    let processesPersonalBests: Bool
    let onDismiss: () -> Void

    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var personalBestRecords: [String] = []
    @State private var hasProcessedPersonalBests = false
    @State private var isGeneratingShare = false
    @State private var showUploadError = false
    @State private var showingNoteEditor = false
    @State private var noteTitleDraft = ""
    @State private var noteBodyDraft = ""
    @State private var isExportingData = false
    @State private var exportFileURL: URL?
    @State private var showingExportSheet = false
    @State private var exportErrorMessage: String?
    @State private var showingDeleteSessionAlert = false

    private var displayedSession: SkiSession? { selectedSession ?? sessions.first }

    private var profile: UserProfile? { profiles.first }

    private var hasAnyTrackDecodeError: Bool {
        displayedSession?.runs.contains(where: { $0.hasTrackDecodeError }) ?? false
    }

    private var unitSystem: UnitSystem {
        profile?.preferredUnits ?? .metric
    }

    init(
        selectedSession: SkiSession? = nil,
        showsDoneButton: Bool = true,
        processesPersonalBests: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.selectedSession = selectedSession
        self.showsDoneButton = showsDoneButton
        self.processesPersonalBests = processesPersonalBests
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = displayedSession {
                    GeometryReader { proxy in
                        if useLandscapeLayout(for: proxy.size) {
                            landscapeSummaryLayout(session: session, size: proxy.size)
                        } else {
                            portraitSummaryLayout(session: session)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "summary_empty_title"),
                        systemImage: "figure.skiing.downhill",
                        description: Text(String(localized: "summary_empty_description"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(String(localized: "summary_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "common_done"), action: onDismiss)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let session = displayedSession {
                        Button {
                            Task { await generateShareCard(session) }
                        } label: {
                            if uploadService.isUploading || isGeneratingShare {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(uploadService.isUploading || isGeneratingShare)
                        .accessibilityLabel(String(localized: "accessibility_share_summary_label"))
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = shareImage {
                    ShareSheet(
                        items: [ShareCardActivityItem(image: image, title: String(localized: "summary_share_title"))],
                        onUpload: { [displayedSession, profiles] in
                            guard let session = displayedSession,
                                  let profile = profiles.first else { return }
                            Task { @MainActor in
                                await uploadService.upload(
                                    session: session,
                                    userId: profile.id.uuidString,
                                    displayName: profile.displayName
                                )
                                if uploadService.lastError != nil {
                                    showUploadError = true
                                }
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert(String(localized: "settings_alert_export_failed_title"), isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        exportErrorMessage = nil
                    }
                }
            )) {
                Button(String(localized: "common_ok"), role: .cancel) {
                    exportErrorMessage = nil
                }
            } message: {
                Text(exportErrorMessage ?? String(localized: "settings_alert_export_unknown_error"))
            }
            .alert(String(localized: "session_detail_upload_failed_title"), isPresented: $showUploadError) {
                Button(String(localized: "common_ok"), role: .cancel) {}
            } message: {
                Text(uploadService.lastError ?? "")
            }
            .sheet(isPresented: $showingNoteEditor) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 0) {
                        // Context header
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "note.text")
                                    .font(Typography.iconBold)
                                    .foregroundStyle(ColorTokens.primaryAccent)
                                Text(String(localized: "note_editor_title"))
                                    .font(Typography.headingMedium)
                            }
                            if let session = displayedSession {
                                resortDateRow(session: session)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.xl)

                        Divider()

                        TextField(String(localized: "note_editor_title_placeholder"), text: $noteTitleDraft)
                            .font(Typography.primaryTitle)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.md)

                        Divider()

                        TextEditor(text: $noteBodyDraft)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .frame(minHeight: 140)

                        Spacer()
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(String(localized: "common_cancel")) {
                                showingNoteEditor = false
                            }
                            .foregroundStyle(.secondary)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "common_save")) {
                                saveSessionNote()
                                showingNoteEditor = false
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(ColorTokens.primaryAccent)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(String(localized: "session_recap_delete_confirm_title"), isPresented: $showingDeleteSessionAlert) {
                Button(String(localized: "common_cancel"), role: .cancel) {}
                Button(String(localized: "common_delete"), role: .destructive) {
                    deleteDisplayedSession()
                }
            } message: {
                Text(String(localized: "session_recap_delete_confirm_message"))
            }
        }
        .task(id: displayedSession?.id) {
            processPersonalBestsIfNeeded()
        }
    }

    private func saveSessionNote() {
        guard let session = displayedSession else { return }
        let title = noteTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = noteBodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        session.noteTitle = title.nonEmpty
        session.noteBody = body.nonEmpty
        // Keep legacy field populated for old read paths.
        session.note = body.nonEmpty ?? title.nonEmpty
        try? modelContext.save()
    }

    private func openNoteEditor(for session: SkiSession) {
        noteTitleDraft = session.effectiveNoteTitle
        noteBodyDraft = session.effectiveNoteBody
        showingNoteEditor = true
    }

    // MARK: - Layout Detection

    private func useLandscapeLayout(for size: CGSize) -> Bool {
        size.width > size.height
    }

    // MARK: - Portrait Layout

    private func portraitSummaryLayout(session: SkiSession) -> some View {
        ScrollView {
            VStack(spacing: Spacing.content) {
                // Route map (always visible)
                RouteMapView(session: session, height: 280)
                    .padding(.horizontal)

                // Avatar + user info
                userInfoSection(session: session)
                    .padding(.horizontal)

                // Hero duration
                heroDurationSection(session: session)

                // 2x2 stats grid
                statsGridSection(session: session)
                    .padding(.horizontal)

                gearSection(session: session)
                    .padding(.horizontal)

                // Track decode error notice
                if hasAnyTrackDecodeError {
                    trackDecodeErrorNotice
                        .padding(.horizontal)
                }

                // Personal best
                if !personalBestRecords.isEmpty {
                    personalBestsBanner(personalBestRecords)
                        .padding(.horizontal)
                }

                // Speed curve
                speedCurveSection(session: session)
                    .padding(.horizontal)

                liftBreakdownSection(session)
                    .padding(.horizontal)

                exportDataButton(session: session)
                    .padding(.horizontal)

                Color.clear.frame(height: Spacing.xxl)
            }
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Landscape Layout

    private func landscapeSummaryLayout(session: SkiSession, size: CGSize) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            landscapeMapColumn(session: session, size: size)
                .frame(width: max(280, size.width * 0.42))

            ScrollView {
                VStack(spacing: Spacing.content) {
                    userInfoSection(session: session)
                    heroDurationSection(session: session)
                    statsGridSection(session: session)
                    gearSection(session: session)

                    if hasAnyTrackDecodeError {
                        trackDecodeErrorNotice
                    }

                    if !personalBestRecords.isEmpty {
                        personalBestsBanner(personalBestRecords)
                    }

                    speedCurveSection(session: session)
                    liftBreakdownSection(session)
                    exportDataButton(session: session)
                    Color.clear.frame(height: Spacing.xxl)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func landscapeMapColumn(session: SkiSession, size: CGSize) -> some View {
        RouteMapView(session: session, height: max(240, size.height - Spacing.xl))
    }

    // MARK: - User Info

    private func userInfoSection(session: SkiSession) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            AvatarView(
                avatarData: profile?.avatarData,
                displayName: profile?.displayName ?? "",
                size: Spacing.section
            )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let name = profile?.displayName, !name.isEmpty {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
                resortDateRow(session: session)
            }

            Spacer(minLength: Spacing.sm)

            noteAccessory(for: session)
        }
    }

    private func resortDateRow(session: SkiSession) -> some View {
        HStack(spacing: Spacing.gap) {
            if let resort = session.resort {
                Text(resort.name)
                Text("\u{00B7}")
            }
            Text(session.startDate.longDisplay)
        }
        .font(Typography.subheadlineMedium)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func noteAccessory(for session: SkiSession) -> some View {
        let noteTitle = session.effectiveNoteTitle
        let noteBody = session.effectiveNoteBody

        if noteTitle.isEmpty && noteBody.isEmpty {
            Button {
                openNoteEditor(for: session)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(Typography.iconBold)
                    .foregroundStyle(ColorTokens.primaryAccent)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if !noteTitle.isEmpty {
                    Text(noteTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                if !noteBody.isEmpty {
                    Text(noteBody)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120)
            .onTapGesture {
                openNoteEditor(for: session)
            }
        }
    }

    // MARK: - Hero Duration

    private func heroDurationSection(session: SkiSession) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Rectangle()
                    .fill(.secondary.opacity(Opacity.moderate))
                    .frame(height: 1)
                Text(Formatters.duration(session.duration))
                    .font(Typography.metricSmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(.secondary.opacity(Opacity.moderate))
                    .frame(height: 1)
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    // MARK: - Stats Grid

    private func statsGridSection(session: SkiSession) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: Spacing.md),
            GridItem(.flexible(), spacing: Spacing.md),
        ]

        return LazyVGrid(columns: columns, spacing: Spacing.md) {
            statCard(
                value: Formatters.speedValue(session.maxSpeed, unit: unitSystem),
                unit: Formatters.speedUnit(unitSystem),
                label: String(localized: "stat_max_speed")
            )
            statCard(
                value: "\(session.runCount)",
                unit: "",
                label: String(localized: "common_runs")
            )
            statCard(
                value: Formatters.vertical(session.totalVertical, unit: unitSystem),
                unit: "",
                label: String(localized: "common_vertical")
            )
            statCard(
                value: Formatters.distance(session.totalDistance, unit: unitSystem),
                unit: "",
                label: String(localized: "common_distance")
            )
        }
    }

    private func statCard(value: String, unit: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(Typography.statValue)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.smallLabel)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
    }

    // MARK: - Gear

    @ViewBuilder
    private func gearSection(session: SkiSession) -> some View {
        if session.hasAttachedGearSetup || !gearSetups.isEmpty {
            let attachedChecklist = gearSetups.first { $0.id == session.gearSetupId }
            let derivedGearSummary = attachedChecklist.map { GearLockerService.coreGearSummary(for: $0, in: gearAssets) } ?? ""
            let assetSummary = session.gearAssetDisplaySummary.nonEmpty ?? derivedGearSummary.nonEmpty ?? ""

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("session_gear_section_label")
                            .font(Typography.subheadlineMedium)
                            .foregroundStyle(.secondary)
                        Text(session.hasAttachedGearSetup ? session.gearSetupDisplayName : String(localized: "session_no_checklist_attached"))
                            .font(.headline)
                        if !assetSummary.isEmpty {
                            Text(assetSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Menu {
                        Button(String(localized: "session_none_option")) {
                            session.clearGearSnapshot()
                            try? modelContext.save()
                        }
                        ForEach(gearSetups) { setup in
                            Button {
                                session.applyGearSnapshot(from: setup, lockerAssets: gearAssets)
                                try? modelContext.save()
                            } label: {
                                HStack {
                                    Text(setup.name)
                                    if session.gearSetupId == setup.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(String(localized: "session_change_checklist_button"), systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                    }
                }

                Text(session.hasAttachedGearSetup
                    ? String(localized: "session_gear_linked_description")
                    : String(localized: "session_gear_attach_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
        }
    }

    // MARK: - Personal Bests

    private func personalBestsBanner(_ records: [String]) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(ColorTokens.brandGold)
                Text(String(localized: "summary_new_personal_best_title"))
                    .font(.headline)
                    .foregroundStyle(ColorTokens.brandGold)
            }
            Text(records.joined(separator: ", "))
                .font(Typography.subheadlineMedium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(ColorTokens.brandGold.opacity(Opacity.subtle), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Speed Curve

    private func speedCurveSection(session: SkiSession) -> some View {
        let skiRuns = session.runs
            .filter { $0.activityType == .skiing }
            .sorted { $0.startDate < $1.startDate }
        let distributions = MockRunSpeedGenerator.distributions(from: skiRuns, unitSystem: unitSystem)
        let speedData = skiRuns.map { $0.maxSpeed }
        let maxSpeedDisplay: Double = {
            switch unitSystem {
            case .metric: return UnitConversion.metersPerSecondToKmh(speedData.max() ?? 0)
            case .imperial: return UnitConversion.metersPerSecondToMph(speedData.max() ?? 0)
            }
        }()

        return Group {
            if !distributions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "tracking_chart_speed_by_run"))
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(.secondary)

                    HalfViolinRunSpeedChart(
                        runs: distributions,
                        unitLabel: Formatters.speedUnit(unitSystem)
                    )
                }
                .padding()
                .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            } else if !speedData.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "tracking_chart_speed_by_run"))
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(.secondary)

                    SpeedCurveView(data: speedData, maxSpeedLabel: maxSpeedDisplay)
                        .frame(height: 120)
                }
                .padding()
                .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            }
        }
    }

    private func liftBreakdownSection(_ session: SkiSession) -> some View {
        let lifts = session.runs
            .filter { $0.activityType == .lift }
            .sorted { $0.startDate < $1.startDate }

        return Group {
            if !lifts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "session_detail_section_chairlift_rides"))
                        .font(Typography.subheadlineMedium)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(Array(lifts.enumerated()), id: \.element.id) { index, ride in
                            HStack {
                                Image(systemName: "cablecar.fill")
                                    .foregroundStyle(ColorTokens.info)
                                Text(Formatters.duration(ride.duration))
                                Spacer()
                                Text("+\(Formatters.vertical(ride.verticalDrop, unit: unitSystem))")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, Spacing.gap)

                            if index < lifts.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
                }
            }
        }
    }

    // MARK: - Export

    @ViewBuilder
    private func exportDataButton(session: SkiSession) -> some View {
        VStack(spacing: Spacing.sm) {
            Button {
                Task { await exportSessionData(session) }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isExportingData {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                    Text(isExportingData
                         ? String(localized: "session_export_data_exporting")
                         : String(localized: "session_export_data_button"))
                        .font(Typography.subheadlineMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .disabled(isExportingData)

            Button(role: .destructive) {
                showingDeleteSessionAlert = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trash")
                    Text(String(localized: "common_delete"))
                        .font(Typography.subheadlineMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .disabled(isGeneratingShare || isExportingData)
        }
    }

    /// Exports canonical session route points as JSON.
    ///
    /// Data-shape flow for export:
    /// ```mermaid
    /// graph LR
    /// P[Raw TrackPoint] --> Q[Kalman Filtered TrackPoint]
    /// Q --> R[Detection/State/Metrics]
    /// P --> S[NDJSON Segment File]
    /// S --> T[Materialized JSON]
    /// T --> U[SkiRun.trackData]
    /// U --> V[Exported GPS]
    /// ```
    ///
    /// Notes:
    /// - Detection/statistics consume filtered points.
    /// - Route storage is raw; export derives filtered GPS points on demand.
    @MainActor
    private func exportSessionData(_ session: SkiSession) async {
        guard !isExportingData else { return }
        isExportingData = true
        defer { isExportingData = false }

        let points: [FilteredTrackPoint] = session.runs
            .sorted { $0.startDate < $1.startDate }
            .flatMap(\.trackPoints)
            .sorted { $0.timestamp < $1.timestamp }

        guard !points.isEmpty else {
            exportErrorMessage = String(localized: "summary_no_route_map_title")
            return
        }

        let resortSlug = sanitizedFilenameComponent(session.resort?.name ?? "Snowly")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "\(resortSlug)_\(dateFormatter.string(from: session.startDate)).filtered-trackpoints.json"

        let fileURL: URL? = await Task.detached(priority: .userInitiated) {
            guard let data = try? JSONEncoder().encode(points) else { return nil }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }.value

        if let fileURL {
            exportFileURL = fileURL
            showingExportSheet = true
        } else {
            exportErrorMessage = String(localized: "settings_alert_export_unknown_error")
        }
    }

    private var trackDecodeErrorNotice: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(ColorTokens.warning)
            Text(String(localized: "session.track_decode_error_notice"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(Spacing.md)
        .background(ColorTokens.warning.opacity(Opacity.subtle), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "Snowly" : collapsed
    }

    private func generateShareCard(_ session: SkiSession) async {
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        // Extract all SwiftData model values BEFORE any async suspension
        // to avoid EXC_BAD_ACCESS from faulted model objects.
        let resortName = session.resort?.name
        let currentUnitSystem = unitSystem
        let currentAvatarData = profile?.avatarData
        let currentDisplayName = profile?.displayName ?? ""

        let renderedImage = await ShareCardRenderer.render(
            session: session,
            resortName: resortName,
            unitSystem: currentUnitSystem,
            avatarData: currentAvatarData,
            displayName: currentDisplayName
        )

        shareImage = renderedImage
        if renderedImage != nil {
            showingShareSheet = true
        }
    }

    private func deleteDisplayedSession() {
        guard let session = displayedSession else { return }
        modelContext.delete(session)
        try? modelContext.save()
        if selectedSession != nil {
            dismiss()
        } else {
            onDismiss()
        }
    }

    // MARK: - Personal Bests Processing

    private func processPersonalBestsIfNeeded() {
        guard processesPersonalBests else { return }
        guard !hasProcessedPersonalBests,
              let session = displayedSession,
              let profile = profiles.first else { return }

        let records = StatsService.checkPersonalBests(
            session: session,
            profile: profile
        )
        personalBestRecords = records

        if !records.isEmpty {
            let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)
            StatsService.applyPersonalBestUpdate(update, to: profile)
        }

        let seasonUpdate = StatsService.computeSeasonBestUpdates(session: session, profile: profile)
        if seasonUpdate.hasUpdates {
            StatsService.applySeasonBestUpdate(seasonUpdate, to: profile)
        }

        hasProcessedPersonalBests = true
    }
}

/// Provides the share card image as the thumbnail preview in UIActivityViewController.
final class ShareCardActivityItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        metadata.iconProvider = NSItemProvider(object: image)
        return metadata
    }
}

/// UIKit share sheet wrapper with card thumbnail preview.
/// Optionally includes an "Upload to Snowly" custom action.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onUpload: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var activities: [UIActivity] = []
        if let onUpload {
            activities.append(UploadToSnowlyActivity(handler: onUpload))
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: activities)
        controller.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .print,
        ]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Custom share sheet action that uploads the session to Snowly's server.
private final class UploadToSnowlyActivity: UIActivity {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.Snowly.uploadToSnowly")
    }

    override var activityTitle: String? {
        String(localized: "share_action_upload_to_snowly")
    }

    override var activityImage: UIImage? {
        UIImage(systemName: "icloud.and.arrow.up")
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        true
    }

    override func perform() {
        handler()
        activityDidFinish(true)
    }
}
