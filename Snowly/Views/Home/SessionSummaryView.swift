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

struct SessionSummaryView: View {
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    let onDismiss: () -> Void

    @State private var showingShareSheet = false
    @State private var shareImage: UIImage?
    @State private var personalBestRecords: [String] = []
    @State private var hasProcessedPersonalBests = false
    @State private var isGeneratingShare = false

    private var latestSession: SkiSession? { sessions.first }

    private var profile: UserProfile? { profiles.first }

    private var unitSystem: UnitSystem {
        profile?.preferredUnits ?? .metric
    }

    private func runTitleText(_ number: Int) -> String {
        let format = String(localized: "session_run_title_format")
        return String(format: format, locale: Locale.current, Int64(number))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = latestSession {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common_done"), action: onDismiss)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
        }
        .task(id: latestSession?.id) {
            processPersonalBestsIfNeeded()
        }
    }

    // MARK: - Layout Detection

    private func useLandscapeLayout(for size: CGSize) -> Bool {
        size.width > size.height
    }

    // MARK: - Portrait Layout

    private func portraitSummaryLayout(session: SkiSession) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Route map (always visible)
                RouteMapView(session: session, height: 280)
                    .padding(.horizontal)

                // Avatar + user info
                userInfoSection(session: session)

                // Hero duration
                heroDurationSection(session: session)

                // 2×2 stats grid
                statsGridSection(session: session)
                    .padding(.horizontal)

                // Personal best
                if !personalBestRecords.isEmpty {
                    personalBestsBanner(personalBestRecords)
                        .padding(.horizontal)
                }

                // Speed curve
                speedCurveSection(session: session)
                    .padding(.horizontal)

                // Run breakdown
                runBreakdownSection(session)
                    .padding(.horizontal)

                // Share button
                shareButton(session: session)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Landscape Layout

    private func landscapeSummaryLayout(session: SkiSession, size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 16) {
            landscapeMapColumn(session: session, size: size)
                .frame(width: max(280, size.width * 0.42))

            ScrollView {
                VStack(spacing: 20) {
                    userInfoSection(session: session)
                    heroDurationSection(session: session)
                    statsGridSection(session: session)

                    if !personalBestRecords.isEmpty {
                        personalBestsBanner(personalBestRecords)
                    }

                    speedCurveSection(session: session)
                    runBreakdownSection(session)

                    shareButton(session: session)
                        .padding(.bottom, 32)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func landscapeMapColumn(session: SkiSession, size: CGSize) -> some View {
        RouteMapView(session: session, height: max(240, size.height - 24))
    }

    // MARK: - User Info

    private func userInfoSection(session: SkiSession) -> some View {
        VStack(spacing: 8) {
            AvatarView(
                avatarData: profile?.avatarData,
                displayName: profile?.displayName ?? "",
                size: 48
            )

            if let name = profile?.displayName, !name.isEmpty {
                Text(name)
                    .font(.headline)
            }

            HStack(spacing: 6) {
                if let resort = session.resort {
                    Text(resort.name)
                    Text("·")
                }
                Text(session.startDate.longDisplay)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Hero Duration

    private func heroDurationSection(session: SkiSession) -> some View {
        VStack(spacing: 4) {
            HStack {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(height: 1)
                Text(Formatters.duration(session.duration))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Stats Grid

    private func statsGridSection(session: SkiSession) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
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
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Personal Bests

    private func personalBestsBanner(_ records: [String]) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text(String(localized: "summary_new_personal_best_title"))
                    .font(.headline)
                    .foregroundStyle(.yellow)
            }
            Text(records.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Speed Curve

    private func speedCurveSection(session: SkiSession) -> some View {
        let skiRuns = session.runs
            .filter { $0.activityType == .skiing }
            .sorted { $0.startDate < $1.startDate }
        let speedData = skiRuns.map { $0.maxSpeed }
        let maxSpeedDisplay: Double = {
            switch unitSystem {
            case .metric: return UnitConversion.metersPerSecondToKmh(speedData.max() ?? 0)
            case .imperial: return UnitConversion.metersPerSecondToMph(speedData.max() ?? 0)
            }
        }()

        return Group {
            if speedData.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "tracking_chart_speed_by_run"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    SpeedCurveView(data: speedData, maxSpeedLabel: maxSpeedDisplay)
                        .frame(height: 120)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
        }
    }

    // MARK: - Run Breakdown

    private func runBreakdownSection(_ session: SkiSession) -> some View {
        let skiRuns = session.runs
            .filter { $0.activityType == .skiing }
            .sorted { $0.startDate < $1.startDate }

        return VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "common_runs"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(Array(skiRuns.enumerated()), id: \.element.id) { index, run in
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ColorTokens.brandGradient)
                        .frame(width: 3, height: 28)

                    Text(runTitleText(index + 1))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text(Formatters.vertical(run.verticalDrop, unit: unitSystem))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    Text(Formatters.speed(run.maxSpeed, unit: unitSystem))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 6)

                if index < skiRuns.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Share

    private func shareButton(session: SkiSession) -> some View {
        Button {
            Task {
                await generateShareCard(session)
            }
        } label: {
            HStack {
                if isGeneratingShare {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(String(localized: "summary_share_cta"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isGeneratingShare)
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

        shareImage = await ShareCardRenderer.render(
            session: session,
            resortName: resortName,
            unitSystem: currentUnitSystem,
            avatarData: currentAvatarData,
            displayName: currentDisplayName
        )
        if shareImage != nil {
            showingShareSheet = true
        }
    }

    // MARK: - Personal Bests Processing

    private func processPersonalBestsIfNeeded() {
        guard !hasProcessedPersonalBests,
              let session = latestSession,
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
        hasProcessedPersonalBests = true
    }
}

/// UIKit share sheet wrapper.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
