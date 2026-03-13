//
//  ActiveTrackingView.swift
//  Snowly
//
//  Tracking dashboard: hero peak speed, animated curve, session/runs tabs,
//  and fixed stop control.
//

import SwiftUI
import SwiftData
import CoreLocation

private enum TrackingDashboardTab: String, CaseIterable {
    case session
    case runs

    var title: String {
        switch self {
        case .session: return String(localized: "tracking_tab_ski_day")
        case .runs: return String(localized: "common_runs")
        }
    }
}

private struct TrackedRunSnapshot: Identifiable {
    let id: Int
    let maxSpeed: Double
    let vertical: Double
    let distance: Double
    let duration: Double
    let avgSpeed: Double
}

/// Live speed curve fed by append-only samples from `SessionTrackingService`.
/// Samples are already filtered upstream; the view keeps only immutable display points.
private struct LiveSpeedCurveView: View {
    private struct FrozenPoint: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let speed: Double
        let state: SpeedCurveState
    }

    @Environment(SessionTrackingService.self) private var trackingService
    let unitSystem: UnitSystem

    private static let maxPointCount = SharedConstants.speedCurveMaxPoints

    // CircularBuffer provides O(1) append and automatic oldest-drop with no array shifting.
    @State private var frozenPoints = CircularBuffer<FrozenPoint>(capacity: SharedConstants.speedCurveMaxPoints)
    @State private var lastProcessedSampleTime: Date?
    @State private var selectedPointTime: Date?
    // Cached to avoid O(N) max-scan inside body on every render.
    @State private var cachedMaxSpeedIndex: Int = 0

    private var chartMaxDisplaySpeed: Double {
        switch unitSystem {
        case .metric:   return 120 // km/h
        case .imperial: return 75  // mph
        }
    }

    private func speedValue(_ metersPerSecond: Double) -> Double {
        switch unitSystem {
        case .metric:   return UnitConversion.metersPerSecondToKmh(metersPerSecond)
        case .imperial: return UnitConversion.metersPerSecondToMph(metersPerSecond)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let graphHeight = max(44, geo.size.height - 18)

            if frozenPoints.isEmpty {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: graphHeight))
                    path.addLine(to: CGPoint(x: width, y: graphHeight))
                }
                .stroke(Color.secondary.opacity(Opacity.muted), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            } else {
                // Materialize once per render — all helpers share this array.
                let elements = frozenPoints.elements
                let coordinates = normalizedCoordinates(elements: elements, width: width, height: graphHeight)
                let maxIndex = cachedMaxSpeedIndex
                let selectionIndex = selectedIndex(in: elements)

                ZStack(alignment: .topLeading) {
                    CurveRendering.smoothFillPath(points: coordinates, baseline: graphHeight)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Canvas { context, _ in
                        drawSegments(
                            into: context,
                            elements: elements,
                            coordinates: coordinates,
                            showsLatestMarker: selectionIndex == nil
                        )
                    }

                    if let selectionIndex, selectionIndex < elements.count {
                        CurveSelectionOverlay(
                            point: coordinates[selectionIndex],
                            baseline: graphHeight,
                            label: selectionLabel(for: elements[selectionIndex]),
                            tint: color(for: elements[selectionIndex].state),
                            chartSize: CGSize(width: width, height: graphHeight)
                        )
                    } else if maxIndex < coordinates.count {
                        let marker = coordinates[maxIndex]
                        let markerColor = color(for: elements[maxIndex].state)
                        VStack(spacing: Spacing.xs) {
                            Text(String(format: "%.1f", elements[maxIndex].speed))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(markerColor)
                                .frame(width: 6, height: 6)
                        }
                        .position(x: marker.x, y: marker.y - 12)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        selectPoint(at: value.location.x, elements: elements, coordinates: coordinates)
                    }
                )
            }
        }
        .onAppear {
            rebuildFromCurrentSamples()
        }
        .onChange(of: trackingService.speedSamples) { _, latest in
            appendNewSamples(from: latest)
        }
    }

    private func rebuildFromCurrentSamples() {
        frozenPoints.removeAll()
        lastProcessedSampleTime = nil
        cachedMaxSpeedIndex = 0
        appendNewSamples(from: trackingService.speedSamples)
    }

    /// Append-only live pipeline:
    /// raw speed (already Kalman-estimated upstream) -> freeze display point.
    /// CircularBuffer auto-drops oldest on overflow — no Array.removeFirst() O(N) shift.
    private func appendNewSamples(from samples: [SpeedSample]) {
        guard !samples.isEmpty else {
            frozenPoints.removeAll()
            lastProcessedSampleTime = nil
            cachedMaxSpeedIndex = 0
            return
        }

        let fresh: [SpeedSample]
        if let lastProcessedSampleTime {
            fresh = samples.filter { $0.time > lastProcessedSampleTime }
        } else {
            fresh = samples
        }
        guard !fresh.isEmpty else { return }

        var updatedPoints = frozenPoints

        for sample in fresh {
            updatedPoints.append(
                FrozenPoint(
                    time: sample.time,
                    speed: speedValue(max(sample.speed, 0)),
                    state: sample.state
                )
            )
        }

        frozenPoints = updatedPoints
        lastProcessedSampleTime = fresh.last?.time

        let elements = updatedPoints.elements
        if let selectedPointTime, !elements.contains(where: { $0.time == selectedPointTime }) {
            self.selectedPointTime = nil
        }
        // Update cached max index so body doesn't scan O(N) on every render.
        cachedMaxSpeedIndex = elements.enumerated()
            .max(by: { $0.element.speed < $1.element.speed })?.offset ?? 0
    }

    private func normalizedCoordinates(elements: [FrozenPoint], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !elements.isEmpty else { return [] }
        guard let firstTime = elements.first?.time,
              let lastTime = elements.last?.time else { return [] }

        let timeSpan = lastTime.timeIntervalSince(firstTime)
        let usesIndexSpacing = timeSpan <= 0.001
        let fallbackStep = width / CGFloat(max(elements.count - 1, 1))

        return elements.enumerated().map { index, point in
            let x: CGFloat
            if usesIndexSpacing {
                x = CGFloat(index) * fallbackStep
            } else {
                let normalizedTime = point.time.timeIntervalSince(firstTime) / timeSpan
                x = width * CGFloat(normalizedTime)
            }
            let y = yCoordinate(for: point.speed, graphHeight: height)
            return CGPoint(x: x, y: y)
        }
    }

    private func yCoordinate(for displaySpeed: Double, graphHeight: CGFloat) -> CGFloat {
        let clamped = min(max(displaySpeed, 0), chartMaxDisplaySpeed)
        return graphHeight - CGFloat(clamped / chartMaxDisplaySpeed) * graphHeight * 0.85 - 4
    }

    private func color(for state: SpeedCurveState) -> Color {
        switch state {
        case .skiing: return ColorTokens.skiingAccent
        case .lift:   return ColorTokens.liftAccent
        case .others: return ColorTokens.walkAccent
        }
    }

    private func selectedIndex(in elements: [FrozenPoint]) -> Int? {
        guard let selectedPointTime else { return nil }
        return elements.firstIndex(where: { $0.time == selectedPointTime })
    }

    private func selectionLabel(for point: FrozenPoint) -> String {
        String(format: "%.1f %@", point.speed, Formatters.speedUnit(unitSystem))
    }

    private func selectPoint(at x: CGFloat, elements: [FrozenPoint], coordinates: [CGPoint]) {
        guard let index = CurveRendering.nearestPointIndex(to: x, in: coordinates) else { return }
        let tappedTime = elements[index].time
        selectedPointTime = selectedPointTime == tappedTime ? nil : tappedTime
    }

    private func drawSegments(
        into context: GraphicsContext,
        elements: [FrozenPoint],
        coordinates: [CGPoint],
        showsLatestMarker: Bool
    ) {
        guard coordinates.count >= 2 else {
            if let point = coordinates.first {
                let markerPath = Path(ellipseIn: CGRect(
                    x: point.x - 2.5,
                    y: point.y - 2.5,
                    width: 5,
                    height: 5
                ))
                context.fill(markerPath, with: .color(color(for: elements[0].state)))
            }
            return
        }

        // Batch contiguous same-state segments into one Path each.
        // Reduces O(N) Path allocations to O(S) where S = number of activity-state transitions.
        // After 10 min (300 pts) this cuts ~299 Paths → ~10-20, keeping renders well under 16 ms.
        let strokeStyle = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        var segStart = 1
        while segStart < coordinates.count {
            let segState = elements[segStart].state
            var j = segStart
            while j < coordinates.count && elements[j].state == segState {
                j += 1
            }
            let segPath = CurveRendering.smoothPath(points: Array(coordinates[(segStart - 1)..<j]))
            context.stroke(segPath, with: .color(color(for: segState)), style: strokeStyle)
            segStart = j
        }

        if showsLatestMarker, let end = coordinates.last, let last = elements.last {
            let markerPath = Path(ellipseIn: CGRect(
                x: end.x - 3,
                y: end.y - 3,
                width: 6,
                height: 6
            ))
            context.fill(markerPath, with: .color(color(for: last.state)))
        }
    }

}

struct ActiveTrackingView: View {
    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(LocationTrackingService.self) private var locationService
    @Environment(SkiMapCacheService.self) private var skiMapService
    @Environment(WatchBridgeService.self) private var watchBridgeService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @Query(sort: \DeviceSettings.createdAt) private var deviceSettings: [DeviceSettings]

    @State private var showingSummary = false
    @State private var showingLandscapeSettings = false
    @State private var activeTab: TrackingDashboardTab = .session
    @State private var selectedHeroInstanceId: UUID? = TrackingDashboardLayout.default.instances.first(where: { $0.slot == .hero })?.instanceId
    @State private var pulseRecording = false
    @State private var cardsAppeared = false
    @State private var cachedSkiRuns: [TrackedRunSnapshot] = []
    @State private var cachedMaxRunSpeed: Double = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var isEditingLayout = false
    @State private var dashboardLayout: TrackingDashboardLayout = .default

    private var deviceSettings_: DeviceSettings? { deviceSettings.first }

    private var heroInstances: [ActiveTrackingCardInstance] {
        // .profile is managed by the landscape overlay, not the portrait hero carousel.
        dashboardLayout.instances.filter { $0.slot == .hero && $0.kind != .profile }
    }

    private var gridInstances: [ActiveTrackingCardInstance] {
        dashboardLayout.instances.filter { $0.slot == .grid }
    }

    private var selectedHeroInstance: ActiveTrackingCardInstance? {
        guard let id = selectedHeroInstanceId else { return heroInstances.first }
        return heroInstances.first(where: { $0.instanceId == id }) ?? heroInstances.first
    }

    private var gridSnapshots: [UUID: ActiveTrackingCardSnapshot] {
        // Grid cards are scalar or text only — no series snapshots are built here.
        // Pass empty arrays for sample fields to avoid subscribing to large @Observable
        // arrays (altitudeSamples, speedSamples, heartRateSamples) that update at GPS/HR
        // frequency and would trigger extra body re-renders with no visual effect.
        let ctx = ActiveTrackingCardSnapshotAssembler.Context(
            unitSystem: unitSystem,
            skiingMetrics: trackingService.skiingMetrics,
            currentSpeed: trackingService.currentSpeed,
            completedRuns: trackingService.completedRuns,
            speedSamples: [],
            altitudeSamples: [],
            currentAltitudeMeters: trackingService.currentAltitude,
            elapsedSeconds: elapsedTime,
            currentHeartRate: watchBridgeService.currentHeartRate,
            averageHeartRate: watchBridgeService.averageHeartRate,
            heartRateSamples: []
        )
        return Dictionary(uniqueKeysWithValues: gridInstances.map { instance in
            (instance.instanceId, ActiveTrackingCardSnapshotAssembler.snapshot(for: instance, context: ctx))
        })
    }


    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var speedUnitLabel: String {
        Formatters.speedUnit(unitSystem)
    }

    private static func buildSkiRuns(from completedRuns: [CompletedRunData]) -> [TrackedRunSnapshot] {
        completedRuns
            .filter { $0.activityType == .skiing }
            .enumerated()
            .map { index, run in
                TrackedRunSnapshot(
                    id: index + 1,
                    maxSpeed: run.maxSpeed,
                    vertical: run.verticalDrop,
                    distance: run.distance,
                    duration: run.endDate.timeIntervalSince(run.startDate),
                    avgSpeed: run.averageSpeed
                )
            }
    }

    private var lastRun: TrackedRunSnapshot? {
        cachedSkiRuns.last
    }

    private var displayedPeakSpeed: Double {
        speedValue(lastRun?.maxSpeed ?? trackingService.skiingMetrics.maxSpeed)
    }

    private var displayedAvgSpeed: Double {
        if let run = lastRun {
            return speedValue(run.avgSpeed)
        }
        let totalDist = trackingService.skiingMetrics.totalDistance
        guard elapsedTime > 0 else { return 0 }
        return speedValue(totalDist / elapsedTime)
    }

    private var displayedCurrentSpeed: Double {
        speedValue(trackingService.currentSpeed)
    }

    private var currentSpeedSubtitle: String {
        switch trackingService.currentActivity {
        case .skiing:    return String(localized: "tracking_activity_skiing")
        case .lift:      return String(localized: "tracking_activity_lift")
        case .walk:      return String(localized: "tracking_activity_walk")
        case .idle:      return String(localized: "tracking_activity_idle")
        }
    }

    private var trackingStatusText: String {
        if trackingService.state == .paused {
            return String(localized: "tracking_state_paused")
        }
        return currentSpeedSubtitle
    }

    private var runCountValue: Double {
        Double(max(trackingService.skiingMetrics.runCount, cachedSkiRuns.count))
    }

    private var peakSpeedSubtitle: String {
        if let run = lastRun {
            let format = String(localized: "tracking_peak_subtitle_last_run_format")
            return String(
                format: format,
                locale: Locale.current,
                formatVertical(run.vertical),
                run.duration / 60
            )
        }
        let format = String(localized: "tracking_peak_subtitle_session_format")
        return String(
            format: format,
            locale: Locale.current,
            formatVertical(trackingService.skiingMetrics.totalVertical),
            elapsedMinutes
        )
    }

    private var avgSpeedSubtitle: String {
        if lastRun != nil {
            return String(localized: "tracking_avg_label_last_run")
        }
        return String(localized: "tracking_avg_label_session")
    }

    private var verticalSubtitle: String {
        let format = String(localized: "tracking_vertical_subtitle_format")
        return String(format: format, locale: Locale.current, Int64(runCountValue), elapsedMinutes)
    }

    private var bestSpeed: Double {
        max(cachedMaxRunSpeed, trackingService.skiingMetrics.maxSpeed)
    }

    private var totalVerticalValue: Double {
        switch unitSystem {
        case .metric: return trackingService.skiingMetrics.totalVertical
        case .imperial: return UnitConversion.metersToFeet(trackingService.skiingMetrics.totalVertical)
        }
    }

    private var totalVerticalUnit: String {
        Formatters.verticalUnit(unitSystem)
    }

    private var totalDistanceValue: Double {
        switch unitSystem {
        case .metric: return trackingService.skiingMetrics.totalDistance / 1000
        case .imperial: return trackingService.skiingMetrics.totalDistance / 1609.344
        }
    }

    private var totalDistanceUnit: String { Formatters.distanceUnit(unitSystem) }

    private var hiddenHeroKinds: [ActiveTrackingCardKind] {
        let presentKinds = Set(heroInstances.map(\.kind))
        return ActiveTrackingCardRegistry.allHeroKinds
            .filter { !presentKinds.contains($0) && $0 != .profile }
    }

    private var landscapeStatKinds: [ActiveTrackingCardKind] {
        let profileInstance = dashboardLayout.instances.first(where: { $0.kind == .profile })
        let raw = profileInstance?.config.profileStatKinds ?? Self.profileDefaultStatKinds
        return raw.compactMap { ActiveTrackingCardKind(rawValue: $0) }
    }

    private var elapsedTimeText: String {
        let total = Int(elapsedTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var profileAltitudeChangeValue: Double {
        let window = trackingService.altitudeSamples.suffix(SyncedActivityProfileView.preferredWindowCount)
        guard let first = window.first?.altitude, let last = window.last?.altitude else { return 0 }
        return last - first
    }

    private var profileAltitudeChangeText: String {
        String(format: "%+.0f %@", profileAltitudeChangeValue, totalVerticalUnit)
    }

    private var currentSpeedMetricText: String {
        String(format: "%.1f %@", displayedCurrentSpeed, speedUnitLabel)
    }

    private var currentHeartRateValue: Double {
        watchBridgeService.currentHeartRate
    }

    private var averageHeartRateValue: Double {
        watchBridgeService.averageHeartRate
    }

    private var currentHeartRateText: String {
        guard currentHeartRateValue > 0 else { return "--" }
        return "\(Int(currentHeartRateValue.rounded()))"
    }

    private var averageHeartRateText: String {
        guard averageHeartRateValue > 0 else { return "--" }
        return "\(Int(averageHeartRateValue.rounded()))"
    }

    private var activityStatusTint: Color {
        if trackingService.state == .paused {
            return ColorTokens.warning
        }

        switch trackingService.currentActivity {
        case .skiing:
            return ColorTokens.sportAccent
        case .lift:
            return Color.secondary
        case .walk, .idle:
            return Color.secondary
        }
    }

    private var heroCardAccent: Color {
        switch selectedHeroInstance?.kind {
        case .peakSpeed:
            return ColorTokens.sportAccent
        case .vertical:
            return ColorTokens.success
        case .heartRate, .heartRateCurve:
            return ColorTokens.brandRed
        default:
            return ColorTokens.sportAccent
        }
    }

    private var elapsedMinutes: Double {
        elapsedTime / 60
    }

    private func runTitleText(_ number: Int) -> String {
        let format = String(localized: "session_run_title_format")
        return String(format: format, locale: Locale.current, Int64(number))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topStatusBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        heroSection
                        if isEditingLayout {
                            heroEditorSection
                        }
                        tabSwitcher

                        Group {
                            if activeTab == .session {
                                sessionContent
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: Spacing.sm)),
                                        removal: .opacity.combined(with: .offset(y: -Spacing.sm))
                                    ))
                            } else {
                                runsContent
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: Spacing.sm)),
                                        removal: .opacity.combined(with: .offset(y: -Spacing.sm))
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 26)
                    .padding(.bottom, Spacing.xxl)
                }
            }

            // Landscape full-screen overlay — replaces portrait content visually.
            // Portrait content is always rendered underneath to keep timers and
            // state updates alive without needing a separate tracking path.
            if verticalSizeClass == .compact {
                landscapeDashboard
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(AnimationTokens.standardEaseInOut, value: verticalSizeClass)
            }
        }
        .sheet(isPresented: $showingLandscapeSettings) {
            landscapeSettingsSheet
        }
        .onAppear {
            pulseRecording = true
            trackingService.setTrackingDashboardVisible(true)
            rebuildCachedRuns()
            updateElapsedTime()
            if let settings = deviceSettings_ {
                dashboardLayout = settings.resolvedDashboardLayout
                selectedHeroInstanceId = dashboardLayout.instances.first(where: { $0.slot == .hero })?.instanceId
            }
            // Ensure the landscape .profile instance exists for config persistence.
            // Users upgrading from layouts that predate the landscape view won't
            // have this entry; add it silently on first open.
            if !dashboardLayout.instances.contains(where: { $0.kind == .profile }) {
                let profileInst = ActiveTrackingCardInstance.make(kind: .profile)
                dashboardLayout = TrackingDashboardLayout(instances: dashboardLayout.instances + [profileInst])
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                cardsAppeared = true
            }
        }
        .onChange(of: dashboardLayout) { _, _ in
            let validId = selectedHeroInstanceId.map { id in heroInstances.contains(where: { $0.instanceId == id }) } ?? false
            if !validId {
                selectedHeroInstanceId = heroInstances.first?.instanceId
            }
            saveLayout()
        }
        .onChange(of: verticalSizeClass) { _, newClass in
            // Exit portrait edit mode when rotating to landscape.
            if newClass == .compact, isEditingLayout {
                withAnimation(AnimationTokens.standardEaseInOut) { isEditingLayout = false }
            }
        }
        .onDisappear {
            trackingService.setTrackingDashboardVisible(false)
        }
        .onChange(of: trackingService.skiingMetrics.runCount) { _, _ in
            rebuildCachedRuns()
        }
        .task(id: trackingService.state) {
            guard trackingService.state != .idle else { return }
            while !Task.isCancelled {
                updateElapsedTime()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .fullScreenCover(isPresented: $showingSummary) {
            SessionSummaryView(onDismiss: {
                dismiss()
            })
        }
    }

    // MARK: - Top

    private var topStatusBar: some View {
        HStack {
            HStack(spacing: Spacing.gap) {
                Circle()
                    .fill(isEditingLayout ? ColorTokens.secondaryAccent : (trackingService.state == .paused ? ColorTokens.warning : ColorTokens.success))
                    .frame(width: Spacing.gap, height: Spacing.gap)
                    .scaleEffect(trackingService.state == .paused || isEditingLayout ? 1.0 : (pulseRecording ? 1 : 0.85))
                    .opacity(trackingService.state == .paused || isEditingLayout ? 0.7 : (pulseRecording ? 1 : Opacity.medium))
                    .animation(
                        trackingService.state == .paused || isEditingLayout
                            ? AnimationTokens.moderateEaseInOut
                            : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulseRecording
                    )
                    .animation(AnimationTokens.moderateEaseInOut, value: trackingService.state)
                    .animation(AnimationTokens.moderateEaseInOut, value: isEditingLayout)

                Text(isEditingLayout ? String(localized: "tracking_edit_mode_label") : trackingStatusText)
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(isEditingLayout ? ColorTokens.secondaryAccent : .secondary)
                    .textCase(.uppercase)
                    .animation(AnimationTokens.quickEaseOut, value: isEditingLayout)
            }

            Spacer()

            if isEditingLayout {
                Button {
                    withAnimation(AnimationTokens.standardEaseInOut) {
                        isEditingLayout = false
                    }
                } label: {
                    Text(String(localized: "common_done"))
                        .font(Typography.caption2Semibold)
                        .foregroundStyle(ColorTokens.secondaryAccent)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.gap)
                        .background(
                            ColorTokens.secondaryAccent.opacity(Opacity.subtle),
                            in: Capsule()
                        )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            } else {
                HStack(spacing: Spacing.xs) {
                    Button { togglePauseAction() } label: {
                        Image(systemName: trackingService.state == .paused ? "play.fill" : "pause.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(trackingService.state == .paused ? ColorTokens.warning : .secondary)
                            .frame(width: 36, height: 36)
                            .background { Circle().fill(.clear).glassEffect(.regular, in: .circle) }
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityIdentifier(
                        trackingService.state == .paused ? "resume_tracking_button" : "pause_tracking_button"
                    )

                    LongPressStopButton(onStop: endSession)
                        .accessibilityIdentifier("stop_tracking_button")

                    Button(action: minimizeTrackingDashboard) {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background { Circle().fill(.clear).glassEffect(.regular, in: .circle) }
                    }
                    .accessibilityIdentifier("minimize_tracking_button")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .animation(AnimationTokens.standardEaseInOut, value: isEditingLayout)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Spacing.sm) {
            TabView(selection: $selectedHeroInstanceId) {
                ForEach(heroInstances) { instance in
                    heroCardView(instance)
                        .tag(instance.instanceId as UUID?)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 188)
            .onLongPressGesture(minimumDuration: 0.5) {
                guard !isEditingLayout else { return }
                HapticFeedback.impact()
                withAnimation(AnimationTokens.standardEaseInOut) {
                    isEditingLayout = true
                }
            }

            if heroInstances.count > 1 {
                HStack(spacing: Spacing.sm) {
                    ForEach(heroInstances) { instance in
                        Capsule()
                            .fill(instance.instanceId == selectedHeroInstanceId ? heroCardAccent : Color.primary.opacity(0.12))
                            .frame(width: instance.instanceId == selectedHeroInstanceId ? 20 : 6, height: 6)
                    }
                }
                .animation(AnimationTokens.quickEaseOut, value: selectedHeroInstanceId)
            }
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .dashboardCardBackground(accent: heroCardAccent)
    }

    @ViewBuilder
    private func heroCardView(_ instance: ActiveTrackingCardInstance) -> some View {
        switch instance.kind {
        case .currentSpeed:
            heroMetricPage(
                label: String(localized: "stat_current_speed"),
                value: displayedCurrentSpeed,
                decimals: 1,
                suffix: speedUnitLabel,
                subtitle: ""
            )
        case .peakSpeed:
            heroMetricPage(
                label: String(localized: "stat_peak_speed"),
                value: displayedPeakSpeed,
                decimals: 1,
                suffix: speedUnitLabel,
                subtitle: peakSpeedSubtitle
            )
        case .avgSpeed:
            heroMetricPage(
                label: String(localized: "stat_avg_speed"),
                value: displayedAvgSpeed,
                decimals: 1,
                suffix: speedUnitLabel,
                subtitle: avgSpeedSubtitle
            )
        case .vertical:
            heroMetricPage(
                label: String(localized: "common_vertical"),
                value: totalVerticalValue,
                decimals: 0,
                suffix: totalVerticalUnit,
                subtitle: verticalSubtitle
            )
        case .heartRate:
            heroTextPage(
                label: String(localized: "stat_heart_rate"),
                value: currentHeartRateText,
                suffix: currentHeartRateValue > 0 ? String(localized: "stat_heart_rate_unit") : "",
                subtitle: averageHeartRateValue > 0
                    ? "\(String(localized: "tracking_hero_heart_rate_subtitle")) · \(averageHeartRateText) \(String(localized: "stat_heart_rate_unit"))"
                    : String(localized: "tracking_hero_heart_rate_subtitle")
            )
        case .profile:
            EmptyView() // shown in landscape overlay only
        case .speedCurve:
            heroSpeedCurvePage
        case .altitudeCurve:
            heroAltitudeCurvePage
        case .heartRateCurve:
            heroHeartRateCurvePage
        default:
            heroMetricPage(
                label: String(localized: "stat_current_speed"),
                value: displayedCurrentSpeed,
                decimals: 1,
                suffix: speedUnitLabel,
                subtitle: ""
            )
        }
    }

    private func heroMetricPage(
        label: String,
        value: Double,
        decimals: Int,
        suffix: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.caption2Semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            AnimatedNumberText(
                value: value,
                decimals: decimals,
                suffix: suffix,
                usesNumericTransition: false,
                animation: nil
            )
            .font(Typography.metricHero)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.64)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func heroTextPage(
        label: String,
        value: String,
        suffix: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.caption2Semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(Typography.metricHero.monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .baselineOffset(1)
                }
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func profileChipContent(for kind: ActiveTrackingCardKind) -> (icon: String, label: String, value: String, tint: Color) {
        switch kind {
        case .currentSpeed:
            return ("speedometer", String(localized: "stat_current_speed"), currentSpeedMetricText, ColorTokens.sportAccent)
        case .peakSpeed:
            return ("bolt.fill", String(localized: "stat_peak_speed"),
                    String(format: "%.1f %@", displayedPeakSpeed, speedUnitLabel), ColorTokens.sportAccent)
        case .avgSpeed:
            return ("gauge.with.dots.needle.33percent", String(localized: "stat_avg_speed"),
                    String(format: "%.1f %@", displayedAvgSpeed, speedUnitLabel), ColorTokens.sportAccent)
        case .vertical:
            return ("arrow.down", String(localized: "common_vertical"),
                    String(format: "%.0f %@", totalVerticalValue, totalVerticalUnit), activityStatusTint)
        case .distance:
            return ("point.topleft.down.to.point.bottomright.curvepath", String(localized: "common_distance"),
                    String(format: "%.2f %@", totalDistanceValue, totalDistanceUnit), ColorTokens.sportAccent)
        case .runCount:
            return ("number", String(localized: "common_runs"),
                    String(format: "%.0f", runCountValue), ColorTokens.success)
        case .heartRate:
            return ("heart.fill", String(localized: "stat_heart_rate"),
                    currentHeartRateText + " bpm", ColorTokens.brandRed)
        default:
            return ("circle", "", "", .secondary)
        }
    }

    private var heroSpeedCurvePage: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(String(localized: "stat_speed_curve"))
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(String(format: "%.1f %@", displayedCurrentSpeed, speedUnitLabel))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            LiveSpeedCurveView(unitSystem: unitSystem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heroAltitudeCurvePage: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(String(localized: "stat_altitude_curve"))
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(profileAltitudeChangeText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            AltitudeSparkline(samples: altitudeHeroSamples, unitLabel: totalVerticalUnit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var altitudeHeroSamples: [AltitudeSample] {
        let cutoff = Date.now.addingTimeInterval(-SharedConstants.altitudeSampleWindowSeconds)
        return trackingService.altitudeSamples.filter { $0.time >= cutoff }
    }

    private var heroHeartRateCurvePage: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "stat_heart_rate_curve"))
                        .font(Typography.caption2Semibold)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                        Text(currentHeartRateText)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        if currentHeartRateValue > 0 {
                            Text("stat_heart_rate_unit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if averageHeartRateValue > 0 {
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text(String(localized: "tracking_hero_heart_rate_subtitle"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(Int(averageHeartRateValue.rounded())) \(String(localized: "stat_heart_rate_unit"))")
                            .font(Typography.caption2Semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HeartRateCurveView(samples: heartRateHeroSamples)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heartRateHeroSamples: [HeartRateSample] {
        let cutoff = Date.now.addingTimeInterval(-SharedConstants.heartRateSampleWindowSeconds)
        return watchBridgeService.heartRateSamples.filter { $0.time >= cutoff }
    }

    // MARK: - Landscape Dashboard

    private var landscapeDashboard: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground).ignoresSafeArea()

            HStack(spacing: 0) {
                // Left panel: speed hero + configurable stat rows
                VStack(alignment: .leading, spacing: 0) {

                    // Recording status row
                    HStack(spacing: Spacing.gap) {
                        Circle()
                            .fill(trackingService.state == .paused ? ColorTokens.warning : ColorTokens.success)
                            .frame(width: Spacing.gap, height: Spacing.gap)
                        Text(elapsedTimeText)
                            .font(Typography.captionSemibold)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Hero speed
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(String(format: "%.1f", displayedCurrentSpeed))
                            .font(Typography.metricDisplay)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText(value: displayedCurrentSpeed))
                        Text(speedUnitLabel)
                            .font(Typography.title3Medium)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Configurable stat rows
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(landscapeStatKinds, id: \.rawValue) { kind in
                            landscapeStatRow(for: kind)
                        }
                    }

                    Spacer()

                    // Configure button
                    Button {
                        showingLandscapeSettings = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "slider.horizontal.3")
                            Text(String(localized: "tracking_overview_stats_label"))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.xl)
                .frame(width: Spacing.landscapeStatPanel)

                // Vertical divider
                Rectangle()
                    .fill(Color.primary.opacity(Opacity.hairline))
                    .frame(width: 1)
                    .padding(.vertical, Spacing.lg)

                // Right panel: speed curve full height
                LiveSpeedCurveView(unitSystem: unitSystem)
                    .padding(Spacing.xl)
            }

            // Controls — top-right corner
            HStack(spacing: Spacing.xs) {
                Button { togglePauseAction() } label: {
                    Image(systemName: trackingService.state == .paused ? "play.fill" : "pause.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(trackingService.state == .paused ? ColorTokens.warning : .secondary)
                        .frame(width: 36, height: 36)
                        .background { Circle().fill(.clear).glassEffect(.regular, in: .circle) }
                        .contentTransition(.symbolEffect(.replace))
                }

                LongPressStopButton(onStop: endSession)

                Button(action: minimizeTrackingDashboard) {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background { Circle().fill(.clear).glassEffect(.regular, in: .circle) }
                }
            }
            .padding(.top, Spacing.sm)
            .padding(.trailing, Spacing.xl)
        }
    }

    private func landscapeStatRow(for kind: ActiveTrackingCardKind) -> some View {
        let chip = profileChipContent(for: kind)
        return HStack(spacing: Spacing.sm) {
            Image(systemName: chip.icon)
                .font(Typography.captionSemibold)
                .foregroundStyle(chip.tint)
                .frame(width: Spacing.lg, alignment: .center)
            Text(chip.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(chip.value)
                .font(Typography.captionSemibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var landscapeSettingsSheet: some View {
        let availableKinds = Self.profileAvailableStatKinds
        let profileInstance = dashboardLayout.instances.first(where: { $0.kind == .profile })
        let selectedKinds = Set(profileInstance?.config.profileStatKinds ?? Self.profileDefaultStatKinds)
        return NavigationStack {
            List {
                ForEach(availableKinds, id: \.rawValue) { kind in
                    let def = ActiveTrackingCardRegistry.definition(for: kind)
                    let isOn = selectedKinds.contains(kind.rawValue)
                    Button {
                        if let inst = profileInstance {
                            toggleProfileStat(kind, in: inst)
                        }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: def.icon)
                                .font(.body)
                                .foregroundStyle(isOn ? ColorTokens.primaryAccent : .secondary)
                                .frame(width: Spacing.xl, alignment: .center)
                            Text(String(localized: String.LocalizationValue(def.titleKey)))
                                .foregroundStyle(.primary)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(Typography.captionSemibold)
                                    .foregroundStyle(ColorTokens.primaryAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "tracking_overview_stats_label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common_done")) {
                        showingLandscapeSettings = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var heroEditorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(String(localized: "tracking_hero_cards_title"))
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(String(localized: "tracking_hero_cards_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(heroInstances) { instance in
                        editableHeroCard(instance)
                    }
                }
            }

            if let selected = selectedHeroInstance, selected.kind == .profile {
                profileStatPickerSection(for: selected)
            }

            if !hiddenHeroKinds.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.gutter) {
                    ForEach(hiddenHeroKinds, id: \.rawValue) { kind in
                        hiddenHeroCardButton(kind)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .dashboardCardBackground(accent: heroCardAccent)
    }

    private func editableHeroCard(_ instance: ActiveTrackingCardInstance) -> some View {
        let def = ActiveTrackingCardRegistry.definition(for: instance.kind)
        let isFirst = heroInstances.first?.instanceId == instance.instanceId
        let isSelected = instance.instanceId == selectedHeroInstanceId
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: def.icon)
                    Text(String(localized: String.LocalizationValue(def.titleKey)))
                        .lineLimit(1)
                }
                .font(Typography.caption2Semibold)

                Spacer(minLength: Spacing.sm)

                if isFirst {
                    Text(String(localized: "tracking_hero_default_badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(heroCardAccent)
                } else if heroInstances.count > 1 {
                    Button {
                        withAnimation(AnimationTokens.standardEaseInOut) {
                            removeHeroCard(instance)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.body)
                            .foregroundStyle(ColorTokens.brandRed)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(heroCardDescription(instance.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !isFirst {
                Button {
                    withAnimation(AnimationTokens.standardEaseInOut) {
                        makeHeroCardDefault(instance)
                    }
                } label: {
                    Text(String(localized: "tracking_hero_make_default"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(heroCardAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(isSelected ? heroCardAccent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .strokeBorder(isSelected ? heroCardAccent.opacity(0.42) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onTapGesture {
            withAnimation(AnimationTokens.quickEaseOut) {
                selectedHeroInstanceId = instance.instanceId
            }
        }
    }

    private func hiddenHeroCardButton(_ kind: ActiveTrackingCardKind) -> some View {
        let def = ActiveTrackingCardRegistry.definition(for: kind)
        return Button {
            withAnimation(AnimationTokens.standardEaseInOut) {
                addHeroCard(kind)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.gutter) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: def.icon)
                    Text(String(localized: String.LocalizationValue(def.titleKey)))
                        .lineLimit(1)
                }
                .font(Typography.caption2Semibold)
                .foregroundStyle(.primary)

                Text(heroCardDescription(kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(heroCardAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(heroCardAccent.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func heroCardDescription(_ kind: ActiveTrackingCardKind) -> String {
        switch kind {
        case .currentSpeed:
            return String(localized: "tracking_hero_card_speed_description")
        case .peakSpeed:
            return String(localized: "tracking_hero_card_peak_description")
        case .avgSpeed:
            return String(localized: "tracking_hero_card_average_description")
        case .vertical:
            return String(localized: "tracking_hero_card_vertical_description")
        case .heartRate:
            return String(localized: "tracking_hero_card_heart_rate_description")
        case .profile:
            return String(localized: "tracking_hero_card_profile_description")
        case .speedCurve:
            return String(localized: "tracking_hero_card_speed_curve_description")
        case .altitudeCurve:
            return String(localized: "tracking_hero_card_altitude_curve_description")
        case .heartRateCurve:
            return String(localized: "tracking_hero_card_heart_rate_curve_description")
        default:
            return ""
        }
    }

    private func makeHeroCardDefault(_ instance: ActiveTrackingCardInstance) {
        guard let index = dashboardLayout.instances.firstIndex(where: { $0.instanceId == instance.instanceId }) else { return }
        selectedHeroInstanceId = instance.instanceId
        guard index != 0 else { return }
        var updated = dashboardLayout.instances
        updated.remove(at: index)
        updated.insert(instance, at: 0)
        dashboardLayout = TrackingDashboardLayout(instances: updated)
    }

    private func removeHeroCard(_ instance: ActiveTrackingCardInstance) {
        guard heroInstances.count > 1 else { return }
        dashboardLayout = TrackingDashboardLayout(
            instances: dashboardLayout.instances.filter { $0.instanceId != instance.instanceId }
        )
    }

    private func addHeroCard(_ kind: ActiveTrackingCardKind) {
        guard !heroInstances.contains(where: { $0.kind == kind }) else { return }
        let newInstance = ActiveTrackingCardInstance.make(kind: kind)
        var updated = dashboardLayout.instances
        updated.append(newInstance)
        dashboardLayout = TrackingDashboardLayout(instances: updated)
        selectedHeroInstanceId = newInstance.instanceId
    }

    private func togglePauseAction() {
        Task {
            if trackingService.state == .paused {
                await trackingService.resumeTracking(unitSystem: unitSystem)
            } else {
                await trackingService.pauseTracking()
            }
        }
    }

    private func toggleProfileStat(_ kind: ActiveTrackingCardKind, in instance: ActiveTrackingCardInstance) {
        guard let index = dashboardLayout.instances.firstIndex(where: { $0.instanceId == instance.instanceId }) else { return }
        let current = instance.config.profileStatKinds ?? Self.profileDefaultStatKinds
        let kindStr = kind.rawValue
        let newKinds = current.contains(kindStr)
            ? current.filter { $0 != kindStr }
            : current + [kindStr]
        var newInstances = dashboardLayout.instances
        newInstances[index].config.profileStatKinds = newKinds
        dashboardLayout = TrackingDashboardLayout(instances: newInstances)
    }

    private static let profileAvailableStatKinds: [ActiveTrackingCardKind] = [
        .currentSpeed, .peakSpeed, .avgSpeed, .vertical, .distance, .runCount, .heartRate
    ]

    private static let profileDefaultStatKinds: [String] =
        ActiveTrackingCardRegistry.definition(for: .profile).defaultConfig.profileStatKinds
        ?? ["currentSpeed", "vertical", "runCount"]

    private func profileStatPickerSection(for instance: ActiveTrackingCardInstance) -> some View {
        let availableKinds = Self.profileAvailableStatKinds
        let selectedKinds = Set(instance.config.profileStatKinds ?? Self.profileDefaultStatKinds)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "tracking_overview_stats_label"))
                .font(Typography.caption2Semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Spacing.xs
            ) {
                ForEach(availableKinds, id: \.rawValue) { kind in
                    let def = ActiveTrackingCardRegistry.definition(for: kind)
                    let isOn = selectedKinds.contains(kind.rawValue)
                    Button {
                        withAnimation(AnimationTokens.quickEaseOut) {
                            toggleProfileStat(kind, in: instance)
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? heroCardAccent : Color.secondary)
                            Text(String(localized: String.LocalizationValue(def.titleKey)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            isOn ? heroCardAccent.opacity(0.10) : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func heroMetricChip(
        icon: String,
        label: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }

    // MARK: - Tabs

    private var tabSwitcher: some View {
        SegmentedPicker(
            items: TrackingDashboardTab.allCases,
            selection: Binding(
                get: { activeTab },
                set: { newTab in
                    withAnimation(AnimationTokens.standardEaseInOut) {
                        activeTab = newTab
                    }
                }
            )
        ) { tab in
            Text(tab.title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.top, Spacing.xxs)
    }

    // MARK: - Session Tab

    private var sessionContent: some View {
        TrackingStatGrid(
            instances: gridInstances,
            snapshots: gridSnapshots,
            isEditing: isEditingLayout,
            cardsAppeared: cardsAppeared,
            onReorder: reorderWidgets,
            onRemove: removeWidget,
            onAdd: addWidget
        )
        .onLongPressGesture(minimumDuration: 0.5) {
            guard !isEditingLayout else { return }
            HapticFeedback.impact()
            withAnimation(AnimationTokens.standardEaseInOut) {
                isEditingLayout = true
            }
        }
    }

    private func removeWidget(_ instance: ActiveTrackingCardInstance) {
        guard gridInstances.count > 1 else { return }
        dashboardLayout = TrackingDashboardLayout(
            instances: dashboardLayout.instances.filter { $0.instanceId != instance.instanceId }
        )
    }

    private func reorderWidgets(_ reorderedGrid: [ActiveTrackingCardInstance]) {
        let heroes = dashboardLayout.instances.filter { $0.slot == .hero }
        dashboardLayout = TrackingDashboardLayout(instances: heroes + reorderedGrid)
    }

    private func addWidget(_ kind: ActiveTrackingCardKind) {
        guard !dashboardLayout.instances.contains(where: { $0.kind == kind }) else { return }
        let newInstance = ActiveTrackingCardInstance.make(kind: kind)
        var updated = dashboardLayout.instances
        updated.append(newInstance)
        dashboardLayout = TrackingDashboardLayout(instances: updated)
    }

    private func saveLayout() {
        deviceSettings_?.trackingDashboardLayoutJSON = dashboardLayout.encoded()
    }

    // MARK: - Runs Tab

    private var runsContent: some View {
        VStack(spacing: Spacing.gutter) {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "tracking_chart_speed_by_run"))
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                RunBarsView(values: runBarValues)

                HStack(spacing: 0) {
                    ForEach(runIndexLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.lg)
            .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.large))

            ForEach(Array(cachedSkiRuns.reversed())) { run in
                runCard(run)
            }
        }
    }

    private func runCard(_ run: TrackedRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(runTitleText(run.id))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if run.maxSpeed == cachedMaxRunSpeed && cachedSkiRuns.count > 1 {
                    Text(String(localized: "tracking_top_run_label"))
                        .font(Typography.caption2Semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                }
            }

            HStack(spacing: Spacing.sm) {
                runMetricColumn(
                    label: String(localized: "tracking_metric_peak"),
                    value: String(format: "%.1f", speedValue(run.maxSpeed)),
                    unit: speedUnitLabel
                )
                runMetricColumn(
                    label: String(localized: "common_vertical"),
                    value: String(format: "%.0f", verticalValue(run.vertical)),
                    unit: totalVerticalUnit
                )
                runMetricColumn(
                    label: String(localized: "common_duration"),
                    value: String(format: "%.1f", run.duration / 60),
                    unit: String(localized: "common_min_abbrev")
                )
            }
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    private func runMetricColumn(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var runBarValues: [Double] {
        let values = cachedSkiRuns.map { speedValue($0.maxSpeed) }
        return values.isEmpty ? [0, 0, 0, 0, 0] : values
    }

    private var runIndexLabels: [String] {
        if cachedSkiRuns.isEmpty {
            return ["1", "2", "3", "4", "5"]
        }
        return Array(1...cachedSkiRuns.count).map(String.init)
    }

    private func verticalValue(_ meters: Double) -> Double {
        switch unitSystem {
        case .metric: return meters
        case .imperial: return UnitConversion.metersToFeet(meters)
        }
    }

    private func speedValue(_ metersPerSecond: Double) -> Double {
        switch unitSystem {
        case .metric: return UnitConversion.metersPerSecondToKmh(metersPerSecond)
        case .imperial: return UnitConversion.metersPerSecondToMph(metersPerSecond)
        }
    }

    private func formatVertical(_ meters: Double) -> String {
        String(format: "%.0f%@", verticalValue(meters), totalVerticalUnit)
    }

    private func rebuildCachedRuns() {
        let runs = Self.buildSkiRuns(from: trackingService.completedRuns)
        cachedSkiRuns = runs
        cachedMaxRunSpeed = runs.map(\.maxSpeed).max() ?? 0
    }

    private func updateElapsedTime() {
        guard let start = trackingService.startDate else {
            elapsedTime = 0
            return
        }
        let pausedNow = trackingService.pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
        elapsedTime = max(0, Date().timeIntervalSince(start) - trackingService.totalPausedTime - pausedNow)
    }

    private func endSession() {
        Task {
            await trackingService.stopTracking()
            await trackingService.finalizeHealthKitWorkout()
            let resortCoordinate = locationService.currentLocation
                ?? locationService.recentTrackPointsSnapshot().last.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            let resort = await ResortResolver.resolveCurrentResort(
                from: skiMapService,
                using: resortCoordinate,
                in: modelContext
            )
            await trackingService.saveSession(to: modelContext, resort: resort)
            showingSummary = true
        }
    }

    private func minimizeTrackingDashboard() {
        trackingService.setTrackingDashboardVisible(false)
        trackingService.persistSnapshotNowIfNeeded()
        dismiss()
    }
}

// MARK: - Heart Rate Curve

private struct HeartRateCurveView: View {
    let samples: [HeartRateSample]

    @State private var selectedSampleTime: Date?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            if samples.count < 2 {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                }
                .stroke(
                    Color.secondary.opacity(Opacity.muted),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            } else {
                let pts = computePoints(size: size)
                let selectionIndex = selectedIndex
                ZStack {
                    CurveRendering.smoothFillPath(points: pts, baseline: size.height)
                        .fill(LinearGradient(
                            colors: [ColorTokens.brandRed.opacity(0.18), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    Canvas { context, _ in
                        drawCurve(into: context, pts: pts)
                    }

                    if let selectionIndex, selectionIndex < pts.count {
                        CurveSelectionOverlay(
                            point: pts[selectionIndex],
                            baseline: size.height,
                            label: selectionLabel(for: samples[selectionIndex]),
                            tint: ColorTokens.brandRed,
                            chartSize: size
                        )
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        selectPoint(at: value.location.x, points: pts)
                    }
                )
            }
        }
        .onChange(of: samples.map(\.time)) { _, latestTimes in
            guard let selectedSampleTime else { return }
            if !latestTimes.contains(selectedSampleTime) {
                self.selectedSampleTime = nil
            }
        }
    }

    private func computePoints(size: CGSize) -> [CGPoint] {
        let values = samples.map(\.bpm)
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range = max(maxVal - minVal, 20)

        return samples.enumerated().map { idx, sample in
            let x = size.width * CGFloat(idx) / CGFloat(samples.count - 1)
            let normalised = (sample.bpm - minVal) / range
            let y = size.height * (1.0 - CGFloat(normalised)) * 0.85 + 4
            return CGPoint(x: x, y: y)
        }
    }

    private var selectedIndex: Int? {
        guard let selectedSampleTime else { return nil }
        return samples.firstIndex(where: { $0.time == selectedSampleTime })
    }

    private func drawCurve(into context: GraphicsContext, pts: [CGPoint]) {
        guard pts.count >= 2 else { return }
        let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        let path = CurveRendering.smoothPath(points: pts)
        context.stroke(path, with: .color(ColorTokens.brandRed), style: strokeStyle)
    }

    private func selectionLabel(for sample: HeartRateSample) -> String {
        "\(Int(sample.bpm.rounded())) bpm"
    }

    private func selectPoint(at x: CGFloat, points: [CGPoint]) {
        guard let index = CurveRendering.nearestPointIndex(to: x, in: points) else { return }
        let tappedTime = samples[index].time
        selectedSampleTime = selectedSampleTime == tappedTime ? nil : tappedTime
    }
}
