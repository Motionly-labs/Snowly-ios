//
//  ActiveTrackingCardInstanceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct ActiveTrackingCardInstanceTests {

    // MARK: - Persistence round-trip

    @Test func decode_newJson_roundtrips() {
        let layout = TrackingDashboardLayout.default
        let json = layout.encoded()

        let decoded = TrackingDashboardLayout.decode(from: json)

        #expect(decoded.instances.count == layout.instances.count)
        for (a, b) in zip(layout.instances, decoded.instances) {
            #expect(a.instanceId == b.instanceId)
            #expect(a.kind == b.kind)
            #expect(a.slot == b.slot)
            #expect(a.presentationKind == b.presentationKind)
        }
    }

    @Test func decode_newJsonWithUnknownKind_dropsUnknownKeepsKnown() throws {
        // Manually craft a new-format JSON with one known and one unknown kind
        let knownId = UUID()
        let json = """
        {"version":1,"instances":[
          {"instanceId":"\(knownId.uuidString)","kind":"currentSpeed","slot":"hero","presentationKind":"scalar","config":{}},
          {"instanceId":"\(UUID().uuidString)","kind":"unknownFutureKind","slot":"grid","presentationKind":"scalar","config":{}}
        ]}
        """

        let layout = TrackingDashboardLayout.decode(from: json)

        #expect(layout.instances.count == 1)
        #expect(layout.instances.first?.kind == .currentSpeed)
        #expect(layout.instances.first?.instanceId == knownId)
    }

    @Test func decode_emptyJson_returnsDefault() {
        let layout = TrackingDashboardLayout.decode(from: "")

        #expect(layout == TrackingDashboardLayout.default)
    }

    // MARK: - Legacy migration

    @Test func decode_legacyJson_migratesSuccessfully() {
        // speedCurve and profile are hero-only; vertical and distance are grid-only
        let json = #"{"heroCards":["speedCurve","profile"],"visibleWidgets":["vertical","distance"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let heroInstances = layout.instances.filter { $0.slot == .hero }
        let gridInstances = layout.instances.filter { $0.slot == .grid }
        #expect(heroInstances.count == 2)
        #expect(gridInstances.count == 2)
    }

    @Test func migrate_legacy_heroCardsGetHeroSlot() {
        // speedCurve and profile are hero-only — they stay in hero after demotion pass
        let json = #"{"heroCards":["speedCurve","profile"],"visibleWidgets":["vertical"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let heroKinds = layout.instances.filter { $0.slot == .hero }.map(\.kind)
        #expect(heroKinds.contains(.speedCurve))
        #expect(heroKinds.contains(.profile))
    }

    @Test func migrate_legacy_widgetsGetGridSlot() {
        let json = #"{"heroCards":["currentSpeed"],"visibleWidgets":["vertical","distance","runCount"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let gridKinds = layout.instances.filter { $0.slot == .grid }.map(\.kind)
        #expect(gridKinds.contains(.vertical))
        #expect(gridKinds.contains(.distance))
        #expect(gridKinds.contains(.runCount))
    }

    // MARK: - Registry

    @Test func registry_definition_returnsExpectedSlot() {
        #expect(ActiveTrackingCardRegistry.definition(for: .currentSpeed).defaultSlot == .grid)
        #expect(ActiveTrackingCardRegistry.definition(for: .altitudeCurve).defaultSlot == .hero)
        #expect(ActiveTrackingCardRegistry.definition(for: .profile).defaultSlot == .hero)
    }

    @Test func registry_allHeroKinds_noGaps() {
        let heroKinds = ActiveTrackingCardRegistry.allHeroKinds
        // Hero section = curve cards only
        let expectedKinds: [ActiveTrackingCardKind] = [.speedCurve, .altitudeCurve, .heartRateCurve, .profile]
        for kind in expectedKinds {
            #expect(heroKinds.contains(kind), "Missing expected hero kind: \(kind)")
        }
    }
}
