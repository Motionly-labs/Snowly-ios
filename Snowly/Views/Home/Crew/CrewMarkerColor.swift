//
//  CrewMarkerColor.swift
//  Snowly
//
//  Stable marker color assignment by user ID so member and pin colors match.
//

import SwiftUI

enum CrewMarkerColor {
    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .pink
    ]

    static func color(for userId: String) -> Color {
        guard !userId.isEmpty else { return .accent }
        let hash = stableHash64(userId)
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    private static func stableHash64(_ string: String) -> UInt64 {
        // FNV-1a 64-bit hash for deterministic cross-launch mapping.
        let offset: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        var hash = offset
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
