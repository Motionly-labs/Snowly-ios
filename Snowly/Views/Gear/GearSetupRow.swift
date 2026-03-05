//
//  GearSetupRow.swift
//  Snowly
//
//  A row displaying a gear setup with name, item count, and progress.
//

import SwiftUI

struct GearSetupRow: View {
    let setup: GearSetup

    private var itemCountText: String {
        let format = String(localized: "gear_setup_items_count_format")
        return String(format: format, locale: Locale.current, Int64(setup.items.count))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Progress circle
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: setup.progress)
                    .stroke(
                        setup.isComplete ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                if setup.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(Int(setup.progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(setup.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    if !setup.brand.isEmpty {
                        Text(setup.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(itemCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if setup.isActive {
                Text(String(localized: "common_active"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
