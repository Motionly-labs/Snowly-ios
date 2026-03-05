//
//  BodyZoneTests.swift
//  SnowlyTests
//
//  Tests for BodyZone enum: category mapping, progress, colors.
//

import Testing
import SwiftUI
@testable import Snowly

struct BodyZoneTests {

    // MARK: - Category Mapping

    @Test func allCategoriesMappedToExactlyOneZone() {
        for category in GearCategory.allCases {
            let zone = BodyZone.zone(for: category)
            #expect(zone.categories.contains(category))
        }
    }

    @Test func protectionMapsToHead() {
        #expect(BodyZone.zone(for: .protection) == .head)
    }

    @Test func clothingMapsToBody() {
        #expect(BodyZone.zone(for: .clothing) == .body)
    }

    @Test func accessoriesMapsToHands() {
        #expect(BodyZone.zone(for: .accessories) == .hands)
    }

    @Test func equipmentMapsToGear() {
        #expect(BodyZone.zone(for: .equipment) == .gear)
    }

    @Test func electronicsAndOtherMapToPack() {
        #expect(BodyZone.zone(for: .electronics) == .pack)
        #expect(BodyZone.zone(for: .other) == .pack)
    }

    @Test func footwearMapsToFeet() {
        #expect(BodyZone.zone(for: .footwear) == .feet)
    }

    @Test func backpackMapsToBackpack() {
        #expect(BodyZone.zone(for: .backpack) == .backpack)
    }

    @Test func sevenZonesTotal() {
        #expect(BodyZone.allCases.count == 7)
    }

    @Test func packCategoriesContainsBoth() {
        let packCats = BodyZone.pack.categories
        #expect(packCats.contains(.electronics))
        #expect(packCats.contains(.other))
        #expect(packCats.count == 2)
    }

    // MARK: - Items Filtering

    @Test func itemsFromSetup_filtersCorrectly() {
        let setup = GearSetup(name: "Test")
        let helmet = GearItem(name: "Helmet", category: .protection, setup: setup)
        let jacket = GearItem(name: "Jacket", category: .clothing, setup: setup)
        let goggles = GearItem(name: "Goggles", category: .protection, setup: setup)
        setup.items = [helmet, jacket, goggles]

        let headItems = BodyZone.head.items(from: setup)
        #expect(headItems.count == 2)
        #expect(headItems.allSatisfy { $0.category == .protection })

        let bodyItems = BodyZone.body.items(from: setup)
        #expect(bodyItems.count == 1)
        #expect(bodyItems.first?.name == "Jacket")
    }

    @Test func itemsFromSetup_emptyForMissingCategory() {
        let setup = GearSetup(name: "Test")
        let helmet = GearItem(name: "Helmet", category: .protection, setup: setup)
        setup.items = [helmet]

        let gearItems = BodyZone.gear.items(from: setup)
        #expect(gearItems.isEmpty)
    }

    @Test func itemsFromSetup_packMergesElectronicsAndOther() {
        let setup = GearSetup(name: "Test")
        let phone = GearItem(name: "Phone Charger", category: .electronics, setup: setup)
        let snack = GearItem(name: "Snacks", category: .other, setup: setup)
        setup.items = [phone, snack]

        let packItems = BodyZone.pack.items(from: setup)
        #expect(packItems.count == 2)
    }

    // MARK: - Progress Calculation

    @Test func progress_emptySetupReturnsZero() {
        let setup = GearSetup(name: "Test")
        #expect(BodyZone.head.progress(from: setup) == 0)
    }

    @Test func progress_noneCheckedReturnsZero() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: false, setup: setup),
            GearItem(name: "Goggles", category: .protection, isChecked: false, setup: setup),
        ]
        #expect(BodyZone.head.progress(from: setup) == 0)
    }

    @Test func progress_halfCheckedReturnsFifty() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: true, setup: setup),
            GearItem(name: "Goggles", category: .protection, isChecked: false, setup: setup),
        ]
        #expect(BodyZone.head.progress(from: setup) == 0.5)
    }

    @Test func progress_allCheckedReturnsOne() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: true, setup: setup),
            GearItem(name: "Goggles", category: .protection, isChecked: true, setup: setup),
        ]
        #expect(BodyZone.head.progress(from: setup) == 1.0)
    }

    @Test func progress_ignoresOtherCategories() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: false, setup: setup),
            GearItem(name: "Jacket", category: .clothing, isChecked: true, setup: setup),
        ]
        #expect(BodyZone.head.progress(from: setup) == 0)
        #expect(BodyZone.body.progress(from: setup) == 1.0)
    }

    // MARK: - Completion

    @Test func isComplete_falseWhenEmpty() {
        let setup = GearSetup(name: "Test")
        #expect(!BodyZone.head.isComplete(from: setup))
    }

    @Test func isComplete_falseWhenPartial() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: true, setup: setup),
            GearItem(name: "Goggles", category: .protection, isChecked: false, setup: setup),
        ]
        #expect(!BodyZone.head.isComplete(from: setup))
    }

    @Test func isComplete_trueWhenAllChecked() {
        let setup = GearSetup(name: "Test")
        setup.items = [
            GearItem(name: "Helmet", category: .protection, isChecked: true, setup: setup),
            GearItem(name: "Goggles", category: .protection, isChecked: true, setup: setup),
        ]
        #expect(BodyZone.head.isComplete(from: setup))
    }

    // MARK: - Display Properties

    @Test func allZonesHaveDisplayNames() {
        for zone in BodyZone.allCases {
            #expect(!zone.displayName.isEmpty)
        }
    }

    @Test func allZonesHaveIcons() {
        for zone in BodyZone.allCases {
            #expect(!zone.iconName.isEmpty)
        }
    }

    @Test func allZonesHaveCategories() {
        for zone in BodyZone.allCases {
            #expect(!zone.categories.isEmpty)
        }
    }
}
