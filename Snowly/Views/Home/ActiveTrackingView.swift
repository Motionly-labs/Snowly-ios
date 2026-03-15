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
        // Use sample timestamp as identity so Equatable auto-synthesis compares
        // GPS data, not a transient allocation UUID.  Required for correct diffing
        // if a ForEach over frozen points is added in future.
        var id: Date { time }
        let time: Date
        let speed: Double
        let state: SpeedCurveState
    }

    let samples: [SpeedSample]
    let unitSystem: UnitSystem
    let renderingPolicy: ActiveTrackingSeriesRenderingPolicy

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
                                    ColorTokens.surfaceOverlay,
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Canvas { context, _ in
                        var ctx = context
                        drawSegments(
                            into: &ctx,
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
                            tint: elements[selectionIndex].state.trackingColor,
                            chartSize: CGSize(width: width, height: graphHeight)
                        )
                    } else if maxIndex < coordinates.count {
                        let marker = coordinates[maxIndex]
                        let markerColor = elements[maxIndex].state.trackingColor
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
        .onChange(of: samples) { _, latest in
            appendNewSamples(from: latest)
        }
    }

    private func rebuildFromCurrentSamples() {
        frozenPoints.removeAll()
        lastProcessedSampleTime = nil
        cachedMaxSpeedIndex = 0
        appendNewSamples(from: samples)
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

        let rawFresh: [SpeedSample]
        if let lastProcessedSampleTime {
            rawFresh = samples.filter { $0.time > lastProcessedSampleTime }
        } else {
            rawFresh = samples.droppingLeadingZeroLikeSamples()
        }
        let fresh = rawFresh
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
        into context: inout GraphicsContext,
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
                context.fill(markerPath, with: .color(elements[0].state.trackingColor))
            }
            return
        }

        let strokeStyle = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        CurveRendering.drawStateSegments(
            into: &context,
            points: coordinates,
            states: elements.map(\.state),
            stateColor: \.trackingColor,
            style: strokeStyle
        )

        if showsLatestMarker, let end = coordinates.last, let last = elements.last {
            let markerPath = Path(ellipseIn: CGRect(
                x: end.x - 3,
                y: end.y - 3,
                width: 6,
                height: 6
            ))
            context.fill(markerPath, with: .color(last.state.trackingColor))
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
        dashboardLayout.instances.filter { $0.slot == .hero }
    }

    private var gridInstances: [ActiveTrackingCardInstance] {
        dashboardLayout.instances.filter { $0.slot == .grid }
    }

    private var selectedHeroInstance: ActiveTrackingCardInstance? {
        guard let id = selectedHeroInstanceId else { return heroInstances.first }
        return heroInstances.first(where: { $0.instanceId == id }) ?? heroInstances.first
    }

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var dashboardCardSource: ActiveTrackingCardInputAssembler.Source {
        ActiveTrackingCardInputAssembler.Source(
            semantic: ActiveTrackingCardInputAssembler.MotionSemanticSnapshot(
                skiingMetrics: trackingService.skiingMetrics,
                currentSpeed: trackingService.currentSpeed,
                currentAltitudeMeters: trackingService.currentAltitude,
                completedRuns: trackingService.completedRuns,
                elapsedSeconds: elapsedTime,
                currentHeartRate: watchBridgeService.currentHeartRate,
                averageHeartRate: watchBridgeService.averageHeartRate
            ),
            presentation: ActiveTrackingCardInputAssembler.MotionPresentationSnapshot(
                speedSamples: trackingService.speedSamples,
                altitudeSamples: trackingService.altitudeSamples,
                heartRateSamples: watchBridgeService.heartRateSamples
            ),
            context: ActiveTrackingCardInputAssembler.TrackingCardPresentationContext(
                unitSystem: unitSystem
            )
        )
    }

    private var dashboardCardInputs: [UUID: AnyActiveTrackingCardInput] {
        Dictionary(uniqueKeysWithValues: dashboardLayout.instances.map { instance in
            (instance.instanceId, ActiveTrackingCardInputAssembler.input(for: instance, source: dashboardCardSource))
        })
    }

    private var speedUnitLabel: String {
        Formatters.speedUnit(unitSystem)
    }

    private func scalarCardInput(for kind: ActiveTrackingCardKind) -> ActiveTrackingScalarCardInput? {
        ActiveTrackingCardInputAssembler.scalarInput(for: kind, source: dashboardCardSource)
    }

    private func numericPrimaryValue(for kind: ActiveTrackingCardKind) -> ActiveTrackingNumericValue? {
        guard let input = scalarCardInput(for: kind) else { return nil }
        guard case .numeric(let value) = input.primaryValue else { return nil }
        return value
    }

    private func textPrimaryValue(for kind: ActiveTrackingCardKind) -> ActiveTrackingTextValue? {
        guard let input = scalarCardInput(for: kind) else { return nil }
        guard case .text(let value) = input.primaryValue else { return nil }
        return value
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
        numericPrimaryValue(for: .peakSpeed)?.value ?? 0
    }

    private var displayedAvgSpeed: Double {
        numericPrimaryValue(for: .avgSpeed)?.value ?? 0
    }

    private var displayedCurrentSpeed: Double {
        numericPrimaryValue(for: .currentSpeed)?.value ?? 0
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

    private var totalVerticalValue: Double {
        numericPrimaryValue(for: .vertical)?.value ?? 0
    }

    private var totalVerticalUnit: String {
        numericPrimaryValue(for: .vertical)?.unit ?? Formatters.verticalUnit(unitSystem)
    }

    private var totalDistanceValue: Double {
        numericPrimaryValue(for: .distance)?.value ?? 0
    }

    private var totalDistanceUnit: String {
        numericPrimaryValue(for: .distance)?.unit ?? Formatters.distanceUnit(unitSystem)
    }

    private var hiddenHeroKinds: [ActiveTrackingCardKind] {
        let presentKinds = Set(heroInstances.map(\.kind))
        return ActiveTrackingCardRegistry.allHeroKinds
            .filter { !presentKinds.contains($0) }
    }

    private var landscapeStatKinds: [ActiveTrackingCardKind] { [.currentSpeed, .vertical, .runCount] }

    private var elapsedTimeText: String {
        let total = Int(elapsedTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var currentHeartRateText: String {
        textPrimaryValue(for: .heartRate)?.value ?? "--"
    }

    private var landscapeSpeedCurveInput: ActiveTrackingSeriesCardInput? {
        ActiveTrackingCardInputAssembler.seriesInput(
            for: .speedCurve,
            source: dashboardCardSource
        )
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
        .onAppear {
            pulseRecording = true
            trackingService.setTrackingDashboardVisible(true)
            rebuildCachedRuns()
            updateElapsedTime()
            if let settings = deviceSettings_ {
                dashboardLayout = settings.resolvedDashboardLayout
                selectedHeroInstanceId = dashboardLayout.instances.first(where: { $0.slot == .hero })?.instanceId
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
        if let input = dashboardCardInputs[instance.instanceId] {
            switch input {
            case .scalar(let scalar):
                heroScalarPage(input: scalar)
            case .series(let series):
                heroSeriesPage(input: series)
            case .composite(let composite):
                heroCompositePage(input: composite)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func heroScalarPage(input: ActiveTrackingScalarCardInput) -> some View {
        switch input.primaryValue {
        case .numeric(let value):
            heroMetricPage(
                label: input.title,
                value: value.value,
                decimals: value.decimals,
                suffix: value.unit,
                subtitle: input.subtitle ?? ""
            )
        case .text(let value):
            heroTextPage(
                label: input.title,
                value: value.value,
                suffix: value.unit,
                subtitle: input.subtitle ?? ""
            )
        }
    }

    private func heroSeriesPage(input: ActiveTrackingSeriesCardInput) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(input.title)
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                if let primaryValue = input.primaryValue {
                    seriesPrimaryValueView(primaryValue)
                }

                if let subtitle = input.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            heroSeriesContent(input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func heroCompositePage(input: ActiveTrackingCompositeCardInput) -> some View {
        let altitudeSamples = input.embeddedSeries
            .first { $0.role == .altitude }?
            .payload
            .altitudeSamples ?? []
        let speedSamples = input.embeddedSeries
            .first { $0.role == .speed }?
            .payload
            .speedSamples ?? []

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(input.title)
                .font(Typography.caption2Semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(input.chips, id: \.kind) { chip in
                    heroMetricChip(
                        icon: ActiveTrackingCardRegistry.definition(for: chip.kind).icon,
                        label: chip.title,
                        value: formattedPrimaryValue(chip.primaryValue),
                        tint: cardAccent(for: chip.kind)
                    )
                }
            }

            SyncedActivityProfileView(
                altitudeSamples: altitudeSamples,
                speedSamples: speedSamples,
                unitSystem: unitSystem
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func seriesPrimaryValueView(_ value: ActiveTrackingCardPrimaryValue) -> some View {
        switch value {
        case .numeric(let numeric):
            Text(String(format: "%.\(numeric.decimals)f %@", numeric.value, numeric.unit))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        case .text(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(text.value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !text.unit.isEmpty {
                    Text(text.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func heroSeriesContent(input: ActiveTrackingSeriesCardInput) -> some View {
        switch input.seriesPayload {
        case .speed(let samples):
            LiveSpeedCurveView(
                samples: samples,
                unitSystem: unitSystem,
                renderingPolicy: input.renderingPolicy
            )
        case .altitude(let samples):
            AltitudeSparkline(samples: samples, unitLabel: totalVerticalUnit)
        case .heartRate(let samples):
            HeartRateCurveView(samples: samples)
        }
    }

    private func formattedPrimaryValue(_ value: ActiveTrackingCardPrimaryValue) -> String {
        switch value {
        case .numeric(let numeric):
            if numeric.unit.isEmpty {
                return String(format: "%.\(numeric.decimals)f", numeric.value)
            }
            return String(format: "%.\(numeric.decimals)f %@", numeric.value, numeric.unit)
        case .text(let text):
            return text.unit.isEmpty ? text.value : "\(text.value) \(text.unit)"
        }
    }

    // MARK: - Landscape Dashboard

    @ViewBuilder
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
                }
                .padding(Spacing.xl)
                .frame(width: Spacing.landscapeStatPanel)

                // Vertical divider
                Rectangle()
                    .fill(Color.primary.opacity(Opacity.hairline))
                    .frame(width: 1)
                    .padding(.vertical, Spacing.lg)

                // Right panel mirrors the shared curve input contract used by hero cards.
                if let landscapeSpeedCurveInput,
                   case .speed(let samples) = landscapeSpeedCurveInput.seriesPayload {
                    LiveSpeedCurveView(
                        samples: samples,
                        unitSystem: unitSystem,
                        renderingPolicy: landscapeSpeedCurveInput.renderingPolicy
                    )
                    .padding(Spacing.xl)
                } else {
                    Color.clear
                        .padding(Spacing.xl)
                }
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

    private func cardAccent(for kind: ActiveTrackingCardKind) -> Color {
        switch kind {
        case .currentSpeed, .speedCurve, .skiTime:
            return ColorTokens.sportAccent
        case .peakSpeed, .liftCount:
            return ColorTokens.secondaryAccent
        case .avgSpeed, .distance:
            return ColorTokens.info
        case .vertical:
            return ColorTokens.success
        case .runCount:
            return ColorTokens.brandGold
        case .currentAltitude, .altitudeCurve:
            return ColorTokens.trailBlack
        case .heartRate, .heartRateCurve:
            return ColorTokens.brandRed
        }
    }

    private func landscapeStatRow(for kind: ActiveTrackingCardKind) -> some View {
        let chip = ActiveTrackingCardInputAssembler.scalarChip(for: kind, source: dashboardCardSource)
        return HStack(spacing: Spacing.sm) {
            Image(systemName: ActiveTrackingCardRegistry.definition(for: kind).icon)
                .font(Typography.captionSemibold)
                .foregroundStyle(cardAccent(for: kind))
                .frame(width: Spacing.lg, alignment: .center)
            Text(chip?.title ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(chip.map { formattedPrimaryValue($0.primaryValue) } ?? "--")
                .font(Typography.captionSemibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
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
            inputs: dashboardCardInputs,
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

    private var displaySamples: [HeartRateSample] {
        samples.droppingLeadingZeroLikeSamples()
    }

    var body: some View {
        let s = displaySamples
        GeometryReader { geo in
            TrackingSeriesCurveView(
                points: CurveRendering.indexedPoints(
                    values: s.map(\.bpm),
                    in: geo.size,
                    minimumRange: 20
                ),
                coloring: .uniform(ColorTokens.brandRed),
                fillColors: [
                    ColorTokens.brandRed.opacity(CurveRendering.standardFillTopOpacity),
                    .clear,
                ],
                selectionLabel: { [s] idx in
                    guard idx < s.count else { return "--" }
                    return "\(Int(s[idx].bpm.rounded())) bpm"
                }
            )
        }
    }
}
