//
//  TrackingDashboardLayout.swift
//  Snowly
//
//  Persisted dashboard layout: an ordered list of card instances.
//  Encoded as `{"version":1,"instances":[...]}`. Decodes legacy
//  `{"heroCards":[...],"visibleWidgets":[...]}` format transparently.
//

import Foundation

struct TrackingDashboardLayout: Codable, Equatable {
    var instances: [ActiveTrackingCardInstance]

    static let `default` = TrackingDashboardLayout(
        instances: ActiveTrackingCardRegistry.defaultInstances
    )

    // MARK: - Decode

    static func decode(from json: String) -> TrackingDashboardLayout {
        guard let data = json.data(using: .utf8) else { return .default }

        // New format: {"version":1,"instances":[...]}
        struct Envelope: Decodable {
            let version: Int?
            let instances: [RawInstance]?
            struct RawInstance: Decodable {
                let instanceId: UUID
                let kind: String
                let slot: String
                let presentationKind: String
                let config: ActiveTrackingCardConfig
            }
        }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data),
           let rawInstances = env.instances {
            let decoded = rawInstances.compactMap { raw -> ActiveTrackingCardInstance? in
                guard let kind = ActiveTrackingCardKind(rawValue: raw.kind),
                      let slot = ActiveTrackingSlot(rawValue: raw.slot),
                      let pk   = ActiveTrackingPresentationKind(rawValue: raw.presentationKind)
                else { return nil }
                return ActiveTrackingCardInstance(
                    instanceId: raw.instanceId,
                    kind: kind,
                    slot: slot,
                    presentationKind: pk,
                    config: raw.config
                )
            }
            let demoted = Self.applySlotDemotion(to: decoded)
            let instances = Self.deduplicate(demoted)
            return instances.isEmpty ? .default : TrackingDashboardLayout(instances: instances)
        }

        // Legacy format: {"heroCards":[...],"visibleWidgets":[...]}
        struct LegacyEnvelope: Decodable {
            let heroCards: [String]?
            let visibleWidgets: [String]?
        }
        if let legacy = try? JSONDecoder().decode(LegacyEnvelope.self, from: data) {
            let heroes = (legacy.heroCards ?? [])
                .compactMap { ActiveTrackingCardKind(rawValue: $0) }
                .map { kind -> ActiveTrackingCardInstance in
                    let def = ActiveTrackingCardRegistry.definition(for: kind)
                    return ActiveTrackingCardInstance(
                        instanceId: UUID(),
                        kind: kind,
                        slot: .hero,
                        presentationKind: def.defaultPresentationKind,
                        config: def.defaultConfig
                    )
                }
            let grids = (legacy.visibleWidgets ?? [])
                .compactMap { ActiveTrackingCardKind(rawValue: $0) }
                .map { kind -> ActiveTrackingCardInstance in
                    let def = ActiveTrackingCardRegistry.definition(for: kind)
                    return ActiveTrackingCardInstance(
                        instanceId: UUID(),
                        kind: kind,
                        slot: .grid,
                        presentationKind: def.defaultPresentationKind,
                        config: def.defaultConfig
                    )
                }
            let demoted = Self.applySlotDemotion(to: heroes + grids)
            let all = Self.deduplicate(demoted)
            return all.isEmpty ? .default : TrackingDashboardLayout(instances: all)
        }

        return .default
    }

    // MARK: - Deduplication

    /// Removes duplicate kinds, keeping the first occurrence.
    /// Prevents stale persisted data from creating multiple cards of the same type.
    private static func deduplicate(_ instances: [ActiveTrackingCardInstance]) -> [ActiveTrackingCardInstance] {
        instances.uniqued(by: \.kind)
    }

    // MARK: - Slot Demotion

    /// Moves any instance whose current slot is no longer in its `supportedSlots` to `defaultSlot`.
    /// Silently migrates persisted layouts when card slot restrictions change between app versions.
    private static func applySlotDemotion(to instances: [ActiveTrackingCardInstance]) -> [ActiveTrackingCardInstance] {
        instances.map { instance in
            let def = ActiveTrackingCardRegistry.definition(for: instance.kind)
            guard def.supportedSlots.contains(instance.slot) else {
                return ActiveTrackingCardInstance(
                    instanceId: instance.instanceId,
                    kind: instance.kind,
                    slot: def.defaultSlot,
                    presentationKind: def.defaultPresentationKind,
                    config: instance.config
                )
            }
            return instance
        }
    }

    // MARK: - Encode

    func encoded() -> String {
        struct Envelope: Encodable {
            let version = 1
            let instances: [ActiveTrackingCardInstance]
        }
        guard let data = try? JSONEncoder().encode(Envelope(instances: instances)),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    // MARK: - Codable (SwiftData / direct decode)

    init(instances: [ActiveTrackingCardInstance]) {
        self.instances = instances
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let json = try container.decode(String.self)
        self = TrackingDashboardLayout.decode(from: json)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoded())
    }
}
