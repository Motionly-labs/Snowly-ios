//
//  CrewPin.swift
//  Snowly
//
//  A location pin dropped by a crew member, broadcast to all teammates.
//

import Foundation
import CoreLocation

/// A pin placed by a crew member on the map with an attached message.
struct CrewPin: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let crewId: String
    let senderId: String
    let senderDisplayName: String
    let latitude: Double
    let longitude: Double
    let message: String
    let createdAt: Date
    let expiresAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isExpired: Bool {
        Date.now >= expiresAt
    }
}

/// Payload sent when creating a new pin.
struct CrewPinUpload: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let message: String
}
