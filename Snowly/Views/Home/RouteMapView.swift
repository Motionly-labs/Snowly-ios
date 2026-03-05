//
//  RouteMapView.swift
//  Snowly
//
//  Displays skiing routes on a satellite map.
//  Only shows skiing segments, ignores chairlift and idle.
//

import SwiftUI
import MapKit

struct RouteMapView: View {
    let session: SkiSession
    let height: CGFloat

    @State private var cachedRoutes: [[CLLocationCoordinate2D]]?

    init(session: SkiSession, height: CGFloat = 240) {
        self.session = session
        self.height = height
    }

    var body: some View {
        let routes = cachedRoutes ?? Self.skiingRoutes(from: session)
        let region = Self.fittedRegion(for: routes) ?? Self.fallbackRegion(for: session)
        routeMap(routes: routes, region: region)
            .task(id: session.id) {
                cachedRoutes = Self.skiingRoutes(from: session)
            }
    }

    private func routeMap(
        routes: [[CLLocationCoordinate2D]],
        region: MKCoordinateRegion
    ) -> some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(Array(routes.enumerated()), id: \.offset) { index, coords in
                MapPolyline(coordinates: coords)
                    .stroke(
                        Self.strokeColor(index: index, total: routes.count),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .allowsHitTesting(false)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    // MARK: - Pure Functions

    /// Extract skiing routes as coordinate arrays, filtering out non-skiing and short runs.
    static func skiingRoutes(from session: SkiSession) -> [[CLLocationCoordinate2D]] {
        session.runs
            .filter { $0.activityType == .skiing && $0.trackData != nil }
            .sorted { $0.startDate < $1.startDate }
            .map { run in
                run.trackPoints.map { $0.clLocation.coordinate }
            }
            .filter { $0.count >= 2 }
    }

    /// Compute a map region that fits all routes with 30% padding.
    /// Returns nil if no coordinates exist.
    static func fittedRegion(
        for routes: [[CLLocationCoordinate2D]]
    ) -> MKCoordinateRegion? {
        let allCoords = routes.flatMap { $0 }
        guard !allCoords.isEmpty else { return nil }

        let minLat = allCoords.map(\.latitude).min()!
        let maxLat = allCoords.map(\.latitude).max()!
        let minLon = allCoords.map(\.longitude).min()!
        let maxLon = allCoords.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let padding = 1.3
        let minSpan = 0.002

        let latSpan = max((maxLat - minLat) * padding, minSpan)
        let lonSpan = max((maxLon - minLon) * padding, minSpan)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// Fallback region when no route coordinates exist.
    /// Centers on the session's resort, or a default span if no resort.
    static func fallbackRegion(for session: SkiSession) -> MKCoordinateRegion {
        let center: CLLocationCoordinate2D
        if let resort = session.resort {
            center = CLLocationCoordinate2D(latitude: resort.latitude, longitude: resort.longitude)
        } else {
            // Default: Zermatt, Switzerland
            center = CLLocationCoordinate2D(latitude: 46.0207, longitude: 7.7491)
        }
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    /// Stroke color for a route based on its position in the time sequence.
    /// Single run uses brand orange; multiple runs fade from 0.5 to 1.0 opacity.
    static func strokeColor(index: Int, total: Int) -> Color {
        guard total > 1 else {
            return ColorTokens.brandWarmOrange
        }
        let opacity = 0.5 + 0.5 * Double(index) / Double(total - 1)
        return ColorTokens.brandWarmOrange.opacity(opacity)
    }
}
