//
//  RouteMapView.swift
//  Snowly
//
//  Displays session routes on a satellite map.
//  Skiing segments are rainbow-colored; lift segments are thin dashed lines.
//

import SwiftUI
import MapKit

struct RouteSegment {
    let coordinates: [CLLocationCoordinate2D]
    let activityType: RunActivityType
}

struct RouteMapView: View {
    let session: SkiSession
    let height: CGFloat

    @State private var cachedSegments: [RouteSegment]?
    @State private var showingFullscreen = false

    init(session: SkiSession, height: CGFloat = 240) {
        self.session = session
        self.height = height
    }

    var body: some View {
        let segments = cachedSegments ?? Self.routeSegments(from: session)
        let region = Self.fittedRegion(for: segments) ?? Self.fallbackRegion(for: session)
        routeMap(segments: segments, region: region, interactive: false)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .snowlyGlass(in: Circle())
                    .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .onTapGesture { showingFullscreen = true }
            .task(id: session.id) {
                cachedSegments = Self.routeSegments(from: session)
            }
            .fullScreenCover(isPresented: $showingFullscreen) {
                FullscreenRouteMapView(
                    segments: segments,
                    region: region,
                    onDismiss: { showingFullscreen = false }
                )
            }
    }

    private func routeMap(
        segments: [RouteSegment],
        region: MKCoordinateRegion,
        interactive: Bool
    ) -> some View {
        let skiingIndices = segments.enumerated()
            .compactMap { $0.element.activityType == .skiing ? $0.offset : nil }
        let skiingOrder = Dictionary(
            uniqueKeysWithValues: skiingIndices.enumerated().map { order, segmentIndex in
                (segmentIndex, order)
            }
        )
        let skiingTotal = skiingIndices.count

        return Map(initialPosition: .region(region), interactionModes: interactive ? .all : []) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let style = Self.strokeStyle(for: segment.activityType)
                let skiIndex = skiingOrder[index] ?? 0
                let color: Color = switch segment.activityType {
                case .skiing:    RunColorPalette.color(forRunIndex: skiIndex, totalRuns: skiingTotal)
                case .lift: Self.liftStrokeColor
                case .walk:      Self.walkStrokeColor
                case .idle:      .clear
                }

                MapPolyline(coordinates: segment.coordinates)
                    .stroke(color, style: style)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .allowsHitTesting(interactive)
        .frame(height: interactive ? nil : height)
        .clipShape(RoundedRectangle(cornerRadius: interactive ? 0 : CornerRadius.large))
    }

    // MARK: - Pure Functions

    /// Extract route segments as coordinate arrays, preserving activity type.
    static func routeSegments(from session: SkiSession) -> [RouteSegment] {
        (session.runs ?? [])
            .filter {
                ($0.activityType == .skiing || $0.activityType == .lift || $0.activityType == .walk) && $0.trackData != nil
            }
            .sorted { $0.startDate < $1.startDate }
            .map { run in
                RouteSegment(
                    coordinates: run.trackPoints.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    },
                    activityType: run.activityType
                )
            }
            .filter { $0.coordinates.count >= 2 }
    }

    /// Extract skiing routes as coordinate arrays, filtering out non-skiing and short runs.
    static func skiingRoutes(from session: SkiSession) -> [[CLLocationCoordinate2D]] {
        routeSegments(from: session)
            .filter { $0.activityType == .skiing }
            .map(\.coordinates)
    }

    /// Compute a map region that fits all routes with 30% padding.
    /// Returns nil if no coordinates exist.
    static func fittedRegion(
        for segments: [RouteSegment]
    ) -> MKCoordinateRegion? {
        fittedRegion(for: segments.map(\.coordinates))
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

    static let liftStrokeColor = Color.white.opacity(0.82)
    static let walkStrokeColor = Color.secondary.opacity(0.6)

    static func strokeStyle(for activityType: RunActivityType) -> StrokeStyle {
        switch activityType {
        case .skiing:
            return StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
        case .lift:
            return StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round, dash: [3, 4])
        case .walk:
            return StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round, dash: [2, 3])
        case .idle:
            return StrokeStyle(lineWidth: 0)
        }
    }
}

// MARK: - Fullscreen

private struct FullscreenRouteMapView: View {
    let segments: [RouteSegment]
    let region: MKCoordinateRegion
    let onDismiss: () -> Void

    private var skiingOrder: [Int: Int] {
        let skiingIndices = segments.enumerated()
            .compactMap { $0.element.activityType == .skiing ? $0.offset : nil }
        return Dictionary(
            uniqueKeysWithValues: skiingIndices.enumerated().map { order, segmentIndex in
                (segmentIndex, order)
            }
        )
    }
    private var skiingTotal: Int {
        segments.filter { $0.activityType == .skiing }.count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(initialPosition: .region(region), interactionModes: .all) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let style = RouteMapView.strokeStyle(for: segment.activityType)
                    let skiIndex = skiingOrder[index] ?? 0
                    let color: Color = switch segment.activityType {
                    case .skiing:    RunColorPalette.color(forRunIndex: skiIndex, totalRuns: skiingTotal)
                    case .lift: RouteMapView.liftStrokeColor
                    case .walk:      RouteMapView.walkStrokeColor
                    case .idle:      .clear
                    }

                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(color, style: style)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .ignoresSafeArea()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(12)
                    .snowlyGlass(in: Circle())
            }
            .padding(.top, 56)
            .padding(.leading, Spacing.lg)
        }
    }
}
