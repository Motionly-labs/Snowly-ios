//
//  CrewMembershipEvent.swift
//  Snowly
//
//  A membership change event (join/leave) derived from server snapshots.
//

import Foundation

struct CrewMembershipEvent: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        case joined
        case left
    }

    let kind: Kind
    let memberId: String
    let displayName: String
    let occurredAt: Date

    var id: String {
        "\(kind.rawValue)-\(memberId)-\(occurredAt.timeIntervalSince1970)"
    }
}
