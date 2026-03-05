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
        case primary
        case mapOnly
    }

    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(BatteryMonitorService.self) private var batteryService
    @Environment(LocationTrackingService.self) private var locationService
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    @Environment(SkiMapCacheService.self) private var skiMapService

    @Namespace private var mapScope

    @State private var weatherService = WeatherService()
    @State private var showingTracking = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var hasFetchedWeather = false
    @State private var hasFetchedSkiMap = false
    @State private var hasInitializedMapCamera = false
    @State private var currentPage: HomePage = .primary
    @State private var showCacheOfflineNotice = false
    @State private var cacheOfflineNoticeTask: Task<Void, Never>?
    @State private var cachedTrailLabels: [MapLabel] = []
    @State private var cachedLiftLabels: [MapLabel] = []

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var hasActiveTrackingSession: Bool {
        trackingService.state != .idle && !showingTracking
    }

    var body: some View {
        mapBackground
            .overlay(alignment: .bottom) {
                pageSwipePanel
            }
            .safeAreaInset(edge: .top, spacing: 12) {
                topBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 8)
            }
            .overlay(alignment: .topTrailing) {
                if currentPage == .mapOnly {
                    mapTopControls
                        .padding(.trailing, 16)
                        .padding(.top, 80)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if currentPage == .mapOnly {
                    mapBottomLocationButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 80)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .mapScope(mapScope)
            .fullScreenCover(isPresented: $showingTracking) {
                ActiveTrackingView()
                    .environment(trackingService)
                    .environment(batteryService)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    trackingService.persistSnapshotNowIfNeeded()
                }
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

                if !hasFetchedWeather {
                    await weatherService.fetchWeather(
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                    hasFetchedWeather = true
                }

                if !hasFetchedSkiMap {
                    await skiMapService.loadSkiArea(center: coord)
                    hasFetchedSkiMap = true
                }
            }
            .onChange(of: locationService.authorizationStatus) { _, status in
                if status == .denied || status == .restricted {
                    hasFetchedWeather = false
                    hasFetchedSkiMap = false
                    hasInitializedMapCamera = false
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
    }

    // MARK: - Page Picker

    private var pagePicker: some View {
        HStack(spacing: 0) {
            pagePickerButton(String(localized: "tab_ride"), systemImage: "play.fill", page: .primary)
            pagePickerButton(String(localized: "home_tab_trail_map"), systemImage: "map.fill", page: .mapOnly)
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

    // MARK: - Page Swipe Panel

    private var pageSwipePanel: some View {
        TabView(selection: $currentPage) {
            homePageContent
                .tag(HomePage.primary)

            mapPageContent
                .tag(HomePage.mapOnly)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: currentPage == .primary ? .infinity : 200)
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

            temperatureDisplay
                .allowsHitTesting(false)

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

            if skiMapService.currentSkiArea != nil {
                trailLegend
            }
        }
        .padding(.bottom, 24)
        .padding(.horizontal, Spacing.lg)
        .animation(.easeInOut(duration: 0.22), value: showCacheOfflineNotice)
    }

    // MARK: - Map Background

    private var mapBackground: some View {
        Map(position: $mapPosition, interactionModes: currentPage == .mapOnly ? .all : [], scope: mapScope) {
            UserAnnotation()

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
        .mapStyle(.imagery(elevation: .realistic))
        .ignoresSafeArea()
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

    private var trailLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: trailGreen, label: String(localized: "trail_difficulty_novice"))
            legendItem(color: trailBlue, label: String(localized: "trail_difficulty_easy"))
            legendItem(color: trailRed, label: String(localized: "trail_difficulty_intermediate"))
            legendItem(color: trailBlack, label: String(localized: "trail_difficulty_advanced"))
            legendItem(color: trailOrange, label: String(localized: "trail_difficulty_expert"))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white)
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
        VStack(spacing: 12) {
            if let weather = weatherService.currentWeather {
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
            } else {
                if shouldShowWeatherSpinner {
                    ProgressView()
                        .tint(.accentColor)
                        .scaleEffect(0.92)
                }

                Text(weatherStatusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.content)
        .padding(.vertical, Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.xLarge, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherAccessibilityLabel)
    }

    private var weatherAccessibilityLabel: String {
        guard let weather = weatherService.currentWeather else {
            return String(localized: "accessibility_weather_loading")
        }
        return "\(temperatureString(weather.temperature)), \(weather.condition)"
    }

    // MARK: - Helpers

    @ViewBuilder
    private var resortTitleText: some View {
        Text(resortName)
            .font(Typography.primaryTitle)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var resortName: String {
        guard let resort = skiMapService.currentSkiArea?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !resort.isEmpty else {
            return String(localized: "common_resort")
        }
        return resort
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

    private var weatherStatusText: String {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            return String(localized: "home_weather_status_location_required")
        case .notDetermined:
            return String(localized: "home_weather_status_allow_location_access")
        default:
            if weatherService.isLoading {
                return String(localized: "home_weather_status_updating")
            }
            if let error = weatherService.lastError, !error.isEmpty {
                return error
            }
            return String(localized: "home_weather_status_waiting_for_gps")
        }
    }

    private var shouldShowWeatherSpinner: Bool {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return weatherService.isLoading || weatherService.lastError == nil
        default:
            return false
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

    HomeView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(musicPlayer)
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

    HomeView()
        .environment(location)
        .environment(motion)
        .environment(battery)
        .environment(healthKit)
        .environment(tracking)
        .environment(skiMap)
        .environment(musicPlayer)
        .modelContainer(for: UserProfile.self, inMemory: true)
        .task {
            skiMap.setPreviewData(SkiMapPreviewData.whistler)
        }
}
