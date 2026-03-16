//
//  GearAsset.swift
//  Snowly
//
//  Internal model backing a user-facing locker gear item.
//

import Foundation
import SwiftData

enum GearAssetCategory: String, Codable, CaseIterable, Sendable {
    // Head
    case helmet = "Helmet"
    case goggles = "Goggles"
    case balaclava = "Balaclava"
    // Body
    case jacket = "Jacket"
    case pants = "Pants"
    case baseLayer = "Base Layer"
    case midLayer = "Mid Layer"
    // Hands
    case gloves = "Gloves"
    case mittens = "Mittens"
    // Feet
    case boots = "Boots"
    case socks = "Socks"
    // Ride
    case skis = "Skis"
    case snowboard = "Snowboard"
    case bindings = "Bindings"
    case poles = "Poles"
    // Protection
    case backProtector = "Back Protector"
    case kneeGuards = "Knee Guards"
    case wristGuards = "Wrist Guards"
    // Safety
    case beacon = "Beacon"
    case probe = "Probe"
    case shovel = "Shovel"
    case airbagPack = "Airbag Pack"
    // Electronics
    case actionCamera = "Action Camera"
    case gpsDevice = "GPS Device"
    case headphones = "Headphones"
    // Bag
    case backpack = "Backpack"
    case bootBag = "Boot Bag"
    case gearBag = "Gear Bag"
    // Other
    case other = "Other"

    /// Migrates legacy raw values from the previous flat category scheme.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let match = GearAssetCategory(rawValue: raw) {
            self = match
            return
        }
        switch raw {
        case "Protection": self = .helmet
        case "Outerwear": self = .jacket
        case "Accessory": self = .gloves
        case "Electronics": self = .actionCamera
        case "Safety": self = .beacon
        case "Bag": self = .backpack
        default: self = .other
        }
    }

    var iconName: String {
        switch self {
        case .helmet: return "shield.fill"
        case .goggles: return "eyeglasses"
        case .balaclava: return "person.fill"
        case .jacket: return "tshirt.fill"
        case .pants: return "figure.stand"
        case .baseLayer: return "thermometer.snowflake"
        case .midLayer: return "rectangle.stack.fill"
        case .gloves: return "hand.raised.fill"
        case .mittens: return "hand.raised.fill"
        case .boots: return "shoe.fill"
        case .socks: return "shoe.fill"
        case .skis: return "figure.skiing.downhill"
        case .snowboard: return "figure.snowboarding"
        case .bindings: return "link"
        case .poles: return "arrow.up.and.down.circle"
        case .backProtector: return "shield.lefthalf.filled"
        case .kneeGuards: return "bandage.fill"
        case .wristGuards: return "hand.raised.slash.fill"
        case .beacon: return "antenna.radiowaves.left.and.right"
        case .probe: return "scope"
        case .shovel: return "hammer.fill"
        case .airbagPack: return "bag.fill"
        case .actionCamera: return "camera.fill"
        case .gpsDevice: return "location.fill"
        case .headphones: return "headphones"
        case .backpack: return "bag.fill"
        case .bootBag: return "suitcase.fill"
        case .gearBag: return "suitcase.rolling.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

extension GearAssetCategory {
    /// First-level grouping used by the category picker.
    enum Group: String, CaseIterable, Identifiable {
        case head = "Head"
        case body = "Body"
        case hands = "Hands"
        case feet = "Feet"
        case ride = "Ride"
        case protection = "Protection"
        case safety = "Safety"
        case electronics = "Electronics"
        case bag = "Bag"
        case other = "Other"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .head: return "person.fill"
            case .body: return "tshirt.fill"
            case .hands: return "hand.raised.fill"
            case .feet: return "shoe.fill"
            case .ride: return "figure.skiing.downhill"
            case .protection: return "shield.fill"
            case .safety: return "cross.case.fill"
            case .electronics: return "bolt.fill"
            case .bag: return "bag.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }

        var categories: [GearAssetCategory] {
            switch self {
            case .head: return [.helmet, .goggles, .balaclava]
            case .body: return [.jacket, .pants, .baseLayer, .midLayer]
            case .hands: return [.gloves, .mittens]
            case .feet: return [.boots, .socks]
            case .ride: return [.skis, .snowboard, .bindings, .poles]
            case .protection: return [.backProtector, .kneeGuards, .wristGuards]
            case .safety: return [.beacon, .probe, .shovel, .airbagPack]
            case .electronics: return [.actionCamera, .gpsDevice, .headphones]
            case .bag: return [.backpack, .bootBag, .gearBag]
            case .other: return [.other]
            }
        }

        static func group(for category: GearAssetCategory) -> Group {
            for group in Group.allCases where group.categories.contains(category) {
                return group
            }
            return .other
        }
    }

    var group: Group { Group.group(for: self) }
}

enum GearMaintenanceRuleType: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case skiDays = "Every N Ski Days"
    case date = "On Date"
}

@Model
final class GearAsset {
    var id: UUID = UUID()
    var name: String = ""
    var category: GearAssetCategory = GearAssetCategory.other
    var brand: String = ""
    var model: String = ""
    var notes: String?
    var acquiredAt: Date?
    var isArchived: Bool = false
    // Legacy synced fields retained for store compatibility. Current product flow uses reminder schedules instead.
    var dueRuleType: GearMaintenanceRuleType = GearMaintenanceRuleType.none
    var dueEverySkiDays: Int?
    var dueDate: Date?
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var setupIDs: [UUID] = []

    // Legacy relationship retained for store compatibility. New UI should not depend on it.
    @Relationship(deleteRule: .cascade, inverse: \GearMaintenanceEvent.asset)
    var maintenanceEvents: [GearMaintenanceEvent]?

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let detail = [brand, model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !detail.isEmpty {
            return detail
        }

        return category.rawValue
    }

    var subtitle: String {
        let detail = [brand, model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !detail.isEmpty && detail != displayName {
            return detail
        }

        return category.rawValue
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        category: GearAssetCategory = .other,
        brand: String = "",
        model: String = "",
        notes: String? = nil,
        acquiredAt: Date? = nil,
        isArchived: Bool = false,
        dueRuleType: GearMaintenanceRuleType = .none,
        dueEverySkiDays: Int? = nil,
        dueDate: Date? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        setupIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.brand = brand
        self.model = model
        self.notes = notes
        self.acquiredAt = acquiredAt
        self.isArchived = isArchived
        self.dueRuleType = dueRuleType
        self.dueEverySkiDays = dueEverySkiDays
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.setupIDs = setupIDs
    }
}
