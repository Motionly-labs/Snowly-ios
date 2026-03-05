//
//  MapSnapshotRenderer.swift
//  Snowly
//
//  Renders a satellite map snapshot with skiing route polylines
//  using MKMapSnapshotter + Core Graphics.
//

import MapKit
import SwiftUI
import UIKit
import os

enum MapSnapshotRenderer {

    private static let logger = Logger(subsystem: "com.Snowly", category: "MapSnapshotRenderer")

    /// Renders a satellite map snapshot with skiing routes drawn on top.
    /// Accepts pre-extracted coordinate arrays (no SwiftData model references)
    /// to avoid EXC_BAD_ACCESS across async boundaries.
    static func render(
        routes: [[CLLocationCoordinate2D]],
        size: CGSize = CGSize(width: 1080, height: 600)
    ) async -> UIImage? {
        guard let region = RouteMapView.fittedRegion(for: routes) else {
            logger.warning("No routes to render map snapshot")
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .hybrid
        options.scale = 1.0

        let snapshotter = MKMapSnapshotter(options: options)

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            logger.error("Map snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let cgContext = context.cgContext
            cgContext.setLineWidth(3.0)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)

            let strokeColor = UIColor(ColorTokens.brandWarmOrange)
            cgContext.setStrokeColor(strokeColor.cgColor)

            for route in routes {
                guard route.count >= 2 else { continue }

                let points = route.map { snapshot.point(for: $0) }
                cgContext.beginPath()
                cgContext.move(to: points[0])
                for point in points.dropFirst() {
                    cgContext.addLine(to: point)
                }
                cgContext.strokePath()
            }
        }
    }
}
