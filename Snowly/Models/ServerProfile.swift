//
//  ServerProfile.swift
//  Snowly
//
//  User-managed server profile for connecting to self-hosted backends.
//  Stored in local-only SwiftData store (not synced via CloudKit).
//

import Foundation
import SwiftData

@Model
final class ServerProfile {
    @Attribute(.unique) var id: UUID = UUID()
    var alias: String = ""
    var urlString: String = ""
    var isActive: Bool = false
    var isDefault: Bool = false
    var createdAt: Date = Date()

    var url: URL? {
        URL(string: urlString)
    }

    /// Base URL for API requests (appends `/api/v1` to the server URL).
    var apiBaseURL: URL? {
        url?.appendingPathComponent("api/v1")
    }

    init(
        id: UUID = UUID(),
        alias: String,
        urlString: String,
        isActive: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.alias = alias
        self.urlString = urlString
        self.isActive = isActive
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}
