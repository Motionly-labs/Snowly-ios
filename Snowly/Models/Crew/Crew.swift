//
//  Crew.swift
//  Snowly
//
//  Server-managed crew and member DTOs.
//  NOT SwiftData — ephemeral state managed by the server.
//

import Foundation

/// A group of skiers sharing real-time locations.
struct Crew: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let creatorId: String
    let createdAt: Date
    let memberCount: Int
    let maxMembers: Int
    let locationUpdateIntervalSeconds: Int
    let members: [CrewMember]
}

/// A single participant in a Crew.
struct CrewMember: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let hasAvatar: Bool
    let joinedAt: Date
    let isCreator: Bool
    let isOnline: Bool
}
