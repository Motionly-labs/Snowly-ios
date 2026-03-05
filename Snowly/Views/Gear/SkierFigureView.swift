//
//  SkierFigureView.swift
//  Snowly
//
//  Interactive skier figure rendered from asset-backed SVG resources.
//

import SwiftData
import SwiftUI

struct SkierFigureView: View {
    let setup: GearSetup
    let selectedZone: BodyZone?
    let onZoneTap: (BodyZone) -> Void

    /// Renderer loaded asynchronously to avoid blocking the main thread.
    @State private var maskRenderer: SkierMaskRenderer?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                displayLayer
                if maskRenderer != nil {
                    zoneOverlays(glowRadius: max(5.0, side * 0.02))
                }
                tapCaptureLayer(size: geo.size)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .task {
            if maskRenderer == nil {
                maskRenderer = SkierMaskRenderer()
            }
        }
    }

    // MARK: - Layer 1: Display Image

    private var displayLayer: some View {
        Image(SkierMaskRenderer.displayAssetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .allowsHitTesting(false)
    }

    // MARK: - Layer 2: Zone Overlays

    private func zoneOverlays(glowRadius: CGFloat) -> some View {
        ForEach(BodyZone.allCases) { zone in
            zoneOverlay(for: zone, glowRadius: glowRadius)
        }
        .allowsHitTesting(false)
    }

    private func zoneOverlay(for zone: BodyZone, glowRadius: CGFloat) -> some View {
        Group {
            if let maskImage = maskRenderer?.zoneMasks[zone] {
                let isSelected = selectedZone == zone
                let colors = zone.shapeColors(from: setup, isSelected: isSelected)
                let active = zone.resolvedColor(from: setup)

                Rectangle()
                    .fill(isSelected ? active.opacity(0.24) : colors.fill)
                    .mask(
                        Image(uiImage: maskImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
                    .shadow(
                        color: isSelected ? active.opacity(0.42) : .clear,
                        radius: isSelected ? glowRadius : 0
                    )
            }
        }
    }

    // MARK: - Layer 3: Tap Capture

    private func tapCaptureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalized = CGPoint(
                    x: location.x / size.width,
                    y: location.y / size.height
                )
                if let zone = maskRenderer?.zone(atNormalized: normalized) {
                    onZoneTap(zone)
                }
            }
    }
}

#Preview {
    let setup = GearSetup(name: "Preview")
    SkierFigureView(
        setup: setup,
        selectedZone: .head,
        onZoneTap: { _ in }
    )
    .padding()
    .background(Color(.systemBackground))
    .modelContainer(for: [GearSetup.self, GearItem.self], inMemory: true)
}
