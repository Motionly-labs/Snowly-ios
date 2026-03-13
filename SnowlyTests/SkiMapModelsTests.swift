//
//  SkiMapModelsTests.swift
//  SnowlyTests
//
//  Tests for ski map data models, enum parsing, bounding box, and cache expiry.
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@MainActor
struct SkiMapModelsTests {

    // MARK: - PisteDifficulty

    @Test func pisteDifficulty_validValues() {
        #expect(PisteDifficulty(osmValue: "novice") == .novice)
        #expect(PisteDifficulty(osmValue: "easy") == .easy)
        #expect(PisteDifficulty(osmValue: "intermediate") == .intermediate)
        #expect(PisteDifficulty(osmValue: "advanced") == .advanced)
        #expect(PisteDifficulty(osmValue: "expert") == .expert)
        #expect(PisteDifficulty(osmValue: "freeride") == .freeride)
    }

    @Test func pisteDifficulty_caseInsensitive() {
        #expect(PisteDifficulty(osmValue: "EASY") == .easy)
        #expect(PisteDifficulty(osmValue: "Intermediate") == .intermediate)
    }

    @Test func pisteDifficulty_unknownValues() {
        #expect(PisteDifficulty(osmValue: nil) == .unknown)
        #expect(PisteDifficulty(osmValue: "") == .unknown)
        #expect(PisteDifficulty(osmValue: "extreme") == .unknown)
    }

    // MARK: - PisteType

    @Test func pisteType_validValues() {
        #expect(PisteType(osmValue: "downhill") == .downhill)
        #expect(PisteType(osmValue: "nordic") == .nordic)
        #expect(PisteType(osmValue: "skitour") == .skitour)
    }

    @Test func pisteType_unknownValues() {
        #expect(PisteType(osmValue: nil) == .unknown)
        #expect(PisteType(osmValue: "halfpipe") == .unknown)
    }

    // MARK: - AerialwayType

    @Test func aerialwayType_validValues() {
        #expect(AerialwayType(osmValue: "chair_lift") == .chairLift)
        #expect(AerialwayType(osmValue: "gondola") == .gondola)
        #expect(AerialwayType(osmValue: "cable_car") == .cableCar)
        #expect(AerialwayType(osmValue: "t-bar") == .tBar)
        #expect(AerialwayType(osmValue: "magic_carpet") == .magicCarpet)
    }

    @Test func aerialwayType_unknownValues() {
        #expect(AerialwayType(osmValue: nil) == .unknown)
        #expect(AerialwayType(osmValue: "funicular") == .unknown)
    }

    // MARK: - Coordinate

    @Test func coordinate_roundTrip() {
        let coord = Coordinate(latitude: 46.8182, longitude: 8.2275)
        #expect(coord.latitude == 46.8182)
        #expect(coord.longitude == 8.2275)

        let cl = coord.clLocationCoordinate2D
        #expect(cl.latitude == 46.8182)
        #expect(cl.longitude == 8.2275)
    }

    @Test func coordinate_fromCLLocationCoordinate2D() {
        let cl = CLLocationCoordinate2D(latitude: 50.1, longitude: -122.9)
        let coord = Coordinate(cl)
        #expect(coord.latitude == 50.1)
        #expect(coord.longitude == -122.9)
    }

    @Test func coordinate_codable() throws {
        let original = Coordinate(latitude: 46.0, longitude: 7.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Coordinate.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - BoundingBox

    @Test func boundingBox_aroundCenter() {
        let center = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)
        let bbox = BoundingBox.around(center: center, radiusMeters: 5000)

        #expect(bbox.south < 46.0)
        #expect(bbox.north > 46.0)
        #expect(bbox.west < 7.0)
        #expect(bbox.east > 7.0)
        // ~0.045 degrees per 5km at this latitude
        #expect(abs(bbox.north - bbox.south) > 0.08)
        #expect(abs(bbox.north - bbox.south) < 0.1)
    }

    @Test func boundingBox_overpassString() {
        let bbox = BoundingBox(south: 45.9, west: 6.9, north: 46.1, east: 7.1)
        let str = bbox.overpassBBoxString
        #expect(str == "45.9,6.9,46.1,7.1")
    }

    @Test func boundingBox_cacheKey_stableWithJitter() {
        let bbox1 = BoundingBox(south: 45.90011, west: 6.90011, north: 46.10011, east: 7.10011)
        let bbox2 = BoundingBox(south: 45.90014, west: 6.90014, north: 46.10014, east: 7.10014)
        // Rounded to 4 decimal places (~11m precision), so sub-meter jitter yields same key
        #expect(bbox1.cacheKey == bbox2.cacheKey)
    }

    @Test func boundingBox_cacheKey_differsByLocation() {
        let bbox1 = BoundingBox(south: 45.9, west: 6.9, north: 46.1, east: 7.1)
        let bbox2 = BoundingBox(south: 50.0, west: -122.0, north: 50.2, east: -121.8)
        #expect(bbox1.cacheKey != bbox2.cacheKey)
    }

    @Test func boundingBox_containsCoordinate() {
        let bbox = BoundingBox(south: 45.9, west: 6.9, north: 46.1, east: 7.1)
        #expect(bbox.contains(CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)))
        #expect(!bbox.contains(CLLocationCoordinate2D(latitude: 46.2, longitude: 7.0)))
        #expect(!bbox.contains(CLLocationCoordinate2D(latitude: 46.0, longitude: 7.2)))
    }

    @Test func boundingBox_approximateArea_positive() {
        let bbox = BoundingBox.around(
            center: CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0),
            radiusMeters: 5000
        )
        #expect(bbox.approximateAreaMetersSquared > 0)
    }

    // MARK: - SkiAreaData Expiry

    @Test func skiAreaData_notExpired_whenFresh() {
        let data = SkiAreaData(
            trails: [],
            lifts: [],
            fetchedAt: Date(),
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1)
        )
        #expect(!data.isExpired())
    }

    @Test func skiAreaData_expired_whenOld() {
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        let data = SkiAreaData(
            trails: [],
            lifts: [],
            fetchedAt: eightDaysAgo,
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1)
        )
        #expect(data.isExpired())
    }

    @Test func skiAreaData_customTTL() {
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        let data = SkiAreaData(
            trails: [],
            lifts: [],
            fetchedAt: twoHoursAgo,
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1)
        )
        // Not expired with 7-day default
        #expect(!data.isExpired())
        // Expired with 1-hour TTL
        #expect(data.isExpired(maxAge: 3600))
    }

    // MARK: - SkiTrail Codable

    @Test func skiTrail_codableRoundTrip() throws {
        let trail = SkiTrail(
            id: "12345",
            name: "Blue Run",
            difficulty: .easy,
            type: .downhill,
            coordinates: [
                Coordinate(latitude: 46.0, longitude: 7.0),
                Coordinate(latitude: 46.01, longitude: 7.01),
            ]
        )

        let data = try JSONEncoder().encode(trail)
        let decoded = try JSONDecoder().decode(SkiTrail.self, from: data)

        #expect(decoded.id == trail.id)
        #expect(decoded.name == trail.name)
        #expect(decoded.difficulty == trail.difficulty)
        #expect(decoded.type == trail.type)
        #expect(decoded.coordinates.count == 2)
    }

    // MARK: - SkiLift Codable

    @Test func skiLift_codableRoundTrip() throws {
        let lift = SkiLift(
            id: "67890",
            name: "Summit Express",
            liftType: .gondola,
            capacity: 2400,
            coordinates: [
                Coordinate(latitude: 46.0, longitude: 7.0),
                Coordinate(latitude: 46.02, longitude: 7.02),
            ]
        )

        let data = try JSONEncoder().encode(lift)
        let decoded = try JSONDecoder().decode(SkiLift.self, from: data)

        #expect(decoded.id == lift.id)
        #expect(decoded.name == lift.name)
        #expect(decoded.liftType == .gondola)
        #expect(decoded.capacity == 2400)
        #expect(decoded.coordinates.count == 2)
    }
}
