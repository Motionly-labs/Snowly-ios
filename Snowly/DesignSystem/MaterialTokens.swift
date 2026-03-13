//
//  MaterialTokens.swift
//  Snowly
//
//  Single entry point for all floating surface styling.
//
//  iOS 26 introduced `.glassEffect()` — a liquid glass rendering path that is
//  visually distinct from the old Material API (.ultraThinMaterial, .regularMaterial).
//  The system tab bar uses glassEffect automatically; using Material anywhere else
//  produces a mismatched gray-frosted look on light backgrounds.
//
//  Rule: never call `.glassEffect()` or any Material directly in view code.
//  Always use `snowlyGlass(in:)` so the token stays the single source of truth.
//

import SwiftUI

extension View {
    /// iOS 26 liquid glass surface for all floating UI — cards, pills, buttons, and banners.
    /// Matches the system tab bar treatment. Shape defines the glass boundary.
    func snowlyGlass<S: Shape>(in shape: S) -> some View {
        glassEffect(in: shape)
    }
}
