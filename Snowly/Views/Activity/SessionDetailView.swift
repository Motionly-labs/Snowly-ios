//
//  SessionDetailView.swift
//  Snowly
//
//  Detailed view of a single ski session.
//

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: SkiSession

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var skiRuns: [SkiRun] {
        session.runs
            .filter { $0.activityType == .skiing }
            .sorted { $0.startDate < $1.startDate }
    }

    private var liftRuns: [SkiRun] {
        session.runs
            .filter { $0.activityType == .lift }
            .sorted { $0.startDate < $1.startDate }
    }

    private var walkingRuns: [SkiRun] {
        session.runs
            .filter { $0.activityType == .walk }
            .sorted { $0.startDate < $1.startDate }
    }

    private func runTitleText(_ number: Int) -> String {
        let format = String(localized: "session_run_title_format")
        return String(format: format, locale: Locale.current, Int64(number))
    }

    var body: some View {
        List {
            Section(String(localized: "session_detail_section_overview")) {
                detailRow(String(localized: "common_date"), value: session.startDate.longDisplay)
                detailRow(String(localized: "common_duration"), value: Formatters.duration(session.duration))
                if let resort = session.resort {
                    detailRow(String(localized: "common_resort"), value: resort.name)
                }
            }

            Section(String(localized: "session_detail_section_stats")) {
                detailRow(String(localized: "stat_max_speed"), value: Formatters.speed(session.maxSpeed, unit: unitSystem))
                detailRow(String(localized: "stat_total_distance"), value: Formatters.distance(session.totalDistance, unit: unitSystem))
                detailRow(String(localized: "stat_vertical_drop"), value: Formatters.vertical(session.totalVertical, unit: unitSystem))
                detailRow(String(localized: "common_runs"), value: "\(session.runCount)")
            }

            if !skiRuns.isEmpty {
                Section(String(localized: "session_detail_section_runs")) {
                    ForEach(Array(skiRuns.enumerated()), id: \.element.id) { index, run in
                        NavigationLink(destination: RunDetailView(run: run, runNumber: index + 1)) {
                            runRow(run, number: index + 1)
                        }
                    }
                }
            }

            if !liftRuns.isEmpty {
                Section(String(localized: "session_detail_section_chairlift_rides")) {
                    ForEach(liftRuns) { ride in
                        HStack {
                            Image(systemName: "cablecar.fill")
                                .foregroundStyle(ColorTokens.info)
                            Text(Formatters.duration(ride.duration))
                            Spacer()
                            Text("+\(Formatters.vertical(ride.verticalDrop, unit: unitSystem))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !walkingRuns.isEmpty {
                Section(String(localized: "session_detail_section_walking")) {
                    ForEach(walkingRuns) { segment in
                        HStack {
                            Image(systemName: "figure.walk")
                                .foregroundStyle(.secondary)
                            Text(Formatters.duration(segment.duration))
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(session.startDate.shortDisplay)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func runRow(_ run: SkiRun, number: Int) -> some View {
        HStack {
            Text(runTitleText(number))
                .fontWeight(.medium)

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(Formatters.speed(run.maxSpeed, unit: unitSystem))
                    .font(.subheadline)
                Text(Formatters.vertical(run.verticalDrop, unit: unitSystem))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
