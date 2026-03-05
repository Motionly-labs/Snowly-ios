#!/usr/bin/env swift
//
//  generate-zone-assets.swift
//  Snowly
//
//  Standalone script that pre-bakes zone mask PNGs and a compact lookup table
//  from the SkierMask SVG. Run this once after changing the source mask.
//
//  Usage:
//    swift Scripts/generate-zone-assets.swift
//
//  Output (into asset catalog):
//    - 5 zone mask PNGs:  ZoneMask-head.png, ZoneMask-body.png, etc.
//    - 1 lookup binary:   ZoneLookup.bin (256x256, 1 byte per pixel)

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

// MARK: - Configuration

/// Must match BodyZone.rawValue ordering exactly.
enum Zone: UInt8, CaseIterable {
    case head = 0
    case body = 1
    case hands = 2
    case gear = 3
    case pack = 4
    case feet = 5
    case backpack = 6

    var assetSuffix: String {
        switch self {
        case .head: return "head"
        case .body: return "body"
        case .hands: return "hands"
        case .gear: return "gear"
        case .pack: return "pack"
        case .feet: return "feet"
        case .backpack: return "backpack"
        }
    }
}

// Must match SkierMaskRenderer.zoneColors exactly.
// SVG layer → color → zone:
//   Head  → #FF00FF magenta → head
//   Body  → #FF0000 red     → body
//   Arms  → #00FF00 green   → gear
//   Hand  → #FFFF00 yellow  → hands
//   Legs  → #0000FF blue    → pack
//   Foot  → #F7931E orange  → feet
//   Bag   → #8CC63F lime    → backpack
let zoneColors: [(zone: Zone, r: UInt8, g: UInt8, b: UInt8)] = [
    (.head, 0xFF, 0x00, 0xFF),      // magenta — Head layer
    (.body, 0xFF, 0x00, 0x00),      // red     — Body layer
    (.gear, 0x00, 0xFF, 0x00),      // green   — Arms layer
    (.hands, 0xFF, 0xFF, 0x00),     // yellow  — Hand layer
    (.pack, 0x00, 0x00, 0xFF),      // blue    — Legs layer
    (.feet, 0xF7, 0x93, 0x1E),     // orange  — Foot layer
    (.backpack, 0x8C, 0xC6, 0x3F), // lime    — Bag layer
]

let colorTolerance: UInt8 = 15
let renderSize = 1024
let lookupSize = 256
let noZoneMarker: UInt8 = 0xFF

// MARK: - Paths

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let assetsDir = projectRoot
    .appendingPathComponent("Snowly")
    .appendingPathComponent("Assets.xcassets")

let maskImagePath = assetsDir
    .appendingPathComponent("SkierMask.imageset")
    .appendingPathComponent("skier-mask.svg")

// MARK: - Pixel helpers (same logic as app's SkierMaskRenderer)

func channelMatches(_ value: UInt8, _ target: UInt8, tolerance: UInt8) -> Bool {
    let diff = value > target ? value - target : target - value
    return diff <= tolerance
}

func matchZone(r: UInt8, g: UInt8, b: UInt8) -> Zone? {
    for (zone, tr, tg, tb) in zoneColors {
        if channelMatches(r, tr, tolerance: colorTolerance),
           channelMatches(g, tg, tolerance: colorTolerance),
           channelMatches(b, tb, tolerance: colorTolerance)
        {
            return zone
        }
    }
    return nil
}

// MARK: - Load and decode SVG

func loadSVG(at path: URL, size: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
    guard let nsImage = NSImage(contentsOf: path) else {
        print("ERROR: Cannot load image from \(path.path)")
        return nil
    }

    let targetSize = NSSize(width: size, height: size)

    // Rasterize the SVG to a bitmap at the target size
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    nsImage.draw(in: NSRect(origin: .zero, size: targetSize),
                 from: NSRect(origin: .zero, size: nsImage.size),
                 operation: .copy,
                 fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = bitmapRep.cgImage else {
        print("ERROR: Cannot get CGImage from bitmap")
        return nil
    }

    let w = cgImage.width
    let h = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = w * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: w * h * bytesPerPixel)

    guard let context = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("ERROR: Cannot create CGContext")
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (pixels, w, h)
}

// MARK: - Generate zone mask PNG

func generateZoneMask(
    from pixels: [UInt8],
    width: Int,
    height: Int,
    targetR: UInt8,
    targetG: UInt8,
    targetB: UInt8
) -> Data? {
    let pixelCount = width * height
    var maskData = [UInt8](repeating: 0, count: pixelCount * 4)

    for i in 0..<pixelCount {
        let srcOffset = i * 4
        let r = pixels[srcOffset]
        let g = pixels[srcOffset + 1]
        let b = pixels[srcOffset + 2]
        let a = pixels[srcOffset + 3]

        if a > 128,
           channelMatches(r, targetR, tolerance: colorTolerance),
           channelMatches(g, targetG, tolerance: colorTolerance),
           channelMatches(b, targetB, tolerance: colorTolerance)
        {
            let dstOffset = i * 4
            maskData[dstOffset] = 255
            maskData[dstOffset + 1] = 255
            maskData[dstOffset + 2] = 255
            maskData[dstOffset + 3] = 255
        }
    }

    let bytesPerRow = width * 4
    guard let context = CGContext(
        data: &maskData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
        let cgImage = context.makeImage()
    else {
        return nil
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    return bitmapRep.representation(using: .png, properties: [:])
}

// MARK: - Generate compact lookup table

func generateLookupTable(
    from pixels: [UInt8],
    sourceWidth: Int,
    sourceHeight: Int,
    outputSize: Int
) -> Data {
    let blockW = sourceWidth / outputSize
    let blockH = sourceHeight / outputSize
    var lookup = Data(count: outputSize * outputSize)

    for outY in 0..<outputSize {
        for outX in 0..<outputSize {
            // Majority-vote within the block
            var votes = [UInt8](repeating: 0, count: Zone.allCases.count)
            var total = 0

            let srcYStart = outY * blockH
            let srcXStart = outX * blockW

            for dy in 0..<blockH {
                for dx in 0..<blockW {
                    let srcX = srcXStart + dx
                    let srcY = srcYStart + dy
                    guard srcX < sourceWidth, srcY < sourceHeight else { continue }

                    let offset = (srcY * sourceWidth + srcX) * 4
                    let r = pixels[offset]
                    let g = pixels[offset + 1]
                    let b = pixels[offset + 2]
                    let a = pixels[offset + 3]

                    guard a > 128 else { continue }

                    if let zone = matchZone(r: r, g: g, b: b) {
                        votes[Int(zone.rawValue)] += 1
                        total += 1
                    }
                }
            }

            let index = outY * outputSize + outX
            if total == 0 {
                lookup[index] = noZoneMarker
            } else {
                let maxVote = votes.max()!
                let winner = votes.firstIndex(of: maxVote)!
                lookup[index] = UInt8(winner)
            }
        }
    }

    return lookup
}

// MARK: - Asset catalog helpers

func writeImageset(name: String, pngData: Data, at assetsBase: URL) throws {
    let imagesetDir = assetsBase.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: imagesetDir, withIntermediateDirectories: true)

    let pngFile = "\(name).png"
    try pngData.write(to: imagesetDir.appendingPathComponent(pngFile))

    let contents: [String: Any] = [
        "images": [
            ["filename": pngFile, "idiom": "universal"],
        ],
        "info": ["author": "xcode", "version": 1],
    ]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: imagesetDir.appendingPathComponent("Contents.json"))
}

func writeDataset(name: String, binaryData: Data, at assetsBase: URL) throws {
    let datasetDir = assetsBase.appendingPathComponent("\(name).dataset")
    try FileManager.default.createDirectory(at: datasetDir, withIntermediateDirectories: true)

    let binFile = "\(name).bin"
    try binaryData.write(to: datasetDir.appendingPathComponent(binFile))

    let contents: [String: Any] = [
        "data": [
            ["filename": binFile, "idiom": "universal"],
        ],
        "info": ["author": "xcode", "version": 1],
    ]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: datasetDir.appendingPathComponent("Contents.json"))
}

// MARK: - Main

func main() throws {
    print("Loading mask SVG from: \(maskImagePath.path)")

    guard let (pixels, width, height) = loadSVG(at: maskImagePath, size: renderSize) else {
        print("FAILED: Could not load or decode SkierMask SVG")
        exit(1)
    }

    print("Decoded mask: \(width)x\(height) (\(pixels.count) bytes)")

    // Generate zone mask PNGs
    for (zone, r, g, b) in zoneColors {
        let name = "ZoneMask-\(zone.assetSuffix)"
        guard let pngData = generateZoneMask(
            from: pixels, width: width, height: height,
            targetR: r, targetG: g, targetB: b
        ) else {
            print("FAILED: Could not generate mask for \(zone.assetSuffix)")
            exit(1)
        }
        try writeImageset(name: name, pngData: pngData, at: assetsDir)
        print("  ✓ \(name).imageset (\(pngData.count) bytes)")
    }

    // Generate compact lookup table
    let lookupData = generateLookupTable(
        from: pixels,
        sourceWidth: width,
        sourceHeight: height,
        outputSize: lookupSize
    )
    try writeDataset(name: "ZoneLookup", binaryData: lookupData, at: assetsDir)
    print("  ✓ ZoneLookup.dataset (\(lookupData.count) bytes)")

    // Validation
    var zonePixelCounts = [UInt8: Int]()
    for byte in lookupData {
        zonePixelCounts[byte, default: 0] += 1
    }
    print("\nLookup table validation:")
    for zone in Zone.allCases {
        let count = zonePixelCounts[zone.rawValue] ?? 0
        print("  \(zone.assetSuffix): \(count) cells")
    }
    let noZone = zonePixelCounts[noZoneMarker] ?? 0
    print("  (no zone): \(noZone) cells")
    print("  total: \(lookupData.count) cells")

    print("\nDone! Assets written to: \(assetsDir.path)")
}

do {
    try main()
} catch {
    print("ERROR: \(error)")
    exit(1)
}
