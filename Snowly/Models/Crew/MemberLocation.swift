//
//  MemberLocation.swift
//  Snowly
//
//  Location snapshot for a crew member + upload payload.
//

import Foundation
import CoreLocation

/// A crew member's latest location snapshot, received from the server.
struct MemberLocation: Codable, Sendable, Equatable, Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
    let hasAvatar: Bool
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date
    let activityType: MemberActivityType
    let isStale: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// What the member is currently doing.
enum MemberActivityType: String, Codable, Sendable {
    case idle
    case skiing
    case onLift
    case unknown
}

/// Payload sent to the server when uploading the current location.
struct LocationUpload: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date
    let batteryLevel: Double?
    let activityType: String?
}
