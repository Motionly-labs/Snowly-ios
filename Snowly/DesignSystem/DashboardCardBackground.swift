//
//  DashboardCardBackground.swift
//  Snowly
//
//  Shared glass-style background modifiers for the tracking dashboard cards.
//

import SwiftUI

struct DashboardCardBackgroundModifier: ViewModifier {
    enum Scale { case full, compact }

    let accent: Color
    let scale: Scale

    func body(content: Content) -> some View {
        switch scale {
        case .full:
            content.background(fullBackground)
        case .compact:
            content.background(compactBackground)
        }
    }

    private var fullBackground: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.xLarge + 4, style: .continuous)
        return shape
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            accent.opacity(0.08),
                            ColorTokens.brandWarmAmber.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 140, height: 140)
                    .blur(radius: 24)
                    .offset(x: 36, y: -52)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 120, height: 120)
                    .blur(radius: 22)
                    .offset(x: -28, y: 54)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }

    private var compactBackground: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
        return shape
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.72), accent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func dashboardCardBackground(accent: Color) -> some View {
        modifier(DashboardCardBackgroundModifier(accent: accent, scale: .full))
    }

    func dashboardGridCardBackground(accent: Color = .clear) -> some View {
        modifier(DashboardCardBackgroundModifier(accent: accent, scale: .compact))
    }
}
