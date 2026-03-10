//
//  ResumeTrackingButton.swift
//  Snowly
//
//  Circular material button that returns to active tracking.
//

import SwiftUI

struct ResumeTrackingButton: View {
    let onTap: () -> Void

    private let buttonSize = Spacing.heroButton
    private let ringInset = Spacing.gap

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.42),
                                    ColorTokens.brandGold.opacity(Opacity.moderate),
                                    ColorTokens.brandWarmAmber.opacity(Opacity.muted)
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: buttonSize * 0.56
                            )
                        )
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(Opacity.moderate), lineWidth: 1.4)
                }
                .overlay {
                    // Active session indicator ring inside glass edge
                    Circle()
                        .stroke(ColorTokens.progressArcGradient, lineWidth: 4)
                        .padding(ringInset)
                }
                .overlay {
                    Text(String(localized: "tracking_resume_button_label"))
                        .font(Typography.buttonResume)
                        .foregroundStyle(ColorTokens.textOnBrand)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                        .shadowStyle(.innerGlow)
                }
        }
        .shadowStyle(.brandGlow)
        .buttonStyle(.plain)
        .accessibilityIdentifier("resume_tracking_dashboard_button")
        .accessibilityLabel(String(localized: "tracking_resume_button_label"))
    }
}

#Preview("Resume Tracking Button") {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.26, green: 0.31, blue: 0.35),
                Color(red: 0.15, green: 0.18, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ResumeTrackingButton { }
    }
    .frame(width: 360, height: 640)
}
