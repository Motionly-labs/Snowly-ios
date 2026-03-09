//
//  RouteMapViewTests.swift
//  SnowlyTests
//
//  Tests for RouteMapView pure functions.
//

import Testing
import CoreLocation
import MapKit
@testable import Snowly

@Suite("RouteMapView")
struct RouteMapViewTests {

    // MARK: - Helpers

    private func makeTrackData(
        coordinates: [(lat: Double, lon: Double)]
    ) -> Data? {
        let points = coordinates.map { coord in
            TrackPoint(
                timestamp: Date(),
                latitude: coord.lat,
                longitude: coord.lon,
                altitude: 2000,
                speed: 10,
                accuracy: 5,
                course: 0
            )
        }
        return try? JSONEncoder().encode(points)
    }

    private func makeRun(
        activityType: RunActivityType = .skiing,
        coordinates: [(lat: Double, lon: Double)] = [(46.0, 7.0), (46.01, 7.01)],
        startDate: Date = Date()
    ) -> SkiRun {
        SkiRun(
            startDate: startDate,
            activityType: activityType,
            trackData: makeTrackData(coordinates: coordinates)
        )
    }

    private func makeSession(runs: [SkiRun]) -> SkiSession {
        let session = SkiSession()
        session.runs = runs
        return session
    }

    // MARK: - skiingRoutes

    @Test("Only includes skiing runs, excludes lift and idle")
    func skiingRoutesFiltersActivityType() {
        let session = makeSession(runs: [
            makeRun(activityType: .skiing),
            makeRun(activityType: .lift),
            makeRun(activityType: .idle),
            makeRun(activityType: .skiing),
        ])

        let routes = RouteMapView.skiingRoutes(from: session)
        #expect(routes.count == 2)
    }

    @Test("Filters runs with fewer than 2 track points")
    func skiingRoutesFiltersShortRuns() {
        let session = makeSession(runs: [
            makeRun(coordinates: [(46.0, 7.0)]),   // 1 point — filtered
            makeRun(coordinates: [(46.0, 7.0), (46.01, 7.01)]),  // 2 points — kept
        ])

        let routes = RouteMapView.skiingRoutes(from: session)
        #expect(routes.count == 1)
        #expect(routes.first?.count == 2)
    }

    @Test("Empty session returns empty array")
    func skiingRoutesEmptySession() {
        let session = makeSession(runs: [])
        let routes = RouteMapView.skiingRoutes(from: session)
        #expect(routes.isEmpty)
    }

    // MARK: - fittedRegion

    @Test("Center is bounding box midpoint")
    func fittedRegionCenter() {
        let routes: [[CLLocationCoordinate2D]] = [
            [
                CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
                CLLocationCoordinate2D(latitude: 46.1, longitude: 7.2),
            ]
        ]

        let region = RouteMapView.fittedRegion(for: routes)
        #expect(region != nil)
        #expect(abs(region!.center.latitude - 46.05) < 0.001)
        #expect(abs(region!.center.longitude - 7.1) < 0.001)
    }

    @Test("Span includes 30% padding")
    func fittedRegionPadding() {
        let routes: [[CLLocationCoordinate2D]] = [
            [
                CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
                CLLocationCoordinate2D(latitude: 46.1, longitude: 7.1),
            ]
        ]

        let region = RouteMapView.fittedRegion(for: routes)!
        let expectedLatSpan = 0.1 * 1.3
        let expectedLonSpan = 0.1 * 1.3
        #expect(abs(region.span.latitudeDelta - expectedLatSpan) < 0.001)
        #expect(abs(region.span.longitudeDelta - expectedLonSpan) < 0.001)
    }

    @Test("Empty input returns nil")
    func fittedRegionEmpty() {
        let region = RouteMapView.fittedRegion(for: [] as [[CLLocationCoordinate2D]])
        #expect(region == nil)
    }

    @Test("Minimum span prevents tiny regions")
    func fittedRegionMinSpan() {
        let routes: [[CLLocationCoordinate2D]] = [
            [
                CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
                CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
            ]
        ]

        let region = RouteMapView.fittedRegion(for: routes)!
        #expect(region.span.latitudeDelta >= 0.002)
        #expect(region.span.longitudeDelta >= 0.002)
    }
}
