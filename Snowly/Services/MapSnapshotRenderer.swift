//
//  MapSnapshotRenderer.swift
//  Snowly
//
//  Renders a satellite map snapshot with session route polylines
//  using MKMapSnapshotter + Core Graphics.
//

import MapKit
import SwiftUI
import UIKit
import os

enum MapSnapshotRenderer {

    private static let logger = Logger(subsystem: "com.Snowly", category: "MapSnapshotRenderer")

    /// Renders a satellite map snapshot with pre-styled session segments drawn on top.
    /// Accepts pre-extracted segment arrays (no SwiftData model references)
    /// to avoid EXC_BAD_ACCESS across async boundaries.
    static func render(
        segments: [RouteSegment],
        size: CGSize = CGSize(width: 1080, height: 600),
        scale: CGFloat = 1.0
    ) async -> UIImage? {
        guard let region = RouteMapView.fittedRegion(for: segments) else {
            logger.warning("No routes to render map snapshot")
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .hybrid
        options.scale = scale

        let snapshotter = MKMapSnapshotter(options: options)

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            logger.error("Map snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let cgContext = context.cgContext
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)

            let skiingIndices = segments.enumerated()
                .compactMap { $0.element.activityType == .skiing ? $0.offset : nil }
            let skiingOrder = Dictionary(
                uniqueKeysWithValues: skiingIndices.enumerated().map { order, segmentIndex in
                    (segmentIndex, order)
                }
            )
            let skiingTotal = skiingIndices.count

            for (index, segment) in segments.enumerated() {
                guard segment.coordinates.count >= 2 else { continue }

                let style = RouteMapView.strokeStyle(for: segment.activityType)
                guard style.lineWidth > 0 else { continue }

                cgContext.setLineWidth(style.lineWidth)
                cgContext.setLineDash(phase: 0, lengths: style.dash)

                let color: UIColor
                if segment.activityType == .skiing {
                    let skiIndex = skiingOrder[index] ?? 0
                    color = UIColor(RunColorPalette.color(forRunIndex: skiIndex, totalRuns: skiingTotal))
                } else {
                    color = UIColor(RouteMapView.liftStrokeColor)
                }
                cgContext.setStrokeColor(color.cgColor)

                let points = segment.coordinates.map { snapshot.point(for: $0) }
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
