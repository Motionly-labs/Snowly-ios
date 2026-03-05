//
//  OverpassServiceTests.swift
//  SnowlyTests
//
//  Tests for Overpass API JSON parsing logic.
//  Uses sample JSON fixtures to verify model mapping.
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@MainActor
struct OverpassServiceTests {

    // MARK: - JSON Fixtures

    /// Sample Overpass API response with one trail and one lift.
    private static let sampleResponse = """
    {
      "version": 0.6,
      "generator": "Overpass API",
      "osm3s": { "timestamp_osm_base": "2026-03-01T00:00:00Z" },
      "elements": [
        {
          "type": "way",
          "id": 100001,
          "tags": {
            "piste:type": "downhill",
            "piste:difficulty": "intermediate",
            "name": "Red Run Alpha"
          },
          "geometry": [
            { "lat": 46.800, "lon": 8.200 },
            { "lat": 46.801, "lon": 8.201 },
            { "lat": 46.802, "lon": 8.203 }
          ]
        },
        {
          "type": "way",
          "id": 100002,
          "tags": {
            "aerialway": "gondola",
            "aerialway:capacity": "2400",
            "name": "Summit Gondola"
          },
          "geometry": [
            { "lat": 46.810, "lon": 8.210 },
            { "lat": 46.815, "lon": 8.215 }
          ]
        },
        {
          "type": "way",
          "id": 100003,
          "tags": {
            "piste:type": "downhill",
            "piste:difficulty": "expert",
            "name": "Black Diamond"
          },
          "geometry": [
            { "lat": 46.820, "lon": 8.220 },
            { "lat": 46.825, "lon": 8.225 }
          ]
        },
        {
          "type": "way",
          "id": 100004,
          "tags": {
            "piste:type": "downhill"
          },
          "geometry": [
            { "lat": 46.830, "lon": 8.230 },
            { "lat": 46.835, "lon": 8.235 }
          ]
        },
        {
          "type": "node",
          "id": 200001,
          "tags": { "name": "Some Node" },
          "lat": 46.800,
          "lon": 8.200
        }
      ]
    }
    """.data(using: .utf8)!

    /// Sample Overpass response for nearby ski areas (relations with center).
    private static let nearbyAreasResponse = """
    {
      "elements": [
        {
          "type": "relation",
          "id": 9001,
          "tags": {
            "landuse": "winter_sports",
            "name": "Zermatt"
          },
          "center": { "lat": 46.0207, "lon": 7.7491 }
        },
        {
          "type": "relation",
          "id": 9002,
          "tags": {
            "landuse": "winter_sports",
            "name": "Verbier"
          },
          "center": { "lat": 46.0960, "lon": 7.2265 }
        },
        {
          "type": "relation",
          "id": 9003,
          "tags": {
            "landuse": "winter_sports"
          },
          "center": { "lat": 46.3000, "lon": 7.5000 }
        },
        {
          "type": "relation",
          "id": 9004,
          "tags": {
            "landuse": "winter_sports",
            "name": "No Center Resort"
          }
        }
      ]
    }
    """.data(using: .utf8)!

    // MARK: - Parsing Tests

    @Test func parseResponse_extractsTrailsAndLifts() throws {
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        )

        #expect(result.trails.count == 3)
        #expect(result.lifts.count == 1)
    }

    @Test func parseResponse_trailFields() throws {
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        )

        let redRun = result.trails.first { $0.name == "Red Run Alpha" }
        #expect(redRun != nil)
        #expect(redRun?.id == "100001")
        #expect(redRun?.difficulty == .intermediate)
        #expect(redRun?.type == .downhill)
        #expect(redRun?.coordinates.count == 3)
    }

    @Test func parseResponse_liftFields() throws {
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        )

        let gondola = result.lifts.first
        #expect(gondola != nil)
        #expect(gondola?.id == "100002")
        #expect(gondola?.name == "Summit Gondola")
        #expect(gondola?.liftType == .gondola)
        #expect(gondola?.capacity == 2400)
        #expect(gondola?.coordinates.count == 2)
    }

    @Test func parseResponse_trailWithoutName() throws {
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        )

        let unnamed = result.trails.first { $0.id == "100004" }
        #expect(unnamed != nil)
        #expect(unnamed?.name == nil)
        #expect(unnamed?.difficulty == .unknown) // No piste:difficulty tag
    }

    @Test func parseResponse_ignoresNodes() throws {
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        )

        // Node 200001 should not appear in trails or lifts
        let total = result.trails.count + result.lifts.count
        #expect(total == 4) // 3 trails + 1 lift, not 5
    }

    @Test func parseResponse_setsMetadata() throws {
        let bbox = BoundingBox(south: 46.0, west: 8.0, north: 47.0, east: 9.0)
        let result = try OverpassResponseParser.parse(
            data: Self.sampleResponse,
            boundingBox: bbox
        )

        #expect(result.boundingBox == bbox)
        // fetchedAt should be recent
        #expect(Date().timeIntervalSince(result.fetchedAt) < 5)
    }

    @Test func parseResponse_emptyElements() throws {
        let json = """
        { "version": 0.6, "elements": [] }
        """.data(using: .utf8)!

        let result = try OverpassResponseParser.parse(
            data: json,
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1)
        )

        #expect(result.trails.isEmpty)
        #expect(result.lifts.isEmpty)
    }

    @Test func parseResponse_invalidJSON_throws() {
        let badJSON = "not json".data(using: .utf8)!

        #expect(throws: OverpassError.self) {
            try OverpassResponseParser.parse(
                data: badJSON,
                boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1)
            )
        }
    }

    // MARK: - Nearby Area Parsing Tests

    @Test func parseNearbyAreas_extractsValidRelationsOnly() throws {
        let result = try OverpassResponseParser.parseNearbyAreas(
            data: Self.nearbyAreasResponse,
            origin: CLLocationCoordinate2D(latitude: 46.02, longitude: 7.75),
            limit: 10,
            recommendedRadiusMeters: 6000
        )

        #expect(result.count == 2)
        #expect(result.contains(where: { $0.name == "Zermatt" }))
        #expect(result.contains(where: { $0.name == "Verbier" }))
    }

    @Test func parseNearbyAreas_sortedByDistanceAndLimited() throws {
        let result = try OverpassResponseParser.parseNearbyAreas(
            data: Self.nearbyAreasResponse,
            origin: CLLocationCoordinate2D(latitude: 46.0208, longitude: 7.7490),
            limit: 1,
            recommendedRadiusMeters: 6000
        )

        #expect(result.count == 1)
        #expect(result.first?.name == "Zermatt")
        #expect(result.first?.recommendedRadiusMeters == 6000)
    }
}
