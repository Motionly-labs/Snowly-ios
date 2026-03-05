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
    case peakSpeed, avgSpeed, runs, vertical
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

struct ActiveTrackingView: View {
    @Environment(SessionTrackingService.self) private var trackingService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var showingSummary = false
    @State private var activeTab: TrackingDashboardTab = .session
    @State private var speedHistory: [Double] = [0, 8, 16, 28, 35, 22, 0]
    @State private var selectedHeroPage: HeroStatPage = .peakSpeed
    @State private var pulseRecording = false
    @State private var cardsAppeared = false
    @State private var cachedSkiRuns: [TrackedRunSnapshot] = []

    private var activityGoalMinutes: Double {
        profiles.first?.dailyGoalMinutes ?? 240
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
        speedValue(lastRun?.maxSpeed ?? trackingService.maxSpeed)
    }

    private var displayedAvgSpeed: Double {
        if let run = lastRun {
            return speedValue(run.avgSpeed)
        }
        let totalDist = trackingService.totalDistance
        let totalTime = trackingService.elapsedTime
        guard totalTime > 0 else { return 0 }
        return speedValue(totalDist / totalTime)
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

    private var runsSubtitle: String {
        let format = String(localized: "tracking_runs_subtitle_format")
        return String(format: format, locale: Locale.current, formatVertical(trackingService.totalVertical))
    }

    private var verticalSubtitle: String {
        let format = String(localized: "tracking_vertical_subtitle_format")
        return String(format: format, locale: Locale.current, Int64(runCountValue), elapsedMinutes)
    }

    private var bestSpeed: Double {
        let runBest = cachedSkiRuns.map(\.maxSpeed).max() ?? 0
        return max(runBest, trackingService.maxSpeed)
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
        trackingService.elapsedTime / 60
    }

    private var activityProgress: Double {
        min(max(elapsedMinutes / activityGoalMinutes, 0), 1)
    }

    private var activityGoalHours: Int64 {
        max(1, Int64(activityGoalMinutes / 60))
    }

    private var activityGoalText: String {
        let format = String(localized: "tracking_goal_progress_format")
        return String(format: format, locale: Locale.current, activityGoalHours)
    }

    private func runTitleText(_ number: Int) -> String {
        let format = String(localized: "session_run_title_format")
        return String(format: format, locale: Locale.current, Int64(number))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            SnowParticlesView()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topStatusBar
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        heroSection
                        speedCurveSection
                        tabSwitcher

                        Group {
                            if activeTab == .session {
                                sessionContent
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.combined(with: .offset(y: -8))
                                    ))
                            } else {
                                runsContent
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.combined(with: .offset(y: -8))
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 26)
                    .padding(.bottom, 150)
                }
            }

            bottomStopControl
        }
        .onAppear {
            pulseRecording = true
            cachedSkiRuns = Self.buildSkiRuns(from: trackingService.completedRuns)
            appendSpeedSample(trackingService.currentSpeed)
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                cardsAppeared = true
            }
        }
        .onChange(of: trackingService.runCount) { _, _ in
            cachedSkiRuns = Self.buildSkiRuns(from: trackingService.completedRuns)
        }
        .onChange(of: trackingService.currentSpeed) { _, newSpeed in
            appendSpeedSample(newSpeed)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(trackingService.state == .paused ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                    .scaleEffect(trackingService.state == .paused ? 1.0 : (pulseRecording ? 1 : 0.85))
                    .opacity(trackingService.state == .paused ? 0.7 : (pulseRecording ? 1 : 0.35))
                    .animation(
                        trackingService.state == .paused
                            ? .easeInOut(duration: 0.3)
                            : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulseRecording
                    )
                    .animation(.easeInOut(duration: 0.3), value: trackingService.state)

                Text(trackingService.state == .paused
                    ? String(localized: "tracking_state_paused")
                    : String(localized: "tracking_state_riding"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Spacer()

            Button {
                if trackingService.state == .paused {
                    trackingService.resumeTracking()
                } else {
                    trackingService.pauseTracking()
                }
            } label: {
                Image(systemName: trackingService.state == .paused ? "play.fill" : "pause.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(trackingService.state == .paused ? Color.orange : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        trackingService.state == .paused
                            ? Color.orange.opacity(0.15)
                            : Color(.quaternarySystemFill)
                    )
                    .clipShape(Circle())
                    .animation(.easeInOut(duration: 0.3), value: trackingService.state)
            }
            .accessibilityIdentifier(
                trackingService.state == .paused ? "resume_tracking_button" : "pause_tracking_button"
            )
            .padding(.leading, 8)

            Button(action: minimizeTrackingDashboard) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.quaternarySystemFill))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("minimize_tracking_button")
            .padding(.leading, 8)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 4) {
            TabView(selection: $selectedHeroPage) {
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
                    label: String(localized: "common_runs"),
                    value: runCountValue,
                    decimals: 0,
                    suffix: "",
                    subtitle: runsSubtitle
                )
                .tag(HeroStatPage.runs)

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

            HStack(spacing: 6) {
                ForEach(HeroStatPage.allCases) { page in
                    Circle()
                        .fill(page == selectedHeroPage ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            AnimatedNumberText(
                value: value,
                decimals: decimals,
                duration: 1.2,
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
        SpeedCurveView(
            data: speedHistory,
            maxSpeedLabel: speedValue(bestSpeed)
        )
        .frame(height: 94)
    }

    // MARK: - Tabs

    private var tabSwitcher: some View {
        SegmentedPicker(
            items: TrackingDashboardTab.allCases,
            selection: Binding(
                get: { activeTab },
                set: { newTab in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeTab = newTab
                    }
                }
            )
        ) { tab in
            Text(tab.title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 2)
    }

    // MARK: - Session Tab

    private var sessionContent: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
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
                    label: String(localized: "stat_top_speed"),
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)

            AnimatedNumberText(
                value: value,
                decimals: decimals,
                duration: 1.2,
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
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(delay),
            value: cardsAppeared
        )
    }

    private var activeTimeCard: some View {
        HStack(spacing: 18) {
            ActivityRingView(
                targetProgress: activityProgress,
                size: 52,
                strokeWidth: 4.5,
                color: .accentColor,
                delay: 0.6
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "common_ski_time"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    AnimatedNumberText(
                        value: elapsedMinutes,
                        decimals: 0,
                        duration: 1.2,
                        delay: 0.6
                    )
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                    Text(String(localized: "common_min_abbrev"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(activityGoalText)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, 14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .opacity(cardsAppeared ? 1 : 0)
        .scaleEffect(cardsAppeared ? 1 : 0.92)
        .animation(
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(0.6),
            value: cardsAppeared
        )
    }

    // MARK: - Runs Tab

    private var runsContent: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "tracking_chart_speed_by_run"))
                    .font(.caption2.weight(.semibold))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(runTitleText(run.id))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if run.maxSpeed == (cachedSkiRuns.map(\.maxSpeed).max() ?? 0) && cachedSkiRuns.count > 1 {
                    Text(String(localized: "tracking_top_run_label"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                }
            }

            HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 2) {
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

    // MARK: - Bottom Stop

    private var bottomStopControl: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                if trackingService.state == .paused {
                    Button {
                        trackingService.resumeTracking()
                    } label: {
                        Label(String(localized: "tracking_resume_cta"), systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 14)
                            .background(.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("resume_tracking_button")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                SlideToStopButton(onStop: endSession)
                    .accessibilityIdentifier("stop_tracking_button")
            }
            .animation(.easeInOut(duration: 0.3), value: trackingService.state)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 44)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea(edges: .bottom)
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

    private func appendSpeedSample(_ metersPerSecond: Double) {
        let sample = max(speedValue(metersPerSecond), 0)
        speedHistory.append(sample)
        if speedHistory.count > 28 {
            speedHistory.removeFirst(speedHistory.count - 28)
        }
    }

    private func endSession() {
        trackingService.stopTracking()
        Task {
            await trackingService.finalizeHealthKitWorkout()
            trackingService.saveSession(to: modelContext)
            showingSummary = true
        }
    }

    private func minimizeTrackingDashboard() {
        trackingService.persistSnapshotNowIfNeeded()
        dismiss()
    }
}
