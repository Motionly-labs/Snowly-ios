//
//  ResortResolverTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import Snowly

@Suite(.serialized)
@MainActor
struct ResortResolverTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Resort.self])
        let configuration = ModelConfiguration(
            "ResortResolverTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: Resort.self,
            configurations: configuration
        )
    }

    @Test func resolveCurrentResort_refreshesFromCoordinateInsideKnownArea() async throws {
        let container = try makeInMemoryContainer()
        let coordinate = CLLocationCoordinate2D(latitude: 46.0207, longitude: 7.7491)
        let boundingBox = BoundingBox.around(center: coordinate, radiusMeters: 1200)
        let skiMapService = SkiMapCacheService(
            cacheDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        #if DEBUG
        skiMapService.setPreviewData(
            SkiAreaData(
                trails: [],
                lifts: [],
                fetchedAt: Date(),
                boundingBox: boundingBox,
                name: "Zermatt"
            )
        )
        #endif

        let resort = await ResortResolver.resolveCurrentResort(
            from: skiMapService,
            using: coordinate,
            in: container.mainContext
        )

        #expect(resort?.name == "Zermatt")

        let storedResorts = try container.mainContext.fetch(FetchDescriptor<Resort>())
        #expect(storedResorts.count == 1)
        #expect(storedResorts.first?.name == "Zermatt")
    }
}
