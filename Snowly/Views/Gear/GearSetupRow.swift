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
        HStack(spacing: Spacing.md) {
            // Progress circle
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: setup.progress)
                    .stroke(
                        setup.isComplete ? ColorTokens.success : Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                if setup.isComplete {
                    Image(systemName: "checkmark")
                        .font(Typography.iconBold)
                        .foregroundStyle(ColorTokens.success)
                } else {
                    Text("\(Int(setup.progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(setup.name)
                    .font(.headline)

                HStack(spacing: Spacing.sm) {
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
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.accentColor.opacity(Opacity.gentle))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
