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
    case heartRate
    case heartRateCurve
}

// MARK: - Per-Card Config

struct ActiveTrackingCardConfig: Codable, Sendable, Equatable {
    var windowSeconds: TimeInterval?
    var smoothingAlpha: Double?

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

// MARK: - Render Inputs

/// Shared card-input metadata. Semantic meaning is resolved upstream before it reaches
/// these inputs; views may restyle or smooth curves, but must not redefine the values.
protocol ActiveTrackingCardInputProtocol: Sendable {
    var instanceId: UUID { get }
    var kind: ActiveTrackingCardKind { get }
    var slot: ActiveTrackingSlot { get }
    var family: ActiveTrackingCardInputFamily { get }
    var title: String { get }
    var subtitle: String? { get }
}

protocol ActiveTrackingScalarCardInputProtocol: ActiveTrackingCardInputProtocol {
    var primaryValue: ActiveTrackingCardPrimaryValue { get }
}

protocol ActiveTrackingSeriesCardInputProtocol: ActiveTrackingCardInputProtocol {
    var primaryValue: ActiveTrackingCardPrimaryValue? { get }
    var seriesPayload: ActiveTrackingSeriesPayload { get }
    var renderingPolicy: ActiveTrackingSeriesRenderingPolicy { get }
}

protocol ActiveTrackingCompositeCardInputProtocol: ActiveTrackingCardInputProtocol {
    var chips: [ActiveTrackingCompositeChip] { get }
    var embeddedSeries: [ActiveTrackingEmbeddedSeries] { get }
}

enum ActiveTrackingCardInputFamily: String, Sendable, Equatable {
    case scalar
    case series
    case composite
}

struct ActiveTrackingNumericValue: Sendable, Equatable {
    let value: Double
    let decimals: Int
    let unit: String
    let animationDelay: Double
}

struct ActiveTrackingTextValue: Sendable, Equatable {
    let value: String
    let unit: String
}

enum ActiveTrackingCardPrimaryValue: Sendable, Equatable {
    case numeric(ActiveTrackingNumericValue)
    case text(ActiveTrackingTextValue)

    var numericValue: ActiveTrackingNumericValue? {
        guard case .numeric(let value) = self else { return nil }
        return value
    }

    var textValue: ActiveTrackingTextValue? {
        guard case .text(let value) = self else { return nil }
        return value
    }
}

struct ActiveTrackingScalarCardInput: ActiveTrackingScalarCardInputProtocol, Sendable, Equatable {
    let instanceId: UUID
    let kind: ActiveTrackingCardKind
    let slot: ActiveTrackingSlot
    let title: String
    let primaryValue: ActiveTrackingCardPrimaryValue
    let subtitle: String?
    let family: ActiveTrackingCardInputFamily = .scalar
}

enum ActiveTrackingSeriesPayload: Sendable, Equatable {
    case altitude([AltitudeSample])
    case speed([SpeedSample])
    case heartRate([HeartRateSample])

    var altitudeSamples: [AltitudeSample]? {
        guard case .altitude(let samples) = self else { return nil }
        return samples
    }

    var speedSamples: [SpeedSample]? {
        guard case .speed(let samples) = self else { return nil }
        return samples
    }

    var heartRateSamples: [HeartRateSample]? {
        guard case .heartRate(let samples) = self else { return nil }
        return samples
    }
}

/// Render-only knobs for chart beautification. Semantic labels remain authoritative and
/// must never be recomputed from the rendered path.
struct ActiveTrackingSeriesRenderingPolicy: Sendable, Equatable {
    let windowSeconds: TimeInterval?
    let smoothingAlpha: Double?
    let allowsRenderOnlySmoothing: Bool

    nonisolated static let renderOnly = ActiveTrackingSeriesRenderingPolicy(
        windowSeconds: nil,
        smoothingAlpha: nil,
        allowsRenderOnlySmoothing: true
    )
}

struct ActiveTrackingSeriesCardInput: ActiveTrackingSeriesCardInputProtocol, Sendable, Equatable {
    let instanceId: UUID
    let kind: ActiveTrackingCardKind
    let slot: ActiveTrackingSlot
    let title: String
    let primaryValue: ActiveTrackingCardPrimaryValue?
    let subtitle: String?
    let seriesPayload: ActiveTrackingSeriesPayload
    let renderingPolicy: ActiveTrackingSeriesRenderingPolicy
    let family: ActiveTrackingCardInputFamily = .series
}

enum ActiveTrackingEmbeddedSeriesRole: String, Sendable, Equatable {
    case altitude
    case speed
    case heartRate
}

struct ActiveTrackingEmbeddedSeries: Sendable, Equatable {
    let role: ActiveTrackingEmbeddedSeriesRole
    let payload: ActiveTrackingSeriesPayload
    let renderingPolicy: ActiveTrackingSeriesRenderingPolicy
}

struct ActiveTrackingCompositeChip: Sendable, Equatable {
    let kind: ActiveTrackingCardKind
    let title: String
    let primaryValue: ActiveTrackingCardPrimaryValue
}

struct ActiveTrackingCompositeCardInput: ActiveTrackingCompositeCardInputProtocol, Sendable, Equatable {
    let instanceId: UUID
    let kind: ActiveTrackingCardKind
    let slot: ActiveTrackingSlot
    let title: String
    let subtitle: String?
    let chips: [ActiveTrackingCompositeChip]
    let embeddedSeries: [ActiveTrackingEmbeddedSeries]
    let family: ActiveTrackingCardInputFamily = .composite
}

enum AnyActiveTrackingCardInput: Sendable, Equatable {
    case scalar(ActiveTrackingScalarCardInput)
    case series(ActiveTrackingSeriesCardInput)
    case composite(ActiveTrackingCompositeCardInput)

    var instanceId: UUID {
        switch self {
        case .scalar(let input):
            input.instanceId
        case .series(let input):
            input.instanceId
        case .composite(let input):
            input.instanceId
        }
    }

    var kind: ActiveTrackingCardKind {
        switch self {
        case .scalar(let input):
            input.kind
        case .series(let input):
            input.kind
        case .composite(let input):
            input.kind
        }
    }

    var family: ActiveTrackingCardInputFamily {
        switch self {
        case .scalar(let input):
            input.family
        case .series(let input):
            input.family
        case .composite(let input):
            input.family
        }
    }
}
