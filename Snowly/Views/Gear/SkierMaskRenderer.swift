//
//  SkierMaskRenderer.swift
//  Snowly
//
//  Loads pre-baked zone mask PNGs and a compact lookup table from the asset
//  catalog. All heavy pixel processing happens at build time via
//  Scripts/generate-zone-assets.swift.
//

import UIKit

struct SkierMaskRenderer {
    // Centralized asset names for skier resources.
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

    // MARK: - Zone color definitions

    /// Maps each zone to the color used in SkierMask SVG.
    /// Must stay in sync with the SVG layer colors and generate-zone-assets.swift.
    ///
    /// SVG layer → color → zone:
    ///   Head  → #FF00FF magenta → head
    ///   Body  → #FF0000 red     → body
    ///   Arms  → #00FF00 green   → gear
    ///   Hand  → #FFFF00 yellow  → hands
    ///   Legs  → #0000FF blue    → pack
    ///   Foot  → #F7931E orange  → feet
    ///   Bag   → #8CC63F lime    → backpack
    static let zoneColors: [(zone: BodyZone, r: UInt8, g: UInt8, b: UInt8)] = [
        (.head, 0xFF, 0x00, 0xFF),      // magenta — Head layer
        (.body, 0xFF, 0x00, 0x00),      // red     — Body layer
        (.gear, 0x00, 0xFF, 0x00),      // green   — Arms layer
        (.hands, 0xFF, 0xFF, 0x00),     // yellow  — Hand layer
        (.pack, 0x00, 0x00, 0xFF),      // blue    — Legs layer
        (.feet, 0xF7, 0x93, 0x1E),      // orange  — Foot layer
        (.backpack, 0x8C, 0xC6, 0x3F),  // lime    — Bag layer
    ]

    /// Per-channel tolerance for mask color matching.
    static let colorTolerance: UInt8 = 15

    // MARK: - Stored data

    let zoneMasks: [BodyZone: UIImage]
    private let lookupData: Data
    private let lookupWidth: Int
    private let lookupHeight: Int

    // MARK: - Initialization

    /// Loads pre-baked zone masks and lookup table from the asset catalog.
    init?() {
        var masks: [BodyZone: UIImage] = [:]
        for (zone, name) in Self.zoneMaskAssetNames {
            guard let img = UIImage(named: name) else { return nil }
            masks[zone] = img
        }
        self.zoneMasks = masks

        guard let asset = NSDataAsset(name: Self.lookupAssetName) else { return nil }
        self.lookupData = asset.data

        // Lookup table is square; derive dimension from byte count.
        let side = Int(Double(asset.data.count).squareRoot())
        guard side * side == asset.data.count, side > 0 else { return nil }
        self.lookupWidth = side
        self.lookupHeight = side
    }

    /// Test-only initializer — inject compact lookup data directly.
    init(lookupData: Data, lookupWidth: Int, lookupHeight: Int) {
        self.lookupData = lookupData
        self.lookupWidth = lookupWidth
        self.lookupHeight = lookupHeight
        self.zoneMasks = [:]
    }

    // MARK: - Zone lookup

    /// Returns the body zone at a normalized point (0...1, 0...1).
    func zone(atNormalized point: CGPoint) -> BodyZone? {
        guard point.x >= 0, point.x <= 1,
              point.y >= 0, point.y <= 1 else {
            return nil
        }

        let px = min(Int(point.x * CGFloat(lookupWidth)), lookupWidth - 1)
        let py = min(Int(point.y * CGFloat(lookupHeight)), lookupHeight - 1)
        let index = py * lookupWidth + px

        guard index < lookupData.count else { return nil }

        let value = lookupData[index]
        guard value != Self.noZoneMarker else { return nil }
        return BodyZone(rawValue: Int(value))
    }

    // MARK: - Color matching

    static func matchZone(r: UInt8, g: UInt8, b: UInt8, tolerance: UInt8) -> BodyZone? {
        for (zone, tr, tg, tb) in zoneColors {
            if channelMatches(r, tr, tolerance: tolerance),
               channelMatches(g, tg, tolerance: tolerance),
               channelMatches(b, tb, tolerance: tolerance)
            {
                return zone
            }
        }
        return nil
    }

    private static func channelMatches(_ value: UInt8, _ target: UInt8, tolerance: UInt8) -> Bool {
        let diff = value > target ? value - target : target - value
        return diff <= tolerance
    }
}
