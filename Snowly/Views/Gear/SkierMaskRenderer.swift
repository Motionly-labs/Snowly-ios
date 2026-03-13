//
//  SkierMaskRenderer.swift
//  Snowly
//
//  Loads precomputed zone masks and lookup data for the checklist figure.
//

import UIKit

struct SkierMaskRenderer {
    static let displayAssetName = "SkierDisplay"

    static let zoneMaskAssetNames: [(zone: BodyZone, name: String)] = [
        (.head, "ZoneMask-head"),
        (.body, "ZoneMask-body"),
        (.hands, "ZoneMask-hands"),
        (.gear, "ZoneMask-gear"),
        (.pack, "ZoneMask-pack"),
        (.feet, "ZoneMask-feet"),
        (.backpack, "ZoneMask-backpack"),
    ]

    private static let lookupAssetName = "ZoneLookup"
    private static let noZoneMarker: UInt8 = 0xFF

    let zoneMasks: [BodyZone: UIImage]
    private let lookupData: Data
    private let lookupWidth: Int
    private let lookupHeight: Int

    init?() {
        var masks: [BodyZone: UIImage] = [:]
        for (zone, name) in Self.zoneMaskAssetNames {
            guard let image = UIImage(named: name) else { return nil }
            masks[zone] = image
        }

        guard let lookupAsset = NSDataAsset(name: Self.lookupAssetName) else { return nil }
        let side = Int(Double(lookupAsset.data.count).squareRoot())
        guard side > 0, side * side == lookupAsset.data.count else { return nil }

        zoneMasks = masks
        lookupData = lookupAsset.data
        lookupWidth = side
        lookupHeight = side
    }

    func zone(atNormalized point: CGPoint) -> BodyZone? {
        guard point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return nil }

        let x = min(Int(point.x * CGFloat(lookupWidth)), lookupWidth - 1)
        let y = min(Int(point.y * CGFloat(lookupHeight)), lookupHeight - 1)
        let index = (y * lookupWidth) + x

        guard index < lookupData.count else { return nil }
        let value = lookupData[index]
        guard value != Self.noZoneMarker else { return nil }
        return BodyZone(rawValue: Int(value))
    }
}
