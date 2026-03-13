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

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        switch scale {
        case .full:
            content.background(fullBackground)
        case .compact:
            content.background(compactBackground)
        }
    }

    // In dark mode, white overlays are nearly invisible so the adaptive base shows through cleanly.
    private var isDark: Bool { colorScheme == .dark }

    private var fullBackground: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.xLarge + 4, style: .continuous)
        return shape
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.06 : 0.82),
                            accent.opacity(0.08),
                            accent.opacity(0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accent.opacity(isDark ? 0.22 : 0.16))
                    .frame(width: 140, height: 140)
                    .blur(radius: 24)
                    .offset(x: 36, y: -52)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.white.opacity(isDark ? 0.04 : 0.72))
                    .frame(width: 120, height: 120)
                    .blur(radius: 22)
                    .offset(x: -28, y: 54)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(isDark ? 0.10 : 0.68), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.06), radius: 18, x: 0, y: 10)
    }

    private var compactBackground: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
        return shape
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.05 : 0.72),
                            accent.opacity(isDark ? 0.14 : 0.08),
                            accent.opacity(isDark ? 0.06 : 0.03),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(accent.opacity(isDark ? 0.16 : 0.12))
                    .frame(width: 74, height: 74)
                    .blur(radius: 16)
                    .offset(x: 16, y: -20)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.white.opacity(isDark ? 0.03 : 0.52))
                    .frame(width: 52, height: 52)
                    .blur(radius: 16)
                    .offset(x: -10, y: 18)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(isDark ? 0.10 : 0.55), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(isDark ? 0.18 : 0.04), radius: 8, x: 0, y: 4)
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
