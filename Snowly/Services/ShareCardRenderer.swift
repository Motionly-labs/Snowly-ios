//
//  ShareCardRenderer.swift
//  Snowly
//
//  Renders a 1080x1920 share card image from session data.
//  Uses MKMapSnapshotter for route map + SwiftUI ImageRenderer.
//
//  IMPORTANT: All SwiftData model values must be extracted before
//  any async suspension point to avoid EXC_BAD_ACCESS.
//

import SwiftUI
import MapKit

enum ShareCardRenderer {

    /// Renders a session summary into a shareable image.
    /// Extracts all SwiftData values synchronously, then performs async map rendering.
    @MainActor
    static func render(
        session: SkiSession,
        resortName: String?,
        unitSystem: UnitSystem,
        avatarData: Data?,
        displayName: String
    ) async -> UIImage? {
        // Extract route data from SwiftData models BEFORE any async work
        let routes = RouteMapView.skiingRoutes(from: session)

        // Snapshot all session values into local copies
        let sessionMaxSpeed = session.maxSpeed
        let sessionRunCount = session.runCount
        let sessionTotalDistance = session.totalDistance
        let sessionTotalVertical = session.totalVertical
        let sessionDuration = session.duration
        let sessionStartDate = session.startDate

        // Now safe to do async work — no more SwiftData model access
        let mapImage = await MapSnapshotRenderer.render(routes: routes)

        let view = ShareCardView(
            maxSpeed: sessionMaxSpeed,
            runCount: sessionRunCount,
            totalDistance: sessionTotalDistance,
            totalVertical: sessionTotalVertical,
            duration: sessionDuration,
            startDate: sessionStartDate,
            resortName: resortName,
            unitSystem: unitSystem,
            avatarData: avatarData,
            displayName: displayName,
            mapImage: mapImage
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        return renderer.uiImage
    }
}
