//
//  ServerProfile.swift
//  Snowly
//
//  User-managed server profile for connecting to self-hosted backends.
//  Stored in local-only SwiftData store (not synced via CloudKit).
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Server Role

enum ServerRole: String, CaseIterable, Codable, Identifiable {
    case crew = "crew"
    case data = "data"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crew: return String(localized: "server_role_crew")
        case .data: return String(localized: "server_role_data")
        }
    }

    var iconName: String {
        switch self {
        case .crew: return "person.3"
        case .data: return "arrow.up.circle"
        }
    }

    var color: Color {
        switch self {
        case .crew: return .blue
        case .data: return .indigo
        }
    }
}

// MARK: - Registration Status

enum RegistrationStatus: String, Codable {
    case pending = "pending"
    case registered = "registered"
    case failed = "failed"
}

// MARK: - ServerProfile

@Model
final class ServerProfile {
    @Attribute(.unique) var id: UUID = UUID()
    var alias: String = ""
    var urlString: String = ""
    var isActive: Bool = false
    /// Raw string stored in SwiftData; use `resolvedRegistrationStatus` for typed access.
    var registrationStatus: String = RegistrationStatus.pending.rawValue
    var createdAt: Date = Date()
    /// Raw role strings stored in SwiftData.
    var roles: [String] = []

    var url: URL? {
        URL(string: urlString)
    }

    /// Base URL for API requests (appends `/api/v1` to the server URL).
    var apiBaseURL: URL? {
        url?.appendingPathComponent("api/v1")
    }

    /// Typed roles derived from raw strings.
    var typedRoles: [ServerRole] {
        roles.compactMap { ServerRole(rawValue: $0) }
    }

    var resolvedRegistrationStatus: RegistrationStatus {
        RegistrationStatus(rawValue: registrationStatus) ?? .pending
    }

    init(
        id: UUID = UUID(),
        alias: String,
        urlString: String,
        isActive: Bool = false,
        registrationStatus: RegistrationStatus = .pending,
        createdAt: Date = Date(),
        roles: [String] = []
    ) {
        self.id = id
        self.alias = alias
        self.urlString = urlString
        self.isActive = isActive
        self.registrationStatus = registrationStatus.rawValue
        self.createdAt = createdAt
        self.roles = roles
    }
}
