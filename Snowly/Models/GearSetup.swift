//
//  GearSetup.swift
//  Snowly
//
//  Internal model backing a user-facing checklist.
//

import Foundation
import SwiftData

@Model
final class GearSetup {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    var isActive: Bool = false
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    var trimmedNotes: String {
        notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        isActive: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
