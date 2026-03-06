//
//  OverpassService.swift
//  Snowly
//
//  Fetches ski trail and lift data from the Overpass API (OpenStreetMap).
//  Parses raw OSM JSON into SkiTrail / SkiLift models.
//

import Foundation
import Observation
import CoreLocation

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
        }
    }
}

// MARK: - Overpass Service

@Observable
@MainActor
final class OverpassService {

    private(set) var isLoading = false
    private(set) var lastError: String?

    private static let primaryEndpoint = "https://overpass-api.de/api/interpreter"
    private static let fallbackEndpoint = "https://overpass.kumi.systems/api/interpreter"
    private static let requestTimeout: TimeInterval = 30
    private static let defaultAreaRadiusMeters: Double = 6000

    /// Fetch ski trails and lifts within a bounding box.
    func fetchSkiArea(boundingBox bbox: BoundingBox) async throws -> SkiAreaData {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let query = buildQuery(bbox: bbox)

        do {
            let data = try await executeQueryWithFallback(query)
            return try parseResponse(data: data, boundingBox: bbox)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Search nearby ski areas (winter_sports relations) around a coordinate.
    func searchNearbySkiAreas(
        center: CLLocationCoordinate2D,
        radiusMeters: Double = 30000,
        limit: Int = 10
    ) async throws -> [NearbySkiArea] {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let query = buildNearbyAreasQuery(center: center, radiusMeters: radiusMeters)

        do {
            let data = try await executeQueryWithFallback(query)
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

    private func buildQuery(bbox: BoundingBox) -> String {
        let bboxStr = bbox.overpassBBoxString
        return """
        [out:json][timeout:\(Int(Self.requestTimeout))];
        (
          way["piste:type"="downhill"](\(bboxStr));
          way["aerialway"](\(bboxStr));
          relation["landuse"="winter_sports"](\(bboxStr));
        );
        out body geom;
        """
    }

    private func buildNearbyAreasQuery(
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> String {
        let radius = max(1000, Int(radiusMeters.rounded()))
        return """
        [out:json][timeout:\(Int(Self.requestTimeout))];
        (
          relation["landuse"="winter_sports"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
          relation["site"="piste"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
          relation["leisure"="ski_resort"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
          way["landuse"="winter_sports"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
          way["site"="piste"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
          way["leisure"="ski_resort"]["name"](around:\(radius),\(center.latitude),\(center.longitude));
        );
        out tags center bb;
        """
    }

    // MARK: - Network

    private func executeQueryWithFallback(_ query: String) async throws -> Data {
        do {
            return try await executeQuery(query, endpoint: Self.primaryEndpoint)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Try fallback endpoint
            return try await executeQuery(query, endpoint: Self.fallbackEndpoint)
        }
    }

    private func executeQuery(_ query: String, endpoint: String) async throws -> Data {
        guard var components = URLComponents(string: endpoint) else {
            throw OverpassError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "data", value: query)]

        guard let url = components.url else {
            throw OverpassError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Snowly iOS App", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverpassError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OverpassError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: - Parsing

    private func parseResponse(data: Data, boundingBox: BoundingBox) throws -> SkiAreaData {
        try OverpassResponseParser.parse(data: data, boundingBox: boundingBox)
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
