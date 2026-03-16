//
//  BodyZone.swift
//  Snowly
//
//  Maps locker gear categories to the skier figure zones.
//

import SwiftUI

enum BodyZone: Int, CaseIterable, Identifiable {
    case head = 0
    case body = 1
    case hands = 2
    case gear = 3
    case pack = 4
    case feet = 5
    case backpack = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .head:
            return "Head"
        case .body:
            return "Body"
        case .hands:
            return "Hands"
        case .gear:
            return "Extras"
        case .pack:
            return "Ride"
        case .feet:
            return "Feet"
        case .backpack:
            return "Backpack"
        }
    }

    var iconName: String {
        switch self {
        case .head:
            return "helmet"
        case .body:
            return "tshirt.fill"
        case .hands:
            return "hand.raised.fill"
        case .gear:
            return "sparkles"
        case .pack:
            return "figure.skiing.downhill"
        case .feet:
            return "shoe.fill"
        case .backpack:
            return "bag.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .head:
            return ColorTokens.brandRed
        case .body:
            return ColorTokens.brandIceBlue
        case .hands:
            return ColorTokens.brandWarmAmber
        case .gear:
            return ColorTokens.brandWarmOrange
        case .pack:
            return ColorTokens.brandGold
        case .feet:
            return ColorTokens.success
        case .backpack:
            return ColorTokens.brandIceBlue.opacity(0.8)
        }
    }

    var categories: [GearAssetCategory] {
        switch self {
        case .head:
            return [.helmet, .goggles, .balaclava]
        case .body:
            return [.jacket, .pants, .baseLayer, .midLayer]
        case .hands:
            return [.gloves, .mittens]
        case .gear:
            return [.backProtector, .kneeGuards, .wristGuards,
                    .beacon, .probe, .shovel, .airbagPack,
                    .actionCamera, .gpsDevice, .headphones, .other]
        case .pack:
            return []
        case .feet:
            return [.boots, .socks]
        case .backpack:
            return [.skis, .snowboard, .bindings, .poles, .backpack, .bootBag, .gearBag]
        }
    }

    func gear(from lockerGear: [GearAsset]) -> [GearAsset] {
        let supportedCategories = Set(categories)
        return lockerGear
            .filter { supportedCategories.contains($0.category) }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    func checkedCount(in lockerGear: [GearAsset], checkedGearIDs: Set<UUID>) -> Int {
        gear(from: lockerGear).filter { checkedGearIDs.contains($0.id) }.count
    }

    func progress(in lockerGear: [GearAsset], checkedGearIDs: Set<UUID>) -> Double {
        let zoneGear = gear(from: lockerGear)
        guard !zoneGear.isEmpty else { return 0 }
        return Double(checkedCount(in: lockerGear, checkedGearIDs: checkedGearIDs)) / Double(zoneGear.count)
    }

    func isComplete(in lockerGear: [GearAsset], checkedGearIDs: Set<UUID>) -> Bool {
        let zoneGear = gear(from: lockerGear)
        return !zoneGear.isEmpty && zoneGear.allSatisfy { checkedGearIDs.contains($0.id) }
    }

    func fillColor(
        in lockerGear: [GearAsset],
        checkedGearIDs: Set<UUID>,
        isSelected: Bool
    ) -> Color {
        guard !gear(from: lockerGear).isEmpty else {
            return .clear
        }

        let progress = progress(in: lockerGear, checkedGearIDs: checkedGearIDs)
        if progress >= 1 {
            return ColorTokens.success.opacity(isSelected ? 0.4 : 0.28)
        }
        if progress > 0 {
            return accentColor.opacity(isSelected ? 0.34 : 0.18 + (progress * 0.16))
        }
        return accentColor.opacity(isSelected ? 0.14 : 0.07)
    }

    static func zone(for category: GearAssetCategory) -> BodyZone {
        switch category {
        case .helmet, .goggles, .balaclava:
            return .head
        case .jacket, .pants, .baseLayer, .midLayer:
            return .body
        case .gloves, .mittens:
            return .hands
        case .boots, .socks:
            return .feet
        case .skis, .snowboard, .bindings, .poles, .backpack, .bootBag, .gearBag:
            return .backpack
        case .backProtector, .kneeGuards, .wristGuards,
             .beacon, .probe, .shovel, .airbagPack,
             .actionCamera, .gpsDevice, .headphones, .other:
            return .gear
        }
    }
}
