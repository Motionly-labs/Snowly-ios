//
//  SkierFigureView.swift
//  Snowly
//
//  Interactive skier figure for the visual checklist.
//

import SwiftUI

struct SkierFigureView: View {
    let gear: [GearAsset]
    let checkedGearIDs: Set<UUID>
    let selectedZone: BodyZone?
    let onZoneTap: (BodyZone) -> Void

    @State private var maskRenderer: SkierMaskRenderer?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let glowRadius = max(6, min(size.width, size.height) * 0.02)

            ZStack {
                Image(SkierMaskRenderer.displayAssetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .allowsHitTesting(false)

                if let maskRenderer {
                    ForEach(BodyZone.allCases) { zone in
                        if let mask = maskRenderer.zoneMasks[zone] {
                            Rectangle()
                                .fill(zone.fillColor(
                                    in: gear,
                                    checkedGearIDs: checkedGearIDs,
                                    isSelected: selectedZone == zone
                                ))
                                .mask(
                                    Image(uiImage: mask)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                )
                                .shadow(
                                    color: (selectedZone == zone ? zone.accentColor : .clear).opacity(0.45),
                                    radius: selectedZone == zone ? glowRadius : 0
                                )
                        }
                    }
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalizedPoint = CGPoint(
                            x: location.x / size.width,
                            y: location.y / size.height
                        )
                        if let zone = maskRenderer?.zone(atNormalized: normalizedPoint) {
                            onZoneTap(zone)
                        }
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            if maskRenderer == nil {
                maskRenderer = SkierMaskRenderer()
            }
        }
    }
}
