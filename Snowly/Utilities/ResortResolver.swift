//
//  ResortResolver.swift
//  Snowly
//
//  Resolves the current ski map selection into a persisted Resort model.
//

import Foundation
import SwiftData
import CoreLocation

struct ResolvedResortInfo: Sendable, Equatable {
    let name: String
    let coordinate: Coordinate
    let regionName: String?
}

@MainActor
enum ResortResolver {
    private static let maxDuplicateDistanceMeters = 1_000.0

    static func resolveCurrentResort(
        from skiMapService: SkiMapCacheService,
        using coordinate: CLLocationCoordinate2D?,
        in context: ModelContext
    ) async -> Resort? {
        if let coordinate {
            await skiMapService.classifyCurrentPlace(at: coordinate)
        }
        return resolveCurrentResort(from: skiMapService, in: context)
    }

    static func resolveCurrentResort(
        from skiMapService: SkiMapCacheService,
        in context: ModelContext
    ) -> Resort? {
        guard let info = skiMapService.currentResortInfo else { return nil }
        return resolve(info, in: context)
    }

    static func resolve(
        _ info: ResolvedResortInfo,
        in context: ModelContext
    ) -> Resort {
        let existingResorts = (try? context.fetch(FetchDescriptor<Resort>())) ?? []

        if let existing = existingResorts.first(where: {
            $0.name.compare(info.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && distanceBetween($0, info.coordinate) <= maxDuplicateDistanceMeters
        }) {
            if existing.country.isEmpty, let regionName = info.regionName {
                existing.country = regionName
            }
            return existing
        }

        let resort = Resort(
            name: info.name,
            latitude: info.coordinate.latitude,
            longitude: info.coordinate.longitude,
            country: info.regionName ?? ""
        )
        context.insert(resort)
        return resort
    }

    private static func distanceBetween(_ resort: Resort, _ coordinate: Coordinate) -> Double {
        CLLocation(latitude: resort.latitude, longitude: resort.longitude)
            .distance(from: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ))
    }
}
