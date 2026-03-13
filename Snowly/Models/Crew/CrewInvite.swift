//
//  CrewInvite.swift
//  Snowly
//
//  Invite token for joining a crew.
//

import Foundation

/// Invite information returned by the server.
struct CrewInvite: Codable, Sendable, Equatable {
    let token: String
    let crewId: String
    let crewName: String
    let deepLink: String

    var shareURL: URL? {
        URL(string: deepLink)
    }
}

/// Preview shown before joining a crew via invite link.
struct CrewPreview: Codable, Sendable {
    let crewId: String
    let crewName: String
    let memberCount: Int
    let creatorDisplayName: String
    let isMember: Bool
}
