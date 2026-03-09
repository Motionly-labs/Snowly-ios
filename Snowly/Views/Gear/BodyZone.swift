//
//  BodyZone.swift
//  Snowly
//
//  Maps GearCategory values to 7 interactive body zones
//  for the skier figure visualization.
//

import SwiftUI

enum BodyZone: Int, CaseIterable, Identifiable {
    case head = 0       // protection
    case body = 1       // clothing
    case hands = 2      // accessories
    case gear = 3       // equipment
    case pack = 4       // electronics + other
    case feet = 5       // footwear
    case backpack = 6   // backpack

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .head: return String(localized: "gear_zone_head")
        case .body: return String(localized: "gear_zone_body")
        case .hands: return String(localized: "gear_zone_hands")
        case .gear: return String(localized: "gear_zone_arms")
        case .pack: return String(localized: "gear_zone_legs")
        case .feet: return String(localized: "gear_zone_feet")
        case .backpack: return String(localized: "gear_zone_other")
        }
    }

    var iconName: String {
        switch self {
        case .head: return "shield.fill"
        case .body: return "tshirt.fill"
        case .hands: return "hand.raised.fill"
        case .gear: return "snowboard"
        case .pack: return "bolt.fill"
        case .feet: return "shoe.fill"
        case .backpack: return "backpack.fill"
        }
    }

    /// Zone identification accent colors. These are NOT semantic status colors —
    /// they visually distinguish body zones on the skier figure.
    var accentColor: Color {
        switch self {
        case .head: return .red
        case .body: return .blue
        case .hands: return .blue
        case .gear: return .orange
        case .pack: return .blue
        case .feet: return .orange
        case .backpack: return .green
        }
    }

    var categories: [GearCategory] {
        switch self {
        case .head: return [.protection]
        case .body: return [.clothing]
        case .hands: return [.accessories]
        case .gear: return [.equipment]
        case .pack: return [.electronics, .other]
        case .feet: return [.footwear]
        case .backpack: return [.backpack]
        }
    }

    // MARK: - Query helpers

    func items(from setup: GearSetup) -> [GearItem] {
        let cats = Set(categories)
        return setup.items
            .filter { cats.contains($0.category) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func progress(from setup: GearSetup) -> Double {
        let zoneItems = items(from: setup)
        guard !zoneItems.isEmpty else { return 0 }
        let checked = zoneItems.filter(\.isChecked).count
        return Double(checked) / Double(zoneItems.count)
    }

    func isComplete(from setup: GearSetup) -> Bool {
        let zoneItems = items(from: setup)
        return !zoneItems.isEmpty && zoneItems.allSatisfy(\.isChecked)
    }

    func resolvedColor(from setup: GearSetup) -> Color {
        isComplete(from: setup) ? ColorTokens.success : accentColor
    }

    // MARK: - Zone color calculation

    /// Returns (fill, stroke) colors for rendering the zone shape.
    func shapeColors(
        from setup: GearSetup,
        isSelected: Bool
    ) -> (fill: Color, stroke: Color) {
        let prog = progress(from: setup)
        let complete = isComplete(from: setup)

        if complete {
            let fillOpacity = isSelected ? Opacity.medium : Opacity.soft
            let strokeOpacity = isSelected ? Opacity.strong : Opacity.prominent
            return (
                fill: ColorTokens.success.opacity(fillOpacity),
                stroke: ColorTokens.success.opacity(strokeOpacity)
            )
        }

        if prog > 0 {
            let fillOpacity = isSelected ? Opacity.soft : (Opacity.subtle + prog * Opacity.muted)
            let strokeOpacity = isSelected ? Opacity.half : Opacity.moderate
            return (
                fill: accentColor.opacity(fillOpacity),
                stroke: accentColor.opacity(strokeOpacity)
            )
        }

        // Not started — show zone accent color as a dim wireframe
        let fillOpacity = isSelected ? Opacity.light : Opacity.faint
        let strokeOpacity = isSelected ? Opacity.prominent : Opacity.soft
        return (
            fill: accentColor.opacity(fillOpacity),
            stroke: accentColor.opacity(strokeOpacity)
        )
    }

    // MARK: - Lookup

    static func zone(for category: GearCategory) -> BodyZone {
        switch category {
        case .protection: return .head
        case .clothing: return .body
        case .accessories: return .hands
        case .equipment: return .gear
        case .electronics, .other: return .pack
        case .footwear: return .feet
        case .backpack: return .backpack
        }
    }
}
