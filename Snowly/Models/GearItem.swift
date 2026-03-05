//
//  GearItem.swift
//  Snowly
//
//  A single item within a gear checklist.
//

import Foundation
import SwiftData

/// Category for organizing gear items.
enum GearCategory: String, Codable, CaseIterable, Sendable {
    case clothing = "Clothing"
    case protection = "Protection"
    case equipment = "Equipment"
    case accessories = "Accessories"
    case electronics = "Electronics"
    case footwear = "Footwear"
    case backpack = "Backpack"
    case other = "Other"

    var iconName: String {
        switch self {
        case .clothing: return "tshirt.fill"
        case .protection: return "shield.fill"
        case .equipment: return "snowboard"
        case .accessories: return "bag.fill"
        case .electronics: return "bolt.fill"
        case .footwear: return "shoe.fill"
        case .backpack: return "backpack.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

@Model
final class GearItem {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var category: GearCategory
    var isChecked: Bool = false
    var sortOrder: Int = 0

    @Relationship(inverse: \GearSetup.items) var setup: GearSetup?

    init(
        id: UUID = UUID(),
        name: String,
        category: GearCategory = GearCategory.other,
        isChecked: Bool = false,
        sortOrder: Int = 0,
        setup: GearSetup? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.isChecked = isChecked
        self.sortOrder = sortOrder
        self.setup = setup
    }
}
