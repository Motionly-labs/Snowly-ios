//
//  SkiLift.swift
//  Snowly
//
//  Ski lift (aerialway) data from OpenStreetMap via Overpass API.
//

import Foundation
import CoreLocation

// MARK: - Aerialway Type

/// Aerialway types from OSM `aerialway` tag.
enum AerialwayType: String, Codable, Sendable {
    case chairLift = "chair_lift"
    case gondola
    case cableCar = "cable_car"
    case mixedLift = "mixed_lift"
    case dragLift = "drag_lift"
    case tBar = "t-bar"
    case jBar = "j-bar"
    case platter
    case ropeTow = "rope_tow"
    case magicCarpet = "magic_carpet"
    case unknown

    init(osmValue: String?) {
        guard let value = osmValue?.lowercased() else {
            self = .unknown
            return
        }
        self = AerialwayType(rawValue: value) ?? .unknown
    }
}

// MARK: - Ski Lift

/// A ski lift parsed from Overpass API response.
struct SkiLift: Codable, Identifiable, Sendable {
    let id: String
    let name: String?
    let liftType: AerialwayType
    let capacity: Int?
    let coordinates: [Coordinate]
}
