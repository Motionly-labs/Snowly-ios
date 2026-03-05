//
//  GearSetup.swift
//  Snowly
//
//  A gear checklist (e.g., "Backcountry Setup", "Park Day").
//

import Foundation
import SwiftData

@Model
final class GearSetup {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var model: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade)
    var items: [GearItem] = []

    /// Progress: fraction of checked items (0.0–1.0).
    var progress: Double {
        guard !items.isEmpty else { return 0 }
        let checked = items.filter(\.isChecked).count
        return Double(checked) / Double(items.count)
    }

    /// Whether all items are checked.
    var isComplete: Bool {
        !items.isEmpty && items.allSatisfy(\.isChecked)
    }

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        model: String = "",
        isActive: Bool = true,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.model = model
        self.isActive = isActive
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
