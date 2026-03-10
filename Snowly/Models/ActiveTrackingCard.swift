//
//  ActiveTrackingCard.swift
//  Snowly
//
//  Card instance model for the active-tracking dashboard.
//  Each card has a stable UUID identity, allowing duplicate kinds
//  with different configs, and supports forward-compatible persistence.
//

import Foundation

// MARK: - Slot / Presentation Enums

enum ActiveTrackingSlot: String, Codable, Sendable, Equatable {
    case hero
    case grid
}

enum ActiveTrackingPresentationKind: String, Codable, Sendable, Equatable {
    case scalar
    case series
    case profile
    case text
    case heartRateSeries
}

// MARK: - Card Kind

enum ActiveTrackingCardKind: String, Codable, CaseIterable, Sendable, Equatable {
    case currentSpeed
    case peakSpeed
    case avgSpeed
    case vertical
    case distance
    case runCount
    case skiTime
    case liftCount
    case currentAltitude
    case altitudeCurve
    case speedCurve
    case profile
    case heartRate
    case heartRateCurve
}

// MARK: - Per-Card Config

struct ActiveTrackingCardConfig: Codable, Sendable, Equatable {
    var windowSeconds: TimeInterval?
    var smoothingAlpha: Double?
    /// Card kinds shown as chips in the overview (.profile) hero card.
    var profileStatKinds: [String]?

    nonisolated static let empty = ActiveTrackingCardConfig()
}

// MARK: - Card Instance

/// The persisted unit for one dashboard card.
/// Identity is `instanceId` (UUID), not `kind`, so the same kind may appear multiple times.
struct ActiveTrackingCardInstance: Codable, Identifiable, Sendable, Equatable {
    let instanceId: UUID
    let kind: ActiveTrackingCardKind
    let slot: ActiveTrackingSlot
    let presentationKind: ActiveTrackingPresentationKind
    var config: ActiveTrackingCardConfig

    var id: UUID { instanceId }

    nonisolated static func make(kind: ActiveTrackingCardKind) -> ActiveTrackingCardInstance {
        let def = ActiveTrackingCardRegistry.definition(for: kind)
        return ActiveTrackingCardInstance(
            instanceId: UUID(),
            kind: kind,
            slot: def.defaultSlot,
            presentationKind: def.defaultPresentationKind,
            config: def.defaultConfig
        )
    }
}

// MARK: - Snapshots

enum ActiveTrackingCardSnapshot: Sendable, Equatable {
    case scalar(ScalarCardSnapshot)
    case series(SeriesCardSnapshot)
    case profile(ProfileCardSnapshot)
    case text(TextCardSnapshot)
    case heartRateSeries(HeartRateSeriesCardSnapshot)
}

struct ScalarCardSnapshot: Sendable, Equatable {
    let kind: ActiveTrackingCardKind
    let value: Double
    let decimals: Int
    let unit: String
    let animationDelay: Double
}

struct SeriesCardSnapshot: Sendable, Equatable {
    let kind: ActiveTrackingCardKind
    let samples: [AltitudeSample]
}

struct ProfileCardSnapshot: Sendable, Equatable {
    let altitudeSamples: [AltitudeSample]
    let speedSamples: [SpeedSample]
}

struct TextCardSnapshot: Sendable, Equatable {
    let kind: ActiveTrackingCardKind
    let value: String
    let unit: String
    let subtitle: String
}

struct HeartRateSeriesCardSnapshot: Sendable, Equatable {
    let kind: ActiveTrackingCardKind
    let samples: [HeartRateSample]
}
