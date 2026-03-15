//
//  TrackingDashboardLayoutTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct TrackingDashboardLayoutTests {

    // MARK: - Legacy migration (Phase 2: tolerant decode)

    @Test func decode_legacyJson_migratesHeroCards() {
        // speedCurve is a hero-only kind — stays in hero after demotion pass; "profile" is dropped (unknown kind)
        let json = #"{"heroCards":["speedCurve","profile"],"visibleWidgets":["vertical","distance"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let heroKinds = layout.instances.filter { $0.slot == .hero }.map(\.kind)
        #expect(heroKinds == [.speedCurve])
    }

    @Test func decode_legacyJson_migratesVisibleWidgets() {
        let json = #"{"heroCards":["speedCurve"],"visibleWidgets":["vertical","distance"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let gridKinds = layout.instances.filter { $0.slot == .grid }.map(\.kind)
        #expect(gridKinds == [.vertical, .distance])
    }

    @Test func decode_unknownHeroCard_dropsUnknownKeepsKnown() {
        // speedCurve is hero-only — stays in hero after demotion pass
        let json = #"{"heroCards":["speedCurve","unknownFutureCard"],"visibleWidgets":["vertical"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        let heroKinds = layout.instances.filter { $0.slot == .hero }.map(\.kind)
        #expect(heroKinds == [.speedCurve])
    }

    @Test func decode_allUnknownHeroCards_fallsBackToDefault() {
        // All cards (both hero and grid) are unknown — `all` is empty → returns default
        let json = #"{"heroCards":["unknownA","unknownB"],"visibleWidgets":["unknownWidget"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        #expect(layout == TrackingDashboardLayout.default)
    }

    @Test func decode_allUnknownWidgets_fallsBackToDefault() {
        let json = #"{"heroCards":["unknownA"],"visibleWidgets":["unknownWidget"]}"#

        let layout = TrackingDashboardLayout.decode(from: json)

        #expect(layout == TrackingDashboardLayout.default)
    }

    @Test func decode_heroInstanceWithNowGridOnlyKind_demotesToGrid() {
        // currentSpeed is now grid-only; a persisted layout with it in hero must be demoted
        let id = UUID()
        let json = """
        {"version":1,"instances":[
          {"instanceId":"\(id.uuidString)","kind":"currentSpeed","slot":"hero","presentationKind":"scalar","config":{}}
        ]}
        """

        let layout = TrackingDashboardLayout.decode(from: json)

        let instance = layout.instances.first { $0.instanceId == id }
        #expect(instance?.slot == .grid)
    }

    @Test func decode_emptyJson_returnsDefault() {
        let layout = TrackingDashboardLayout.decode(from: "")

        #expect(layout == TrackingDashboardLayout.default)
    }

    // MARK: - New format round-trip

    @Test func encoded_thenDecoded_preservesInstances() {
        let layout = TrackingDashboardLayout.default
        let json = layout.encoded()

        let decoded = TrackingDashboardLayout.decode(from: json)

        #expect(decoded.instances.map(\.kind) == layout.instances.map(\.kind))
        #expect(decoded.instances.map(\.slot) == layout.instances.map(\.slot))
    }
}
