//
//  BodyZoneTests.swift
//  SnowlyTests
//
//  Tests for visual checklist body-zone mapping.
//

import Testing
@testable import Snowly

struct BodyZoneTests {

    @Test func skisAndSnowboardsMapToBackpack() {
        #expect(BodyZone.zone(for: .skis) == .backpack)
        #expect(BodyZone.zone(for: .snowboard) == .backpack)
    }

    @Test func backpackZoneContainsBoardsAndBag() {
        let backpackCategories = Set(BodyZone.backpack.categories)

        #expect(backpackCategories.contains(.skis))
        #expect(backpackCategories.contains(.snowboard))
        #expect(backpackCategories.contains(.bag))
        #expect(BodyZone.pack.categories.isEmpty)
    }
}
