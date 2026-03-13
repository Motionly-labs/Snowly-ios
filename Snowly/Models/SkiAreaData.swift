//
//  SkiAreaData.swift
//  Snowly
//
//  Aggregated ski area data with cache metadata.
//  Supporting types: Coordinate, BoundingBox.
//

import Foundation
import CoreLocation

// MARK: - Coordinate

/// Codable wrapper for a geographic coordinate.
struct Coordinate: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - Bounding Box

/// Geographic bounding box for Overpass API queries.
struct BoundingBox: Codable, Sendable, Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    /// Create a bounding box centered on a coordinate with a given radius in meters.
    static func around(
        center: CLLocationCoordinate2D,
        radiusMeters: Double = 5000
    ) -> BoundingBox {
        // Approximate degrees per meter at this latitude
        let latDelta = radiusMeters / 111_320.0
        let metersPerLongitudeDegree = max(
            1e-6,
            111_320.0 * abs(cos(center.latitude * .pi / 180.0))
        )
        let lonDelta = radiusMeters / metersPerLongitudeDegree

        return BoundingBox(
            south: center.latitude - latDelta,
            west: center.longitude - lonDelta,
            north: center.latitude + latDelta,
            east: center.longitude + lonDelta
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= south &&
            coordinate.latitude <= north &&
            coordinate.longitude >= west &&
            coordinate.longitude <= east
    }

    /// Approximate 2D area in square meters, used for deterministic tie-breaking.
    var approximateAreaMetersSquared: Double {
        let centerLat = (south + north) / 2.0
        let latMeters = max(0, north - south) * 111_320.0
        let lonMeters = max(0, east - west) * 111_320.0 * abs(cos(centerLat * .pi / 180.0))
        return latMeters * lonMeters
    }

    /// String for Overpass QL bbox parameter: "south,west,north,east".
    var overpassBBoxString: String {
        "\(south),\(west),\(north),\(east)"
    }

    /// Stable hash for use as a cache key.
    /// Rounds to ~11m precision (4 decimal places) to avoid cache misses from GPS jitter.
    var cacheKey: String {
        String(format: "%.4f_%.4f_%.4f_%.4f", south, west, north, east)
    }

    /// Geographic midpoint of the bounding box.
    var center: Coordinate {
        Coordinate(
            latitude: (south + north) / 2.0,
            longitude: (west + east) / 2.0
        )
    }
}

// MARK: - Ski Area Data

/// Aggregated ski area data for a bounding box region.
struct SkiAreaData: Codable, Sendable {
    let trails: [SkiTrail]
    let lifts: [SkiLift]
    let fetchedAt: Date
    let boundingBox: BoundingBox
    var name: String? = nil

    /// Whether this cached data has expired.
    func isExpired(maxAge: TimeInterval = 7 * 24 * 3600) -> Bool {
        Date().timeIntervalSince(fetchedAt) > maxAge
    }
}
