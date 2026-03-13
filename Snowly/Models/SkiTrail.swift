//
//  SkiTrail.swift
//  Snowly
//
//  Ski trail (piste) data from OpenStreetMap via Overpass API.
//

import Foundation
import CoreLocation

// MARK: - Piste Difficulty

/// Standard piste difficulty levels from OSM `piste:difficulty` tag.
enum PisteDifficulty: String, Codable, Sendable, CaseIterable {
    case novice
    case easy
    case intermediate
    case advanced
    case expert
    case freeride
    case unknown

    init(osmValue: String?) {
        guard let value = osmValue?.lowercased() else {
            self = .unknown
            return
        }
        self = PisteDifficulty(rawValue: value) ?? .unknown
    }
}

// MARK: - Piste Type

/// Piste type from OSM `piste:type` tag.
enum PisteType: String, Codable, Sendable {
    case downhill
    case nordic
    case skitour
    case sled
    case hike
    case sleigh
    case unknown

    init(osmValue: String?) {
        guard let value = osmValue?.lowercased() else {
            self = .unknown
            return
        }
        self = PisteType(rawValue: value) ?? .unknown
    }
}

// MARK: - Ski Trail

/// A ski trail parsed from Overpass API response.
struct SkiTrail: Codable, Identifiable, Sendable {
    let id: String
    let name: String?
    let difficulty: PisteDifficulty
    let type: PisteType
    let coordinates: [Coordinate]
}
