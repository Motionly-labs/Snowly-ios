//
//  GearZoneChecklistCard.swift
//  Snowly
//
//  Selected-zone checklist content for the visual checklist module.
//

import SwiftUI

struct GearZoneChecklistCard: View {
    let zone: BodyZone
    let gear: [GearAsset]
    let checkedGearIDs: Set<UUID>
    let onToggleGear: (GearAsset) -> Void

    private var checkedCount: Int {
        gear.filter { checkedGearIDs.contains($0.id) }.count
    }

    private var progress: Double {
        guard !gear.isEmpty else { return 0 }
        return Double(checkedCount) / Double(gear.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Label(zone.displayName, systemImage: zone.iconName)
                        .font(.headline)
                    Text("gear_zone_packed_count_format \(checkedCount) \(gear.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(zone.accentColor)
            }

            ProgressView(value: progress)
                .tint(zone.accentColor)

            VStack(spacing: Spacing.sm) {
                ForEach(gear) { item in
                    let isChecked = checkedGearIDs.contains(item.id)
                    Button {
                        onToggleGear(item)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isChecked ? ColorTokens.success : zone.accentColor.opacity(0.7))

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isChecked {
                                Text(String(localized: "gear_checklist_packed"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ColorTokens.success)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                                .fill(isChecked ? zone.accentColor.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.lg)
        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.xLarge, style: .continuous))
    }
}
