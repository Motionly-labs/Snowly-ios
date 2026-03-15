//
//  Resort.swift
//  Snowly
//
//  Ski resort entity — deduplicated, referenced by sessions.
//

import Foundation
import SwiftData

@Model
final class Resort {
    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var country: String = ""
    @Relationship(inverse: \SkiSession.resort)
    var sessions: [SkiSession]?

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        country: String = ""
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
    }
}
