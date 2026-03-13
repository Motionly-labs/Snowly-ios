//
//  SessionCard.swift
//  Snowly
//
//  Session card component for list rows.
//  Date label, resort name, runs count, 4-column stats.
//

import SwiftUI

struct SessionCard: View {
    let session: SkiSession
    let unitSystem: UnitSystem

    private var headerTitle: String {
        let location = session.resort?.name ?? String(localized: "session_card_unknown_resort")
        let title = session.effectiveNoteTitle
        guard !title.isEmpty else { return location }
        return "\(title)（\(location)）"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Date label
            Text(session.startDate.shortDisplay.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(ColorTokens.primaryAccent)

            // Resort name + Runs
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(headerTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if session.hasAttachedGearSetup {
                        Text(session.gearSetupDisplayName)
                            .font(.caption)
                            .foregroundStyle(ColorTokens.primaryAccent)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(session.runCount) \(String(localized: "common_runs"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 4-column stats grid
            HStack(spacing: 0) {
                statColumn(
                    value: Formatters.distance(session.totalDistance, unit: unitSystem),
                    label: String(localized: "common_distance")
                )
                statColumn(
                    value: Formatters.vertical(session.totalVertical, unit: unitSystem),
                    label: String(localized: "common_vertical")
                )
                statColumn(
                    value: Formatters.duration(session.duration),
                    label: String(localized: "common_time")
                )
                statColumn(
                    value: Formatters.speed(session.maxSpeed, unit: unitSystem),
                    label: String(localized: "session_card_stat_max")
                )
            }
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
