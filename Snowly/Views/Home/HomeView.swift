//
//  HomeView.swift
//  Snowly
//
//  Main home screen.
//  Background: dark-styled map of current location.
//  Layout: resort name + GPS status, music pill, temperature,
//  conditions label, concentric ring START button.
//

import SwiftUI
import SwiftData
import MapKit

struct HomeView: View {
    /// Incremented by MainTabView each time the Ride tab is tapped.
    /// Resets the internal page back to primary regardless of current sub-page.
    var resetTrigger: Int = 0

    private enum HomePage: Hashable {
        case primary  // Ride page
        case map      // Unified map page (trails + crew)
    }

    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(BatteryMonitorService.self) private var batteryService
    @Environment(LocationTrackingService.self) private var locationService
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    @Environment(SkiMapCacheService.self) private var skiMapService
    @Environment(CrewService.self) private var crewService
    @Environment(CrewPinNotificationService.self) private var pinNotificationService

    @Namespace private var mapScope

    @State private var weatherService = WeatherService()
    @State private var showingTracking = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var hasInitializedMapCamera = false
    @State private var lastSkiAreaLoadCoordinate: CLLocationCoordinate2D?
    @State private var currentPage: HomePage = .primary
    @State private var isPinningMode = false
    @State private var mapCenterCoordinate: CLLocationCoordinate2D?
    @State private var showCacheOfflineNotice = false
    @State private var cacheOfflineNoticeTask: Task<Void, Never>?
    @State private var mapOverlayActivationTask: Task<Void, Never>?
    @State private var cachedTrailLabels: [MapLabel] = []
    @State private var cachedLiftLabels: [MapLabel] = []
    @State private var showMapOverlays = false
    @State private var showCrewCreateAlert = false
    @State private var showCrewJoinAlert = false
    @State private var crewNameInput = ""
    @State private var crewJoinTokenInput = ""
    @State private var crewActionError: String?
    @State private var lastHomeDataRefreshAt: Date?
    @State private var showingGPSNotReadyAlert = false

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var hasActiveTrackingSession: Bool {
        trackingService.state != .idle && !showingTracking
    }

    private var trackingIntervalKey: String {
        let value = deviceSettings.first?.resolvedTrackingUpdateIntervalSeconds ?? 1.0
        return String(format: "%.1f", value)
    }

    var body: some View {
        mapBackground
            .overlay {
                if isPinningMode {
                    pinCrosshair
                }
            }
            .overlay(alignment: .bottom) {
                pageSwipePanel
            }
            .safeAreaInset(edge: .top, spacing: Spacing.md) {
                topBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
            }
            .overlay(alignment: .topLeading) {
                Group {
                    if currentPage == .map && crewService.activeCrew != nil && !isPinningMode {
                        CrewHeaderOverlay()
                            .padding(.leading, Spacing.lg)
                            .padding(.top, 80)
                            .frame(maxWidth: 260)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .animation(AnimationTokens.moderateEaseInOut, value: currentPage)
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if currentPage == .map {
                        mapTopControls
                            .padding(.trailing, Spacing.lg)
                            .padding(.top, 80)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .animation(AnimationTokens.moderateEaseInOut, value: currentPage)
            }
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if currentPage == .map && !isPinningMode {
                        VStack(spacing: Spacing.gutter) {
                            if crewService.activeCrew != nil {
                                CrewPinButton(action: { isPinningMode = true })
                            } else {
                                crewPlusButton
                            }
                            mapBottomLocationButton
                        }
                        .padding(.trailing, Spacing.lg)
                        .padding(.bottom, 80)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .animation(AnimationTokens.moderateEaseInOut, value: currentPage)
            }
            .overlay(alignment: .top) {
                if trackingService.didRecoverSession {
                    sessionRecoveredBanner
                        .padding(.top, 90)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(AnimationTokens.moderateEaseInOut, value: trackingService.didRecoverSession)
            .task(id: trackingService.didRecoverSession) {
                guard trackingService.didRecoverSession else { return }
                try? await Task.sleep(for: .seconds(4))
                trackingService.dismissRecoveryNotification()
            }
            .overlay(alignment: .top) {
                if let pin = pinNotificationService.currentBanner {
                    CrewPinBanner(pin: pin) {
                        withAnimation { pinNotificationService.dismissBanner() }
                    }
                    .padding(.top, 90)
                }
            }
            .overlay(alignment: .top) {
                if let event = pinNotificationService.currentMembershipBanner {
                    CrewMembershipBanner(event: event) {
                        withAnimation { pinNotificationService.dismissMembershipBanner() }
                    }
                    .padding(.top, 150)
                }
            }
            .animation(AnimationTokens.moderateEaseInOut, value: pinNotificationService.currentBanner?.id)
            .animation(AnimationTokens.moderateEaseInOut, value: pinNotificationService.currentMembershipBanner?.id)
            .animation(AnimationTokens.standardEaseInOut, value: isPinningMode)
            .onChange(of: currentPage) { _, newPage in
                isPinningMode = false
                mapOverlayActivationTask?.cancel()
                mapOverlayActivationTask = nil
                if newPage == .map {
                    // Defer overlay insertion until after page transition settles
                    mapOverlayActivationTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, currentPage == .map else { return }
                        showMapOverlays = true
                    }
                } else {
                    showMapOverlays = false
                }
            }
            .mapScope(mapScope)
            .fullScreenCover(isPresented: $showingTracking) {
                ActiveTrackingView()
                    .environment(trackingService)
                    .environment(batteryService)
                    .environment(skiMapService)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    trackingService.persistSnapshotNowIfNeeded()
                }
                trackingService.updateAppActiveState(scenePhase == .active)
            }
            .onAppear {
                trackingService.updateAppActiveState(scenePhase == .active)
                applyTrackingIntervalSettings()
                handleQuickStartIfPending()
                if locationService.authorizationStatus == .notDetermined {
                    locationService.requestAuthorization()
                }
            }
            .task(id: trackingIntervalKey) {
                applyTrackingIntervalSettings()
            }
            .onChange(of: trackingService.quickStartPending) {
                handleQuickStartIfPending()
            }
            .onChange(of: crewService.focusRequestedPin?.id) { _, _ in
                focusOnRequestedPinIfNeeded()
            }
            .onChange(of: resetTrigger) { _, _ in
                guard currentPage != .primary else { return }
                withAnimation(.easeInOut(duration: 0.2)) { currentPage = .primary }
            }
            .task(id: locationCoordinateKey) {
                guard let coord = locationService.currentLocation else { return }
                guard !showingTracking else { return }
                guard shouldRefreshHomeDataNow() else { return }

                // Only auto-center once to avoid resetting user camera interactions
                // (pitch / heading / rotation) on every location update.
                if !hasInitializedMapCamera {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        mapPosition = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        ))
                    }
                    hasInitializedMapCamera = true
                }

                await refreshHomeData(for: coord)
            }
            .onChange(of: locationService.authorizationStatus) { _, status in
                if status == .denied || status == .restricted {
                    hasInitializedMapCamera = false
                    lastSkiAreaLoadCoordinate = nil
                }
            }
            .onChange(of: skiMapService.currentSkiArea?.boundingBox) { _, _ in
                if let skiArea = skiMapService.currentSkiArea {
                    cachedTrailLabels = deduplicatedTrailLabels(from: skiArea.trails)
                    cachedLiftLabels = deduplicatedLiftLabels(from: skiArea.lifts)
                } else {
                    cachedTrailLabels = []
                    cachedLiftLabels = []
                }
            }
            .onChange(of: skiMapService.lastError) { _, newError in
                guard newError != nil else { return }
                presentCacheOfflineNoticeIfNeeded()
            }
            .onChange(of: skiMapService.currentSkiArea != nil) { _, hasCachedArea in
                guard hasCachedArea, skiMapService.lastError != nil else { return }
                presentCacheOfflineNoticeIfNeeded()
            }
            .onDisappear {
                cacheOfflineNoticeTask?.cancel()
                cacheOfflineNoticeTask = nil
                mapOverlayActivationTask?.cancel()
                mapOverlayActivationTask = nil
            }
            .alert(String(localized: "crew_create_title"), isPresented: $showCrewCreateAlert) {
                TextField(String(localized: "crew_name_placeholder"), text: $crewNameInput)
                Button(String(localized: "common_create")) { createCrew() }
                    .disabled(crewNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(String(localized: "common_cancel"), role: .cancel) { crewNameInput = "" }
            }
            .alert(String(localized: "crew_join_title"), isPresented: $showCrewJoinAlert) {
                TextField(String(localized: "crew_join_token_placeholder"), text: $crewJoinTokenInput)
                Button(String(localized: "crew_join_action")) { joinCrew() }
                    .disabled(crewJoinTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(String(localized: "common_cancel"), role: .cancel) { crewJoinTokenInput = "" }
            }
            .alert(String(localized: "gps_error_title"), isPresented: $showingGPSNotReadyAlert) {
                if locationService.authorizationStatus == .denied
                    || locationService.authorizationStatus == .restricted {
                    Button(String(localized: "common_open_settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button(String(localized: "common_ok"), role: .cancel) {}
            } message: {
                Text(gpsNotReadyAlertMessage)
            }
    }

    // MARK: - Page Picker

    private var pagePicker: some View {
        HStack(spacing: 0) {
            pagePickerButton(String(localized: "tab_ride"), systemImage: "play.fill", page: .primary)
            pagePickerButton(String(localized: "home_tab_trail_map"), systemImage: "map.fill", page: .map)
        }
        .padding(0)
        .frame(maxWidth: .infinity)
        .snowlyGlass(in: Capsule())
    }

    private func applyTrackingIntervalSettings() {
        let settings = deviceSettings.first
        trackingService.updateTrackingUpdateInterval(seconds: settings?.resolvedTrackingUpdateIntervalSeconds ?? 1.0)
    }

    private func pagePickerButton(
        _ title: String,
        systemImage: String,
        page: HomePage
    ) -> some View {
        let isSelected = currentPage == page
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentPage = page
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? ColorTokens.primaryAccent : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(ColorTokens.surfaceOverlay)
                            .overlay {
                                Capsule()
                                    .fill(ColorTokens.primaryAccent.opacity(Opacity.gentle))
                            }
                            .overlay {
                                Capsule()
                                    .stroke(ColorTokens.primaryAccent.opacity(Opacity.medium), lineWidth: 1)
                            }
                            .shadowStyle(.small)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        pagePicker
    }

    private var mapTopControls: some View {
        VStack(spacing: Spacing.sm) {
            MapPitchToggle(scope: mapScope)
            MapCompass(scope: mapScope)
        }
        .mapControlVisibility(.visible)
        .buttonBorderShape(.circle)
        .shadowStyle(.medium)
    }

    private var mapBottomLocationButton: some View {
        MapUserLocationButton(scope: mapScope)
            .mapControlVisibility(.visible)
            .buttonBorderShape(.circle)
            .shadowStyle(.medium)
    }

    private var crewPlusButton: some View {
        Menu {
            Button {
                showCrewCreateAlert = true
            } label: {
                Label(String(localized: "crew_create"), systemImage: "plus.circle")
            }
            Button {
                showCrewJoinAlert = true
            } label: {
                Label(String(localized: "crew_join"), systemImage: "link")
            }
        } label: {
            Image(systemName: "plus")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .snowlyGlass(in: Circle())
        }
        .shadowStyle(.medium)
    }

    // MARK: - Page Swipe Panel

    private var pageSwipePanel: some View {
        Group {
            if isPinningMode && currentPage == .map {
                CrewPinComposeBar(
                    coordinate: mapCenterCoordinate,
                    onDismiss: { isPinningMode = false }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            } else {
                TabView(selection: $currentPage) {
                    homePageContent
                        .tag(HomePage.primary)

                    mapPageContent
                        .tag(HomePage.map)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: currentPage == .primary ? .infinity : 200)
            }
        }
    }

    private var homePageContent: some View {
        VStack(spacing: 0) {
            // Resort name + GPS + Music (swipes away with Home page)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    resortTitleText

                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(gpsStatusColor)
                            .frame(width: Spacing.gutter, height: Spacing.gutter)

                        Text(gpsStatusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if shouldShowWeatherModule {
                        temperatureDisplay
                    }
                }

                Spacer()

                MusicPillButton()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.gutter)
            .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
            .padding(.top, Spacing.xl)
            .padding(.horizontal, Spacing.xl)

            Spacer(minLength: Spacing.xxl)

            primaryTrackingButton

            if ProcessInfo.processInfo.arguments.contains("-ui_testing") {
                Button {
                    trackingService.startTracking(unitSystem: unitSystem)
                    showingTracking = true
                } label: {
                    Text(String(localized: "home_ui_test_start"))
                }
                .accessibilityIdentifier("ui_start_tracking_button")
                .frame(width: 1, height: 1)
                .opacity(Opacity.invisible)
            }
        }
        .padding(.bottom, Spacing.section)
    }

    private var primaryTrackingButton: some View {
        Group {
            if hasActiveTrackingSession {
                ResumeTrackingButton {
                    showingTracking = true
                }
            } else {
                LongPressStartButton {
                    guard locationService.isGPSReadyForTracking else {
                        showingGPSNotReadyAlert = true
                        return
                    }
                    trackingService.startTracking(
                        healthKitEnabled: deviceSettings.first?.healthKitEnabled ?? false,
                        unitSystem: unitSystem
                    )
                    showingTracking = true
                }
            }
        }
    }

    private var mapPageContent: some View {
        VStack {
            Spacer()

            if showCacheOfflineNotice {
                HStack(alignment: .top, spacing: Spacing.gutter) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(String(localized: "cache_offline_notice"))
                            .font(.caption.weight(.semibold))
                        Text(String(localized: "cache_basemap_offline_hint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    Button {
                        dismissCacheOfflineNotice()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let error = crewService.lastError ?? crewActionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ColorTokens.error)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.gap)
                    .snowlyGlass(in: Capsule())
            }
        }
        .padding(.bottom, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .animation(AnimationTokens.fastEaseInOut, value: showCacheOfflineNotice)
    }

    // MARK: - Map Background

    private var mapBackground: some View {
        Map(position: $mapPosition, interactionModes: currentPage == .map ? .all : [], scope: mapScope) {
            UserAnnotation()

            // Crew member annotations
            if crewService.activeCrew != nil {
                ForEach(crewService.memberLocations) { member in
                    Annotation(
                        "",
                        coordinate: member.coordinate
                    ) {
                        CrewMemberAnnotation(member: member)
                    }
                }

                ForEach(crewService.activePins) { pin in
                    Annotation(
                        "",
                        coordinate: pin.coordinate
                    ) {
                        CrewPinAnnotation(
                            pin: pin,
                            onResend: crewService.canManagePin(pin) ? { resendPin(pin) } : nil,
                            onDelete: crewService.canManagePin(pin) ? { deletePin(pin) } : nil
                        )
                    }
                }
            }

            // Ski trail & lift overlays — only rendered on map page
            if showMapOverlays, let skiArea = skiMapService.currentSkiArea {
                // Draw all trail segments (polylines)
                ForEach(skiArea.trails) { trail in
                    MapPolyline(coordinates: trail.coordinates.map(\.clLocationCoordinate2D))
                        .stroke(
                            colorForDifficulty(trail.difficulty),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }

                // Deduplicated trail name labels (one per unique name)
                ForEach(cachedTrailLabels) { label in
                    Annotation("", coordinate: label.coordinate.clLocationCoordinate2D, anchor: .bottom) {
                        Text(label.name)
                            .font(Typography.caption2Semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                colorForDifficulty(label.difficulty).opacity(Opacity.heavy),
                                in: Capsule()
                            )
                    }
                }

                // Ski lift overlays
                ForEach(skiArea.lifts) { lift in
                    MapPolyline(coordinates: lift.coordinates.map(\.clLocationCoordinate2D))
                        .stroke(
                            Color.white.opacity(Opacity.heavy),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])
                        )
                }

                // Deduplicated lift name labels
                ForEach(cachedLiftLabels) { label in
                    Annotation("", coordinate: label.coordinate.clLocationCoordinate2D, anchor: .bottom) {
                        Text(label.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(Opacity.nearFull))
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .snowlyGlass(in: Capsule())
                    }
                }
            }
        }
        .onMapCameraChange { context in
            guard currentPage == .map else { return }
            mapCenterCoordinate = context.camera.centerCoordinate
        }
        .mapControls { }
        .mapStyle(.imagery(elevation: .realistic))
        .ignoresSafeArea()
    }

    private var pinCrosshair: some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: "mappin")
                .font(Typography.speedDisplay)
                .foregroundStyle(ColorTokens.warning)
            Circle()
                .fill(.black.opacity(Opacity.soft))
                .frame(width: Spacing.sm, height: Spacing.xs)
        }
        .shadowStyle(.subtle)
        .offset(y: -22)
        .allowsHitTesting(false)
    }

    private func handleQuickStartIfPending() {
        guard trackingService.quickStartPending,
              trackingService.state == .idle else { return }
        trackingService.quickStartPending = false
        guard locationService.isGPSReadyForTracking else {
            showingGPSNotReadyAlert = true
            return
        }
        trackingService.startTracking(
            healthKitEnabled: deviceSettings.first?.healthKitEnabled ?? false,
            unitSystem: unitSystem
        )
        showingTracking = true
    }

    private func presentCacheOfflineNoticeIfNeeded() {
        guard skiMapService.currentSkiArea != nil else { return }

        cacheOfflineNoticeTask?.cancel()
        withAnimation(AnimationTokens.fastEaseInOut) {
            showCacheOfflineNotice = true
        }

        cacheOfflineNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AnimationTokens.fastEaseInOut) {
                showCacheOfflineNotice = false
            }
        }
    }

    private func dismissCacheOfflineNotice() {
        cacheOfflineNoticeTask?.cancel()
        cacheOfflineNoticeTask = nil
        withAnimation(AnimationTokens.fastEaseInOut) {
            showCacheOfflineNotice = false
        }
    }

    // MARK: - Crew Actions

    private func focusOnRequestedPinIfNeeded() {
        guard let pin = crewService.focusRequestedPin else { return }
        withAnimation(AnimationTokens.slowEaseInOut) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: pin.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        }
        crewService.consumeFocusRequestedPin()
    }

    private func resendPin(_ pin: CrewPin) {
        Task {
            do {
                try await crewService.resendPin(pin)
                crewActionError = nil
            } catch {
                crewActionError = error.localizedDescription
            }
        }
    }

    private func deletePin(_ pin: CrewPin) {
        Task {
            do {
                try await crewService.deletePin(pin)
                crewActionError = nil
            } catch {
                crewActionError = error.localizedDescription
            }
        }
    }

    private func createCrew() {
        let name = crewNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await crewService.createCrew(name: name)
                crewNameInput = ""
                crewActionError = nil
            } catch {
                crewActionError = error.localizedDescription
            }
        }
    }

    private func joinCrew() {
        let inviteInput = crewJoinTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inviteInput.isEmpty else { return }
        Task {
            do {
                try await crewService.joinCrew(token: inviteInput)
                crewJoinTokenInput = ""
                crewActionError = nil
            } catch {
                crewActionError = error.localizedDescription
            }
        }
    }

    // MARK: - Trail Colors

    private func colorForDifficulty(_ difficulty: PisteDifficulty) -> Color {
        switch difficulty {
        case .novice:       ColorTokens.trailGreen
        case .easy:         ColorTokens.trailBlue
        case .intermediate: ColorTokens.trailRed
        case .advanced:     ColorTokens.trailBlack
        case .expert:       ColorTokens.trailOrange
        case .freeride:     ColorTokens.trailYellow
        case .unknown:      ColorTokens.trailUnknown
        }
    }

    // MARK: - Label Deduplication

    /// A single deduplicated label for a named trail or lift.
    private struct MapLabel: Identifiable {
        let id: String
        let name: String
        let coordinate: Coordinate
        let difficulty: PisteDifficulty
    }

    /// Groups trails by name; picks the best known difficulty and the midpoint
    /// of the longest segment for label placement.
    private func deduplicatedTrailLabels(from trails: [SkiTrail]) -> [MapLabel] {
        let grouped = Dictionary(grouping: trails.filter { $0.name != nil }, by: { $0.name! })
        return grouped.map { name, segments in
            // Prefer the most specific (non-unknown) difficulty
            let bestDifficulty = segments
                .map(\.difficulty)
                .first(where: { $0 != .unknown }) ?? .unknown
            // Place label at the midpoint of the longest segment
            let longest = segments.max(by: { $0.coordinates.count < $1.coordinates.count })!
            let midpoint = longest.coordinates.midElement ?? longest.coordinates[0]
            return MapLabel(id: "trail-\(name)", name: name, coordinate: midpoint, difficulty: bestDifficulty)
        }
    }

    /// Groups lifts by name; places label at the midpoint of the longest segment.
    private func deduplicatedLiftLabels(from lifts: [SkiLift]) -> [MapLabel] {
        let grouped = Dictionary(grouping: lifts.filter { $0.name != nil }, by: { $0.name! })
        return grouped.map { name, segments in
            let longest = segments.max(by: { $0.coordinates.count < $1.coordinates.count })!
            let midpoint = longest.coordinates.midElement ?? longest.coordinates[0]
            return MapLabel(id: "lift-\(name)", name: name, coordinate: midpoint, difficulty: .unknown)
        }
    }

    // MARK: - Weather Display

    private var temperatureDisplay: some View {
        HStack(spacing: Spacing.sm) {
            if let weather = weatherService.currentWeather {
                Image(systemName: weather.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(temperatureString(weather.temperature))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(weather.condition)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.tertiary)

                Label(windSpeedShort(weather.windSpeed), systemImage: "wind")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherAccessibilityLabel)
    }

    private var weatherAccessibilityLabel: String {
        guard let weather = weatherService.currentWeather else {
            return ""
        }
        return "\(temperatureString(weather.temperature)), \(weather.condition)"
    }

    private var shouldShowWeatherModule: Bool {
        weatherService.currentWeather != nil
    }

    // MARK: - Helpers

    private func refreshHomeData(for coordinate: CLLocationCoordinate2D) async {
        await weatherService.fetchWeather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        if shouldReloadSkiArea(for: coordinate) {
            await skiMapService.loadSkiArea(center: coordinate)
            lastSkiAreaLoadCoordinate = coordinate
        }

        await skiMapService.classifyCurrentPlace(at: coordinate)
        lastHomeDataRefreshAt = Date()
    }

    private func shouldRefreshHomeDataNow() -> Bool {
        if trackingService.state == .idle {
            return true
        }

        guard let lastRefresh = lastHomeDataRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefresh) >= 15 * 60
    }

    private func shouldReloadSkiArea(for coordinate: CLLocationCoordinate2D) -> Bool {
        guard skiMapService.currentSkiArea != nil,
              let lastSkiAreaLoadCoordinate else {
            return true
        }

        let last = CLLocation(
            latitude: lastSkiAreaLoadCoordinate.latitude,
            longitude: lastSkiAreaLoadCoordinate.longitude
        )
        let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return current.distance(from: last) >= SkiMapCacheService.defaultReclassifyDistanceMeters
    }

    @ViewBuilder
    private var resortTitleText: some View {
        Text(resortName)
            .font(Typography.primaryTitle)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var resortName: String {
        let title = skiMapService.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title != SkiMapCacheService.fallbackDisplayTitle else {
            return String(localized: "common_resort")
        }
        return title
    }

    /// Quantized to ~100m grid to avoid re-triggering .task on every GPS update.
    /// Each 0.001° of latitude ≈ 111m, so rounding to 3 decimal places
    /// prevents the task from restarting unless the user moves ~100m.
    private var locationCoordinateKey: String {
        guard let coord = locationService.currentLocation else { return "none" }
        let lat = (coord.latitude * 1000).rounded() / 1000
        let lon = (coord.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }

    private var gpsStatusColor: Color {
        if locationService.currentLocation != nil &&
            (locationService.authorizationStatus == .authorizedWhenInUse ||
             locationService.authorizationStatus == .authorizedAlways) {
            return ColorTokens.sensorGreen
        }
        return ColorTokens.sensorRed
    }

    private var gpsStatusText: String {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return locationService.currentLocation != nil
                ? String(localized: "home_gps_status_ready")
                : String(localized: "home_gps_status_locating")
        case .denied, .restricted:
            return String(localized: "home_gps_status_denied")
        default:
            return String(localized: "home_gps_status_pending")
        }
    }

    private var gpsNotReadyAlertMessage: String {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            return String(localized: "gps_error_not_authorized_message")
        default:
            return String(localized: "gps_error_no_fix_message")
        }
    }

    private func temperatureString(_ celsius: Double) -> String {
        let value: Int
        switch unitSystem {
        case .metric:
            value = Int(round(celsius))
        case .imperial:
            value = Int(round(celsius * 9.0 / 5.0 + 32))
        }
        return "\(value)\u{00B0}"
    }

    private func windSpeedShort(_ kmh: Double) -> String {
        switch unitSystem {
        case .metric:
            return "\(Int(round(kmh))) km/h"
        case .imperial:
            return "\(Int(round(kmh * 0.621371))) mph"
        }
    }

    private func weatherMetricText(
        text: String,
        systemImage: String
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(Typography.subheadlineMedium)
            .foregroundStyle(.secondary)
    }

    // MARK: - Session Recovery Banner

    private var sessionRecoveredBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(ColorTokens.info)
            Text(String(localized: "record.session_recovered_banner"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        .padding(.horizontal, Spacing.xl)
        .shadowStyle(.subtle)
    }
}

#Preview("Default") {
    let location = LocationTrackingService()
    let motion = MotionDetectionService()
    let battery = BatteryMonitorService()
    let healthKit = HealthKitService()
    let tracking = SessionTrackingService(
        locationService: location,
        motionService: motion,
        batteryService: battery,
        healthKitService: healthKit
    )
    let skiMap = SkiMapCacheService()
    let musicPlayer = MusicPlayerService()
    let crew = CrewService(apiClient: CrewAPIClient(), locationService: location)
    let pinNotification = CrewPinNotificationService()

    HomeView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(musicPlayer)
        .environment(crew)
        .environment(pinNotification)
        .modelContainer(for: UserProfile.self, inMemory: true)
}

#Preview("Ski Map Overlay") {
    let location = LocationTrackingService()
    let motion = MotionDetectionService()
    let battery = BatteryMonitorService()
    let healthKit = HealthKitService()
    let tracking = SessionTrackingService(
        locationService: location,
        motionService: motion,
        batteryService: battery,
        healthKitService: healthKit
    )
    let skiMap = SkiMapCacheService()
    let musicPlayer = MusicPlayerService()
    let crew = CrewService(apiClient: CrewAPIClient(), locationService: location)
    let pinNotification = CrewPinNotificationService()

    HomeView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(musicPlayer)
        .environment(crew)
        .environment(pinNotification)
        .modelContainer(for: UserProfile.self, inMemory: true)
}
