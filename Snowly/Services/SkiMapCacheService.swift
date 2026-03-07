//
//  SkiMapCacheService.swift
//  Snowly
//
//  Coordinates ski area data fetching with local file caching.
//  Cache key = bounding box hash; default TTL = 7 days.
//

import Foundation
import CoreLocation
import MapKit
import Observation
import os

enum CachedAreaStatus: String, Sendable {
    case fresh
    case stale
    case downloading
    case failed
}

struct CachedAreaSummary: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let center: Coordinate
    let boundingBox: BoundingBox
    let fetchedAt: Date
    let expiresAt: Date
    let trailCount: Int
    let liftCount: Int
    let lastError: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var status: CachedAreaStatus {
        if let lastError, !lastError.isEmpty {
            return .failed
        }
        return isExpired ? .stale : .fresh
    }
}

@Observable
@MainActor
final class SkiMapCacheService {

    private(set) var currentSkiArea: SkiAreaData?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var activeAreaOperations: Set<String> = []

    private(set) var displayResortName: String?
    private(set) var displayRegionName: String?
    private(set) var lastClassifiedCoordinate: Coordinate?
    private(set) var activeResortId: String?
    private(set) var activeResortBBox: BoundingBox?

    var displayTitle: String {
        sanitizeName(displayResortName) ??
            sanitizeName(displayRegionName) ??
            Self.fallbackDisplayTitle
    }

    var currentResortInfo: ResolvedResortInfo? {
        guard let name = sanitizeName(displayResortName) else { return nil }
        let coordinate = activeResortBBox?.center
            ?? currentSkiArea?.boundingBox.center
            ?? lastClassifiedCoordinate
        guard let coordinate else { return nil }
        return ResolvedResortInfo(
            name: name,
            coordinate: coordinate,
            regionName: sanitizeName(displayRegionName)
        )
    }

    private let overpassService: OverpassService
    private let cacheDirectory: URL
    private let cacheTTL: TimeInterval
    private let indexURL: URL
    private let nearbyAreasURL: URL
    private var lastReverseGeocodeDate: Date?
    private var lastReverseGeocodeCoordinate: Coordinate?
    private var lastReverseGeocodedRegion: String?

    private static let logger = Logger(subsystem: "com.Snowly", category: "SkiMapCache")

    /// Default cache TTL: 7 days.
    nonisolated static let defaultTTL: TimeInterval = 7 * 24 * 3600
    nonisolated static let defaultNearbySearchRadiusMeters: Double = 30000
    nonisolated static let extendedNearbySearchRadiusMeters: Double = 90000
    nonisolated static let defaultAreaCacheRadiusMeters: Double = 6000
    nonisolated static let defaultReclassifyDistanceMeters: Double = 3000
    nonisolated static let reverseGeocodeThrottleSeconds: TimeInterval = 60
    nonisolated static let fallbackDisplayTitle = "Resort"

    init(
        overpassService: OverpassService? = nil,
        cacheTTL: TimeInterval = SkiMapCacheService.defaultTTL,
        cacheDirectory: URL? = nil
    ) {
        self.overpassService = overpassService ?? OverpassService()
        self.cacheTTL = cacheTTL

        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.cacheDirectory = caches.appendingPathComponent("SkiMapCache", isDirectory: true)
        }
        self.indexURL = self.cacheDirectory.appendingPathComponent("cache_index.json")
        self.nearbyAreasURL = self.cacheDirectory.appendingPathComponent("nearby_areas.json")

        createCacheDirectoryIfNeeded()
        pruneOrphanedIndexEntries()
    }

    /// Load ski area data for a location. Checks cache first, then fetches from API.
    func loadSkiArea(center: CLLocationCoordinate2D, radiusMeters: Double = 5000) async {
        let bbox = BoundingBox.around(center: center, radiusMeters: radiusMeters)

        // Check cache
        if let cached = readCache(for: bbox), !cached.isExpired(maxAge: cacheTTL) {
            currentSkiArea = cached
            applySkiAreaNameIfNeeded(cached, fallbackBBox: bbox)
            return
        }

        // Fetch from API
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let skiArea = try await overpassService.fetchSkiArea(boundingBox: bbox)
            currentSkiArea = skiArea
            applySkiAreaNameIfNeeded(skiArea, fallbackBBox: bbox)
            writeCache(skiArea, for: bbox)
        } catch {
            lastError = error.localizedDescription
            // Keep stale cached data if available
            if let stale = readCache(for: bbox) {
                currentSkiArea = stale
                applySkiAreaNameIfNeeded(stale, fallbackBBox: bbox)
            }
        }
    }

    /// Reclassify current place into "resort name first, region fallback".
    /// This method is idempotent and only re-runs when movement passes threshold
    /// or when leaving the active resort bounding box.
    func classifyCurrentPlace(at coordinate: CLLocationCoordinate2D) async {
        if let from = lastClassifiedCoordinate?.clLocationCoordinate2D,
           !shouldReclassify(from: from, to: coordinate) {
            return
        }

        if let activeResortBBox,
           activeResortBBox.contains(coordinate),
           sanitizeName(displayResortName) != nil {
            lastClassifiedCoordinate = Coordinate(coordinate)
            return
        }

        let candidates = await fetchNearbyAreas(
            center: coordinate,
            radiusMeters: Self.defaultNearbySearchRadiusMeters,
            limit: 40
        )

        if let matched = selectBestMatchingArea(containing: coordinate, candidates: candidates) {
            displayResortName = matched.name
            displayRegionName = nil
            activeResortId = matched.id
            activeResortBBox = boundsFor(area: matched)
            lastClassifiedCoordinate = Coordinate(coordinate)
            return
        }

        let regionName = await reverseGeocodeRegionName(for: coordinate)
        displayResortName = nil
        displayRegionName = sanitizeName(regionName)
        activeResortId = nil
        activeResortBBox = nil
        lastClassifiedCoordinate = Coordinate(coordinate)
    }

    /// Determines if we should re-run place classification.
    func shouldReclassify(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Bool {
        if CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) >= Self.defaultReclassifyDistanceMeters {
            return true
        }

        if let activeResortBBox, !activeResortBBox.contains(to) {
            return true
        }

        return false
    }

    /// Search nearby named ski areas around a location.
    func fetchNearbyAreas(
        center: CLLocationCoordinate2D,
        radiusMeters: Double = SkiMapCacheService.defaultNearbySearchRadiusMeters,
        limit: Int = 10
    ) async -> [NearbySkiArea] {
        if let snapshot = readNearbyAreasSnapshot(),
           canReuseNearbySnapshot(snapshot, center: center, radiusMeters: radiusMeters) {
            lastError = nil
            return nearbyAreasFromSnapshot(snapshot, center: center, limit: limit)
        }

        do {
            lastError = nil
            var queryRadius = radiusMeters
            var areas = try await overpassService.searchNearbySkiAreas(
                center: center,
                radiusMeters: queryRadius,
                limit: max(limit, 40)
            )

            if areas.isEmpty,
               radiusMeters < Self.extendedNearbySearchRadiusMeters {
                queryRadius = Self.extendedNearbySearchRadiusMeters
                areas = try await overpassService.searchNearbySkiAreas(
                    center: center,
                    radiusMeters: queryRadius,
                    limit: max(limit, 40)
                )
            }

            writeNearbyAreasSnapshot(.init(
                fetchedAt: Date(),
                center: Coordinate(center),
                radiusMeters: queryRadius,
                areas: areas
            ))
            return Array(areas.prefix(max(0, limit)))
        } catch {
            lastError = error.localizedDescription

            // Fallback to cached nearby areas if they're relevant to current location.
            if let snapshot = readNearbyAreasSnapshot(),
               canFallbackToNearbySnapshot(snapshot, center: center, radiusMeters: radiusMeters) {
                return nearbyAreasFromSnapshot(snapshot, center: center, limit: limit)
            }
            return []
        }
    }

    /// Cache one nearby area and update index metadata.
    /// Set `updateCurrent` to `false` to cache without changing the displayed ski area.
    func cacheArea(_ area: NearbySkiArea, updateCurrent: Bool = true) async {
        let preferredRadius = area.recommendedRadiusMeters > 0
            ? area.recommendedRadiusMeters
            : Self.defaultAreaCacheRadiusMeters
        let cacheRadius = max(1000, preferredRadius)
        let bbox = area.bounds ?? BoundingBox.around(
            center: area.center.clLocationCoordinate2D,
            radiusMeters: cacheRadius
        )
        await cacheArea(
            id: area.id,
            name: area.name,
            center: area.center,
            radiusMeters: cacheRadius,
            boundingBox: bbox,
            updateCurrent: updateCurrent
        )
    }

    /// Refresh an existing cached area by ID.
    func refreshArea(id: String) async {
        guard let entry = readIndex().entries.first(where: { $0.id == id }) else { return }
        await cacheArea(
            id: entry.id,
            name: entry.name,
            center: entry.center,
            radiusMeters: entry.radiusMeters,
            boundingBox: entry.boundingBox
        )
    }

    /// Remove a cached area and its persisted map data.
    func removeArea(id: String) {
        var index = readIndex()
        guard let entry = index.entries.first(where: { $0.id == id }) else { return }

        try? FileManager.default.removeItem(at: cacheFileURL(forKey: entry.cacheKey))
        index.entries.removeAll { $0.id == id }
        writeIndex(index)

        if currentSkiArea?.boundingBox.cacheKey == entry.cacheKey {
            currentSkiArea = nil
        }

        if activeResortId == id {
            activeResortId = nil
            activeResortBBox = nil
            displayResortName = nil
        }
    }

    /// List all user-cached ski areas.
    func listCachedAreas() -> [CachedAreaSummary] {
        let index = pruneOrphanedIndexEntries()
        return index.entries
            .map(makeSummary(from:))
            .sorted { $0.fetchedAt > $1.fetchedAt }
    }

    /// Load a cached area into current map state.
    func loadCachedArea(id: String) {
        var index = readIndex()
        guard let entry = index.entries.first(where: { $0.id == id }) else { return }

        guard let cached = readCache(forKey: entry.cacheKey) else {
            index.entries.removeAll { $0.id == id }
            writeIndex(index)
            return
        }
        currentSkiArea = cached
        displayResortName = sanitizeName(entry.name) ?? sanitizeName(cached.name)
        displayRegionName = nil
        activeResortId = entry.id
        activeResortBBox = entry.boundingBox
    }

    func isAreaOperationInProgress(_ id: String) -> Bool {
        activeAreaOperations.contains(id)
    }

    /// Clear all cached ski area data.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        createCacheDirectoryIfNeeded()
        currentSkiArea = nil
        activeAreaOperations.removeAll()
        lastError = nil

        displayResortName = nil
        displayRegionName = nil
        lastClassifiedCoordinate = nil
        activeResortId = nil
        activeResortBBox = nil
        lastReverseGeocodeDate = nil
        lastReverseGeocodeCoordinate = nil
        lastReverseGeocodedRegion = nil
    }

    #if DEBUG
    /// Inject ski area data directly for previews and tests.
    func setPreviewData(_ data: SkiAreaData) {
        currentSkiArea = data
        applySkiAreaNameIfNeeded(data, fallbackBBox: data.boundingBox)
    }
    #endif

    // MARK: - File Cache

    private func cacheFileURL(for bbox: BoundingBox) -> URL {
        cacheFileURL(forKey: bbox.cacheKey)
    }

    private func cacheFileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func readCache(for bbox: BoundingBox) -> SkiAreaData? {
        readCache(forKey: bbox.cacheKey)
    }

    private func readCache(forKey key: String) -> SkiAreaData? {
        let url = cacheFileURL(forKey: key)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SkiAreaData.self, from: data)
        } catch {
            Self.logger.error("Failed to read cache for key \(key): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writeCache(_ skiArea: SkiAreaData, for bbox: BoundingBox) {
        let url = cacheFileURL(for: bbox)
        do {
            let data = try JSONEncoder().encode(skiArea)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to write cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Index

    private struct CacheIndex: Codable {
        var entries: [CacheIndexEntry] = []
    }

    private struct CacheIndexEntry: Codable {
        let id: String
        var name: String
        var center: Coordinate
        var radiusMeters: Double
        var boundingBox: BoundingBox
        var cacheKey: String
        var fetchedAt: Date
        var trailCount: Int
        var liftCount: Int
        var lastError: String?
    }

    private func readIndex() -> CacheIndex {
        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode(CacheIndex.self, from: data)
        } catch {
            // Missing index is normal on first run; only log non-trivial errors
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFileReadNoSuchFileError {
                Self.logger.error("Failed to read cache index: \(error.localizedDescription, privacy: .public)")
            }
            return CacheIndex()
        }
    }

    private func writeIndex(_ index: CacheIndex) {
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write cache index: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    private func pruneOrphanedIndexEntries() -> CacheIndex {
        var index = readIndex()
        let originalCount = index.entries.count
        index.entries.removeAll { !FileManager.default.fileExists(atPath: cacheFileURL(forKey: $0.cacheKey).path) }
        if index.entries.count != originalCount {
            writeIndex(index)
        }
        return index
    }

    private func makeSummary(from entry: CacheIndexEntry) -> CachedAreaSummary {
        CachedAreaSummary(
            id: entry.id,
            name: entry.name,
            center: entry.center,
            boundingBox: entry.boundingBox,
            fetchedAt: entry.fetchedAt,
            expiresAt: entry.fetchedAt.addingTimeInterval(cacheTTL),
            trailCount: entry.trailCount,
            liftCount: entry.liftCount,
            lastError: entry.lastError
        )
    }

    private func cacheArea(
        id: String,
        name: String,
        center: Coordinate,
        radiusMeters: Double,
        boundingBox: BoundingBox,
        updateCurrent: Bool = true
    ) async {
        activeAreaOperations.insert(id)
        isLoading = true
        defer {
            activeAreaOperations.remove(id)
            isLoading = false
        }

        do {
            let skiArea = try await overpassService.fetchSkiArea(boundingBox: boundingBox)
            if updateCurrent {
                currentSkiArea = skiArea
                displayResortName = sanitizeName(name) ?? sanitizeName(skiArea.name)
                displayRegionName = nil
                activeResortId = id
                activeResortBBox = boundingBox
            }
            writeCache(skiArea, for: boundingBox)
            lastError = nil

            var index = readIndex()
            let cacheKey = boundingBox.cacheKey
            let fetchedAt = Date()

            if let existingIndex = index.entries.firstIndex(where: { $0.id == id }) {
                let oldCacheKey = index.entries[existingIndex].cacheKey
                if oldCacheKey != cacheKey {
                    try? FileManager.default.removeItem(at: cacheFileURL(forKey: oldCacheKey))
                }

                index.entries[existingIndex].name = name
                index.entries[existingIndex].center = center
                index.entries[existingIndex].radiusMeters = radiusMeters
                index.entries[existingIndex].boundingBox = boundingBox
                index.entries[existingIndex].cacheKey = cacheKey
                index.entries[existingIndex].fetchedAt = fetchedAt
                index.entries[existingIndex].trailCount = skiArea.trails.count
                index.entries[existingIndex].liftCount = skiArea.lifts.count
                index.entries[existingIndex].lastError = nil
            } else {
                index.entries.append(CacheIndexEntry(
                    id: id,
                    name: name,
                    center: center,
                    radiusMeters: radiusMeters,
                    boundingBox: boundingBox,
                    cacheKey: cacheKey,
                    fetchedAt: fetchedAt,
                    trailCount: skiArea.trails.count,
                    liftCount: skiArea.lifts.count,
                    lastError: nil
                ))
            }
            writeIndex(index)
        } catch {
            lastError = error.localizedDescription

            var index = readIndex()
            if let existingIndex = index.entries.firstIndex(where: { $0.id == id }) {
                index.entries[existingIndex].lastError = error.localizedDescription
                writeIndex(index)
            }

            if let stale = readCache(for: boundingBox) {
                currentSkiArea = stale
                applySkiAreaNameIfNeeded(stale, fallbackBBox: boundingBox)
            }
        }
    }

    private func createCacheDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Nearby Areas Cache

    private struct NearbyAreasSnapshot: Codable {
        let fetchedAt: Date
        let center: Coordinate
        let radiusMeters: Double
        let areas: [NearbySkiArea]
    }

    private func readNearbyAreasSnapshot() -> NearbyAreasSnapshot? {
        do {
            let data = try Data(contentsOf: nearbyAreasURL)
            return try JSONDecoder().decode(NearbyAreasSnapshot.self, from: data)
        } catch {
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSFileReadNoSuchFileError {
                Self.logger.error("Failed to read nearby areas cache: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private func writeNearbyAreasSnapshot(_ snapshot: NearbyAreasSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: nearbyAreasURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write nearby areas cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func canReuseNearbySnapshot(
        _ snapshot: NearbyAreasSnapshot,
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> Bool {
        guard Date().timeIntervalSince(snapshot.fetchedAt) <= cacheTTL else { return false }
        guard abs(snapshot.radiusMeters - radiusMeters) <= 1 else { return false }

        let distance = CLLocation(
            latitude: snapshot.center.latitude,
            longitude: snapshot.center.longitude
        ).distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))

        return distance <= Self.defaultReclassifyDistanceMeters
    }

    private func canFallbackToNearbySnapshot(
        _ snapshot: NearbyAreasSnapshot,
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> Bool {
        guard Date().timeIntervalSince(snapshot.fetchedAt) <= cacheTTL else { return false }

        let distance = CLLocation(
            latitude: snapshot.center.latitude,
            longitude: snapshot.center.longitude
        ).distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))

        return distance <= max(radiusMeters, snapshot.radiusMeters)
    }

    private func nearbyAreasFromSnapshot(
        _ snapshot: NearbyAreasSnapshot,
        center: CLLocationCoordinate2D,
        limit: Int
    ) -> [NearbySkiArea] {
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let sorted = snapshot.areas
            .map { area -> NearbySkiArea in
                let areaLocation = CLLocation(
                    latitude: area.center.latitude,
                    longitude: area.center.longitude
                )
                return NearbySkiArea(
                    id: area.id,
                    name: area.name,
                    center: area.center,
                    distanceMeters: origin.distance(from: areaLocation),
                    recommendedRadiusMeters: area.recommendedRadiusMeters,
                    bounds: area.bounds
                )
            }
            .sorted(by: { $0.distanceMeters < $1.distanceMeters })

        return Array(sorted.prefix(max(0, limit)))
    }

    // MARK: - Place Classification Helpers

    private func selectBestMatchingArea(
        containing coordinate: CLLocationCoordinate2D,
        candidates: [NearbySkiArea]
    ) -> NearbySkiArea? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return candidates
            .compactMap { area -> (NearbySkiArea, Double, Double)? in
                let bounds = boundsFor(area: area)
                guard bounds.contains(coordinate) else { return nil }

                let centerLocation = CLLocation(latitude: area.center.latitude, longitude: area.center.longitude)
                let distance = origin.distance(from: centerLocation)
                let areaSize = bounds.approximateAreaMetersSquared
                return (area, areaSize, distance)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }
            .first?.0
    }

    private func boundsFor(area: NearbySkiArea) -> BoundingBox {
        if let bounds = area.bounds {
            return bounds
        }

        let radius = max(1000, area.recommendedRadiusMeters)
        return BoundingBox.around(center: area.center.clLocationCoordinate2D, radiusMeters: radius)
    }

    private func applySkiAreaNameIfNeeded(_ area: SkiAreaData, fallbackBBox: BoundingBox) {
        guard let name = sanitizeName(area.name) else { return }
        displayResortName = name
        displayRegionName = nil
        activeResortId = "bbox-\(fallbackBBox.cacheKey)"
        activeResortBBox = area.boundingBox
    }

    private func sanitizeName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func reverseGeocodeRegionName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let current = Coordinate(coordinate)

        if let lastDate = lastReverseGeocodeDate,
           Date().timeIntervalSince(lastDate) < Self.reverseGeocodeThrottleSeconds,
           let lastCoordinate = lastReverseGeocodeCoordinate,
           CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= Self.defaultReclassifyDistanceMeters {
            return lastReverseGeocodedRegion
        }

        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let region = try await reverseGeocodeRegionNameUsingMapKit(for: location)

            lastReverseGeocodeDate = Date()
            lastReverseGeocodeCoordinate = current
            lastReverseGeocodedRegion = region
            return region
        } catch {
            Self.logger.error("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
            return lastReverseGeocodedRegion
        }
    }

    @available(iOS 26.0, *)
    private func reverseGeocodeRegionNameUsingMapKit(for location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }
        let mapItems = try await request.mapItems
        let first = mapItems.first
        return sanitizeName(first?.addressRepresentations?.cityName) ??
            sanitizeName(first?.addressRepresentations?.regionName) ??
            sanitizeName(first?.name) ??
            sanitizeName(first?.address?.shortAddress)
    }
}
