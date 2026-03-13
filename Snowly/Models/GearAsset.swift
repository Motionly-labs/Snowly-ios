//
//  GearAsset.swift
//  Snowly
//
//  Internal model backing a user-facing locker gear item.
//

import Foundation
import SwiftData

enum GearAssetCategory: String, Codable, CaseIterable, Sendable {
    case skis = "Skis"
    case snowboard = "Snowboard"
    case boots = "Boots"
    case outerwear = "Outerwear"
    case protection = "Protection"
    case accessory = "Accessory"
    case electronics = "Electronics"
    case bag = "Bag"
    case safety = "Safety"
    case other = "Other"

    var iconName: String {
        switch self {
        case .skis: return "figure.skiing.downhill"
        case .snowboard: return "figure.snowboarding"
        case .boots: return "shoe.fill"
        case .outerwear: return "tshirt.fill"
        case .protection: return "shield.fill"
        case .accessory: return "sparkles"
        case .electronics: return "bolt.fill"
        case .bag: return "bag.fill"
        case .safety: return "cross.case.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum GearMaintenanceRuleType: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case skiDays = "Every N Ski Days"
    case date = "On Date"
}

@Model
final class GearAsset {
    @Attribute(.unique) var id: UUID = UUID()
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
    @Relationship(deleteRule: .cascade)
    var maintenanceEvents: [GearMaintenanceEvent] = []

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
