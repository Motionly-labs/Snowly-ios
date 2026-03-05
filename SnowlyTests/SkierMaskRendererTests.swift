//
//  SkierMaskRendererTests.swift
//  SnowlyTests
//
//  Tests for SkierMaskRenderer: compact lookup, color matching, zone detection.
//

import Testing
import UIKit
@testable import Snowly

struct SkierMaskRendererTests {

    // MARK: - Helpers

    private static let noZone: UInt8 = 0xFF

    /// Creates a compact lookup table (1 byte per pixel) with a specific zone
    /// in the center 2x2 region and no-zone everywhere else.
    private func makeLookupData(
        width: Int = 4,
        height: Int = 4,
        centerZone: BodyZone
    ) -> Data {
        var bytes = [UInt8](repeating: Self.noZone, count: width * height)
        for y in 1...2 {
            for x in 1...2 {
                bytes[y * width + x] = UInt8(centerZone.rawValue)
            }
        }
        return Data(bytes)
    }

    /// Creates a compact lookup table with 7 horizontal zone stripes.
    private func makeMultiZoneLookup(width: Int = 10, height: Int = 70) -> Data {
        var bytes = [UInt8](repeating: Self.noZone, count: width * height)
        for y in 0..<height {
            let zoneIndex = y / 10  // 0..6
            guard zoneIndex < BodyZone.allCases.count else { break }
            for x in 0..<width {
                bytes[y * width + x] = UInt8(zoneIndex)
            }
        }
        return Data(bytes)
    }

    // MARK: - Color Matching

    // Color mapping matches SVG layers:
    //   Head  → magenta → head
    //   Body  → red     → body
    //   Arms  → green   → gear
    //   Hand  → yellow  → hands
    //   Legs  → blue    → pack
    //   Foot  → orange  → feet
    //   Bag   → lime    → backpack

    @Test func matchZone_magenta_returnsHead() {
        let zone = SkierMaskRenderer.matchZone(r: 255, g: 0, b: 255, tolerance: 15)
        #expect(zone == .head)
    }

    @Test func matchZone_red_returnsBody() {
        let zone = SkierMaskRenderer.matchZone(r: 255, g: 0, b: 0, tolerance: 15)
        #expect(zone == .body)
    }

    @Test func matchZone_green_returnsGear() {
        let zone = SkierMaskRenderer.matchZone(r: 0, g: 255, b: 0, tolerance: 15)
        #expect(zone == .gear)
    }

    @Test func matchZone_yellow_returnsHands() {
        let zone = SkierMaskRenderer.matchZone(r: 255, g: 255, b: 0, tolerance: 15)
        #expect(zone == .hands)
    }

    @Test func matchZone_blue_returnsPack() {
        let zone = SkierMaskRenderer.matchZone(r: 0, g: 0, b: 255, tolerance: 15)
        #expect(zone == .pack)
    }

    @Test func matchZone_orange_returnsFeet() {
        let zone = SkierMaskRenderer.matchZone(r: 0xF7, g: 0x93, b: 0x1E, tolerance: 15)
        #expect(zone == .feet)
    }

    @Test func matchZone_lime_returnsBackpack() {
        let zone = SkierMaskRenderer.matchZone(r: 0x8C, g: 0xC6, b: 0x3F, tolerance: 15)
        #expect(zone == .backpack)
    }

    @Test func matchZone_white_returnsNil() {
        let zone = SkierMaskRenderer.matchZone(r: 255, g: 255, b: 255, tolerance: 15)
        #expect(zone == nil)
    }

    @Test func matchZone_black_returnsNil() {
        let zone = SkierMaskRenderer.matchZone(r: 0, g: 0, b: 0, tolerance: 15)
        #expect(zone == nil)
    }

    @Test func matchZone_withinTolerance_matches() {
        // Near-magenta should still match head
        let zone = SkierMaskRenderer.matchZone(r: 245, g: 10, b: 245, tolerance: 15)
        #expect(zone == .head)
    }

    @Test func matchZone_outsideTolerance_noMatch() {
        let zone = SkierMaskRenderer.matchZone(r: 230, g: 0, b: 0, tolerance: 15)
        #expect(zone == nil)
    }

    @Test func matchZone_zeroTolerance_onlyExactMatch() {
        // Magenta → head with zero tolerance
        let exact = SkierMaskRenderer.matchZone(r: 255, g: 0, b: 255, tolerance: 0)
        #expect(exact == .head)

        let offByOne = SkierMaskRenderer.matchZone(r: 254, g: 0, b: 255, tolerance: 0)
        #expect(offByOne == nil)
    }

    // MARK: - Zone Lookup via Normalized Coordinates

    @Test func zone_centerOfHeadRegion_returnsHead() {
        let data = makeLookupData(centerZone: .head)
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 4, lookupHeight: 4)

        let zone = renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.5))
        #expect(zone == .head)
    }

    @Test func zone_noZoneArea_returnsNil() {
        let data = makeLookupData(centerZone: .head)
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 4, lookupHeight: 4)

        // Top-left corner is no-zone
        let zone = renderer.zone(atNormalized: CGPoint(x: 0.0, y: 0.0))
        #expect(zone == nil)
    }

    @Test func zone_outOfBounds_returnsNil() {
        let data = makeLookupData(centerZone: .head)
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 4, lookupHeight: 4)

        #expect(renderer.zone(atNormalized: CGPoint(x: -0.1, y: 0.5)) == nil)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: -0.1)) == nil)
        #expect(renderer.zone(atNormalized: CGPoint(x: 1.1, y: 0.5)) == nil)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 1.1)) == nil)
    }

    @Test func zone_edgeBoundary_valid() {
        let data = makeLookupData(centerZone: .body)
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 4, lookupHeight: 4)

        // Exactly (1.0, 1.0) clamps to last pixel which is no-zone in test data
        let zone = renderer.zone(atNormalized: CGPoint(x: 1.0, y: 1.0))
        #expect(zone == nil)

        #expect(renderer.zone(atNormalized: CGPoint(x: 0.0, y: 0.0)) == nil)
    }

    @Test func zone_multipleZones_correctMapping() {
        let data = makeMultiZoneLookup()
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 10, lookupHeight: 70)

        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.07)) == .head)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.21)) == .body)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.36)) == .hands)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.50)) == .gear)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.64)) == .pack)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.79)) == .feet)
        #expect(renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.93)) == .backpack)
    }

    // MARK: - Asset Loading (integration)

    @Test func initFromAssetCatalog_loadsSuccessfully() {
        let renderer = SkierMaskRenderer()
        #expect(renderer != nil)
        if let renderer {
            #expect(renderer.zoneMasks.count == 7)
        }
    }

    @Test func zoneMasks_allZonesPresent() {
        guard let renderer = SkierMaskRenderer() else {
            Issue.record("SkierMaskRenderer failed to initialize from asset catalog")
            return
        }
        for zone in BodyZone.allCases {
            #expect(renderer.zoneMasks[zone] != nil, "Missing mask for \(zone)")
        }
    }

    @Test func lookupTable_correctSize() {
        // The pre-baked lookup table should be 256x256 = 65536 bytes
        guard let asset = NSDataAsset(name: "ZoneLookup") else {
            Issue.record("ZoneLookup data asset not found")
            return
        }
        #expect(asset.data.count == 65536)
    }

    // MARK: - Compact lookup edge cases

    @Test func zone_singlePixelLookup_returnsCorrectZone() {
        let data = Data([UInt8(BodyZone.gear.rawValue)])
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 1, lookupHeight: 1)
        let zone = renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.5))
        #expect(zone == .gear)
    }

    @Test func zone_singlePixelNoZone_returnsNil() {
        let data = Data([Self.noZone])
        let renderer = SkierMaskRenderer(lookupData: data, lookupWidth: 1, lookupHeight: 1)
        let zone = renderer.zone(atNormalized: CGPoint(x: 0.5, y: 0.5))
        #expect(zone == nil)
    }
}
