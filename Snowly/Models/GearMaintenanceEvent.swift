//
//  GearMaintenanceEvent.swift
//  Snowly
//
//  Legacy service-event model retained only for synced-store compatibility.
//

import Foundation
import SwiftData

enum GearMaintenanceEventType: String, Codable, CaseIterable, Sendable {
    case wax = "Wax"
    case edgeTune = "Edge Tune"
    case bindingCheck = "Binding Check"
    case baseRepair = "Base Repair"
    case bootFitAdjustment = "Boot Fit"
    case other = "Other"

    var iconName: String {
        switch self {
        case .wax: return "drop.fill"
        case .edgeTune: return "wrench.and.screwdriver.fill"
        case .bindingCheck: return "checkmark.shield.fill"
        case .baseRepair: return "bandage.fill"
        case .bootFitAdjustment: return "shoeprints.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

@Model
final class GearMaintenanceEvent {
    var id: UUID = UUID()
    var type: GearMaintenanceEventType = GearMaintenanceEventType.other
    var date: Date = Date()
    var notes: String?
    var createdAt: Date = Date()

    var asset: GearAsset?

    init(
        id: UUID = UUID(),
        type: GearMaintenanceEventType = .other,
        date: Date = Date(),
        notes: String? = nil,
        createdAt: Date = Date(),
        asset: GearAsset? = nil
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.notes = notes
        self.createdAt = createdAt
        self.asset = asset
    }
}
