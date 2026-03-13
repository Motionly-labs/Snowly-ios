//
//  GearSummaryBadge.swift
//  Snowly
//
//  Capsule badge used on gear detail screens.
//

import SwiftUI

struct GearSummaryBadge: View {
    private let text: String
    private let systemImage: String
    private let tint: Color

    init(_ text: String, systemImage: String, tint: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .snowlyGlass(in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }
}
