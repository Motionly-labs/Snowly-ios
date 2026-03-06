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
    @State private var cachedTrailLabels: [MapLabel] = []
    @State private var cachedLiftLabels: [MapLabel] = []
    @State private var showCrewCreateAlert = false
    @State private var showCrewJoinAlert = false
    @State private var crewNameInput = ""
    @State private var crewJoinTokenInput = ""
    @State private var crewActionError: String?

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var hasActiveTrackingSession: Bool {
        trackingService.state != .idle && !showingTracking
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
            .safeAreaInset(edge: .top, spacing: 12) {
                topBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 8)
            }
            .overlay(alignment: .topLeading) {
                if currentPage == .map && crewService.activeCrew != nil && !isPinningMode {
                    CrewHeaderOverlay()
                        .padding(.leading, 16)
                        .padding(.top, 80)
                        .frame(maxWidth: 260)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if currentPage == .map {
                    mapTopControls
                        .padding(.trailing, 16)
                        .padding(.top, 80)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if currentPage == .map && !isPinningMode {
                    VStack(spacing: 10) {
                        if crewService.activeCrew != nil {
                            CrewPinButton(action: { isPinningMode = true })
                        } else {
                            crewPlusButton
                        }
                        mapBottomLocationButton
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 80)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
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
            .animation(.easeInOut(duration: 0.3), value: pinNotificationService.currentBanner?.id)
            .animation(.easeInOut(duration: 0.3), value: pinNotificationService.currentMembershipBanner?.id)
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .animation(.easeInOut(duration: 0.25), value: isPinningMode)
            .onChange(of: currentPage) { _, _ in
                isPinningMode = false
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
            }
            .onChange(of: crewService.focusRequestedPin?.id) { _, _ in
                focusOnRequestedPinIfNeeded()
            }
            .task(id: locationCoordinateKey) {
                guard let coord = locationService.currentLocation else { return }

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
    }

    // MARK: - Page Picker

    private var pagePicker: some View {
        HStack(spacing: 0) {
            pagePickerButton(String(localized: "tab_ride"), systemImage: "play.fill", page: .primary)
            pagePickerButton(String(localized: "home_tab_trail_map"), systemImage: "map.fill", page: .map)
        }
        .padding(0)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Capsule())
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
                .foregroundStyle(isSelected ? .accent : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule().fill(.background)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        pagePicker
    }

    private var mapTopControls: some View {
        VStack(spacing: 8) {
            MapPitchToggle(scope: mapScope)
            MapCompass(scope: mapScope)
        }
        .mapControlVisibility(.visible)
        .buttonBorderShape(.circle)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    private var mapBottomLocationButton: some View {
        MapUserLocationButton(scope: mapScope)
            .mapControlVisibility(.visible)
            .buttonBorderShape(.circle)
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
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
                .padding(.bottom, 24)
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
                VStack(alignment: .leading, spacing: 6) {
                    resortTitleText

                    HStack(spacing: 8) {
                        Circle()
                            .fill(gpsStatusColor)
                            .frame(width: 10, height: 10)

                        Text(gpsStatusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                MusicPillButton()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
            .padding(.top, 24)
            .padding(.horizontal, Spacing.xl)

            Spacer()

            if shouldShowWeatherModule {
                temperatureDisplay
                    .allowsHitTesting(false)
            }

            Spacer()

            primaryTrackingButton

            if ProcessInfo.processInfo.arguments.contains("-ui_testing") {
                Button {
                    trackingService.startTracking()
                    showingTracking = true
                } label: {
                    Text(String(localized: "home_ui_test_start"))
                }
                .accessibilityIdentifier("ui_start_tracking_button")
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
        .padding(.bottom, 48)
    }

    private var primaryTrackingButton: some View {
        Group {
            if hasActiveTrackingSession {
                ResumeTrackingButton {
                    showingTracking = true
                }
            } else {
                LongPressStartButton {
                    trackingService.startTracking(
                        healthKitEnabled: deviceSettings.first?.healthKitEnabled ?? false
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
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "cache_offline_notice"))
                            .font(.caption.weight(.semibold))
                        Text(String(localized: "cache_basemap_offline_hint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
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
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let error = crewService.lastError ?? crewActionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, 24)
        .padding(.horizontal, Spacing.lg)
        .animation(.easeInOut(duration: 0.22), value: showCacheOfflineNotice)
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

            // Ski trail overlays
            if let skiArea = skiMapService.currentSkiArea {
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
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                colorForDifficulty(label.difficulty).opacity(0.8),
                                in: Capsule()
                            )
                    }
                }

                // Ski lift overlays
                ForEach(skiArea.lifts) { lift in
                    MapPolyline(coordinates: lift.coordinates.map(\.clLocationCoordinate2D))
                        .stroke(
                            Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])
                        )
                }

                // Deduplicated lift name labels
                ForEach(cachedLiftLabels) { label in
                    Annotation("", coordinate: label.coordinate.clLocationCoordinate2D, anchor: .bottom) {
                        Text(label.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
        .onMapCameraChange { context in
            mapCenterCoordinate = context.camera.centerCoordinate
        }
        .mapControls { }
        .mapStyle(.imagery(elevation: .realistic))
        .ignoresSafeArea()
    }

    private var pinCrosshair: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.orange)
            Circle()
                .fill(.black.opacity(0.25))
                .frame(width: 8, height: 4)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .offset(y: -22)
        .allowsHitTesting(false)
    }

    private func presentCacheOfflineNoticeIfNeeded() {
        guard skiMapService.currentSkiArea != nil else { return }

        cacheOfflineNoticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            showCacheOfflineNotice = true
        }

        cacheOfflineNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                showCacheOfflineNotice = false
            }
        }
    }

    private func dismissCacheOfflineNotice() {
        cacheOfflineNoticeTask?.cancel()
        cacheOfflineNoticeTask = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            showCacheOfflineNotice = false
        }
    }

    // MARK: - Crew Actions

    private func focusOnRequestedPinIfNeeded() {
        guard let pin = crewService.focusRequestedPin else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
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

    private let trailGreen = Color(red: 0.2, green: 0.78, blue: 0.35)
    private let trailBlue = Color(red: 0.25, green: 0.52, blue: 0.96)
    private let trailRed = Color(red: 0.92, green: 0.26, blue: 0.24)
    private let trailBlack = Color(red: 0.35, green: 0.35, blue: 0.40)
    private let trailOrange = Color(red: 1.0, green: 0.6, blue: 0.15)
    private let trailYellow = Color(red: 0.95, green: 0.85, blue: 0.25)
    private let trailUnknown = Color.white.opacity(0.35)

    private func colorForDifficulty(_ difficulty: PisteDifficulty) -> Color {
        switch difficulty {
        case .novice:       trailGreen
        case .easy:         trailBlue
        case .intermediate: trailRed
        case .advanced:     trailBlack
        case .expert:       trailOrange
        case .freeride:     trailYellow
        case .unknown:      trailUnknown
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
        Group {
            if let weather = weatherService.currentWeather {
                VStack(spacing: 12) {
                    Text(temperatureString(weather.temperature))
                        .font(Typography.temperatureHero)
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Label(weather.condition, systemImage: weather.symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        weatherMetricText(
                            text: windSpeedShort(weather.windSpeed),
                            systemImage: "wind"
                        )
                        weatherMetricText(
                            text: "UV \(weather.uvIndex)",
                            systemImage: "sun.max"
                        )
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.content)
                .padding(.vertical, Spacing.lg)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.xLarge, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(weatherAccessibilityLabel)
            }
        }
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

    private var locationCoordinateKey: String {
        guard let coord = locationService.currentLocation else { return "none" }
        return "\(coord.latitude),\(coord.longitude)"
    }

    private var gpsStatusColor: Color {
        if locationService.currentLocation != nil &&
            (locationService.authorizationStatus == .authorizedWhenInUse ||
             locationService.authorizationStatus == .authorizedAlways) {
            return sensorGreen
        }
        return sensorRed
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
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var sensorRed: Color { ColorTokens.sensorRed }
    private var sensorGreen: Color { ColorTokens.sensorGreen }
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
        .task {
            skiMap.setPreviewData(SkiMapPreviewData.whistler)
        }
}
