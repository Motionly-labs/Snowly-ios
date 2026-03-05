//
//  RunDetailView.swift
//  Snowly
//
//  Detailed view of a single ski run.
//

import SwiftUI
import SwiftData

struct RunDetailView: View {
    let run: SkiRun
    let runNumber: Int

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var unitSystem: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var runTitleText: String {
        let format = String(localized: "session_run_title_format")
        return String(format: format, locale: Locale.current, Int64(runNumber))
    }

    var body: some View {
        List {
            Section(String(localized: "run_detail_section_stats")) {
                detailRow(String(localized: "common_duration"), value: Formatters.duration(run.duration))
                detailRow(String(localized: "stat_max_speed"), value: Formatters.speed(run.maxSpeed, unit: unitSystem))
                detailRow(String(localized: "stat_avg_speed"), value: Formatters.speed(run.averageSpeed, unit: unitSystem))
                detailRow(String(localized: "common_distance"), value: Formatters.distance(run.distance, unit: unitSystem))
                detailRow(String(localized: "stat_vertical_drop"), value: Formatters.vertical(run.verticalDrop, unit: unitSystem))
            }

            Section(String(localized: "run_detail_section_timing")) {
                detailRow(String(localized: "common_start"), value: run.startDate.timeDisplay)
                if let end = run.endDate {
                    detailRow(String(localized: "common_end"), value: end.timeDisplay)
                }
            }

            if !run.trackPoints.isEmpty {
                Section(String(localized: "run_detail_section_track_data")) {
                    detailRow(String(localized: "run_detail_gps_points"), value: "\(run.trackPoints.count)")
                    if let first = run.trackPoints.first, let last = run.trackPoints.last {
                        detailRow(String(localized: "run_detail_start_altitude"),
                                  value: Formatters.vertical(first.altitude, unit: unitSystem))
                        detailRow(String(localized: "run_detail_end_altitude"),
                                  value: Formatters.vertical(last.altitude, unit: unitSystem))
                    }
                }
            }
        }
        .navigationTitle(runTitleText)
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
}
