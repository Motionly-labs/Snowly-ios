//
//  OverpassService.swift
//  Snowly
//
//  Fetches ski trail and lift data from the Overpass API (OpenStreetMap).
//  Parses raw OSM JSON into SkiTrail / SkiLift models.
//

import Foundation
import CoreLocation
import os

struct NearbySkiArea: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let center: Coordinate
    let distanceMeters: Double
    let recommendedRadiusMeters: Double
    let bounds: BoundingBox?
}

// MARK: - Overpass Error

enum OverpassError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case noData
    case decodingFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Overpass API URL"
        case .httpError(let code):
            return "Overpass API returned HTTP \(code)"
        case .noData:
            return "No data returned from Overpass API"
        case .decodingFailed(let detail):
            return "Failed to parse Overpass response: \(detail)"
        case .timeout:
            return "Overpass API request timed out"
        }
    }
}

// MARK: - Overpass Service

@MainActor
final class OverpassService {

    private(set) var isLoading = false
    private(set) var lastError: String?

    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]
    private static let queryTimeout: Int = 25
    private static let networkTimeout: TimeInterval = 35
    private static let defaultAreaRadiusMeters: Double = 6000

    private static let logger = Logger(subsystem: "com.Snowly", category: "Overpass")

    /// Fetch ski trails and lifts within a bounding box.
    func fetchSkiArea(boundingBox bbox: BoundingBox) async throws -> SkiAreaData {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let query = Self.buildSkiAreaQuery(bbox: bbox)

        do {
            let data = try await executeWithFallback(query)
            return try OverpassResponseParser.parse(data: data, boundingBox: bbox)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Search nearby ski areas (winter_sports relations) around a coordinate.
    func searchNearbySkiAreas(
        center: CLLocationCoordinate2D,
        radiusMeters: Double = 30_000,
        limit: Int = 10
    ) async throws -> [NearbySkiArea] {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let query = Self.buildNearbyAreasQuery(center: center, radiusMeters: radiusMeters)

        do {
            let data = try await executeWithFallback(query)
            return try OverpassResponseParser.parseNearbyAreas(
                data: data,
                origin: center,
                limit: limit,
                recommendedRadiusMeters: Self.defaultAreaRadiusMeters
            )
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Query Building

    private static func buildSkiAreaQuery(bbox: BoundingBox) -> String {
        let b = bbox.overpassBBoxString
        return "[out:json][timeout:\(queryTimeout)];" +
            "(way[\"piste:type\"=\"downhill\"](\(b));" +
            "way[\"aerialway\"](\(b));" +
            "relation[\"landuse\"=\"winter_sports\"](\(b)););" +
            "out body geom;"
    }

    /// Query relations only — ski resorts in OSM are mapped as relations.
    /// Way-scoped `around` queries are orders of magnitude slower and return nothing useful.
    private static func buildNearbyAreasQuery(
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> String {
        let r = max(1000, Int(radiusMeters.rounded()))
        let lat = center.latitude
        let lon = center.longitude
        return "[out:json][timeout:\(queryTimeout)];" +
            "(relation[\"landuse\"=\"winter_sports\"][\"name\"](around:\(r),\(lat),\(lon));" +
            "relation[\"site\"=\"piste\"][\"name\"](around:\(r),\(lat),\(lon));" +
            "relation[\"leisure\"=\"ski_resort\"][\"name\"](around:\(r),\(lat),\(lon)););" +
            "out tags center bb;"
    }

    // MARK: - Network

    /// Try each endpoint in order. Abort immediately on cancellation or timeout
    /// (retrying a different server won't help).
    private func executeWithFallback(_ query: String) async throws -> Data {
        var lastError: Error?

        for endpoint in Self.endpoints {
            try Task.checkCancellation()

            do {
                return try await executeQuery(query, endpoint: endpoint)
            } catch is CancellationError {
                throw CancellationError()
            } catch OverpassError.timeout {
                throw OverpassError.timeout
            } catch {
                Self.logger.warning("Overpass endpoint failed: \(endpoint, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }

        throw lastError ?? OverpassError.noData
    }

    private func executeQuery(_ query: String, endpoint: String) async throws -> Data {
        try Task.checkCancellation()

        guard let url = URL(string: endpoint) else {
            throw OverpassError.invalidURL
        }

        // Build form body using URLComponents for correct encoding.
        var formComponents = URLComponents()
        formComponents.queryItems = [URLQueryItem(name: "data", value: query)]

        guard let formBody = formComponents.percentEncodedQuery?.data(using: .utf8) else {
            throw OverpassError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.networkTimeout
        request.setValue("Snowly iOS App", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession wraps structured-concurrency cancellation as URLError.cancelled.
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .timedOut {
            Self.logger.error("Overpass request timed out: \(endpoint, privacy: .public)")
            throw OverpassError.timeout
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverpassError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OverpassError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

}

// MARK: - Overpass Response Parser (pure, testable)

/// Stateless parser for Overpass API JSON → SkiAreaData.
enum OverpassResponseParser {

    static func parse(data: Data, boundingBox: BoundingBox) throws -> SkiAreaData {
        let json: OverpassResponse
        do {
            json = try JSONDecoder().decode(OverpassResponse.self, from: data)
        } catch {
            throw OverpassError.decodingFailed(error.localizedDescription)
        }

        var trails: [SkiTrail] = []
        var lifts: [SkiLift] = []
        var areaName: String?

        for element in json.elements {
            let tags = element.tags ?? [:]

            // Extract ski area name from relation
            if element.type == "relation", tags["landuse"] == "winter_sports" {
                areaName = areaName ?? tags["name"]
                continue
            }

            guard element.type == "way", let geometry = element.geometry else {
                continue
            }

            let coordinates = geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }

            if tags["piste:type"] != nil {
                trails.append(SkiTrail(
                    id: String(element.id),
                    name: tags["name"],
                    difficulty: PisteDifficulty(osmValue: tags["piste:difficulty"]),
                    type: PisteType(osmValue: tags["piste:type"]),
                    coordinates: coordinates
                ))
            } else if tags["aerialway"] != nil {
                lifts.append(SkiLift(
                    id: String(element.id),
                    name: tags["name"],
                    liftType: AerialwayType(osmValue: tags["aerialway"]),
                    capacity: tags["aerialway:capacity"].flatMap(Int.init),
                    coordinates: coordinates
                ))
            }
        }

        return SkiAreaData(
            trails: trails,
            lifts: lifts,
            fetchedAt: Date(),
            boundingBox: boundingBox,
            name: areaName
        )
    }

    static func parseNearbyAreas(
        data: Data,
        origin: CLLocationCoordinate2D,
        limit: Int,
        recommendedRadiusMeters: Double
    ) throws -> [NearbySkiArea] {
        let json: OverpassResponse
        do {
            json = try JSONDecoder().decode(OverpassResponse.self, from: data)
        } catch {
            throw OverpassError.decodingFailed(error.localizedDescription)
        }

        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        var areas: [NearbySkiArea] = []
        areas.reserveCapacity(json.elements.count)

        for element in json.elements {
            guard element.type == "relation" || element.type == "way" else {
                continue
            }

            guard
                let tags = element.tags,
                isSkiArea(tags: tags),
                let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let center = element.center
            else {
                continue
            }

            let areaCenter = CLLocation(latitude: center.lat, longitude: center.lon)
            let distance = originLocation.distance(from: areaCenter)

            areas.append(NearbySkiArea(
                id: "\(element.type)-\(element.id)",
                name: name,
                center: Coordinate(latitude: center.lat, longitude: center.lon),
                distanceMeters: distance,
                recommendedRadiusMeters: recommendedRadiusMeters,
                bounds: element.bounds?.boundingBox
            ))
        }

        let uniqueSorted = Dictionary(grouping: areas, by: { normalizedAreaName($0.name) })
            .values
            .compactMap { group -> NearbySkiArea? in
                guard var best = group.min(by: { $0.distanceMeters < $1.distanceMeters }) else {
                    return nil
                }

                if best.bounds == nil, let fallbackBounds = group.compactMap(\.bounds).first {
                    best = NearbySkiArea(
                        id: best.id,
                        name: best.name,
                        center: best.center,
                        distanceMeters: best.distanceMeters,
                        recommendedRadiusMeters: best.recommendedRadiusMeters,
                        bounds: fallbackBounds
                    )
                }

                return best
            }
            .sorted(by: { $0.distanceMeters < $1.distanceMeters })

        return Array(uniqueSorted.prefix(max(0, limit)))
    }

    private static func isSkiArea(tags: [String: String]) -> Bool {
        tags["landuse"] == "winter_sports"
            || tags["site"] == "piste"
            || tags["leisure"] == "ski_resort"
    }

    private static func normalizedAreaName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Overpass API JSON Structure

/// Top-level Overpass API response.
struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

/// A single OSM element (node/way/relation) from Overpass.
struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let tags: [String: String]?
    let geometry: [OverpassGeomPoint]?
    let center: OverpassGeomPoint?
    let bounds: OverpassBounds?
}

/// A lat/lon point in Overpass `out geom` output.
struct OverpassGeomPoint: Decodable {
    let lat: Double
    let lon: Double
}

/// Overpass relation bounds (`out bb`) in WGS84 degrees.
struct OverpassBounds: Decodable {
    let minlat: Double
    let minlon: Double
    let maxlat: Double
    let maxlon: Double

    var boundingBox: BoundingBox {
        BoundingBox(south: minlat, west: minlon, north: maxlat, east: maxlon)
    }
}
