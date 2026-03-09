//
//  ActivityHistoryView.swift
//  Snowly
//
//  Activity screen. Header, stat pills, recent sessions list.
//  Profile button in top-right corner.
//

import SwiftUI
import SwiftData

struct ActivityHistoryView: View {
    @Query(sort: \SkiSession.startDate, order: .reverse) private var sessions: [SkiSession]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var seasonStats: StatsService.SeasonStats {
        StatsService.seasonStats(from: sessions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    activityEmptyState
                } else {
                    activityContent
                }
            }
            .navigationTitle(String(localized: "activity_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ProfileView()) {
                        Image(systemName: "person.circle")
                    }
                    .accessibilityIdentifier("profile_button")
                }
            }
        }
    }

    // MARK: - Activity Content

    private var activityContent: some View {
        List {
            Section {
                HStack(spacing: Spacing.md) {
                    StatPill(
                        value: "\(seasonStats.totalSessions)",
                        label: String(localized: "activity_stat_ski_days"),
                        isAccented: true
                    )
                    StatPill(
                        value: "\(seasonStats.totalRuns)",
                        label: String(localized: "activity_stat_runs")
                    )
                    StatPill(
                        value: Formatters.vertical(seasonStats.totalVertical, unit: unitSystem),
                        label: String(localized: "activity_stat_vertical")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)
            }

            Section(String(localized: "activity_section_recent_ski_days")) {
                ForEach(sessions) { session in
                    NavigationLink(
                        destination: SessionSummaryView(
                            selectedSession: session,
                            showsDoneButton: false,
                            processesPersonalBests: false
                        )
                    ) {
                        SessionCard(session: session, unitSystem: unitSystem)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var activityEmptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "activity_empty_title"), systemImage: "chart.bar")
        } description: {
            Text(String(localized: "activity_empty_start_tracking_hint"))
        }
    }
}

#Preview {
    ActivityHistoryView()
        .modelContainer(for: [SkiSession.self, UserProfile.self], inMemory: true)
}
