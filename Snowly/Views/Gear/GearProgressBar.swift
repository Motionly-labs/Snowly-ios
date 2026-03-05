//
//  GearProgressBar.swift
//  Snowly
//
//  Visual progress indicator for gear checklist completion.
//

import SwiftUI

struct GearProgressBar: View {
    let progress: Double
    let itemCount: Int

    private var itemTotalText: String {
        let format = String(localized: "gear_progress_item_total_format")
        return String(format: format, locale: Locale.current, Int64(itemCount))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(statusText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(progressColor)
            }

            ProgressView(value: progress)
                .tint(progressColor)

            Text(itemTotalText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if progress >= 1.0 { return String(localized: "gear_progress_status_all_packed") }
        if progress >= 0.5 { return String(localized: "gear_progress_status_almost_there") }
        if progress > 0 { return String(localized: "gear_progress_status_getting_ready") }
        return String(localized: "gear_progress_status_not_started")
    }

    private var progressColor: Color {
        if progress >= 1.0 { return .green }
        if progress >= 0.5 { return .accentColor }
        return .gray
    }
}
