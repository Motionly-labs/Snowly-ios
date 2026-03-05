//
//  ZoneStatusBar.swift
//  Snowly
//
//  Horizontal row of dots indicating zone completion status.
//  Tappable to switch between body zones.
//

import SwiftUI

struct ZoneStatusBar: View {
    let setup: GearSetup
    let selectedZone: BodyZone?
    let onZoneTap: (BodyZone) -> Void

    /// Only show dots for zones that have items.
    private var activeZones: [BodyZone] {
        BodyZone.allCases.filter { !$0.items(from: setup).isEmpty }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(activeZones) { zone in
                dotView(for: zone)
                    .onTapGesture { onZoneTap(zone) }
            }
        }
    }

    private func dotView(for zone: BodyZone) -> some View {
        let isComplete = zone.isComplete(from: setup)
        let isSelected = selectedZone == zone

        let color: Color = if isComplete {
            .green
        } else if isSelected {
            zone.accentColor
        } else {
            Color.secondary
        }

        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isSelected ? 1.4 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    let setup = GearSetup(name: "Preview")
    ZoneStatusBar(
        setup: setup,
        selectedZone: .body,
        onZoneTap: { _ in }
    )
    .padding()
}
