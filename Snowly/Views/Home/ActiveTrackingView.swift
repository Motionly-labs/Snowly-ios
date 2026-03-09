//
//  ActiveTrackingView.swift
//  Snowly
//
//  Tracking dashboard: hero peak speed, animated curve, session/runs tabs,
//  and fixed stop control.
//

import SwiftUI
import SwiftData

private enum HeroStatPage: Int, CaseIterable, Identifiable {
    case currentSpeed, peakSpeed, avgSpeed, vertical
    var id: Int { rawValue }
}

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

/// Self-contained speed curve that reads time-stamped samples from the
/// tracking service and resamples them to uniform intervals.
///
/// Uses `TimelineView` for periodic refresh (tied to view lifecycle — no
/// Timer leak). Reads `speedSamples` only inside the timeline closure so
/// the outer view doesn't subscribe to sample mutations via `@Observable`.
private struct LiveSpeedCurveView: View {
    @Environment(SessionTrackingService.self) private var trackingService
    let unitSystem: UnitSystem
    let cachedMaxRunSpeed: Double

    private static let windowDuration: TimeInterval = 600 // 10 minutes
    private static let resampleInterval: TimeInterval = 2  // seconds between points
    private static let refreshInterval: TimeInterval = 2   // timeline tick
    private static let smoothingAlpha: Double = 0.45

    private var bestSpeed: Double {
        max(cachedMaxRunSpeed, trackingService.maxSpeed)
    }

    private func speedValue(_ metersPerSecond: Double) -> Double {
        switch unitSystem {
        case .metric: return UnitConversion.metersPerSecondToKmh(metersPerSecond)
        case .imperial: return UnitConversion.metersPerSecondToMph(metersPerSecond)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { context in
            // Reading speedSamples inside TimelineView's content closure
            // avoids subscribing the parent view to observation changes.
            let samples = trackingService.speedSamples
            let resampled = resample(samples, now: context.date)
            SpeedCurveView(
                data: resampled,
                maxSpeedLabel: speedValue(bestSpeed)
            )
        }
    }

    // MARK: - Resampling

    /// Linearly interpolates `samples` onto a uniform grid covering the
    /// available time span (up to 10 minutes) with one point every
    /// `resampleInterval` seconds, then applies bidirectional EMA smoothing.
    private func resample(_ samples: [SpeedSample], now: Date) -> [Double] {
        guard let first = samples.first else { return [] }

        let windowStart = max(
            first.time,
            now.addingTimeInterval(-Self.windowDuration)
        )
        let span = now.timeIntervalSince(windowStart)
        guard span > 0 else {
            return [speedValue(samples.last?.speed ?? 0)]
        }

        let pointCount = max(Int(span / Self.resampleInterval), 1)
        var result: [Double] = []
        result.reserveCapacity(pointCount + 1)

        var sampleIndex = 0
        for i in 0...pointCount {
            let targetTime = windowStart.addingTimeInterval(
                Double(i) / Double(pointCount) * span
            )

            while sampleIndex < samples.count - 1
                    && samples[sampleIndex + 1].time <= targetTime {
                sampleIndex += 1
            }

            let s0 = samples[sampleIndex]
            if sampleIndex < samples.count - 1 {
                let s1 = samples[sampleIndex + 1]
                let gap = s1.time.timeIntervalSince(s0.time)
                if gap > 0 {
                    let t = targetTime.timeIntervalSince(s0.time) / gap
                    let interpolated = s0.speed + (s1.speed - s0.speed) * t
                    result.append(speedValue(max(interpolated, 0)))
                } else {
                    result.append(speedValue(max(s0.speed, 0)))
                }
            } else {
                result.append(speedValue(max(s0.speed, 0)))
            }
        }

        return Self.smoothBidirectionalEMA(result, alpha: Self.smoothingAlpha)
    }

    /// Zero-phase EMA: forward pass + backward pass averaged.
    /// Removes GPS jitter while preserving peak timing (no lag).
    private static func smoothBidirectionalEMA(_ data: [Double], alpha: Double) -> [Double] {
        guard data.count >= 3 else { return data }

        let count = data.count

        // Forward EMA
        var forward = [Double]()
        forward.reserveCapacity(count)
        forward.append(data[0])
        for i in 1..<count {
            forward.append(alpha * data[i] + (1 - alpha) * forward[i - 1])
        }

        // Backward EMA
        var backward = [Double](repeating: 0, count: count)
        backward[count - 1] = data[count - 1]
        for i in stride(from: count - 2, through: 0, by: -1) {
            backward[i] = alpha * data[i] + (1 - alpha) * backward[i + 1]
        }

        // Average both passes
        var result = [Double]()
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append((forward[i] + backward[i]) / 2)
        }
        return result
    }
}

struct ActiveTrackingView: View {
    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(SkiMapCacheService.self) private var skiMapService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var showingSummary = false
    @State private var activeTab: TrackingDashboardTab = .session
    @State private var selectedHeroPage: HeroStatPage = .peakSpeed
    @State private var pulseRecording = false
    @State private var cardsAppeared = false
    @State private var cachedSkiRuns: [TrackedRunSnapshot] = []
    @State private var cachedMaxRunSpeed: Double = 0
    @State private var elapsedTime: TimeInterval = 0


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
        speedValue(lastRun?.maxSpeed ?? trackingService.maxSpeed)
    }

    private var displayedAvgSpeed: Double {
        if let run = lastRun {
            return speedValue(run.avgSpeed)
        }
        let totalDist = trackingService.totalDistance
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
        Double(max(trackingService.runCount, cachedSkiRuns.count))
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
            formatVertical(trackingService.totalVertical),
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
        max(cachedMaxRunSpeed, trackingService.maxSpeed)
    }

    private var totalVerticalValue: Double {
        switch unitSystem {
        case .metric: return trackingService.totalVertical
        case .imperial: return UnitConversion.metersToFeet(trackingService.totalVertical)
        }
    }

    private var totalVerticalUnit: String {
        Formatters.verticalUnit(unitSystem)
    }

    private var totalDistanceValue: Double {
        switch unitSystem {
        case .metric: return trackingService.totalDistance / 1000
        case .imperial: return trackingService.totalDistance / 1609.344
        }
    }

    private var totalDistanceUnit: String {
        switch unitSystem {
        case .metric: return "km"
        case .imperial: return "mi"
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
                        speedCurveSection
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
        }
        .onAppear {
            pulseRecording = true
            trackingService.setTrackingDashboardVisible(true)
            rebuildCachedRuns()
            updateElapsedTime()
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                cardsAppeared = true
            }
        }
        .onDisappear {
            trackingService.setTrackingDashboardVisible(false)
        }
        .onChange(of: trackingService.runCount) { _, _ in
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
                    .fill(trackingService.state == .paused ? ColorTokens.warning : ColorTokens.success)
                    .frame(width: Spacing.gap, height: Spacing.gap)
                    .scaleEffect(trackingService.state == .paused ? 1.0 : (pulseRecording ? 1 : 0.85))
                    .opacity(trackingService.state == .paused ? 0.7 : (pulseRecording ? 1 : Opacity.medium))
                    .animation(
                        trackingService.state == .paused
                            ? AnimationTokens.moderateEaseInOut
                            : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulseRecording
                    )
                    .animation(AnimationTokens.moderateEaseInOut, value: trackingService.state)

                Text(trackingStatusText)
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer()

            Button {
                Task {
                    if trackingService.state == .paused {
                        await trackingService.resumeTracking(unitSystem: unitSystem)
                    } else {
                        await trackingService.pauseTracking()
                    }
                }
            } label: {
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
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Spacing.xs) {
            TabView(selection: $selectedHeroPage) {
                heroPage(
                    label: String(localized: "stat_current_speed"),
                    value: displayedCurrentSpeed,
                    decimals: 1,
                    suffix: speedUnitLabel,
                    subtitle: currentSpeedSubtitle
                )
                .tag(HeroStatPage.currentSpeed)

                heroPage(
                    label: String(localized: "stat_peak_speed"),
                    value: displayedPeakSpeed,
                    decimals: 1,
                    suffix: speedUnitLabel,
                    subtitle: peakSpeedSubtitle
                )
                .tag(HeroStatPage.peakSpeed)

                heroPage(
                    label: String(localized: "stat_avg_speed"),
                    value: displayedAvgSpeed,
                    decimals: 1,
                    suffix: speedUnitLabel,
                    subtitle: avgSpeedSubtitle
                )
                .tag(HeroStatPage.avgSpeed)

                heroPage(
                    label: String(localized: "common_vertical"),
                    value: totalVerticalValue,
                    decimals: 0,
                    suffix: totalVerticalUnit,
                    subtitle: verticalSubtitle
                )
                .tag(HeroStatPage.vertical)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 130)

            HStack(spacing: Spacing.gap) {
                ForEach(HeroStatPage.allCases) { page in
                    Circle()
                        .fill(page == selectedHeroPage ? Color.primary : Color.primary.opacity(Opacity.muted))
                        .frame(width: Spacing.gap, height: Spacing.gap)
                }
            }
        }
    }

    private func heroPage(
        label: String,
        value: Double,
        decimals: Int,
        suffix: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            AnimatedNumberText(
                value: value,
                decimals: decimals,
                suffix: suffix
            )
            .font(Typography.metricHero)
            .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Curve

    private var speedCurveSection: some View {
        LiveSpeedCurveView(unitSystem: unitSystem, cachedMaxRunSpeed: cachedMaxRunSpeed)
            .frame(height: 94)
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
        VStack(spacing: Spacing.gutter) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Spacing.gutter
            ) {
                statCard(
                    label: String(localized: "common_vertical"),
                    icon: "arrow.down",
                    value: totalVerticalValue,
                    decimals: 0,
                    suffix: totalVerticalUnit,
                    delay: 0.0
                )
                statCard(
                    label: String(localized: "common_distance"),
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    value: totalDistanceValue,
                    decimals: 1,
                    suffix: totalDistanceUnit,
                    delay: 0.08
                )
                statCard(
                    label: String(localized: "common_runs"),
                    icon: "number",
                    value: Double(max(trackingService.runCount, cachedSkiRuns.count)),
                    decimals: 0,
                    suffix: "",
                    delay: 0.16
                )
                statCard(
                    label: String(localized: "stat_peak_speed"),
                    icon: "bolt.fill",
                    value: speedValue(bestSpeed),
                    decimals: 1,
                    suffix: speedUnitLabel,
                    delay: 0.24
                )
            }

            activeTimeCard
        }
    }

    private func statCard(
        label: String,
        icon: String,
        value: Double,
        decimals: Int,
        suffix: String,
        delay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gutter) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(Typography.caption2Semibold)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)

            AnimatedNumberText(
                value: value,
                decimals: decimals,
                suffix: suffix,
                delay: delay
            )
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.lg)
        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(
            AnimationTokens.smoothEntranceFast.delay(delay),
            value: cardsAppeared
        )
    }

    private var activeTimeCard: some View {
        HStack(spacing: Spacing.card) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "common_ski_time"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    AnimatedNumberText(
                        value: elapsedMinutes,
                        decimals: 0,
                        delay: 0.6
                    )
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                    Text(String(localized: "common_min_abbrev"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, 14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(
            AnimationTokens.smoothEntranceFast.delay(0.6),
            value: cardsAppeared
        )
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
            let resort = ResortResolver.resolveCurrentResort(
                from: skiMapService,
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
