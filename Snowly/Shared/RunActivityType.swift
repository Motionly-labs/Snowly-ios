//
//  RunActivityType.swift
//  Snowly
//
//  Shared between iOS and watchOS targets.
//  Activity type for a run segment.
//

/// Activity type for a run segment.
enum RunActivityType: String, Codable, Sendable {
    case skiing
    case chairlift
    case idle
}
