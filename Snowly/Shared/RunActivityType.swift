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
    case lift = "chairlift"  // rawValue preserved for backward compatibility with stored data
    case idle
    case walk
}
