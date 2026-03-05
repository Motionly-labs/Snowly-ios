//
//  SkiMapCacheService.swift
//  Snowly
//
//  Coordinates ski area data fetching with local file caching.
//  Cache key = bounding box hash; default TTL = 7 days.
//

import Foundation
import CoreLocation
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

    private let overpassService: OverpassService
    private let cacheDirectory: URL
    private let cacheTTL: TimeInterval
    private let indexURL: URL
    private static let logger = Logger(subsystem: "com.Snowly", category: "SkiMapCache")

    /// Default cache TTL: 7 days.
    nonisolated static let defaultTTL: TimeInterval = 7 * 24 * 3600
    nonisolated static let defaultNearbySearchRadiusMeters: Double = 30000
    nonisolated static let defaultAreaCacheRadiusMeters: Double = 6000

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

        createCacheDirectoryIfNeeded()
        pruneOrphanedIndexEntries()
    }

    /// Load ski area data for a location. Checks cache first, then fetches from API.
    func loadSkiArea(center: CLLocationCoordinate2D, radiusMeters: Double = 5000) async {
        let bbox = BoundingBox.around(center: center, radiusMeters: radiusMeters)

        // Check cache
        if let cached = readCache(for: bbox), !cached.isExpired(maxAge: cacheTTL) {
            currentSkiArea = cached
            return
        }

        // Fetch from API
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let skiArea = try await overpassService.fetchSkiArea(boundingBox: bbox)
            currentSkiArea = skiArea
            writeCache(skiArea, for: bbox)
        } catch {
            lastError = error.localizedDescription
            // Keep stale cached data if available
            if let stale = readCache(for: bbox) {
                currentSkiArea = stale
            }
        }
    }

    /// Search nearby named ski areas around a location.
    func fetchNearbyAreas(
        center: CLLocationCoordinate2D,
        radiusMeters: Double = SkiMapCacheService.defaultNearbySearchRadiusMeters,
        limit: Int = 10
    ) async -> [NearbySkiArea] {
        do {
            lastError = nil
            return try await overpassService.searchNearbySkiAreas(
                center: center,
                radiusMeters: radiusMeters,
                limit: limit
            )
        } catch {
            lastError = error.localizedDescription
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
        let bbox = BoundingBox.around(
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
    }

    #if DEBUG
    /// Inject ski area data directly for previews and testing.
    func setPreviewData(_ data: SkiAreaData) {
        currentSkiArea = data
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
            }
            writeCache(skiArea, for: boundingBox)
            lastError = nil

            var index = readIndex()
            let cacheKey = boundingBox.cacheKey
            let fetchedAt = Date()

            if let existingIndex = index.entries.firstIndex(where: { $0.id == id }) {
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
            }
        }
    }

    private func createCacheDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
}
