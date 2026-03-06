//
//  SkiMapCacheServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@MainActor
struct SkiMapCacheServiceTests {

    private func makeIsolatedCacheDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func initialState() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        #expect(service.currentSkiArea == nil)
        #expect(service.isLoading == false)
        #expect(service.lastError == nil)
    }

    @Test func clearCache_resetsSkiArea() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        service.clearCache()
        #expect(service.currentSkiArea == nil)
    }

    @Test func defaultTTL() {
        #expect(SkiMapCacheService.defaultTTL == 7 * 24 * 3600)
    }

    @Test func displayTitle_defaultsToFallback() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        #expect(service.displayTitle == SkiMapCacheService.fallbackDisplayTitle)
    }

    @Test func listCachedAreas_emptyByDefault() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        #expect(service.listCachedAreas().isEmpty)
    }

    @Test func areaOperationState_defaultFalse() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        #expect(!service.isAreaOperationInProgress("relation-1"))
    }

    @Test func shouldReclassify_trueWhenDistanceExceedsThreshold() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        let from = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)
        let to = CLLocationCoordinate2D(latitude: 46.03, longitude: 7.0) // ~3.3km north
        #expect(service.shouldReclassify(from: from, to: to))
    }

    @Test func shouldReclassify_falseWhenNearbyAndNoActiveBounds() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        let from = CLLocationCoordinate2D(latitude: 46.0, longitude: 7.0)
        let to = CLLocationCoordinate2D(latitude: 46.005, longitude: 7.0) // ~550m north
        #expect(!service.shouldReclassify(from: from, to: to))
    }

    #if DEBUG
    @Test func setPreviewData_setsCurrentSkiArea() {
        let service = SkiMapCacheService(cacheDirectory: makeIsolatedCacheDirectory())
        let data = SkiAreaData(
            trails: [],
            lifts: [],
            fetchedAt: Date(),
            boundingBox: BoundingBox(south: 0, west: 0, north: 1, east: 1),
            name: "Test Resort"
        )
        service.setPreviewData(data)
        #expect(service.currentSkiArea != nil)
        #expect(service.currentSkiArea?.name == "Test Resort")
    }
    #endif
}
