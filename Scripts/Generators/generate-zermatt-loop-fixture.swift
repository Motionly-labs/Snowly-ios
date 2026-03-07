#!/usr/bin/env swift
//
//  generate-zermatt-loop-fixture.swift
//  Snowly
//
//  Fetches real Zermatt ski trails/lifts from Overpass (OSM) and generates
//  looped GPS fixture data along actual geometries:
//  lift up + piste down, repeated for multiple laps.
//
//  Usage:
//    swift Scripts/Generators/generate-zermatt-loop-fixture.swift
//    swift Scripts/Generators/generate-zermatt-loop-fixture.swift /tmp/zermatt.trackpoints.json
//

import Foundation

// MARK: - Models

struct FixtureTrackPoint: Codable {
    let timestamp: TimeInterval
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let accuracy: Double
    let course: Double
}

struct Coordinate {
    let latitude: Double
    let longitude: Double
}

struct Waypoint {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct OSMWay {
    let id: Int64
    let name: String?
    let tags: [String: String]
    let coordinates: [Coordinate]
}

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let tags: [String: String]?
    let geometry: [OverpassPoint]?
}

struct OverpassPoint: Decodable {
    let lat: Double
    let lon: Double
}

struct ElevationResponse: Decodable {
    let results: [ElevationResultEntry]
}

struct ElevationResultEntry: Decodable {
    let elevation: Double?
}

enum GeneratorError: Error, LocalizedError {
    case noLiftFound
    case noTrailFound
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noLiftFound:
            return "No suitable aerialway found in fetched Zermatt area."
        case .noTrailFound:
            return "No suitable downhill piste found near selected lift."
        case .invalidResponse(let message):
            return "Overpass response invalid: \(message)"
        }
    }
}

// MARK: - Constants

private let overpassEndpoints = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

private let elevationEndpoints = [
    "https://api.opentopodata.org/v1/srtm90m",
    "https://api.open-elevation.com/api/v1/lookup",
]

// Sunnegga area anchor (used as base reference).
private let zermattAnchor = Coordinate(latitude: 46.0217, longitude: 7.7823)
private let fetchRadiusMeters: Double = 8500
private let loopCount = 4
private let sampleInterval: TimeInterval = 2.0

// MARK: - Geometry helpers

private func deg2rad(_ value: Double) -> Double { value * .pi / 180.0 }
private func rad2deg(_ value: Double) -> Double { value * 180.0 / .pi }

private func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = deg2rad(b.latitude - a.latitude)
    let dLon = deg2rad(b.longitude - a.longitude)
    let lat1 = deg2rad(a.latitude)
    let lat2 = deg2rad(b.latitude)
    let x = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(x), sqrt(max(1 - x, 0)))
    return earthRadius * c
}

private func polylineLength(_ points: [Coordinate]) -> Double {
    guard points.count > 1 else { return 0 }
    var total = 0.0
    for idx in 1..<points.count {
        total += distanceMeters(points[idx - 1], points[idx])
    }
    return total
}

private func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double {
    let lat1 = deg2rad(a.latitude)
    let lat2 = deg2rad(b.latitude)
    let dLon = deg2rad(b.longitude - a.longitude)
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let angle = rad2deg(atan2(y, x))
    let normalized = angle.truncatingRemainder(dividingBy: 360)
    return normalized >= 0 ? normalized : normalized + 360
}

private func metersToLatitudeDelta(_ meters: Double) -> Double {
    meters / 111_111.0
}

private func metersToLongitudeDelta(_ meters: Double, atLatitude latitude: Double) -> Double {
    let scale = max(cos(deg2rad(latitude)), 0.15)
    return meters / (111_111.0 * scale)
}

private func bboxAround(center: Coordinate, radiusMeters: Double) -> (south: Double, west: Double, north: Double, east: Double) {
    let latDelta = radiusMeters / 111_320.0
    let lonScale = max(1e-6, 111_320.0 * abs(cos(center.latitude * .pi / 180.0)))
    let lonDelta = radiusMeters / lonScale
    return (
        south: center.latitude - latDelta,
        west: center.longitude - lonDelta,
        north: center.latitude + latDelta,
        east: center.longitude + lonDelta
    )
}

// MARK: - Overpass fetch

private func buildOverpassQuery(for bbox: (south: Double, west: Double, north: Double, east: Double)) -> String {
    """
    [out:json][timeout:40];
    (
      way["piste:type"="downhill"](\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east));
      way["aerialway"](\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east));
    );
    out body geom;
    """
}

private func executeRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
    let semaphore = DispatchSemaphore(value: 0)
    var capturedData: Data?
    var capturedResponse: URLResponse?
    var capturedError: Error?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        capturedData = data
        capturedResponse = response
        capturedError = error
        semaphore.signal()
    }
    task.resume()

    let timeoutResult = semaphore.wait(timeout: .now() + request.timeoutInterval + 5)
    if timeoutResult == .timedOut {
        task.cancel()
        throw URLError(.timedOut)
    }
    if let capturedError {
        throw capturedError
    }
    guard let capturedData, let capturedResponse else {
        throw GeneratorError.invalidResponse("Missing response data")
    }
    return (capturedData, capturedResponse)
}

private func fetchOverpassWays(center: Coordinate, radiusMeters: Double) throws -> (trails: [OSMWay], lifts: [OSMWay]) {
    let bbox = bboxAround(center: center, radiusMeters: radiusMeters)
    let query = buildOverpassQuery(for: bbox)
    var lastError: Error?

    for endpoint in overpassEndpoints {
        guard var components = URLComponents(string: endpoint) else { continue }
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = components.url else { continue }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("Snowly Fixture Generator", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try executeRequest(request)
            guard let http = response as? HTTPURLResponse else {
                throw GeneratorError.invalidResponse("Non-HTTP response")
            }
            guard (200...299).contains(http.statusCode) else {
                throw GeneratorError.invalidResponse("HTTP \(http.statusCode) from \(endpoint)")
            }

            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            let ways = decoded.elements.compactMap { element -> OSMWay? in
                guard element.type == "way",
                      let tags = element.tags,
                      let geometry = element.geometry,
                      geometry.count >= 2 else {
                    return nil
                }
                let coords = geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }
                return OSMWay(id: element.id, name: tags["name"], tags: tags, coordinates: coords)
            }

            let trails = ways.filter { $0.tags["piste:type"]?.lowercased() == "downhill" }
            let lifts = ways.filter {
                guard let aerialway = $0.tags["aerialway"]?.lowercased() else { return false }
                let allowed = Set([
                    "chair_lift", "gondola", "cable_car", "mixed_lift",
                    "drag_lift", "t-bar", "j-bar", "platter",
                    "rope_tow", "magic_carpet"
                ])
                return allowed.contains(aerialway)
            }
            return (trails, lifts)
        } catch {
            lastError = error
            continue
        }
    }

    throw lastError ?? GeneratorError.invalidResponse("All Overpass endpoints failed")
}

// MARK: - Elevation fetch (DEM)

/// Fetch a single batch (≤ 90 points) from one endpoint.
private func fetchElevationBatch(for coordinates: [Coordinate], endpoint: String) throws -> [Double] {
    if endpoint.contains("opentopodata") {
        // OpenTopoData — GET with pipe-separated locations
        let locString = coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
        guard var components = URLComponents(string: endpoint) else {
            throw GeneratorError.invalidResponse("Bad elevation URL")
        }
        components.queryItems = [URLQueryItem(name: "locations", value: locString)]
        guard let url = components.url else {
            throw GeneratorError.invalidResponse("Bad elevation URL construction")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Snowly Fixture Generator", forHTTPHeaderField: "User-Agent")

        let (data, response) = try executeRequest(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GeneratorError.invalidResponse("Elevation HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let decoded = try JSONDecoder().decode(ElevationResponse.self, from: data)
        guard decoded.results.count == coordinates.count else {
            throw GeneratorError.invalidResponse("Elevation count mismatch: expected \(coordinates.count), got \(decoded.results.count)")
        }
        return decoded.results.map { $0.elevation ?? 0 }
    } else {
        // Open-Elevation — POST JSON
        struct LocRequest: Encodable { let locations: [LocEntry] }
        struct LocEntry: Encodable { let latitude: Double; let longitude: Double }

        let body = LocRequest(locations: coordinates.map { LocEntry(latitude: $0.latitude, longitude: $0.longitude) })
        let bodyData = try JSONEncoder().encode(body)

        guard let url = URL(string: endpoint) else {
            throw GeneratorError.invalidResponse("Bad elevation URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Snowly Fixture Generator", forHTTPHeaderField: "User-Agent")

        let (data, response) = try executeRequest(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GeneratorError.invalidResponse("Elevation HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let decoded = try JSONDecoder().decode(ElevationResponse.self, from: data)
        guard decoded.results.count == coordinates.count else {
            throw GeneratorError.invalidResponse("Elevation count mismatch: expected \(coordinates.count), got \(decoded.results.count)")
        }
        return decoded.results.map { $0.elevation ?? 0 }
    }
}

/// Fetch real DEM elevations for all coordinates, batching at 90 per request.
/// Tries each endpoint in order; falls through on failure.
private func fetchElevations(for coordinates: [Coordinate]) throws -> [Double] {
    let batchSize = 90
    var lastError: Error?

    for endpoint in elevationEndpoints {
        var allElevations: [Double] = []
        var failed = false

        for batchStart in stride(from: 0, to: coordinates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, coordinates.count)
            let batch = Array(coordinates[batchStart..<batchEnd])

            do {
                let elevations = try fetchElevationBatch(for: batch, endpoint: endpoint)
                allElevations.append(contentsOf: elevations)

                // Respect rate limit between batches
                if batchEnd < coordinates.count {
                    Thread.sleep(forTimeInterval: 1.5)
                }
            } catch {
                print("  Elevation batch failed (\(endpoint)): \(error)")
                lastError = error
                failed = true
                break
            }
        }

        if !failed && allElevations.count == coordinates.count {
            return allElevations
        }
    }

    throw lastError ?? GeneratorError.invalidResponse("All elevation endpoints failed")
}

// MARK: - Selection heuristics

private func keywordRank(_ text: String?, keywords: [String]) -> Int {
    guard let value = text?.lowercased() else { return 99 }
    for (index, keyword) in keywords.enumerated() where value.contains(keyword) {
        return index
    }
    return 99
}

private struct LiftTrailSelection {
    let liftWay: OSMWay
    let trailWay: OSMWay
    let liftPath: [Coordinate]
    let trailPath: [Coordinate]
    let liftLength: Double
    let trailLength: Double
    let anchorDistance: Double
    let topDistance: Double
    let baseDistance: Double
    let mode: String
}

private func nearestPoint(on path: [Coordinate], to target: Coordinate) -> (index: Int, distance: Double) {
    guard !path.isEmpty else { return (0, .greatestFiniteMagnitude) }
    var bestIndex = 0
    var bestDistance = Double.greatestFiniteMagnitude
    for (idx, point) in path.enumerated() {
        let d = distanceMeters(point, target)
        if d < bestDistance {
            bestDistance = d
            bestIndex = idx
        }
    }
    return (bestIndex, bestDistance)
}

private func sliceTrailForLoop(trail: [Coordinate], liftBase: Coordinate, liftTop: Coordinate) -> (path: [Coordinate], topDistance: Double, baseDistance: Double)? {
    guard trail.count >= 2 else { return nil }
    let nearTop = nearestPoint(on: trail, to: liftTop)
    let nearBase = nearestPoint(on: trail, to: liftBase)
    guard nearTop.index != nearBase.index else { return nil }

    let segment: [Coordinate]
    if nearTop.index < nearBase.index {
        segment = Array(trail[nearTop.index...nearBase.index])
    } else {
        segment = Array(trail[nearBase.index...nearTop.index].reversed())
    }
    guard segment.count >= 2 else { return nil }

    let length = polylineLength(segment)
    guard length >= 850 else { return nil }
    return (segment, nearTop.distance, nearBase.distance)
}

private func chooseLiftTrailPair(
    lifts: [OSMWay],
    trails: [OSMWay],
    anchor: Coordinate
) throws -> LiftTrailSelection {
    struct LiftCandidate {
        let keywordRank: Int
        let endpointDistance: Double
        let length: Double
        let path: [Coordinate]
        let way: OSMWay
    }

    struct PairCandidate {
        let score: Double
        let lift: LiftCandidate
        let trailWay: OSMWay
        let trailPath: [Coordinate]
        let trailLength: Double
        let topDistance: Double
        let baseDistance: Double
        let mode: String
    }

    let liftKeywords = ["rothorn", "sunnegga", "blauherd", "gornergrat"]
    let trailKeywords = ["national", "sunnegga", "findeln", "blauherd", "rothorn", "kumme"]
    let famousTrailKeywords = ["national", "kumme", "rothorn", "findeln", "ried", "sunnegga"]

    let liftCandidates: [LiftCandidate] = lifts.compactMap { lift in
        guard lift.coordinates.count >= 2 else { return nil }
        let length = polylineLength(lift.coordinates)
        guard length >= 700 else { return nil }
        guard let first = lift.coordinates.first, let last = lift.coordinates.last else { return nil }
        let dFirst = distanceMeters(first, anchor)
        let dLast = distanceMeters(last, anchor)
        let oriented = dFirst <= dLast ? lift.coordinates : Array(lift.coordinates.reversed())
        return LiftCandidate(
            keywordRank: keywordRank(lift.name, keywords: liftKeywords),
            endpointDistance: min(dFirst, dLast),
            length: length,
            path: oriented,
            way: lift
        )
    }

    guard !liftCandidates.isEmpty else { throw GeneratorError.noLiftFound }

    var strictPairs: [PairCandidate] = []
    var strictFamousPairs: [PairCandidate] = []
    var moderatePairs: [PairCandidate] = []
    var moderateFamousPairs: [PairCandidate] = []
    var loosePairs: [PairCandidate] = []
    var allPairs: [PairCandidate] = []

    for lift in liftCandidates {
        guard let liftBase = lift.path.first, let liftTop = lift.path.last else { continue }
        for trail in trails {
            guard trail.coordinates.count >= 2 else { continue }
            guard let sliced = sliceTrailForLoop(
                trail: trail.coordinates,
                liftBase: liftBase,
                liftTop: liftTop
            ) else {
                continue
            }
            let topDistance = sliced.topDistance
            let baseDistance = sliced.baseDistance
            let trailPath = sliced.path
            let trailLength = polylineLength(trailPath)
            let trailKeywordRank = keywordRank(trail.name, keywords: trailKeywords)
            let famousRank = keywordRank(trail.name, keywords: famousTrailKeywords)
            let isFamousNamedTrail = famousRank < 99

            let score = lift.endpointDistance * 0.7
                + topDistance * 5.4
                + baseDistance * 6.1
                + Double(lift.keywordRank * 35 + trailKeywordRank * 18 + famousRank * 8)
                - (lift.length + trailLength) * 0.009

            let pair = PairCandidate(
                score: score,
                lift: lift,
                trailWay: trail,
                trailPath: trailPath,
                trailLength: trailLength,
                topDistance: topDistance,
                baseDistance: baseDistance,
                mode: ""
            )
            allPairs.append(pair)

            if topDistance <= 60 && baseDistance <= 140 {
                strictPairs.append(pair)
                if isFamousNamedTrail {
                    strictFamousPairs.append(pair)
                }
            } else if topDistance <= 120 && baseDistance <= 260 {
                moderatePairs.append(pair)
                if isFamousNamedTrail {
                    moderateFamousPairs.append(pair)
                }
            } else if topDistance <= 220 && baseDistance <= 420 {
                loosePairs.append(pair)
            }
        }
    }

    func pickBest(_ pairs: [PairCandidate], mode: String) -> PairCandidate? {
        guard var best = pairs.min(by: { $0.score < $1.score }) else { return nil }
        best = PairCandidate(
            score: best.score,
            lift: best.lift,
            trailWay: best.trailWay,
            trailPath: best.trailPath,
            trailLength: best.trailLength,
            topDistance: best.topDistance,
            baseDistance: best.baseDistance,
            mode: mode
        )
        return best
    }

    let selected = pickBest(strictFamousPairs, mode: "strict connectivity + named trail")
        ?? pickBest(strictPairs, mode: "strict connectivity")
        ?? pickBest(moderateFamousPairs, mode: "moderate connectivity + named trail")
        ?? pickBest(moderatePairs, mode: "moderate connectivity")
        ?? pickBest(loosePairs, mode: "loose connectivity fallback")
        ?? pickBest(allPairs, mode: "weakest fallback")

    guard let selected else {
        throw GeneratorError.noTrailFound
    }

    print("Selection mode: \(selected.mode)")
    print("Selected lift: \(selected.lift.way.name ?? "unnamed") [id=\(selected.lift.way.id)]")
    print("  length=\(Int(selected.lift.length))m, anchorDistance=\(Int(selected.lift.endpointDistance))m")
    print("Selected downhill trail: \(selected.trailWay.name ?? "unnamed") [id=\(selected.trailWay.id)]")
    print("  length=\(Int(selected.trailLength))m, topDistance=\(Int(selected.topDistance))m, baseDistance=\(Int(selected.baseDistance))m")

    return LiftTrailSelection(
        liftWay: selected.lift.way,
        trailWay: selected.trailWay,
        liftPath: selected.lift.path,
        trailPath: selected.trailPath,
        liftLength: selected.lift.length,
        trailLength: selected.trailLength,
        anchorDistance: selected.lift.endpointDistance,
        topDistance: selected.topDistance,
        baseDistance: selected.baseDistance,
        mode: selected.mode
    )
}

// MARK: - Track synthesis along chosen geometries

private func waypoints(from coordinates: [Coordinate], startAltitude: Double, endAltitude: Double) -> [Waypoint] {
    guard coordinates.count > 1 else {
        return coordinates.map {
            Waypoint(latitude: $0.latitude, longitude: $0.longitude, altitude: startAltitude)
        }
    }

    var cumulative: [Double] = [0]
    cumulative.reserveCapacity(coordinates.count)
    for index in 1..<coordinates.count {
        let seg = distanceMeters(coordinates[index - 1], coordinates[index])
        cumulative.append((cumulative.last ?? 0) + seg)
    }
    let total = max(cumulative.last ?? 0, 1)

    return coordinates.enumerated().map { idx, c in
        let progress = cumulative[idx] / total
        return Waypoint(
            latitude: c.latitude,
            longitude: c.longitude,
            altitude: startAltitude + (endAltitude - startAltitude) * progress
        )
    }
}

private func interpolate(_ a: Waypoint, _ b: Waypoint, t: Double) -> Waypoint {
    Waypoint(
        latitude: a.latitude + (b.latitude - a.latitude) * t,
        longitude: a.longitude + (b.longitude - a.longitude) * t,
        altitude: a.altitude + (b.altitude - a.altitude) * t
    )
}

private func appendSegment(
    from start: Waypoint,
    to end: Waypoint,
    baseSpeed: Double,
    speedJitter: Double,
    baseAccuracy: Double,
    accuracyJitter: Double,
    lateralNoiseMeters: Double,
    sampleInterval: TimeInterval,
    currentTime: inout TimeInterval,
    output: inout [FixtureTrackPoint],
    includeStartPoint: Bool
) {
    let startCoord = Coordinate(latitude: start.latitude, longitude: start.longitude)
    let endCoord = Coordinate(latitude: end.latitude, longitude: end.longitude)
    let distance = distanceMeters(startCoord, endCoord)
    let duration = max(distance / max(baseSpeed, 0.2), sampleInterval)
    let sampleCount = max(Int(duration / sampleInterval), 1)
    let baseCourse = bearingDegrees(from: startCoord, to: endCoord)
    let startIndex = includeStartPoint ? 0 : 1

    for i in startIndex...sampleCount {
        let progress = Double(i) / Double(sampleCount)
        let p = interpolate(start, end, t: progress)

        let phase = Double(output.count + i)
        let noiseX = lateralNoiseMeters * sin(phase * 0.23)
        let noiseY = lateralNoiseMeters * cos(phase * 0.17)
        let driftSpike = output.count % 121 == 0 ? lateralNoiseMeters * 1.3 : 0
        let lat = p.latitude + metersToLatitudeDelta(noiseY + driftSpike * sin(phase * 0.41))
        let lon = p.longitude + metersToLongitudeDelta(noiseX + driftSpike * cos(phase * 0.39), atLatitude: p.latitude)

        let wobble = sin(phase * 0.31)
        let speed = max(0.35, baseSpeed + wobble * speedJitter)
        let accuracy = max(3, baseAccuracy + abs(wobble) * accuracyJitter + (driftSpike > 0 ? 4 : 0))

        output.append(
            FixtureTrackPoint(
                timestamp: currentTime,
                latitude: lat,
                longitude: lon,
                altitude: p.altitude,
                speed: speed,
                accuracy: accuracy,
                course: baseCourse
            )
        )
        currentTime += sampleInterval
    }
}

private func appendPath(
    _ path: [Waypoint],
    baseSpeed: Double,
    speedJitter: Double,
    baseAccuracy: Double,
    accuracyJitter: Double,
    lateralNoiseMeters: Double,
    sampleInterval: TimeInterval,
    currentTime: inout TimeInterval,
    output: inout [FixtureTrackPoint],
    includeFirstPoint: Bool
) {
    guard path.count > 1 else { return }
    for i in 0..<(path.count - 1) {
        appendSegment(
            from: path[i],
            to: path[i + 1],
            baseSpeed: baseSpeed,
            speedJitter: speedJitter,
            baseAccuracy: baseAccuracy,
            accuracyJitter: accuracyJitter,
            lateralNoiseMeters: lateralNoiseMeters,
            sampleInterval: sampleInterval,
            currentTime: &currentTime,
            output: &output,
            includeStartPoint: includeFirstPoint && i == 0
        )
    }
}

private func appendPause(
    at anchor: Waypoint,
    duration: TimeInterval,
    sampleInterval: TimeInterval,
    baseAccuracy: Double,
    driftMeters: Double,
    currentTime: inout TimeInterval,
    output: inout [FixtureTrackPoint]
) {
    let sampleCount = max(Int(duration / sampleInterval), 1)
    var previous = Coordinate(latitude: anchor.latitude, longitude: anchor.longitude)

    for i in 0..<sampleCount {
        let phase = Double(output.count + i)
        let driftX = driftMeters * sin(phase * 0.19) + driftMeters * 0.4 * cos(phase * 0.043)
        let driftY = driftMeters * cos(phase * 0.16) + driftMeters * 0.35 * sin(phase * 0.037)
        let lat = anchor.latitude + metersToLatitudeDelta(driftY)
        let lon = anchor.longitude + metersToLongitudeDelta(driftX, atLatitude: anchor.latitude)
        let coord = Coordinate(latitude: lat, longitude: lon)
        let course = bearingDegrees(from: previous, to: coord)
        previous = coord

        let wobble = abs(sin(phase * 0.22))
        let speed = max(0.35, 0.25 + wobble * 1.0)
        let accuracy = baseAccuracy + wobble * max(2.0, driftMeters * 0.4)

        output.append(
            FixtureTrackPoint(
                timestamp: currentTime,
                latitude: lat,
                longitude: lon,
                altitude: anchor.altitude + sin(phase * 0.12) * 0.8,
                speed: speed,
                accuracy: accuracy,
                course: course
            )
        )
        currentTime += sampleInterval
    }
}

private func appendConnectorIfNeeded(
    from start: Waypoint,
    to end: Waypoint,
    sampleInterval: TimeInterval,
    currentTime: inout TimeInterval,
    output: inout [FixtureTrackPoint]
) {
    let startCoord = Coordinate(latitude: start.latitude, longitude: start.longitude)
    let endCoord = Coordinate(latitude: end.latitude, longitude: end.longitude)
    let gap = distanceMeters(startCoord, endCoord)
    guard gap >= 6 else { return }

    appendSegment(
        from: start,
        to: end,
        baseSpeed: 1.3,
        speedJitter: 0.2,
        baseAccuracy: 8.0,
        accuracyJitter: 2.0,
        lateralNoiseMeters: 1.8,
        sampleInterval: sampleInterval,
        currentTime: &currentTime,
        output: &output,
        includeStartPoint: false
    )
}

// MARK: - GPX output

private func iso8601String(from timeIntervalSinceReferenceDate: TimeInterval) -> String {
    let date = Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

/// Xcode simulates movement only when `<wpt>` elements contain `<time>` tags.
/// It replays waypoints in chronological order, interpolating between them.
private func generateGPX(from points: [FixtureTrackPoint]) -> String {
    guard !points.isEmpty else {
        return """
        <?xml version="1.0"?>
        <gpx version="1.1" creator="Snowly Real Trail Generator"></gpx>
        """
    }

    // Sample every 3rd point to keep file size reasonable.
    // With 2s base interval this gives ~6s between GPX waypoints — Xcode interpolates the rest.
    let strideStep = 3
    var sampled: [FixtureTrackPoint] = []
    var idx = 0
    while idx < points.count {
        sampled.append(points[idx])
        idx += strideStep
    }
    if let last = points.last, sampled.last?.timestamp != last.timestamp {
        sampled.append(last)
    }

    var gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Snowly Real Trail Generator"
         xmlns="http://www.topografix.com/GPX/1/1"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
    """

    for point in sampled {
        let time = iso8601String(from: point.timestamp)
        gpx += """

        <wpt lat="\(point.latitude)" lon="\(point.longitude)">
          <ele>\(point.altitude)</ele>
          <time>\(time)</time>
        </wpt>
        """
    }

    gpx += """

    </gpx>
    """
    return gpx
}

// MARK: - Main

private func main() throws {
    let outputPath: String
    if CommandLine.arguments.count > 1 {
        outputPath = CommandLine.arguments[1]
    } else {
        outputPath = "Snowly/Debug/Fixtures/ZermattRothornSunneggaLoop.trackpoints.json"
    }

    print("Fetching real OSM trails/lifts from Overpass...")
    let fetched = try fetchOverpassWays(center: zermattAnchor, radiusMeters: fetchRadiusMeters)
    guard !fetched.lifts.isEmpty else { throw GeneratorError.noLiftFound }
    guard !fetched.trails.isEmpty else { throw GeneratorError.noTrailFound }
    print("Fetched: \(fetched.lifts.count) lifts, \(fetched.trails.count) downhill trails")

    let selection = try chooseLiftTrailPair(lifts: fetched.lifts, trails: fetched.trails, anchor: zermattAnchor)
    let liftCoordinates = selection.liftPath
    let trailCoordinates = selection.trailPath

    let liftPath: [Waypoint]
    let downhillPath: [Waypoint]

    do {
        print("Fetching real elevations from DEM (SRTM)...")
        let allCoordinates = liftCoordinates + trailCoordinates
        let allElevations = try fetchElevations(for: allCoordinates)
        let liftElevations = Array(allElevations[0..<liftCoordinates.count])
        let trailElevations = Array(allElevations[liftCoordinates.count..<allCoordinates.count])

        var liftWaypoints = zip(liftCoordinates, liftElevations).map { coord, ele in
            Waypoint(latitude: coord.latitude, longitude: coord.longitude, altitude: ele)
        }
        var trailWaypoints = zip(trailCoordinates, trailElevations).map { coord, ele in
            Waypoint(latitude: coord.latitude, longitude: coord.longitude, altitude: ele)
        }

        // Orient using real elevation: lift must go uphill, trail must go downhill.
        if let first = liftWaypoints.first, let last = liftWaypoints.last, first.altitude > last.altitude {
            liftWaypoints.reverse()
        }
        if let first = trailWaypoints.first, let last = trailWaypoints.last, first.altitude < last.altitude {
            trailWaypoints.reverse()
        }

        liftPath = liftWaypoints
        downhillPath = trailWaypoints

        let liftBase = Int(liftWaypoints.first?.altitude ?? 0)
        let liftTop = Int(liftWaypoints.last?.altitude ?? 0)
        let trailTop = Int(trailWaypoints.first?.altitude ?? 0)
        let trailBase = Int(trailWaypoints.last?.altitude ?? 0)
        print("  Lift: \(liftBase)m → \(liftTop)m  Trail: \(trailTop)m → \(trailBase)m")
    } catch {
        print("Warning: elevation fetch failed (\(error.localizedDescription)), using linear interpolation fallback")
        let liftBaseAlt = 2300.0
        let liftTopAlt = 3100.0
        liftPath = waypoints(from: liftCoordinates, startAltitude: liftBaseAlt, endAltitude: liftTopAlt)
        downhillPath = waypoints(from: trailCoordinates, startAltitude: liftTopAlt, endAltitude: liftBaseAlt)
    }

    let startDate = ISO8601DateFormatter().date(from: "2026-02-15T08:30:00Z") ?? Date()
    var currentTime = startDate.timeIntervalSinceReferenceDate
    var points: [FixtureTrackPoint] = []
    points.reserveCapacity(loopCount * 450)

    for lap in 0..<loopCount {
        // Keep realistic queue waits from lap 2 onward.
        if lap > 0, let liftBase = liftPath.first {
            appendPause(
                at: liftBase,
                duration: 120,
                sampleInterval: sampleInterval,
                baseAccuracy: 12,
                driftMeters: 14,
                currentTime: &currentTime,
                output: &points
            )
        }

        appendPath(
            liftPath,
            baseSpeed: 3.4,
            speedJitter: 0.45,
            baseAccuracy: 9.5,
            accuracyJitter: 2.6,
            lateralNoiseMeters: 3.8,
            sampleInterval: sampleInterval,
            currentTime: &currentTime,
            output: &points,
            includeFirstPoint: lap == 0
        )

        if let liftTop = liftPath.last {
            appendPause(
                at: liftTop,
                duration: 70,
                sampleInterval: sampleInterval,
                baseAccuracy: 8.5,
                driftMeters: 11,
                currentTime: &currentTime,
                output: &points
            )
        }

        if let liftTop = liftPath.last, let downhillTop = downhillPath.first {
            appendConnectorIfNeeded(
                from: liftTop,
                to: downhillTop,
                sampleInterval: sampleInterval,
                currentTime: &currentTime,
                output: &points
            )
        }

        appendPath(
            downhillPath,
            baseSpeed: 14.8,
            speedJitter: 2.5,
            baseAccuracy: 5.8,
            accuracyJitter: 2.0,
            lateralNoiseMeters: 3.2,
            sampleInterval: sampleInterval,
            currentTime: &currentTime,
            output: &points,
            includeFirstPoint: false
        )

        if let downhillBase = downhillPath.last, let liftBase = liftPath.first {
            appendConnectorIfNeeded(
                from: downhillBase,
                to: liftBase,
                sampleInterval: sampleInterval,
                currentTime: &currentTime,
                output: &points
            )
        }

        if let liftBase = liftPath.first {
            appendPause(
                at: liftBase,
                duration: 95,
                sampleInterval: sampleInterval,
                baseAccuracy: 11.5,
                driftMeters: 16,
                currentTime: &currentTime,
                output: &points
            )
        }
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(points)
    try jsonData.write(to: outputURL)

    let gpxURL: URL
    if CommandLine.arguments.count > 1 {
        gpxURL = outputURL.deletingPathExtension().appendingPathExtension("gpx")
    } else {
        gpxURL = URL(fileURLWithPath: "Snowly/Debug/Locations/ZermattRothornSunneggaLoop.gpx")
    }
    try generateGPX(from: points).write(
        to: gpxURL,
        atomically: true,
        encoding: .utf8
    )

    print("Generated \(points.count) real-trail track points")
    print("JSON: \(outputURL.path)")
    print("GPX:  \(gpxURL.path)")
}

do {
    try main()
} catch {
    fputs("ERROR: \(error)\n", stderr)
    exit(1)
}
