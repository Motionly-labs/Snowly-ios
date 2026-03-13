//
//  ZoneStatusBar.swift
//  Snowly
//
//  Horizontal zone selector for the visual checklist.
//

import SwiftUI

struct ZoneStatusBar: View {
    let gear: [GearAsset]
    let checkedGearIDs: Set<UUID>
    let selectedZone: BodyZone?
    let onZoneTap: (BodyZone) -> Void

    private var activeZones: [BodyZone] {
        BodyZone.allCases.filter { !$0.gear(from: gear).isEmpty }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(activeZones) { zone in
                    zoneChip(for: zone)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func zoneChip(for zone: BodyZone) -> some View {
        let zoneGear = zone.gear(from: gear)
        let checkedCount = zone.checkedCount(in: gear, checkedGearIDs: checkedGearIDs)
        let isSelected = selectedZone == zone
        let isComplete = zone.isComplete(in: gear, checkedGearIDs: checkedGearIDs)
        let accent = isComplete ? ColorTokens.success : zone.accentColor

        return Button {
            onZoneTap(zone)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: zone.iconName)
                Text(zone.displayName)
                Text("\(checkedCount)/\(zoneGear.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? accent.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(accent.opacity(isSelected ? 0.45 : 0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
