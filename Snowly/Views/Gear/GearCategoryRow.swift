//
//  GearCategoryRow.swift
//  Snowly
//
//  Zone detail card shown when a body zone is selected.
//  Displays zone icon, name, progress, and item checklist.
//

import SwiftUI

struct GearCategoryRow: View {
    let zone: BodyZone
    let items: [GearItem]
    let isEditing: Bool
    let onToggleItem: (GearItem) -> Void
    var onAddItem: (() -> Void)?

    private var checkedCount: Int {
        items.filter(\.isChecked).count
    }

    private var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(checkedCount) / Double(items.count)
    }

    private var isComplete: Bool {
        !items.isEmpty && items.allSatisfy(\.isChecked)
    }

    private var barColor: Color {
        isComplete ? .green : zone.accentColor
    }

    private var readyCountText: String {
        let format = String(localized: "gear_category_ready_count_format")
        return String(format: format, locale: Locale.current, Int64(checkedCount), Int64(items.count))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(barColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: zone.iconName)
                        .font(.title3)
                        .foregroundStyle(barColor)
                }

                // Zone name + count
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.displayName)
                        .font(.headline)

                    if !items.isEmpty {
                        Text(readyCountText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(String(localized: "gear_category_no_items"))
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }

                Spacer()

                // Percentage
                if !items.isEmpty {
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.bold())
                        .foregroundStyle(barColor)
                }
            }
            .padding(16)

            // Progress bar
            if !items.isEmpty {
                ProgressView(value: progress)
                    .tint(barColor)
                    .padding(.horizontal, 16)
            }

            // Item list
            if !items.isEmpty {
                VStack(spacing: 0) {
                    let sortedItems = items.sorted { $0.sortOrder < $1.sortOrder }
                    ForEach(sortedItems) { item in
                        if isEditing {
                            HStack(spacing: 12) {
                                Text(item.name)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        } else {
                            GearItemRow(item: item, onToggle: { onToggleItem(item) })
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        if item.id != sortedItems.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }

            // Add item button
            if let onAddItem {
                Divider()
                    .padding(.horizontal, 16)

                Button(action: onAddItem) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(zone.accentColor.opacity(0.6))
                        Text(String(localized: "gear_category_add_item"))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            Spacer().frame(height: 8)
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 16))
    }
}
