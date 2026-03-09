//
//  GearModelTests.swift
//  SnowlyTests
//
//  Tests for GearSetup and GearItem models.
//

import Testing
import Foundation
@testable import Snowly

struct GearModelTests {

    // MARK: - GearSetup

    @Test func gearSetup_progressEmpty() {
        let setup = GearSetup(name: "Test")
        #expect(setup.progress == 0)
    }

    @Test func gearSetup_isCompleteEmpty() {
        let setup = GearSetup(name: "Test")
        #expect(!setup.isComplete)
    }

    // MARK: - GearCategory

    @Test func gearCategory_allCasesCount() {
        #expect(GearCategory.allCases.count == 8)
    }

    @Test func gearCategory_iconNames() {
        for category in GearCategory.allCases {
            #expect(!category.iconName.isEmpty)
        }
    }

    @Test func gearCategory_rawValues() {
        #expect(GearCategory.clothing.rawValue == "Clothing")
        #expect(GearCategory.protection.rawValue == "Protection")
        #expect(GearCategory.equipment.rawValue == "Equipment")
        #expect(GearCategory.accessories.rawValue == "Accessories")
        #expect(GearCategory.electronics.rawValue == "Electronics")
        #expect(GearCategory.footwear.rawValue == "Footwear")
        #expect(GearCategory.backpack.rawValue == "Backpack")
        #expect(GearCategory.other.rawValue == "Other")
    }

    // MARK: - GearItem

    @Test func gearItem_defaultValues() {
        let item = GearItem(name: "Helmet")
        #expect(item.name == "Helmet")
        #expect(item.isChecked == false)
        #expect(item.category == .other)
        #expect(item.sortOrder == 0)
    }

    // MARK: - RunActivityType

    @Test func runActivityType_codable() throws {
        let types: [RunActivityType] = [.skiing, .lift, .idle]
        for type in types {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(RunActivityType.self, from: data)
            #expect(decoded == type)
        }
    }
}
